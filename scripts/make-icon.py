#!/usr/bin/env python3
"""Draws the Bus Stop app icon and writes every size the app and docs need.

The design follows docs/SPEC.md section 4.6: a turquoise glass bus-stop sign
with a USB-C port on its plate, on a near-black continuous-corner squircle.
The squircle is 824 px wide inside a transparent 1024 px canvas, the margin
macOS 26 and 27 expect, so the system does not put the icon on a grey plate.

Everything is drawn at four times the final size and scaled down with
Lanczos filtering for clean edges.

Usage: python3 scripts/make-icon.py

Writes:
    Support/AppIcon.icns       16 to 1024 px (all ten iconset slots)
    docs/images/icon.png       1024 px
    docs/images/icon-256.png   256 px

Needs Pillow (pip install Pillow).
"""

from __future__ import annotations

import io
import math
import struct
import sys
from pathlib import Path

try:
    from PIL import Image, ImageChops, ImageDraw, ImageFilter
except ImportError:  # pragma: no cover - a message beats a traceback here
    sys.exit("make-icon.py needs Pillow: python3 -m pip install Pillow")

ROOT = Path(__file__).resolve().parent.parent
SCALE = 4
SIZE = 1024
CANVAS = SIZE * SCALE

# Lagoon palette (docs/SPEC.md section 4.2).
ACCENT = (62, 230, 212)        # #3EE6D4
ACCENT_DEEP = (15, 163, 160)   # #0FA3A0
ACCENT_GLOW = (138, 255, 243)  # #8AFFF3
ACCENT_PALE = (201, 255, 249)  # #C9FFF9
BACKGROUND_TOP = (10, 20, 21)  # #0A1415
BACKGROUND_BOTTOM = (3, 6, 7)  # #030607
INK = (3, 17, 17)              # near-black for the glyph

Box = tuple[float, float, float, float]


# MARK: Geometry helpers (all in 1024-px units, scaled when drawn)

def px(value: float) -> int:
    """A length in final pixels, in supersampled pixels."""
    return int(round(value * SCALE))


def box(left: float, top: float, right: float, bottom: float) -> Box:
    return (left * SCALE, top * SCALE, right * SCALE, bottom * SCALE)


def blank_mask() -> Image.Image:
    return Image.new("L", (CANVAS, CANVAS), 0)


def squircle_mask(centre: float, half: float, exponent: float = 5.0) -> Image.Image:
    """A superellipse |x|^n + |y|^n <= 1, the continuous-corner shape of
    macOS app icons."""
    points = []
    steps = 2048
    for i in range(steps):
        t = 2 * math.pi * i / steps
        c, s = math.cos(t), math.sin(t)
        x = math.copysign(abs(c) ** (2 / exponent), c)
        y = math.copysign(abs(s) ** (2 / exponent), s)
        points.append(((centre + half * x) * SCALE, (centre + half * y) * SCALE))
    mask = blank_mask()
    ImageDraw.Draw(mask).polygon(points, fill=255)
    return mask


def rounded_mask(rect: Box, radius: float) -> Image.Image:
    mask = blank_mask()
    ImageDraw.Draw(mask).rounded_rectangle(rect, radius=px(radius), fill=255)
    return mask


def ellipse_mask(rect: Box) -> Image.Image:
    mask = blank_mask()
    ImageDraw.Draw(mask).ellipse(rect, fill=255)
    return mask


def scaled(mask: Image.Image, factor: float) -> Image.Image:
    """Multiplies a mask's values by `factor` (0...1)."""
    return mask.point(lambda v: int(round(v * factor)))


def blurred(mask: Image.Image, radius: float) -> Image.Image:
    return mask.filter(ImageFilter.GaussianBlur(px(radius)))


def ramp(top: float, bottom: float, start: float = 0, end: float = SIZE) -> Image.Image:
    """A vertical greyscale ramp from `top` to `bottom` (0...1) between rows
    `start` and `end`, flat outside them."""
    column = Image.new("L", (1, CANVAS))
    values = []
    for row in range(CANVAS):
        y = row / SCALE
        t = min(1.0, max(0.0, (y - start) / max(1e-6, end - start)))
        t = t * t * (3 - 2 * t)  # smoothstep
        values.append(int(round(255 * (top + (bottom - top) * t))))
    column.putdata(values)
    return column.resize((CANVAS, CANVAS), Image.Resampling.NEAREST)


