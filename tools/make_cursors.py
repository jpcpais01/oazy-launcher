#!/usr/bin/env python3
"""Renders Oazy's mouse pointer themes.

Every theme is a full Windows set (arrow, link hand, text, busy, working,
precision, unavailable, help, move, four resize arrows, alternate) drawn from
the vector shapes below, so they stay sharp at every size and DPI.

Writes:
  assets/cursors/<theme>.bin       one bundle per theme: a multi-size .cur
                                   (32 to 128 px) per still glyph, and the
                                   layers Oazy turns into the animated busy
                                   and working cursors at runtime (see
                                   scripts/autoload/cursors.gd)
  assets/cursors/<theme>/*.png     64 px images for previews in Settings and
                                   Godot's own cursor when the companion
                                   isn't there
  scripts/util/cursor_sets.gd      theme list, hotspots and layout

The spinners turn by 90 degree steps of FRAMES // 4 drawn frames, so only a
quarter of the animation is stored.

Needs: pip install cairosvg pillow
Run from the repo root: python3 tools/make_cursors.py
"""

import io
import math
import os
import struct
import sys

import cairosvg
from PIL import Image, ImageChops, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "cursors")
GD = os.path.join(ROOT, "scripts", "util", "cursor_sets.gd")

UNIT = 32  # design canvas
SIZES = [32, 48, 64, 96, 128]
PREVIEW = 64
FRAMES = 20
JIFFIES = 3  # 1/60 s per frame -> one turn a second
# Spinner centre and the square (design units) its layer is cut to.
SPIN = {"busy": ((16, 16), 32), "working": ((23, 24), 16)}

# --- Themes -------------------------------------------------------------------
# fill: gradient stops top -> bottom; line: outline; accent: spinners, badges;
# ring: the spinner's track; glass: translucent liquid-glass treatment;
# gloss: Aero-style highlight over the top half.

THEMES = [
    dict(id="oazy", name="Oazy", shape="dart", fill=["#ffffff", "#e3f6f3"], line="#0e2a2c", accent="#2fc8b6",
         ring="#d6eeeb", ow=1.25),
    dict(id="snow", name="Snow", shape="arrow", fill=["#ffffff", "#ffffff"], line="#101215", accent="#3a8dff",
         ring="#e6e8ec", ow=1.2),
    dict(id="ink", name="Ink", shape="arrow", fill=["#24272e", "#0a0b0e"], line="#ffffff", accent="#ffffff",
         ring="#3a3e47", ow=1.25),
    dict(id="aero", name="Aero", shape="arrow", fill=["#8fe0ff", "#1d74d8"], line="#ffffff", accent="#ffffff",
         ring="#0c4f9e", ow=1.3, gloss=True, rim="#0a3f86"),
    dict(id="glass", name="Liquid glass", shape="dart", fill=["#ffffff", "#cfefff"], line="#0b1a22",
         accent="#ffffff", ring="#ffffff", ow=1.0, glass=True),
    dict(id="lagoon", name="Lagoon", shape="dart", fill=["#5ff0dc", "#118fb5"], line="#ffffff", accent="#ffffff",
         ring="#0d6e86", ow=1.35),
    dict(id="ember", name="Ember", shape="dart", fill=["#ffc46b", "#f2546a"], line="#ffffff", accent="#ffffff",
         ring="#b8344a", ow=1.35),
    dict(id="orchid", name="Orchid", shape="dart", fill=["#ff9bd6", "#7a5cff"], line="#ffffff", accent="#ffffff",
         ring="#5a3fd0", ow=1.35),
    dict(id="graphite", name="Graphite", shape="dart", fill=["#4a5262", "#161a22"], line="#ffffff",
         accent="#7fe9da", ring="#2c323d", ow=1.25),
    dict(id="aurora", name="Aurora", shape="dart", fill=["#4ef0e0", "#8b6bff"], line="#0b1020", accent="#4ef0e0",
         ring="#232a46", ow=1.15, glow="#7ff6ff"),
]

