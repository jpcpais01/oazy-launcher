extends Node
## The user's library: games and apps, persistence, store imports (Steam, Epic, GOG),
## launching and playtime tracking.

signal changed
signal entry_changed(id: String)
signal launched(id: String)
signal import_finished(added: int, found: int)

const PATH := "user://library.json"
const SMOKE_PATH := "user://smoke/library.json"
const EPIC_MANIFESTS := "C:/ProgramData/Epic/EpicGamesLauncher/Data/Manifests"
const STEAM_SKIP_IDS := [
	"228980", "1070560", "1391110", "1628350", "1493710", "1826330", "2180100",
	"1113280", "1161040", "961940", "1054830", "1245040", "1420170", "1580130",
]
const STEAM_SKIP_WORDS := [
	"redistributable", "steamworks", "proton", "steam linux runtime",
	"dedicated server", " sdk", "soundtrack", "steamvr",
]
const POLL_SECONDS := 8.0
const KNOWN_APPS := [
	"discord", "spotify", "chrome", "firefox", "msedge", "brave", "opera", "obs", "code",
	"slack", "teams", "zoom", "notion", "figma", "blender", "photoshop", "vlc", "telegram",
	"whatsapp", "steam.exe", "epicgameslauncher", "galaxyclient", "battle.net", "notepad",
]

var entries: Array[Dictionary] = []
var steam_root := ""
var importing := false

var _path := PATH
var _sessions := {}
var _poll_busy := false
var _save_queued := false


func _ready() -> void:
	if App.smoke_test:
		_path = SMOKE_PATH
		DirAccess.make_dir_recursive_absolute(SMOKE_PATH.get_base_dir())
		if FileAccess.file_exists(SMOKE_PATH):
			DirAccess.remove_absolute(SMOKE_PATH)
	load_library()
	steam_root = str(Settings.get_value("steam_root"))
	if steam_root == "" and App.is_windows() and not App.smoke_test:
		WorkerThreadPool.add_task(func() -> void: _set_steam_root.call_deferred(find_steam_root()), false, "Find Steam")
	var timer := Timer.new()
	timer.wait_time = POLL_SECONDS
	timer.autostart = true
	timer.timeout.connect(_poll_sessions)
	add_child(timer)


# --- Model -------------------------------------------------------------------

func make_entry(fields: Dictionary = {}) -> Dictionary:
	var e := {
		"id": _new_id(),
		"name": "Untitled",
		"path": "",
		"args": "",
		"kind": "game",
		"source": "custom",
		"steam_appid": "",
		"epic_app": "",
		"epic_uri": "",
		"cover": "",
		"hero": "",
		"logo": "",
		"color": "",
		"favorite": false,
		"added_at": int(Time.get_unix_time_from_system()),
		"last_played": 0,
		"playtime": 0,
		"launches": 0,
	}
	e.merge(fields, true)
	return e


func get_entry(id: String) -> Dictionary:
	for e in entries:
		if e["id"] == id:
			return e
	return {}


func has_entry(id: String) -> bool:
	return not get_entry(id).is_empty()


func add_entry(fields: Dictionary) -> String:
	var e := make_entry(fields)
	if str(e["name"]).strip_edges().is_empty():
		e["name"] = Fmt.pretty_name(str(e["path"]))
	entries.append(e)
	_queue_save()
	changed.emit()
	return e["id"]


func update_entry(id: String, fields: Dictionary) -> void:
	var e := get_entry(id)
	if e.is_empty():
		return
	var structural := fields.has("name") or fields.has("kind") or fields.has("favorite")
	e.merge(fields, true)
	_queue_save()
	entry_changed.emit(id)
	if structural:
		changed.emit()


func remove_entry(id: String) -> void:
	for i in entries.size():
		if entries[i]["id"] == id:
			entries.remove_at(i)
			_sessions.erase(id)
			_queue_save()
			changed.emit()
			return


