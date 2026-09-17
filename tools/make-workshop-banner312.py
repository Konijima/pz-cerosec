#!/usr/bin/env python3
"""Draw the Steam Workshop banner as two 312 px panels, not one 630.

    python3 tools/make-workshop-banner312.py
        writes workshop/banner312-a.png and workshop/banner312-b.png

**Why two files and not one image cut in half.** `workshop/banner.png` (630
wide, made by `tools/make-workshop-images.py` off `workshop/art/banner.png`)
is a single bitmap: cutting it at the halfway column would slice the desk
lamp or a letter of the wordmark in two, and a 312 px `<img>` on a 352 px
phone column sits under the NEXT `<img>`, not beside half of itself. So each
panel is composed fresh from the same pieces `make-workshop-images.py`
already uses -- `key_dark` cuts of the mark and the wordmark off
`workshop/art/poster.png`, `cerosec_art`'s scanline field and pixel text --
at 312 native, never a resize of the 630 art. That is also why this is a
script and not a crop: the source `banner.png` IS hand-made single art (see
its own docstring), and the two-panel form does not exist in it.

**The pair, not two banners.** Both panels share one height and one frame
style (a phosphor rule on all four edges) so that on desktop, where the
description puts two inline `<img>`s on the same line, they read as one
banner with a seam down the middle; and on a phone, where Steam stacks them,
each is a complete vignette with its own border -- nothing of one panel
finishes inside the other, which a plaque cut mid-word would do.

  A  the CeroSec plaque: the mark, the wordmark, the tagline -- the same
     three pieces `workshop/banner.png`'s left third already carries.
  B  a terminal window: a title bar and a few status lines in the header
     idiom (`> ` prompt, block cursor) `tools/make-workshop-headers.py`
     uses, so the pair reads as the same machine as the rest of the page.
"""

import sys
from pathlib import Path

from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parent))
from cerosec_art import (BONE, glow_behind, key_dark, pixel_text,
                         sample_phosphor, scanline_field)

REPO = Path(__file__).resolve().parent.parent
SRC_POSTER = REPO / "workshop" / "art" / "poster.png"
OUT_A = REPO / "workshop" / "banner312-a.png"
OUT_B = REPO / "workshop" / "banner312-b.png"

W = 312            # the mobile-safe width; see docs/notes/workshop-study.md
H = 170            # tall enough for the plaque's three lines at this width
FRAME_PX = 2        # the phosphor rule on all four edges of BOTH panels

# The same crops `make-workshop-images.py` cuts for the poster's logo
# lockup, off workshop/art/poster.png -- kept in this file too rather than
# imported, because that script's filename has a hyphen and is not an
# importable module.
ART_MARK = (0.0587, 0.749, 0.264, 0.917)
ART_WORDMARK = (0.289, 0.769, 0.968, 0.917)

TAGLINE = "THE NETWORK NEVER DIED."

# Panel B's title and lines are real, not invented: the project's own rule
# ("Never invent Unix behaviour") applies to a banner as much as to a string
# in the mod. The title is the premises name from the BIOS
# example already quoted in the manual, and the five lines below it are the
# same example's boot lines plus a login and a command run against the
# actual engine (lua5.1 on _verify/vmrun.lua, which loads the real
# CeroSecOS):
#   - "Ethernet: eth0 10.4.17.3" and "Phone line: 555-0417" --
#     CeroSecManualAdmin.lua:1596-1598, the BIOS's own worked example.
#   - "login: admin" -- the real prompt string (CeroSecContent.lua login
#     text) and the account a machine with no owner takes (see workshop.txt).
#   - "$ date" / "Tue Jun 15 12:00:00 1993" -- Vmrun.exec(vm, "date") on a
#     fresh machine at vmrun.lua's own fixed clock (FIXED_TIME, 1993-06-15
#     12:00:00), which is why the wiki's own examples never drift.
TERM_TITLE = "CoffeeShop"
TERM_LINES = ["Ethernet: eth0 10.4.17.3", "Phone line: 555-0417",
              "login: admin", "$ date", "Tue Jun 15 12:00:00 1993"]

LINE_EVERY = 3
LINE_DROP = 0.72
GLOW = 0.10
VIGNETTE = 0.35

PAD = 14
BASE_PX = 8
SCALE = 2
TRACKING = 1


def piece(src, box):
    w, h = src.size
    left, top, right, bottom = box
    return src.convert("RGB").crop(
        (round(left * w), round(top * h), round(right * w), round(bottom * h)))


