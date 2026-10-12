#!/usr/bin/env python3
"""Generate the app icon: Resources/AppIcon.svg (vector master) and
Resources/AppIcon.icns (every macOS size, rendered natively from the vector).

The design is a frosted-glass response letter: the three-column table the
app exports, with a black section band across the top, an ID column of
triage dots (green, yellow, red), the reviewers' comments in grey lines and
the responses in ink-blue lines, sealed with an indigo badge carrying a
white reply arrow. It is drawn in the macOS 26 Liquid Glass style, in the
"Slate" palette (pale silver to slate blue-grey), and follows the icons of
QDVC Progress, Meetings, Nice Mail, Bibliotheca and GTD EML for macOS, so
the apps look like a family.

Geometry follows Apple's macOS icon template: a 1024x1024 canvas holding an
824x824 tile (100 px transparent margin) with a 185.4 px continuous-curvature
("squircle") corner, plus a soft drop shadow. The corner is the curve UIKit
draws for continuous corners, as reverse-engineered and published by PaintCode
(https://www.paintcodeapp.com/blogpost/code-for-ios-7-rounded-rectangles).

Usage:

    python3 tools/make_icon.py            # writes Resources/AppIcon.{svg,icns}
    python3 tools/make_icon.py --preview  # also writes build/icon-preview.png

Requires rsvg-convert (macOS: `brew install librsvg`; Debian/Ubuntu:
`apt install librsvg2-bin`). No other dependencies; the .icns is written
directly, so Apple's iconutil is not needed.
"""

import argparse
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RESOURCES = ROOT / "Resources"

# ---------------------------------------------------------------------------
# Palette ("Slate"). The deep tone also tints the card's shadows, so the
# white glass stays distinct from the pale background.

BG_TOP = "#F1F4F9"
BG_DEEP = "#5F6F8E"

# The app's own colours (Sources/QDVCResponseLetter/Style.swift).
TRIAGE = ["#34C759", "#FFCC00", "#FF3B30"]
COMMENT_INK = "#9AA3B5"
RESPONSE_INK = "#2F5AA8"
BAND = "#14161C"

# The seal: an indigo sphere with a white reply arrow.
FACE_LIGHT, FACE_MID, FACE_DARK = "#8C8DF5", "#4B4ACF", "#25247A"
FEATURES = "#FFFFFF"

# ---------------------------------------------------------------------------
# Apple's template geometry.

TILE_ORIGIN, TILE_SIZE, CORNER_RADIUS = 100, 824, 185.4
SHADOW_BLUR_RADIUS, SHADOW_OFFSET_Y, SHADOW_OPACITY = 28, 12, 0.5

# Continuous-corner segments around the top-right corner, in units of the
# radius: (distance from the right edge, distance from the top edge).
_CORNER = [
    ("L", (1.52866471, 0.0)),
    ("C", (1.08849323, 0.0), (0.86840689, 0.0), (0.66993427, 0.06549600)),
    ("L", (0.63149399, 0.07491100)),
    ("C", (0.37282392, 0.16905899), (0.16906013, 0.37282401), (0.07491176, 0.63149399)),
    ("C", (0.0, 0.86840701), (0.0, 1.08849299), (0.0, 1.52866483)),
]


def continuous_rounded_rect(x, y, w, h, r):
    """SVG path of a rounded rectangle with Apple's continuous corners."""
    r = min(r, min(w, h) / 2 / 1.52866483)
    corners = [
        lambda u, v: (x + w - u * r, y + v * r),        # top-right
        lambda u, v: (x + w - v * r, y + h - u * r),    # bottom-right
        lambda u, v: (x + u * r, y + h - v * r),        # bottom-left
        lambda u, v: (x + v * r, y + u * r),            # top-left
    ]

    def fmt(p):
        return f"{p[0]:.2f},{p[1]:.2f}"

    d = [f"M{fmt((x + 1.52866483 * r, y))}"]
    for corner in corners:
        for seg in _CORNER:
            if seg[0] == "L":
                d.append("L" + fmt(corner(*seg[1])))
            else:
                d.append("C" + " ".join(fmt(corner(*p)) for p in seg[1:]))
    d.append("Z")
    return " ".join(d)


