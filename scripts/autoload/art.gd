extends Node
## Artwork pipeline: covers (portrait), heroes (wide backgrounds) and logos.
## Sources, in order: a file the user picked, our download cache, Steam's local
## library cache, then the internet: Steam (also found by name for games from
## other stores), the Epic launcher's own catalog cache, GOG Galaxy's games
## database and, for covers, Wikipedia. Lookups are remembered on disk. Decoding and resizing happen on worker
## threads so scrolling a big library never hitches. Every cover also donates
## an accent colour that tints the whole UI when it is selected.

signal art_ready(id: String, kind: StringName)

const CACHE_DIR := "user://art"
const MAX_DOWNLOADS := 3
const MAX_SIZE := {
	&"cover": Vector2i(420, 630),
	&"hero": Vector2i(2880, 1240),
	&"logo": Vector2i(720, 320),
}
const STEAM_FILES := {
	&"cover": ["library_600x900_2x.jpg", "library_600x900.jpg", "library_capsule.jpg"],
	&"hero": ["library_hero_2x.jpg", "library_hero.jpg"],
	&"logo": ["logo.png", "logo_2x.png"],
}
const STEAM_CDN := [
	"https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/%s/",
	"https://cdn.cloudflare.steamstatic.com/steam/apps/%s/",
]
const HERO_CACHE_LIMIT := 6
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

## Epic launcher image types per kind, best first.
const EPIC_TYPES := {
	&"cover": ["DieselGameBoxTall", "OfferImageTall", "DieselStoreFrontTall", "Thumbnail"],
	&"hero": ["DieselGameBox", "OfferImageWide", "DieselStoreFrontWide", "featuredMedia"],
	&"logo": ["DieselGameBoxLogo"],
}
const EPIC_CATCACHE := "EpicGamesLauncher/Saved/Data/Catalog/catcache.bin"
const STEAM_SEARCH := "https://store.steampowered.com/api/storesearch/?l=english&cc=US&term=%s"
const GAMESDB := "https://gamesdb.gog.com/platforms/%s/external_releases/%s"
const GOG_PRODUCT := "https://api.gog.com/products/%s"
const WIKI_SEARCH := "https://en.wikipedia.org/w/api.php?action=query&format=json&formatversion=2&generator=search&gsrlimit=5&prop=pageimages&piprop=thumbnail&pithumbsize=640&gsrsearch=%s"
const LAZY := "lazy:"
## File names (any image extension) that count as art when placed next to the exe.
const SIDECAR_NAMES := {
	&"cover": ["cover", "capsule", "boxart", "poster"],
	&"hero": ["hero", "banner", "background", "splash"],
	&"logo": ["logo"],
}
const LOOKUPS_PATH := CACHE_DIR + "/lookups.json"
## How long "found nothing" is trusted before we look again.
const MISS_TTL := 3 * 86400

signal _memo_done(key: String)

var _cache := {}
var _cache_src := {}
var _pending := {}
var _queue: Array[Dictionary] = []
var _active := 0
var _hero_order: Array[String] = []
var _memo := {}
var _memo_pending := {}
var _lookups := {}
var _lookups_queued := false


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(CACHE_DIR)
	_load_lookups()
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
	_memo.clear()
	_lookups.clear()
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
	candidates.append_array(sidecar_art(str(e.get("path", "")), kind, str(e.get("name", ""))))
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
	_missing.call_deferred(id, kind)


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
	if kind == &"logo" and img.detect_alpha() != Image.ALPHA_NONE:
		# Store logos often carry wide transparent margins; trim them so the
		# logo lines up with the text under it.
		var used := img.get_used_rect()
		if used.has_area() and used.size != img.get_size():
			img.copy_from(img.get_region(used))
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
			var w := c.s * c.s * smoothstep(0.12, 0.55, c.v) * c.a
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


