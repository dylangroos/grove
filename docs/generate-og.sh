#!/usr/bin/env bash
#
# Generate docs/og.png — OG image for grove.wtf
# Requires: python3 with Pillow (pip install Pillow)
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUT="$SCRIPT_DIR/og.png"

python3 -c "
from PIL import Image, ImageDraw, ImageFont

W, H = 1200, 630
bg = (10, 26, 15)        # --bg: #0a1a0f
green = (76, 175, 80)    # --accent: #4caf50
bright = (102, 187, 106) # --accent-bright: #66bb6a
dim = (138, 173, 142)    # --text-dim: #8aad8e
white = (224, 242, 225)  # --text: #e0f2e1

img = Image.new('RGB', (W, H), bg)
draw = ImageDraw.Draw(img)

# Try monospace fonts in order of preference
import os
font_paths = [
    '/Library/Fonts/SF-Mono-Bold.otf',
    '/System/Library/Fonts/Menlo.ttc',
    '/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf',
    '/usr/share/fonts/truetype/liberation/LiberationMono-Bold.ttf',
]

def load_font(size):
    for fp in font_paths:
        if os.path.exists(fp):
            try:
                return ImageFont.truetype(fp, size)
            except Exception:
                continue
    return ImageFont.load_default()

font_title = load_font(72)
font_tag = load_font(30)
font_url = load_font(26)

# Title
draw.text((W // 2, 220), 'grove', fill=bright, font=font_title, anchor='mm')

# Tagline
draw.text((W // 2, 320), 'Run coding agents in parallel', fill=dim, font=font_tag, anchor='mm')
draw.text((W // 2, 360), 'across git worktrees.', fill=dim, font=font_tag, anchor='mm')

# URL
draw.text((W // 2, 500), 'grove.wtf', fill=green, font=font_url, anchor='mm')

# Subtle top/bottom border lines
draw.line([(40, 40), (W - 40, 40)], fill=(30, 58, 40), width=1)
draw.line([(40, H - 40), (W - 40, H - 40)], fill=(30, 58, 40), width=1)

img.save('$OUT')
print('Generated: $OUT')
"

echo "Done: $OUT ($(du -h "$OUT" | cut -f1))"
