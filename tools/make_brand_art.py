#!/usr/bin/env python3
"""Builds Oazy's built-in artwork for popular apps (assets/brand/*.webp.bin).

The .bin suffix keeps Godot from importing them, so they ship as small webp
files inside the exe (see include_filter in export_presets.cfg).

Original art in each app's brand colours: soft light blooms, a liquid-glass
sheen and fine grain, with the name set in Outfit. No third-party logos.
Run: python3 tools/make_brand_art.py  (needs Pillow, numpy, fonttools, brotli)
"""
import math, os, random, sys, tempfile, zlib
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont
from fontTools.ttLib import TTFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "brand")
TMP = os.path.join(tempfile.gettempdir(), "oazy-brand-fonts")

# slug: (title, tagline, base, [bloom colours], ink)
APPS = {
    "claude": ("Claude", "Think it through", "#1f1b18", ["#d97757", "#f0b48f", "#a8543a", "#f5e6d6"], "#fbf3ea"),
    "claudecode": ("Claude Code", "Build with Claude", "#16130f", ["#d97757", "#7a3b26", "#f0a27d", "#2e2a26"], "#fbf3ea"),
    "discord": ("Discord", "Hang out together", "#1a1d4a", ["#5865f2", "#8a93ff", "#eb459e", "#3c45c8"], "#ffffff"),
    "higgsfield": ("Higgsfield", "Create with AI", "#0b0d08", ["#c8f31d", "#5f7d0c", "#e9ff7a", "#2b3a06"], "#f4ffd6"),
    "chrome": ("Chrome", "The web, fast", "#101a2e", ["#4285f4", "#ea4335", "#fbbc05", "#34a853"], "#ffffff"),
    "spotify": ("Spotify", "Music for everyone", "#07120b", ["#1db954", "#0f6e33", "#5ff28f", "#123b20"], "#eafff1"),
    "whatsapp": ("WhatsApp", "Simple. Private.", "#06231e", ["#25d366", "#128c7e", "#7af0b0", "#075e54"], "#effff6"),
    "visualstudiocode": ("VS Code", "Code, anywhere", "#0b1626", ["#007acc", "#1f9cf0", "#5fd0ff", "#0b3a66"], "#eef7ff"),
    "obsstudio": ("OBS Studio", "Record and stream", "#111114", ["#6b6b78", "#c9c9d6", "#3a3a46", "#8f86ff"], "#f4f4fa"),
    "steam": ("Steam", "Your game library", "#0d1622", ["#66c0f4", "#1b6fa8", "#2a475e", "#c7d5e0"], "#eef7ff"),
    "firefox": ("Firefox", "Browse freely", "#1d0f2e", ["#ff7139", "#e31587", "#9059ff", "#ffbd4f"], "#fff6ef"),
    "telegram": ("Telegram", "Messages, fast", "#071a2a", ["#2aabee", "#229ed9", "#8fd8ff", "#0b5f8f"], "#effaff"),
    "figma": ("Figma", "Design together", "#141414", ["#f24e1e", "#a259ff", "#1abcfe", "#0acf83"], "#ffffff"),
    "notion": ("Notion", "Your connected workspace", "#151515", ["#8a8a8a", "#e8e8e8", "#3a3a3a", "#c9b8a0"], "#ffffff"),
    "blender": ("Blender", "Make it in 3D", "#101b2a", ["#e87d0d", "#265787", "#f5a54a", "#5a8fc4"], "#fff7ee"),
    "slack": ("Slack", "Where work happens", "#2a0c2b", ["#36c5f0", "#2eb67d", "#ecb22e", "#e01e5a"], "#ffffff"),
    "epicgameslauncher": ("Epic Games", "Play, free every week", "#0e0e10", ["#5a5a66", "#d8d8e2", "#2a2a34", "#0078f2"], "#ffffff"),
}


def font(weight, size):
    os.makedirs(TMP, exist_ok=True)
    name = {"title": "Outfit-800", "tag": "Inter-500"}[weight]
    ttf = os.path.join(TMP, name + ".ttf")
    if not os.path.exists(ttf):
        f = TTFont(os.path.join(ROOT, "assets", "fonts", name + ".woff2"))
        f.flavor = None
        f.save(ttf)
    return ImageFont.truetype(ttf, size)


def rgb(h):
    h = h.lstrip("#")
    return np.array([int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)])


