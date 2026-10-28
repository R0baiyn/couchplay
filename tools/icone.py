"""Dessine l'icône de l'app : un canapé et un bouton lecture, sur fond violet.

Sans dépendance (bibliothèque standard seule). Écrit l'icône Windows, en
plusieurs tailles, et un aperçu PNG si on le demande :

    python tools/icone.py windows/runner/resources/app_icon.ico [apercu.png]

Ou les ressources Android : icône des anciens Android, icône adaptative
(fond, canapé, version monochrome pour les icônes à thème) et bannière de
l'écran d'accueil des TV :

    python tools/icone.py --android android/app/src/main/res
"""

import os
import struct
import sys
import zlib

SIZES = (16, 24, 32, 48, 64, 128, 256)
SAMPLES = 4  # anticrénelage : 4 × 4 échantillons par pixel

TOP = (0x95, 0x75, 0xCD)  # dégradé du fond, couleur du thème (deepPurple)
BOTTOM = (0x45, 0x27, 0xA0)
COUCH = (0xFF, 0xFF, 0xFF)
SHADE = (0xE3, 0xDB, 0xF2)  # assise, un peu plus sombre que le dossier
PLAY = (0x5E, 0x35, 0xB1)
CLEAR = (0, 0, 0, 0)

# Android : facteur de densité de chaque dossier mipmap.
DENSITIES = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}

# Calque avant de l'icône adaptative : 108 dp, dont un cercle de 66 dp
# toujours visible, quelle que soit la forme choisie par le téléphone. Le
# canapé (0,76 × 0,52 de l'icône) y tient réduit à 68 %.
FOREGROUND_SCALE = 0.68

# Bannière TV : 320 × 180 px (xhdpi), canapé centré sur 90 % de la hauteur.
BANNER = (320, 180)
BANNER_SCALE = 0.9


def rounded(x, y, x0, y0, x1, y1, r):
    """Le point (x, y) est dans le rectangle aux coins arrondis de rayon r."""
    if not (x0 <= x <= x1 and y0 <= y <= y1):
        return False
    cx = min(max(x, x0 + r), x1 - r)
    cy = min(max(y, y0 + r), y1 - r)
    return (x - cx) ** 2 + (y - cy) ** 2 <= r * r


def triangle(x, y, a, b, c):
    def side(p, q):
        return (q[0] - p[0]) * (y - p[1]) - (q[1] - p[1]) * (x - p[0])

    s = (side(a, b), side(b, c), side(c, a))
    return all(v >= 0 for v in s) or all(v <= 0 for v in s)


def couch_at(x, y):
    """Couleur RGBA du canapé ou du bouton au point (x, y) de l'icône
    (coordonnées de 0 à 1), `None` sur le fond."""
    y += 0.05  # canapé centré dans le carré
    if triangle(x, y, (0.445, 0.335), (0.445, 0.525), (0.595, 0.43)):
        return PLAY + (255,)
    if rounded(x, y, 0.235, 0.29, 0.765, 0.585, 0.08):  # dossier
        return COUCH + (255,)
    if rounded(x, y, 0.12, 0.46, 0.3, 0.76, 0.075) or rounded(
        x, y, 0.7, 0.46, 0.88, 0.76, 0.075
    ):  # accoudoirs
        return COUCH + (255,)
    if rounded(x, y, 0.27, 0.56, 0.73, 0.74, 0.04):  # assise
        return SHADE + (255,)
    if rounded(x, y, 0.17, 0.74, 0.25, 0.81, 0.02) or rounded(
        x, y, 0.75, 0.74, 0.83, 0.81, 0.02
    ):  # pieds
        return COUCH + (255,)
    return None


def gradient(t):
    """Fond, de TOP (t = 0) à BOTTOM (t = 1)."""
    return tuple(round(a + (b - a) * t) for a, b in zip(TOP, BOTTOM)) + (255,)


def icon_at(x, y):
    """Icône complète : carré arrondi violet et canapé."""
    if not rounded(x, y, 0, 0, 1, 1, 0.22):
        return CLEAR
    return couch_at(x, y) or gradient(y)


def foreground_at(x, y):
    """Calque avant de l'icône adaptative : le canapé seul, réduit."""
    s = FOREGROUND_SCALE
    return couch_at(0.5 + (x - 0.5) / s, 0.5 + (y - 0.5) / s) or CLEAR


