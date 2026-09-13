#!/usr/bin/env python3
"""Cut the four published images out of the two pieces of source art.

Sources, both hand-made and never written by this script:

    workshop/art/poster.png   roughly 4:3   the CRT on the desk
    workshop/art/banner.png   roughly 16:5  the logo, the tagline, the bullets

Outputs, each at a size proven against the game rather than chosen:

    workshop/preview.png   512x512   the Steam Workshop preview image
    42/poster.png          512x512   the poster the B42 mod panel draws
    42/icon.png             64x64    the icon the mod list draws
    workshop/banner.png     630 wide the banner for the Steam description

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

  * workshop/banner.png is not read by the game at all, and the 1000 px this
    file used to say was wrong. The ceiling is Steam's own stylesheet, and it
    is 630. In public/css/skin_1/workshop.css on community.akamai.steamstatic
    .com, at the rule after .workshopItemDescription:

        .workshopItemDescription img {
            max-width: 630px;
        }

    So a 1000 px banner is not shown at 1000: the browser scales it to 630 and
    the hard edges of a pixel wordmark come back as grey ones. Everything meant
    for an [img] is therefore authored at exactly 630 and displays one image
    pixel to one CSS pixel. (The widely repeated "425" and "627" come from a
    community artwork guide and match nothing in the stylesheet.) The full-size
    art still goes up as an item screenshot, where clicking it shows all of it.
    See docs/RELEASE.md for how the URL reaches the description: Steam will not
    serve an [img] out of a file inside the mod, so it has to be hosted, and the
    item's own screenshots are the hosting.

Adjustable crops. Each is a box in FRACTIONS of the source image, left, top,
right, bottom, so it survives the art being redrawn at another size. A crop
that is not square is squared off around its own centre before the resize, so
none of the outputs is ever stretched.

The square poster: three candidates
-----------------------------------

The preview and the in-game poster have to be square and the art is 4:3, so
something has to give. Rather than argue about it, the script draws three and
`POSTER_CANDIDATE` says which one is published:

  A  a recomposition. The CRT scene is cut to a wide rectangle centred on the
     screen and the logo is re-placed under it on a band lifted out of the
     art's own dark tones. Keeps the monitor big and the wordmark legible;
     loses the outer edges of the desk.
  B  the whole poster, letterboxed, with the bars filled by a mirrored,
     blurred, darkened continuation of the art's own edge instead of flat
     black. Keeps every pixel of the composition; loses height on the subject,
     so the monitor is smaller than in A.
  C  no scene at all: the mark and the wordmark, large, on a CRT face generated
     in code (a centre glow, a vignette and raster lines), with the tagline
     drawn under them. Keeps the brand and reads at 200 px better than either
     of the others; loses the zombie, the desk and the whole of the atmosphere.

`tools/out/poster-candidates.png` puts all three side by side at both sizes on
neutral grey, which is the only honest way to judge a 200 px poster: the mod
panel draws it at 200 and half the argument is what survives down there.
"""

import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, str(Path(__file__).resolve().parent))
from cerosec_art import (BONE, CRT_BLACK, PHOSPHOR, fit_pixel_text,
                         glow_behind, key_dark, sample_phosphor,
                         scanline_field, screen_paste)

REPO = Path(__file__).resolve().parent.parent

SRC_POSTER = REPO / "workshop" / "art" / "poster.png"
SRC_BANNER = REPO / "workshop" / "art" / "banner.png"

OUT_PREVIEW = REPO / "workshop" / "preview.png"
OUT_POSTER = REPO / "42" / "poster.png"
OUT_ICON = REPO / "42" / "icon.png"
OUT_BANNER = REPO / "workshop" / "banner.png"

OUT_DIR = REPO / "tools" / "out"
OUT_SHEET = OUT_DIR / "poster-candidates.png"

# Sizes, from the proofs in the docstring above.
PREVIEW_PX = 512          # legal values are 256 and 512, nothing else
POSTER_PX = 512           # drawn at 200x200, square or it is squashed
ICON_PX = 64              # drawn at ~28x28
BANNER_WIDTH_PX = 630     # .workshopItemDescription img { max-width: 630px }
PREVIEW_MAX_BYTES = 1024000

