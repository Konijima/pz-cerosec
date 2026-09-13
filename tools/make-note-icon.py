#!/usr/bin/env python3
#
# Run from the repo root:  python3 tools/make-note-icon.py
#
#   Item_CeroSecStickyNote.png   a yellow note with a line of writing on it
#
# The language is tools/make-module-icons.py's, down to the same ink: a
# transparent ground, one dark outline all the way round (10,12,22 -- the manual
# icon's own), flat fills with a single highlight above and a single shade below,
# no anti-aliasing anywhere. Six colours.
#
# The shape is a square of paper with its bottom-right corner CURLED, which is the
# whole of how a sticky note is drawn and what tells it from the sheet of paper
# vanilla already has: the curl is three steps of the shade colour and a fourth of
# the ink, and the paper's own outline stops where the curl starts.
#
# The writing is two short bars and a longer one, in ink, at the top -- a name and
# a word under it, which is what is on this note. Deliberately NOT legible: it is
# four pixels tall, and a survivor reads the note off the item's NAME (the
# inventory shows "Sticky note: root / falcon12"), not off its icon.
#
# Mathieu may well replace it by hand; this file is what makes it reproducible in
# the meantime, and every colour is named once at the top so a repaint is one line.
#
# The contact sheet to judge it by -- 1x and 4x on a checkerboard -- is
# tools/out/note-sheet.png, which is NOT in the repository (tools/out is scratch).
# Rebuild it with
#
#   python3 tools/make-note-icon.py --sheet

import sys

from PIL import Image

OUT = "common/media/textures/Item_CeroSec%s.png"
SIZE = 32

CLEAR = (0, 0, 0, 0)
INK = (10, 12, 22, 255)          # the outline, the manual icon's own
PAPER = (242, 214, 96, 255)      # the yellow of a 1993 sticky note
PAPER_HI = (252, 238, 156, 255)  # the light the top edge catches
PAPER_LO = (196, 164, 58, 255)   # the shade under it, and the curl
GLUE = (214, 182, 64, 255)       # the strip of gum across the top


class Icon:
    def __init__(self):
        self.px = [[CLEAR] * SIZE for _ in range(SIZE)]

    def dot(self, x, y, c):
        if 0 <= x < SIZE and 0 <= y < SIZE:
            self.px[y][x] = c

    def rect(self, x0, y0, x1, y1, c):
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                self.dot(x, y, c)

    def hline(self, x0, x1, y, c):
        self.rect(x0, y, x1, y, c)

    def vline(self, x, y0, y1, c):
        self.rect(x, y0, x, y1, c)

    def save(self, name):
        im = Image.new("RGBA", (SIZE, SIZE), CLEAR)
        for y in range(SIZE):
            for x in range(SIZE):
                im.putpixel((x, y), self.px[y][x])
        path = OUT % name
        im.save(path)
        print("wrote", path)


def sticky_note():
    """A square of paper, a strip of gum across the top, a curled corner and
    three bars of writing."""
    i = Icon()

    # The paper: 22 wide, 22 tall, sitting a little below centre so the curl has
    # room. x 5..26, y 5..26.
    x0, y0, x1, y1 = 5, 5, 26, 26
    # The curl eats the bottom-right: the last CURL rows get shorter.
    CURL = 5

    # The fill, row by row, so the curl can shorten the bottom rows.
    for y in range(y0 + 1, y1):
        right = x1 - 1
        over = CURL - (y1 - y)
        if over > 0:
            right = x1 - 1 - over
        i.hline(x0 + 1, right, y, PAPER)

    # The light on the top edge and the shade along the bottom of the flat part.
    i.hline(x0 + 1, x1 - 1, y0 + 1, PAPER_HI)
    i.vline(x0 + 1, y0 + 1, y1 - 1, PAPER_HI)
    i.hline(x0 + 1, x1 - CURL, y1 - CURL, PAPER_LO)

    # The strip of gum across the top: what makes it a sticky note and not a
    # square of paper. Two rows, a shade darker than the paper.
    i.hline(x0 + 2, x1 - 2, y0 + 3, GLUE)
    i.hline(x0 + 2, x1 - 2, y0 + 4, GLUE)

    # The outline. The three straight sides all the way, and the fourth stopped
    # where the curl begins.
    i.hline(x0, x1, y0, INK)
    i.vline(x0, y0, y1, INK)
    i.vline(x1, y0, y1 - CURL, INK)
    i.hline(x0, x1 - CURL, y1, INK)

    # The curl itself: the diagonal in ink, with the under-side of the paper in
    # shade behind it, which is the way a folded corner reads at this size.
    for step in range(CURL):
        x = x1 - CURL + step
        y = y1 - step
        i.dot(x, y, INK)
        # The underside, one pixel in from the fold.
        if step > 0:
            i.dot(x - 1, y, PAPER_LO)

    # The writing: a name, then a shorter word under it, then a rule. Ink, and not
    # meant to be read.
    i.hline(x0 + 3, x0 + 11, y0 + 8, INK)
    i.hline(x0 + 3, x0 + 7, y0 + 11, INK)
    i.hline(x0 + 3, x0 + 15, y0 + 14, INK)

    return i


def sheet():
    """The four-times blow-up on a checkerboard, to judge it against the other
    icons. tools/out is scratch and is not in the repository."""
    import os

    os.makedirs("tools/out", exist_ok=True)
    src = Image.open(OUT % "StickyNote").convert("RGBA")
    pad = 8
    w = SIZE + pad * 2 + SIZE * 4 + pad
    h = SIZE * 4 + pad * 2
    board = Image.new("RGBA", (w, h), (255, 255, 255, 255))
    for y in range(h):
        for x in range(w):
            if ((x // 8) + (y // 8)) % 2 == 0:
                board.putpixel((x, y), (204, 204, 204, 255))
    board.alpha_composite(src, (pad, pad))
    board.alpha_composite(src.resize((SIZE * 4, SIZE * 4), Image.NEAREST),
                          (pad + SIZE + pad, pad))
    board.save("tools/out/note-sheet.png")
    print("wrote tools/out/note-sheet.png")


def main():
    sticky_note().save("StickyNote")
    if "--sheet" in sys.argv:
        sheet()


if __name__ == "__main__":
    main()
