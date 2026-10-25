extends Node
## Artwork pipeline: covers (portrait), heroes (wide backgrounds) and logos.
## Sources, in order: a file the user picked, our download cache, Steam's local
## library cache, then Steam's CDN. Decoding and resizing happen on worker
## threads so scrolling a big library never hitches. Every cover also donates
## an accent colour that tints the whole UI when it is selected.

signal art_ready(id: String, kind: StringName)

const CACHE_DIR := "user://art"
const MAX_DOWNLOADS := 3
const MAX_SIZE := {
	&"cover": Vector2i(420, 630),
	&"hero": Vector2i(1920, 820),
	&"logo": Vector2i(720, 320),
}
const STEAM_FILES := {
	&"cover": ["library_600x900_2x.jpg", "library_600x900.jpg", "library_capsule.jpg"],
	&"hero": ["library_hero.jpg", "library_hero_2x.jpg"],
	&"logo": ["logo.png", "logo_2x.png"],
}
const STEAM_CDN := [
	"https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/%s/",
	"https://cdn.cloudflare.steamstatic.com/steam/apps/%s/",
]
const HERO_CACHE_LIMIT := 10
## Steam's store API knows the real (often hashed) URLs of every library asset.
const STEAM_ITEMS_API := "https://api.steampowered.com/IStoreBrowseService/GetItems/v1/?input_json="
const STEAM_ASSET_BASE := "https://shared.akamai.steamstatic.com/store_item_assets/"
const STEAM_ASSET_KEYS := {
	&"cover": ["library_capsule_2x", "library_capsule"],
	&"hero": ["library_hero_2x", "library_hero"],
	&"logo": ["library_logo_2x", "library_logo"],
}
## Name fragments used to recognise files in Steam's local library cache.
const STEAM_LOCAL_TOKENS := {
	&"cover": ["600x900", "library_capsule"],
	&"hero": ["library_hero"],
	&"logo": ["logo"],
}

signal _steam_assets_done(appid: String)

var _cache := {}
var _cache_src := {}
var _pending := {}
var _queue: Array[Dictionary] = []
var _active := 0
var _hero_order: Array[String] = []
var _steam_assets := {}
var _steam_assets_pending := {}


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(CACHE_DIR)
	Library.entry_changed.connect(_on_entry_changed)


## Returns the texture if it is ready, otherwise null (and starts loading it).
func get_art(id: String, kind: StringName) -> Texture2D:
	var key := _key(id, kind)
	if _cache.has(key):
		if kind == &"hero":
			_touch_hero(key)
		return _cache[key]
	if not _pending.has(key):
		_start(id, kind)
	return null


## True once we know whether art exists (it may still be null = none found).
func is_resolved(id: String, kind: StringName) -> bool:
	return _cache.has(_key(id, kind))


func forget(id: String) -> void:
	for kind in MAX_SIZE.keys():
		_cache.erase(_key(id, kind))


func clear_downloads() -> void:
	for f in DirAccess.get_files_at(CACHE_DIR):
		DirAccess.remove_absolute(CACHE_DIR.path_join(f))
	_cache.clear()
	for e in Library.entries:
		for kind in MAX_SIZE.keys():
			art_ready.emit(e["id"], kind)


func _key(id: String, kind: StringName) -> String:
	return "%s:%s" % [id, kind]


func _on_entry_changed(id: String) -> void:
	# A changed custom image path means our cached texture may be stale.
	var e := Library.get_entry(id)
	for kind in MAX_SIZE.keys():
		var key := _key(id, kind)
		var src := str(e.get(String(kind), ""))
		if _cache.has(key) and _cache_src.get(key, "") != src:
			_cache.erase(key)
			_start(id, kind)



func _start(id: String, kind: StringName) -> void:
	var e := Library.get_entry(id)
	if e.is_empty():
		return
	var key := _key(id, kind)
	_pending[key] = true
	_cache_src[key] = str(e.get(String(kind), ""))
	var candidates := PackedStringArray()
	var custom := str(e.get(String(kind), ""))
	if custom != "":
		candidates.append(custom)
	for ext in ["jpg", "png", "webp"]:
		candidates.append(_cache_file(id, kind, ext))
	var steam_id := str(e.get("steam_appid", ""))
	var steam_root := Library.steam_root
	if steam_root == "" and App.is_windows():
		steam_root = "C:/Program Files (x86)/Steam"
	var want_accent := kind == &"cover" and str(e.get("color", "")) == ""
	WorkerThreadPool.add_task(_load_worker.bind(id, kind, candidates, steam_id, steam_root, want_accent), false, "Load artwork")


func _cache_file(id: String, kind: StringName, ext: String) -> String:
	return CACHE_DIR.path_join("%s_%s.%s" % [id, kind, ext])


# --- Worker side -----------------------------------------------------------------

