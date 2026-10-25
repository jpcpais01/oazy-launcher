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

var _cache := {}
var _cache_src := {}
var _pending := {}
var _queue: Array[Dictionary] = []
var _active := 0
var _hero_order: Array[String] = []


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
	var dir := cache.path_join(appid)
	if DirAccess.dir_exists_absolute(dir):
		for n in names:
			out.append(dir.path_join(n))
		for sub in DirAccess.get_directories_at(dir):
			for n in names:
				out.append(dir.path_join(sub).path_join(n))
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
	if steam_id != "" and not App.smoke_test:
		var urls := PackedStringArray()
		var names: Array = STEAM_FILES[kind]
		for base in STEAM_CDN:
			for n in names:
				urls.append((base % steam_id) + n)
		if kind != &"logo":
			urls.append((STEAM_CDN[0] % steam_id) + "header.jpg")
		_queue.append({"id": id, "kind": kind, "urls": urls})
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
	var urls: PackedStringArray = job["urls"]
	var id: String = job["id"]
	var kind: StringName = job["kind"]
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


func _touch_hero(key: String) -> void:
	_hero_order.erase(key)
	_hero_order.append(key)
	while _hero_order.size() > HERO_CACHE_LIMIT:
		var old: String = _hero_order.pop_front()
		_cache.erase(old)