# The preview and the in-game poster are the WHOLE poster, letterboxed into
# the square: the logo runs the full width of the art, so any square cut off
# the middle beheads it. The bars take the colour of the art's own edge.
# (Set PREVIEW_CROP to a fractional box to cut instead, e.g. (0.125,0,0.875,1).)
PREVIEW_CROP = None

# The square the icon is cut from. The logo sits at the left of the banner, so
# that is the source; set ICON_SOURCE to "poster" to take it off the poster
# instead. The box is squared off around its centre before the resize.
ICON_SOURCE = "banner"
ICON_CROP = (0.018, 0.09, 0.115, 0.50)   # the C mark, top left of the banner

POSTER_CROP = PREVIEW_CROP

# --------------------------------------------------------------------------
# The square poster
# --------------------------------------------------------------------------

# Which of the three is published as workshop/preview.png and 42/poster.png.
# All three are written to tools/out/ whichever this says.
POSTER_CANDIDATE = "A"

POSTER_SIZES = (512, 200)     # 512 is Steam's; 200 is what the mod panel draws

# Where the pieces of workshop/art/poster.png are, in fractions of it. Every one
# of these was measured off the file rather than eyeballed:
#
#   * the scene ends and the dark band begins at the image's darkest row, mean
#     brightness 12/255 at y=372 of 506;
#   * the band's two ink groups are separated by a 28 px gutter, x=173..201;
#   * the mark's ink runs y=379..464 and the wordmark's y=389..464. They do NOT
#     share a top, and the ten rows between them are not empty: a diagonal glint
#     off the desk edge crosses x=500..670 at y=378..388, as bright as the
#     letters are. One box around both therefore drags that glint into the lift,
#     where it reads as a scratch across the logo instead of as a highlight in a
#     photograph. So the mark and the wordmark are lifted SEPARATELY and set back
#     down with the gutter between them (logo_lockup), and the glint stays in the
#     scene it belongs to.
ART_SCENE = (0.0, 0.0, 1.0, 0.735)           # everything above the band
ART_MARK = (0.0587, 0.749, 0.264, 0.917)     # the C mark, y=379..464
ART_WORDMARK = (0.289, 0.769, 0.968, 0.917)  # "CeroSec", y=389..464
ART_TAGLINE = (0.100, 0.913, 0.905, 0.966)   # "UNIX NETWORK TERMINAL"
ART_BAND_TONE = (0.0, 0.972, 1.0, 1.0)       # clean dark band, no ink in it
ART_LOGO_GUTTER = 28 / 682.0                 # mark to wordmark, as measured

# --- A: the recomposition -------------------------------------------------
# The band is wide enough to matter because the scene crop's WIDTH is derived
# from it: a taller band means a wider slice of the desk, and at 182 the slice
# reaches from the bookshelf to past the window, which a 158 band did not.
A_BAND_PX = 182          # the logo band, out of 512
A_SCENE_CENTER_X = 0.50  # the crop's centre: the CRT's own centre, measured
A_LOGO_W = 446           # the mark and the wordmark across the band
A_GAP_TAG = 18           # logo to tagline
A_TAG_W = 306
A_RULE_PX = 2            # the phosphor hairline between scene and band
A_TONE_BLUR = 6          # the lifted band strip, smoothed of its own grain

# --- B: the honest letterbox ---------------------------------------------
B_EDGE_FRAC = 0.14       # how much of the art's edge is mirrored into a bar
B_BLUR = 14
B_DARKEN = 0.42
B_RULE_PX = 1

# --- C: the logo on a generated CRT face ---------------------------------
C_MARK_SCALE = 2         # whole number: the mark is pixel art, never resampled
C_WORD_W = 430
C_TAG_W = 330
C_GAP_MARK = 24
C_GAP_RULE = 22
C_GAP_TAG = 18
C_RULE_W = 430
C_LINE_EVERY = 3
C_LINE_DROP = 0.58
C_GLOW = 0.26
C_VIGNETTE = 0.58

SHEET_BG = (138, 138, 138)   # neutral grey: judge a poster against nothing
SHEET_PAD = 28
SHEET_GAP = 22
SHEET_LABEL_H = 40
SHEET_LABEL_W = 330          # the label, not the column: fit_pixel_text grows
SHEET_LABELS = {
    "A": "A   SCENE RECOMPOSED",
    "B": "B   LETTERBOX, SOFT BARS",
    "C": "C   LOGO ON A CRT FACE",
}


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