func _load_worker(id: String, kind: StringName, candidates: PackedStringArray, steam_id: String, steam_root: String, want_accent: bool) -> void:
	var paths := Array(candidates)
	if steam_id != "" and steam_root != "":
		paths.append_array(_steam_local(steam_root, steam_id, kind))
	for p in paths:
		if not FileAccess.file_exists(p):
			continue
		var img := _decode_file(p)
		if img == null:
			continue
		_prepare(img, kind)
		var accent := extract_accent(img) if want_accent else Color(0, 0, 0, 0)
		_finish.call_deferred(id, kind, img, accent)
		return
	_missing.call_deferred(id, kind, steam_id)


static func _decode_file(path: String) -> Image:
	var bytes := FileAccess.get_file_as_bytes(path)
	return decode(bytes)


static func decode(bytes: PackedByteArray) -> Image:
	if bytes.size() < 16:
		return null
	var img := Image.new()
	var err := ERR_FILE_UNRECOGNIZED
	if bytes[0] == 0x89 and bytes[1] == 0x50:
		err = img.load_png_from_buffer(bytes)
	elif bytes[0] == 0xFF and bytes[1] == 0xD8:
		err = img.load_jpg_from_buffer(bytes)
	elif bytes[0] == 0x52 and bytes[1] == 0x49 and bytes[8] == 0x57:
		err = img.load_webp_from_buffer(bytes)
	elif bytes[0] == 0x42 and bytes[1] == 0x4D:
		err = img.load_bmp_from_buffer(bytes)
	if err != OK or img.is_empty():
		return null
	return img


static func _prepare(img: Image, kind: StringName) -> void:
	if img.is_compressed():
		img.decompress()
	var max_size: Vector2i = MAX_SIZE[kind]
	var w := img.get_width()
	var h := img.get_height()
	var s := minf(float(max_size.x) / w, float(max_size.y) / h)
	if kind == &"cover":
		# Covers get cropped to fill; keep enough pixels for the short side.
		s = maxf(float(max_size.x) / w, float(max_size.y) / h)
	if s < 1.0:
		img.resize(maxi(1, int(w * s)), maxi(1, int(h * s)), Image.INTERPOLATE_LANCZOS)
	if img.get_format() != Image.FORMAT_RGBA8 and img.get_format() != Image.FORMAT_RGB8:
		img.convert(Image.FORMAT_RGBA8)
	img.generate_mipmaps()


## Picks the most characterful colour in an image: the dominant vivid hue,
## lifted so it reads well as a UI accent on a dark background.
static func extract_accent(img: Image) -> Color:
	var small := img.duplicate() as Image
	small.clear_mipmaps()
	small.resize(16, 16, Image.INTERPOLATE_BILINEAR)
	var bins := []
	for i in 12:
		bins.append([0.0, Vector3.ZERO])
	for y in 16:
		for x in 16:
			var c := small.get_pixel(x, y)
			var w := c.s * c.s * smoothstep(0.12, 0.55, c.v)
			if w <= 0.002:
				continue
			var b := int(c.h * 12.0) % 12
			bins[b][0] += w
			bins[b][1] += Vector3(c.r, c.g, c.b) * w
	var best := -1
	var best_w := 0.0
	for i in 12:
		if bins[i][0] > best_w:
			best_w = bins[i][0]
			best = i
	if best < 0 or best_w < 0.25:
		return Color(0, 0, 0, 0)
	var v: Vector3 = bins[best][1] / best_w
	var col := Color(v.x, v.y, v.z)
	return Color.from_hsv(col.h, clampf(col.s * 1.15, 0.45, 0.85), clampf(col.v * 1.25, 0.78, 1.0))


static func _steam_local(root: String, appid: String, kind: StringName) -> Array:
	var out := []
	var cache := root.path_join("appcache/librarycache")
	var names: Array = STEAM_FILES[kind]
	for n in names:
		out.append(cache.path_join("%s_%s" % [appid, n]))
	# Newer Steam clients keep one folder per app, sometimes with hashed subfolders.
	var dir := cache.path_join(appid)
	if DirAccess.dir_exists_absolute(dir):
		var found := _scan_for(dir, STEAM_LOCAL_TOKENS[kind], kind, 2)
		found.sort_custom(func(a: String, b: String) -> bool: return a.length() < b.length())
		out.append_array(found)
	return out


static func _scan_for(dir: String, tokens: Array, kind: StringName, depth: int) -> Array:
	var out := []
	for f in DirAccess.get_files_at(dir):
		var lower := f.to_lower()
		if not (lower.ends_with(".jpg") or lower.ends_with(".png") or lower.ends_with(".webp")):
			continue
		if lower.contains("blur"):
			continue
		if kind == &"logo" and not lower.ends_with(".png"):
			continue
		for t in tokens:
			if lower.contains(t):
				# Prefer the 2x variants.
				if lower.contains("_2x"):
					out.push_front(dir.path_join(f))
				else:
					out.append(dir.path_join(f))
				break
	if depth > 0:
		for sub in DirAccess.get_directories_at(dir):
			out.append_array(_scan_for(dir.path_join(sub), tokens, kind, depth - 1))
	return out


# --- Main thread side ---------------------------------------------------------------