func _missing(id: String, kind: StringName) -> void:
	var key := _key(id, kind)
	var online := not App.smoke_test or App.screenshot_dir != ""
	if online and _remembered(_miss_key(id, kind)) == null:
		_queue.append({"id": id, "kind": kind})
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
	var id: String = job["id"]
	var kind: StringName = job["kind"]
	var sources := await _sources_for(id)
	var urls: PackedStringArray = sources.get(kind, PackedStringArray())
	for url in urls:
		if url.begins_with(LAZY):
			url = await _resolve_lazy(url, kind)
			if url == "":
				continue
		var body := await _http_get(url)
		var ext := _image_ext(body)
		if ext == "" or body.size() <= 2048:
			continue
		if kind == &"logo" and not _is_cutout(body):
			continue
		var f := FileAccess.open(_cache_file(id, kind, ext), FileAccess.WRITE)
		if f:
			f.store_buffer(body)
			f.close()
		_forget_lookup(_miss_key(id, kind))
		_active -= 1
		_pump()
		var e := Library.get_entry(id)
		var want_accent := kind == &"cover" and not e.is_empty() and str(e.get("color", "")) == ""
		WorkerThreadPool.add_task(_load_worker.bind(id, kind, PackedStringArray([_cache_file(id, kind, ext)]), "", "", want_accent), false, "Decode artwork")
		return
	# Nothing anywhere: don't ask the internet again for a few days.
	if Library.has_entry(id):
		_remember(_miss_key(id, kind), "")
	_active -= 1
	_pump()
	var key := _key(id, kind)
	_pending.erase(key)
	_cache[key] = null
	art_ready.emit(id, kind)


## Logos sit on top of the hero, so only images with transparency will do.
static func _is_cutout(body: PackedByteArray) -> bool:
	var img := decode(body)
	return img != null and img.detect_alpha() != Image.ALPHA_NONE


static func _image_ext(body: PackedByteArray) -> String:
	if body.size() < 16:
		return ""
	if body[0] == 0x89 and body[1] == 0x50:
		return "png"
	if body[0] == 0xFF and body[1] == 0xD8:
		return "jpg"
	if body[0] == 0x52 and body[1] == 0x49 and body[8] == 0x57:
		return "webp"
	return ""


# --- Where art comes from ----------------------------------------------------------

## Every URL worth trying for each kind of art for one entry, best first. Some
## are LAZY markers that cost a request of their own, resolved only if needed.
func _sources_for(id: String) -> Dictionary:
	var e := Library.get_entry(id)
	if e.is_empty():
		return {}
	return await _once("sources:%s:%s" % [id, e["name"]], _build_sources.bind(e.duplicate()))


func _build_sources(e: Dictionary) -> Dictionary:
	var name := str(e.get("name", ""))
	var source := str(e.get("source", ""))
	var game := str(e.get("kind", "")) == "game"
	var steam_id := str(e.get("steam_appid", ""))
	# Most games are on Steam even when installed from somewhere else, and
	# Steam's library art (clean hero, tall capsule, transparent logo) is the best.
	if steam_id == "" and game:
		steam_id = await _steam_id_by_name(name)
	var epic := epic_ids(e)
	var gog_id := gog_id_for(str(e.get("path", ""))) if source != "steam" and source != "epic" else ""
	var out := {}
	for kind: StringName in MAX_SIZE.keys():
		var urls := PackedStringArray()
		if steam_id != "":
			urls.append_array(await _steam_urls(steam_id, kind))
		if source == "epic" or game:
			urls.append_array(await _epic_urls(str(epic.get("item", "")), name, kind))
		if str(epic.get("app", "")) != "":
			urls.append(LAZY + "gamesdb/epic/" + str(epic["app"]))
		var other := gamesdb_ref(e)
		if other != "":
			urls.append(LAZY + "gamesdb/" + other)
		if gog_id != "":
			urls.append(LAZY + "gamesdb/gog/" + gog_id)
			if kind == &"hero":
				urls.append(LAZY + "gog/" + gog_id)
		if steam_id != "":
			urls.append(LAZY + "gamesdb/steam/" + steam_id)
			urls.append_array(await _steam_fallback_urls(steam_id, kind))
		if game and kind == &"cover":
			urls.append(LAZY + "wiki/" + name)
		out[kind] = urls
	return out


func _resolve_lazy(url: String, kind: StringName) -> String:
	var rest := url.trim_prefix(LAZY)
	if rest.begins_with("gamesdb/"):
		var parts := rest.split("/", true, 2)
		var imgs: Dictionary = await _once("gamesdb:%s:%s" % [parts[1], parts[2]], _fetch_gamesdb.bind(parts[1], parts[2]))
		return str(imgs.get(kind, ""))
	if rest.begins_with("gog/"):
		var gid := rest.trim_prefix("gog/")
		return str(await _once("gog:" + gid, _fetch_gog_background.bind(gid)))
	if rest.begins_with("wiki/"):
		return await _wiki_cover(rest.trim_prefix("wiki/"))
	return ""


## Steam's own asset files for an app, from its store API and CDN.
func _steam_urls(appid: String, kind: StringName) -> PackedStringArray:
	var urls := PackedStringArray()
	var assets: Dictionary = await _steam_assets_for(appid)
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
	return urls


