"""Renders Oazy Files' icon into native/files/oazy_files.ico.

The same family as Oazy Terminal's: a night-glass squircle with a lagoon glow,
here holding an amber folder. Run with: python3 tools/make_files_icon.py  (needs Pillow)
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
S = 1024


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(len(a)))


def vertical(size, top, bottom):
    g = Image.new("RGB", (1, size))
    for y in range(size):
        g.putpixel((0, y), lerp(top, bottom, y / max(1, size - 1)))
    return g.resize((size, size))


def render(size=S):
    bg = Image.new("RGB", (size, size))
    px = bg.load()
    c0, c1 = (12, 20, 30), (34, 52, 66)
    for y in range(size):
        for x in range(size):
            px[x, y] = lerp(c1, c0, min(1.0, (y * 0.8 + x * 0.2) / size))
    glow = Image.new("L", (size, size), 0)
    ImageDraw.Draw(glow).ellipse((-size * 0.35, size * 0.45, size * 0.75, size * 1.35), fill=170)
    glow = glow.filter(ImageFilter.GaussianBlur(size * 0.14))
    bg = Image.composite(Image.new("RGB", (size, size), (40, 190, 175)), bg, glow.point(lambda v: v // 2))

    def shape(draw_fn):
        m = Image.new("L", (size, size), 0)
        draw_fn(ImageDraw.Draw(m))
        return m

    u = size / 64
    # Back of the folder with its tab.
    back = shape(lambda d: (
        d.rounded_rectangle((12 * u, 18 * u, 52 * u, 48 * u), radius=int(4 * u), fill=255),
        d.rounded_rectangle((12 * u, 15 * u, 28 * u, 24 * u), radius=int(3 * u), fill=255),
    ))
    # A sheet of paper peeking out.
    sheet = shape(lambda d: d.rounded_rectangle((16 * u, 22 * u, 48 * u, 38 * u), radius=int(2 * u), fill=255))
    front = shape(lambda d: d.rounded_rectangle((10 * u, 27 * u, 54 * u, 49 * u), radius=int(4.5 * u), fill=255))

    shadow = front.filter(ImageFilter.GaussianBlur(size * 0.03)).point(lambda v: v * 2 // 5)
    bg = Image.composite(Image.new("RGB", (size, size), (0, 0, 0)), bg, shadow.transform(shadow.size, Image.AFFINE, (1, 0, 0, 0, 1, -size * 0.02)))
    bg = Image.composite(vertical(size, (231, 166, 74), (181, 106, 34)), bg, back)
    bg = Image.composite(Image.new("RGB", (size, size), (250, 252, 255)), bg, sheet)
    bg = Image.composite(vertical(size, (255, 227, 160), (233, 154, 61)), bg, front)
    gloss = shape(lambda d: d.rounded_rectangle((10 * u, 27 * u, 54 * u, 37 * u), radius=int(4.5 * u), fill=110))
    gloss = Image.composite(gloss, Image.new("L", (size, size), 0), front)
    bg = Image.composite(Image.new("RGB", (size, size), (255, 255, 255)), bg, gloss)

    rim = Image.new("L", (size, size), 0)
    ImageDraw.Draw(rim).rounded_rectangle((size * 0.02, size * 0.02, size * 0.98, size * 0.98), radius=int(size * 0.22), outline=90, width=int(size * 0.012))
    fade = Image.linear_gradient("L").resize((size, size)).point(lambda v: 255 - v)
    rim = Image.composite(rim, Image.new("L", (size, size), 0), fade)
    bg = Image.composite(Image.new("RGB", (size, size), (255, 255, 255)), bg, rim)

    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, size - 1, size - 1), radius=int(size * 0.23), fill=255)
    out = bg.convert("RGBA")
    out.putalpha(mask)
    return out


if __name__ == "__main__":
    img = render()
    img.save(ROOT / "native/files/oazy_files.ico", sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
    img.resize((256, 256), Image.LANCZOS).save("/tmp/oazy_files_icon.png")
