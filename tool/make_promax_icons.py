import hashlib
import json
import os
import re
import sys

from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE = os.path.join(ROOT, 'design', 'promax-logo-source.png')
MARK = os.path.join(ROOT, 'assets', 'promax.png')
FLAT = os.path.join(ROOT, 'assets', 'promax_icon.png')
PREVIEW_DIR = os.path.join(ROOT, 'assets', 'icons')
IOS_RUNNER = os.path.join(ROOT, 'ios', 'Runner')
IOS_APPICON = os.path.join(IOS_RUNNER, 'Assets.xcassets', 'AppIcon.appiconset')
IOS_PLIST = os.path.join(IOS_RUNNER, 'Info.plist')
IOS_PROJECT = os.path.join(ROOT, 'ios', 'Runner.xcodeproj', 'project.pbxproj')
ANDROID_RES = os.path.join(ROOT, 'android', 'app', 'src', 'main', 'res')
WINDOWS_RESOURCES = os.path.join(ROOT, 'windows', 'runner', 'resources')
INSTALLER_DIR = os.path.join(ROOT, 'windows', 'installer')
INSTALLER_PANELS = {100: (202, 386), 150: (336, 643), 200: (430, 824)}
INSTALLER_BADGES = {100: 58, 150: 97, 200: 124}

ANDROID_DENSITIES = {'mdpi': 1, 'hdpi': 1.5, 'xhdpi': 2, 'xxhdpi': 3, 'xxxhdpi': 4}
ANDROID_LEGACY_DP = 48
ANDROID_LAYER_DP = 108
ANDROID_SUBJECT_DP = 58
WINDOWS_ICO_SIZES = (16, 20, 24, 32, 40, 48, 64, 96, 128, 256)
ARTWORK_FILL = 0.9

VARIANTS = {
    'Light': {'background': [(246, 247, 251), (226, 229, 238)], 'mark': (12, 13, 18)},
    'Aurora': {'background': [(123, 92, 255), (34, 211, 238)], 'mark': (255, 255, 255)},
    'Sunset': {'background': [(255, 122, 69), (255, 61, 139)], 'mark': (255, 255, 255)},
    'Glass': {'background': [(40, 44, 56), (8, 9, 13)], 'mark': (255, 255, 255), 'glass': True},
}

ARTWORKS = {
    'Halloween': {'source': 'promax-logo-halloween.png', 'center': (650, 625), 'extent': 470},
    'NewYear': {'source': 'promax-logo-newyear.png', 'center': (720, 590), 'extent': 440},
}

ALTERNATES = list(VARIANTS) + list(ARTWORKS)


def resource_name(name):
    return f'ic_launcher_{name.lower()}'


def mark_alpha(size):
    source = Image.open(SOURCE).convert('L')
    alpha = source.point(lambda v: 0 if v < 24 else (255 if v > 232 else int((v - 24) * 255 / 208)))
    return alpha.resize((size, size), Image.LANCZOS)


def gradient(size, top, bottom):
    return vertical_gradient(size, size, top, bottom)


def vertical_gradient(width, height, top, bottom):
    image = Image.new('RGB', (width, height))
    draw = ImageDraw.Draw(image)
    for y in range(height):
        t = y / max(1, height - 1)
        color = tuple(round(top[i] + (bottom[i] - top[i]) * t) for i in range(3))
        draw.line([(0, y), (width, y)], fill=color)
    return image


def glass(image, alpha, mark_size):
    glow = Image.new('RGB', image.size, (120, 140, 255))
    halo = glass_halo(alpha, mark_size)
    image = Image.composite(glow, image, halo)
    shine = vertical_gradient(*image.size, (255, 255, 255), (196, 206, 230))
    return Image.composite(shine, image, alpha)


def glass_halo(alpha, mark_size):
    return alpha.filter(ImageFilter.GaussianBlur(mark_size / 18)).point(lambda v: int(v * 0.55))


def compose(size, spec):
    image = gradient(size, *spec['background'])
    alpha = mark_alpha(size)
    if spec.get('glass'):
        return glass(image, alpha, size)
    return Image.composite(Image.new('RGB', (size, size), spec['mark']), image, alpha)


def artwork_crop(spec, side):
    source = Image.open(os.path.join(ROOT, 'design', spec['source'])).convert('RGB')
    corner = source.getpixel((0, 0))
    cx, cy = spec['center']
    left = round(cx - side / 2)
    top = round(cy - side / 2)
    canvas = Image.new('RGB', (round(side), round(side)), corner)
    canvas.paste(source, (-left, -top))
    return canvas


def artwork_side(spec):
    return 2 * spec['extent'] / ARTWORK_FILL


def full_bleed(name, size):
    if name in VARIANTS:
        return compose(size, VARIANTS[name])
    spec = ARTWORKS[name]
    return artwork_crop(spec, artwork_side(spec)).resize((size, size), Image.LANCZOS)


