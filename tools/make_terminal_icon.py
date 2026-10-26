"""Renders Oazy Terminal's icon into native/terminal/oazy_terminal.ico.

Run with: python3 tools/make_terminal_icon.py  (needs Pillow)
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
S = 1024


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(len(a)))


def render(size=S):
    # Night glass: deep slate with a lagoon glow rising from the bottom left.
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

    # The mark: a prompt chevron and a cursor bar, in Oazy aqua.
    mark = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(mark)
    w = int(size * 0.085)
    d.line([(size * 0.27, size * 0.33), (size * 0.47, size * 0.5), (size * 0.27, size * 0.67)], fill=255, width=w, joint="curve")
    for cx, cy in [(size * 0.27, size * 0.33), (size * 0.27, size * 0.67), (size * 0.47, size * 0.5)]:
        d.ellipse((cx - w / 2, cy - w / 2, cx + w / 2, cy + w / 2), fill=255)
    d.rounded_rectangle((size * 0.54, size * 0.63, size * 0.76, size * 0.63 + w), radius=w // 2, fill=255)
    shade = Image.new("RGB", (size, size))
    sp = shade.load()
    for y in range(size):
        col = lerp((170, 255, 236), (56, 214, 196), y / size)
        for x in range(size):
            sp[x, y] = col
    halo = mark.filter(ImageFilter.GaussianBlur(size * 0.03)).point(lambda v: v * 3 // 5)
    bg = Image.composite(Image.new("RGB", (size, size), (56, 214, 196)), bg, halo)
    bg = Image.composite(shade, bg, mark)

    # Glass rim along the top edge.
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
    img.save(ROOT / "native/terminal/oazy_terminal.ico", sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
    img.resize((256, 256), Image.LANCZOS).save("/tmp/oazy_terminal_icon.png")