def horizontal_ramp(left: float, right: float, start: float, end: float, centre_peak: bool) -> Image.Image:
    """A horizontal ramp, or a centre-bright profile when `centre_peak`."""
    row_image = Image.new("L", (CANVAS, 1))
    values = []
    for column in range(CANVAS):
        x = column / SCALE
        t = min(1.0, max(0.0, (x - start) / max(1e-6, end - start)))
        if centre_peak:
            t = 1 - abs(2 * t - 1)
        values.append(int(round(255 * (left + (right - left) * t))))
    row_image.putdata(values)
    return row_image.resize((CANVAS, CANVAS), Image.Resampling.NEAREST)


def gradient_fill(top_colour: tuple[int, int, int], bottom_colour: tuple[int, int, int],
                  start: float, end: float) -> Image.Image:
    """An opaque RGB image with a vertical colour gradient."""
    top = Image.new("RGB", (CANVAS, CANVAS), top_colour)
    bottom = Image.new("RGB", (CANVAS, CANVAS), bottom_colour)
    return Image.composite(bottom, top, ramp(0, 1, start, end))


def layer(colour: tuple[int, int, int] | Image.Image, alpha: Image.Image) -> Image.Image:
    """An RGBA layer of a flat colour or an RGB image, with the given alpha."""
    if isinstance(colour, Image.Image):
        result = colour.convert("RGBA")
    else:
        result = Image.new("RGBA", (CANVAS, CANVAS), colour + (0,))
    result.putalpha(alpha)
    return result


def multiply(*masks: Image.Image) -> Image.Image:
    result = masks[0]
    for mask in masks[1:]:
        result = ImageChops.multiply(result, mask)
    return result


# MARK: Drawing

def draw_icon() -> Image.Image:
    canvas = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))

    def add(colour, alpha):
        nonlocal canvas
        canvas = Image.alpha_composite(canvas, layer(colour, alpha))

    # Background squircle with a subtle vertical gradient.
    tile = squircle_mask(512, 412)
    add(gradient_fill(BACKGROUND_TOP, BACKGROUND_BOTTOM, 100, 924), tile)

    # Ambient turquoise light behind the sign.
    ambient = blurred(ellipse_mask(box(262, 200, 762, 620)), 140)
    add(ACCENT_DEEP, multiply(scaled(ambient, 0.20), tile))

    # Inner glow along the edges, mostly at the top.
    edge_glow = ImageChops.subtract(tile, blurred(tile, 16))
    add(ACCENT, multiply(scaled(edge_glow, 0.40), ramp(1.0, 0.15, 100, 700)))

    # Thin rim light, bright at the top and fading towards the bottom.
    rim = ImageChops.subtract(tile, squircle_mask(512, 409.5))
    rim = blurred(rim, 0.6)
    add(ACCENT_GLOW, multiply(rim, ramp(0.95, 0.22, 100, 924)))

    # Plate and pole geometry.
    plate_rect = box(244, 226, 780, 562)
    plate_radius = 80
    pole_top, pole_bottom = 548, 812

    # Soft glow on the ground where the pole stands, brightest at its foot.
    ground = blurred(ellipse_mask(box(392, 790, 632, 834)), 18)
    add(ACCENT, multiply(scaled(ground, 0.45), tile))
    core = blurred(ellipse_mask(box(462, 800, 562, 824)), 8)
    add(ACCENT_GLOW, multiply(scaled(core, 0.55), tile))

    # Pole: a cylinder, brighter along its centre line, fading into the glow.
    pole = blank_mask()
    ImageDraw.Draw(pole).rectangle(box(490, pole_top, 534, pole_bottom), fill=255)
    pole_shade = horizontal_ramp(0.30, 1.0, 490, 534, centre_peak=True)
    pole_colour = Image.composite(Image.new("RGB", (CANVAS, CANVAS), ACCENT_GLOW),
                                  Image.new("RGB", (CANVAS, CANVAS), ACCENT_DEEP), pole_shade)
    add(pole_colour, multiply(pole, ramp(1.0, 0.25, 720, pole_bottom)))

    # Glow under the plate.
    plate = rounded_mask(plate_rect, plate_radius)
    plate_glow = blurred(rounded_mask(box(268, 270, 756, 590), plate_radius), 46)
    add(ACCENT, multiply(scaled(plate_glow, 0.55), tile))

    # Plate: turquoise glass.
    add(gradient_fill(ACCENT, ACCENT_DEEP, 226, 562), plate)

    # A darker band along the bottom edge gives the glass some thickness.
    depth = ImageChops.subtract(plate, rounded_mask(box(244, 214, 780, 550), plate_radius))
    add(ACCENT_DEEP, scaled(blurred(depth, 3), 0.65))

    # Glass edge: a bright inner border, strongest at the top.
    inner = rounded_mask(box(250, 232, 774, 556), plate_radius - 6)
    border = ImageChops.subtract(plate, inner)
    add(ACCENT_PALE, multiply(scaled(blurred(border, 0.8), 0.9), ramp(1.0, 0.15, 226, 562)))
    # Light caught by the bottom edge, as on Liquid Glass.
    bottom_edge = multiply(border, ramp(0.0, 1.0, 470, 562))
    add(ACCENT_GLOW, scaled(blurred(bottom_edge, 1), 0.45))

    # Specular highlight along the top edge, curving down at the corners.
    sheen_shape = multiply(plate, ellipse_mask(box(120, -60, 904, 430)))
    sheen = multiply(sheen_shape, ramp(0.58, 0.0, 226, 350))
    add((255, 255, 255), blurred(sheen, 2))
    streak = multiply(rounded_mask(box(296, 238, 728, 248), 5), horizontal_ramp(0.0, 1.0, 296, 728, True))
    add((255, 255, 255), scaled(blurred(streak, 2), 0.9))

    # USB-C port glyph: a dark rounded slot with the connector tongue inside.
    slot = rounded_mask(box(346, 332, 678, 458), 63)
    add(INK, slot)
    # Lower lip of the slot catches a little light.
    lip = ImageChops.subtract(slot, rounded_mask(box(346, 326, 678, 452), 63))
    add(ACCENT_GLOW, scaled(blurred(lip, 1), 0.30))
    tongue = rounded_mask(box(416, 380, 608, 412), 16)
    add(gradient_fill(ACCENT_GLOW, ACCENT, 380, 412), tongue)

    return canvas


