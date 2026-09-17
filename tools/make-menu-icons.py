#!/usr/bin/env python3
"""The CeroSec context-menu icon: three pixel-art candidates plus the judging
sheet (`planche.png`) that mocks up the real ISContextMenu row.

Why this exists: the owner saw the Computer Mod's context menu carry a small
icon left of its "Computer" entry (a blue-screen glyph, `media/textures/
files.PNG`, 32x32) and asked for the CeroSec equivalent. B42's
ISContextMenu.lua renders `option.iconTexture` at `iconSize = itemHgt - 12`,
itemHgt = fontHgt + padY*2 (UIFont.Medium, padY=6) -- effectively the text
line height, drawn with drawTextureScaledAspect (aspect-fit, any source
works). The Computer Mod and CeroSec's own existing item icon
(common/media/textures/Item_CeroSecRelay.png) both ship 32x32 sources, so
that is the native size used here: no fractional scale, matches the sibling
mod and the mod's own convention.

The palette comes straight from tools/cerosec_art.py (PHOSPHOR/PHOSPHOR_DIM/
CRT_BLACK/BONE), sampled off workshop/art/poster.png, so the icon is the same
green as the banner and wordmark, not a fresh guess.
"""

import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont, ImageFilter

REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO / "tools"))
from cerosec_art import PHOSPHOR, PHOSPHOR_DIM, CRT_BLACK, BONE  # noqa: E402

OUT_DIR = REPO / "42" / "media" / "ui"
# Candidates and the judging sheet are throwaway, never shipped: a plain
# shared /tmp path, not a path out of anybody's home directory.
SCRATCH = Path("/tmp/cerosec-menu-icons")
CANDIDATES_DIR = SCRATCH / "candidates"

# The chosen candidate (owner's call, 2026-09-17): the green terminal screen
# with ">_" lit inside, not the bare glyph. This is the only file the mod
# actually ships.
WINNER = "b"
WINNER_NAME = "cerosec-menu.png"

N = 16          # base grid, hand pixel art
SCALE = 2       # -> 32x32, the native size found in the report
SIZE = N * SCALE


def canvas():
    return Image.new("RGBA", (N, N), (0, 0, 0, 0))


def outline(img, colour, alpha=255):
    """1px contour in `colour` around the opaque pixels, drawn BEHIND them,
    so the icon reads on both the dark idle row and the lighter hover row."""
    a = img.split()[3]
    dil = a.filter(ImageFilter.MaxFilter(3))
    ring = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ring.paste(colour + (alpha,), (0, 0), dil)
    ring.paste((0, 0, 0, 0), (0, 0), a)
    out = Image.new("RGBA", img.size, (0, 0, 0, 0))
    out.alpha_composite(ring)
    out.alpha_composite(img)
    return out


def upscale(img):
    return img.resize((SIZE, SIZE), Image.NEAREST)


# ---------------------------------------------------------------------------
# (a) the sigle reduced: the wordmark's own ">_" prompt glyph, nothing added.
def candidate_a():
    im = canvas()
    px = im.load()
    green = PHOSPHOR + (255,)
    # chevron ">" -- two diagonal strokes, 2px thick, apex at (7,7.5)
    chevron = [
        (3, 3), (4, 3), (3, 4), (4, 4),
        (5, 5), (6, 5), (5, 6), (6, 6),
        (7, 7), (8, 7), (7, 8), (8, 8),
        (5, 9), (6, 9), (5, 10), (6, 10),
        (3, 11), (4, 11), (3, 12), (4, 12),
    ]
    for x, y in chevron:
        px[x, y] = green
    # underscore "_"
    for x in range(9, 13):
        px[x, 11] = green
        px[x, 12] = green
    return outline(im, PHOSPHOR_DIM)


# ---------------------------------------------------------------------------
# (b) a terminal screen: bone bezel, black tube, ">_" lit inside.
def candidate_b():
    im = canvas()
    d = ImageDraw.Draw(im)
    bezel = PHOSPHOR + (255,)
    screen = CRT_BLACK + (255,)
    green = PHOSPHOR + (255,)
    d.rectangle([1, 1, 14, 11], fill=bezel)
    d.rectangle([2, 2, 13, 10], fill=screen)
    # bold chevron + underscore filling most of the tube
    px = im.load()
    chevron = [(4, 4), (5, 5), (4, 6), (6, 5)]
    for x, y in chevron:
        px[x, y] = green
    for x in range(8, 12):
        px[x, 8] = green
    # stand
    d.rectangle([6, 12, 9, 14], fill=bezel)
    return outline(im, (0, 0, 0))


