#!/usr/bin/env python3
#
# Run from the repo root:  python3 tools/make-module-icons.py
#
# The hardware module icons, the part they are built from and the book that
# teaches them, 32x32, drawn rather than rendered.
#
#   Item_CeroSecMagneticContact.png   a reed switch and its magnet, on a frame
#   Item_CeroSecRelay.png             an ice-cube relay, socket pins down
#   Item_CeroSecElectricStrike.png    a strike plate, keeper cut out of it
#   Item_CeroSecDoorOperator.png      a motor, its arm folded against it
#   Item_CeroSecSmallMotor.png        the motor on its own, no arm and no case
#   Item_CeroSecWiringGuide.png       the magazine the four recipes come out of
#
# The language is the one the mod's other icons already speak: a transparent
# ground, one dark outline all the way round (the manual's 10,12,22), flat fills
# with a single highlight above and a single shade below, and no anti-aliasing
# anywhere -- Item_CeroSecManual.png is eleven colours and every pixel of it is
# one of them. Nothing here is drawn in more than six.
#
# The green is the OS' own screen green out of the manual icon (92,255,122). On
# the four boxes it is used for exactly one thing on exactly one icon -- the
# relay's lamp -- because a survivor holding two small grey boxes tells them
# apart by that lamp. On the Wiring Guide it is the whole cover: the book is
# CeroSec Systems' own printing and it is printed in the colour of their screen.
#
# The art may well be replaced by hand later; this file is what makes all four
# reproducible in the meantime, and every colour is named once at the top so a
# repaint is one line.
#
# The contact sheet to judge them by -- the four at 1x and 4x on a checkerboard
# -- is tools/out/modules-sheet.png, which is NOT in the repository: tools/out is
# scratch (.gitignore). Rebuild it with
#
#   python3 tools/make-module-icons.py --sheet

import sys

from PIL import Image

OUT = "common/media/textures/Item_CeroSec%s.png"
SIZE = 32

CLEAR = (0, 0, 0, 0)
INK = (10, 12, 22, 255)          # the outline, the manual icon's own
STEEL = (150, 155, 165, 255)     # galvanised metal
STEEL_HI = (205, 210, 220, 255)
STEEL_LO = (95, 100, 112, 255)
CASE = (58, 66, 86, 255)         # the dark plastic of a relay case
CASE_HI = (92, 104, 132, 255)
BRASS = (176, 124, 60, 255)      # wire, and screw heads
CREAM = (196, 191, 167, 255)     # a label
GREEN = (92, 255, 122, 255)      # the OS' screen green: the relay's lamp


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

    # A filled box with the ink border drawn round the outside of the fill.
    def box(self, x0, y0, x1, y1, fill, border=INK):
        self.rect(x0, y0, x1, y1, border)
        self.rect(x0 + 1, y0 + 1, x1 - 1, y1 - 1, fill)

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


def magnetic_contact():
    """Two blocks and the gap between them: the switch, wired, and the magnet
    that shuts it. The gap is the whole point of the thing, so it is two pixels
    wide and dead centre."""
    i = Icon()
    # The switch half: taller, wired, on the left.
    i.box(6, 8, 14, 25, STEEL)
    i.rect(7, 9, 13, 11, STEEL_HI)
    i.rect(7, 23, 13, 24, STEEL_LO)
    # The magnet half: the same box, shorter, no wires.
    i.box(17, 10, 25, 23, STEEL)
    i.rect(18, 11, 24, 12, STEEL_HI)
    i.rect(18, 21, 24, 22, STEEL_LO)
    # The two wires out of the switch, into the frame.
    i.hline(2, 5, 13, BRASS)
    i.hline(2, 5, 17, BRASS)
    i.dot(1, 13, INK)
    i.dot(1, 17, INK)
    # The mounting screw in each half.
    i.dot(10, 14, INK)
    i.dot(10, 20, INK)
    i.dot(21, 16, INK)
    i.save("MagneticContact")


