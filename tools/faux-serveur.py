"""Faux serveur de catalogue, pour essayer l'app sans solliciter le vrai.

Lancement : python -I tools/faux-serveur.py [--port 8080] [--donnees DIR]
            [--video FICHIER] [--video-hd FICHIER]

Dans l'app : hôte http://localhost:8080 (PC) ou http://<IP du PC>:8080
(téléphone), mot de passe quelconque. Le nom d'utilisateur choisit le
comportement :
  refuse   identifiants refusés (auth 0)
  expire   abonnement expiré
  lent     chaque réponse attend 5 s
  muet     chaque réponse attend 40 s, plus que le délai de l'app
  html     page HTML à la place du JSON (pare-feu, page d'erreur)
  plein    max_connections 1 appliqué : un 2e flux simultané reçoit un 403
  403, 429, 500…  ce code HTTP à chaque requête
  autre    fonctionnement normal

Le catalogue vient de probe/ (vraies réponses enregistrées, hors git) ou, à
défaut, de test/fixtures/. Les listes respectent category_id, comme le vrai
serveur. Les films dont le nom porte SD ou HD jouent la vidéo --video-hd
(probe/mire-720p.mkv par défaut), les autres films et tous les épisodes la
vidéo --video : la résolution affichée par le lecteur montre quelle version
est lue.
"""

import argparse
import json
import mimetypes
import re
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, unquote, urlsplit

RACINE = Path(__file__).resolve().parent.parent
FICHIERS = {
    'get_vod_categories': 'vod_categories.json',
    'get_vod_streams': 'vod_streams.json',
    'get_series_categories': 'series_categories.json',
    'get_series': 'series.json',
}
HTML = b'<html><body><h1>503 Service Unavailable</h1></body></html>'
FLUX = re.compile(r'^/(movie|series)/([^/]+)/([^/]+)/([^/.]+)[^/]*$')
QUALITE_HD = re.compile(r'\b(SD|HD)\b')
PLAGE = re.compile(r'^bytes=(\d*)-(\d*)$')

flux_ouverts: dict[str, int] = {}
verrou = threading.Lock()


def infos_compte(utilisateur: str, mot_de_passe: str) -> dict:
    if utilisateur == 'refuse':
        return {'user_info': {'auth': 0}}
    maintenant = int(time.time())
    expire = utilisateur == 'expire'
    with verrou:
        actifs = flux_ouverts.get(utilisateur, 0)
    # Mêmes champs et mêmes types (nombres en texte) que le vrai serveur.
    return {
        'user_info': {
            'username': utilisateur,
            'password': mot_de_passe,
            'message': '',
            'auth': 1,
            'status': 'Expired' if expire else 'Active',
            'exp_date': str(maintenant + (-86400 if expire else 365 * 86400)),
            'is_trial': '0',
            'active_cons': str(actifs),
            'created_at': str(maintenant - 365 * 86400),
            'max_connections': '1',
            'allowed_output_formats': ['ts', 'hls'],
        },
        'server_info': {
            'url': 'localhost',
            'port': '8080',
            'server_protocol': 'http',
            'timezone': 'Europe/Paris',
            'timestamp_now': maintenant,
            'time_now': time.strftime('%Y-%m-%d %H:%M:%S'),
        },
    }