TILE = continuous_rounded_rect(TILE_ORIGIN, TILE_ORIGIN, TILE_SIZE, TILE_SIZE, CORNER_RADIUS)

# The card (x, y, width, height) and the seal's radius. The seal sits on the
# card's lower right corner.
CARD = (196, 250, 592, 488)
SEAL_RADIUS = 118


def _hex2rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def _mix(a, b, t):
    ra, rb = _hex2rgb(a), _hex2rgb(b)
    return "#%02X%02X%02X" % tuple(round(x + (y - x) * t) for x, y in zip(ra, rb))


# Rows: (triage index, comment line widths, response line widths), as
# fractions of each column.
ROWS = [
    (0, [1.0, 0.7], [1.0, 0.9, 0.55]),
    (1, [0.95, 1.0, 0.5], [1.0, 0.75]),
    (2, [1.0, 0.6], [0.9, 1.0, 0.4]),
]


def _card():
    """The frosted-glass table card. Returns (elements, seal centre)."""
    x, y, w, h = CARD
    pad = 44
    id_w, gap = 74, 22
    inner_w = w - 2 * pad
    col_w = (inner_w - id_w - 2 * gap) / 2
    c_id = x + pad
    c_com = c_id + id_w + gap
    c_res = c_com + col_w + gap
    parts = [f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="56" fill="url(#glass)"/>']

    # The black section band, its heading in white in the second column.
    band_y, band_h = y + 48, 46
    parts.append(f'<rect x="{x + pad - 8}" y="{band_y}" width="{inner_w + 16}" height="{band_h}" rx="14" fill="{BAND}"/>')
    parts.append(f'<rect x="{c_com}" y="{band_y + 16}" width="{col_w * 0.72:.1f}" height="14" rx="7" fill="#FFFFFF"/>')

    line_h, line_gap = 14, 12
    yy = band_y + band_h + 30
    for i, (tri, comment, response) in enumerate(ROWS):
        n = max(len(comment), len(response))
        row_h = n * line_h + (n - 1) * line_gap
        # Triage dot in the ID column.
        parts.append(f'<circle cx="{c_id + id_w / 2:.1f}" cy="{yy + 13}" r="17" fill="{TRIAGE[tri]}"/>')
        for j, f in enumerate(comment):
            parts.append(f'<rect x="{c_com}" y="{yy + j * (line_h + line_gap)}" width="{col_w * f:.1f}" '
                         f'height="{line_h}" rx="7" fill="{COMMENT_INK}" fill-opacity="0.75"/>')
        for j, f in enumerate(response):
            parts.append(f'<rect x="{c_res}" y="{yy + j * (line_h + line_gap)}" width="{col_w * f:.1f}" '
                         f'height="{line_h}" rx="7" fill="{RESPONSE_INK}"/>')
        yy += row_h + 30
        if i < len(ROWS) - 1:
            parts.append(f'<rect x="{x + pad - 8}" y="{yy - 16}" width="{inner_w + 16}" height="3" rx="1.5" '
                         f'fill="{BG_DEEP}" fill-opacity="0.18"/>')
    # Column rules.
    for cx in (c_com - gap / 2, c_res - gap / 2):
        parts.append(f'<rect x="{cx - 1.5:.1f}" y="{band_y + band_h + 14}" width="3" height="{yy - band_y - band_h - 30}" '
                     f'rx="1.5" fill="{BG_DEEP}" fill-opacity="0.18"/>')

    # glass rim
    parts.append(f'<rect x="{x + 2}" y="{y + 2}" width="{w - 4}" height="{h - 4}" rx="54" fill="none" '
                 'stroke="url(#rim)" stroke-width="4"/>')
    return parts, (x + w - 46, y + h - 40)


def _seal(cx, cy, r):
    """A glossy indigo seal with a white reply arrow, in a white ring."""
    s = r * 0.55
    # A reply arrow: a curved shaft from lower right sweeping up and left,
    # ending in an arrowhead pointing left.
    shaft = (f'M{cx + s * 0.85:.1f},{cy + s * 0.75:.1f} '
             f'C{cx + s * 0.85:.1f},{cy - s * 0.15:.1f} {cx + s * 0.25:.1f},{cy - s * 0.30:.1f} '
             f'{cx - s * 0.45:.1f},{cy - s * 0.30:.1f}')
    tip = (cx - s * 0.95, cy - s * 0.30)
    head = (f'M{tip[0]:.1f},{tip[1]:.1f} L{tip[0] + s * 0.62:.1f},{tip[1] - s * 0.52:.1f} '
            f'L{tip[0] + s * 0.62:.1f},{tip[1] + s * 0.52:.1f} Z')
    return [
        f'<circle cx="{cx}" cy="{cy}" r="{r + 10}" fill="#FFFFFF" opacity="0.9"/>',
        f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="url(#face)"/>',
        f'<path d="{shaft}" fill="none" stroke="{FEATURES}" stroke-width="{r * 0.17:.1f}" stroke-linecap="round"/>',
        f'<path d="{head}" fill="{FEATURES}" stroke="{FEATURES}" stroke-width="{r * 0.06:.1f}" stroke-linejoin="round"/>',
        # specular highlight
        f'<ellipse cx="{cx - r * 0.30:.1f}" cy="{cy - r * 0.55:.1f}" rx="{r * 0.38:.1f}" '
        f'ry="{r * 0.18:.1f}" fill="#FFFFFF" opacity="0.40"/>',
    ]


def icon_svg():
    sigma = SHADOW_BLUR_RADIUS / 2
    defs = [
        f'<linearGradient id="bg" x1="0" y1="0" x2="0.35" y2="1">'
        f'<stop offset="0" stop-color="{BG_TOP}"/><stop offset="1" stop-color="{BG_DEEP}"/></linearGradient>',
        '<radialGradient id="glow" cx="0.30" cy="0.18" r="0.75">'
        '<stop offset="0" stop-color="#FFFFFF" stop-opacity="0.34"/>'
        '<stop offset="1" stop-color="#FFFFFF" stop-opacity="0"/></radialGradient>',
        '<linearGradient id="sheen" x1="0" y1="0" x2="0" y2="1">'
        '<stop offset="0" stop-color="#FFFFFF" stop-opacity="0.22"/>'
        '<stop offset="0.40" stop-color="#FFFFFF" stop-opacity="0.03"/>'
        '<stop offset="1" stop-color="#FFFFFF" stop-opacity="0"/></linearGradient>',
        '<linearGradient id="rim" x1="0" y1="0" x2="0" y2="1">'
        '<stop offset="0" stop-color="#FFFFFF" stop-opacity="0.9"/>'
        '<stop offset="0.5" stop-color="#FFFFFF" stop-opacity="0.3"/>'
        '<stop offset="1" stop-color="#FFFFFF" stop-opacity="0.6"/></linearGradient>',
        '<linearGradient id="edge" x1="0" y1="0" x2="0" y2="1">'
        '<stop offset="0" stop-color="#FFFFFF" stop-opacity="0.75"/>'
        '<stop offset="0.5" stop-color="#FFFFFF" stop-opacity="0.12"/>'
        '<stop offset="1" stop-color="#FFFFFF" stop-opacity="0.35"/></linearGradient>',
        '<linearGradient id="glass" x1="0" y1="0" x2="0" y2="1">'
        '<stop offset="0" stop-color="#FFFFFF" stop-opacity="0.78"/>'
        f'<stop offset="1" stop-color="{_mix("#FFFFFF", BG_DEEP, 0.25)}" stop-opacity="0.55"/></linearGradient>',
        '<linearGradient id="glassflap" x1="0" y1="0" x2="0" y2="1">'
        '<stop offset="0" stop-color="#FFFFFF" stop-opacity="0.95"/>'
        '<stop offset="1" stop-color="#FFFFFF" stop-opacity="0.62"/></linearGradient>',
        '<radialGradient id="face" cx="0.38" cy="0.30" r="0.8">'
        f'<stop offset="0" stop-color="{FACE_LIGHT}"/><stop offset="0.55" stop-color="{FACE_MID}"/>'
        f'<stop offset="1" stop-color="{FACE_DARK}"/></radialGradient>',
        f'<clipPath id="clip"><path d="{TILE}"/></clipPath>',
        # Apple template shadow: black, 28 px blur radius, 12 px down, 50 %.
        '<filter id="shadow" x="-20%" y="-20%" width="140%" height="140%">'
        f'<feGaussianBlur in="SourceAlpha" stdDeviation="{sigma}"/><feOffset dy="{SHADOW_OFFSET_Y}"/>'
        f'<feComponentTransfer><feFuncA type="linear" slope="{SHADOW_OPACITY}"/></feComponentTransfer>'
        '<feMerge><feMergeNode/><feMergeNode in="SourceGraphic"/></feMerge></filter>',
        # Tinted shadow under the card and seal.
        '<filter id="objshadow" x="-30%" y="-30%" width="160%" height="160%">'
        '<feGaussianBlur in="SourceAlpha" stdDeviation="14"/><feOffset dx="0" dy="16"/>'
        f'<feFlood flood-color="{BG_DEEP}" flood-opacity="0.55"/><feComposite operator="in" in2="SourceAlpha"/>'
        '<feMerge><feMergeNode/><feMergeNode in="SourceGraphic"/></feMerge></filter>',
    ]
    card, (cx, cy) = _card()
    objects = card + _seal(cx, cy, SEAL_RADIUS)
    parts = [
        f'<g filter="url(#shadow)"><path d="{TILE}" fill="url(#bg)"/></g>',
        '<g clip-path="url(#clip)">',
        '<rect x="100" y="100" width="824" height="824" fill="url(#glow)"/>',
        '<g filter="url(#objshadow)">', *objects, '</g>',
        '<rect x="100" y="100" width="824" height="824" fill="url(#sheen)"/>',
        '</g>',
        f'<path d="{TILE}" fill="none" stroke="url(#edge)" stroke-width="6"/>',
    ]
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">'
            f'<defs>{"".join(defs)}</defs>{"".join(parts)}</svg>\n')


