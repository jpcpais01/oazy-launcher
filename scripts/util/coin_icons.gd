class_name CoinIcons
extends RefCounted
## Coin and stock logos for the trading desk. Crypto: Hyperliquid's own icon
## files, then the cryptocurrency-icons set. HIP-3 markets (stocks, ETFs,
## indices, FX): a hand-picked logo first, then the company logo by its real
## ticker, then Hyperliquid's file. Kept on disk as round PNGs; a coin with no
## logo anywhere is retried after a week.

const DIR := "user://coin_icons3"
const SIZE := 96
const MISS_TTL := 7 * 86400

const FMP := "https://financialmodelingprep.com/image-stock/%s.png"
const FLAG := "https://flagcdn.com/w160/%s.png"
const SITE := "https://www.google.com/s2/favicons?domain=%s&sz=128"

## Hand-picked logos for HIP-3 names whose own art is poor or missing:
## "flag:xx" a country flag, "site:domain" the brand's site icon, anything
## else a real stock ticker. Names not listed use their own name as ticker.
const LOGOS := {
	"XYZ100": ["NDAQ", "site:nasdaq.com"], "SP500": ["SPGI", "site:spglobal.com"],
	"VIX": ["CBOE", "site:cboe.com"], "VOL": ["CBOE", "site:cboe.com"], "DXY": ["flag:us"],
	"IBOV": ["flag:br"], "JP225": ["flag:jp"], "KR200": ["flag:kr"], "NIFTY": ["flag:in"],
	"EUR": ["flag:eu"], "GBP": ["flag:gb"], "JPY": ["flag:jp"], "KRW": ["flag:kr"],
	"EWJ": ["flag:jp"], "EWT": ["flag:tw"], "EWY": ["flag:kr"], "EWZ": ["flag:br"],
	"KORU": ["flag:kr"], "KSTR": ["flag:cn"],
	"DRAM": ["DRAM", "site:roundhillinvestments.com"], "MAGS": ["MAGS", "site:roundhillinvestments.com"],
	"LYTE": ["site:roundhillinvestments.com"], "NCLD": ["site:roundhillinvestments.com"],
	"SMH": ["SMH", "site:vaneck.com"], "URNM": ["URNM", "site:sprott.com"],
	"SOXL": ["SOXL", "site:direxion.com"], "SNXX": ["site:tradretfs.com"],
	"XBI": ["XBI", "site:ssga.com"], "XLE": ["XLE", "site:ssga.com"], "TLT": ["TLT", "site:ishares.com"],
	"SKHX": ["000660.KS", "site:skhynix.com"], "SKHY": ["000660.KS", "site:skhynix.com"],
	"SMSN": ["005930.KS", "site:samsung.com"], "HYUNDAI": ["005380.KS", "site:hyundai.com"],
	"SOFTBANK": ["9984.T", "site:group.softbank"], "KIOXIA": ["285A.T", "site:kioxia.com"],
	"IBIDEN": ["4062.T", "site:ibiden.com"], "RELIANCE": ["RELIANCE.NS", "site:ril.com"],
	"JIO": ["site:jio.com"], "CATL": ["300750.SZ", "site:catl.com"], "CXMT": ["site:cxmt.com"],
	"GIGADEV": ["603986.SS", "site:gigadevice.com"], "UNITREE": ["site:unitree.com"],
	"YMTC": ["site:ymtc.com"], "INNOLIGHT": ["300308.SZ", "site:innolight.com"], "AMEC": ["688012.SS", "site:amec-inc.com"],
	"MINIMAX": ["site:minimax.io"], "ZHIPU": ["site:zhipuai.cn"], "SHEIN": ["site:shein.com"],
	"SPCX": ["site:spacex.com"], "ANT": ["site:anthropic.com"], "OURA": ["site:ouraring.com"],
	"CBRS": ["CBRS", "site:cerebras.ai"], "QNT": ["site:quantinuum.com"], "BIRD": ["BIRD"],
	"PURRDAT": ["PURR"], "UMC": ["UMC", "site:umc.com"], "TSM": ["TSM", "site:tsmc.com"],
}

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
	var hl := "https://app.hyperliquid.xyz/coins/%s.svg" % c
	if Hyperliquid.dex_of(c) == "":
		return PackedStringArray([hl, "https://cdn.jsdelivr.net/npm/cryptocurrency-icons@0.18.1/svg/color/%s.svg" % short.trim_prefix("k").to_lower()])
	var out := PackedStringArray()
	for src: String in LOGOS.get(short.to_upper(), [short.to_upper()]):
		if src.begins_with("flag:"):
			out.append(FLAG % src.trim_prefix("flag:"))
		elif src.begins_with("site:"):
			out.append(SITE % src.trim_prefix("site:"))
		else:
			out.append(FMP % src)
	out.append(hl)
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
				img = decode(res[3], url.ends_with(".svg"), url.begins_with(FLAG.get_slice("%", 0)))
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
## (a web page served in its place, say). Square logos sit on a disc of their
## own most used colour; a `fill` image (a flag) is cropped to cover it.
static func decode(bytes: PackedByteArray, svg: bool, fill := false) -> Image:
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
	var k := float(SIZE) / (minf(w, h) if fill else maxf(w, h))
	if not svg and not fill:
		# Leave a margin so the logo sits inside the disc.
		k *= 0.68
	img.resize(maxi(1, roundi(w * k)), maxi(1, roundi(h * k)), Image.INTERPOLATE_LANCZOS)
	var out := Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	if not svg and not fill:
		out.fill(dominant(img))
	var off := (Vector2i(SIZE, SIZE) - img.get_size()) / 2
	out.blend_rect(img, Rect2i(-off.min(Vector2i.ZERO), img.get_size()), off.max(Vector2i.ZERO))
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


## The colour most of an image's solid pixels share (not their average), so a
## logo's backdrop matches its own field. Close shades count as one; white
## when the image has no solid pixels.
static func dominant(img: Image) -> Color:
	var counts := {}
	var sums := {}
	var step := maxi(1, maxi(img.get_width(), img.get_height()) / 64)
	for y in range(0, img.get_height(), step):
		for x in range(0, img.get_width(), step):
			var c := img.get_pixel(x, y)
			if c.a < 0.6:
				continue
			var k := (int(c.r * 15.99) << 8) | (int(c.g * 15.99) << 4) | int(c.b * 15.99)
			counts[k] = int(counts.get(k, 0)) + 1
			sums[k] = (sums.get(k, Color(0, 0, 0, 0)) as Color) + Color(c.r, c.g, c.b, 1.0)
	var best := -1
	for k: int in counts:
		if best < 0 or int(counts[k]) > int(counts[best]):
			best = k
	if best < 0:
		return Color.WHITE
	var sum: Color = sums[best]
	return Color(sum.r / sum.a, sum.g / sum.a, sum.b / sum.a)