## Steam's store header (wide, with the title baked in): better than nothing.
func _steam_fallback_urls(appid: String, kind: StringName) -> PackedStringArray:
	var urls := PackedStringArray()
	if kind == &"logo":
		return urls
	var assets: Dictionary = await _steam_assets_for(appid)
	var fmt := str(assets.get("asset_url_format", ""))
	if fmt != "" and assets.has("header"):
		urls.append(STEAM_ASSET_BASE + fmt.replace("%s", str(assets["header"])))
	urls.append((STEAM_CDN[0] % appid) + "header.jpg")
	return urls


## Asks Steam's store for the app's asset table once, shared by all three kinds.
func _steam_assets_for(appid: String) -> Dictionary:
	return await _once("steam_assets:" + appid, _fetch_steam_assets.bind(appid))


func _fetch_steam_assets(appid: String) -> Dictionary:
	var query := {
		"ids": [{"appid": int(appid)}],
		"context": {"language": "english", "country_code": "US", "steam_realm": 1},
		"data_request": {"include_assets": true},
	}
	var data: Variant = await _http_json(STEAM_ITEMS_API + JSON.stringify(query).uri_encode())
	if data is Dictionary:
		var items: Variant = data.get("response", {}).get("store_items", [])
		if items is Array and not items.is_empty() and items[0] is Dictionary:
			var a: Variant = items[0].get("assets", {})
			if a is Dictionary:
				return a
	return {}


## Finds a game's Steam app id from its name; only an exact title match counts.
func _steam_id_by_name(name: String) -> String:
	var norm := norm_title(name)
	if norm == "":
		return ""
	var key := "steam_name:" + norm
	var known: Variant = _remembered(key)
	if known != null:
		return str(known)
	return str(await _once(key, _search_steam.bind(name, key)))


func _search_steam(name: String, key: String) -> String:
	var data: Variant = await _http_json(STEAM_SEARCH % name.uri_encode())
	if not data is Dictionary:
		return ""
	var found := match_steam_search(data, name)
	_remember(key, found)
	return found


static func match_steam_search(data: Dictionary, name: String) -> String:
	var norm := norm_title(name)
	var items: Variant = data.get("items", [])
	if items is Array:
		for it in items:
			if it is Dictionary and norm_title(str(it.get("name", ""))) == norm:
				return str(int(it.get("id", 0)))
	return ""


## Art the Epic launcher already downloaded, from its local catalog cache.
func _epic_urls(item_id: String, name: String, kind: StringName) -> PackedStringArray:
	var urls := PackedStringArray()
	var cat: Dictionary = await _once("epic_catalog", _load_epic_catalog)
	var imgs: Variant = null
	if item_id != "":
		imgs = cat.get("by_id", {}).get(item_id)
	if imgs == null:
		imgs = cat.get("by_title", {}).get(norm_title(name))
	if imgs is Dictionary:
		var types: Array = EPIC_TYPES[kind]
		for t in types:
			if imgs.has(t):
				urls.append(str(imgs[t]))
	return urls


func _load_epic_catalog() -> Dictionary:
	var path := ""
	if App.is_windows():
		path = OS.get_environment("LOCALAPPDATA").replace("\\", "/").path_join(EPIC_CATCACHE)
	var result := {}
	if path == "" or not FileAccess.file_exists(path):
		return result
	var task := WorkerThreadPool.add_task(func() -> void: result.merge(parse_epic_catalog(FileAccess.get_file_as_string(path))), false, "Read Epic catalog")
	while not WorkerThreadPool.is_task_completed(task):
		await get_tree().process_frame
	WorkerThreadPool.wait_for_task_completion(task)
	return result


## The launcher's catcache.bin is base64-wrapped JSON: an array of catalog items
## that each carry a keyImages list. Indexed by item id and by title.
static func parse_epic_catalog(text: String) -> Dictionary:
	var raw := text.strip_edges()
	if not raw.begins_with("["):
		raw = Marshalls.base64_to_raw(raw).get_string_from_utf8()
	var data: Variant = JSON.parse_string(raw)
	var by_id := {}
	var by_title := {}
	if data is Array:
		for item in data:
			if not item is Dictionary or not item.get("keyImages") is Array:
				continue
			var imgs := {}
			for k in item["keyImages"]:
				if k is Dictionary and str(k.get("url", "")).begins_with("http"):
					imgs[str(k.get("type", ""))] = str(k["url"])
			if imgs.is_empty():
				continue
			by_id[str(item.get("id", ""))] = imgs
			if not item.has("mainGameItem"):
				var t := norm_title(str(item.get("title", "")))
				if t != "" and not by_title.has(t):
					by_title[t] = imgs
	return {"by_id": by_id, "by_title": by_title}


