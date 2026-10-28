#!/usr/bin/env python3
"""Builds Oazy's built-in artwork for popular apps (assets/brand/*.webp.bin).

The .bin suffix keeps Godot from importing them, so they ship as small webp
files inside the exe (see include_filter in export_presets.cfg).

Each app's mark and name centred over its brand colours: soft light blooms, a
liquid-glass orb and fine grain, with the name set in Outfit. Marks come from
tools/brand_src/marks (CC0: @iconify-json/logos, simple-icons). A finished
cover, hero or logo in tools/brand_src/<slug>_{cover,hero,logo}.png is used as
it is (a given hero is cropped to the banner shape).
Run: python3 tools/make_brand_art.py  (needs Pillow, numpy, fonttools, brotli, cairosvg)
"""
import io, math, os, random, sys, tempfile, zlib
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont
from fontTools.ttLib import TTFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "brand")
SRC = os.path.join(ROOT, "tools", "brand_src")
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
    "flow": ("Flow", "Make images and video", "#0b0a1f", ["#7c6cff", "#265cd6", "#c58bff", "#2fd3e6"], "#f4f2ff"),
    "epicgameslauncher": ("Epic Games", "Play, free every week", "#0e0e10", ["#5a5a66", "#d8d8e2", "#2a2a34", "#0078f2"], "#ffffff"),
    "arcgisearth": ("ArcGIS Earth", "The whole planet, in 3D", "#02050c", ["#1f6fd1", "#0b2a5c", "#5fb4ff", "#0a1630"], "#ffffff"),
    "hyperliquid": ("Hyperliquid", "Trade on-chain", "#030809", ["#97fce4", "#1f6f62", "#5fe0c8", "#0b2e2a"], "#ffffff"),
    "youtube": ("YouTube", "Watch anything", "#0f0f0f", ["#ff0033", "#7a0019", "#ff5a6e", "#2a0008"], "#ffffff"),
    "suno": ("Suno", "Make any song", "#2a0b2e", ["#ff6a1a", "#b04ad8", "#ff2e4d", "#e8b0ff"], "#ffffff"),
    "microsoftteams": ("Teams", "Meet, chat, call", "#14123a", ["#5b5fc7", "#7b83eb", "#4b53bc", "#c5c9ff"], "#ffffff"),
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


def noise3(p, seed, octaves=6):
    """Fractal value noise at points p (N x 3), roughly 0..1."""
    rng = np.random.default_rng(seed)
    out = np.zeros(len(p), np.float32)
    amp, total, freq = 1.0, 0.0, 2.2
    for _ in range(octaves):
        n = 64
        grid = rng.random((n, n, n)).astype(np.float32)
        q = p * freq + rng.random(3) * 10 + 100
        i = np.floor(q).astype(int)
        f = q - i
        f = f * f * (3 - 2 * f)
        acc = 0
        for dx in (0, 1):
            for dy in (0, 1):
                for dz in (0, 1):
                    wgt = (f[:, 0] if dx else 1 - f[:, 0]) * (f[:, 1] if dy else 1 - f[:, 1]) * (f[:, 2] if dz else 1 - f[:, 2])
                    acc = acc + wgt * grid[(i[:, 0] + dx) % n, (i[:, 1] + dy) % n, (i[:, 2] + dz) % n]
        out += acc * amp
        total += amp
        amp *= 0.5
        freq *= 2.1
    return out / total


