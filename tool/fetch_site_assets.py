from pathlib import Path
import urllib.request


repository = Path(__file__).resolve().parent.parent
root = repository / 'server/promax-hub/site/assets'
for folder in ['fonts', 'screens', 'licenses']:
    (root / folder).mkdir(exist_ok=True)
for name in ['Inter', 'Unbounded']:
    (root / 'fonts' / f'{name}.ttf').write_bytes((repository / f'assets/fonts/{name}.ttf').read_bytes())
for name in ['chat', 'themes', 'privacy', 'transfer']:
    (root / 'screens' / f'{name}.png').write_bytes((repository / f'media/promo/assets/{name}.png').read_bytes())
for name, slug, identifier in [('windows', 'windows-logo', 147204), ('android', 'android-logo', 147319), ('apple', 'apple-logo', 147318)]:
    url = f'https://images.icon-icons.com/2429/PNG/512/{slug.replace("-", "_")}_icon_{identifier}.png'
    request = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0', 'Referer': f'https://icon-icons.com/icon/{slug}/{identifier}'})
    (root / 'icons' / f'{name}.png').write_bytes(urllib.request.urlopen(request, timeout=20).read())
    print(name, url)
(root / 'licenses' / 'Apache-2.0.txt').write_bytes(urllib.request.urlopen('https://www.apache.org/licenses/LICENSE-2.0.txt', timeout=20).read())