# Godot cursor shape -> glyph, and Windows OCR_* id -> glyph.
GLYPHS = ["arrow", "hand", "text", "busy", "working", "cross", "no", "help", "move", "ns", "we", "nwse", "nesw",
          "up"]
ANIMATED = {"busy", "working"}


# --- Geometry -----------------------------------------------------------------

def pts(p):
    return "M" + " L".join("%.3f,%.3f" % xy for xy in p) + " Z"


ARROW = pts([(3, 2), (3, 24.2), (8.4, 19.2), (11.9, 27.2), (15.3, 25.7), (11.8, 17.9), (19.2, 17.9)])
DART = pts([(4, 3), (24.6, 12.6), (15.4, 15.6), (11.6, 25.6)])
POINTER_HOT = {"arrow": (3, 2), "dart": (4, 3)}


def rrect(x, y, w, h, r, extra=""):
    return '<rect x="%.3f" y="%.3f" width="%.3f" height="%.3f" rx="%.3f" %s/>' % (x, y, w, h, r, extra)


def hand_parts():
    # Pointing hand, index finger up. Drawn slightly under 32 units tall.
    s = []
    s.append(rrect(11.2, 2.0, 4.6, 17.0, 2.3))              # index
    s.append(rrect(15.6, 10.0, 4.4, 10.0, 2.2))             # middle
    s.append(rrect(19.8, 11.4, 4.2, 10.0, 2.1))             # ring
    s.append(rrect(23.8, 13.4, 3.8, 9.0, 1.9))              # little
    s.append('<path d="M11.2,15 L27.6,15 L27.6,21.5 C27.6,27 24.6,29.6 19.6,29.6 L17.2,29.6 '
             'C14.2,29.6 12.6,28.6 11.2,26.8 Z"/>')         # palm
    s.append(rrect(7.6, 14.6, 4.6, 11.0, 2.3, 'transform="rotate(-34 12.6 24.4)"'))  # thumb
    creases = [(15.7, 11.6, 15.7, 15.0), (19.8, 13.0, 19.8, 16.2), (23.8, 15.0, 23.8, 17.8)]
    return s, creases


def double_arrow(angle, length=11.0, head=6.2, half=4.7, shaft=2.3, single=False):
    """Shapes for a double (or single) headed arrow through the centre."""
    L = length
    parts = []
    tip_far = (L, 0)
    heads = [1] if single else [1, -1]
    start = 0 if single else -(L - head + 0.4)
    parts.append(("poly", [(start - (4 if single else 0), -shaft / 2), (L - head + 0.4, -shaft / 2),
                           (L - head + 0.4, shaft / 2), (start - (4 if single else 0), shaft / 2)]))
    for d in heads:
        parts.append(("poly", [(d * L, 0), (d * (L - head), -half), (d * (L - head), half)]))
    out = []
    a = math.radians(angle)
    ca, sa = math.cos(a), math.sin(a)
    for _, poly in parts:
        out.append('<path d="%s"/>' % pts([(16 + x * ca - y * sa, 16 + x * sa + y * ca) for x, y in poly]))
    return out, tip_far


