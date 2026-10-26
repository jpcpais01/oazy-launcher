"""Renders Oazy Browser's icon into native/browser/oazy_browser.ico.

A lagoon-glass squircle (the same family as Oazy's own icon) with a globe
whose lower half is water. Run with: python3 tools/make_browser_icon.py
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
S = 1024


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(len(a)))


def render(size=S):
    bg = Image.new("RGB", (size, size))
    px = bg.load()
    c0, c1, c2 = (8, 26, 52), (28, 126, 190), (120, 226, 214)
    for y in range(size):
        for x in range(size):
            t = (x * 0.3 + (size - y) * 0.7) / size
            px[x, y] = lerp(c0, c1, min(t * 1.35, 1.0)) if t < 0.74 else lerp(c1, c2, (t - 0.74) / 0.26)
    glow = Image.new("L", (size, size), 0)
    ImageDraw.Draw(glow).ellipse((size * 0.4, -size * 0.3, size * 1.3, size * 0.5), fill=140)
    glow = glow.filter(ImageFilter.GaussianBlur(size * 0.12))
    bg = Image.composite(Image.new("RGB", (size, size), (150, 220, 255)), bg, glow.point(lambda v: v // 2))

    mark = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(mark)
    cx, cy, r, w = size * 0.5, size * 0.5, size * 0.27, int(size * 0.06)
    d.ellipse((cx - r, cy - r, cx + r, cy + r), outline=255, width=w)
    # Meridian.
    d.ellipse((cx - r * 0.42, cy - r, cx + r * 0.42, cy + r), outline=255, width=int(w * 0.8))
    # Two waves across the globe: the oasis. Stamped round dots keep them smooth.
    import math
    ww = w * 0.8
    for yo, amp in ((0.0, 0.08), (0.32, 0.065)):
        for i in range(0, 801):
            t = i / 800
            x = cx - r * 1.0 + t * r * 2.0
            y = cy + r * yo + math.sin(t * math.pi * 2) * r * amp
            d.ellipse((x - ww / 2, y - ww / 2, x + ww / 2, y + ww / 2), fill=255)
    clip = Image.new("L", (size, size), 0)
    ImageDraw.Draw(clip).ellipse((cx - r, cy - r, cx + r, cy + r), fill=255)
    mark = Image.composite(mark, Image.new("L", (size, size), 0), clip)

    shadow = mark.filter(ImageFilter.GaussianBlur(size * 0.02)).point(lambda v: v * 0.35)
    img = bg.convert("RGBA")
    img = Image.composite(Image.new("RGBA", (size, size), (2, 12, 24, 255)), img, shadow.point(lambda v: int(v)))
    img = Image.composite(Image.new("RGBA", (size, size), (255, 255, 255, 255)), img, mark)

    m = Image.new("L", (size, size), 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, size - 1, size - 1), radius=int(size * 0.23), fill=255)
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    out.paste(img, (0, 0), m)
    return out


if __name__ == "__main__":
    big = render()
    dest = ROOT / "native" / "browser" / "oazy_browser.ico"
    big.save(dest, sizes=[(16, 16), (20, 20), (24, 24), (32, 32), (40, 40), (48, 48), (64, 64), (128, 128), (256, 256)])
    big.resize((256, 256), Image.LANCZOS).save("/tmp/oazy_browser_preview.png")
    print("wrote", dest)