# MARK: Output

# Iconset slots in the order iconutil writes them: (OSType, pixel size).
ICNS_SLOTS = [
    (b"icp4", 16),    # icon_16x16
    (b"ic11", 32),    # icon_16x16@2x
    (b"icp5", 32),    # icon_32x32
    (b"ic12", 64),    # icon_32x32@2x
    (b"ic07", 128),   # icon_128x128
    (b"ic13", 256),   # icon_128x128@2x
    (b"ic08", 256),   # icon_256x256
    (b"ic14", 512),   # icon_256x256@2x
    (b"ic09", 512),   # icon_512x512
    (b"ic10", 1024),  # icon_512x512@2x
]


def resized(image: Image.Image, size: int) -> Image.Image:
    if image.width == size:
        return image
    result = image.resize((size, size), Image.Resampling.LANCZOS)
    if size <= 32:
        # Small sizes lose contrast when scaled down; sharpen them a little.
        result = result.filter(ImageFilter.UnsharpMask(radius=0.6, percent=60, threshold=1))
    return result


def png_bytes(image: Image.Image) -> bytes:
    buffer = io.BytesIO()
    image.save(buffer, format="PNG", optimize=True)
    return buffer.getvalue()


def write_icns(image: Image.Image, path: Path) -> None:
    """Writes an .icns container with PNG data in every iconset slot."""
    cache: dict[int, bytes] = {}
    chunks = []
    for ostype, size in ICNS_SLOTS:
        if size not in cache:
            cache[size] = png_bytes(resized(image, size))
        data = cache[size]
        chunks.append(ostype + struct.pack(">I", len(data) + 8) + data)
    body = b"".join(chunks)
    path.write_bytes(b"icns" + struct.pack(">I", len(body) + 8) + body)


def main() -> None:
    art = draw_icon().resize((SIZE, SIZE), Image.Resampling.LANCZOS)

    support = ROOT / "Support"
    images = ROOT / "docs" / "images"
    support.mkdir(parents=True, exist_ok=True)
    images.mkdir(parents=True, exist_ok=True)

    art.save(images / "icon.png", optimize=True)
    resized(art, 256).save(images / "icon-256.png", optimize=True)
    write_icns(art, support / "AppIcon.icns")

    for path in (support / "AppIcon.icns", images / "icon.png", images / "icon-256.png"):
        print(f"wrote {path.relative_to(ROOT)} ({path.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