func toggle_favorite(id: String) -> bool:
	var e := get_entry(id)
	if e.is_empty():
		return false
	var fav := not bool(e["favorite"])
	update_entry(id, {"favorite": fav})
	return fav


## Home row order: most recently played first, then newest additions.
func recent() -> Array[Dictionary]:
	var list: Array[Dictionary] = entries.duplicate()
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var la := int(a["last_played"])
		var lb := int(b["last_played"])
		if la != lb:
			return la > lb
		return int(a["added_at"]) > int(b["added_at"])
	)
	return list


func query(filter: String, text: String, sort: String) -> Array[Dictionary]:
	var needle := text.strip_edges().to_lower()
	var list: Array[Dictionary] = []
	for e in entries:
		match filter:
			"games":
				if e["kind"] != "game":
					continue
			"apps":
				if e["kind"] != "app":
					continue
			"favorites":
				if not e["favorite"]:
					continue
		if needle != "" and not str(e["name"]).to_lower().contains(needle):
			continue
		list.append(e)
	match sort:
		"name":
			list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				return str(a["name"]).naturalnocasecmp_to(str(b["name"])) < 0
			)
		"playtime":
			list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				return int(a["playtime"]) > int(b["playtime"])
			)
		_:
			var order := recent()
			var rank := {}
			for i in order.size():
				rank[order[i]["id"]] = i
			list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				return int(rank[a["id"]]) < int(rank[b["id"]])
			)
	return list


func source_label(e: Dictionary) -> String:
	match str(e.get("source", "")):
		"steam": return "Steam"
		"epic": return "Epic Games"
		"gog": return "GOG"
	return "Game" if e.get("kind") == "game" else "App"


## Builds entry fields from a file, shortcut or URL the user picked or dropped.
static func infer_from_path(path: String) -> Dictionary:
	var d := {"path": path, "name": Fmt.pretty_name(path), "kind": "game", "source": "custom"}
	if path.contains("://"):
		d["name"] = path.get_slice("://", 1).get_slice("/", 0).trim_prefix("www.")
		d["kind"] = "app"
		return d
	var ext := path.get_extension().to_lower()
	if ext == "url" and FileAccess.file_exists(path):
		for line in FileAccess.get_file_as_string(path).split("\n"):
			var l := line.strip_edges()
			if not l.begins_with("URL="):
				continue
			var url := l.substr(4)
			var steam := RegEx.create_from_string("steam://rungameid/(\\d+)").search(url)
			if steam:
				d["source"] = "steam"
				d["steam_appid"] = steam.get_string(1)
			elif url.begins_with("com.epicgames.launcher://"):
				d["source"] = "epic"
				d["epic_uri"] = url
				d["epic_app"] = url.get_slice("?", 0).get_slice("%3A", 2)
	var lower := path.get_file().to_lower()
	for app in KNOWN_APPS:
		if lower.begins_with(app):
			d["kind"] = "app"
	return d


# --- Persistence ---------------------------------------------------------------

func load_library() -> void:
	entries.clear()
	if not FileAccess.file_exists(_path):
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(_path))
	if data is Array:
		for item in data:
			if item is Dictionary and item.has("id"):
				entries.append(make_entry(item))


func save_now() -> void:
	_save_queued = false
	DirAccess.make_dir_recursive_absolute(_path.get_base_dir())
	var tmp := _path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_warning("Could not save library: %s" % error_string(FileAccess.get_open_error()))
		return
	f.store_string(JSON.stringify(entries, "\t"))
	f.close()
	DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(_path))


func _queue_save() -> void:
	if _save_queued:
		return
	_save_queued = true
	save_now.call_deferred()


func _new_id() -> String:
	return "%x%06x" % [int(Time.get_unix_time_from_system() * 1000.0), randi() % 0xffffff]


# --- Launching -----------------------------------------------------------------