# ---------------------------------------------------------------------------
# .icns writing. These are the element types `iconutil` emits for a standard
# .iconset; all of them hold PNG data.

ICNS_ELEMENTS = [
    ("icp4", 16), ("ic11", 32), ("icp5", 32), ("ic12", 64),
    ("ic07", 128), ("ic13", 256), ("ic08", 256), ("ic14", 512),
    ("ic09", 512), ("ic10", 1024),
]


def render_png(svg_path, size, out_path):
    subprocess.run(["rsvg-convert", "-w", str(size), "-h", str(size), str(svg_path), "-o", str(out_path)],
                   check=True)


def write_icns(pngs_by_size, out_path):
    chunks = b""
    for code, size in ICNS_ELEMENTS:
        data = pngs_by_size[size]
        chunks += code.encode("ascii") + struct.pack(">I", len(data) + 8) + data
    out_path.write_bytes(b"icns" + struct.pack(">I", len(chunks) + 8) + chunks)


def main():
    parser = argparse.ArgumentParser(description="Generate Resources/AppIcon.svg and AppIcon.icns.")
    parser.add_argument("--preview", action="store_true",
                        help="also write build/icon-preview.png (1024 px)")
    args = parser.parse_args()

    try:
        subprocess.run(["rsvg-convert", "--version"], check=True, capture_output=True)
    except (OSError, subprocess.CalledProcessError):
        sys.exit("error: rsvg-convert not found (macOS: brew install librsvg)")

    RESOURCES.mkdir(exist_ok=True)
    svg_path = RESOURCES / "AppIcon.svg"
    svg_path.write_text(icon_svg())

    with tempfile.TemporaryDirectory() as tmp:
        pngs = {}
        for size in sorted({s for _, s in ICNS_ELEMENTS}):
            png = Path(tmp) / f"icon_{size}.png"
            render_png(svg_path, size, png)
            pngs[size] = png.read_bytes()
        write_icns(pngs, RESOURCES / "AppIcon.icns")

    if args.preview:
        (ROOT / "build").mkdir(exist_ok=True)
        render_png(svg_path, 1024, ROOT / "build" / "icon-preview.png")
    print(f"Wrote {svg_path.relative_to(ROOT)} and Resources/AppIcon.icns")


if __name__ == "__main__":
    main()