def scaled_to_width(img, width):
    height = max(1, round(img.height * width / img.width))
    return img.resize((width, height), Image.LANCZOS)


def framed(panel, green):
    draw = ImageDraw.Draw(panel)
    draw.rectangle([0, 0, panel.width - 1, panel.height - 1],
                   outline=green, width=FRAME_PX)
    return panel


def panel_a(poster, green):
    """The plaque: mark over wordmark, the tagline under them, centred."""
    panel = scanline_field((W, H), phosphor=green, line_every=LINE_EVERY,
                           line_drop=LINE_DROP, glow=GLOW, vignette=VIGNETTE)

    mark = key_dark(piece(poster, ART_MARK))
    word = key_dark(piece(poster, ART_WORDMARK))
    logo_w = W - 2 * PAD - 20
    mark = scaled_to_width(mark, round(logo_w * mark.width
                                       / (mark.width + word.width)))
    word = scaled_to_width(word, logo_w - mark.width)

    tag = pixel_text(TAGLINE, BASE_PX, SCALE, green, tracking=TRACKING)
    if tag.width > W - 2 * PAD:
        raise ValueError("%r is %d px wide and panel A has %d"
                          % (TAGLINE, tag.width, W - 2 * PAD))

    logo_h = max(mark.height, word.height)
    group_h = logo_h + 14 + tag.height
    y = (H - group_h) // 2

    x = (W - (mark.width + 10 + word.width)) // 2
    panel.paste(mark.convert("RGB"), (x, y + logo_h - mark.height), mark)
    panel.paste(word.convert("RGB"), (x + mark.width + 10,
                                      y + logo_h - word.height), word)

    ty = y + logo_h + 14
    halo = glow_behind(tag)
    tx = (W - tag.width) // 2
    panel.paste(halo.convert("RGB"), (tx, ty), halo)
    panel.paste(tag.convert("RGB"), (tx, ty), tag)

    return framed(panel, green)


def panel_b(green):
    """A terminal window: the premises name as a title, then real BIOS and
    shell lines (see TERM_TITLE/TERM_LINES above for where each comes from).

    The title used to be a solid green fill, which read as a second, heavier
    frame stacked on this panel alone. It is now a line of text and a 2px
    rule -- the same weight as `framed()`'s own border below -- so A and B
    share one frame style, not two.
    """
    panel = scanline_field((W, H), phosphor=green, line_every=LINE_EVERY,
                           line_drop=LINE_DROP, glow=GLOW, vignette=VIGNETTE)
    draw = ImageDraw.Draw(panel)

    title = pixel_text(TERM_TITLE, BASE_PX, SCALE, green, tracking=TRACKING)
    title_y = 10
    panel.paste(title.convert("RGB"), (PAD, title_y), title)
    bar_h = title_y + title.height + 8
    draw.line([(0, bar_h), (W - 1, bar_h)], fill=green, width=FRAME_PX)

    y = bar_h + 12
    for line in TERM_LINES:
        text = pixel_text(line, BASE_PX, SCALE, BONE, tracking=TRACKING)
        panel.paste(text.convert("RGB"), (PAD, y), text)
        y += text.height + 10

    return framed(panel, green)


def main():
    if not SRC_POSTER.is_file():
        print("missing %s: the phosphor and the logo are sampled off it"
              % SRC_POSTER, file=sys.stderr)
        return 1
    poster = Image.open(SRC_POSTER).convert("RGBA")
    green = sample_phosphor(SRC_POSTER)
    print("phosphor sampled off the art: %s" % (green,))

    a = panel_a(poster, green)
    a.save(OUT_A, "PNG", optimize=True)
    print("%s %dx%d, %d bytes" % (OUT_A, a.width, a.height,
                                  OUT_A.stat().st_size))

    b = panel_b(green)
    b.save(OUT_B, "PNG", optimize=True)
    print("%s %dx%d, %d bytes" % (OUT_B, b.width, b.height,
                                  OUT_B.stat().st_size))

    pair = Image.new("RGB", (a.width + b.width, max(a.height, b.height)),
                     (36, 36, 36))
    pair.paste(a, (0, 0))
    pair.paste(b, (a.width, 0))
    strip = REPO / "tools" / "out" / "banner312-pair.png"
    strip.parent.mkdir(parents=True, exist_ok=True)
    pair.save(strip, "PNG", optimize=True)
    print("%s (side by side, as desktop shows them)" % strip)
    return 0


if __name__ == "__main__":
    sys.exit(main())