# ---------------------------------------------------------------------------
# (c) "CS" monogram inside a screen frame.
def candidate_c():
    im = canvas()
    d = ImageDraw.Draw(im)
    green = PHOSPHOR + (255,)
    screen = CRT_BLACK + (255,)
    d.rectangle([0, 0, 15, 15], outline=green, width=1)
    d.rectangle([1, 1, 14, 14], fill=screen)
    font = ImageFont.truetype(
        "/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf", 13)
    mask = Image.new("L", (N, N), 0)
    ImageDraw.Draw(mask).text((1, 0), "CS", font=font, fill=255)
    mask = mask.point(lambda v: 255 if v > 110 else 0)
    im.paste(green, (0, 0), mask)
    return outline(im, (0, 0, 0))


CANDIDATES = {
    "a": ("cerosec-menu-prompt.png", candidate_a),
    "b": ("cerosec-menu-screen.png", candidate_b),
    "c": ("cerosec-menu-cs.png", candidate_c),
}


def write_candidates():
    CANDIDATES_DIR.mkdir(parents=True, exist_ok=True)
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    paths = {}
    for key, (name, fn) in CANDIDATES.items():
        img = upscale(fn())
        p = CANDIDATES_DIR / name
        img.save(p)
        paths[key] = p
        print("wrote", p, img.size)
    winner_path = OUT_DIR / WINNER_NAME
    Image.open(paths[WINNER]).save(winner_path)
    print("shipped winner ->", winner_path)
    return paths


# ---------------------------------------------------------------------------
# planche.png: a faithful mock of the ISContextMenu row.
MENU_BG = (30, 30, 30, 235)      # dark translucent panel
HOVER_BG = (55, 55, 60, 235)     # lighter highlighted row
BORDER = (90, 90, 90, 255)
TEXT = (222, 222, 214, 255)
FONT_PX = 18


def mock_row(width, label, icon, hovered, font):
    row_h = FONT_PX + 12
    row = Image.new("RGBA", (width, row_h), HOVER_BG if hovered else MENU_BG)
    d = ImageDraw.Draw(row)
    icon_size = row_h - 12
    if icon is not None:
        ic = icon.resize((icon_size, icon_size), Image.NEAREST)
        row.alpha_composite(ic, (2, 6))
    text_x = icon_size + 6
    d.text((text_x, (row_h - FONT_PX) // 2 - 2), label, font=font, fill=TEXT)
    return row


def build_planche(paths):
    font = ImageFont.truetype(
        "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", FONT_PX)
    width = 260
    rows_spec = [
        ("Turn on computer", None, False),               # scale reference (no icon)
        ("CeroSec: Door", "a", True),
        ("CeroSec (dev)", "a", False),
    ]
    columns = []
    for key in ("a", "b", "c"):
        icon = Image.open(paths[key]).convert("RGBA")
        rows = []
        for label, use, hovered in rows_spec:
            ic = icon if use == "a" or use is None and False else (
                icon if use else None)
            # use the candidate icon on both CeroSec rows, none on the
            # "Turn on computer" reference row
            ic = icon if use else None
            rows.append(mock_row(width, label, ic, hovered, font))
        menu = Image.new("RGBA", (width, sum(r.height for r in rows) + 2),
                          BORDER)
        y = 1
        for r in rows:
            menu.paste(r, (1, y))
            y += r.height
        columns.append((key, menu))

    pad = 20
    label_h = 26
    col_w = max(c.width for _, c in columns)
    col_h = max(c.height for _, c in columns)
    scale4 = 4
    small_w = pad + (col_w + pad) * len(columns)
    big_w = pad + (col_w * scale4 + pad) * len(columns)
    total_w = max(small_w, big_w)
    total_h = pad * 2 + label_h + col_h + label_h + col_h * scale4
    sheet = Image.new("RGBA", (total_w, total_h), (18, 18, 20, 255))
    d = ImageDraw.Draw(sheet)
    label_font = ImageFont.truetype(
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 16)

    x = pad
    d.text((pad, 4), "echelle 1x (rendu reel)", font=label_font, fill=(230, 230, 230, 255))
    for key, menu in columns:
        d.text((x, label_h), "candidate %s" % key, font=label_font, fill=(200, 200, 200, 255))
        sheet.paste(menu, (x, label_h + 20))
        x += col_w + pad

    y2 = label_h + 20 + col_h + 20
    d.text((pad, y2 - 20), "agrandi 4x (plus proche voisin)", font=label_font, fill=(230, 230, 230, 255))
    x = pad
    for key, menu in columns:
        big = menu.resize((menu.width * scale4, menu.height * scale4), Image.NEAREST)
        sheet.paste(big, (x, y2))
        x += big.width + pad
    sheet = sheet.crop((0, 0, total_w, y2 + col_h * scale4 + pad))
    out = SCRATCH / "planche.png"
    sheet.save(out)
    print("wrote", out, sheet.size)


if __name__ == "__main__":
    paths = write_candidates()
    build_planche(paths)
