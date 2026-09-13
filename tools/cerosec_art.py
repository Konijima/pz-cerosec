#!/usr/bin/env python3
"""The pieces the two image scripts share: the phosphor palette, a pixel text
renderer and the generated CRT field.

Nothing here opens a file the mod ships. It is a small library so that
`make-workshop-images.py` (the poster and the preview) and
`make-workshop-headers.py` (the seven section headers) draw the same green, the
same scanlines and the same letters, rather than two people's ideas of them.

**The letters.** The mod's own art is a chunky bitmap face and there is no ttf
of it on this machine, so it is approximated the way a bitmap face is really
made: a monospaced outline font is rendered *small*, with antialiasing thrown
away by a hard threshold, and the result is scaled up by a whole number with
nearest-neighbour. Every pixel of the output is then a square block of one
colour, which is what a 1993 screen font is. Rendering large and blurring down
would give grey edges, which is the one thing the art has none of.

**The green.** Read off `workshop/art/poster.png` rather than chosen: the
tagline "UNIX NETWORK TERMINAL" under the wordmark is the mod's phosphor, and
`PHOSPHOR` below is the mean of its lit pixels. `sample_phosphor()` re-reads it
from the art so a redrawn poster moves the palette with it.
"""

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

# The phosphor, measured off workshop/art/poster.png's tagline (see the
# docstring). Kept as a literal so a script can draw without opening the art.
PHOSPHOR = (126, 235, 141)
PHOSPHOR_DIM = (58, 118, 70)
CRT_BLACK = (8, 13, 9)          # the band under the logo in the poster art
BONE = (226, 226, 214)          # the wordmark's off-white

# A monospaced outline font every Ubuntu has. Only its shapes are used: the
# renderer throws its antialiasing away.
FONT_PATH = "/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf"
FONT_PATH_REG = "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf"

# Below this, a threshold turns thin stems into dust; above it, the blocks stop
# reading as pixels. Eight to fourteen is the usable window.
PIXEL_BASE_MIN = 7
INK_THRESHOLD = 110             # 0-255 on the rendered mask