def glyph_shapes(g, shape):
    """Returns (shapes, extras, hotspot). shapes: SVG elements filled with the
    theme; extras: callable(theme, frame) -> SVG drawn on top."""
    ptr = DART if shape == "dart" else ARROW
    hot_ptr = POINTER_HOT[shape]
    if g == "arrow":
        return ['<path d="%s"/>' % ptr], None, hot_ptr
    if g == "hand":
        s, creases = hand_parts()
        def ex(t, f):
            return "".join('<line x1="%.2f" y1="%.2f" x2="%.2f" y2="%.2f" stroke="%s" stroke-opacity="0.32" '
                           'stroke-width="0.7" stroke-linecap="round"/>' % (c + (t["line"],)) for c in creases)
        return s, ex, (13.5, 2.4)
    if g == "text":
        s = [rrect(15.05, 6.2, 1.9, 19.6, 0.5),
             '<path d="M11.6,5.2 C13.6,5.2 15.1,5.6 16,6.8 C16.9,5.6 18.4,5.2 20.4,5.2 L20.4,7.1 C18.4,7.1 17.4,7.6 '
             '16.95,8.6 L15.05,8.6 C14.6,7.6 13.6,7.1 11.6,7.1 Z"/>',
             '<path d="M11.6,26.8 C13.6,26.8 15.1,26.4 16,25.2 C16.9,26.4 18.4,26.8 20.4,26.8 L20.4,24.9 C18.4,24.9 '
             '17.4,24.4 16.95,23.4 L15.05,23.4 C14.6,24.4 13.6,24.9 11.6,24.9 Z"/>']
        return s, None, (16, 16)
    if g == "busy":
        return [], lambda t, f: spinner(t, f, 16, 16, 10.2, 3.6), (16, 16)
    if g == "working":
        return ['<path d="%s"/>' % ptr], lambda t, f: spinner(t, f, 23, 24, 5.0, 2.3), hot_ptr
    if g == "cross":
        return [], lambda t, f: crosshair(t), (16, 16)
    if g == "no":
        return [], lambda t, f: no_sign(t), (16, 16)
    if g == "help":
        return ['<path d="%s"/>' % ptr], lambda t, f: help_badge(t), hot_ptr
    if g == "move":
        a, _ = double_arrow(0, 12.0, 5.4, 4.0, 2.0)
        b, _ = double_arrow(90, 12.0, 5.4, 4.0, 2.0)
        return a + b, None, (16, 16)
    if g in ("ns", "we", "nwse", "nesw"):
        ang = {"ns": 90, "we": 0, "nwse": 45, "nesw": -45}[g]
        s, _ = double_arrow(ang, 11.6 if g in ("ns", "we") else 11.0)
        return s, None, (16, 16)
    if g == "up":
        s, _ = double_arrow(-90, 12.5, 6.4, 5.0, 2.3, single=True)
        return s, None, (16, 3.5)
    raise ValueError(g)


# --- Painting -----------------------------------------------------------------

def fill_paint(t, defs):
    defs.append('<linearGradient id="fill" gradientUnits="userSpaceOnUse" x1="0" y1="2" x2="6" y2="30">'
                '<stop offset="0" stop-color="%s"/><stop offset="1" stop-color="%s"/></linearGradient>'
                % (t["fill"][0], t["fill"][1]))
    return "url(#fill)"


def spinner(t, frame, cx, cy, r, w):
    ow = t["ow"]
    a0 = -90 + 360.0 * frame / FRAMES
    sweep = 112
    def arc(a_from, a_to):
        x0, y0 = cx + r * math.cos(math.radians(a_from)), cy + r * math.sin(math.radians(a_from))
        x1, y1 = cx + r * math.cos(math.radians(a_to)), cy + r * math.sin(math.radians(a_to))
        return "M%.3f,%.3f A%.3f,%.3f 0 0 1 %.3f,%.3f" % (x0, y0, r, r, x1, y1)
    out = []
    track_op = 0.35 if t.get("glass") else 1.0
    out.append('<circle cx="%.2f" cy="%.2f" r="%.2f" fill="none" stroke="%s" stroke-width="%.2f"/>'
               % (cx, cy, r, t["line"], w + ow * 2))
    out.append('<circle cx="%.2f" cy="%.2f" r="%.2f" fill="none" stroke="%s" stroke-opacity="%.2f" '
               'stroke-width="%.2f"/>' % (cx, cy, r, t["ring"], track_op, w))
    acc = t["accent"]
    out.append('<path d="%s" fill="none" stroke="%s" stroke-width="%.2f" stroke-linecap="round"/>'
               % (arc(a0, a0 + sweep), acc, w))
    # a softer tail behind the head
    out.append('<path d="%s" fill="none" stroke="%s" stroke-opacity="0.4" stroke-width="%.2f" '
               'stroke-linecap="round"/>' % (arc(a0 - 70, a0 + 4), acc, w))
    return "".join(out)


