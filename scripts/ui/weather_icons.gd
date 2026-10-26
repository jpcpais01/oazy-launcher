class_name WeatherIcons
## Full-colour weather glyphs (glossy sun, soft clouds, blue rain) drawn from
## SVG at runtime like Icons, so they stay crisp at any size.

const _HEAD := "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"64\" height=\"64\" viewBox=\"0 0 64 64\">"

const _DEFS := "<defs>" \
	+ "<radialGradient id=\"sun\" cx=\"0.38\" cy=\"0.34\" r=\"0.7\"><stop offset=\"0\" stop-color=\"#fff6c2\"/><stop offset=\"0.55\" stop-color=\"#ffd25a\"/><stop offset=\"1\" stop-color=\"#ff9f2e\"/></radialGradient>" \
	+ "<linearGradient id=\"moon\" x1=\"0\" y1=\"0\" x2=\"1\" y2=\"1\"><stop offset=\"0\" stop-color=\"#fbf9ff\"/><stop offset=\"1\" stop-color=\"#aebcea\"/></linearGradient>" \
	+ "<linearGradient id=\"cloud\" x1=\"0\" y1=\"15\" x2=\"0\" y2=\"48\" gradientUnits=\"userSpaceOnUse\"><stop offset=\"0\" stop-color=\"#ffffff\"/><stop offset=\"1\" stop-color=\"#c3d1e6\"/></linearGradient>" \
	+ "<linearGradient id=\"dark\" x1=\"0\" y1=\"15\" x2=\"0\" y2=\"48\" gradientUnits=\"userSpaceOnUse\"><stop offset=\"0\" stop-color=\"#d5dceb\"/><stop offset=\"1\" stop-color=\"#8391ab\"/></linearGradient>" \
	+ "<linearGradient id=\"bolt\" x1=\"0\" y1=\"0\" x2=\"0\" y2=\"1\"><stop offset=\"0\" stop-color=\"#fff0a0\"/><stop offset=\"1\" stop-color=\"#ffb52e\"/></linearGradient>" \
	+ "</defs>"

const _RAYS := "<g stroke=\"#ffc548\" stroke-width=\"3.6\" stroke-linecap=\"round\"><path d=\"M32 6v6M32 52v6M6 32h6M52 32h6M13.6 13.6l4.2 4.2M46.2 46.2l4.2 4.2M13.6 50.4l4.2-4.2M46.2 17.8l4.2-4.2\"/></g>"

static var _cache := {}


static func _sun(tx: float = 0.0, ty: float = 0.0, s: float = 1.0) -> String:
	return "<g transform=\"translate(%s %s) scale(%s)\">%s<circle cx=\"32\" cy=\"32\" r=\"13\" fill=\"url(#sun)\"/></g>" % [tx, ty, s, _RAYS]


static func _moon(tx: float = 0.0, ty: float = 0.0, s: float = 1.0) -> String:
	return "<g transform=\"translate(%s %s) scale(%s)\"><path d=\"M38 9a23 23 0 1 0 17 33A19 19 0 0 1 38 9z\" fill=\"url(#moon)\"/></g>" % [tx, ty, s]


static func _cloud(fill: String = "cloud", tx: float = 0.0, ty: float = 0.0, s: float = 1.0) -> String:
	return ("<g transform=\"translate(%s %s) scale(%s)\" fill=\"url(#%s)\">" % [tx, ty, s, fill]) \
		+ "<circle cx=\"22\" cy=\"38\" r=\"10\"/><circle cx=\"34\" cy=\"29\" r=\"14\"/><circle cx=\"46\" cy=\"37\" r=\"11\"/><rect x=\"22\" y=\"34\" width=\"24\" height=\"14\"/></g>"


static func _drops(n: int) -> String:
	var xs := [22.0, 32.0, 42.0] if n >= 3 else [26.0, 38.0]
	var out := "<g stroke=\"#5ec4ff\" stroke-width=\"3.4\" stroke-linecap=\"round\">"
	for x in xs:
		out += "<path d=\"M%s 49l-3 8\"/>" % x
	return out + "</g>"


static func svg(kind: String, day: bool = true) -> String:
	var body := ""
	match kind:
		"clear":
			body = _sun() if day else _moon(2, 2, 0.92)
		"partly":
			body = (_sun(-1, -1, 0.7) if day else _moon(1, -3, 0.66)) + _cloud("cloud", 4, 8, 0.92)
		"cloudy":
			body = _cloud("dark", -4, -6, 0.7) + _cloud("cloud", 2, 4, 0.98)
		"fog":
			body = _cloud("cloud", 0, -4) + "<g stroke=\"#c9d4e6\" stroke-width=\"3.4\" stroke-linecap=\"round\"><path d=\"M14 51h30M22 58h30\"/></g>"
		"drizzle":
			body = _cloud("cloud", 0, -6) + _drops(2)
		"rain":
			body = _cloud("dark", 0, -6) + _drops(3)
		"snow":
			body = _cloud("cloud", 0, -6) + "<g fill=\"#ffffff\"><circle cx=\"22\" cy=\"51\" r=\"2.6\"/><circle cx=\"32\" cy=\"56\" r=\"2.6\"/><circle cx=\"42\" cy=\"51\" r=\"2.6\"/></g>"
		"storm":
			body = _cloud("dark", 0, -8) + "<path d=\"M34 36l-9 13h7l-3 11 11-15h-7l3-9z\" fill=\"url(#bolt)\"/>"
		_:
			body = _cloud("cloud")
	return _HEAD + _DEFS + body + "</svg>"


## Renders `kind` (see Weather.kind_for) at `px` logical pixels, 2x internally.
static func tex(kind: String, day: bool = true, px: int = 24) -> Texture2D:
	var key := "%s|%s|%d" % [kind, day, px]
	if _cache.has(key):
		return _cache[key]
	var img := Image.new()
	if img.load_svg_from_string(svg(kind, day), float(px) / 64.0 * 2.0) != OK:
		img = Image.create(px * 2, px * 2, false, Image.FORMAT_RGBA8)
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	t.set_size_override(Vector2i(px, px))
	_cache[key] = t
	return t


## A TextureRect showing `kind`, centred and smoothly filtered.
static func rect(kind: String, day: bool = true, px: int = 24) -> TextureRect:
	var r := TextureRect.new()
	r.texture = tex(kind, day, px)
	r.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	r.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r
