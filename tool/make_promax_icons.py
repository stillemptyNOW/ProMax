import json
import os
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE = os.path.join(ROOT, 'design', 'promax-logo-source.png')
MARK = os.path.join(ROOT, 'assets', 'promax.png')
FLAT = os.path.join(ROOT, 'assets', 'promax_icon.png')
PREVIEW_DIR = os.path.join(ROOT, 'assets', 'icons')
IOS_RUNNER = os.path.join(ROOT, 'ios', 'Runner')
IOS_APPICON = os.path.join(IOS_RUNNER, 'Assets.xcassets', 'AppIcon.appiconset')

VARIANTS = {
    'Light': {'background': [(246, 247, 251), (226, 229, 238)], 'mark': (12, 13, 18)},
    'Aurora': {'background': [(123, 92, 255), (34, 211, 238)], 'mark': (255, 255, 255)},
    'Sunset': {'background': [(255, 122, 69), (255, 61, 139)], 'mark': (255, 255, 255)},
    'Glass': {'background': [(40, 44, 56), (8, 9, 13)], 'mark': (255, 255, 255), 'glass': True},
}


def mark_alpha(size):
    source = Image.open(SOURCE).convert('L')
    alpha = source.point(lambda v: 0 if v < 24 else (255 if v > 232 else int((v - 24) * 255 / 208)))
    return alpha.resize((size, size), Image.LANCZOS)


def gradient(size, top, bottom):
    image = Image.new('RGB', (size, size))
    draw = ImageDraw.Draw(image)
    for y in range(size):
        t = y / max(1, size - 1)
        color = tuple(round(top[i] + (bottom[i] - top[i]) * t) for i in range(3))
        draw.line([(0, y), (size, y)], fill=color)
    return image


def compose(size, spec):
    image = gradient(size, *spec['background'])
    alpha = mark_alpha(size)
    if spec.get('glass'):
        glow = Image.new('RGB', (size, size), (120, 140, 255))
        halo = alpha.filter(ImageFilter.GaussianBlur(size / 18)).point(lambda v: int(v * 0.55))
        image = Image.composite(glow, image, halo)
        shine = gradient(size, (255, 255, 255), (196, 206, 230))
        image = Image.composite(shine, image, alpha)
    else:
        image = Image.composite(Image.new('RGB', (size, size), spec['mark']), image, alpha)
    return image


def save_mark():
    alpha = mark_alpha(1024)
    mark = Image.new('RGBA', (1024, 1024), (255, 255, 255, 0))
    mark.putalpha(alpha)
    mark.save(MARK, optimize=True)
    flat = Image.new('RGB', (1024, 1024), (0, 0, 0))
    flat.paste(Image.new('RGB', (1024, 1024), (255, 255, 255)), mask=alpha)
    flat.save(FLAT, optimize=True)


def save_variants():
    os.makedirs(PREVIEW_DIR, exist_ok=True)
    for name, spec in VARIANTS.items():
        compose(512, spec).save(os.path.join(PREVIEW_DIR, f'promax_{name.lower()}.png'), optimize=True)
        for scale, px in ((2, 120), (3, 180)):
            compose(px, spec).save(os.path.join(IOS_RUNNER, f'Icon{name}@{scale}x.png'), optimize=True)


def save_primary():
    contents = json.load(open(os.path.join(IOS_APPICON, 'Contents.json'), encoding='utf-8'))
    for entry in contents['images']:
        filename = entry.get('filename')
        if not filename or 'appearances' in entry:
            continue
        points = float(entry['size'].split('x')[0])
        scale = int(entry['scale'][0])
        px = round(points * scale)
        image = Image.open(FLAT).convert('RGB').resize((px, px), Image.LANCZOS)
        image.save(os.path.join(IOS_APPICON, filename), optimize=True)


if __name__ == '__main__':
    save_mark()
    save_variants()
    if '--skip-primary' not in sys.argv:
        save_primary()