def crosshair(t):
    ow = t["ow"]
    segs = [(16, 3.5, 16, 12.2), (16, 19.8, 16, 28.5), (3.5, 16, 12.2, 16), (19.8, 16, 28.5, 16)]
    out = []
    for col, wd in ((t["line"], 1.7 + ow * 2), (t["fill"][0] if not t.get("glass") else "#ffffff", 1.7)):
        for s in segs:
            out.append('<line x1="%.2f" y1="%.2f" x2="%.2f" y2="%.2f" stroke="%s" stroke-width="%.2f" '
                       'stroke-linecap="round"/>' % (s + (col, wd)))
    out.append('<circle cx="16" cy="16" r="%.2f" fill="%s"/>' % (1.2 + ow, t["line"]))
    out.append('<circle cx="16" cy="16" r="1.2" fill="%s"/>' % t["accent"])
    return "".join(out)


def no_sign(t):
    ow = t["ow"]
    r, w = 9.6, 3.1
    d = r * 0.7071
    out = []
    for col, wd in ((t["line"], w + ow * 2), ("url(#fill)", w)):
        out.append('<circle cx="16" cy="16" r="%.2f" fill="none" stroke="%s" stroke-width="%.2f"/>' % (r, col, wd))
        out.append('<line x1="%.2f" y1="%.2f" x2="%.2f" y2="%.2f" stroke="%s" stroke-width="%.2f" '
                   'stroke-linecap="round"/>' % (16 - d, 16 - d, 16 + d, 16 + d, col, wd))
    return "".join(out)


def luma(c):
    return 0.2126 * int(c[1:3], 16) + 0.7152 * int(c[3:5], 16) + 0.0722 * int(c[5:7], 16)


def help_badge(t):
    ow = t["ow"]
    cx, cy, r = 23.2, 23.6, 5.6
    acc = t["accent"]
    # White accents get a white badge with the theme's own colour inside.
    q = min((t["fill"][1], t["line"]), key=luma) if acc.lower() == "#ffffff" else "#ffffff"
    return ('<circle cx="%.2f" cy="%.2f" r="%.2f" fill="%s"/>' % (cx, cy, r + ow, t["line"]) +
            '<circle cx="%.2f" cy="%.2f" r="%.2f" fill="%s"/>' % (cx, cy, r, acc) +
            '<path d="M21.3,22.1 C21.3,20.9 22.2,20.2 23.25,20.2 C24.4,20.2 25.2,20.95 25.2,21.95 C25.2,23.3 '
            '23.3,23.4 23.3,25.0" fill="none" stroke="%s" stroke-width="1.45" stroke-linecap="round" '
            'stroke-linejoin="round"/>' % q +
            '<circle cx="23.3" cy="27.0" r="0.95" fill="%s"/>' % q)


def svg(t, g, frame=0, part="shapes", view=(0, 0, 32)):
    """part: "shapes" (the outlined, filled glyph), "extras" (spinners,
    badges, crosshair) or "mask" (the glyph's fill area in white)."""
    shapes, extra, _ = glyph_shapes(g, t["shape"])
    defs = []
    paint = fill_paint(t, defs)
    ow = t["ow"]
    body = []
    group = "".join(shapes)
    if part == "mask" and shapes:
        body.append('<g fill="#fff" stroke="#fff" stroke-width="0.9" stroke-linejoin="round">%s</g>' % group)
    elif part == "shapes" and shapes:
        # Outline: every part stroked wide underneath, so overlapping parts
        # (the hand) read as one outlined silhouette.
        body.append('<g fill="%s" stroke="%s" stroke-width="%.2f" stroke-linejoin="round">%s</g>'
                    % (t["line"], t["line"], ow * 2 + 0.9, group))
        if t.get("glass"):
            # See-through body over a whisper of white so it never vanishes.
            body.append('<g opacity="0.18" fill="#ffffff" stroke="#ffffff" stroke-width="0.9" '
                        'stroke-linejoin="round">%s</g>' % group)
        # Group opacity, so overlapping parts don't stack up darker.
        fill_op = 0.40 if t.get("glass") else 1.0
        body.append('<g opacity="%.2f" fill="%s" stroke="%s" stroke-width="0.9" stroke-linejoin="round">%s</g>'
                    % (fill_op, paint, paint, group))
        if t.get("glass") or t.get("gloss"):
            # A specular sweep over the top of the glyph.
            defs.append('<clipPath id="clip">%s</clipPath>' % group)
            strong = 0.9 if t.get("gloss") else 0.75
            defs.append('<linearGradient id="spec" gradientUnits="userSpaceOnUse" x1="0" y1="2" x2="0" y2="17">'
                        '<stop offset="0" stop-color="#ffffff" stop-opacity="%.2f"/>'
                        '<stop offset="1" stop-color="#ffffff" stop-opacity="0.05"/></linearGradient>' % strong)
            body.append('<g clip-path="url(#clip)"><path d="M-2,-2 L34,-2 L34,10 C24,12 12,17 -2,22 Z" '
                        'fill="url(#spec)"/></g>')
    elif part == "extras" and extra:
        body.append(extra(t, frame))
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="{0}" height="{0}" viewBox="{3} {4} {0} {0}">'
            '<defs>{1}</defs>{2}</svg>').format(view[2], "".join(defs), "".join(body), view[0], view[1])