## Catalog ids from an Epic entry's launch URI (namespace:item:app).
static func epic_ids(e: Dictionary) -> Dictionary:
	var out := {"app": str(e.get("epic_app", ""))}
	var uri := str(e.get("epic_uri", ""))
	if uri.contains("/apps/"):
		var parts := uri.get_slice("/apps/", 1).get_slice("?", 0).replace("%3A", ":").replace("%3a", ":").split(":")
		if parts.size() >= 3:
			out = {"ns": parts[0], "item": parts[1], "app": parts[2]}
	return out


## Images dropped next to a game's exe: cover.png, banner.jpg, logo.png, or the
## same with the game's name in front ("My Game_banner.png", "my-game-cover.jpg").
static func sidecar_art(path: String, kind: StringName, name: String = "") -> PackedStringArray:
	var out := PackedStringArray()
	if path == "" or path.contains("://") or path.begins_with("shell:") or not path.to_lower().ends_with(".exe"):
		return out
	var dir := path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		return out
	var owners := [norm_title(path.get_file().get_basename()), norm_title(dir.get_file()), norm_title(name)]
	var plain := PackedStringArray()
	for f in DirAccess.get_files_at(dir):
		var ext := f.get_extension().to_lower()
		if not ext in ["png", "jpg", "jpeg", "webp"]:
			continue
		var base := f.get_basename().to_lower()
		for role: String in SIDECAR_NAMES[kind]:
			if base == role:
				plain.append(dir.path_join(f))
			elif base.ends_with(role):
				var owner := norm_title(base.trim_suffix(role))
				if owner != "" and owner in owners:
					out.append(dir.path_join(f))
	out.append_array(plain)
	return out


## GOG Galaxy's platform/id for games from other launchers ("" if unknown).
static func gamesdb_ref(e: Dictionary) -> String:
	var path := str(e.get("path", ""))
	match str(e.get("source", "")):
		"riot":
			var m := RegEx.create_from_string("--launch-product=(\\S+)").search(str(e.get("args", "")))
			if m:
				return "riot/" + m.get_string(1)
		"ubisoft":
			var id := path.trim_prefix("uplay://launch/").get_slice("/", 0)
			if id.is_valid_int():
				return "uplay/" + id
		"amazon":
			var id := path.trim_prefix("amazon-games://play/")
			if id != "" and id != path:
				return "amazon/" + id
	return ""


## GOG games ship a goggame-<id>.info next to the executable.
static func gog_id_for(path: String) -> String:
	if path == "" or path.contains("://"):
		return ""
	var dir := path if DirAccess.dir_exists_absolute(path) else path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		return ""
	for f in DirAccess.get_files_at(dir):
		if f.begins_with("goggame-") and f.ends_with(".info"):
			var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join(f)))
			if data is Dictionary and str(data.get("gameId", "")) != "":
				return str(data["gameId"])
			var digits := f.trim_prefix("goggame-").trim_suffix(".info")
			if digits.is_valid_int():
				return digits
	return ""


## GOG Galaxy's games database maps Steam, Epic and GOG releases to one game
## with a tall cover, a background and a transparent logo. No key needed.
func _fetch_gamesdb(platform: String, ext_id: String) -> Dictionary:
	var data: Variant = await _http_json(GAMESDB % [platform, ext_id.uri_encode()])
	return gamesdb_images(data) if data is Dictionary else {}


static func gamesdb_images(data: Dictionary) -> Dictionary:
	var out := {}
	var game: Variant = data.get("game", {})
	if not game is Dictionary:
		game = {}
	for pair in [[&"cover", "vertical_cover"], [&"hero", "background"], [&"logo", "logo"]]:
		var img: Variant = game.get(pair[1], data.get(pair[1]))
		if img is Dictionary and str(img.get("url_format", "")) != "":
			var ext := "png" if pair[0] == &"logo" else "jpg"
			out[pair[0]] = str(img["url_format"]).replace("{formatter}", "").replace("{ext}", ext)
	# Some entries reuse the cover image as their "logo".
	if out.has(&"logo") and out.has(&"cover") and str(out[&"logo"]).get_basename() == str(out[&"cover"]).get_basename():
		out.erase(&"logo")
	return out


func _fetch_gog_background(gog_id: String) -> String:
	var data: Variant = await _http_json(GOG_PRODUCT % gog_id)
	if data is Dictionary and data.get("images") is Dictionary:
		var bg := str(data["images"].get("background", ""))
		if bg.begins_with("//"):
			return "https:" + bg
		return bg
	return ""