def relay():
    """An ice-cube relay: a dark case with a clear window, a lamp, and the four
    socket pins it stands on."""
    i = Icon()
    i.box(8, 5, 23, 24, CASE)
    # The window down the middle of the case, with the coil behind it.
    i.rect(11, 8, 20, 17, CASE_HI)
    i.rect(13, 10, 18, 15, STEEL_LO)
    i.vline(14, 10, 15, STEEL)
    i.vline(17, 10, 15, STEEL)
    # The lamp, top right, and its socket.
    i.rect(19, 6, 21, 7, GREEN)
    i.dot(18, 6, INK)
    i.dot(18, 7, INK)
    # The label across the bottom of the case.
    i.rect(10, 19, 21, 21, CREAM)
    i.hline(11, 20, 20, CASE)
    # Four pins under it.
    for x in (10, 14, 18, 22):
        i.vline(x, 25, 28, STEEL)
        i.dot(x, 29, INK)
        i.vline(x - 1, 25, 28, INK)
        i.vline(x + 1, 25, 28, INK)
    i.hline(8, 23, 25, INK)
    i.save("Relay")


def electric_strike():
    """A strike plate seen flat: the long faceplate, the keeper cut out of it,
    and the two screws that hold it in the jamb."""
    i = Icon()
    i.box(9, 2, 22, 29, STEEL)
    i.vline(10, 3, 28, STEEL_HI)
    i.vline(21, 3, 28, STEEL_LO)
    # The cut-out: the hole the latch drops into. Ink, because a hole in a
    # 32-pixel plate is a hole only if it is the darkest thing on it.
    i.box(12, 11, 19, 20, INK, INK)
    i.rect(13, 12, 18, 19, CLEAR)
    # The keeper, hinged on the left of the cut-out.
    i.rect(13, 12, 14, 19, STEEL_LO)
    i.vline(15, 12, 19, STEEL)
    # Two screws, one at each end.
    for y in (6, 25):
        i.rect(14, y - 1, 17, y + 1, BRASS)
        i.dot(13, y, INK)
        i.dot(18, y, INK)
        i.hline(15, 16, y, INK)
    # The wire out of the back of it, touching the plate it leaves.
    i.hline(22, 27, 16, BRASS)
    i.dot(28, 16, INK)
    i.save("ElectricStrike")


def door_operator():
    """A motor with its arm folded against the case: the heaviest thing in the
    mod, and it should look it. A wide body, a barrel on the end of it, and the
    arm across the front."""
    i = Icon()
    # The body.
    i.box(3, 9, 21, 22, STEEL)
    i.rect(4, 10, 20, 12, STEEL_HI)
    i.rect(4, 20, 20, 21, STEEL_LO)
    # The cooling ribs.
    for x in (7, 10, 13, 16):
        i.vline(x, 13, 19, STEEL_LO)
    # The barrel on the right: the gearbox the arm comes out of.
    i.box(21, 6, 28, 25, CASE)
    i.rect(22, 7, 27, 9, CASE_HI)
    i.rect(23, 14, 26, 17, STEEL)
    i.rect(24, 15, 25, 16, INK)
    # The arm, folded down across the bottom of the body rather than floating
    # under it: at 32 pixels a bar with a gap over it is a second object.
    i.rect(6, 22, 24, 24, STEEL)
    i.hline(6, 24, 22, INK)
    i.hline(6, 24, 25, INK)
    i.dot(5, 23, INK)
    i.dot(5, 24, INK)
    i.dot(25, 23, INK)
    i.dot(25, 24, INK)
    i.rect(7, 23, 9, 23, STEEL_HI)
    # The power lead.
    i.hline(1, 2, 15, BRASS)
    i.dot(0, 15, INK)
    i.save("DoorOperator")


