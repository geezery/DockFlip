"""Extend docs/assets/feature-flip.gif with the Windows 11 grid.

The original 128 frames (Flip 3D, type-to-filter, open a window) stay as they
are, with a "⌘Tab switcher  [Flip 3D | Grid]" toggle drawn in the top-right
corner. After them a pointer flips the toggle to Grid, the stack becomes a
Windows 11 style grid of tiles, Tab and Shift-Tab move the selection, and the
pointer flips the toggle back before the loop starts again.

The source is the Flip 3D-only GIF from commit d5b0c38, not the current one
(running this on its own output would add the grid twice):

    git show d5b0c38:docs/assets/feature-flip.gif > flip-only.gif
    python scripts/make-flip-grid-gif.py flip-only.gif docs/assets/feature-flip.gif

Needs Pillow; fonts come from site/fonts. A one-off helper for the
illustration, not part of the app or the site build.
"""
import os
import sys
from PIL import Image, ImageDraw, ImageFont, ImageFilter

SRC, OUT = sys.argv[1], sys.argv[2]
REPO = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
W, H, S = 1280, 800, 2  # drawn at 2x, then scaled down for smooth edges

BG = (12, 16, 15)
CARD = (24, 31, 29)
PILL_BG = (23, 30, 28)
PILL_LINE = (37, 48, 45)
INK = (233, 240, 236)
MUTED = (139, 154, 148)
GREEN = (31, 196, 141)
KEY_ON_BG = (26, 58, 48)
KEY_ON_LINE = (28, 126, 94)
KEY_ON_TEXT = (127, 239, 198)
KEY_OFF_BG = (28, 36, 34)
KEY_OFF_LINE = (53, 52, 50)

FONTS = os.path.join(REPO, 'site/fonts')
_fonts = {}


def font(weight, size):
    key = (weight, size)
    if key not in _fonts:
        _fonts[key] = ImageFont.truetype(os.path.join(FONTS, f'geist-{weight}.woff2'), size * S)
    return _fonts[key]


def sym_font(size):
    # ⌘ and ⇧ are not in Geist.
    for f in ('C:/Windows/Fonts/seguisym.ttf', 'C:/Windows/Fonts/segoeui.ttf'):
        if os.path.exists(f):
            return ImageFont.truetype(f, size * S)
    return font(600, size)


def mix(a, b, t):
    return tuple(round(x + (y - x) * t) for x, y in zip(a, b))


def layer():
    return Image.new('RGBA', (W * S, H * S), (0, 0, 0, 0))


def down(img):
    return img.resize((W, H), Image.LANCZOS)


def rr(d, box, r, fill=None, outline=None, width=1):
    x0, y0, x1, y1 = box
    d.rounded_rectangle((x0 * S, y0 * S, x1 * S, y1 * S), r * S, fill=fill,
                        outline=outline, width=width * S if outline else 0)


def text(d, xy, s, f, fill, anchor='la'):
    d.text((xy[0] * S, xy[1] * S), s, font=f, fill=fill, anchor=anchor)


def text_w(s, f):
    return f.getlength(s) / S


# ---------------------------------------------------------------- app icons

APPS = {
    'Inbox': ('Mail', (226, 97, 80), 'mail'),
    'Design team': ('Chat', (124, 96, 201), 'chat'),
    'Travel plan': ('Notes', (44, 172, 152), 'notes'),
    'Snapping.swift': ('Code', (98, 106, 110), 'code'),
    'Road trip mix': ('Music', (214, 90, 140), 'music'),
    'Quarterly plan': ('Browser', (67, 125, 222), 'globe'),
}
ORDER = ['Inbox', 'Design team', 'Travel plan', 'Snapping.swift', 'Road trip mix', 'Quarterly plan']


