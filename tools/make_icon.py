"""Renders the Oazy logo mark into assets/icon.png and assets/icon.ico.

Run with: python3 tools/make_icon.py  (needs Pillow)
"""
import math
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
S = 1024


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(len(a)))


def squircle_mask(size, radius):
    m = Image.new("L", (size, size), 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, size - 1, size - 1), radius=radius, fill=255)
    return m


def render(size=S):
    # Diagonal gradient: deep lagoon -> clear aqua -> sunlit mint, an oasis pool.
    bg = Image.new("RGB", (size, size))
    px = bg.load()
    c0, c1, c2 = (6, 30, 46), (24, 150, 170), (150, 236, 196)
    for y in range(size):
        for x in range(size):
            t = (x * 0.35 + (size - y) * 0.65) / size
            col = lerp(c0, c1, min(t * 1.4, 1.0)) if t < 0.72 else lerp(c1, c2, (t - 0.72) / 0.28)
            px[x, y] = col
    # Soft light bloom in the top-right corner.
    glow = Image.new("L", (size, size), 0)
    ImageDraw.Draw(glow).ellipse((size * 0.45, -size * 0.25, size * 1.25, size * 0.55), fill=150)
    glow = glow.filter(ImageFilter.GaussianBlur(size * 0.12))
    bg = Image.composite(Image.new("RGB", (size, size), (120, 200, 255)), bg, glow.point(lambda v: v // 2))

    # The mark: an open ring with an orbiting dot.
    mark = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(mark)
    cx, cy, r, w = size * 0.5, size * 0.53, size * 0.255, size * 0.085
    d.arc((cx - r, cy - r, cx + r, cy + r), start=-35, end=265, fill=255, width=int(w))
    # Rounded caps.
    for ang in (-35, 265):
        a = math.radians(ang)
        ex, ey = cx + (r - w / 2) * math.cos(a), cy + (r - w / 2) * math.sin(a)
        d.ellipse((ex - w / 2, ey - w / 2, ex + w / 2, ey + w / 2), fill=255)
    a = math.radians(-62)
    dx, dy, dr = cx + r * 1.02 * math.cos(a), cy + r * 1.02 * math.sin(a), size * 0.062
    d.ellipse((dx - dr, dy - dr, dx + dr, dy + dr), fill=255)

    shadow = mark.filter(ImageFilter.GaussianBlur(size * 0.03)).point(lambda v: int(v * 0.45))
    bg = Image.composite(Image.new("RGB", (size, size), (2, 22, 32)), bg, shadow)
    bg = Image.composite(Image.new("RGB", (size, size), (255, 255, 255)), bg, mark)

    # Aero gloss: a soft glassy highlight over the top half.
    gloss = Image.new("L", (size, size), 0)
    ImageDraw.Draw(gloss).ellipse((-size * 0.35, -size * 0.62, size * 1.35, size * 0.46), fill=70)
    gloss = gloss.filter(ImageFilter.GaussianBlur(size * 0.035))
    bg = Image.composite(Image.new("RGB", (size, size), (255, 255, 255)), bg, gloss)

    out = bg.convert("RGBA")
    out.putalpha(squircle_mask(size, int(size * 0.23)))
    return out


def main():
    big = render()
    big.resize((512, 512), Image.LANCZOS).save(ROOT / "assets" / "icon.png")
    sizes = [(256, 256), (128, 128), (64, 64), (48, 48), (32, 32), (24, 24), (16, 16)]
    big.resize((256, 256), Image.LANCZOS).save(ROOT / "assets" / "icon.ico", sizes=sizes)


if __name__ == "__main__":
    main()