def background(w, h, base, blooms, seed, focus, orb=0.30):
    """Brand blooms over a deep base, a glass orb, an arc of light and grain.
    focus: where the light pools (0..1 of width/height); orb: orb radius."""
    rnd = random.Random(seed)
    s = max(w, h)
    y, x = np.mgrid[0:h, 0:w].astype(np.float32)
    x /= s
    y /= s
    fx, fy = focus[0] * w / s, focus[1] * h / s
    img = np.ones((h, w, 3), np.float32) * rgb(base)
    # Blooms: saturated pools of colour that keep the base dark between them.
    for i, c in enumerate(blooms + blooms[:2]):
        ang = rnd.uniform(0, math.tau)
        dist = rnd.uniform(0.08, 0.42)
        cx, cy = fx + math.cos(ang) * dist, fy + math.sin(ang) * dist * 0.8
        r = rnd.uniform(0.10, 0.24)
        a = rnd.uniform(0.55, 0.9) if i < len(blooms) else 0.35
        g = np.exp(-(((x - cx) ** 2 + (y - cy) ** 2) / (2 * r * r)))[..., None] * a
        img = img * (1 - g) + rgb(c) * g + rgb(c) * g * 0.25
    # Glass orb: darker, tinted body, bright rim, one soft specular highlight.
    d = np.sqrt((x - fx) ** 2 + (y - fy) ** 2) / orb
    inside = np.clip((1.0 - d) * 60, 0, 1)[..., None]
    tint = rgb(blooms[0]) * 0.5 + rgb(blooms[2 % len(blooms)]) * 0.5
    body = img * 0.72 + tint * 0.10 + (np.clip(d, 0, 1) ** 5 * 0.30)[..., None]
    hx, hy = fx - orb * 0.35, fy - orb * 0.48
    spec = np.exp(-(((x - hx) / (orb * 0.42)) ** 2 + ((y - hy) / (orb * 0.18)) ** 2))[..., None] * 0.30
    img = img * (1 - inside) + (body + spec) * inside
    rim = np.exp(-((d - 1.0) / 0.012) ** 2)[..., None] * 0.28
    halo = np.exp(-((d - 1.0) / 0.25) ** 2)[..., None] * (d > 1)[..., None] * 0.10
    img += rim + halo * rgb(blooms[0])
    # Arc of light sweeping through.
    cx, cy, rr = fx + 0.25, fy - 1.05, 1.25
    da = np.abs(np.sqrt((x - cx) ** 2 + (y - cy) ** 2) - rr)
    img += (np.exp(-(da / 0.003) ** 2) * 0.12 + np.exp(-(da / 0.04) ** 2) * 0.05)[..., None]
    # Vignette and grain.
    vx = (x * s / w - 0.5) * 2
    vy = (y * s / h - 0.5) * 2
    img *= (1.0 - 0.45 * np.clip(vx * vx * 0.5 + vy * vy * 0.7, 0, 1))[..., None]
    img += np.random.default_rng(seed).normal(0, 0.010, (h, w, 1)).astype(np.float32)
    return Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8))


def text_shadow(im, xy, text, fnt, ink, blur):
    shadow = Image.new("RGBA", im.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).text((xy[0], xy[1] + blur // 2), text, font=fnt, fill=(0, 0, 0, 150))
    im.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(blur)))
    ImageDraw.Draw(im).text(xy, text, font=fnt, fill=ink)


def fit(text, weight, width, start):
    size = start
    while size > 20:
        f = font(weight, size)
        if f.getbbox(text)[2] <= width:
            return f
        size -= 4
    return font(weight, size)


def cover(slug, app):
    title, tag, base, blooms, ink = app
    w, h = 600, 900
    im = background(w, h, base, blooms, zlib.crc32(slug.encode()) & 0xFFFF, (0.58, 0.33), orb=0.26).convert("RGBA")
    # Bottom scrim so the name always reads.
    scrim = np.linspace(0, 1, h)[:, None] ** 2.2 * 0.55
    shade = Image.fromarray((np.repeat(scrim, w, 1) * 255).astype(np.uint8), "L")
    im.alpha_composite(Image.merge("RGBA", [Image.new("L", (w, h), 0)] * 3 + [shade]))
    tf = fit(title, "title", w - 96, 104)
    tb = tf.getbbox(title)
    ty = h - 150 - (tb[3] - tb[1])
    text_shadow(im, (48, ty - tb[1]), title, tf, ink, 10)
    ImageDraw.Draw(im).text((50, h - 120), tag, font=font("tag", 30), fill=ink + "c0")
    return im.convert("RGB")


def hero(slug, app):
    _, _, base, blooms, _ = app
    return background(2560, 1100, base, blooms, (zlib.crc32(slug.encode()) & 0xFFFF) + 7, (0.72, 0.5), orb=0.13)


def logo(slug, app):
    title, _, _, _, ink = app
    f = font("title", 200)
    b = f.getbbox(title)
    pad = 40
    im = Image.new("RGBA", (b[2] - b[0] + pad * 2, b[3] - b[1] + pad * 2), (0, 0, 0, 0))
    text_shadow(im, (pad - b[0], pad - b[1]), title, f, ink, 14)
    return im


def main():
    os.makedirs(OUT, exist_ok=True)
    only = sys.argv[1:]
    for slug, app in APPS.items():
        if only and slug not in only:
            continue
        cover(slug, app).save(os.path.join(OUT, slug + "_cover.webp.bin"), "WEBP", quality=86, method=6)
        hero(slug, app).save(os.path.join(OUT, slug + "_hero.webp.bin"), "WEBP", quality=82, method=6)
        logo(slug, app).save(os.path.join(OUT, slug + "_logo.webp.bin"), "WEBP", quality=92, method=6)
        print("made", slug)


if __name__ == "__main__":
    main()