func launch(id: String) -> bool:
	var e := get_entry(id)
	if e.is_empty():
		return false
	var ok := false
	match str(e["source"]):
		"steam":
			ok = OS.shell_open("steam://rungameid/%s" % e["steam_appid"]) == OK
		"epic":
			ok = OS.shell_open(str(e["epic_uri"])) == OK
		_:
			ok = _launch_path(e)
	if ok:
		update_entry(id, {
			"last_played": int(Time.get_unix_time_from_system()),
			"launches": int(e["launches"]) + 1,
		})
		launched.emit(id)
	return ok


func _launch_path(e: Dictionary) -> bool:
	var path := str(e["path"]).strip_edges()
	if path.is_empty():
		App.toast("%s has no file to launch yet. Edit it to pick one." % e["name"], &"error")
		return false
	if path.contains("://"):
		return OS.shell_open(path) == OK
	if not FileAccess.file_exists(path):
		App.toast("Can't find %s. Was it moved or uninstalled?" % path.get_file(), &"error")
		return false
	var ext := path.get_extension().to_lower()
	if not App.is_windows():
		return OS.create_process(path, split_args(str(e["args"]))) > 0
	if ext in ["lnk", "url", "appref-ms"]:
		return OS.shell_open(path) == OK
	# Start through a tiny script so the program gets its own folder as the
	# working directory; plenty of games refuse to start otherwise.
	var script := _write_launch_script(str(e["id"]), path, str(e["args"]))
	if script.is_empty():
		return OS.create_process(path, split_args(str(e["args"]))) > 0
	var pid := OS.create_process("cmd.exe", ["/c", script])
	if pid > 0 and ext == "exe":
		_sessions[e["id"]] = {
			"image": path.get_file().to_lower(),
			"started": int(Time.get_unix_time_from_system()),
			"seen_at": 0,
			"last_seen": 0,
		}
	return pid > 0


func _write_launch_script(id: String, path: String, args: String) -> String:
	DirAccess.make_dir_recursive_absolute("user://launch")
	var file := "user://launch/%s.cmd" % id
	var f := FileAccess.open(file, FileAccess.WRITE)
	if f == null:
		return ""
	var win_path := path.replace("/", "\\")
	var dir := win_path.get_base_dir()
	f.store_string("@echo off\r\nchcp 65001 >nul\r\ncd /d \"%s\"\r\nstart \"\" \"%s\" %s\r\n" % [dir, win_path, args])
	f.close()
	return ProjectSettings.globalize_path(file).replace("/", "\\")


## Splits a command line into arguments, honouring double quotes.
static func split_args(text: String) -> PackedStringArray:
	var out := PackedStringArray()
	var cur := ""
	var quoted := false
	var has := false
	for c in text:
		if c == "\"":
			quoted = not quoted
			has = true
		elif (c == " " or c == "\t") and not quoted:
			if has:
				out.append(cur)
			cur = ""
			has = false
		else:
			cur += c
			has = true
	if has:
		out.append(cur)
	return out


# --- Playtime ------------------------------------------------------------------

func _poll_sessions() -> void:
	if _sessions.is_empty() or _poll_busy or not App.is_windows():
		return
	_poll_busy = true
	var images := PackedStringArray()
	for s in _sessions.values():
		images.append(s["image"])
	WorkerThreadPool.add_task(_poll_worker.bind(images), false, "Playtime poll")


func _poll_worker(images: PackedStringArray) -> void:
	var out := []
	OS.execute("tasklist", ["/FO", "CSV", "/NH"], out)
	var text := "" if out.is_empty() else str(out[0]).to_lower()
	var result := {}
	for img in images:
		result[img] = text.contains("\"%s\"" % img)
	_apply_poll.call_deferred(result)