def sample_phosphor(poster_path):
    """The mean colour of the lit pixels of the poster's tagline line."""
    img = Image.open(poster_path).convert("RGB")
    w, h = img.size
    # The tagline sits in the bottom band; in fractions so a redraw survives.
    box = (round(0.10 * w), round(0.920 * h), round(0.90 * w), round(0.960 * h))
    px = img.crop(box).load()
    bw, bh = box[2] - box[0], box[3] - box[1]
    tot = [0, 0, 0]
    n = 0
    for x in range(bw):
        for y in range(bh):
            r, g, b = px[x, y]
            if g > 90 and g - r > 25:
                tot[0] += r
                tot[1] += g
                tot[2] += b
                n += 1
    if not n:
        return PHOSPHOR
    return tuple(t // n for t in tot)


def pixel_text(text, base_px, scale, colour, bold=True, tracking=0):
    """One line of text as hard pixel blocks, on a transparent RGBA image.

    `base_px` is the size the outline font is rendered at and `scale` is the
    whole number every pixel of it is then blown up by, so the block size is
    exactly `scale` and the cap height is whatever `base_px` gives. `tracking`
    adds that many BASE pixels between characters, before the scale-up, which
    is how a bitmap face is letterspaced: in whole cells, never in fractions.
    """
    if base_px < PIXEL_BASE_MIN:
        raise ValueError("base_px %d is below the readable floor %d"
                         % (base_px, PIXEL_BASE_MIN))
    font = ImageFont.truetype(FONT_PATH if bold else FONT_PATH_REG, base_px)

    # Measure with the tracking already in, character by character, because a
    # letterspaced string has no single advance to ask the font for.
    advances = [round(font.getlength(ch)) + tracking for ch in text]
    width = max(1, sum(advances) - (tracking if text else 0))
    ascent, descent = font.getmetrics()
    height = ascent + descent

    mask = Image.new("L", (width + 2, height + 2), 0)
    draw = ImageDraw.Draw(mask)
    x = 1
    for ch, adv in zip(text, advances):
        draw.text((x, 1), ch, font=font, fill=255)
        x += adv

    # Throw the antialiasing away: a pixel is lit or it is not.
    mask = mask.point(lambda v: 255 if v >= INK_THRESHOLD else 0)
    mask = mask.crop(mask.getbbox() or (0, 0, 1, 1))
    mask = mask.resize((mask.width * scale, mask.height * scale), Image.NEAREST)

    out = Image.new("RGBA", mask.size, colour + (0,))
    out.putalpha(mask)
    return out


def text_block_width(text, base_px, scale, bold=True, tracking=0):
    """What pixel_text will come out at, without drawing it."""
    return pixel_text(text, base_px, scale, (255, 255, 255), bold, tracking).width


def fit_pixel_text(text, target_w, colour, bold=True, tracking=0, max_scale=6):
    """The largest whole-pixel rendering of `text` that fits `target_w`.

    Walks the scale down and the base size down inside it, so it prefers big
    blocks of a small font (which looks like a bitmap face) over small blocks
    of a big one (which looks like a screenshot of a word processor).
    """
    best = None
    for scale in range(max_scale, 0, -1):
        for base in range(22, PIXEL_BASE_MIN - 1, -1):
            img = pixel_text(text, base, scale, colour, bold, tracking)
            if img.width <= target_w:
                if best is None or img.height > best.height:
                    best = img
                break
    if best is None:
        best = pixel_text(text, PIXEL_BASE_MIN, 1, colour, bold, tracking)
    return best


def scanline_field(size, phosphor=PHOSPHOR, ground=CRT_BLACK,
                   line_every=3, line_drop=0.55, glow=0.30, vignette=0.55):
    """A dark CRT face: a centre glow in the phosphor, then the raster lines.

    `line_every` is the scanline pitch in pixels and `line_drop` is how much of
    the brightness a dark line keeps. `glow` is how far toward the phosphor the
    centre is lifted and `vignette` how much the corners are taken down. All
    generated: no file is read.
    """
    w, h = size
    field = Image.new("RGB", (w, h), ground)
    px = field.load()
    cx, cy = w / 2.0, h / 2.0
    radius = (cx * cx + cy * cy) ** 0.5
    for y in range(h):
        dy = (y - cy) / radius
        for x in range(w):
            dx = (x - cx) / radius
            d = (dx * dx + dy * dy) ** 0.5
            lift = glow * max(0.0, 1.0 - d * 1.9)
            fall = 1.0 - vignette * min(1.0, d * 1.25)
            r = (ground[0] + (phosphor[0] - ground[0]) * lift) * fall
            g = (ground[1] + (phosphor[1] - ground[1]) * lift) * fall
            b = (ground[2] + (phosphor[2] - ground[2]) * lift) * fall
            px[x, y] = (int(r), int(g), int(b))

    lines = Image.new("L", (w, h), 255)
    ld = ImageDraw.Draw(lines)
    for y in range(0, h, line_every):
        ld.line([(0, y), (w, y)], fill=int(255 * line_drop))
    return ImageChops.multiply(field, lines.convert("RGB"))


def key_dark(img, lo=30, hi=76):
    """Turn a crop of the art into an RGBA whose dark ground is transparent.

    The logo crops are lit pixels standing on the art's own near-black. Pasted,
    they stamp a rectangle of that near-black onto whatever is under them;
    screened, the rectangle shows up as a lighter box, because near-black is
    not black. So the ground is keyed out on brightness instead: below `lo` a
    pixel is gone, above `hi` it is whole, and between the two it fades, which
    keeps the soft edge the wordmark's own glow has instead of cutting a hard
    stencil out of it.
    """
    img = img.convert("RGB")
    lum = img.convert("L")
    span = max(1, hi - lo)
    alpha = lum.point(lambda v: 0 if v <= lo else (255 if v >= hi
                                                  else int(255 * (v - lo) / span)))
    out = img.convert("RGBA")
    out.putalpha(alpha)
    return out


def screen_paste(base, layer, xy):
    """Put `layer` on `base` with a screen blend, in place.

    The logo crops carry the art's own near-black behind them. Pasting them
    would stamp a black rectangle onto the field; screening lets the near-black
    disappear into whatever is under it and only the lit pixels land.
    """
    full = Image.new("RGB", base.size, (0, 0, 0))
    if layer.mode == "RGBA":
        full.paste(layer.convert("RGB"), xy, layer)
    else:
        full.paste(layer, xy)
    return ImageChops.screen(base, full)


def glow_behind(layer, radius=6, strength=0.55):
    """A soft halo of the layer's own light, for the bloom a CRT has."""
    if layer.mode != "RGBA":
        layer = layer.convert("RGBA")
    halo = layer.filter(ImageFilter.GaussianBlur(radius))
    alpha = halo.split()[3].point(lambda v: int(v * strength))
    halo.putalpha(alpha)
    return halo
