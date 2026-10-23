import argparse
import io
import json
import os
import sys
import urllib.parse
import urllib.request

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUTPUT = os.path.join(ROOT, 'native', 'promax_effects', 'ios', 'Resources', 'masks')
REPOSITORY = 'microsoft/fluentui-emoji'
REVISION = '1ffb34c752ecf5d402f04cfb4b392c77f57c54bc'
MAX_SIDE = 512
PADDING = 4

STICKERS = [
    {'id': 'sunglasses', 'source': 'assets/Sunglasses/3D/sunglasses_3d.png', 'anchor': 'eyes',
     'width': 2.25, 'pivot': (126, 123), 'depth': 0.15},
    {'id': 'goggles', 'source': 'assets/Goggles/3D/goggles_3d.png', 'anchor': 'eyes',
     'width': 2.45, 'pivot': (125, 150), 'depth': 0.15},
    {'id': 'heartEyes', 'source': 'assets/Red heart/3D/red_heart_3d.png', 'anchor': 'eachEye',
     'width': 0.95, 'pivot': (128, 142), 'depth': 0.1},
    {'id': 'crown', 'source': 'assets/Crown/3D/crown_3d.png', 'anchor': 'forehead',
     'width': 2.15, 'pivot': (128, 232), 'offset': (0, 0.35), 'depth': -0.45},
    {'id': 'topHat', 'source': 'assets/Top hat/3D/top_hat_3d.png', 'anchor': 'forehead',
     'width': 3.0, 'pivot': (128, 222), 'offset': (0, 0.08), 'depth': -0.45},
    {'id': 'pigNose', 'source': 'assets/Pig nose/3D/pig_nose_3d.png', 'anchor': 'nose',
     'width': 1.15, 'pivot': (128, 156), 'offset': (0, -0.05), 'depth': 0.1},
    {'id': 'mustache', 'source': 'assets/Disguised face/3D/disguised_face_3d.png', 'anchor': 'mouth',
     'width': 3.1, 'pivot': (129, 197), 'offset': (0, 0.3), 'extract': 'mustache'},
    {'id': 'cat', 'source': 'assets/Cat face/3D/cat_face_3d.png', 'anchor': 'eyes',
     'width': 3.5, 'pivot': (124, 147)},
    {'id': 'fox', 'source': 'assets/Fox/3D/fox_3d.png', 'anchor': 'eyes',
     'width': 3.5, 'pivot': (125, 146)},
    {'id': 'panda', 'source': 'assets/Panda/3D/panda_3d.png', 'anchor': 'eyes',
     'width': 3.4, 'pivot': (128, 136)},
    {'id': 'alien', 'source': 'assets/Alien/3D/alien_3d.png', 'anchor': 'eyes',
     'width': 3.2, 'pivot': (122, 135)},
    {'id': 'robot', 'source': 'assets/Robot/3D/robot_3d.png', 'anchor': 'eyes',
     'width': 3.2, 'pivot': (128, 113)},
]

EFFECTS = [
    {'id': 'pixels', 'effect': 'pixelate', 'anchor': 'face', 'scale': 3.0, 'aspect': 1.3},
]


def fetch(source_dir, path):
    if source_dir:
        with open(os.path.join(source_dir, path), 'rb') as handle:
            return handle.read()
    url = 'https://raw.githubusercontent.com/%s/%s/%s' % (
        REPOSITORY, REVISION, urllib.parse.quote(path))
    with urllib.request.urlopen(url, timeout=60) as response:
        return response.read()