def icon(d, x, y, size, title):
    """An app icon like the ones in the stack: a rounded square with a white glyph."""
    color = APPS[title][1]
    top, bottom = mix(color, (255, 255, 255), 0.12), mix(color, (0, 0, 0), 0.06)
    r = size * 0.24
    # Vertical gradient, clipped to the rounded square.
    grad = Image.new('RGBA', (round(size * S), round(size * S)))
    gd = ImageDraw.Draw(grad)
    for i in range(grad.height):
        gd.line((0, i, grad.width, i), fill=mix(top, bottom, i / grad.height) + (255,))
    mask = Image.new('L', grad.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, grad.width - 1, grad.height - 1), r * S, fill=255)
    d._image.paste(grad, (round(x * S), round(y * S)), mask)
    white = (255, 255, 255, 245)
    c = (x + size / 2) * S, (y + size / 2) * S
    u = size * S / 100  # glyph units: the icon is 100 wide
    kind = APPS[title][2]
    if kind == 'mail':
        d.rounded_rectangle((c[0] - 26 * u, c[1] - 19 * u, c[0] + 26 * u, c[1] + 19 * u), 5 * u, fill=white)
        d.line((c[0] - 24 * u, c[1] - 15 * u, c[0], c[1] + 4 * u, c[0] + 24 * u, c[1] - 15 * u),
               fill=color + (255,), width=round(5 * u), joint='curve')
    elif kind == 'chat':
        d.ellipse((c[0] - 27 * u, c[1] - 22 * u, c[0] + 27 * u, c[1] + 18 * u), fill=white)
        d.polygon(((c[0] - 18 * u, c[1] + 8 * u), (c[0] - 24 * u, c[1] + 28 * u), (c[0] - 4 * u, c[1] + 15 * u)), fill=white)
    elif kind == 'notes':
        d.rounded_rectangle((c[0] - 20 * u, c[1] - 27 * u, c[0] + 20 * u, c[1] + 27 * u), 6 * u, fill=white)
        for k in (-12, 0, 12):
            d.line((c[0] - 11 * u, c[1] + k * u, c[0] + 11 * u, c[1] + k * u), fill=color + (255,), width=round(5 * u))
    elif kind == 'code':
        w = round(7 * u)
        d.line((c[0] - 8 * u, c[1] - 20 * u, c[0] - 26 * u, c[1], c[0] - 8 * u, c[1] + 20 * u), fill=white, width=w, joint='curve')
        d.line((c[0] + 8 * u, c[1] - 20 * u, c[0] + 26 * u, c[1], c[0] + 8 * u, c[1] + 20 * u), fill=white, width=w, joint='curve')
    elif kind == 'music':
        d.ellipse((c[0] - 22 * u, c[1] + 6 * u, c[0] - 2 * u, c[1] + 24 * u), fill=white)
        d.rectangle((c[0] - 7 * u, c[1] - 26 * u, c[0] - 1 * u, c[1] + 15 * u), fill=white)
        d.polygon(((c[0] - 7 * u, c[1] - 26 * u), (c[0] + 22 * u, c[1] - 18 * u), (c[0] + 22 * u, c[1] - 6 * u), (c[0] - 1 * u, c[1] - 13 * u)), fill=white)
    elif kind == 'globe':
        w = round(5 * u)
        d.ellipse((c[0] - 26 * u, c[1] - 26 * u, c[0] + 26 * u, c[1] + 26 * u), outline=white, width=w)
        d.ellipse((c[0] - 11 * u, c[1] - 26 * u, c[0] + 11 * u, c[1] + 26 * u), outline=white, width=w)
        d.line((c[0] - 26 * u, c[1], c[0] + 26 * u, c[1]), fill=white, width=w)
        d.line((c[0] - 22 * u, c[1] - 12 * u, c[0] + 22 * u, c[1] - 12 * u), fill=white, width=w)
        d.line((c[0] - 22 * u, c[1] + 12 * u, c[0] + 22 * u, c[1] + 12 * u), fill=white, width=w)


# ---------------------------------------------------------------- the toggle

TOGGLE_LABEL = '⌘Tab switcher'
SEGMENTS = ['Flip 3D', 'Grid']
T_RIGHT, T_TOP, T_H = 1232, 36, 44


