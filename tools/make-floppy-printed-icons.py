#!/usr/bin/env python3
#
# Run from the repo root:  python3 tools/make-floppy-printed-icons.py
#
#   Item_CeroSecFloppy<Colour>Printed.png   the same disk, with a PRINTED label
#
# Four files, one per shell colour, and they are the look a disk with a factory
# sticker on it wears in the inventory (CeroSecContent.markLabel puts the name of
# one of them in the item's own modData, which is where the engine reads a
# per-item icon from -- the javap proof is over that function).
#
# It DERIVES rather than draws: the four plain icons are the art, and a printed
# disk is that art with two lines of print on the sticker. So this file opens
# Item_CeroSecFloppy<Colour>.png, finds the sticker, and lays the print on it.
# Nothing else about the shell is touched, which is the point -- a printed blue
# disk has to be recognisable as the same blue disk, and a hand-drawn second set
# would drift away from the first the day somebody repaints one.
#
# The print is TWO BARS, one long and one short, in toner, with white paper above,
# between and below them. Deliberately not legible: it is a 32x32 icon and the
# sticker is seven rows of it. What a survivor reads is the item's NAME (the
# inventory shows "CeroSec UTILITIES 1.0") and the tooltip line under it; what the
# icon has to do is be tellable at a glance from the blank sticker of a disk
# somebody wrote on in biro, which one long bar and one short one at this size is.
#
# The sticker is FOUND and not typed in: the light rows of the plain icon, which
# are x 9..22 over y 16..22 in all four of them today. A repaint that moves the
# sticker moves the print with it, and one that takes the sticker away fails here
# loudly instead of printing on the shell.
#
# The contact sheet to judge them by -- 1x and 4x, plain beside printed, on a
# checkerboard -- is tools/out/floppy-printed-sheet.png, which is NOT in the
# repository (tools/out is scratch). Rebuild it with
#
#   python3 tools/make-floppy-printed-icons.py --sheet

import sys

from PIL import Image

PLAIN = "common/media/textures/Item_CeroSecFloppy%s.png"
OUT = "common/media/textures/Item_CeroSecFloppy%sPrinted.png"
SIZE = 32
COLOURS = ("Blue", "Yellow", "Red", "Green")

# The toner. Not the outline's own ink (10,12,22): print on white paper at this
# size reads as a warm dark grey and a pure ink bar reads as a hole in the label.
TONER = (26, 28, 38, 255)
PAPER = (250, 250, 250, 255)

# What counts as the sticker: opaque, and light in all three channels. The shells
# are saturated (the blue one is 55,46,251) and the shutter is grey at 139 or
# below, so the floor below only ever finds paper.
LIGHT = 150
# And what counts as a run of sticker: ten pixels across, six rows deep. The
# shutter's own light rows are seven across at their widest and four deep.
WIDE_ENOUGH = 10
TALL_ENOUGH = 6


def sticker_rows(px):
    """The sticker, row by row: { y: (x0, x1) }, top row first.

    A WIDE RUN of light rows and not every light row there is: the metal shutter
    at the top of the disk catches the light too and answers seven pixels of grey
    over 150 on four rows of its own, so a floor on brightness alone finds the
    shutter first and prints the label on it. The sticker is the run at least
    WIDE_ENOUGH across and at least TALL_ENOUGH deep, and the LAST such run down
    the icon -- which is the sticker on all four of them.
    """
    wide = {}
    for y in range(SIZE):
        xs = [x for x in range(SIZE)
              if px[x, y][3] == 255 and min(px[x, y][:3]) > LIGHT]
        if len(xs) >= WIDE_ENOUGH:
            wide[y] = (min(xs), max(xs))
    run, best = [], []
    for y in range(SIZE):
        if y in wide:
            run.append(y)
        else:
            if len(run) >= TALL_ENOUGH:
                best = run
            run = []
    if len(run) >= TALL_ENOUGH:
        best = run
    if not best:
        raise SystemExit("no sticker found on the plain icon")
    return dict((y, wide[y]) for y in best)


def printed(colour):
    """The plain icon with two bars of print on its sticker."""
    im = Image.open(PLAIN % colour).convert("RGBA")
    if im.size != (SIZE, SIZE):
        raise SystemExit("%s is not %dx%d" % (PLAIN % colour, SIZE, SIZE))
    px = im.load()
    rows = sticker_rows(px)
    ys = sorted(rows)
    top, bottom = ys[0], ys[-1]
    if bottom - top < 5:
        raise SystemExit("the sticker on %s is too short to print on" % colour)

    # The paper first, flat: a printed label was white card and the plain icon's
    # sticker carries a shade per row. Flattening it is what makes the print read
    # as ink on paper rather than as a fifth band of the gradient.
    for y in ys:
        x0, x1 = rows[y]
        for x in range(x0, x1 + 1):
            px[x, y] = PAPER

    # Then the two bars, measured off the sticker and not off the icon: the long
    # one a third of the way down, the short one two thirds, each inset two
    # columns so the paper has a margin on both sides.
    x0, x1 = rows[top + 2]
    inset = 2
    wide = (x0 + inset, x1 - inset)
    narrow = (x0 + inset, x0 + inset + (x1 - x0 - inset * 2) // 2)
    for bar, at in ((wide, top + 3), (narrow, top + 5)):
        for x in range(bar[0], bar[1] + 1):
            px[x, at] = TONER

    return im


def sheet():
    """Plain beside printed, 1x and 4x, on a checkerboard. tools/out is
    scratch and is not in the repository."""
    import os

    os.makedirs("tools/out", exist_ok=True)
    pad = 8
    cell = SIZE * 4
    w = pad + (SIZE + pad) * 2 + (cell + pad) * 2
    h = pad + (cell + pad) * len(COLOURS)
    board = Image.new("RGBA", (w, h), (255, 255, 255, 255))
    for y in range(h):
        for x in range(w):
            if ((x // 8) + (y // 8)) % 2 == 0:
                board.putpixel((x, y), (204, 204, 204, 255))
    for row, colour in enumerate(COLOURS):
        y = pad + (cell + pad) * row
        plain = Image.open(PLAIN % colour).convert("RGBA")
        ink = Image.open(OUT % colour).convert("RGBA")
        board.alpha_composite(plain, (pad, y))
        board.alpha_composite(ink, (pad + SIZE + pad, y))
        board.alpha_composite(plain.resize((cell, cell), Image.NEAREST),
                              (pad + (SIZE + pad) * 2, y))
        board.alpha_composite(ink.resize((cell, cell), Image.NEAREST),
                              (pad + (SIZE + pad) * 2 + cell + pad, y))
    board.save("tools/out/floppy-printed-sheet.png")
    print("wrote tools/out/floppy-printed-sheet.png")


def main():
    for colour in COLOURS:
        path = OUT % colour
        printed(colour).save(path)
        print("wrote", path)
    if "--sheet" in sys.argv:
        sheet()


if __name__ == "__main__":
    main()
