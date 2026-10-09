#!/usr/bin/env python3
"""Draws the installer window background (Resources/dmg-background.png).

The result is committed, so building a DMG does not need Pillow; run this only to change the art:
    python3 Scripts/make-dmg-background.py

The PNG is drawn at 2x and tagged 144 dpi, which Finder shows as a sharp 660x400pt background.
Icon centres are fixed by Scripts/make-dmg.sh: app at (170, 185), Applications at (490, 185).

The art is deliberately light: Finder draws the icon labels in dark text over a background picture
whatever the system appearance, so a dark background would swallow the app and folder names.
"""
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "Resources" / "dmg-background.png"

W, H = 660, 400            # window content size in points
SCALE = 2                  # drawn at 2x, downsampled for the 1x image

MINT = (62, 168, 104)       # deeper than the app's mint so it holds up on a light ground
INK = (29, 29, 31)
GRAY = (110, 110, 115)
DIM = (150, 150, 156)

FONT_TEXT = "/System/Library/Fonts/SFNS.ttf"
FONT_ROUNDED = "/System/Library/Fonts/SFNSRounded.ttf"


def font(path: str, size: float, weight: str) -> ImageFont.FreeTypeFont:
    f = ImageFont.truetype(path, int(size * SCALE))
    try:
        f.set_variation_by_name(weight)
    except Exception:
        pass
    return f


def text_centered(draw: ImageDraw.ImageDraw, x: float, y: float, text: str, f, fill) -> None:
    box = draw.textbbox((0, 0), text, font=f)
    draw.text((x * SCALE - (box[2] - box[0]) / 2 - box[0], y * SCALE - (box[3] - box[1]) / 2 - box[1]), text, font=f, fill=fill)


def render() -> Image.Image:
    w, h = W * SCALE, H * SCALE
    img = Image.new("RGB", (w, h), (0, 0, 0))

    # Soft off-white, a touch darker towards the bottom
    px = ImageDraw.Draw(img)
    for y in range(h):
        t = y / h
        v = int(250 - 14 * t)
        px.line([(0, y), (w, y)], fill=(v, v, v + 1))

    # A faint mint halo behind the arrow
    from PIL import ImageChops
    glow = Image.new("RGB", (w, h), (0, 0, 0))
    ImageDraw.Draw(glow).ellipse(
        [(w / 2 - 150 * SCALE), (185 * SCALE - 60 * SCALE), (w / 2 + 150 * SCALE), (185 * SCALE + 60 * SCALE)],
        fill=(14, 3, 10),
    )
    glow = glow.filter(ImageFilter.GaussianBlur(45 * SCALE))
    img = ImageChops.subtract(img, glow)

    d = ImageDraw.Draw(img)

    # Heading
    text_centered(d, W / 2, 50, "One Percent", font(FONT_ROUNDED, 26, "Semibold"), INK)
    text_centered(d, W / 2, 80, "Drag it into Applications to install", font(FONT_TEXT, 13, "Regular"), GRAY)

    # Three chevrons, dim to mint, pointing from the app to the Applications folder
    cy = 185 * SCALE
    for i, (cx, colour, width) in enumerate([(285, (205, 205, 210), 3.0), (330, (150, 196, 170), 3.0), (375, MINT, 3.4)]):
        x = cx * SCALE
        half = 15 * SCALE
        d.line([(x - half / 2, cy - half), (x + half / 2, cy), (x - half / 2, cy + half)], fill=colour,
               width=int(width * SCALE), joint="curve")
        for tip in [(x - half / 2, cy - half), (x - half / 2, cy + half), (x + half / 2, cy)]:
            r = width * SCALE / 2
            d.ellipse([tip[0] - r, tip[1] - r, tip[0] + r, tip[1] + r], fill=colour)

    # Gatekeeper hint: the build is ad-hoc signed, so the very first launch needs right-click > Open
    text_centered(d, W / 2, 352, "First launch: right-click One Percent, then choose Open", font(FONT_TEXT, 11, "Regular"), DIM)
    return img


def main() -> int:
    big = render()
    OUT.parent.mkdir(parents=True, exist_ok=True)
    big.save(OUT, dpi=(144, 144))
    if (ROOT / "build").exists():
        big.save(ROOT / "build" / "dmg-background-preview.png")
    print(f"wrote {OUT.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
