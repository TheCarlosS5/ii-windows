"""Material 3 colors from a wallpaper, in the colors.json format illogical-impulse reads
(the keys of its matugen template, snake_case -> "#RRGGBB").

Same pipeline as ii's generate_colors_material.py (materialyoucolor: Celebi quantizer,
Score, dynamic scheme). Stand-in until the generator is ported to C++ inside the shell.

usage: python gen_colors.py --image wall.jpg [--mode dark|light] [--scheme tonal-spot] --out colors.json
"""
import argparse
import json
import math
import re

from PIL import Image
from materialyoucolor.dynamiccolor.material_dynamic_colors import MaterialDynamicColors
from materialyoucolor.hct import Hct
from materialyoucolor.quantize import QuantizeCelebi
from materialyoucolor.score.score import Score
from materialyoucolor.utils.color_utils import rgba_from_argb

SCHEMES = {
    'tonal-spot': 'scheme_tonal_spot.SchemeTonalSpot',
    'content': 'scheme_content.SchemeContent',
    'expressive': 'scheme_expressive.SchemeExpressive',
    'fidelity': 'scheme_fidelity.SchemeFidelity',
    'fruit-salad': 'scheme_fruit_salad.SchemeFruitSalad',
    'monochrome': 'scheme_monochrome.SchemeMonochrome',
    'neutral': 'scheme_neutral.SchemeNeutral',
    'rainbow': 'scheme_rainbow.SchemeRainbow',
    'vibrant': 'scheme_vibrant.SchemeVibrant',
}

# Keys of dots/.config/matugen/templates/colors.json
KEYS = [
    'background', 'error', 'error_container', 'inverse_on_surface', 'inverse_primary',
    'inverse_surface', 'on_background', 'on_error', 'on_error_container', 'on_primary',
    'on_primary_container', 'on_primary_fixed', 'on_primary_fixed_variant', 'on_secondary',
    'on_secondary_container', 'on_secondary_fixed', 'on_secondary_fixed_variant', 'on_surface',
    'on_surface_variant', 'on_tertiary', 'on_tertiary_container', 'on_tertiary_fixed',
    'on_tertiary_fixed_variant', 'outline', 'outline_variant', 'primary', 'primary_container',
    'primary_fixed', 'primary_fixed_dim', 'scrim', 'secondary', 'secondary_container',
    'secondary_fixed', 'secondary_fixed_dim', 'shadow', 'surface', 'surface_bright',
    'surface_container', 'surface_container_high', 'surface_container_highest',
    'surface_container_low', 'surface_container_lowest', 'surface_dim', 'surface_tint',
    'surface_variant', 'tertiary', 'tertiary_container', 'tertiary_fixed', 'tertiary_fixed_dim',
]


def source_color(path, bitmap_size=128):
    image = Image.open(path)
    if image.format == 'GIF':
        image.seek(1)
    image = image.convert('RGB')
    w, h = image.size
    scale = math.sqrt(bitmap_size ** 2 / (w * h)) if w * h > bitmap_size ** 2 else 1
    image = image.resize((max(1, round(w * scale)), max(1, round(h * scale))), Image.Resampling.BICUBIC)
    pixels = list(image.getdata())
    return Score.score(QuantizeCelebi(pixels, 128))[0]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--image')
    ap.add_argument('--color', help='#RRGGBB instead of an image')
    ap.add_argument('--mode', choices=['dark', 'light'], default='dark')
    ap.add_argument('--scheme', default='tonal-spot', choices=sorted(SCHEMES))
    ap.add_argument('--out', required=True)
    args = ap.parse_args()

    if args.color:
        c = args.color.lstrip('#')
        argb = 0xFF000000 | int(c, 16)
    else:
        argb = source_color(args.image)

    module_name, class_name = SCHEMES[args.scheme].split('.')
    module = __import__(f'materialyoucolor.scheme.{module_name}', fromlist=[class_name])
    scheme = getattr(module, class_name)(Hct.from_int(argb), args.mode == 'dark', 0.0)

    out = {}
    for key in KEYS:
        camel = re.sub(r'_([a-z])', lambda m: m.group(1).upper(), key)
        dynamic = getattr(MaterialDynamicColors, camel, None)
        if dynamic is None:
            continue
        r, g, b, _ = rgba_from_argb(dynamic.get_argb(scheme))
        out[key] = '#{:02x}{:02x}{:02x}'.format(round(r), round(g), round(b))

    with open(args.out, 'w', encoding='utf-8') as f:
        json.dump(out, f, indent=2)
    r, g, b, _ = rgba_from_argb(argb)
    print(f'source #{round(r):02x}{round(g):02x}{round(b):02x} -> {len(out)} colors -> {args.out}')


if __name__ == '__main__':
    main()
