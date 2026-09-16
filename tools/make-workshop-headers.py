#!/usr/bin/env python3
"""Draw the section headers for the Steam Workshop description.

    python3 tools/make-workshop-headers.py      writes workshop/img/h-*.png

One band per section of `workshop/workshop.txt`. Nothing is cut out of
the source art: they are drawn from `tools/cerosec_art.py` -- the phosphor
sampled off the poster, the scanline field and the pixel text renderer -- so a
header can be added by putting a line in HEADERS and running this again.

**Why they are images at all.** Every one of the five most subscribed Project
Zomboid pages studied in `docs/notes/workshop-study.md` sets its section
headers as images rather than as `[h1]`, and it is the single thing that most
separates a page that looks made from a page that looks typed. Steam's `[h1]`
is one grey weight in one grey face on every item on the Workshop.

**Why 630 and not 1000.** The ceiling on an image inside a description is
Steam's own stylesheet:

    .workshopItemDescription img { max-width: 630px; }

(public/css/skin_1/workshop.css on community.akamai.steamstatic.com.) A header
drawn at 1000 is not shown at 1000: the browser scales it to 630, which is a
factor of 0.63, and 0.63 is the worst thing that can happen to a bitmap face --
every block edge lands between two pixels and comes back grey. Drawn at 630 the
blocks are square and hard, which is the whole look. See
docs/RELEASE.md for where the URLs come from.

**The form.** The mod's own banner writes its bullets as `> REAL UNIX
TERMINAL`, so a header is a shell prompt: a phosphor marker, the words in the
wordmark's bone, a block cursor after them, and a phosphor rule along the
bottom. That is the mod's idiom and not a decoration borrowed from somewhere.
"""

import sys
from pathlib import Path

from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parent))
from cerosec_art import (BONE, glow_behind, pixel_text, sample_phosphor,
                         scanline_field)

REPO = Path(__file__).resolve().parent.parent
SRC_POSTER = REPO / "workshop" / "art" / "poster.png"
OUT_DIR = REPO / "workshop" / "img"

# The band. 630 is the stylesheet's ceiling (see the docstring).
HEADER_W = 630
HEADER_H = 80

# ONE size for all of them, and it is not negotiable per header. Sizing each
# header to its own band is what a first pass of this script did, and the
# result was FEATURES in letters twice the height of WHAT YOU FIND: nine
# headers at nine sizes are not a set, they are nine pictures. So the size is
# fixed here and a header whose words do not fit is an error that names itself,
# because the fix is a shorter header and never a smaller font.
BASE_PX = 15        # the outline font's size before the threshold
SCALE = 3           # the block size every pixel of it is blown up to
TRACKING = 2        # whole base pixels between characters, never a fraction

PAD_X = 24          # left and right margin inside the band
GAP_PROMPT = 21     # the marker to the words: two thirds of a cell
GAP_CURSOR = 14     # the words to the block cursor
CURSOR_W = 24       # one character cell, near enough
RULE_PX = 2         # the phosphor rule along the bottom edge

LINE_EVERY = 3
LINE_DROP = 0.72    # lighter than the poster's: a header is read, not looked at
GLOW = 0.10
VIGNETTE = 0.35

PROMPT = ">"

# file stem -> the words on it. The stems are what workshop.txt references, so
# renaming one here means renaming it there.
HEADERS = [
    ("h-features", "FEATURES"),
    ("h-automation", "AUTOMATION"),
    ("h-getting-started", "GETTING STARTED"),
    ("h-network", "THE NETWORK"),
    ("h-world", "WHAT YOU FIND"),
    ("h-multiplayer", "MULTIPLAYER"),
    ("h-faithful", "TRUE TO 1993"),
    ("h-faq", "QUESTIONS"),
    ("h-credits", "CREDITS"),
]


def header(words, green):
    """One band: the prompt, the words, the cursor, the rule."""
    band = scanline_field((HEADER_W, HEADER_H), phosphor=green,
                          line_every=LINE_EVERY, line_drop=LINE_DROP,
                          glow=GLOW, vignette=VIGNETTE)

    prompt = pixel_text(PROMPT, BASE_PX, SCALE, green, tracking=0)
    text = pixel_text(words, BASE_PX, SCALE, BONE, tracking=TRACKING)
    room = (HEADER_W - 2 * PAD_X - prompt.width - GAP_PROMPT
            - GAP_CURSOR - CURSOR_W)
    if text.width > room:
        raise ValueError(
            "%r is %d px wide and the band has %d: shorten the header, do not "
            "shrink the type -- they are one set or they are nothing"
            % (words, text.width, room))

    baseline = (HEADER_H - RULE_PX - text.height) // 2
    x = PAD_X
    # The marker sits on the words' own baseline, not on the band's middle:
    # they are one line of a terminal, and a terminal has one baseline.
    py = baseline + text.height - prompt.height
    halo = glow_behind(prompt)
    band.paste(halo.convert("RGB"), (x, py), halo)
    band.paste(prompt.convert("RGB"), (x, py), prompt)

    x += prompt.width + GAP_PROMPT
    band.paste(text.convert("RGB"), (x, baseline), text)

    x += text.width + GAP_CURSOR
    draw = ImageDraw.Draw(band)
    draw.rectangle([x, baseline, x + CURSOR_W - 1, baseline + text.height - 1],
                   fill=green)
    draw.rectangle([0, HEADER_H - RULE_PX, HEADER_W, HEADER_H - 1], fill=green)
    return band


def main():
    if not SRC_POSTER.is_file():
        print("missing %s: the phosphor is sampled off it" % SRC_POSTER,
              file=sys.stderr)
        return 1
    green = sample_phosphor(SRC_POSTER)
    print("phosphor sampled off the art: %s" % (green,))

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for stem, words in HEADERS:
        dest = OUT_DIR / ("%s.png" % stem)
        header(words, green).save(dest, "PNG", optimize=True)
        print("%s %dx%d, %d bytes  %s"
              % (dest, HEADER_W, HEADER_H, dest.stat().st_size, words))

    # A sheet to look at them as a set rather than one at a time: bands
    # whose left edges do not line up is the thing this catches.
    gap = 12
    sheet = Image.new("RGB", (HEADER_W, len(HEADERS) * (HEADER_H + gap) - gap),
                      (36, 36, 36))
    y = 0
    for stem, words in HEADERS:
        sheet.paste(Image.open(OUT_DIR / ("%s.png" % stem)), (0, y))
        y += HEADER_H + gap
    strip = REPO / "tools" / "out" / "workshop-headers.png"
    strip.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(strip, "PNG", optimize=True)
    print("%s (all %d, stacked)" % (strip, len(HEADERS)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