func _finish(id: String, kind: StringName, img: Image, accent: Color) -> void:
	var key := _key(id, kind)
	_pending.erase(key)
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	if kind == &"hero":
		_touch_hero(key)
	if accent.a > 0.0 and Library.has_entry(id) and str(Library.get_entry(id).get("color", "")) == "":
		Library.update_entry(id, {"color": accent.to_html(false)})
	art_ready.emit(id, kind)


func _missing(id: String, kind: StringName, steam_id: String) -> void:
	var key := _key(id, kind)
	if steam_id != "" and (not App.smoke_test or App.screenshot_dir != ""):
		_queue.append({"id": id, "kind": kind, "steam_id": steam_id})
		_pump()
		return
	_pending.erase(key)
	_cache[key] = null
	art_ready.emit(id, kind)


func _pump() -> void:
	while _active < MAX_DOWNLOADS and not _queue.is_empty():
		var job: Dictionary = _queue.pop_front()
		_active += 1
		_download(job)


func _download(job: Dictionary) -> void:
	var http := HTTPRequest.new()
	http.timeout = 20.0
	http.use_threads = true
	add_child(http)
	var id: String = job["id"]
	var kind: StringName = job["kind"]
	var urls := await _steam_urls(str(job["steam_id"]), kind)
	for url in urls:
		if http.request(url, ["User-Agent: %s/%s" % [App.USER_AGENT, App.version]]) != OK:
			continue
		var res: Array = await http.request_completed
		var body: PackedByteArray = res[3]
		if int(res[0]) == HTTPRequest.RESULT_SUCCESS and int(res[1]) == 200 and body.size() > 2048:
			var ext := "png" if body[0] == 0x89 else "jpg"
			var f := FileAccess.open(_cache_file(id, kind, ext), FileAccess.WRITE)
			if f:
				f.store_buffer(body)
				f.close()
			http.queue_free()
			_active -= 1
			_pump()
			var e := Library.get_entry(id)
			var want_accent := kind == &"cover" and not e.is_empty() and str(e.get("color", "")) == ""
			WorkerThreadPool.add_task(_load_worker.bind(id, kind, PackedStringArray([_cache_file(id, kind, ext)]), "", "", want_accent), false, "Decode artwork")
			return
	http.queue_free()
	_active -= 1
	_pump()
	var key := _key(id, kind)
	_pending.erase(key)
	_cache[key] = null
	art_ready.emit(id, kind)


## Every URL worth trying for one Steam asset, best first.
func _steam_urls(appid: String, kind: StringName) -> PackedStringArray:
	var urls := PackedStringArray()
	var assets := await _steam_assets_for(appid)
	var fmt := str(assets.get("asset_url_format", ""))
	if fmt != "":
		var keys: Array = STEAM_ASSET_KEYS[kind]
		for k in keys:
			if assets.has(k) and str(assets[k]) != "":
				urls.append(STEAM_ASSET_BASE + fmt.replace("%s", str(assets[k])))
		if kind == &"logo":
			urls.append(STEAM_ASSET_BASE + fmt.replace("%s", "logo_2x.png"))
			urls.append(STEAM_ASSET_BASE + fmt.replace("%s", "logo.png"))
	var names: Array = STEAM_FILES[kind]
	for base in STEAM_CDN:
		for n in names:
			urls.append((base % appid) + n)
	if kind != &"logo":
		if fmt != "" and assets.has("header"):
			urls.append(STEAM_ASSET_BASE + fmt.replace("%s", str(assets["header"])))
		urls.append((STEAM_CDN[0] % appid) + "header.jpg")
	return urls


## Asks Steam's store for the app's asset table once, shared by all three kinds.
func _steam_assets_for(appid: String) -> Dictionary:
	if _steam_assets.has(appid):
		return _steam_assets[appid]
	if _steam_assets_pending.has(appid):
		while _steam_assets_pending.has(appid):
			await _steam_assets_done
		return _steam_assets.get(appid, {})
	_steam_assets_pending[appid] = true
	var http := HTTPRequest.new()
	http.timeout = 12.0
	add_child(http)
	var query := {
		"ids": [{"appid": int(appid)}],
		"context": {"language": "english", "country_code": "US", "steam_realm": 1},
		"data_request": {"include_assets": true},
	}
	var assets := {}
	if http.request(STEAM_ITEMS_API + JSON.stringify(query).uri_encode(), ["User-Agent: %s/%s" % [App.USER_AGENT, App.version]]) == OK:
		var res: Array = await http.request_completed
		if int(res[0]) == HTTPRequest.RESULT_SUCCESS and int(res[1]) == 200:
			var data: Variant = JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8())
			if data is Dictionary:
				var items: Variant = data.get("response", {}).get("store_items", [])
				if items is Array and not items.is_empty() and items[0] is Dictionary:
					var a: Variant = items[0].get("assets", {})
					if a is Dictionary:
						assets = a
	http.queue_free()
	_steam_assets[appid] = assets
	_steam_assets_pending.erase(appid)
	_steam_assets_done.emit(appid)
	return assets


func _touch_hero(key: String) -> void:
	_hero_order.erase(key)
	_hero_order.append(key)
	while _hero_order.size() > HERO_CACHE_LIMIT:
		var old: String = _hero_order.pop_front()
		_cache.erase(old)