def toggle_geometry():
    f = font(500, 16)
    widths = [text_w(s, f) + 36 for s in SEGMENTS]
    x1 = T_RIGHT
    x0 = x1 - sum(widths) - 8
    segs, x = [], x0 + 4
    for w in widths:
        segs.append((x, T_TOP + 4, x + w, T_TOP + T_H - 4))
        x += w
    return (x0, T_TOP, x1, T_TOP + T_H), segs


def draw_toggle(t, press=0.0):
    """t: 0 = Flip 3D chosen, 1 = Grid chosen; in between, the knob slides."""
    img = layer()
    d = ImageDraw.Draw(img)
    box, segs = toggle_geometry()
    rr(d, box, T_H / 2, fill=PILL_BG + (255,), outline=PILL_LINE + (255,), width=1)
    knob = tuple(a + (b - a) * t for a, b in zip(segs[0], segs[1]))
    shrink = 1.5 * press
    knob = (knob[0] + shrink, knob[1] + shrink, knob[2] - shrink, knob[3] - shrink)
    rr(d, knob, (knob[3] - knob[1]) / 2, fill=KEY_ON_BG + (255,), outline=KEY_ON_LINE + (255,), width=2)
    f = font(500, 16)
    for i, (s, seg) in enumerate(zip(SEGMENTS, segs)):
        on = 1 - t if i == 0 else t
        text(d, ((seg[0] + seg[2]) / 2, (seg[1] + seg[3]) / 2), s, f, mix(MUTED, KEY_ON_TEXT, on) + (255,), anchor='mm')
    rest = TOGGLE_LABEL[1:]
    rx = box[0] - 14
    cy = (box[1] + box[3]) / 2
    text(d, (rx, cy), rest, font(500, 15), MUTED + (255,), anchor='rm')
    text(d, (rx - text_w(rest, font(500, 15)) - 1, cy), '⌘', sym_font(15), MUTED + (255,), anchor='rm')
    return img


def segment_centre(i):
    _, segs = toggle_geometry()
    s = segs[i]
    return ((s[0] + s[2]) / 2, (s[1] + s[3]) / 2)


def draw_pointer(img, x, y, scale=1.0):
    """A macOS-like arrow pointer with its tip at (x, y)."""
    d = ImageDraw.Draw(img)
    pts = [(0, 0), (0, 25), (6, 19.5), (10.5, 29), (14.5, 27.2), (10.2, 18.2), (18, 18)]
    k = 1.15 * scale
    poly = [((x + px * k) * S, (y + py * k) * S) for px, py in pts]
    # No soft shadow: its faint pixels would stay behind in the GIF's delta frames.
    d.polygon(poly, fill=(255, 255, 255, 255), outline=(10, 10, 10, 255), width=round(1.6 * S))


# ---------------------------------------------------------------- keys and pill

def draw_key(d, x, label, pressed, w=80, sym=False):
    y = 684
    f = sym_font(40) if sym else font(600, 32)
    if pressed:
        rr(d, (x, y, x + w, y + 80), 14, fill=KEY_ON_BG + (255,), outline=KEY_ON_LINE + (255,), width=2)
        text(d, (x + w / 2, y + 40), label, f, KEY_ON_TEXT + (255,), anchor='mm')
    else:
        y -= 3
        rr(d, (x, y + 6, x + w, y + 83), 14, fill=(5, 7, 7, 255))
        rr(d, (x, y, x + w, y + 77), 14, fill=KEY_OFF_BG + (255,), outline=KEY_OFF_LINE + (255,), width=2)
        text(d, (x + w / 2, y + 38), label, f, INK + (255,), anchor='mm')


def draw_keys(d, tab_pressed, shift=False):
    draw_key(d, 48, '⌘', True, sym=True)
    x = 145
    if shift:
        draw_key(d, x, '⇧', True, sym=True)
        x += 97
    draw_key(d, x, 'tab', tab_pressed, w=115 if not tab_pressed else 115)