def _raster(t, g, frame, part, big, view=(0, 0, 32)):
    png = cairosvg.svg2png(bytestring=svg(t, g, frame, part, view).encode(), output_width=big, output_height=big)
    return Image.open(io.BytesIO(png)).convert("RGBA")


def _tint(alpha, color, strength):
    rgb = tuple(int(color[i:i + 2], 16) for i in (1, 3, 5))
    out = Image.new("RGBA", alpha.size, rgb + (0,))
    out.putalpha(alpha.point(lambda v: int(v * strength)))
    return out


def render(t, g, px, frame=0, layer="all"):
    """RGBA image at px: soft drop shadow, optional glow and glass rim.
    layer "base" leaves the spinner out (its shadow and glow stay), and
    "spin" is just the spinner, cut to its SPIN square."""
    ss = 4 if px < 64 else 2
    big = px * ss
    k = big / UNIT
    if layer == "spin":
        (cx, cy), side = SPIN[g]
        out = side * px // UNIT
        im = _raster(t, g, frame, "extras", out * ss, (cx - side / 2, cy - side / 2, side))
        return im.resize((out, out), Image.LANCZOS)
    shapes = _raster(t, g, frame, "shapes", big)
    extras = _raster(t, g, frame, "extras", big)
    top = Image.new("RGBA", shapes.size, (0, 0, 0, 0))
    top.alpha_composite(shapes)
    if t.get("glass") and glyph_shapes(g, t["shape"])[0]:
        mask = _raster(t, g, frame, "mask", big).getchannel("A")
        inner = mask.filter(ImageFilter.MinFilter(max(3, int(round(0.95 * k)) | 1)))
        rim = ImageChops.subtract(mask, inner)
        top.alpha_composite(_tint(rim.filter(ImageFilter.GaussianBlur(0.25 * k)), "#ffffff", 0.95))
    whole = top.copy()
    whole.alpha_composite(extras)
    if layer != "base":
        top = whole
    alpha = whole.getchannel("A")
    base = Image.new("RGBA", top.size, (0, 0, 0, 0))
    # Shadow from the alpha: nudged down, blurred, ~35 %.
    shadow = _tint(alpha.filter(ImageFilter.GaussianBlur(1.0 * k)), "#000000", 0.30 if t.get("glass") else 0.38)
    base.alpha_composite(shadow, (0, int(round(0.9 * k))))
    if t.get("glow"):
        base.alpha_composite(_tint(alpha.filter(ImageFilter.GaussianBlur(1.3 * k)), t["glow"], 0.75))
    base.alpha_composite(top)
    return base.resize((px, px), Image.LANCZOS)


# --- Windows file formats ----------------------------------------------------

