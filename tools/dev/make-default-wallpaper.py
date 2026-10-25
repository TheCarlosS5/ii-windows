"""ii-windows' own default wallpaper (overlay/ii/assets/images/default_wallpaper.png).

Drawn here from scratch so its licence is the repository's (no third-party picture): a dark blue-violet field with a
few large, soft Material-style shapes. It replaces upstream's picture at the same path, so every place that falls back
to "ii's own wallpaper" (first run, a deleted file, the welcome cover) shows this one.
    python -I tools/dev/make-default-wallpaper.py [out.png]
Needs Pillow."""
import math
import os
import sys

from PIL import Image, ImageDraw, ImageFilter

W, H = 2560, 1440
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), '..', '..', 'overlay', 'ii', 'assets',
                                                          'images', 'default_wallpaper.png')


def lerp(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


# Diagonal base gradient.
top_left, bottom_right = (24, 26, 52), (44, 30, 74)
base = Image.new('RGB', (W, H))
px = base.load()
for y in range(H):
    for x in range(0, W, 4):
        t = min(1.0, max(0.0, (x / W) * 0.55 + (y / H) * 0.45))
        c = lerp(top_left, bottom_right, t)
        for dx in range(4):
            px[x + dx, y] = c

# Soft shapes: a scalloped "cookie" (Material 3 Expressive), a pill and two glows, blurred heavily.
shapes = Image.new('RGBA', (W, H), (0, 0, 0, 0))
d = ImageDraw.Draw(shapes)


def cookie(cx, cy, r, lobes, depth, fill):
    pts = []
    for i in range(720):
        a = 2 * math.pi * i / 720
        rr = r * (1 + depth * math.cos(lobes * a))
        pts.append((cx + rr * math.cos(a), cy + rr * math.sin(a)))
    d.polygon(pts, fill=fill)


cookie(1880, 520, 470, 9, 0.06, (110, 86, 190, 200))
d.rounded_rectangle((260, 880, 1260, 1240), radius=180, fill=(46, 140, 150, 150))
d.ellipse((900, -300, 1700, 500), fill=(170, 110, 200, 90))
d.ellipse((1500, 1000, 2500, 1800), fill=(70, 90, 200, 120))
shapes = shapes.filter(ImageFilter.GaussianBlur(90))
img = Image.alpha_composite(base.convert('RGBA'), shapes)

# A crisper copy of the cookie on top, faint, so the picture keeps a shape and is not only blur.
crisp = Image.new('RGBA', (W, H), (0, 0, 0, 0))
d = ImageDraw.Draw(crisp)
cookie(1880, 520, 360, 9, 0.07, (150, 128, 230, 46))
img = Image.alpha_composite(img, crisp.filter(ImageFilter.GaussianBlur(3)))

os.makedirs(os.path.dirname(os.path.abspath(OUT)), exist_ok=True)
img.convert('RGB').save(OUT, optimize=True)
print('wrote', os.path.abspath(OUT), os.path.getsize(OUT), 'bytes')