func _apply_poll(result: Dictionary) -> void:
	_poll_busy = false
	var now := int(Time.get_unix_time_from_system())
	var any_running := false
	for id in _sessions.keys():
		var s: Dictionary = _sessions[id]
		var running: bool = result.get(s["image"], false)
		if running:
			if int(s["seen_at"]) == 0:
				s["seen_at"] = int(s["started"])
			s["last_seen"] = now
			any_running = true
		elif int(s["seen_at"]) > 0:
			var played := maxi(0, int(s["last_seen"]) - int(s["seen_at"]) + int(POLL_SECONDS / 2.0))
			var e := get_entry(id)
			if not e.is_empty():
				update_entry(id, {"playtime": int(e["playtime"]) + played})
			_sessions.erase(id)
		elif now - int(s["started"]) > 90:
			_sessions.erase(id)
	if App.game_running != any_running:
		App.game_running = any_running
		App.refresh_fps()


# --- Store imports -------------------------------------------------------------

func import_stores() -> void:
	if importing:
		return
	importing = true
	WorkerThreadPool.add_task(_import_worker, false, "Scan game stores")


func _import_worker() -> void:
	var found: Array = []
	var root := find_steam_root()
	if root != "":
		found.append_array(scan_steam_root(root))
	found.append_array(scan_epic(EPIC_MANIFESTS))
	found.append_array(scan_gog())
	_import_apply.call_deferred(found, root)


func _set_steam_root(root: String) -> void:
	if root != "":
		steam_root = root
		Settings.set_value("steam_root", root)


func _import_apply(found: Array, root: String) -> void:
	importing = false
	_set_steam_root(root)
	var added := 0
	for item in found:
		if _already_imported(item):
			continue
		var e := make_entry(item)
		entries.append(e)
		added += 1
	if added > 0:
		_queue_save()
		changed.emit()
	import_finished.emit(added, found.size())


func _already_imported(item: Dictionary) -> bool:
	for e in entries:
		match str(item.get("source", "")):
			"steam":
				if str(e["steam_appid"]) == str(item["steam_appid"]):
					return true
			"epic":
				if str(e["epic_app"]) == str(item["epic_app"]):
					return true
		var p := str(item.get("path", ""))
		if p != "" and str(e["path"]).to_lower() == p.to_lower() and e["source"] == item.get("source", ""):
			return true
	return false


func find_steam_root() -> String:
	if not App.is_windows():
		return ""
	var queries := [
		["HKCU\\Software\\Valve\\Steam", "SteamPath"],
		["HKLM\\SOFTWARE\\WOW6432Node\\Valve\\Steam", "InstallPath"],
	]
	for q in queries:
		var out := []
		if OS.execute("reg", ["query", q[0], "/v", q[1]], out) == 0 and not out.is_empty():
			for line in str(out[0]).split("\n"):
				if line.contains("REG_SZ"):
					var p := line.split("REG_SZ")[1].strip_edges().replace("\\", "/")
					if DirAccess.dir_exists_absolute(p):
						return p
	for c in ["C:/Program Files (x86)/Steam", "C:/Program Files/Steam"]:
		if DirAccess.dir_exists_absolute(c):
			return c
	return ""


static func scan_steam_root(root: String) -> Array:
	var libs := PackedStringArray([root])
	var vdf_path := root.path_join("steamapps/libraryfolders.vdf")
	if FileAccess.file_exists(vdf_path):
		var data := Vdf.parse(FileAccess.get_file_as_string(vdf_path))
		var folders: Variant = Vdf.get_key(data, "libraryfolders", {})
		if folders is Dictionary:
			for k in folders.keys():
				var v: Variant = folders[k]
				var p := ""
				if v is Dictionary:
					p = str(Vdf.get_key(v, "path", ""))
				elif v is String and str(k).is_valid_int():
					p = v
				p = p.replace("\\", "/")
				if p != "":
					var known := false
					for l in libs:
						if l.to_lower() == p.to_lower():
							known = true
					if not known:
						libs.append(p)
	var found: Array = []
	var seen := {}
	for lib in libs:
		var apps_dir := lib.path_join("steamapps")
		if not DirAccess.dir_exists_absolute(apps_dir):
			continue
		for f in DirAccess.get_files_at(apps_dir):
			if not (f.begins_with("appmanifest_") and f.ends_with(".acf")):
				continue
			var acf := Vdf.parse(FileAccess.get_file_as_string(apps_dir.path_join(f)))
			var state: Variant = Vdf.get_key(acf, "AppState", {})
			if not state is Dictionary:
				continue
			var appid := str(Vdf.get_key(state, "appid", ""))
			var name := str(Vdf.get_key(state, "name", ""))
			if appid == "" or name == "" or seen.has(appid) or is_steam_tool(appid, name):
				continue
			seen[appid] = true
			found.append({
				"name": name,
				"source": "steam",
				"kind": "game",
				"steam_appid": appid,
				"path": apps_dir.path_join("common").path_join(str(Vdf.get_key(state, "installdir", ""))),
			})
	return found


