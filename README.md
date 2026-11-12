# CouchPlay

Lecteur vidéo personnel pour Windows et Android, écrit en Flutter.

## Compiler

Prérequis : Flutter stable, Visual Studio Build Tools avec la charge « Développement desktop en C++ » (Windows), SDK Android avec le NDK (Android).

```sh
flutter pub get
flutter build windows
flutter build apk
```

## Linux

Pas encore publiée : aucune archive Linux dans les releases, il faut la compiler soi-même (voir plus bas). Dépendances à l'exécution (Debian, Ubuntu) :

```sh
sudo apt-get install -y libgtk-3-0 libmpv2 libsecret-1-0 gnome-keyring
```

Un trousseau de clés (gnome-keyring, KWallet) doit tourner pour stocker les comptes. Lancer `./couchplay` depuis `build/linux/x64/release/bundle`. Aucune mise à jour n'est proposée tant qu'aucune archive Linux n'est publiée.

Pour compiler : `sudo apt-get install -y clang cmake ninja-build pkg-config libgtk-3-dev libmpv-dev libsecret-1-dev`, puis `flutter build linux --release`.

## Essayer sans le vrai serveur

`tools/faux-serveur.py` imite le serveur du fournisseur (Python 3.10+, sans dépendance) :

```sh
python -I tools/faux-serveur.py
```

Dans l'app : hôte `http://localhost:8080` (ou `http://<IP du PC>:8080` depuis le téléphone), mot de passe quelconque. Le nom d'utilisateur choisit le comportement (`refuse`, `expire`, `lent`, `muet`, `html`, `plein`, un code HTTP comme `429`…), détaillé en tête du script. Le catalogue vient de `probe/` s'il existe, sinon de `test/fixtures/` ; la vidéo jouée est `probe/mire.mkv` ou celle passée avec `--video`. Vérification : `python -I tools/test_faux_serveur.py`.