def edge_colour(src):
    """The average colour of the outermost pixels: what the bars are painted."""
    w, h = src.size
    px = src.convert("RGB").load()
    total = [0, 0, 0]
    n = 0
    for x in range(w):
        for y in (0, h - 1):
            for i in range(3):
                total[i] += px[x, y][i]
            n += 1
    return tuple(t // n for t in total)


def letterboxed(src, px, dest):
    """Fit the whole image into a px square on bars of its own edge colour."""
    scale = min(px / src.width, px / src.height)
    size = (max(1, round(src.width * scale)), max(1, round(src.height * scale)))
    fitted = src.convert("RGB").resize(size, Image.LANCZOS)
    out = Image.new("RGB", (px, px), edge_colour(src))
    out.paste(fitted, ((px - size[0]) // 2, (px - size[1]) // 2))
    out.save(dest, "PNG", optimize=True)
    return out


def square_or_box(src, box, px, dest):
    if box is None:
        return letterboxed(src, px, dest)
    return square_out(src, box, px, dest)


# --------------------------------------------------------------------------
# The three square posters. Each takes the art and answers a 512 RGB image;
# the 200 is that one resized, never a second composition, so what the mod
# panel draws is what the Workshop preview shows.
# --------------------------------------------------------------------------

def piece(src, box):
    """A fractional box of the source art as its own image, not squared off."""
    return src.convert("RGB").crop(to_pixels(box, src.size))


def scaled_to_width(img, width):
    height = max(1, round(img.height * width / img.width))
    return img.resize((width, height), Image.LANCZOS)


def logo_lockup(poster, width):
    """The mark and the wordmark, keyed off their ground and set side by side.

    Lifted separately and rebuilt rather than cut as one box, for the reason
    written against ART_MARK: a glint crosses the gap between their two tops.
    They are aligned on their BOTTOMS, which is how they sit in the art (both
    end at y=464) and which is the only edge they really share.
    """
    mark = key_dark(piece(poster, ART_MARK))
    word = key_dark(piece(poster, ART_WORDMARK))
    gutter_src = round(ART_LOGO_GUTTER * poster.width)

    src_w = mark.width + gutter_src + word.width
    scale = width / src_w
    mark = scaled_to_width(mark, max(1, round(mark.width * scale)))
    word = scaled_to_width(word, max(1, round(word.width * scale)))
    gutter = max(1, round(gutter_src * scale))

    height = max(mark.height, word.height)
    out = Image.new("RGBA", (mark.width + gutter + word.width, height), (0, 0, 0, 0))
    out.paste(mark, (0, height - mark.height), mark)
    out.paste(word, (mark.width + gutter, height - word.height), word)
    return out


def candidate_a(poster, green, px=512):
    """The CRT scene cut square, the logo re-placed on a band of the art's own
    dark tones. The crop is anchored on the screen's centre and its width is
    DERIVED from the band height, so moving the band moves the crop with it."""
    band_h = A_BAND_PX
    scene_h = px - band_h

    scene = piece(poster, ART_SCENE)
    # As wide a slice of the scene as the scene area's aspect will take, at the
    # scene's full height, centred on A_SCENE_CENTER_X and clamped to the art.
    want_w = min(scene.width, round(scene.height * px / scene_h))
    cx = A_SCENE_CENTER_X * scene.width
    left = max(0, min(round(cx - want_w / 2), scene.width - want_w))
    scene = scene.crop((left, 0, left + want_w, scene.height))
    scene = scene.resize((px, scene_h), Image.LANCZOS)

    out = Image.new("RGB", (px, px), CRT_BLACK)
    out.paste(scene, (0, 0))

    # The band: a strip of the art with no ink in it, stretched to fill.
    tone = piece(poster, ART_BAND_TONE).resize((px, band_h), Image.LANCZOS)
    tone = tone.filter(ImageFilter.GaussianBlur(A_TONE_BLUR))
    out.paste(tone, (0, scene_h))
    ImageDraw.Draw(out).rectangle(
        [0, scene_h, px, scene_h + A_RULE_PX - 1], fill=green)

    logo = logo_lockup(poster, A_LOGO_W)
    tag = fit_pixel_text("UNIX NETWORK TERMINAL", A_TAG_W, green, tracking=2)

    # The two are centred in the band as ONE group rather than hung off its top,
    # so changing the band height or the logo width cannot leave the pair
    # floating high with a hole under them.
    group = logo.height + A_GAP_TAG + tag.height
    ly = scene_h + A_RULE_PX + (band_h - A_RULE_PX - group) // 2
    out.paste(logo.convert("RGB"), ((px - logo.width) // 2, ly), logo)

    ty = ly + logo.height + A_GAP_TAG
    halo = glow_behind(tag)
    out.paste(halo.convert("RGB"), ((px - tag.width) // 2, ty), halo)
    out.paste(tag.convert("RGB"), ((px - tag.width) // 2, ty), tag)
    return out


def candidate_b(poster, green, px=512):
    """The whole poster on bars, the bars a mirrored, blurred, darkened
    continuation of the art's own edge rather than flat black."""
    art = poster.convert("RGB")
    fitted_h = max(1, round(art.height * px / art.width))
    fitted = art.resize((px, fitted_h), Image.LANCZOS)
    bar = (px - fitted_h) // 2

    out = Image.new("RGB", (px, px), CRT_BLACK)
    if bar > 0:
        strip_h = max(2, round(art.height * B_EDGE_FRAC))

        def extend(src_strip):
            # Mirrored, so the bar continues the picture outward instead of
            # repeating it; then blurred and taken down so nothing in it reads
            # as a subject.
            m = src_strip.transpose(Image.FLIP_TOP_BOTTOM)
            m = m.resize((px, bar), Image.LANCZOS)
            m = m.filter(ImageFilter.GaussianBlur(B_BLUR))
            return m.point(lambda v: int(v * B_DARKEN))

        out.paste(extend(art.crop((0, 0, art.width, strip_h))), (0, 0))
        out.paste(extend(art.crop((0, art.height - strip_h, art.width,
                                   art.height))), (0, px - bar))

    out.paste(fitted, (0, bar))
    if bar > 0 and B_RULE_PX:
        d = ImageDraw.Draw(out)
        d.rectangle([0, bar - B_RULE_PX, px, bar - 1], fill=green)
        d.rectangle([0, bar + fitted_h, px, bar + fitted_h + B_RULE_PX - 1],
                    fill=green)
    return out


def candidate_c(poster, banner, green, px=512):
    """The mark and the wordmark on a CRT face made in code. No scene."""
    out = scanline_field((px, px), phosphor=green, line_every=C_LINE_EVERY,
                         line_drop=C_LINE_DROP, glow=C_GLOW,
                         vignette=C_VIGNETTE)

    mark = key_dark(piece(poster, ART_MARK))
    mark = mark.resize((mark.width * C_MARK_SCALE, mark.height * C_MARK_SCALE),
                       Image.NEAREST)
    word = scaled_to_width(key_dark(piece(poster, ART_WORDMARK)), C_WORD_W)
    tag = fit_pixel_text("UNIX NETWORK TERMINAL", C_TAG_W, green, tracking=2)

    stack = (mark.height + C_GAP_MARK + word.height + C_GAP_RULE
             + A_RULE_PX + C_GAP_TAG + tag.height)
    y = (px - stack) // 2

    out.paste(mark.convert("RGB"), ((px - mark.width) // 2, y), mark)
    y += mark.height + C_GAP_MARK
    out.paste(word.convert("RGB"), ((px - word.width) // 2, y), word)
    y += word.height + C_GAP_RULE
    ImageDraw.Draw(out).rectangle(
        [(px - C_RULE_W) // 2, y, (px + C_RULE_W) // 2, y + A_RULE_PX - 1],
        fill=green)
    y += A_RULE_PX + C_GAP_TAG
    halo = glow_behind(tag)
    out.paste(halo.convert("RGB"), ((px - tag.width) // 2, y), halo)
    out.paste(tag.convert("RGB"), ((px - tag.width) // 2, y), tag)
    return out


def build_candidates(poster, banner, green):
    """The three, each at 512. Everything else is a resize of one of these."""
    return {
        "A": candidate_a(poster, green),
        "B": candidate_b(poster, green),
        "C": candidate_c(poster, banner, green),
    }


def contact_sheet(candidates, dest):
    """A, B and C at 512 and at 200, side by side on neutral grey.

    The 200 column is the point of the sheet. `ModInfoPanelDesc` draws poster 0
    at 200x200, so a composition that only works at 512 is a composition most
    of the people who install this will never see working.
    """
    big, small = POSTER_SIZES
    col_w = big + SHEET_GAP + small
    width = SHEET_PAD * 2 + 3 * col_w + 2 * SHEET_GAP * 2
    height = SHEET_PAD * 2 + SHEET_LABEL_H + big

    sheet = Image.new("RGB", (width, height), SHEET_BG)
    draw = ImageDraw.Draw(sheet)
    x = SHEET_PAD
    for key in ("A", "B", "C"):
        img = candidates[key]
        label = fit_pixel_text(SHEET_LABELS[key], SHEET_LABEL_W,
                               (26, 26, 26), tracking=1)
        sheet.paste(label.convert("RGB"), (x, SHEET_PAD), label)
        top = SHEET_PAD + SHEET_LABEL_H
        sheet.paste(img, (x, top))
        sheet.paste(img.resize((small, small), Image.LANCZOS),
                    (x + big + SHEET_GAP, top + big - small))
        draw.rectangle([x - 1, top - 1, x + big, top + big], outline=(60, 60, 60))
        draw.rectangle([x + big + SHEET_GAP - 1, top + big - small - 1,
                        x + big + SHEET_GAP + small, top + big],
                       outline=(60, 60, 60))
        x += col_w + SHEET_GAP * 2

    dest.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(dest, "PNG", optimize=True)
    return sheet


def main():
    missing = [p for p in (SRC_POSTER, SRC_BANNER) if not p.is_file()]
    if missing:
        for p in missing:
            print("missing source art: %s" % p, file=sys.stderr)
        print("Drop the two source images there; this script never draws them.",
              file=sys.stderr)
        return 1

    poster = Image.open(SRC_POSTER).convert("RGBA")
    banner = Image.open(SRC_BANNER).convert("RGBA")
    print("poster source %dx%d, banner source %dx%d"
          % (poster.width, poster.height, banner.width, banner.height))

    # The phosphor comes off the art, so a redrawn poster moves the green the
    # generated pieces are lit in instead of leaving them on last year's.
    green = sample_phosphor(SRC_POSTER)
    print("phosphor sampled off the art: %s" % (green,))

    candidates = build_candidates(poster, banner, green)
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for key, img in sorted(candidates.items()):
        for px in POSTER_SIZES:
            dest = OUT_DIR / ("poster-%s-%d.png" % (key, px))
            out = img if px == img.width else img.resize((px, px), Image.LANCZOS)
            out.save(dest, "PNG", optimize=True)
            print("%s %dx%d, %d bytes" % (dest, px, px, dest.stat().st_size))
    contact_sheet(candidates, OUT_SHEET)
    print("%s (A, B and C at %d and %d on neutral grey)"
          % (OUT_SHEET, POSTER_SIZES[0], POSTER_SIZES[1]))

    if POSTER_CANDIDATE not in candidates:
        print("POSTER_CANDIDATE is %r, which is not one of %s"
              % (POSTER_CANDIDATE, ", ".join(sorted(candidates))), file=sys.stderr)
        return 1
    chosen = candidates[POSTER_CANDIDATE]
    print("publishing candidate %s" % POSTER_CANDIDATE)

    chosen.resize((PREVIEW_PX, PREVIEW_PX), Image.LANCZOS).save(
        OUT_PREVIEW, "PNG", optimize=True)
    size = OUT_PREVIEW.stat().st_size
    print("%s %dx%d, %d bytes" % (OUT_PREVIEW, PREVIEW_PX, PREVIEW_PX, size))
    if size > PREVIEW_MAX_BYTES:
        # Steam's own ceiling. Say so rather than hand over a file the submit
        # screen will refuse with "PreviewFileSize".
        print("preview is over Steam's %d-byte ceiling: flatten it or drop to 256"
              % PREVIEW_MAX_BYTES, file=sys.stderr)
        return 1

    chosen.resize((POSTER_PX, POSTER_PX), Image.LANCZOS).save(
        OUT_POSTER, "PNG", optimize=True)
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
