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
from cerosec_art import (BONE, PIXEL_BASE_MIN, glow_behind, pixel_text,
                         sample_phosphor, scanline_field, text_block_width)

REPO = Path(__file__).resolve().parent.parent
SRC_POSTER = REPO / "workshop" / "art" / "poster.png"
OUT_DIR = REPO / "workshop" / "img"

LINE_EVERY = 3
LINE_DROP = 0.72    # lighter than the poster's: a header is read, not looked at
GLOW = 0.10
VIGNETTE = 0.35

PROMPT = ">"

# Two bands, not one. The 630 is Steam's stylesheet ceiling and stays exactly
# as it was (workshop/img/h-*.png, the copies the live 0.4.0 page still
# serves). The 312 is the width measured on a real phone on 2026-09-17 (see
# docs/notes/workshop-study.md): two 312 <img>s sit side by side on desktop and
# stack on a 352-360 px column without stretching the page, which 630 does not.
# Each width gets ITS OWN font size, found by search rather than eyeballed, so
# "GETTING STARTED" -- the longest header -- is still square blocks and never a
# resample. ONE size within a width, for the reason TRACKING's neighbour
# comment gives: nine headers at nine sizes are not a set.
WIDTHS = {
    "630": dict(w=630, h=80, base_px=15, scale=3, tracking=2,
                pad_x=24, gap_prompt=21, gap_cursor=14, cursor_w=24, rule_px=2,
                out_dir=OUT_DIR, prefix="h-"),
    "312": dict(w=312, h=40, base_px=None, scale=None, tracking=1,
                pad_x=10, gap_prompt=9, gap_cursor=6, cursor_w=11, rule_px=1,
                out_dir=OUT_DIR, prefix="h312-"),
}

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


def room_for(cfg, prompt_w):
    return (cfg["w"] - 2 * cfg["pad_x"] - prompt_w - cfg["gap_prompt"]
            - cfg["gap_cursor"] - cfg["cursor_w"])


def pick_size(cfg, words_list, max_scale=6):
    """The largest whole-pixel (base_px, scale) that fits every header in
    `words_list` inside this band, walking down the way fit_pixel_text does
    (big blocks of a small font over small blocks of a big one), but checked
    against the WHOLE set at once -- one size or it is not a set."""
    for scale in range(max_scale, 0, -1):
        for base in range(22, PIXEL_BASE_MIN - 1, -1):
            prompt_w = text_block_width(PROMPT, base, scale, tracking=0)
            room = room_for(cfg, prompt_w)
            widths = [text_block_width(w, base, scale, tracking=cfg["tracking"])
                      for w in words_list]
            if max(widths) <= room:
                return base, scale
    raise ValueError("no (base_px, scale) fits %r at %d px even at the floor"
                      % (max(words_list, key=len), cfg["w"]))


def header(words, green, cfg, base_px, scale):
    """One band: the prompt, the words, the cursor, the rule."""
    w, h, rule_px = cfg["w"], cfg["h"], cfg["rule_px"]
    band = scanline_field((w, h), phosphor=green,
                          line_every=LINE_EVERY, line_drop=LINE_DROP,
                          glow=GLOW, vignette=VIGNETTE)

    prompt = pixel_text(PROMPT, base_px, scale, green, tracking=0)
    text = pixel_text(words, base_px, scale, BONE, tracking=cfg["tracking"])
    room = room_for(cfg, prompt.width)
    if text.width > room:
        raise ValueError(
            "%r is %d px wide and the %d px band has %d: shorten the header, "
            "do not shrink the type -- they are one set or they are nothing"
            % (words, text.width, w, room))

    baseline = (h - rule_px - text.height) // 2
    x = cfg["pad_x"]
    # The marker sits on the words' own baseline, not on the band's middle:
    # they are one line of a terminal, and a terminal has one baseline.
    py = baseline + text.height - prompt.height
    halo = glow_behind(prompt)
    band.paste(halo.convert("RGB"), (x, py), halo)
    band.paste(prompt.convert("RGB"), (x, py), prompt)

    x += prompt.width + cfg["gap_prompt"]
    band.paste(text.convert("RGB"), (x, baseline), text)

    x += text.width + cfg["gap_cursor"]
    draw = ImageDraw.Draw(band)
    draw.rectangle([x, baseline, x + cfg["cursor_w"] - 1,
                    baseline + text.height - 1], fill=green)
    draw.rectangle([0, h - rule_px, w, h - 1], fill=green)
    return band


def build_width(key, cfg, green):
    words_list = [words for _, words in HEADERS]
    if cfg["base_px"] is None:
        base_px, scale = pick_size(cfg, words_list)
        print("%s px band: picked base_px=%d scale=%d for %r"
              % (key, base_px, scale, max(words_list, key=len)))
    else:
        base_px, scale = cfg["base_px"], cfg["scale"]

    out_dir = cfg["out_dir"]
    out_dir.mkdir(parents=True, exist_ok=True)
    stems = []
    for stem, words in HEADERS:
        name = cfg["prefix"] + stem[len("h-"):]
        dest = out_dir / ("%s.png" % name)
        header(words, green, cfg, base_px, scale).save(
            dest, "PNG", optimize=True)
        print("%s %dx%d, %d bytes  %s"
              % (dest, cfg["w"], cfg["h"], dest.stat().st_size, words))
        stems.append(name)

    # A sheet to look at them as a set rather than one at a time: bands
    # whose left edges do not line up is the thing this catches.
    gap = 12
    sheet = Image.new("RGB", (cfg["w"], len(stems) * (cfg["h"] + gap) - gap),
                      (36, 36, 36))
    y = 0
    for name in stems:
        sheet.paste(Image.open(out_dir / ("%s.png" % name)), (0, y))
        y += cfg["h"] + gap
    strip = REPO / "tools" / "out" / ("workshop-headers-%s.png" % key)
    strip.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(strip, "PNG", optimize=True)
    print("%s (all %d, stacked)" % (strip, len(stems)))


def main():
    if not SRC_POSTER.is_file():
        print("missing %s: the phosphor is sampled off it" % SRC_POSTER,
              file=sys.stderr)
        return 1
    green = sample_phosphor(SRC_POSTER)
    print("phosphor sampled off the art: %s" % (green,))

    for key, cfg in WIDTHS.items():
        build_width(key, cfg, green)
    return 0


if __name__ == "__main__":
    sys.exit(main())
