"""Draws the images of the installer's wizard (tools/package/setup/*.bmp): a purple-to-teal gradient with the "ii"
mark, in the Material 3 colours ii-windows uses. Run once; the .bmp files are committed."""
import os

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, 'setup')
os.makedirs(OUT, exist_ok=True)


def gradient(size, top, bottom):
    w, h = size
    img = Image.new('RGB', size)
    px = img.load()
    for y in range(h):
        t = y / max(1, h - 1)
        color = tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3))
        for x in range(w):
            px[x, y] = color
    return img


def font(name, size):
    for candidate in (r'C:\Windows\Fonts\%s' % name, r'C:\Windows\Fonts\segoeuib.ttf', r'C:\Windows\Fonts\arialbd.ttf'):
        if os.path.exists(candidate):
            return ImageFont.truetype(candidate, size)
    return ImageFont.load_default()


def big(scale=3):
    w, h = 164 * scale, 314 * scale
    img = gradient((w, h), (38, 25, 79), (24, 64, 92))
    d = ImageDraw.Draw(img)
    # soft blobs, like ii's shapes
    d.ellipse((-w * 0.4, h * 0.55, w * 0.9, h * 1.25), fill=(77, 53, 140))
    d.ellipse((w * 0.35, h * 0.1, w * 1.4, h * 0.7), fill=(32, 83, 112))
    d.rounded_rectangle((w * 0.16, h * 0.14, w * 0.84, h * 0.14 + w * 0.68), radius=int(w * 0.2), fill=(208, 188, 255))
    f = font('segoeuib.ttf', int(w * 0.46))
    d.text((w * 0.5, h * 0.14 + w * 0.34), 'ii', font=f, fill=(56, 30, 114), anchor='mm')
    f2 = font('segoeuib.ttf', int(w * 0.13))
    d.text((w * 0.5, h * 0.62), 'ii-windows', font=f2, fill=(255, 255, 255), anchor='mm')
    f3 = font('segoeui.ttf', int(w * 0.075))
    d.text((w * 0.5, h * 0.68), 'para programadores', font=f3, fill=(214, 206, 240), anchor='mm')
    return img.resize((164, 314), Image.LANCZOS)


def small(scale=4):
    s = 55 * scale
    img = gradient((s, s), (38, 25, 79), (24, 64, 92))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((s * 0.12, s * 0.12, s * 0.88, s * 0.88), radius=int(s * 0.26), fill=(208, 188, 255))
    d.text((s * 0.5, s * 0.5), 'ii', font=font('segoeuib.ttf', int(s * 0.5)), fill=(56, 30, 114), anchor='mm')
    return img.resize((55, 55), Image.LANCZOS)


def icon(size=256):
    img = gradient((size, size), (38, 25, 79), (24, 64, 92)).convert('RGBA')
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((size * 0.1, size * 0.1, size * 0.9, size * 0.9), radius=int(size * 0.27), fill=(208, 188, 255, 255))
    d.text((size * 0.5, size * 0.5), 'ii', font=font('segoeuib.ttf', int(size * 0.52)), fill=(56, 30, 114, 255), anchor='mm')
    mask = Image.new('L', (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, size - 1, size - 1), radius=int(size * 0.22), fill=255)
    img.putalpha(mask)
    return img


icon().save(os.path.join(OUT, 'ii.ico'), sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
big().save(os.path.join(OUT, 'wizard.bmp'))
small().save(os.path.join(OUT, 'wizard-small.bmp'))
print('wrote', OUT)
