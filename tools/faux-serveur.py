"""Faux serveur de catalogue, pour essayer l'app sans solliciter le vrai.

Lancement : python -I tools/faux-serveur.py [--port 8080] [--donnees DIR]
            [--video FICHIER] [--video-hd FICHIER] [--max-par-categorie N]
            [--debit KIO_PAR_S] [--direct FICHIER] [--debit-direct KIO_PAR_S]
            [--delai-coupure S] [--arret-fin-entree]

Dans l'app : hôte http://localhost:8080 (PC) ou http://<IP du PC>:8080
(téléphone), mot de passe quelconque. Le nom d'utilisateur choisit le
comportement :
  refuse   identifiants refusés (auth 0)
  expire   abonnement expiré
  lent     chaque réponse attend 5 s
  muet     chaque réponse attend 40 s, plus que le délai de l'app
  html     page HTML à la place du JSON (pare-feu, page d'erreur)
  plein    max_connections 1 appliqué : un 2e flux simultané reçoit un 403
  coupe    un film ou épisode demandé sans Range est coupé au milieu du
           fichier ; une requête avec Range (reprise) aboutit. Un flux du
           direct est coupé au bout de 15 s
  sansguide  guide des programmes vide
  403, 429, 500…  ce code HTTP à chaque requête
  autre    fonctionnement normal

Le catalogue vient de probe/ (vraies réponses enregistrées, hors git) ou, à
défaut, de test/fixtures/. Les listes respectent category_id, comme le vrai
serveur. Les films dont le nom porte SD ou HD jouent la vidéo --video-hd
(probe/mire-720p.mkv par défaut), les autres films et tous les épisodes la
vidéo --video : la résolution affichée par le lecteur montre quelle version
est lue. --debit bride l'envoi des vidéos (Kio/s), pour voir avancer un
téléchargement.

Direct : /live/U/P/<id>.ts envoie la mire --direct (probe/mire-720p.ts par
défaut) en boucle (par ffmpeg s'il est là, pour un raccord sans gel), sans fin
ni Content-Length, à --debit-direct (celui de la mire par défaut). Comme le
vrai serveur, un 2e flux du même compte est accepté et le plus ancien est
coupé --delai-coupure secondes plus tard (14 par défaut).
Le guide (xmltv.php, gzip) est calculé autour de l'heure courante pour les
chaînes servies ; l'id « absente.test » n'y figure pas et
« sansprogramme.test » y figure sans programme.
--arret-fin-entree arrête le serveur quand son entrée standard se ferme : le
banc des parcours meurt sans l'arrêter, le port est quand même libéré.
"""

import argparse
import gzip
import json
import mimetypes
import os
import re
import shutil
import subprocess
import threading
import time
from contextlib import closing
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, unquote, urlsplit
from xml.sax.saxutils import escape

RACINE = Path(__file__).resolve().parent.parent
FICHIERS = {
    'get_vod_categories': 'vod_categories.json',
    'get_vod_streams': 'vod_streams.json',
    'get_series_categories': 'series_categories.json',
    'get_series': 'series.json',
    'get_live_categories': 'live_categories.json',
    'get_live_streams': 'live_streams.json',
}
HTML = b'<html><body><h1>503 Service Unavailable</h1></body></html>'
FLUX = re.compile(r'^/(movie|series|live)/([^/]+)/([^/]+)/([^/.]+)[^/]*$')
QUALITE_HD = re.compile(r'\b(SD|HD)\b')
PLAGE = re.compile(r'^bytes=(\d*)-(\d*)$')

# Secondes de direct envoyées d'un coup à l'ouverture, pour démarrer vite (à 2,
# mpv gelait 1 s vers la 5e seconde de la mire).
AVANCE_DIRECT = 4
# Guide : durées (minutes) répétées sans fin depuis 1970, pour que les mêmes
# programmes reviennent à chaque requête.
DUREES = (30, 60, 45, 90, 75)
TITRES = (
    'Journal & météo',
    "L'été indien",
    'Le "grand" débat',
    'Cinéma de minuit',
    'Découverte',
    'Sport : le résumé',
    'Série à suivre',
)

