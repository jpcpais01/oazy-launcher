class_name CoinIcons
extends RefCounted
## Coin and stock logos for the trading desk. Hyperliquid's own icon files
## first (HIP-3 markets by their full "dex:NAME"), then a keyless fallback:
## the cryptocurrency-icons set for crypto, company logos for stocks. Kept on
## disk as round PNGs; a coin with no logo anywhere is retried after a week.

const DIR := "user://coin_icons"
const SIZE := 96
const MISS_TTL := 7 * 86400

static var _tex := {}
static var _waiting := {}


## Where to look for a coin's logo, best first.
static func urls(c: String) -> PackedStringArray:
	var short := Hyperliquid.display(c)
	if Hyperliquid.is_spot(c):
		# Spot tokens by name: Hyperliquid's spot art, then its perp art.
		short = str((Hyperliquid.spot_pairs.get(c, {}) as Dictionary).get("base", short))
		return PackedStringArray(["https://app.hyperliquid.xyz/coins/%s_spot.svg" % short, "https://app.hyperliquid.xyz/coins/%s.svg" % short,
			"https://cdn.jsdelivr.net/npm/cryptocurrency-icons@0.18.1/svg/color/%s.svg" % short.trim_prefix("U").to_lower()])
	var out := PackedStringArray(["https://app.hyperliquid.xyz/coins/%s.svg" % c])
	if Hyperliquid.dex_of(c) != "":
		out.append("https://financialmodelingprep.com/image-stock/%s.png" % short.to_upper())
	else:
		out.append("https://cdn.jsdelivr.net/npm/cryptocurrency-icons@0.18.1/svg/color/%s.svg" % short.trim_prefix("k").to_lower())
	return out


static func _path(c: String, ext: String) -> String:
	return DIR.path_join(c.replace(":", "_").validate_filename() + ext)


## Puts the logo on `badge` (a coin_badge) now if known, else once it arrives.
static func apply(badge: Control, c: String) -> void:
	var tex := get_icon(c)
	if tex != null:
		_show(badge, tex)
		return
	if App.smoke_test or _missed(c):
		return
	var list: Array = _waiting.get(c, [])
	list.append(func(t: Texture2D) -> void:
		if is_instance_valid(badge):
			_show(badge, t)
	)
	if _waiting.has(c):
		return
	_waiting[c] = list
	_fetch(c)


## The logo if it's in memory or on disk, else null.
static func get_icon(c: String) -> Texture2D:
	if _tex.has(c):
		return _tex[c]
	var p := _path(c, ".png")
	if FileAccess.file_exists(p):
		var img := Image.load_from_file(ProjectSettings.globalize_path(p))
		if img != null and not img.is_empty():
			_tex[c] = ImageTexture.create_from_image(img)
			return _tex[c]
	return null


static func _missed(c: String) -> bool:
	var p := _path(c, ".miss")
	return FileAccess.file_exists(p) and Time.get_unix_time_from_system() - FileAccess.get_modified_time(p) < MISS_TTL


static func _show(badge: Control, tex: Texture2D) -> void:
	for n in badge.get_children():
		if n is Label:
			n.visible = false
		elif n is TextureRect:
			return
	badge.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var r := TextureRect.new()
	r.texture = tex
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	badge.add_child(r)


static func _fetch(c: String) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var img: Image = null
	for url in urls(c):
		var http := HTTPRequest.new()
		http.timeout = 10.0
		tree.root.add_child(http)
		if http.request(url) == OK:
			var res: Array = await http.request_completed
			if int(res[0]) == HTTPRequest.RESULT_SUCCESS and int(res[1]) == 200:
				img = decode(res[3], url.ends_with(".svg"))
		http.queue_free()
		if img != null:
			break
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var tex: Texture2D = null
	if img != null:
		img.save_png(ProjectSettings.globalize_path(_path(c, ".png")))
		tex = ImageTexture.create_from_image(img)
		_tex[c] = tex
	else:
		var f := FileAccess.open(_path(c, ".miss"), FileAccess.WRITE)
		if f != null:
			f.store_string(str(int(Time.get_unix_time_from_system())))
	var list: Array = _waiting.get(c, [])
	_waiting.erase(c)
	if tex != null:
		for cb in list:
			(cb as Callable).call(tex)


## An SVG or PNG logo as a SIZE × SIZE round image, or null when it isn't one
## (a web page served in its place, say). Square logos sit on a white disc.
static func decode(bytes: PackedByteArray, svg: bool) -> Image:
	if bytes.is_empty():
		return null
	var img := Image.new()
	if svg:
		var head := bytes.slice(0, 256).get_string_from_utf8().strip_edges().to_lower()
		if not (head.begins_with("<svg") or head.begins_with("<?xml")) or img.load_svg_from_buffer(bytes, 1.0) != OK:
			return null
		var big := maxi(img.get_width(), img.get_height())
		if big <= 0 or img.load_svg_from_buffer(bytes, float(SIZE) / big) != OK:
			return null
	elif img.load_png_from_buffer(bytes) != OK:
		return null
	if img.is_empty():
		return null
	img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()
	var k := float(SIZE) / maxf(w, h)
	if not svg:
		# Leave a margin so the logo sits inside the disc.
		k *= 0.68
	img.resize(maxi(1, roundi(w * k)), maxi(1, roundi(h * k)), Image.INTERPOLATE_LANCZOS)
	var out := Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	if not svg:
		out.fill(Color.WHITE)
	out.blend_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), (Vector2i(SIZE, SIZE) - img.get_size()) / 2)
	# Round it, with a soft one-pixel edge.
	var r := SIZE * 0.5
	for y in SIZE:
		for x in SIZE:
			var d := Vector2(x + 0.5 - r, y + 0.5 - r).length()
			if d > r - 1.0:
				var px := out.get_pixel(x, y)
				px.a *= clampf(r - d, 0.0, 1.0)
				out.set_pixel(x, y, px)
	return out