def draw_pill(d, title):
    app = APPS[title][0]
    ft, fa = font(600, 24), font(500, 24)
    tail = '· ' + app
    # Same metrics as the pill in the original frames (Inbox: x 516 to 765).
    w = 16 + 40 + 19 + text_w(title, ft) + 20 + text_w(tail, fa) + 26
    x0 = round(640.5 - w / 2)
    rr(d, (x0, 692, x0 + w, 760), 34, fill=PILL_BG + (255,), outline=PILL_LINE + (255,), width=2)
    icon(d, x0 + 16, 706, 40, title)
    text(d, (x0 + 75, 726), title, ft, INK + (255,), anchor='lm')
    text(d, (x0 + 75 + text_w(title, ft) + 20, 726), tail, fa, MUTED + (255,), anchor='lm')


# ---------------------------------------------------------------- the grid

COLS, TILE_W, TILE_H, GAP, PAD = 3, 284, 200, 22, 30
PANEL_W = COLS * TILE_W + (COLS - 1) * GAP + 2 * PAD
PANEL_H = 2 * TILE_H + GAP + 2 * PAD
PANEL_X = (W - PANEL_W) / 2
PANEL_Y = 112


def tile_box(i):
    r, c = divmod(i, COLS)
    x = PANEL_X + PAD + c * (TILE_W + GAP)
    y = PANEL_Y + PAD + r * (TILE_H + GAP)
    return (x, y, x + TILE_W, y + TILE_H)


def draw_grid_panel():
    img = layer()
    # Shadow under the panel.
    sh = Image.new('L', img.size, 0)
    ImageDraw.Draw(sh).rounded_rectangle(((PANEL_X) * S, (PANEL_Y + 24) * S, (PANEL_X + PANEL_W) * S, (PANEL_Y + PANEL_H + 30) * S), 26 * S, fill=170)
    sh = sh.filter(ImageFilter.GaussianBlur(36 * S))
    img.paste(Image.new('RGBA', img.size, (0, 0, 0, 255)), (0, 0), sh)
    d = ImageDraw.Draw(img)
    rr(d, (PANEL_X, PANEL_Y, PANEL_X + PANEL_W, PANEL_Y + PANEL_H), 26,
       fill=(19, 24, 23, 255), outline=PILL_LINE + (255,), width=1)
    for i, title in enumerate(ORDER):
        x0, y0, x1, y1 = tile_box(i)
        app, color, _ = APPS[title]
        # Header: small icon and the window's title, as in Windows 11.
        icon(d, x0 + 12, y0 + 12, 22, title)
        text(d, (x0 + 44, y0 + 23), title, font(500, 16), INK + (255,), anchor='lm')
        # The window's picture.
        px0, py0, px1, py1 = x0 + 12, y0 + 46, x1 - 12, y1 - 12
        rr(d, (px0, py0, px1, py1), 10, fill=CARD + (255,), outline=(36, 44, 42, 255), width=1)
        bar = mix(CARD, color, 0.17)
        d.rounded_rectangle((px0 * S + S, py0 * S + S, px1 * S - S, (py0 + 26) * S), 9 * S, fill=bar + (255,))
        d.rectangle((px0 * S + S, (py0 + 14) * S, px1 * S - S, (py0 + 26) * S), fill=bar + (255,))
        icon(d, px0 + 10, py0 + 6, 14, title)
        text(d, (px0 + 30, py0 + 13), title, font(500, 11), mix(INK, bar, 0.35) + (255,), anchor='lm')
        icon(d, px0 + 18, py0 + 46, 62, title)
        text(d, (px0 + 96, py0 + 62), title, font(600, 19), INK + (255,), anchor='lm')
        text(d, (px0 + 96, py0 + 88), app, font(400, 15), MUTED + (255,), anchor='lm')
    return img