## Last resort for a cover: the game's Wikipedia infobox image.
func _wiki_cover(name: String) -> String:
	var norm := norm_title(name)
	if norm == "":
		return ""
	var key := "wiki:" + norm
	var known: Variant = _remembered(key)
	if known != null:
		return str(known)
	return str(await _once(key, _search_wiki.bind(name, key)))


func _search_wiki(name: String, key: String) -> String:
	var data: Variant = await _http_json(WIKI_SEARCH % (name + " video game").uri_encode())
	if not data is Dictionary:
		return ""
	var found := match_wiki(data, name)
	_remember(key, found)
	return found


static func match_wiki(data: Dictionary, name: String) -> String:
	var norm := norm_title(name)
	var pages: Variant = data.get("query", {}).get("pages", [])
	if not pages is Array:
		return ""
	var list: Array = pages.duplicate()
	list.sort_custom(func(a: Variant, b: Variant) -> bool: return int(a.get("index", 0)) < int(b.get("index", 0)))
	for p in list:
		if not p is Dictionary:
			continue
		var title := str(p.get("title", "")).get_slice(" (", 0)
		var thumb: Variant = p.get("thumbnail", {})
		if norm_title(title) == norm and thumb is Dictionary and str(thumb.get("source", "")) != "":
			return str(thumb["source"])
	return ""


## Lowercase letters and digits only, so "Marvel Rivals™" matches "MARVEL RIVALS".
static func norm_title(s: String) -> String:
	var t := s.to_lower().replace("&", "and")
	var out := ""
	for c in t:
		if (c >= "a" and c <= "z") or (c >= "0" and c <= "9"):
			out += c
	return out


# --- Requests and lookups ----------------------------------------------------------

func _http_get(url: String) -> PackedByteArray:
	var http := HTTPRequest.new()
	http.timeout = 15.0
	http.use_threads = true
	add_child(http)
	var body := PackedByteArray()
	if http.request(url, ["User-Agent: %s/%s" % [App.USER_AGENT, App.version]]) == OK:
		var res: Array = await http.request_completed
		if int(res[0]) == HTTPRequest.RESULT_SUCCESS and int(res[1]) == 200:
			body = res[3]
	http.queue_free()
	return body


func _http_json(url: String) -> Variant:
	var body := await _http_get(url)
	if body.is_empty():
		return null
	return JSON.parse_string(body.get_string_from_utf8())


## Runs fn once per key and shares the result with everyone who asks meanwhile.
func _once(key: String, fn: Callable) -> Variant:
	if _memo.has(key):
		return _memo[key]
	if _memo_pending.has(key):
		while _memo_pending.has(key):
			await _memo_done
		return _memo.get(key)
	_memo_pending[key] = true
	var v: Variant = await fn.call()
	_memo[key] = v
	_memo_pending.erase(key)
	_memo_done.emit(key)
	return v


func _miss_key(id: String, kind: StringName) -> String:
	return "miss:%s:%s:%s" % [id, kind, norm_title(str(Library.get_entry(id).get("name", "")))]


## A remembered lookup, or null if unknown. Misses ("") expire so we retry.
func _remembered(key: String) -> Variant:
	var r: Variant = _lookups.get(key)
	if not r is Dictionary:
		return null
	var v: Variant = r.get("v", "")
	if str(v) == "" and int(Time.get_unix_time_from_system()) - int(r.get("t", 0)) > MISS_TTL:
		return null
	return v


func _remember(key: String, v: Variant) -> void:
	_lookups[key] = {"v": v, "t": int(Time.get_unix_time_from_system())}
	_save_lookups()


func _forget_lookup(key: String) -> void:
	if _lookups.erase(key):
		_save_lookups()


func _load_lookups() -> void:
	if App.smoke_test or not FileAccess.file_exists(LOOKUPS_PATH):
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(LOOKUPS_PATH))
	if data is Dictionary:
		_lookups = data


func _save_lookups() -> void:
	if _lookups_queued or App.smoke_test:
		return
	_lookups_queued = true
	await get_tree().process_frame
	_lookups_queued = false
	var f := FileAccess.open(LOOKUPS_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(_lookups))
		f.close()


func _touch_hero(key: String) -> void:
	_hero_order.erase(key)
	_hero_order.append(key)
	while _hero_order.size() > HERO_CACHE_LIMIT:
		var old: String = _hero_order.pop_front()
		_cache.erase(old)
