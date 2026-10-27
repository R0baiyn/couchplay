"""Vérifie les modes du faux serveur : python -I tools/test_faux_serveur.py"""

import http.client
import importlib.util
import json
import tempfile
import threading
from pathlib import Path

ICI = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('faux', ICI / 'faux-serveur.py')
faux = importlib.util.module_from_spec(spec)
spec.loader.exec_module(faux)


def get(port, chemin, entetes={}):
    connexion = http.client.HTTPConnection('localhost', port, timeout=10)
    connexion.request('GET', chemin, headers=entetes)
    reponse = connexion.getresponse()
    return reponse, connexion


def api(port, utilisateur, action=''):
    reponse, connexion = get(
        port, f'/player_api.php?username={utilisateur}&password=x{action}'  # pre-push:allow : fictif
    )
    corps = reponse.read()
    connexion.close()
    return reponse, corps


def principal():
    with tempfile.TemporaryDirectory(ignore_cleanup_errors=True) as dossier:
        # Assez gros pour qu'un flux non lu reste ouvert côté serveur.
        video = Path(dossier) / 'mire.mkv'
        video.write_bytes(bytes(range(256)) * 80_000)
        faux.Requete.donnees = ICI.parent / 'test' / 'fixtures'
        faux.Requete.video = video
        serveur = faux.ThreadingHTTPServer(('localhost', 0), faux.Requete)
        threading.Thread(target=serveur.serve_forever, daemon=True).start()
        port = serveur.server_address[1]

        r, corps = api(port, 'demo')
        infos = json.loads(corps)['user_info']
        assert (infos['auth'], infos['status']) == (1, 'Active'), infos
        r, corps = api(port, 'refuse', '&action=get_vod_streams')
        assert json.loads(corps)['user_info']['auth'] == 0
        r, corps = api(port, 'expire')
        assert json.loads(corps)['user_info']['status'] == 'Expired'
        r, _ = api(port, '429')
        assert r.status == 429
        r, corps = api(port, 'html', '&action=get_vod_streams')
        assert r.status == 200 and corps.startswith(b'<html>')

        r, corps = api(port, 'demo', '&action=get_vod_streams')
        assert isinstance(json.loads(corps), list)
        r, corps = api(port, 'demo', '&action=get_vod_info&vod_id=../account')
        assert 'movie_data' in json.loads(corps), 'id hors chiffres refusé'
        r, corps = api(port, 'demo', '&action=get_live_streams')
        assert corps == b'[]'

        entetes = {'Range': 'bytes=10-19'}
        r, c = get(port, '/movie/demo/x/1.mkv', entetes)  # pre-push:allow : fictif
        assert r.status == 206 and r.read() == bytes(range(10, 20))
        assert r.getheader('Content-Range') == f'bytes 10-19/{video.stat().st_size}'
        c.close()

        premier, c1 = get(port, '/series/plein/x/1.mkv')  # pre-push:allow : fictif
        assert premier.status == 200
        second, c2 = get(port, '/series/plein/x/2.mkv')  # pre-push:allow : fictif
        assert second.status == 403, 'un 2e flux simultané est refusé'
        c1.close()
        c2.close()
        # Le fil du 1er flux peut tenir la vidéo ouverte encore un instant.
        serveur.shutdown()
    print('Faux serveur : tout est bon')


if __name__ == '__main__':
    principal()