flux_ouverts: dict[str, int] = {}
# Flux du direct ouverts par compte ; 'fin' : instant de la coupure prévue.
directs: dict[str, list[dict]] = {}
verrou = threading.Lock()


def blocs_direct(mire: Path):
    """La mire sans fin. ffmpeg garde des horodatages continus d'une boucle à
    l'autre (sinon l'image gèle près d'une seconde à chaque raccord) ; sans
    lui, ou si le fichier n'est pas un .ts, les octets sont répétés."""
    ffmpeg = shutil.which('ffmpeg')
    with mire.open('rb') as f:
        ts = f.read(1) == b'\x47' and mire.stat().st_size % 188 == 0
    if ffmpeg and ts:
        commande = [ffmpeg, '-v', 'error', '-stream_loop', '-1', '-i',
                    str(mire), '-c', 'copy', '-f', 'mpegts', 'pipe:1']
        with subprocess.Popen(
            commande,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            # Sans console (banc d'intégration), pas de fenêtre par flux.
            creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0),
        ) as processus:
            try:
                while bloc := processus.stdout.read(1 << 15):
                    yield bloc
            finally:
                processus.kill()
    else:
        while True:
            with mire.open('rb') as f:
                while bloc := f.read(1 << 15):
                    yield bloc


def guide(chaines: list, maintenant: int) -> str:
    """Guide XML des chaînes, de maintenant − 3 h à maintenant + 3 jours."""
    par_id: dict[str, dict] = {}
    for chaine in chaines:
        ident = chaine.get('epg_channel_id')
        if ident and str(ident) != 'absente.test':
            par_id.setdefault(str(ident), chaine)

    def x(valeur) -> str:
        return escape(str(valeur), {"'": '&apos;', '"': '&quot;'})

    def date(instant: int) -> str:
        return time.strftime('%Y%m%d%H%M%S +0100', time.gmtime(instant + 3600))

    cycle = sum(DUREES) * 60
    debut, fin = maintenant - 3 * 3600, maintenant + 3 * 86400
    annonces, programmes = [], []
    for ident, chaine in par_id.items():
        icone = chaine.get('stream_icon')
        annonces.append(
            f'<channel id="{x(ident)}">'
            f'<display-name>{x(chaine.get("name") or ident)}</display-name>'
            + (f'<icon src="{x(icone)}" />' if icone else '')
            + '</channel>'
        )
        if ident == 'sansprogramme.test':
            continue
        # Décale les titres et les horaires d'une chaîne à l'autre.
        rang = sum(ident.encode())
        t = (debut // cycle - 1) * cycle + rang % 12 * 300
        n = t // cycle * len(DUREES)
        while t < fin:
            stop = t + DUREES[n % len(DUREES)] * 60
            if stop > debut:
                titre = x(TITRES[(n + rang) % len(TITRES)])
                desc = (
                    f'<desc>Résumé de « {titre} ».</desc>' if n % 4 else ''
                )
                programmes.append(
                    f'<programme start="{date(t)}" stop="{date(stop)}" '
                    f'channel="{x(ident)}"><title>{titre}</title>{desc}'
                    '</programme>'
                )
            t, n = stop, n + 1
    return (
        '<?xml version="1.0" encoding="utf-8" ?>'
        '<!DOCTYPE tv SYSTEM "xmltv.dtd">'
        '<tv generator-info-name="faux" generator-info-url="">'
        + ''.join(annonces + programmes)
        + '</tv>'
    )


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
    # Kio/s des vidéos, None : sans bride.
    debit: int | None = None
    direct: Path | None = None
    # Kio/s du direct : la mire .ts pèse 48,6 Mo pour 300 s.
    debit_direct = 160
    # Secondes avant la coupure : flux « coupe », et ancien flux d'un compte
    # qui en ouvre un autre (relevé sur le vrai serveur).
    duree_coupe = 15
    delai_coupure = 14
    # Listes chargées une fois : action -> entrées, et nom de chaque film.
    listes: dict[str, list] = {}
    noms_films: dict[str, str] = {}

    def do_GET(self):
        url = urlsplit(self.path)
        params = {k: v[0] for k, v in parse_qs(url.query).items()}
        flux = FLUX.match(url.path)
        if url.path in ('/player_api.php', '/xmltv.php'):
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
        if url.path == '/xmltv.php':
            return self.envoyer_guide(utilisateur)
        return self.api(params, utilisateur)

    def envoyer_guide(self, utilisateur: str):
        chaines = self.listes['get_live_streams']
        if utilisateur == 'sansguide':
            chaines = []
        corps = gzip.compress(guide(chaines, int(time.time())).encode(), 6)
        self.repondre(200, corps, 'text/xml', 'gzip')

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
            fichier = trouver(self.donnees, FICHIERS[action])
        else:
            # Action inconnue : les vrais serveurs renvoient une liste vide.
            return self.repondre(200, b'[]')
        self.repondre(200, fichier.read_bytes())

    def envoyer_video(self, utilisateur: str, type_flux: str, ident: str):
        video = self.video
        nom = self.noms_films.get(ident, '') if type_flux == 'movie' else ''
        if self.video_hd is not None and QUALITE_HD.search(nom):
            video = self.video_hd
        if type_flux == 'live':
            video = self.direct
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
            if type_flux == 'live':
                self.envoyer_direct(utilisateur, video)
            else:
                self.envoyer_plage(video, coupe=utilisateur == 'coupe')
        except ConnectionError:
            pass  # Le lecteur a fermé ou sauté ailleurs dans la vidéo.
        finally:
            with verrou:
                flux_ouverts[utilisateur] -= 1

    def envoyer_direct(self, utilisateur: str, mire: Path):
        """La mire en boucle jusqu'à ce que le lecteur ferme ou soit coupé."""
        maintenant = time.monotonic()
        flux = {
            'fin': maintenant + self.duree_coupe
            if utilisateur == 'coupe'
            else None
        }
        with verrou:
            ouverts = directs.setdefault(utilisateur, [])
            for ancien in ouverts:
                echeance = maintenant + self.delai_coupure
                ancien['fin'] = min(ancien['fin'] or echeance, echeance)
            ouverts.append(flux)
        try:
            self.send_response(200)
            self.send_header('Content-Type', 'video/mp2t')
            self.end_headers()
            debit = self.debit_direct * 1024
            envoye = 0
            with closing(blocs_direct(mire)) as blocs:
                for bloc in blocs:
                    if flux['fin'] and time.monotonic() >= flux['fin']:
                        break
                    self.wfile.write(bloc)
                    envoye += len(bloc)
                    # Calé sur l'horloge : les retards ne s'accumulent pas.
                    attente = (
                        maintenant + envoye / debit - AVANCE_DIRECT
                        - time.monotonic()
                    )
                    if attente > 0:
                        time.sleep(attente)
        finally:
            with verrou:
                ouverts.remove(flux)

    def envoyer_plage(self, video: Path, coupe=False):
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
        # Coupé au milieu : l'en-tête annonce tout, la connexion se ferme
        # avant la fin.
        limite = taille // 2 if coupe and not plage else fin + 1
        with video.open('rb') as f:
            f.seek(debut)
            reste = min(fin + 1, limite) - debut
            while reste > 0:
                bloc = f.read(min(reste, 1 << 16))
                if not bloc:
                    break
                self.wfile.write(bloc)
                reste -= len(bloc)
                if self.debit:
                    time.sleep(len(bloc) / (self.debit * 1024))
        if limite <= fin:
            self.close_connection = True

    def repondre(
        self, code: int, corps: bytes, type_mime='application/json', encodage=None
    ):
        self.send_response(code)
        self.send_header('Content-Type', type_mime)
        if encodage:
            self.send_header('Content-Encoding', encodage)
        self.send_header('Content-Length', str(len(corps)))
        self.end_headers()
        self.wfile.write(corps)


def premiers_par_categorie(entrees: list, n: int) -> list:
    """Les n premières entrées de chaque catégorie, dans leur ordre."""
    vues: dict[str, int] = {}
    gardees = []
    for e in entrees:
        cle = str(e.get('category_id'))
        if vues.get(cle, 0) < n:
            vues[cle] = vues.get(cle, 0) + 1
            gardees.append(e)
    return gardees


def trouver(donnees: Path, nom: str) -> Path:
    """Le fichier de donnees, sinon la fixture : un vieux dump n'a pas tout."""
    fichier = donnees / nom
    return fichier if fichier.is_file() else RACINE / 'test' / 'fixtures' / nom


def charger(donnees: Path, max_par_categorie: int | None = None):
    """Lit les listes filtrables par catégorie."""
    Requete.donnees = donnees
    for action in ('get_vod_streams', 'get_series', 'get_live_streams'):
        fichier = trouver(donnees, FICHIERS[action])
        entrees = json.loads(fichier.read_text(encoding='utf-8'))
        if max_par_categorie is not None:
            entrees = premiers_par_categorie(entrees, max_par_categorie)
        Requete.listes[action] = entrees
    Requete.noms_films = {
        str(f.get('stream_id')): str(f.get('name') or '')
        for f in Requete.listes['get_vod_streams']
    }


def arreter_a_la_fin_de_l_entree():
    """Attend que celui qui tient l'entrée standard la ferme ou meure."""
    # os.read : sans le verrou de sys.stdin, qui gênerait les autres fils.
    while os.read(0, 1024):
        pass
    os._exit(0)


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
    # L'émulateur Android TV perd quelques octets sur les gros transferts :
    # les listes complètes (8 Mo) y échouent, quelques centaines de Ko
    # passent presque toujours.
    arguments.add_argument(
        '--max-par-categorie',
        type=int,
        metavar='N',
        help='ne garder que les N premiers titres de chaque catégorie',
    )
    arguments.add_argument(
        '--debit',
        type=int,
        metavar='KIO_PAR_S',
        help="bride l'envoi des vidéos à ce débit",
    )
    arguments.add_argument(
        '--direct',
        type=Path,
        default=sondes / 'mire-720p.ts'
        if (sondes / 'mire-720p.ts').is_file()
        else None,
        help='mire .ts du direct',
    )
    arguments.add_argument(
        '--debit-direct',
        type=int,
        default=Requete.debit_direct,
        metavar='KIO_PAR_S',
        help='débit du direct',
    )
    arguments.add_argument(
        '--delai-coupure',
        type=float,
        default=Requete.delai_coupure,
        metavar='S',
        help="délai avant de couper l'ancien flux du direct d'un compte",
    )
    arguments.add_argument(
        '--arret-fin-entree',
        action='store_true',
        help="s'arrêter quand l'entrée standard se ferme",
    )
    a = arguments.parse_args()
    charger(a.donnees, a.max_par_categorie)
    Requete.video = a.video
    Requete.video_hd = a.video_hd
    Requete.debit = a.debit
    Requete.direct = a.direct
    Requete.debit_direct = a.debit_direct
    Requete.delai_coupure = a.delai_coupure
    # Sous Windows, SO_REUSEADDR laisse un second serveur écouter le même
    # port sans erreur, et l'ancien garde les connexions : sans lui, le
    # lancement échoue si un faux serveur tourne déjà.
    ThreadingHTTPServer.allow_reuse_address = os.name != 'nt'
    try:
        serveur = ThreadingHTTPServer(('0.0.0.0', a.port), Requete)
    except OSError:
        raise SystemExit(f'Le port {a.port} est déjà pris : un faux serveur '
                         'tourne peut-être encore.')
    if a.arret_fin_entree:
        threading.Thread(
            target=arreter_a_la_fin_de_l_entree, daemon=True
        ).start()

    print(f'Catalogue : {a.donnees}')
    print(f'Vidéo : {a.video or "aucune, les flux répondent 404"}')
    print(f'Vidéo des films SD et HD : {a.video_hd or "la même"}')
    if a.debit:
        print(f'Débit des vidéos : {a.debit} Kio/s')
    print(f'Direct : {a.direct or "aucune mire, les flux répondent 404"}')
    print(f'Écoute sur http://localhost:{a.port} (Ctrl+C pour arrêter)')
    try:
        serveur.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == '__main__':
    principal()
