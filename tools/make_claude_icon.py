"""Renders Oazy Claude's icon into native/claude/oazy_claude.ico.

Run with: python3 tools/make_claude_icon.py  (needs Pillow)
"""
import math
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
S = 1024


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(len(a)))


def render(size=S):
    # Warm glass: Claude's coral, deepening toward the bottom right.
    bg = Image.new("RGB", (size, size))
    px = bg.load()
    c0, c1 = (246, 172, 132), (178, 82, 50)
    for y in range(size):
        for x in range(size):
            px[x, y] = lerp(c0, c1, min(1.0, (y * 0.75 + x * 0.25) / size))
    glow = Image.new("L", (size, size), 0)
    ImageDraw.Draw(glow).ellipse((-size * 0.3, -size * 0.45, size * 0.9, size * 0.55), fill=120)
    glow = glow.filter(ImageFilter.GaussianBlur(size * 0.12))
    bg = Image.composite(Image.new("RGB", (size, size), (255, 214, 190)), bg, glow.point(lambda v: v // 2))

    # The mark: eight rounded rays around an open centre, in white.
    mark = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(mark)
    w = int(size * 0.078)
    c = size / 2
    for i in range(8):
        a = math.pi / 4 * i
        r0, r1 = size * 0.12, size * 0.33
        p0 = (c + math.cos(a) * r0, c + math.sin(a) * r0)
        p1 = (c + math.cos(a) * r1, c + math.sin(a) * r1)
        d.line([p0, p1], fill=255, width=w)
        for p in (p0, p1):
            d.ellipse((p[0] - w / 2, p[1] - w / 2, p[0] + w / 2, p[1] + w / 2), fill=255)
    shadow = mark.filter(ImageFilter.GaussianBlur(size * 0.02)).point(lambda v: v * 2 // 7)
    bg = Image.composite(Image.new("RGB", (size, size), (120, 44, 20)), bg, shadow)
    bg = Image.composite(Image.new("RGB", (size, size), (255, 250, 246)), bg, mark)

    rim = Image.new("L", (size, size), 0)
    ImageDraw.Draw(rim).rounded_rectangle((size * 0.02, size * 0.02, size * 0.98, size * 0.98), radius=int(size * 0.22), outline=110, width=int(size * 0.012))
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
    img.save(ROOT / "native/claude/oazy_claude.ico", sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
    img.resize((256, 256), Image.LANCZOS).save("/tmp/oazy_claude_icon.png")