def draw_selection(i):
    img = layer()
    x0, y0, x1, y1 = tile_box(i)
    glow = Image.new('L', img.size, 0)
    ImageDraw.Draw(glow).rounded_rectangle(((x0 - 6) * S, (y0 - 6) * S, (x1 + 6) * S, (y1 + 6) * S), 18 * S, outline=120, width=8 * S)
    glow = glow.filter(ImageFilter.GaussianBlur(10 * S))
    img.paste(Image.new('RGBA', img.size, GREEN + (255,)), (0, 0), glow.point(lambda v: v // 3))
    d = ImageDraw.Draw(img)
    rr(d, (x0 - 5, y0 - 5, x1 + 5, y1 + 5), 16, fill=(31, 196, 141, 22), outline=GREEN + (255,), width=3)
    return img


# ---------------------------------------------------------------- frames

def compose(base, *layers):
    out = base.convert('RGBA')
    for l in layers:
        out = Image.alpha_composite(out, down(l) if l.size != out.size else l)
    return out.convert('RGB')


def ease(t):
    return t * t * (3 - 2 * t)


src = Image.open(SRC)
orig = []
for i in range(src.n_frames):
    src.seek(i)
    orig.append((src.convert('RGB'), src.info.get('duration', 40)))

frames = []  # (image, duration ms)


def add(img, ms=40, exact=False):
    # exact: redraw every pixel that differs at all, so a crossfade leaves no ghost behind
    frames.append((img, ms, exact))


toggle_cache = {}


def toggle_layer(t, press=0.0):
    key = (round(t, 3), round(press, 3))
    if key not in toggle_cache:
        toggle_cache[key] = down(draw_toggle(t, press))
    return toggle_cache[key]


# 1. The original Flip 3D story, with the toggle on Flip 3D.
for img, ms in orig:
    add(compose(img, toggle_layer(0)), ms)
add(compose(orig[0][0], toggle_layer(0)), 40, exact=True)

stack = orig[0][0]  # the loop's first frame: the stack, Inbox in front

grid_panel = down(draw_grid_panel())


def grid_scene(sel, tab_pressed=False, shift=False):
    keys = layer()
    kd = ImageDraw.Draw(keys)
    draw_keys(kd, tab_pressed, shift)
    draw_pill(kd, ORDER[sel])
    return compose(Image.new('RGB', (W, H), BG), grid_panel, down(draw_selection(sel)), down(keys))


def flip_toggle(base, frm, to, start):
    """A pointer comes in, clicks the other segment, the knob slides, the pointer leaves."""
    target = segment_centre(to)
    tx, ty = target[0] + 6, target[1] + 4
    sx, sy = start
    for k in range(12):  # glide in
        t = ease((k + 1) / 12)
        p = layer()
        draw_pointer(p, sx + (tx - sx) * t, sy + (ty - sy) * t)
        add(compose(base, toggle_layer(frm), down(p)))
    for k, press in enumerate((0.6, 1.0, 0.6)):  # click
        p = layer()
        draw_pointer(p, tx, ty, 0.92 if press > 0.8 else 0.96)
        add(compose(base, toggle_layer(frm, press), down(p)))
    for k in range(7):  # the knob slides
        t = ease((k + 1) / 7)
        p = layer()
        draw_pointer(p, tx, ty)
        add(compose(base, toggle_layer(frm + (to - frm) * t), down(p)))
    p = layer()
    draw_pointer(p, tx, ty)
    add(compose(base, toggle_layer(to), down(p)), 360)
    for k in range(8):  # glide out
        t = ease((k + 1) / 8)
        p = layer()
        draw_pointer(p, tx + (sx - tx) * t, ty + (sy - ty) * t)
        add(compose(base, toggle_layer(to), down(p)))


def crossfade(a, b, n=9):
    for k in range(1, n + 1):
        add(Image.blend(a, b, ease(k / (n + 1))))


# 2. Switch to Grid, on the stack.
flip_toggle(stack, 0, 1, (1300, 330))

# 3. The stack becomes the grid.
g0 = compose(grid_scene(0), toggle_layer(1))
crossfade(compose(stack, toggle_layer(1)), g0)
add(g0, 700, exact=True)

# 4. Tab, Tab, then Shift-Tab back: the selection walks the grid.
for sel, shift in ((1, False), (2, False), (1, True), (0, True)):
    add(compose(grid_scene(sel, True, shift), toggle_layer(1)), 200)
    add(compose(grid_scene(sel, False, shift), toggle_layer(1)), 520 if sel else 400)

# 5. Back to Flip 3D, and the grid becomes the stack again: the loop restarts.
flip_toggle(g0, 1, 0, (1300, 330))
crossfade(compose(g0, toggle_layer(0)), compose(stack, toggle_layer(0)))
add(compose(stack, toggle_layer(0)), 40, exact=True)

# GIF: each frame stores only the rectangle that changed, quantized with its
# own 256-colour palette. Pillow's own writer re-quantizes whole frames, so
# static pixels flicker between palettes and every frame is stored in full.
import io
import struct
from PIL import ImageChops


def lzw_block(p_img):
    """Encode a P image with Pillow; return (colour table, size bits, LZW data)."""
    buf = io.BytesIO()
    p_img.save(buf, 'GIF', optimize=False, interlace=False)  # keep the indices, CLEAR included
    b = buf.getvalue()
    pos = 13
    packed = b[10]
    table, bits = None, None
    if packed & 0x80:
        bits = packed & 7
        n = 3 * (2 << bits)
        table = b[pos:pos + n]
        pos += n
    while b[pos] == 0x21:  # skip extensions
        pos += 2
        while b[pos]:
            pos += b[pos] + 1
        pos += 1
    assert b[pos] == 0x2C
    lp = b[pos + 9]
    pos += 10
    if lp & 0x80:
        bits = lp & 7
        n = 3 * (2 << bits)
        table = b[pos:pos + n]
        pos += n
    start = pos
    pos += 1  # LZW minimum code size
    while b[pos]:
        pos += b[pos] + 1
    pos += 1
    return table, bits, b[start:pos]


def changed_mask(a, b, threshold=6):
    r, g, bl = ImageChops.difference(a, b).split()
    return ImageChops.lighter(ImageChops.lighter(r, g), bl).point(lambda v: 255 if v > threshold else 0)


CLEAR = 255  # palette index for "keep what is on screen": runs of it compress to nearly nothing
out = bytearray(b'GIF89a' + struct.pack('<HHBBB', W, H, 0x70, 0, 0))
out += b'\x21\xFF\x0BNETSCAPE2.0\x03\x01\x00\x00\x00'
pieces = []  # (box, P image, ms, uses CLEAR)
shown = None
for img, ms, exact in frames:
    if shown is None:
        box, mask = (0, 0, W, H), None
    else:
        full = changed_mask(img, shown, 0 if exact else 6)
        box = full.getbbox()
        if box is None:
            pieces[-1] = pieces[-1][:2] + (pieces[-1][2] + ms,) + pieces[-1][3:]
            continue
        mask = full.crop(box)
    region = img.crop(box).quantize(colors=255, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    pal = region.getpalette()[:765]
    region.putpalette(pal + [0] * (768 - len(pal)))
    rgb = region.convert('RGB')
    if shown is None:
        shown = rgb
    else:
        shown.paste(rgb, box[:2], mask)
        region.paste(CLEAR, (0, 0) + region.size, ImageChops.invert(mask))
    pieces.append((box, region, ms, mask is not None))
for box, region, ms, clear in pieces:
    table, bits, data = lzw_block(region)
    assert bits == 7, bits
    out += b'\x21\xF9\x04' + bytes([0x05 if clear else 0x04]) + struct.pack('<H', round(ms / 10)) + bytes([CLEAR, 0])
    out += b'\x2C' + struct.pack('<HHHH', box[0], box[1], box[2] - box[0], box[3] - box[1]) + bytes([0x80 | bits])
    out += table + data
out += b'\x3B'
with open(OUT, 'wb') as f:
    f.write(out)
print(f'{len(pieces)} frames, {sum(p[2] for p in pieces) / 1000:.1f} s, {len(out) / 1e6:.2f} MB')