def monochrome_at(x, y):
    """Icône à thème : la silhouette du canapé, le bouton en creux. Android
    la colore lui-même."""
    color = foreground_at(x, y)
    return CLEAR if color in (CLEAR, PLAY + (255,)) else COUCH + (255,)


def banner_at(x, y):
    """Bannière TV : dégradé, canapé centré."""
    width, height = BANNER
    s = BANNER_SCALE
    icon_x = 0.5 + (x - 0.5) * width / height / s
    return couch_at(icon_x, 0.5 + (y - 0.5) / s) or gradient(y)


def render(width, height, color):
    """Pixels RGBA de `color(x, y)`, ligne par ligne, prémultipliés puis
    moyennés."""
    rows = []
    n = SAMPLES
    for py in range(height):
        row = bytearray()
        for px in range(width):
            acc = [0, 0, 0, 0]
            for sy in range(n):
                for sx in range(n):
                    r, g, b, a = color(
                        (px + (sx + 0.5) / n) / width,
                        (py + (sy + 0.5) / n) / height,
                    )
                    acc[0] += r * a
                    acc[1] += g * a
                    acc[2] += b * a
                    acc[3] += a
            alpha = acc[3] / (n * n)
            if acc[3]:
                row += bytes(round(acc[i] / acc[3]) for i in range(3))
            else:
                row += b"\0\0\0"
            row.append(round(alpha))
        rows.append(bytes(row))
    return rows


def png(width, height, rows):
    def chunk(kind, data):
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body))

    raw = b"".join(b"\0" + row for row in rows)
    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(raw, 9))
        + chunk(b"IEND", b"")
    )


def square_png(size, color):
    return png(size, size, render(size, size, color))


def ico(images):
    """Icône Windows dont chaque taille est un PNG (Windows Vista et suivants)."""
    header = struct.pack("<HHH", 0, 1, len(images))
    offset = len(header) + 16 * len(images)
    entries, data = b"", b""
    for size, image in images:
        dim = 0 if size >= 256 else size
        entries += struct.pack("<BBBBHHII", dim, dim, 0, 0, 1, 32, len(image), offset + len(data))
        data += image
    return header + entries + data


ADAPTIVE_ICON = """<?xml version="1.0" encoding="utf-8"?>
<!-- Généré par tools/icone.py -->
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@drawable/ic_launcher_background" />
    <foreground android:drawable="@mipmap/ic_launcher_foreground" />
    <monochrome android:drawable="@mipmap/ic_launcher_monochrome" />
</adaptive-icon>
"""

BACKGROUND = """<?xml version="1.0" encoding="utf-8"?>
<!-- Généré par tools/icone.py -->
<shape xmlns:android="http://schemas.android.com/apk/res/android">
    <gradient
        android:angle="270"
        android:startColor="#{top}"
        android:endColor="#{bottom}" />
</shape>
"""


def write(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    mode = "w" if isinstance(data, str) else "wb"
    with open(path, mode, **({"encoding": "utf-8", "newline": "\n"} if mode == "w" else {})) as f:
        f.write(data)


def android(res):
    for name, density in DENSITIES.items():
        folder = os.path.join(res, f"mipmap-{name}")
        # Android 7 : l'icône entière (48 dp).
        write(os.path.join(folder, "ic_launcher.png"), square_png(round(48 * density), icon_at))
        size = round(108 * density)
        write(os.path.join(folder, "ic_launcher_foreground.png"), square_png(size, foreground_at))
        write(os.path.join(folder, "ic_launcher_monochrome.png"), square_png(size, monochrome_at))
    write(os.path.join(res, "mipmap-anydpi-v26", "ic_launcher.xml"), ADAPTIVE_ICON)
    hexa = lambda c: "".join(f"{v:02X}" for v in c)
    write(
        os.path.join(res, "drawable", "ic_launcher_background.xml"),
        BACKGROUND.format(top=hexa(TOP), bottom=hexa(BOTTOM)),
    )
    width, height = BANNER
    write(os.path.join(res, "drawable-xhdpi", "banner.png"), png(width, height, render(width, height, banner_at)))


def main():
    if sys.argv[1] == "--android":
        android(sys.argv[2])
        return
    images = [(size, square_png(size, icon_at)) for size in SIZES]
    with open(sys.argv[1], "wb") as f:
        f.write(ico(images))
    if len(sys.argv) > 2:
        with open(sys.argv[2], "wb") as f:
            f.write(images[-1][1])


if __name__ == "__main__":
    main()