def extract_mustache(image):
    box = (56, 168, 204, 236)
    crop = image.crop(box)
    red = crop.getchannel('R')
    alpha = red.point(lambda v: 255 if v <= 100 else (0 if v >= 185 else (185 - v) * 255 // 85))
    alpha = ImageChops.multiply(alpha, crop.getchannel('A'))
    region = alpha.point(lambda v: 128 if v > 8 else 0)
    ImageDraw.floodfill(region, (72, 30), 255)
    region = region.point(lambda v: 255 if v == 255 else 0).filter(ImageFilter.MaxFilter(3))
    alpha = ImageChops.multiply(alpha, region).filter(ImageFilter.GaussianBlur(0.5))
    core = red.point(lambda v: 255 if v <= 100 else 0)
    fill = Image.composite(crop, Image.new('RGBA', crop.size, (0, 0, 0, 0)), core)
    for _ in range(6):
        grown = fill.filter(ImageFilter.MaxFilter(3))
        fill = Image.composite(fill, grown, fill.getchannel('A').point(lambda v: 255 if v else 0))
    result = Image.composite(crop, fill, core).convert('RGB').convert('RGBA')
    result.putalpha(alpha)
    canvas = Image.new('RGBA', image.size, (0, 0, 0, 0))
    canvas.paste(result, box[:2])
    return canvas


def trim(image, pivot):
    left, top, right, bottom = image.getchannel('A').point(lambda v: 255 if v > 4 else 0).getbbox()
    left = max(left - PADDING, 0)
    top = max(top - PADDING, 0)
    right = min(right + PADDING, image.width)
    bottom = min(bottom + PADDING, image.height)
    cropped = image.crop((left, top, right, bottom))
    return cropped, (pivot[0] - left, pivot[1] - top), right - left


def render(sticker, data):
    image = Image.open(io.BytesIO(data)).convert('RGBA')
    source_width = image.width
    if sticker.get('extract') == 'mustache':
        image = extract_mustache(image)
    image, pivot, cropped_width = trim(image, sticker['pivot'])
    scale = sticker['width'] * cropped_width / source_width
    if max(image.size) > MAX_SIDE:
        factor = MAX_SIDE / max(image.size)
        image = image.resize((round(image.width * factor), round(image.height * factor)), Image.LANCZOS)
        pivot = (pivot[0] * factor, pivot[1] * factor)
    pivot = (pivot[0] / image.width, pivot[1] / image.height)
    entry = {
        'id': sticker['id'],
        'asset': sticker['id'] + '.png',
        'anchor': sticker['anchor'],
        'scale': round(scale, 4),
        'offset': list(sticker.get('offset', (0, 0))),
        'pivot': [round(pivot[0], 4), round(pivot[1], 4)],
        'depth': sticker.get('depth', 0),
    }
    return image, entry


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--source', help='local checkout of %s at %s' % (REPOSITORY, REVISION))
    args = parser.parse_args()
    os.makedirs(OUTPUT, exist_ok=True)
    entries = []
    for sticker in STICKERS:
        image, entry = render(sticker, fetch(args.source, sticker['source']))
        image.save(os.path.join(OUTPUT, entry['asset']), optimize=True)
        entries.append(entry)
    entries.extend(EFFECTS)
    manifest = {
        'source': 'https://github.com/%s/tree/%s' % (REPOSITORY, REVISION),
        'masks': entries,
    }
    lines = ',\n'.join('    ' + json.dumps(entry) for entry in entries)
    with open(os.path.join(OUTPUT, 'masks.json'), 'w', encoding='utf-8') as handle:
        handle.write('{\n  "source": %s,\n  "masks": [\n%s\n  ]\n}\n' % (json.dumps(manifest['source']), lines))
    license_text = fetch(args.source, 'LICENSE').decode('utf-8')
    with open(os.path.join(OUTPUT, 'LICENSE-fluentui-emoji.txt'), 'w', encoding='utf-8') as handle:
        handle.write('Microsoft Fluent Emoji, %s\n\n' % manifest['source'])
        handle.write('\n'.join(line.strip() for line in license_text.strip().splitlines()) + '\n')
    print('wrote %d masks to %s' % (len(entries), os.path.relpath(OUTPUT, ROOT)))


if __name__ == '__main__':
    sys.exit(main())
