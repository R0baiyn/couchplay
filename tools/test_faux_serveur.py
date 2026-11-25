"""Vérifie les modes du faux serveur : python -I tools/test_faux_serveur.py"""

import gzip
import http.client
import importlib.util
import json
import re
import shutil
import subprocess
import tempfile
import threading
import time
from datetime import datetime
from pathlib import Path
from xml.etree import ElementTree

ICI = Path(__file__).resolve().parent
FIXTURES = ICI.parent / 'test' / 'fixtures'
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


def attendre(condition, message):
    """Attend un effet du côté serveur (autre fil), 5 s au plus."""
    limite = time.monotonic() + 5
    while not condition():
        assert time.monotonic() < limite, message
        time.sleep(0.05)


def direct_listes(port):
    _, corps = api(port, 'demo', '&action=get_live_categories')
    categories = {c['category_id']: c['category_name'] for c in json.loads(corps)}
    assert categories['104'] == 'FRANCE HD' and '1346' not in categories
    _, corps = api(port, 'demo', '&action=get_live_streams')
    chaines = json.loads(corps)
    # Les types relevés sur le vrai serveur sont gardés.
    assert {c['stream_type'] for c in chaines} == {'live', 'radio_streams'}
    assert {type(c['tv_archive_duration']) for c in chaines} == {int, str}
    assert any(c['epg_channel_id'] is None for c in chaines)
    assert any(c['stream_icon'] == '' for c in chaines)
    _, corps = api(port, 'demo', '&action=get_live_streams&category_id=105')
    assert {c['category_id'] for c in json.loads(corps)} == {'105'}

    faux.charger(FIXTURES, 1)
    _, corps = api(port, 'demo', '&action=get_live_streams')
    ids = [c['category_id'] for c in json.loads(corps)]
    assert len(ids) == len(set(ids)), '--max-par-categorie vaut pour les chaînes'
    faux.charger(FIXTURES)


def lire_guide(port, utilisateur):
    r, c = get(port, f'/xmltv.php?username={utilisateur}&password=x')  # pre-push:allow : fictif
    corps = r.read()
    c.close()
    assert r.status == 200 and r.getheader('Content-Encoding') == 'gzip'
    texte = gzip.decompress(corps).decode('utf-8')
    assert '<!DOCTYPE tv SYSTEM "xmltv.dtd">' in texte
    return texte, ElementTree.fromstring(texte.encode('utf-8'))


def instant(date):
    assert re.fullmatch(r'\d{14} \+0100', date), date
    return datetime.strptime(date, '%Y%m%d%H%M%S %z').timestamp()


def direct_guide(port):
    texte, racine = lire_guide(port, 'demo')
    annoncees = [c.get('id') for c in racine.findall('channel')]
    assert len(annoncees) == len(set(annoncees)), 'une seule fois par id'
    assert {'chaine1.test', 'sansprogramme.test', '12345'} <= set(annoncees)
    assert 'absente.test' not in annoncees
    programmes = racine.findall('programme')
    assert {p.get('channel') for p in programmes} == set(annoncees) - {
        'sansprogramme.test'
    }
    maintenant = time.time()
    suite = [
        (instant(p.get('start')), instant(p.get('stop')))
        for p in programmes
        if p.get('channel') == 'chaine1.test'
    ]
    assert any(d <= maintenant < f for d, f in suite), 'un programme en cours'
    assert all(30 * 60 <= f - d <= 90 * 60 for d, f in suite)
    assert all(a[1] == b[0] for a, b in zip(suite, suite[1:])), 'sans trou'
    assert suite[0][0] <= maintenant - 3 * 3600
    assert suite[-1][1] >= maintenant + 3 * 86400
    for entite in ('&amp;', '&apos;', '&quot;'):
        assert entite in texte, entite
    assert any('é' in p.findtext('title') for p in programmes)
    assert any(p.find('desc') is None for p in programmes)
    assert any(p.find('desc') is not None for p in programmes)


def direct_sans_guide(port):
    _, racine = lire_guide(port, 'sansguide')
    assert list(racine) == []
    _, corps = api(port, 'sansguide', '&action=get_live_streams')
    assert json.loads(corps), 'les chaînes restent servies'


def direct_flux(port, mire):
    r, c = get(port, '/live/demo/x/9001.ts')  # pre-push:allow : fictif
    assert r.status == 200 and r.getheader('Content-Length') is None
    assert r.getheader('Content-Type') == 'video/mp2t'
    contenu = mire.read_bytes()
    assert r.read(3 * len(contenu)) == contenu * 3, 'la mire tourne en boucle'
    r.close()
    c.close()
    attendre(lambda: faux.flux_ouverts['demo'] == 0, 'fil du direct libéré')

    # Au débit demandé, passé les secondes envoyées d'avance.
    faux.Requete.debit_direct = 64
    r, c = get(port, '/live/demo/x/9001.ts')  # pre-push:allow : fictif
    debut = time.monotonic()  # Après la connexion, qui peut prendre 2 s.
    octets = 64 * 1024 * (faux.AVANCE_DIRECT + 1)
    assert len(r.read(octets)) == octets
    assert time.monotonic() - debut >= 0.4, '1 s de direct de plus que l avance'
    r.close()
    c.close()


def direct_coupe(port):
    assert faux.Requete.duree_coupe == 15
    faux.Requete.duree_coupe = 1
    faux.Requete.debit_direct = 256
    r, c = get(port, '/live/coupe/x/9001.ts')  # pre-push:allow : fictif
    debut = time.monotonic()
    r.read()  # Se termine : le serveur ferme.
    assert 0.8 <= time.monotonic() - debut < 5
    c.close()
    faux.Requete.duree_coupe = 15