def small_motor():
    """The motor on its own: the can, the end bell it is bolted through, and the
    shaft sticking out of it. It has to be told apart from the door operator at
    a glance, and the thing that does it is the SHAFT -- the operator's arm is
    folded flat across its body and this one has a bare spindle standing proud
    of the end, with nothing on it. Narrower than the operator too, and centred
    rather than filling the tile: it is a part, not a fitting."""
    i = Icon()
    # The can, on its side. Ribbed like the operator's body, because it is the
    # same kind of object -- the difference is what is on the end of it.
    i.box(5, 10, 21, 22, STEEL)
    i.rect(6, 11, 20, 12, STEEL_HI)
    i.rect(6, 20, 20, 21, STEEL_LO)
    for x in (9, 12, 15, 18):
        i.vline(x, 13, 19, STEEL_LO)
    # The end bell: the darker cap the shaft comes out of, and the two through
    # bolts that hold the can together.
    i.box(21, 12, 25, 20, CASE)
    i.rect(22, 13, 24, 14, CASE_HI)
    i.dot(23, 11, INK)
    i.dot(23, 21, INK)
    # The shaft, bare. Two pixels thick so it reads as a rod and not as a wire,
    # and it is the only thing on this icon that is a highlight all the way out.
    i.rect(26, 15, 30, 16, STEEL_HI)
    i.hline(26, 30, 14, INK)
    i.hline(26, 30, 17, INK)
    i.dot(31, 15, INK)
    i.dot(31, 16, INK)
    # The two leads out of the back of it, the contact's own brass.
    i.hline(1, 4, 13, BRASS)
    i.hline(1, 4, 19, BRASS)
    i.dot(0, 13, INK)
    i.dot(0, 19, INK)
    i.save("SmallMotor")


def wiring_guide():
    """The magazine the four recipes come out of, lying flat and seen square on:
    a dark cover, the masthead band across the top in the screen green, the
    house C under it, and the sliver of pages down the right edge that is the
    only thing telling a reader this is a magazine and not a box.

    The C is the hero and it is drawn big -- seven pixels by eleven. At 32
    pixels a mark small enough to be tasteful is a mark nobody can see, and this
    icon has to be told apart from four grey boxes in one inventory row."""
    i = Icon()
    # The pages first, so the cover is laid down on top of them and their edge
    # shows only where it sticks out: right and bottom, the way a magazine on a
    # table does.
    i.box(9, 5, 26, 30, CREAM)
    # The cover over them.
    i.box(6, 2, 24, 28, CASE)
    # The masthead: the title band, in the screen green, with the ink rule under
    # it that every CeroSec Systems cover has.
    i.rect(7, 3, 23, 6, GREEN)
    i.hline(7, 23, 7, INK)
    # The house C, dead centre of what is left of the cover.
    i.rect(11, 11, 12, 23, GREEN)
    i.rect(13, 11, 18, 12, GREEN)
    i.rect(13, 22, 18, 23, GREEN)
    # Two lines of cover text under it, dim: print, not screen.
    i.hline(8, 21, 25, CASE_HI)
    i.hline(8, 16, 27, CASE_HI)
    # And the shade down the inside of the spine, which is the left edge here.
    i.vline(7, 8, 27, CASE_HI)
    i.vline(23, 8, 27, STEEL_LO)
    i.save("WiringGuide")


magnetic_contact()
relay()
electric_strike()
door_operator()
small_motor()
wiring_guide()


# The contact sheet, on demand: the four icons at 1x over 4x on a checkerboard,
# which is the only way to judge a 32-pixel icon that will be looked at in an
# inventory row. Written into tools/out, which the repository does not keep.
if "--sheet" in sys.argv:
    import os
    zoom, pad = 4, 10
    cell = SIZE * zoom
    names = ["MagneticContact", "Relay", "ElectricStrike", "DoorOperator",
             "SmallMotor", "WiringGuide"]
    ims = [Image.open(OUT % n).convert("RGBA") for n in names]
    w = pad + len(ims) * (cell + pad)
    h = pad + SIZE + pad + cell + pad
    sheet = Image.new("RGBA", (w, h), (0, 0, 0, 255))
    for bx in range(0, w, 8):
        for by in range(0, h, 8):
            c = (58, 58, 64, 255) if (bx // 8 + by // 8) % 2 == 0 else (34, 34, 38, 255)
            for x in range(bx, min(bx + 8, w)):
                for y in range(by, min(by + 8, h)):
                    sheet.putpixel((x, y), c)
    for k, im in enumerate(ims):
        x = pad + k * (cell + pad)
        sheet.alpha_composite(im, (x + (cell - SIZE) // 2, pad))
        sheet.alpha_composite(im.resize((cell, cell), Image.NEAREST), (x, pad + SIZE + pad))
    os.makedirs("tools/out", exist_ok=True)
    sheet.save("tools/out/modules-sheet.png")
    print("wrote tools/out/modules-sheet.png")