def cur_bytes(images, hot):
    """ICO-style cursor with PNG-compressed entries (Vista and later)."""
    n = len(images)
    head = struct.pack("<HHH", 0, 2, n)
    dirs = b""
    data = b""
    offset = 6 + 16 * n
    for img in images:
        w = img.width
        buf = io.BytesIO()
        img.save(buf, "PNG", optimize=True)
        blob = buf.getvalue()
        hx = int(round(hot[0] * w / UNIT))
        hy = int(round(hot[1] * w / UNIT))
        dirs += struct.pack("<BBBBHHII", w % 256, w % 256, 0, 0, hx, hy, len(blob), offset)
        data += blob
        offset += len(blob)
    return head + dirs + data


def png(img):
    buf = io.BytesIO()
    img.save(buf, "PNG", optimize=True)
    return buf.getvalue()


def bundle(entries):
    """OZC1, entry count, then per entry: u16 name length, name, u32 size, data."""
    out = [b"OZC1", struct.pack("<I", len(entries))]
    for name, data in entries:
        n = name.encode()
        out += [struct.pack("<H", len(n)), n, struct.pack("<I", len(data)), data]
    return b"".join(out)


# --- Main ---------------------------------------------------------------------

def main():
    only = sys.argv[1:]
    quarter = FRAMES // 4
    for t in THEMES:
        if only and t["id"] not in only:
            continue
        d = os.path.join(OUT, t["id"])
        os.makedirs(d, exist_ok=True)
        entries = []
        for g in GLYPHS:
            hot = glyph_shapes(g, t["shape"])[2]
            if g in ANIMATED:
                for px in SIZES:
                    entries.append(("%s/base/%d" % (g, px), png(render(t, g, px, 0, "base"))))
                    for f in range(quarter):
                        entries.append(("%s/spin/%d/%d" % (g, px, f), png(render(t, g, px, f, "spin"))))
                render(t, g, PREVIEW, 0, "base").save(os.path.join(d, g + "_base.png"), optimize=True)
                render(t, g, PREVIEW, 0, "spin").save(os.path.join(d, g + "_spin.png"), optimize=True)
            else:
                entries.append((g + ".cur", cur_bytes([render(t, g, px) for px in SIZES], hot)))
            render(t, g, PREVIEW, 2).save(os.path.join(d, g + ".png"), optimize=True)
        with open(os.path.join(OUT, t["id"] + ".bin"), "wb") as fh:
            fh.write(bundle(entries))
        print("made", t["id"])
    if not only:
        write_gd()


def write_gd():
    def v(p):
        return "Vector2(%s, %s)" % (p[0], p[1])
    lines = ["class_name CursorSets", "## Generated by tools/make_cursors.py. Don't edit by hand.", "",
             "const GLYPHS: Array[String] = [%s]" % ", ".join('"%s"' % g for g in GLYPHS),
             "const ANIMATED: Array[String] = [%s]" % ", ".join('"%s"' % g for g in sorted(ANIMATED)),
             "## Design canvas the hotspots are measured in.", "const UNIT := %d" % UNIT,
             "const SIZES: Array[int] = [%s]" % ", ".join(str(x) for x in SIZES),
             "const PREVIEW := %d" % PREVIEW,
             "## Animation frames, of which FRAMES / 4 are stored (the rest are quarter turns).",
             "const FRAMES := %d" % FRAMES,
             "## Frame length in 1/60 s.", "const JIFFIES := %d" % JIFFIES,
             "## Spinner centre and the square its layer covers, in design units.",
             "const SPIN := {%s}" % ", ".join('"%s": {"center": %s, "side": %d}' % (g, v(c), side)
                                            for g, (c, side) in SPIN.items()),
             "const THEMES: Array[Dictionary] = ["]
    for t in THEMES:
        lines.append('\t{"id": "%s", "name": "%s", "shape": "%s"},' % (t["id"], t["name"], t["shape"]))
    lines.append("]")
    lines.append("const HOTSPOTS := {")
    for shape in ("arrow", "dart"):
        items = ", ".join('"%s": %s' % (g, v(glyph_shapes(g, shape)[2])) for g in GLYPHS)
        lines.append('\t"%s": {%s},' % (shape, items))
    lines.append("}")
    with open(GD, "w") as fh:
        fh.write("\n".join(lines) + "\n")


if __name__ == "__main__":
    main()
