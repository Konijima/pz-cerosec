#!/usr/bin/env python3
#
# Run from the repo root:  python3 tools/make-volume-icons.py
#
# The three volume icons, made FROM the shipped one rather than drawn again.
#
# Item_CeroSecManual.png is a 32x32 closed book: a cream page block down the
# left, a navy cover, the OS' own green screen on it and two cream title bars
# under the screen. Three volumes are the same book in three bindings, so the
# only thing that changes is the navy -- and the navy is changed by SWAPPING
# channels rather than by picking new colours by eye, which keeps the three
# covers at the same value and the same contrast against the cream and the
# green that are not touched.
#
#   volume 1  User's Guide                  blue   the navy as it shipped
#   volume 2  System Administrator's Guide   green  G and B swapped
#   volume 3  Programmer's Guide             red    R and B swapped
#
# And a 3x5 numeral, in the cream of the title bars, in the place of the lower
# title bar: the volume number, where a 1993 documentation set prints it.

from PIL import Image

SRC = "common/media/textures/Item_CeroSecManual.png"

# The three navies: cover, spine highlight, bottom shading. Everything else in
# the icon -- the page block, the border, the screen, the cream highlights --
# is the same on all three bindings and is left alone.
COVER = {(30, 46, 84, 255), (48, 70, 120, 255), (20, 30, 58, 255)}

# The two title bars under the screen. Both come out: a numeral needs the whole
# of the lower half of the cover to itself, and a 3x5 numeral with a cream bar
# a pixel above it reads at 32 pixels as one cream blob and not as a number.
BARS = {(156, 145, 121, 255), (196, 191, 167, 255)}
INK = (196, 191, 167, 255)   # the cream the bars were printed in

DIGITS = {
    1: ("-#-", "##-", "-#-", "-#-", "###"),
    2: ("###", "--#", "###", "#--", "###"),
    3: ("###", "--#", "###", "--#", "###"),
}

# Where the numeral goes. The cover's interior is x 11..22, so a 3-wide numeral
# is centred at 15; rows 22..26 are the five clear rows between the screen's
# lower border and the bottom shading.
DIGIT_X, DIGIT_Y = 15, 22
BAR_ROWS = (21, 23)
COVER_X = range(11, 23)


def bind(swap, number, out):
    im = Image.open(SRC).convert("RGBA")
    px = im.load()

    # The binding: every navy pixel, channel-swapped.
    for y in range(im.height):
        for x in range(im.width):
            c = px[x, y]
            if c in COVER:
                px[x, y] = (c[swap[0]], c[swap[1]], c[swap[2]], c[3])

    # The flat of the cover, read back after the swap rather than written out a
    # second time by hand: the paint-out has to match what is beside it.
    cover = px[16, 25]

    # Both title bars are painted out in that, and the numeral takes their
    # place -- the volume number, where a 1993 documentation set prints it.
    # Over the cover's own columns and no others: the page block down the left
    # is printed in the same cream as the bars, and a paint-out that went the
    # whole width of the icon took a bite out of it.
    for y in BAR_ROWS:
        for x in COVER_X:
            if px[x, y] in BARS:
                px[x, y] = cover
    for r, row in enumerate(DIGITS[number]):
        for c, mark in enumerate(row):
            if mark == "#":
                px[DIGIT_X + c, DIGIT_Y + r] = INK

    im.save(out)


for swap, number, name in (
    ((0, 1, 2), 1, "User"),
    ((0, 2, 1), 2, "Admin"),
    ((2, 1, 0), 3, "Programmer"),
):
    out = "common/media/textures/Item_CeroSecManual%s.png" % name
    bind(swap, number, out)
    print("wrote", out)