def earth(w, h, cx, cy, r, seed):
    """Earth from space: oceans, land, clouds, a thin blue atmosphere and stars."""
    rnd = np.random.default_rng(seed)
    img = np.zeros((h, w, 3), np.float32) + rgb("#02040a")
    # Stars, a few brighter than the rest.
    n = w * h // 900
    sx, sy = rnd.integers(0, w, n), rnd.integers(0, h, n)
    img[sy, sx] += (rnd.random(n) ** 6 * 0.9 + 0.08)[:, None] * rgb("#dfe9ff")
    y, x = np.mgrid[0:h, 0:w].astype(np.float32)
    nx, ny = (x - cx) / r, (y - cy) / r
    d2 = nx * nx + ny * ny
    on = d2 < 1
    nz = np.sqrt(np.clip(1 - d2, 0, 1))
    # Rotate the globe a little so the view isn't straight down the equator.
    t = 0.45
    px, py, pz = nx[on], ny[on] * math.cos(t) - nz[on] * math.sin(t), ny[on] * math.sin(t) + nz[on] * math.cos(t)
    pts = np.stack([px, py, pz], 1)
    land = noise3(pts, seed, 7)
    cloud = noise3(pts * np.array([1.2, 3.0, 1.2]), seed + 1, 6)
    lat = np.abs(py)
    sea = rgb("#0a3a7a") * 0.6 + rgb("#1560b8") * 0.4
    col = np.tile(sea, (len(pts), 1)) * (0.75 + 0.5 * land[:, None])
    is_land = land > 0.535
    green = rgb("#3d6b2f") * (1 - lat[:, None]) + rgb("#9a8a5c") * lat[:, None] * 0.6 + rgb("#3d6b2f") * lat[:, None] * 0.4
    dry = rgb("#b59a6a")
    mix = np.clip((noise3(pts * 2.0, seed + 2, 4) - 0.45) * 4, 0, 1)[:, None]
    lc = green * (1 - mix) + dry * mix
    col[is_land] = lc[is_land] * (0.8 + 0.4 * land[is_land, None])
    ice = lat + (land - 0.5) * 0.3 > 0.975
    col[ice] = rgb("#e8f0f8")
    c = np.clip((cloud - 0.54) * 4.0, 0, 1)[:, None]
    col = col * (1 - c * 0.85) + rgb("#f4f8ff") * c * 0.85
    # Sunlight from the upper left, with a soft terminator.
    light = np.array([-0.55, -0.45, 0.70])
    light /= np.linalg.norm(light)
    lam = nx[on] * light[0] + ny[on] * light[1] + nz[on] * light[2]
    shade = np.clip(lam * 1.3 + 0.12, 0.02, 1.0)[:, None]
    spec = (np.clip(lam, 0, 1) ** 40 * 0.35 * (~is_land))[:, None]
    col = col * shade + spec
    # Edge haze inside the globe.
    col = col * (1 - (1 - nz[on])[:, None] ** 3 * 0.5) + rgb("#5fb4ff") * ((1 - nz[on]) ** 4 * 0.45 * np.clip(lam + 0.4, 0, 1))[:, None]
    img[on] = col
    # Atmosphere glow just outside the rim, brightest on the lit side.
    dd = np.sqrt(d2)
    lit = np.clip((nx * light[0] + ny * light[1]) / np.maximum(dd, 1e-3) * 0.8 + 0.5, 0.05, 1)
    glow = np.exp(-((dd - 1.0) / 0.018) ** 2) * 0.55 + np.exp(-np.clip(dd - 1.0, 0, None) / 0.06) * (dd > 1) * 0.25
    img += (glow * lit)[..., None] * rgb("#6cc0ff")
    img += rnd.normal(0, 0.008, (h, w, 1)).astype(np.float32)
    return Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8))


SCENES = {
    # slug: (cover globe, hero globe), each (cx, cy, r) as fractions of the width
    "arcgisearth": ((0.5, 1.0, 0.64), (0.74, 0.50 * 1100 / 2560, 0.23)),
}


def mark(slug, size):
    """The app's mark, about size px on its long side, or None."""
    path = os.path.join(SRC, "marks", slug + ".svg")
    if not os.path.exists(path):
        return None
    import cairosvg
    png = cairosvg.svg2png(url=path, output_width=size * 4)
    im = Image.open(io.BytesIO(png)).convert("RGBA")
    im = im.crop(im.getbbox())
    k = size / max(im.size)
    return im.resize((max(1, round(im.width * k)), max(1, round(im.height * k))), Image.LANCZOS)


