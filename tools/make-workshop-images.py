#!/usr/bin/env python3
"""Cut the four published images out of the two pieces of source art.

Sources, both hand-made and never written by this script:

    workshop/art/poster.png   roughly 4:3   the CRT on the desk
    workshop/art/banner.png   roughly 16:5  the logo, the tagline, the bullets

Outputs, each at a size proven against the game rather than chosen:

    workshop/preview.png   512x512   the Steam Workshop preview image
    42/poster.png          512x512   the poster the B42 mod panel draws
    42/icon.png             64x64    the icon the mod list draws
    workshop/banner.png    1000 wide the banner for the Steam description

Where the sizes come from:

  * preview.png is read by SteamWorkshopItem.validatePreviewImage. Decompiled
    from the shipped jar (javap -p -c zombie.core.znet.SteamWorkshopItem), the
    method refuses the file in exactly three ways: over 1024000 bytes is
    "PreviewFileSize" (offset 34-47), width != height OR width neither 256 nor
    512 is "PreviewDimensions" (offset 82-120), and anything PNGDecoder cannot
    read is "PreviewFormat" (offset 189-197). So: PNG, square, 256 or 512, and
    under a megabyte. 512 is the larger of the two legal sizes.

  * 42/poster.png is poster 0, drawn by ModInfoPanel.Desc:render with
    drawTextureScaled(self.tex, ..., size, size) where size = 200
    (media/lua/client/OptionScreens/ModSelector/ModInfoPanelDesc.lua:12 and 14).
    drawTextureScaled does NOT keep the aspect ratio, so a poster that is not
    square is squashed into a square on screen. Hence a square source. 512 is
    two and a half times the drawn size, which covers the UI scale settings.

  * 42/icon.png is drawn at BUTTON_HGT x BUTTON_HGT, BUTTON_HGT being
    FONT_HGT_SMALL + 6 (ModListBox.lua:8 and :201), and at 28x28 in the load
    order list (ModOrderListBox.lua:235). Square and small: 64 is comfortably
    above both and is a power of two.

  * workshop/banner.png is not read by the game at all. Steam renders [img] in
    an item description at up to 1000 px wide before it scales the image down,
    so the banner is written out at 1000 px wide and left at its own aspect.
    See docs/RELEASE.md for how it reaches the description (Steam will not
    serve an [img] from a file inside the mod: it has to be hosted, and the
    item's own first screenshot is the hosting).

Adjustable crops. Each is a box in FRACTIONS of the source image, left, top,
right, bottom, so it survives Mathieu redrawing the art at another size. A crop
that is not square is squared off around its own centre before the resize, so
none of the outputs is ever stretched.
"""

import sys
from pathlib import Path

from PIL import Image

REPO = Path(__file__).resolve().parent.parent

SRC_POSTER = REPO / "workshop" / "art" / "poster.png"
SRC_BANNER = REPO / "workshop" / "art" / "banner.png"

OUT_PREVIEW = REPO / "workshop" / "preview.png"
OUT_POSTER = REPO / "42" / "poster.png"
OUT_ICON = REPO / "42" / "icon.png"
OUT_BANNER = REPO / "workshop" / "banner.png"

# Sizes, from the proofs in the docstring above.
PREVIEW_PX = 512          # legal values are 256 and 512, nothing else
POSTER_PX = 512           # drawn at 200x200, square or it is squashed
ICON_PX = 64              # drawn at ~28x28
BANNER_WIDTH_PX = 1000    # widest Steam shows an [img] before scaling it down
PREVIEW_MAX_BYTES = 1024000

# The square the preview is cut from the poster. The poster is 4:3, so a
# full-height square is 0.75 of its width; this box is that square centred,
# which lands on the CRT. Move it left or right (keep the width at 0.75) to
# recentre on the screen if the art puts the CRT off centre.
PREVIEW_CROP = (0.125, 0.0, 0.875, 1.0)

# The square the icon is cut from. The logo sits at the left of the banner, so
# that is the source; set ICON_SOURCE to "poster" to take it off the poster
# instead. The box is squared off around its centre before the resize.
ICON_SOURCE = "banner"
ICON_CROP = (0.015, 0.06, 0.20, 0.70)

# The square the in-game poster is cut from. Same 4:3 arithmetic as the
# preview: the whole height, centred.
POSTER_CROP = (0.125, 0.0, 0.875, 1.0)


def to_pixels(box, size):
    """A fractional box against an image size, as integer pixels."""
    w, h = size
    left, top, right, bottom = box
    return [round(left * w), round(top * h), round(right * w), round(bottom * h)]


def squared(box, size):
    """Grow the shorter side of a pixel box about its centre, clamped to the image."""
    w, h = size
    left, top, right, bottom = box
    side = min(max(right - left, bottom - top), w, h)
    cx = (left + right) / 2
    cy = (top + bottom) / 2
    left = round(cx - side / 2)
    top = round(cy - side / 2)
    left = max(0, min(left, w - side))
    top = max(0, min(top, h - side))
    return (left, top, left + side, top + side)


def square_out(src, box, px, dest):
    """Cut a square out of src, resize it to px, write it as a PNG."""
    cut = src.crop(squared(to_pixels(box, src.size), src.size))
    cut = cut.resize((px, px), Image.LANCZOS)
    cut.save(dest, "PNG", optimize=True)
    return cut


def main():
    missing = [p for p in (SRC_POSTER, SRC_BANNER) if not p.is_file()]
    if missing:
        for p in missing:
            print("missing source art: %s" % p, file=sys.stderr)
        print("Mathieu drops the two originals there; this script never draws them.",
              file=sys.stderr)
        return 1

    poster = Image.open(SRC_POSTER).convert("RGBA")
    banner = Image.open(SRC_BANNER).convert("RGBA")
    print("poster source %dx%d, banner source %dx%d"
          % (poster.width, poster.height, banner.width, banner.height))

    square_out(poster, PREVIEW_CROP, PREVIEW_PX, OUT_PREVIEW)
    size = OUT_PREVIEW.stat().st_size
    print("%s %dx%d, %d bytes" % (OUT_PREVIEW, PREVIEW_PX, PREVIEW_PX, size))
    if size > PREVIEW_MAX_BYTES:
        # Steam's own ceiling. Say so rather than hand over a file the submit
        # screen will refuse with "PreviewFileSize".
        print("preview is over Steam's %d-byte ceiling: flatten it or drop to 256"
              % PREVIEW_MAX_BYTES, file=sys.stderr)
        return 1

    square_out(poster, POSTER_CROP, POSTER_PX, OUT_POSTER)
    print("%s %dx%d" % (OUT_POSTER, POSTER_PX, POSTER_PX))

    icon_src = banner if ICON_SOURCE == "banner" else poster
    square_out(icon_src, ICON_CROP, ICON_PX, OUT_ICON)
    print("%s %dx%d (from the %s)" % (OUT_ICON, ICON_PX, ICON_PX, ICON_SOURCE))

    height = round(banner.height * BANNER_WIDTH_PX / banner.width)
    if banner.width <= BANNER_WIDTH_PX:
        wide = banner.copy()
    else:
        wide = banner.resize((BANNER_WIDTH_PX, height), Image.LANCZOS)
    wide.save(OUT_BANNER, "PNG", optimize=True)
    print("%s %dx%d" % (OUT_BANNER, wide.width, wide.height))

    return 0


if __name__ == "__main__":
    sys.exit(main())
