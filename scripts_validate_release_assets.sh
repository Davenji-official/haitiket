#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
ASSET_DIR="$ROOT/assets"
if [ ! -d "$ASSET_DIR" ]; then ASSET_DIR="$ROOT/lib/assets"; fi
python3 - "$ASSET_DIR" <<'PY'
import struct, sys
from pathlib import Path
root=Path(sys.argv[1])
required_png=('logo.png','logo_t.png')
required_mascots=('mascots/profile.webp','mascots/seller.webp','mascots/messages.webp',
                  'mascots/support.webp','mascots/welcome.webp','mascots/badge.webp',
                  'mascots/boutiques.webp','mascots/notifications.webp','mascots/orders.webp',
                  'mascots/cart.webp','mascots/bazar.webp','mascots/admin.webp',
                  'mascots/home.webp','mascots/wallet.webp')
errors=[]
for name in required_png:
    path=root/name
    if not path.is_file():
        errors.append(f'Missing required brand asset: {path}')
        continue
    data=path.read_bytes()
    if len(data)<24 or data[:8]!=b'\x89PNG\r\n\x1a\n':
        errors.append(f'Invalid PNG file: {path}')
        continue
    width,height=struct.unpack('>II',data[16:24])
    if width<64 or height<64:
        errors.append(f'PNG dimensions suspiciously small ({width}x{height}): {path}')
for name in required_mascots:
    path=root/name
    if not path.is_file():
        errors.append(f'Missing required mascot asset: {path}')
        continue
    data=path.read_bytes()
    if len(data)<100 or data[:4]!=b'RIFF' or data[8:12]!=b'WEBP':
        errors.append(f'Invalid or suspiciously small WebP: {path}')
if errors:
    print('\n'.join('ERROR: '+e for e in errors), file=sys.stderr)
    raise SystemExit(1)
print(f'Release assets OK: {len(required_png)} PNG brand logos and {len(required_mascots)} WebP mascot files in {root}')
PY