def artwork_layer(spec, size):
    side = 2 * spec['extent'] * ANDROID_LAYER_DP / ANDROID_SUBJECT_DP
    return artwork_crop(spec, side).resize((size, size), Image.LANCZOS)


def variant_foreground(spec, size):
    alpha = mark_alpha(size)
    if spec.get('glass'):
        halo = Image.new('RGBA', (size, size), (120, 140, 255, 0))
        halo.putalpha(glass_halo(alpha, size))
        shine = vertical_gradient(size, size, (255, 255, 255), (196, 206, 230)).convert('RGBA')
        shine.putalpha(alpha)
        return Image.alpha_composite(halo, shine)
    mark = Image.new('RGBA', (size, size), spec['mark'] + (0,))
    mark.putalpha(alpha)
    return mark


def hex_color(rgb):
    return '#' + ''.join(f'{c:02X}' for c in rgb)


def write_text(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w', encoding='utf-8', newline='\n') as f:
        f.write(text)


def save_mark():
    alpha = mark_alpha(1024)
    mark = Image.new('RGBA', (1024, 1024), (255, 255, 255, 0))
    mark.putalpha(alpha)
    mark.save(MARK, optimize=True)
    flat = Image.new('RGB', (1024, 1024), (0, 0, 0))
    flat.paste(Image.new('RGB', (1024, 1024), (255, 255, 255)), mask=alpha)
    flat.save(FLAT, optimize=True)


def save_previews():
    os.makedirs(PREVIEW_DIR, exist_ok=True)
    for name in ALTERNATES:
        full_bleed(name, 512).save(os.path.join(PREVIEW_DIR, f'promax_{name.lower()}.png'), optimize=True)


def save_ios_alternates():
    for name in ALTERNATES:
        for scale, px in ((2, 120), (3, 180)):
            full_bleed(name, px).save(os.path.join(IOS_RUNNER, f'Icon{name}@{scale}x.png'), optimize=True)
    sync_ios_plist()
    sync_ios_project()


def ios_alternates_block(indent):
    lines = [f'{indent}<key>CFBundleAlternateIcons</key>', f'{indent}<dict>']
    for name in ALTERNATES:
        lines += [
            f'{indent}\t<key>Icon{name}</key>',
            f'{indent}\t<dict>',
            f'{indent}\t\t<key>CFBundleIconFiles</key>',
            f'{indent}\t\t<array>',
            f'{indent}\t\t\t<string>Icon{name}</string>',
            f'{indent}\t\t</array>',
            f'{indent}\t\t<key>UIPrerenderedIcon</key>',
            f'{indent}\t\t<false/>',
            f'{indent}\t</dict>',
        ]
    lines.append(f'{indent}</dict>')
    return '\n'.join(lines)


def sync_ios_plist():
    plist = open(IOS_PLIST, encoding='utf-8').read()
    key = re.search(r'([ \t]*)<key>CFBundleAlternateIcons</key>\s*<dict>', plist)
    if key is None:
        raise SystemExit('Info.plist has no CFBundleAlternateIcons dictionary')
    depth = 1
    position = key.end()
    for tag in re.finditer(r'<dict>|</dict>', plist[position:]):
        depth += 1 if tag.group(0) == '<dict>' else -1
        if depth == 0:
            end = position + tag.end()
            break
    else:
        raise SystemExit('Info.plist CFBundleAlternateIcons dictionary is not closed')
    updated = plist[:key.start()] + ios_alternates_block(key.group(1)) + plist[end:]
    write_text(IOS_PLIST, updated)


def pbx_id(kind, filename):
    return hashlib.md5(f'promax-icon-{kind}:{filename}'.encode()).hexdigest()[:24].upper()


def insert_after_last(lines, pattern, line):
    matches = [i for i, existing in enumerate(lines) if re.match(pattern, existing)]
    if not matches:
        raise SystemExit(f'project.pbxproj has no line matching {pattern}')
    lines.insert(matches[-1] + 1, line)


def sync_ios_project():
    lines = open(IOS_PROJECT, encoding='utf-8').read().split('\n')
    icon = r'Icon\w+@\dx\.png'
    for name in ALTERNATES:
        for scale in (2, 3):
            filename = f'Icon{name}@{scale}x.png'
            if any(f'/* {filename} */' in line for line in lines):
                continue
            build, ref = pbx_id('build', filename), pbx_id('ref', filename)
            insert_after_last(
                lines,
                rf'\t\t[0-9A-F]{{24}} /\* {icon} in Resources \*/ = {{isa = PBXBuildFile;',
                f'\t\t{build} /* {filename} in Resources */ = {{isa = PBXBuildFile; fileRef = {ref} /* {filename} */; }};',
            )
            insert_after_last(
                lines,
                rf'\t\t[0-9A-F]{{24}} /\* {icon} \*/ = {{isa = PBXFileReference;',
                f'\t\t{ref} /* {filename} */ = {{isa = PBXFileReference; lastKnownFileType = image.png; path = "{filename}"; sourceTree = "<group>"; }};',
            )
            insert_after_last(lines, rf'\t\t\t\t[0-9A-F]{{24}} /\* {icon} \*/,$', f'\t\t\t\t{ref} /* {filename} */,')
            insert_after_last(
                lines,
                rf'\t\t\t\t[0-9A-F]{{24}} /\* {icon} in Resources \*/,$',
                f'\t\t\t\t{build} /* {filename} in Resources */,',
            )
    write_text(IOS_PROJECT, '\n'.join(lines))


def adaptive_icon_xml(background, foreground):
    return (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        f'  <background android:drawable="{background}"/>\n'
        f'  {foreground}\n'
        '  <monochrome>\n'
        '      <inset\n'
        '          android:drawable="@drawable/ic_launcher_monochrome"\n'
        '          android:inset="16%" />\n'
        '  </monochrome>\n'
        '</adaptive-icon>\n'
    )


def gradient_xml(top, bottom):
    return (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<shape xmlns:android="http://schemas.android.com/apk/res/android"\n'
        '    android:shape="rectangle">\n'
        '    <gradient\n'
        '        android:angle="270"\n'
        f'        android:startColor="{hex_color(top)}"\n'
        f'        android:endColor="{hex_color(bottom)}"\n'
        '        android:type="linear" />\n'
        '</shape>\n'
    )


def save_android_alternates():
    for name in ALTERNATES:
        res = resource_name(name)
        for density, scale in ANDROID_DENSITIES.items():
            legacy = round(ANDROID_LEGACY_DP * scale)
            path = os.path.join(ANDROID_RES, f'mipmap-{density}', f'{res}.png')
            os.makedirs(os.path.dirname(path), exist_ok=True)
            full_bleed(name, legacy).save(path, optimize=True)
            layer = round(ANDROID_LAYER_DP * scale)
            drawables = os.path.join(ANDROID_RES, f'drawable-{density}')
            os.makedirs(drawables, exist_ok=True)
            if name in VARIANTS:
                variant_foreground(VARIANTS[name], layer).save(
                    os.path.join(drawables, f'{res}_foreground.png'), optimize=True)
            else:
                artwork_layer(ARTWORKS[name], layer).save(
                    os.path.join(drawables, f'{res}_background.png'), optimize=True)
        if name in VARIANTS:
            write_text(
                os.path.join(ANDROID_RES, 'drawable', f'{res}_background.xml'),
                gradient_xml(*VARIANTS[name]['background']),
            )
            foreground = (
                '<foreground>\n'
                '      <inset\n'
                f'          android:drawable="@drawable/{res}_foreground"\n'
                '          android:inset="16%" />\n'
                '  </foreground>'
            )
        else:
            foreground = '<foreground android:drawable="@android:color/transparent"/>'
        write_text(
            os.path.join(ANDROID_RES, 'mipmap-anydpi-v26', f'{res}.xml'),
            adaptive_icon_xml(f'@drawable/{res}_background', foreground),
        )


def save_windows_alternates():
    os.makedirs(WINDOWS_RESOURCES, exist_ok=True)
    for name in ALTERNATES:
        frames = [full_bleed(name, size).convert('RGBA') for size in WINDOWS_ICO_SIZES]
        largest = frames[-1]
        largest.save(
            os.path.join(WINDOWS_RESOURCES, f'app_icon_{name.lower()}.ico'),
            format='ICO',
            sizes=[(size, size) for size in WINDOWS_ICO_SIZES],
            append_images=frames[:-1],
        )


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


def installer_panel(width, height):
    image = vertical_gradient(width, height, *VARIANTS['Glass']['background'])
    size = round(width * 0.56)
    alpha = Image.new('L', (width, height), 0)
    alpha.paste(mark_alpha(size), ((width - size) // 2, round(height * 0.4 - size / 2)))
    return glass(image, alpha, size)


def installer_badge(size):
    big = size * 4
    mask = Image.new('L', (big, big), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, big - 1, big - 1], radius=round(big * 0.225), fill=255)
    badge = compose(size, VARIANTS['Glass']).convert('RGBA')
    badge.putalpha(mask.resize((size, size), Image.LANCZOS))
    return badge


def save_installer_images():
    for scale, (width, height) in INSTALLER_PANELS.items():
        path = os.path.join(INSTALLER_DIR, f'wizard_image_{scale}.png')
        installer_panel(width, height).save(path, optimize=True)
    for scale, size in INSTALLER_BADGES.items():
        installer_badge(size).save(os.path.join(INSTALLER_DIR, f'wizard_small_{scale}.png'), optimize=True)


if __name__ == '__main__':
    if '--installer-only' not in sys.argv:
        save_mark()
        save_previews()
        save_ios_alternates()
        save_android_alternates()
        save_windows_alternates()
        if '--skip-primary' not in sys.argv:
            save_primary()
    save_installer_images()
