"""
Generate MotoPulse app icons for all Android mipmap densities.
Design: black background, red speedometer arc + needle, white "MP" text.
"""
from PIL import Image, ImageDraw, ImageFont
import math, os, shutil

def draw_icon(size):
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    pad = size * 0.04
    r = size - 2 * pad

    # Rounded rect background
    bg_radius = size * 0.22
    draw.rounded_rectangle([0, 0, size-1, size-1],
                            radius=bg_radius,
                            fill=(8, 8, 8, 255))

    cx, cy = size / 2, size / 2

    # ── Speedometer arc (220° sweep, starting at 160°) ─────────────────────
    arc_pad = size * 0.15
    arc_box = [arc_pad, arc_pad + size*0.04, size - arc_pad, size - arc_pad + size*0.04]
    arc_w = max(2, int(size * 0.055))

    # Background track
    draw.arc(arc_box, start=160, end=20, fill=(255,255,255,20), width=arc_w)

    # Active red arc (goes 0-80% of range for visual effect)
    draw.arc(arc_box, start=160, end=340, fill=(232, 0, 61, 220), width=arc_w)

    # ── Needle ──────────────────────────────────────────────────────────────
    # Angle: 160° start, goes to 290° (about 75% of 220°)
    needle_angle_deg = 160 + 220 * 0.75   # ≈ 325°
    needle_angle = math.radians(needle_angle_deg)
    arc_r = (size - 2*arc_pad) / 2
    needle_len = arc_r * 0.78
    # Center of arc
    arc_cx = (arc_box[0] + arc_box[2]) / 2
    arc_cy = (arc_box[1] + arc_box[3]) / 2
    nx = arc_cx + needle_len * math.cos(needle_angle)
    ny = arc_cy + needle_len * math.sin(needle_angle)
    nw = max(1, int(size * 0.025))
    draw.line([(arc_cx, arc_cy), (nx, ny)],
              fill=(255, 255, 255, 230), width=nw)
    # Centre dot
    dot_r = max(2, int(size * 0.04))
    draw.ellipse([arc_cx-dot_r, arc_cy-dot_r, arc_cx+dot_r, arc_cy+dot_r],
                 fill=(232, 0, 61, 255))

    # ── "MP" text ────────────────────────────────────────────────────────────
    font_size = int(size * 0.24)
    try:
        font = ImageFont.truetype("arialbd.ttf", font_size)
    except Exception:
        try:
            font = ImageFont.truetype("DejaVuSans-Bold.ttf", font_size)
        except Exception:
            font = ImageFont.load_default()

    text = "MP"
    bbox = draw.textbbox((0, 0), text, font=font)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    tx = (size - tw) / 2 - bbox[0]
    ty = size * 0.60 - bbox[1]
    draw.text((tx, ty), text, font=font, fill=(255, 255, 255, 240))

    # Small "MOTOPULSE" sub-label
    sub_size = max(8, int(size * 0.07))
    try:
        sub_font = ImageFont.truetype("arial.ttf", sub_size)
    except Exception:
        sub_font = font
    sub = "MOTOPULSE"
    sbbox = draw.textbbox((0, 0), sub, font=sub_font)
    sw = sbbox[2] - sbbox[0]
    sx = (size - sw) / 2 - sbbox[0]
    sy = size * 0.60 + th + size*0.02 - sbbox[1]
    draw.text((sx, sy), sub, font=sub_font,
              fill=(232, 0, 61, 200),
              spacing=2)

    return img


# Android mipmap sizes
SIZES = {
    'mipmap-mdpi':    48,
    'mipmap-hdpi':    72,
    'mipmap-xhdpi':   96,
    'mipmap-xxhdpi':  144,
    'mipmap-xxxhdpi': 192,
}

base = r'C:\Users\cecil\motopulse\android\app\src\main\res'

for folder, size in SIZES.items():
    out_dir = os.path.join(base, folder)
    os.makedirs(out_dir, exist_ok=True)
    icon = draw_icon(size)
    icon.save(os.path.join(out_dir, 'ic_launcher.png'))
    # Also save round variant
    icon.save(os.path.join(out_dir, 'ic_launcher_round.png'))
    print(f'  {folder}: {size}x{size} OK')

# Also save 512x512 for Play Store
large = draw_icon(512)
large.save(r'C:\Users\cecil\motopulse\icon_512.png')
print('  icon_512.png (Play Store) OK')
print('Done!')
