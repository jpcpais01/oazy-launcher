class_name Icons
## Stroke icons (24x24 grid, Lucide style) rendered from SVG at runtime, so they
## stay razor sharp at any UI scale and need no imported assets.

const _HEAD := "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"24\" height=\"24\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\">"

const SVGS := {
	"play": "<path d=\"M7 4.8v14.4a1 1 0 0 0 1.5.86l12-7.2a1 1 0 0 0 0-1.72l-12-7.2A1 1 0 0 0 7 4.8z\" fill=\"currentColor\"/>",
	"plus": "<path d=\"M12 5v14M5 12h14\"/>",
	"search": "<circle cx=\"11\" cy=\"11\" r=\"7\"/><path d=\"m20 20-3.5-3.5\"/>",
	"settings": "<path d=\"M12.22 2h-.44a2 2 0 0 0-2 2v.18a2 2 0 0 1-1 1.73l-.43.25a2 2 0 0 1-2 0l-.15-.08a2 2 0 0 0-2.73.73l-.22.38a2 2 0 0 0 .73 2.73l.15.1a2 2 0 0 1 1 1.72v.51a2 2 0 0 1-1 1.74l-.15.09a2 2 0 0 0-.73 2.73l.22.38a2 2 0 0 0 2.73.73l.15-.08a2 2 0 0 1 2 0l.43.25a2 2 0 0 1 1 1.73V20a2 2 0 0 0 2 2h.44a2 2 0 0 0 2-2v-.18a2 2 0 0 1 1-1.73l.43-.25a2 2 0 0 1 2 0l.15.08a2 2 0 0 0 2.73-.73l.22-.39a2 2 0 0 0-.73-2.73l-.15-.08a2 2 0 0 1-1-1.74v-.5a2 2 0 0 1 1-1.74l.15-.09a2 2 0 0 0 .73-2.73l-.22-.38a2 2 0 0 0-2.73-.73l-.15.08a2 2 0 0 1-2 0l-.43-.25a2 2 0 0 1-1-1.73V4a2 2 0 0 0-2-2z\"/><circle cx=\"12\" cy=\"12\" r=\"3\"/>",
	"home": "<path d=\"M3 10.5 12 3l9 7.5\"/><path d=\"M5 9v11a1 1 0 0 0 1 1h4v-6h4v6h4a1 1 0 0 0 1-1V9\"/>",
	"grid": "<rect x=\"3\" y=\"3\" width=\"7\" height=\"7\" rx=\"1.5\"/><rect x=\"14\" y=\"3\" width=\"7\" height=\"7\" rx=\"1.5\"/><rect x=\"3\" y=\"14\" width=\"7\" height=\"7\" rx=\"1.5\"/><rect x=\"14\" y=\"14\" width=\"7\" height=\"7\" rx=\"1.5\"/>",
	"heart": "<path d=\"M19 14c1.49-1.46 3-3.21 3-5.5A5.5 5.5 0 0 0 16.5 3c-1.76 0-3 .5-4.5 2-1.5-1.5-2.74-2-4.5-2A5.5 5.5 0 0 0 2 8.5c0 2.3 1.5 4.05 3 5.5l7 7Z\"/>",
	"heart_fill": "<path d=\"M19 14c1.49-1.46 3-3.21 3-5.5A5.5 5.5 0 0 0 16.5 3c-1.76 0-3 .5-4.5 2-1.5-1.5-2.74-2-4.5-2A5.5 5.5 0 0 0 2 8.5c0 2.3 1.5 4.05 3 5.5l7 7Z\" fill=\"currentColor\"/>",
	"more": "<circle cx=\"5\" cy=\"12\" r=\"1.4\" fill=\"currentColor\"/><circle cx=\"12\" cy=\"12\" r=\"1.4\" fill=\"currentColor\"/><circle cx=\"19\" cy=\"12\" r=\"1.4\" fill=\"currentColor\"/>",
	"close": "<path d=\"M18 6 6 18M6 6l12 12\"/>",
	"minimize": "<path d=\"M5 12h14\"/>",
	"maximize": "<rect x=\"5\" y=\"5\" width=\"14\" height=\"14\" rx=\"2\"/>",
	"restore": "<rect x=\"4\" y=\"8\" width=\"12\" height=\"12\" rx=\"2\"/><path d=\"M8 8V6a2 2 0 0 1 2-2h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2h-2\"/>",
	"download": "<path d=\"M12 3v12\"/><path d=\"m7 10 5 5 5-5\"/><path d=\"M5 21h14\"/>",
	"refresh": "<path d=\"M21 12a9 9 0 0 1-15.5 6.2L3 16\"/><path d=\"M3 21v-5h5\"/><path d=\"M3 12a9 9 0 0 1 15.5-6.2L21 8\"/><path d=\"M21 3v5h-5\"/>",
	"check": "<path d=\"M20 6 9 17l-5-5\"/>",
	"folder": "<path d=\"M4 20h16a2 2 0 0 0 2-2V8a2 2 0 0 0-2-2h-7.93a2 2 0 0 1-1.66-.9l-.82-1.2A2 2 0 0 0 7.93 3H4a2 2 0 0 0-2 2v13c0 1.1.9 2 2 2Z\"/>",
	"edit": "<path d=\"M12 20h9\"/><path d=\"M16.4 3.6a2.1 2.1 0 0 1 3 3L7 19l-4 1 1-4Z\"/>",
	"trash": "<path d=\"M3 6h18\"/><path d=\"M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6\"/><path d=\"M8 6V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2\"/>",
	"image": "<rect x=\"3\" y=\"3\" width=\"18\" height=\"18\" rx=\"2.5\"/><circle cx=\"9\" cy=\"9\" r=\"2\"/><path d=\"m21 15-3.1-3.1a2 2 0 0 0-2.8 0L6 21\"/>",
	"sparkles": "<path d=\"M9.94 15.5A2 2 0 0 0 8.5 14.06l-6.13-1.58a.5.5 0 0 1 0-.96L8.5 9.94A2 2 0 0 0 9.94 8.5l1.58-6.13a.5.5 0 0 1 .96 0L14.06 8.5A2 2 0 0 0 15.5 9.94l6.13 1.58a.5.5 0 0 1 0 .96L15.5 14.06a2 2 0 0 0-1.44 1.44l-1.58 6.13a.5.5 0 0 1-.96 0z\"/><path d=\"M20 3v4M22 5h-4\"/>",
	"info": "<circle cx=\"12\" cy=\"12\" r=\"10\"/><path d=\"M12 16v-4M12 8h.01\"/>",
	"alert": "<circle cx=\"12\" cy=\"12\" r=\"10\"/><path d=\"M12 8v4M12 16h.01\"/>",
	"gamepad": "<path d=\"M6 11h4M8 9v4M15 12h.01M18 10h.01\"/><path d=\"M17.32 5H6.68a4 4 0 0 0-3.98 3.59C2.6 9.42 2 14.46 2 16a3 3 0 0 0 3 3c1 0 1.5-.5 2-1l1.41-1.41A2 2 0 0 1 9.83 16h4.34a2 2 0 0 1 1.41.59L17 18c.5.5 1 1 2 1a3 3 0 0 0 3-3c0-1.55-.6-6.58-.69-7.26A4 4 0 0 0 17.32 5z\"/>",
	"app": "<rect x=\"3\" y=\"4\" width=\"18\" height=\"16\" rx=\"2.5\"/><path d=\"M3 9h18M7 6.5h.01M10 6.5h.01\"/>",
	"clock": "<circle cx=\"12\" cy=\"12\" r=\"9\"/><path d=\"M12 7v5l3 2\"/>",
	"bolt": "<path d=\"M13 2 4 14h7l-1 8 9-12h-7z\"/>",
	"chevron_right": "<path d=\"m9 18 6-6-6-6\"/>",
	"chevron_left": "<path d=\"m15 18-6-6 6-6\"/>",
	"chevron_down": "<path d=\"m6 9 6 6 6-6\"/>",
	"external": "<path d=\"M15 3h6v6M10 14 21 3\"/><path d=\"M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6\"/>",
	"sort": "<path d=\"M3 6h18M6 12h12M10 18h4\"/>",
	"star": "<path d=\"M12 2.5 14.9 8.4l6.5.9-4.7 4.6 1.1 6.5L12 17.3l-5.8 3.1 1.1-6.5L2.6 9.3l6.5-.9z\"/>",
	"layers": "<path d=\"m12 2 10 5-10 5L2 7z\"/><path d=\"m2 17 10 5 10-5\"/><path d=\"m2 12 10 5 10-5\"/>",
	"volume": "<path d=\"M11 5 6 9H2v6h4l5 4z\"/><path d=\"M15.5 8.5a5 5 0 0 1 0 7M19 5a10 10 0 0 1 0 14\"/>",
	"monitor": "<rect x=\"2\" y=\"3\" width=\"20\" height=\"14\" rx=\"2\"/><path d=\"M8 21h8M12 17v4\"/>",
	"palette": "<circle cx=\"13.5\" cy=\"6.5\" r=\".8\" fill=\"currentColor\"/><circle cx=\"17.5\" cy=\"10.5\" r=\".8\" fill=\"currentColor\"/><circle cx=\"8.5\" cy=\"7.5\" r=\".8\" fill=\"currentColor\"/><circle cx=\"6.5\" cy=\"12.5\" r=\".8\" fill=\"currentColor\"/><path d=\"M12 2C6.5 2 2 6.5 2 12s4.5 10 10 10c.93 0 1.65-.75 1.65-1.69 0-.44-.18-.84-.44-1.13-.29-.29-.44-.65-.44-1.13a1.64 1.64 0 0 1 1.67-1.67h2c3.05 0 5.56-2.5 5.56-5.55C21.97 6.01 17.46 2 12 2z\"/>",
	"logo": "<circle cx=\"11.5\" cy=\"13\" r=\"7\" stroke-width=\"3\" stroke-dasharray=\"36 8\" transform=\"rotate(-20 11.5 13)\"/><circle cx=\"18.2\" cy=\"5.6\" r=\"2.2\" fill=\"currentColor\" stroke=\"none\"/>",
	"terminal": "<rect x=\"2.5\" y=\"4\" width=\"19\" height=\"16\" rx=\"2.5\"/><path d=\"m7 10 3 2.5L7 15M12.5 15H17\"/>",
	"power": "<path d=\"M12 3v8\"/><path d=\"M18.4 6.6a9 9 0 1 1-12.8 0\"/>",
	"lock": "<rect x=\"4\" y=\"11\" width=\"16\" height=\"10\" rx=\"2.5\"/><path d=\"M8 11V7a4 4 0 0 1 8 0v4\"/>",
	"moon": "<path d=\"M20.5 14.5A8.5 8.5 0 1 1 9.5 3.5a7 7 0 0 0 11 11z\"/>",
	"sun": "<circle cx=\"12\" cy=\"12\" r=\"4\"/><path d=\"M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4\"/>",
	"restart": "<path d=\"M3 12a9 9 0 1 0 3-6.7L3 8\"/><path d=\"M3 3v5h5\"/>",
	"user": "<circle cx=\"12\" cy=\"8\" r=\"4\"/><path d=\"M4 21a8 8 0 0 1 16 0\"/>",
	"pin": "<path d=\"M12 17v5\"/><path d=\"M9 10.8V5h6v5.8l2.5 2.7a1 1 0 0 1-.7 1.7H7.2a1 1 0 0 1-.7-1.7z\"/><path d=\"M8 5h8\"/>",
	"unpin": "<path d=\"M12 17v5\"/><path d=\"M9 10.8V5h6v5.8l2.5 2.7a1 1 0 0 1-.7 1.7H7.2a1 1 0 0 1-.7-1.7z\"/><path d=\"M3 3l18 18\"/>",
	"window": "<rect x=\"3\" y=\"4\" width=\"18\" height=\"16\" rx=\"2.5\"/><path d=\"M3 9h18\"/>",
	"cpu": "<rect x=\"6\" y=\"6\" width=\"12\" height=\"12\" rx=\"2\"/><path d=\"M9 2v3M15 2v3M9 19v3M15 19v3M2 9h3M2 15h3M19 9h3M19 15h3\"/>",
	"memory": "<rect x=\"3\" y=\"7\" width=\"18\" height=\"10\" rx=\"2\"/><path d=\"M7 17v3M11 17v3M15 17v3M7 10v4M11 10v4M15 10v4\"/>",
	"battery": "<rect x=\"2\" y=\"7\" width=\"17\" height=\"10\" rx=\"2.5\"/><path d=\"M22 11v2\"/>",
	"location": "<path d=\"M20 10c0 5-5.5 10.2-7.4 11.8a1 1 0 0 1-1.2 0C9.5 20.2 4 15 4 10a8 8 0 0 1 16 0z\"/><circle cx=\"12\" cy=\"10\" r=\"3\"/>",
	"droplet": "<path d=\"M12 2.7 6.3 8.4a8 8 0 1 0 11.4 0z\"/>",
	"wind": "<path d=\"M12.8 19.6A2 2 0 1 0 14 16H2M17.5 8a2.5 2.5 0 1 1 2 4H2M9.8 4.4A2 2 0 1 1 11 8H2\"/>",
	"thermometer": "<path d=\"M14 4v10.54a4 4 0 1 1-4 0V4a2 2 0 0 1 4 0z\"/>",
	"claude": "<path d=\"M12 2.5v6M12 15.5v6M2.5 12h6M15.5 12h6M5.3 5.3l4.2 4.2M14.5 14.5l4.2 4.2M18.7 5.3l-4.2 4.2M9.5 14.5l-4.2 4.2\"/>",
	"claude_code": "<path d=\"M3 8l4 4-4 4\"/><path d=\"M16 6v3.5M16 14.5V18M10 12h3.5M18.5 12H22M11.8 7.8l2.4 2.4M17.8 13.8l2.4 2.4M20.2 7.8l-2.4 2.4M14.2 13.8l-2.4 2.4\"/>",
	"whatsapp": "<path d=\"M3.5 20.5l1.4-4.2a8.5 8.5 0 1 1 3.2 3z\"/><path d=\"M9 8.7c.4-.6 1.1-.6 1.4 0l.7 1.4c.2.4.1.8-.2 1.1l-.4.4a5 5 0 0 0 2 2l.4-.4c.3-.3.7-.4 1.1-.2l1.4.7c.6.3.6 1 0 1.4-.9.6-2 .7-3 .2a7.6 7.6 0 0 1-3.6-3.6c-.5-1-.4-2.1.2-3z\" fill=\"currentColor\" stroke-width=\"1\"/>",
	"chat": "<path d=\"M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z\"/>",
	"code": "<path d=\"m16 18 6-6-6-6M8 6l-6 6 6 6\"/>",
	"compass": "<circle cx=\"12\" cy=\"12\" r=\"9\"/><path d=\"m16.24 7.76-2.12 6.36-6.36 2.12 2.12-6.36z\"/>",
	"globe": "<circle cx=\"12\" cy=\"12\" r=\"9\"/><path d=\"M3 12h18M12 3a14 14 0 0 1 0 18M12 3a14 14 0 0 0 0 18\"/>",
	"apps": "<rect x=\"3.5\" y=\"3.5\" width=\"7\" height=\"7\" rx=\"2\"/><rect x=\"13.5\" y=\"3.5\" width=\"7\" height=\"7\" rx=\"2\"/><rect x=\"3.5\" y=\"13.5\" width=\"7\" height=\"7\" rx=\"2\"/><circle cx=\"17\" cy=\"17\" r=\"3.5\"/>",
	"arrow_left": "<path d=\"M19 12H5M11 18l-6-6 6-6\"/>",
	"desktop": "<rect x=\"2\" y=\"3\" width=\"20\" height=\"14\" rx=\"2\"/><path d=\"M8 21h8M12 17v4\"/>",
	"downloads": "<path d=\"M12 3v12\"/><path d=\"m7 10 5 5 5-5\"/><path d=\"M4 17v2a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-2\"/>",
	"document": "<path d=\"M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z\"/><path d=\"M14 3v5h5M9 13h6M9 17h6\"/>",
	"music": "<path d=\"M9 18V5l12-2v13\"/><circle cx=\"6\" cy=\"18\" r=\"3\"/><circle cx=\"18\" cy=\"16\" r=\"3\"/>",
	"leaf": "<path d=\"M11 20A7 7 0 0 1 9.8 6.1C15.5 5 17 4.5 19 2c1 2 2 4.2 2 8 0 5.5-4.8 10-10 10Z\"/><path d=\"M2 21c0-3 1.9-5.4 5.2-6.1C9.5 14.5 12 13 13 12\"/>",
	"wifi": "<path d=\"M12 20h.01\"/><path d=\"M2 8.8a15 15 0 0 1 20 0\"/><path d=\"M5 12.9a10 10 0 0 1 14 0\"/><path d=\"M8.5 16.4a5 5 0 0 1 7 0\"/>",
	"bluetooth": "<path d=\"m7 7 10 10-5 5V2l5 5L7 17\"/>",
	"calculator": "<rect x=\"4\" y=\"2\" width=\"16\" height=\"20\" rx=\"2.5\"/><path d=\"M8 6h8M8 11h.01M12 11h.01M16 11h.01M8 15h.01M12 15h.01M16 15h.01M8 18.5h.01M12 18.5h.01M16 18.5h.01\"/>",
	"volume_low": "<path d=\"M11 5 6 9H2v6h4l5 4z\"/><path d=\"M15.5 8.5a5 5 0 0 1 0 7\"/>",
	"volume_x": "<path d=\"M11 5 6 9H2v6h4l5 4z\"/><path d=\"m22 9-6 6M16 9l6 6\"/>",
	"pause": "<rect x=\"6\" y=\"4.5\" width=\"4\" height=\"15\" rx=\"1\" fill=\"currentColor\"/><rect x=\"14\" y=\"4.5\" width=\"4\" height=\"15\" rx=\"1\" fill=\"currentColor\"/>",
	"skip_back": "<path d=\"M19 20 9 12l10-8z\" fill=\"currentColor\"/><path d=\"M5 19V5\"/>",
	"skip_forward": "<path d=\"m5 4 10 8-10 8z\" fill=\"currentColor\"/><path d=\"M19 5v14\"/>",
	"calendar": "<rect x=\"3\" y=\"4\" width=\"18\" height=\"18\" rx=\"2.5\"/><path d=\"M16 2v4M8 2v4M3 10h18\"/>",
	"keyboard": "<rect x=\"2\" y=\"5\" width=\"20\" height=\"14\" rx=\"2.5\"/><path d=\"M6 9h.01M10 9h.01M14 9h.01M18 9h.01M6 13h.01M18 13h.01M10 13h4M7 16h10\"/>",
	"wand": "<path d=\"m21.64 3.64-1.28-1.28a1.21 1.21 0 0 0-1.72 0L2.36 18.64a1.21 1.21 0 0 0 0 1.72l1.28 1.28a1.2 1.2 0 0 0 1.72 0L21.64 5.36a1.2 1.2 0 0 0 0-1.72z\"/><path d=\"m14 7 3 3M5 6v4M19 14v4M10 2v2M7 8H3M21 16h-4M11 3H9\"/>",
	"shield": "<path d=\"M20 13c0 5-3.5 7.5-7.66 8.95a1 1 0 0 1-.67-.01C7.5 20.5 4 18 4 13V6a1 1 0 0 1 1-1c2 0 4.5-1.2 6.24-2.72a1.17 1.17 0 0 1 1.52 0C14.51 3.81 17 5 19 5a1 1 0 0 1 1 1z\"/><path d=\"m9 12 2 2 4-4\"/>",
	"rocket": "<path d=\"M4.5 16.5c-1.5 1.26-2 5-2 5s3.74-.5 5-2c.71-.84.7-2.13-.09-2.91a2.18 2.18 0 0 0-2.91-.09z\"/><path d=\"m12 15-3-3a22 22 0 0 1 2-3.95A12.88 12.88 0 0 1 22 2c0 2.72-.78 7.5-6 11a22.35 22.35 0 0 1-4 2z\"/><path d=\"M9 12H4s.55-3.03 2-4c1.62-1.08 5 0 5 0M12 15v5s3.03-.55 4-2c1.08-1.62 0-5 0-5\"/>",
	"eye_off": "<path d=\"M10.73 5.08A10.43 10.43 0 0 1 12 5c7 0 10 7 10 7a13.16 13.16 0 0 1-1.67 2.68M6.61 6.61A13.53 13.53 0 0 0 2 12s3 7 10 7a9.74 9.74 0 0 0 5.39-1.61\"/><path d=\"M9.88 9.88a3 3 0 1 0 4.24 4.24M2 2l20 20\"/>",
	"broom": "<path d=\"m16 22-1-4M19 13.99a1 1 0 0 0 1-1V12a2 2 0 0 0-2-2h-3a1 1 0 0 1-1-1V4a2 2 0 0 0-4 0v5a1 1 0 0 1-1 1H6a2 2 0 0 0-2 2v.99a1 1 0 0 0 1 1M5 14h14l1.5 8h-17zM8 22l1-4\"/>",
	"undo": "<path d=\"M9 14 4 9l5-5\"/><path d=\"M4 9h10.5a5.5 5.5 0 0 1 0 11H11\"/>",
	"dot": "<circle cx=\"12\" cy=\"12\" r=\"4\" fill=\"currentColor\"/>",
}

static var _cache := {}


## Renders an icon at `px` logical pixels (2x internally for crisp scaling).
static func tex(name: String, px: int = 24, color: Color = Color.WHITE) -> Texture2D:
	var key := "%s|%d|%s" % [name, px, color.to_html()]
	if _cache.has(key):
		return _cache[key]
	var body: String = SVGS.get(name, SVGS["dot"])
	var svg := (_HEAD + body + "</svg>").replace("currentColor", "#" + color.to_html(false))
	if color.a < 0.999:
		svg = svg.replace("<svg ", "<svg opacity=\"%.3f\" " % color.a)
	var img := Image.new()
	var err := img.load_svg_from_string(svg, float(px) / 24.0 * 2.0)
	if err != OK:
		push_warning("Icon %s failed to render" % name)
		img = Image.create(px * 2, px * 2, false, Image.FORMAT_RGBA8)
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	t.set_size_override(Vector2i(px, px))
	_cache[key] = t
	return t