static func is_steam_tool(appid: String, name: String) -> bool:
	if appid in STEAM_SKIP_IDS:
		return true
	var lower := " " + name.to_lower()
	for w in STEAM_SKIP_WORDS:
		if lower.contains(w):
			return true
	return false


static func scan_epic(manifest_dir: String) -> Array:
	var found: Array = []
	if not DirAccess.dir_exists_absolute(manifest_dir):
		return found
	for f in DirAccess.get_files_at(manifest_dir):
		if not f.to_lower().ends_with(".item"):
			continue
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_dir.path_join(f)))
		if not data is Dictionary:
			continue
		var item := epic_entry(data)
		if not item.is_empty():
			found.append(item)
	return found


static func epic_entry(data: Dictionary) -> Dictionary:
	if bool(data.get("bIsIncompleteInstall", false)):
		return {}
	var app := str(data.get("AppName", ""))
	var main_app := str(data.get("MainGameAppName", app))
	if app == "" or main_app != app:
		return {}
	var cats: Variant = data.get("AppCategories", [])
	if cats is Array and cats.has("addons"):
		return {}
	var ns := str(data.get("CatalogNamespace", ""))
	var item_id := str(data.get("CatalogItemId", ""))
	var install := str(data.get("InstallLocation", "")).replace("\\", "/")
	var exe := str(data.get("LaunchExecutable", "")).replace("\\", "/")
	return {
		"name": str(data.get("DisplayName", app)),
		"source": "epic",
		"kind": "game" if (cats is Array and cats.has("games")) else "app",
		"epic_app": app,
		"epic_uri": "com.epicgames.launcher://apps/%s%%3A%s%%3A%s?action=launch&silent=true" % [ns, item_id, app],
		"path": install.path_join(exe) if exe != "" else install,
	}


static func scan_gog() -> Array:
	var found: Array = []
	if OS.get_name() != "Windows":
		return found
	var out := []
	if OS.execute("reg", ["query", "HKLM\\SOFTWARE\\WOW6432Node\\GOG.com\\Games", "/s"], out) != 0 or out.is_empty():
		return found
	return parse_gog_registry(str(out[0]))


static func parse_gog_registry(text: String) -> Array:
	var found: Array = []
	var cur := {}
	for raw in text.split("\n"):
		var line := raw.strip_edges()
		if line.begins_with("HKEY_"):
			_flush_gog(cur, found)
			cur = {}
			continue
		for key in ["gameName", "exe", "workingDir", "launchParam"]:
			if line.begins_with(key + " ") and line.contains("REG_SZ"):
				cur[key] = line.split("REG_SZ", true, 1)[1].strip_edges()
	_flush_gog(cur, found)
	return found


static func _flush_gog(cur: Dictionary, found: Array) -> void:
	if cur.has("gameName") and cur.has("exe"):
		found.append({
			"name": cur["gameName"],
			"source": "gog",
			"kind": "game",
			"path": str(cur["exe"]).replace("\\", "/"),
			"args": str(cur.get("launchParam", "")),
		})