def direct_plein(port):
    faux.Requete.debit_direct = 256
    premier, c1 = get(port, '/live/plein/x/9001.ts')  # pre-push:allow : fictif
    assert premier.status == 200
    second, c2 = get(port, '/live/plein/x/9002.ts')  # pre-push:allow : fictif
    assert second.status == 403
    premier.close()
    c1.close()
    c2.close()


def direct_deuxieme_connexion(port):
    assert faux.Requete.delai_coupure == 14
    faux.Requete.delai_coupure = 1
    faux.Requete.debit_direct = 256
    ancien, c1 = get(port, '/live/zap/x/9001.ts')  # pre-push:allow : fictif
    recent, c2 = get(port, '/live/zap/x/9002.ts')  # pre-push:allow : fictif
    debut = time.monotonic()
    assert recent.status == 200, 'la 2e connexion est acceptée'
    ancien.read()
    assert 0.8 <= time.monotonic() - debut < 5, 'l ancienne coupée après le délai'
    assert len(recent.read(700_000)) == 700_000, 'la nouvelle continue'
    recent.close()
    c1.close()
    c2.close()
    faux.Requete.delai_coupure = 14


def direct_raccord(port, dossier):
    """D'une boucle à l'autre, les horodatages doivent continuer."""
    ffmpeg, ffprobe = shutil.which('ffmpeg'), shutil.which('ffprobe')
    if not ffmpeg or not ffprobe:
        print('ffmpeg absent : raccord de boucle non vérifié')
        return
    mire = Path(dossier) / 'court.ts'
    subprocess.run(
        [ffmpeg, '-v', 'error', '-f', 'lavfi', '-i', 'testsrc=size=160x120',
         '-t', '2', '-c:v', 'mpeg2video', '-f', 'mpegts', str(mire)],
        check=True,
    )
    faux.Requete.direct = mire
    faux.Requete.debit_direct = 100_000
    r, c = get(port, '/live/demo/x/9001.ts')  # pre-push:allow : fictif
    recu = r.read(3 * mire.stat().st_size)
    r.close()
    c.close()
    sortie = subprocess.run(
        [ffprobe, '-v', 'error', '-show_entries', 'packet=dts_time',
         '-of', 'default=nk=1:nw=1', '-'],
        input=recu, capture_output=True, check=True,
    ).stdout
    dts = [float(d) for d in sortie.split()]
    assert dts[-1] - dts[0] > 4, 'au moins deux boucles'
    assert all(a < b for a, b in zip(dts, dts[1:])), 'horodatages continus'


def principal():
    entrees = [{'category_id': c, 'n': i} for i, c in enumerate('aabaab')]
    assert faux.premiers_par_categorie(entrees, 2) == [
        entrees[0], entrees[1], entrees[2], entrees[5]
    ]
    assert faux.premiers_par_categorie(entrees, 0) == []

    with tempfile.TemporaryDirectory(ignore_cleanup_errors=True) as dossier:
        # Assez gros pour qu'un flux non lu reste ouvert côté serveur.
        video = Path(dossier) / 'mire.mkv'
        video.write_bytes(bytes(range(256)) * 80_000)
        mire = Path(dossier) / 'mire.ts'
        mire.write_bytes(bytes(range(251)) * 400)
        faux.charger(FIXTURES)
        faux.Requete.video = video
        faux.Requete.video_hd = video
        faux.Requete.direct = mire
        faux.Requete.debit_direct = 100_000
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
        r, corps = api(port, 'demo', '&action=get_action_inconnue')
        assert corps == b'[]'

        direct_listes(port)
        direct_guide(port)
        direct_sans_guide(port)
        direct_flux(port, mire)
        direct_coupe(port)
        direct_plein(port)
        direct_deuxieme_connexion(port)
        direct_raccord(port, dossier)

        entetes = {'Range': 'bytes=10-19'}
        r, c = get(port, '/movie/demo/x/1.mkv', entetes)  # pre-push:allow : fictif
        assert r.status == 206 and r.read() == bytes(range(10, 20))
        assert r.getheader('Content-Range') == f'bytes 10-19/{video.stat().st_size}'
        c.close()

        taille = video.stat().st_size
        r, c = get(port, '/movie/coupe/x/1.mkv')  # pre-push:allow : fictif
        assert r.status == 200 and r.getheader('Content-Length') == str(taille)
        try:
            r.read()
            raise AssertionError('le flux sans Range doit être coupé')
        except http.client.IncompleteRead as e:
            recu = e.partial
        c.close()
        assert recu == video.read_bytes()[: taille // 2], len(recu)
        r, c = get(port, '/movie/coupe/x/1.mkv',  # pre-push:allow : fictif
                   {'Range': f'bytes={len(recu)}-'})
        assert r.status == 206
        assert recu + r.read() == video.read_bytes(), 'la reprise aboutit'
        c.close()

        faux.Requete.debit = 50
        debut = time.monotonic()
        r, c = get(port, '/movie/demo/x/1.mkv',  # pre-push:allow : fictif
                   {'Range': 'bytes=0-25599'})
        assert len(r.read()) == 25600
        assert time.monotonic() - debut >= 0.45, '25 Kio à 50 Kio/s'
        c.close()
        faux.Requete.debit = None

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