class Requete(BaseHTTPRequestHandler):
    donnees: Path
    video: Path | None
    video_hd: Path | None
    # Listes chargées une fois : action -> entrées, et nom de chaque film.
    listes: dict[str, list] = {}
    noms_films: dict[str, str] = {}

    def do_GET(self):
        url = urlsplit(self.path)
        params = {k: v[0] for k, v in parse_qs(url.query).items()}
        flux = FLUX.match(url.path)
        if url.path == '/player_api.php':
            utilisateur = params.get('username', '')
        elif flux:
            utilisateur = unquote(flux.group(2))
        else:
            return self.repondre(404, b'')

        if utilisateur == 'lent':
            time.sleep(5)
        elif utilisateur == 'muet':
            time.sleep(40)
        if utilisateur.isdigit() and len(utilisateur) == 3:
            return self.repondre(int(utilisateur), b'')
        if utilisateur == 'html':
            return self.repondre(200, HTML, 'text/html')

        if flux:
            return self.envoyer_video(utilisateur, flux.group(1), flux.group(4))
        return self.api(params, utilisateur)

    def api(self, params: dict, utilisateur: str):
        action = params.get('action')
        if utilisateur == 'refuse' or not action:
            corps = infos_compte(utilisateur, params.get('password', ''))
            return self.repondre(200, json.dumps(corps).encode())
        if action in ('get_vod_info', 'get_series_info'):
            nom = action.removeprefix('get_')
            cle = params.get('vod_id' if nom == 'vod_info' else 'series_id', '')
            # Une réponse enregistrée pour cet id si elle existe, sinon la
            # même pour tous : le titre ne correspondra pas, la structure si.
            # Chiffres seuls : l'id finit dans un chemin de fichier.
            fichier = self.donnees / f'{nom}_{cle}.json'
            if not cle.isdigit() or not fichier.is_file():
                fichier = self.donnees / f'{nom}.json'
        elif action in self.listes:
            entrees = self.listes[action]
            categorie = params.get('category_id')
            if categorie is not None:
                entrees = [
                    e for e in entrees if str(e.get('category_id')) == categorie
                ]
            return self.repondre(200, json.dumps(entrees).encode())
        elif action in FICHIERS:
            fichier = self.donnees / FICHIERS[action]
        else:
            # Action inconnue : les vrais serveurs renvoient une liste vide.
            return self.repondre(200, b'[]')
        self.repondre(200, fichier.read_bytes())

    def envoyer_video(self, utilisateur: str, type_flux: str, ident: str):
        video = self.video
        nom = self.noms_films.get(ident, '') if type_flux == 'movie' else ''
        if self.video_hd is not None and QUALITE_HD.search(nom):
            video = self.video_hd
        if video is None:
            return self.repondre(404, b'')
        with verrou:
            actifs = flux_ouverts.get(utilisateur, 0)
            refuse = utilisateur == 'plein' and actifs >= 1
            if not refuse:
                flux_ouverts[utilisateur] = actifs + 1
        if refuse:
            return self.repondre(403, b'')
        try:
            self.envoyer_plage(video)
        except ConnectionError:
            pass  # Le lecteur a fermé ou sauté ailleurs dans la vidéo.
        finally:
            with verrou:
                flux_ouverts[utilisateur] -= 1

    def envoyer_plage(self, video: Path):
        taille = video.stat().st_size
        debut, fin = 0, taille - 1
        plage = PLAGE.match(self.headers.get('Range', ''))
        if plage and plage.group(1):
            debut = int(plage.group(1))
            if plage.group(2):
                fin = min(int(plage.group(2)), fin)
        elif plage and plage.group(2):
            debut = max(taille - int(plage.group(2)), 0)
        if debut > fin:
            self.send_response(416)
            self.send_header('Content-Range', f'bytes */{taille}')
            self.send_header('Content-Length', '0')
            return self.end_headers()

        self.send_response(206 if plage else 200)
        type_mime = mimetypes.guess_type(video.name)[0]
        self.send_header('Content-Type', type_mime or 'video/x-matroska')
        self.send_header('Accept-Ranges', 'bytes')
        self.send_header('Content-Length', str(fin - debut + 1))
        if plage:
            self.send_header('Content-Range', f'bytes {debut}-{fin}/{taille}')
        self.end_headers()
        with video.open('rb') as f:
            f.seek(debut)
            reste = fin - debut + 1
            while reste > 0:
                bloc = f.read(min(reste, 1 << 16))
                if not bloc:
                    break
                self.wfile.write(bloc)
                reste -= len(bloc)

    def repondre(self, code: int, corps: bytes, type_mime='application/json'):
        self.send_response(code)
        self.send_header('Content-Type', type_mime)
        self.send_header('Content-Length', str(len(corps)))
        self.end_headers()
        self.wfile.write(corps)


def principal():
    sondes = RACINE / 'probe'
    arguments = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    arguments.add_argument('--port', type=int, default=8080)
    arguments.add_argument(
        '--donnees',
        type=Path,
        default=sondes
        if (sondes / 'vod_streams.json').is_file()
        else RACINE / 'test' / 'fixtures',
    )
    arguments.add_argument(
        '--video',
        type=Path,
        default=sondes / 'mire.mkv' if (sondes / 'mire.mkv').is_file() else None,
    )
    arguments.add_argument(
        '--video-hd',
        type=Path,
        default=sondes / 'mire-720p.mkv'
        if (sondes / 'mire-720p.mkv').is_file()
        else None,
    )
    a = arguments.parse_args()
    Requete.donnees = a.donnees
    Requete.video = a.video
    Requete.video_hd = a.video_hd
    for action in ('get_vod_streams', 'get_series'):
        fichier = a.donnees / FICHIERS[action]
        Requete.listes[action] = json.loads(fichier.read_text(encoding='utf-8'))
    Requete.noms_films = {
        str(f.get('stream_id')): str(f.get('name') or '')
        for f in Requete.listes['get_vod_streams']
    }
    serveur = ThreadingHTTPServer(('0.0.0.0', a.port), Requete)
    print(f'Catalogue : {a.donnees}')
    print(f'Vidéo : {a.video or "aucune, les flux répondent 404"}')
    print(f'Vidéo des films SD et HD : {a.video_hd or "la même"}')
    print(f'Écoute sur http://localhost:{a.port} (Ctrl+C pour arrêter)')
    try:
        serveur.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == '__main__':
    principal()