def paste_shadowed(im, layer, xy, blur):
    """Pastes layer at xy over a soft drop shadow."""
    shadow = Image.new("RGBA", im.size, (0, 0, 0, 0))
    a = layer.getchannel("A").point(lambda v: v * 0.55)
    shadow.paste(Image.new("RGBA", layer.size, (0, 0, 0, 255)), (xy[0], xy[1] + blur // 2), a)
    im.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(blur)))
    im.alpha_composite(layer, xy)


def centred_text(im, cy, text, fnt, ink, blur):
    b = fnt.getbbox(text)
    x = (im.width - (b[2] - b[0])) // 2 - b[0]
    text_shadow(im, (x, cy - (b[3] - b[1]) // 2 - b[1]), text, fnt, ink, blur)


def cover(slug, app):
    given = os.path.join(SRC, slug + "_cover.png")
    if os.path.exists(given):
        im = Image.open(given).convert("RGB").resize((600, 900), Image.LANCZOS)
        return im.filter(ImageFilter.UnsharpMask(2, 60, 2))
    title, tag, base, blooms, ink = app
    w, h = 600, 900
    if slug in SCENES:
        gx, gy, gr = SCENES[slug][0]
        im = earth(w, h, gx * w, gy * w, gr * w, zlib.crc32(slug.encode()) & 0xFFFF).convert("RGBA")
        centred_text(im, int(h * 0.11), title, fit(title, "title", w - 100, 92), ink, 12)
        centred_text(im, int(h * 0.11) + 72, tag, font("tag", 28), ink + "b0", 6)
        return im.convert("RGB")
    im = background(w, h, base, blooms, zlib.crc32(slug.encode()) & 0xFFFF, (0.5, 0.40), orb=0.25).convert("RGBA")
    m = mark(slug, 230)
    if m:
        paste_shadowed(im, m, ((w - m.width) // 2, int(h * 0.40) - m.height // 2), 18)
        centred_text(im, int(h * 0.72), title, fit(title, "title", w - 120, 88), ink, 10)
    else:
        # No mark: the name is the mark.
        centred_text(im, int(h * 0.40), title, fit(title, "title", w - 120, 120), ink, 12)
        centred_text(im, int(h * 0.72), tag, font("tag", 30), ink + "c0", 6)
    return im.convert("RGB")


def hero(slug, app):
    given = os.path.join(SRC, slug + "_hero.png")
    if os.path.exists(given):
        im = Image.open(given).convert("RGB")
        w, h = im.width, min(im.height, round(im.width * 1100 / 2560))
        w = min(w, round(h * 2560 / 1100))
        x, y = (im.width - w) // 2, (im.height - h) // 2
        im = im.crop((x, y, x + w, y + h)).resize((1600, 688), Image.LANCZOS)
        return im.filter(ImageFilter.UnsharpMask(2, 50, 2))
    _, _, base, blooms, _ = app
    if slug in SCENES:
        gx, gy, gr = SCENES[slug][1]
        return earth(2560, 1100, gx * 2560, gy * 2560, gr * 2560, zlib.crc32(slug.encode()) & 0xFFFF)
    return background(2560, 1100, base, blooms, (zlib.crc32(slug.encode()) & 0xFFFF) + 7, (0.72, 0.5), orb=0.13)


def logo(slug, app):
    """Mark and name side by side on transparency."""
    given = os.path.join(SRC, slug + "_logo.png")
    if os.path.exists(given):
        return Image.open(given).convert("RGBA")
    title, _, _, _, ink = app
    f = font("title", 200)
    b = f.getbbox(title)
    tw, th = b[2] - b[0], b[3] - b[1]
    m = mark(slug, int(th * 1.25))
    gap = int(th * 0.35) if m else 0
    mw, mh = (m.width, m.height) if m else (0, 0)
    pad = 40
    h = max(th, mh)
    im = Image.new("RGBA", (mw + gap + tw + pad * 2, h + pad * 2), (0, 0, 0, 0))
    if m:
        paste_shadowed(im, m, (pad, pad + (h - mh) // 2), 14)
    text_shadow(im, (pad + mw + gap - b[0], pad + (h - th) // 2 - b[1]), title, f, ink, 14)
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
