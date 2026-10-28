"""Dessine l'icône de l'app : un canapé et un bouton lecture, sur fond violet.

Sans dépendance (bibliothèque standard seule). Écrit l'icône Windows, en
plusieurs tailles, et un aperçu PNG si on le demande :

    python tools/icone.py windows/runner/resources/app_icon.ico [apercu.png]
"""

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


def color_at(x, y):
    """Couleur RGBA du point (x, y), coordonnées de 0 à 1."""
    if not rounded(x, y, 0, 0, 1, 1, 0.22):
        return (0, 0, 0, 0)
    t = y
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
    return tuple(round(a + (b - a) * t) for a, b in zip(TOP, BOTTOM)) + (255,)


def render(size):
    """Pixels RGBA, ligne par ligne, prémultipliés puis moyennés."""
    rows = []
    n = SAMPLES
    for py in range(size):
        row = bytearray()
        for px in range(size):
            acc = [0, 0, 0, 0]
            for sy in range(n):
                for sx in range(n):
                    r, g, b, a = color_at(
                        (px + (sx + 0.5) / n) / size, (py + (sy + 0.5) / n) / size
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


def png(size, rows):
    def chunk(kind, data):
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body))

    raw = b"".join(b"\0" + row for row in rows)
    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(raw, 9))
        + chunk(b"IEND", b"")
    )


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


def main():
    images = [(size, png(size, render(size))) for size in SIZES]
    with open(sys.argv[1], "wb") as f:
        f.write(ico(images))
    if len(sys.argv) > 2:
        with open(sys.argv[2], "wb") as f:
            f.write(images[-1][1])


if __name__ == "__main__":
    main()
