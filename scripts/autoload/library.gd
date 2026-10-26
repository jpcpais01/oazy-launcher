extends Node
## The user's library: games and apps, persistence, store imports (Steam, Epic,
## GOG, EA, Ubisoft, Battle.net, Riot, Amazon, Xbox), launching and playtime tracking.

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
## Windows "installed programs" lists, read for the launchers without their own files.
const UNINSTALL_KEYS := [
	"HKLM\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall",
	"HKLM\\SOFTWARE\\WOW6432Node\\Microsoft\\Windows\\CurrentVersion\\Uninstall",
	"HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall",
]
const UNINSTALL_VALUES := ["DisplayName", "DisplayIcon", "InstallLocation", "UninstallString", "Publisher", "SystemComponent", "ParentKeyName", "ReleaseType"]
## Launchers and helpers that show up next to games in those lists.
const STORE_SKIP_NAMES := [
	"riot client", "battle.net", "ea app", "origin", "ubisoft connect", "uplay", "amazon games",
	"easyanticheat", "easy anti-cheat", "battleye", "vanguard", "directx", "visual c++", "redistributable",
]
## Publishers whose installed programs are games (standalone installs with no store).
const GAME_PUBLISHERS := [
	"mojang", "hoyoverse", "mihoyo", "cognosphere", "wargaming", "roblox", "rockstar games", "bethesda",
	"cd projekt", "square enix", "bandai namco", "krafton", "garena", "level infinite", "gaijin",
	"grinding gear", "digital extremes", "jagex", "hi-rez", "smilegate", "ncsoft", "nexon", "pearl abyss",
	"kakao games", "innersloth", "activision", "sega", "capcom", "konami", "2k games", "warner bros. games",
	"kuro games", "netease games", "playstation pc", "sony interactive", "paradox interactive", "embark studios",
]
## Launchers and tools those publishers also install.
const NOT_GAME_WORDS := ["launcher", "game center", "hoyoplay", "social club", "anti-cheat", "anticheat", "redistributable", "editor", "toolkit", "sdk", "server", "benchmark"]
const SOURCE_LABELS := {
	"steam": "Steam", "epic": "Epic Games", "gog": "GOG", "ea": "EA app", "ubisoft": "Ubisoft Connect",
	"battlenet": "Battle.net", "riot": "Riot Games", "amazon": "Amazon Games", "xbox": "Xbox",
}
## Import order doubles as preference when one game shows up in two stores.
const SOURCE_RANK := ["steam", "epic", "gog", "xbox", "ea", "ubisoft", "battlenet", "riot", "amazon"]
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
		"cwd": "",
		"kind": "game",
		"source": "custom",
		"steam_appid": "",
		"epic_app": "",
		"epic_uri": "",
		"app_id": "",
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
	# Pointing an app from Start at something else makes it a plain entry.
	var app_id := str(e.get("app_id", ""))
	if app_id != "" and fields.has("path") and str(fields["path"]).replace("\\", "/") != ("shell:AppsFolder/" + app_id).replace("\\", "/"):
		fields = fields.duplicate()
		fields["app_id"] = ""
		structural = true
	e.merge(fields, true)
	_queue_save()
	entry_changed.emit(id)
	if structural:
		changed.emit()


func remove_entry(id: String) -> void:
	for i in entries.size():
		if entries[i]["id"] == id:
			# Found automatically? Then don't bring it back on the next scan.
			if entries[i]["source"] != "custom" or bool(entries[i].get("auto", false)):
				var removed: Array = Settings.get_value("removed_imports").duplicate()
				removed.append(import_key(entries[i]))
				Settings.set_value("removed_imports", removed.slice(-200))
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
	var src := str(e.get("source", ""))
	if SOURCE_LABELS.has(src):
		return SOURCE_LABELS[src]
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
	# Apps added from Start open the way Start opens them.
	if str(e.get("app_id", "")) != "":
		ok = Catalog.launch_app(str(e["app_id"]))
	else:
		ok = _launch_source(e)
	if ok:
		update_entry(id, {
			"last_played": int(Time.get_unix_time_from_system()),
			"launches": int(e["launches"]) + 1,
		})
		launched.emit(id)
	return ok


func _launch_source(e: Dictionary) -> bool:
	var ok := false
	match str(e["source"]):
		"steam":
			ok = OS.shell_open("steam://rungameid/%s" % e["steam_appid"]) == OK
		"epic":
			ok = OS.shell_open(str(e["epic_uri"])) == OK
		_:
			ok = _launch_path(e)
	return ok


func _launch_path(e: Dictionary) -> bool:
	var path := str(e["path"]).strip_edges()
	if path.is_empty():
		App.toast("%s has no file to launch yet. Edit it to pick one." % e["name"], &"error")
		return false
	if path.contains("://"):
		return OS.shell_open(path) == OK
	if path.begins_with("shell:"):
		return OS.create_process("explorer.exe", [path]) > 0
	# Claude Code and other shell commands (cmd.exe /k claude) get a tab in
	# Oazy Terminal.
	if Terminal.enabled() and Terminal.runs_shell(path) and path.get_file().to_lower() != "wt.exe":
		var cmd := '"%s" %s' % [path.replace("/", "\\"), str(e["args"])]
		var cwd := str(e.get("cwd", "")).replace("/", "\\")
		return Terminal.open({"run": cmd.strip_edges(), "cwd": cwd, "title": str(e["name"])}, func() -> void: _launch_path_direct(e))
	return _launch_path_direct(e)


func _launch_path_direct(e: Dictionary) -> bool:
	var path := str(e["path"]).strip_edges()
	# Bare commands ("wt.exe", "code") are found on PATH by `start`.
	var bare := not path.contains("/") and not path.contains("\\")
	if not bare and not FileAccess.file_exists(path):
		App.toast("Can't find %s. Was it moved or uninstalled?" % path.get_file(), &"error")
		return false
	var ext := path.get_extension().to_lower()
	if not App.is_windows():
		return OS.create_process(path, split_args(str(e["args"]))) > 0
	if ext in ["lnk", "url", "appref-ms"] and not bare:
		return OS.shell_open(path) == OK
	# Start through a tiny script so the program gets its own folder as the
	# working directory; plenty of games refuse to start otherwise.
	var script := _write_launch_script(str(e["id"]), path, str(e["args"]), str(e.get("cwd", "")))
	if script.is_empty():
		return OS.create_process(path, split_args(str(e["args"]))) > 0
	var pid := OS.create_process("cmd.exe", ["/c", script])
	# Launcher-run games (Riot) would clock the always-on launcher, not the game.
	if pid > 0 and ext == "exe" and not bare and e["kind"] == "game" and str(e["source"]) != "riot":
		_sessions[e["id"]] = {
			"image": path.get_file().to_lower(),
			"started": int(Time.get_unix_time_from_system()),
			"seen_at": 0,
			"last_seen": 0,
		}
	return pid > 0


func _write_launch_script(id: String, path: String, args: String, cwd: String = "") -> String:
	DirAccess.make_dir_recursive_absolute("user://launch")
	var file := "user://launch/%s.cmd" % id
	var f := FileAccess.open(file, FileAccess.WRITE)
	if f == null:
		return ""
	var win_path := path.replace("/", "\\")
	var dir := cwd.replace("/", "\\") if cwd != "" else win_path.get_base_dir()
	if dir == "":
		dir = OS.get_environment("USERPROFILE")
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


## Finds the Claude Code command line tool, so it can sit on the taskbar like
## any other app. Returns the fields for a library entry, or {} if missing.
static func detect_claude_code() -> Dictionary:
	if OS.get_name() != "Windows":
		return {}
	var out := []
	if OS.execute("where", ["claude"], out) != 0 or out.is_empty() or str(out[0]).strip_edges() == "":
		return {}
	var system := OS.get_environment("SystemRoot")
	if system == "":
		system = "C:/Windows"
	return {
		"name": "Claude Code",
		"kind": "app",
		"source": "custom",
		"path": system.replace("\\", "/").path_join("System32/cmd.exe"),
		"args": "/k claude",
		"cwd": OS.get_environment("USERPROFILE").replace("\\", "/"),
	}


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
	if App.is_windows():
		found.append_array(scan_uninstall_entries(read_uninstall_registry()))
		found.append_array(scan_xbox(xbox_roots()))
		found.append_array(scan_game_folders(game_folders()))
	_import_apply.call_deferred(dedupe_found(found), root)


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
		_resolve_xbox_launch(item)
		var e := make_entry(item)
		entries.append(e)
		added += 1
	if added > 0:
		_queue_save()
		changed.emit()
	import_finished.emit(added, found.size())


func _already_imported(item: Dictionary) -> bool:
	if Settings.get_value("removed_imports").has(import_key(item)):
		return true
	var norm := Art.norm_title(str(item.get("name", "")))
	for e in entries:
		# The same game from a second store (or added by hand) stays one tile.
		if norm != "" and e["kind"] == "game" and item.get("kind") == "game" and Art.norm_title(str(e["name"])) == norm:
			return true
		match str(item.get("source", "")):
			"steam":
				if str(e["steam_appid"]) == str(item["steam_appid"]):
					return true
			"epic":
				if str(e["epic_app"]) == str(item["epic_app"]):
					return true
		var p := str(item.get("path", ""))
		if p != "" and str(e["path"]).to_lower() == p.to_lower() and str(e["args"]) == str(item.get("args", "")) and e["source"] == item.get("source", ""):
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
		# Manifests can outlive an uninstall; only keep games still on disk.
		var install := str(data.get("InstallLocation", ""))
		if install != "" and not DirAccess.dir_exists_absolute(install):
			continue
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
	for key in ["HKLM\\SOFTWARE\\WOW6432Node\\GOG.com\\Games", "HKLM\\SOFTWARE\\GOG.com\\Games"]:
		var out := []
		if OS.execute("reg", ["query", key, "/s"], out) == 0 and not out.is_empty():
			for item in parse_gog_registry(str(out[0])):
				if FileAccess.file_exists(str(item["path"])):
					found.append(item)
	return found


static func parse_gog_registry(text: String) -> Array:
	var found: Array = []
	var cur := {}
	for raw in text.split("\n"):
		var line := raw.strip_edges()
		if line.begins_with("HKEY_"):
			_flush_gog(cur, found)
			cur = {}
			continue
		for key in ["gameName", "exe", "workingDir", "launchParam", "dependsOn", "gameID"]:
			if line.begins_with(key + " ") and line.contains("REG_SZ"):
				cur[key] = line.split("REG_SZ", true, 1)[1].strip_edges()
	_flush_gog(cur, found)
	return found


static func _flush_gog(cur: Dictionary, found: Array) -> void:
	# DLCs list the game they belong to in dependsOn.
	if cur.has("gameName") and cur.has("exe") and str(cur.get("dependsOn", "")) == "":
		found.append({
			"name": cur["gameName"],
			"source": "gog",
			"kind": "game",
			"path": str(cur["exe"]).replace("\\", "/"),
			"args": str(cur.get("launchParam", "")),
			"cwd": str(cur.get("workingDir", "")).replace("\\", "/"),
			"gog_id": str(cur.get("gameID", "")),
		})


## One item per game: when two stores report the same title, the earlier one in
## SOURCE_RANK wins.
static func dedupe_found(found: Array) -> Array:
	var best := {}
	var order: Array[String] = []
	for item in found:
		var key := Art.norm_title(str(item.get("name", "")))
		if key == "" or item.get("kind") != "game":
			key = "path:" + str(item.get("path", "")).to_lower() + "|" + str(item.get("args", ""))
		if not best.has(key):
			best[key] = item
			order.append(key)
		elif _rank(item) < _rank(best[key]):
			best[key] = item
	var out: Array = []
	for k in order:
		out.append(best[k])
	return out


static func _rank(item: Dictionary) -> int:
	var i := SOURCE_RANK.find(str(item.get("source", "")))
	return i if i >= 0 else SOURCE_RANK.size()


# --- Installed programs list (EA, Ubisoft, Battle.net, Riot, Amazon) -------------

static func read_uninstall_registry() -> Array:
	var all: Array = []
	for key in UNINSTALL_KEYS:
		var out := []
		if OS.execute("reg", ["query", key, "/s"], out) == 0 and not out.is_empty():
			all.append_array(parse_reg_blocks(str(out[0]), UNINSTALL_VALUES))
	return all


## Splits `reg query /s` output into one dictionary per key, with "_key" set to
## the key's last path segment.
static func parse_reg_blocks(text: String, wanted: Array) -> Array:
	var blocks: Array = []
	var cur := {}
	for raw in text.split("\n"):
		var line := raw.strip_edges()
		if line.begins_with("HKEY_"):
			if not cur.is_empty():
				blocks.append(cur)
			cur = {"_key": line.get_slice("\\", line.get_slice_count("\\") - 1)}
			continue
		if cur.is_empty():
			continue
		for type in ["REG_SZ", "REG_EXPAND_SZ", "REG_DWORD"]:
			var marker := "    %s    " % type
			var at := raw.find(marker)
			if at < 0:
				continue
			var name := raw.substr(0, at).strip_edges()
			if name in wanted:
				cur[name] = raw.substr(at + marker.length()).strip_edges()
			break
	if not cur.is_empty():
		blocks.append(cur)
	return blocks


## Turns installed-program entries from game launchers into library items.
static func scan_uninstall_entries(blocks: Array) -> Array:
	var found: Array = []
	for b in blocks:
		var item := uninstall_item(b)
		if not item.is_empty():
			found.append(item)
	return found


static func uninstall_item(b: Dictionary) -> Dictionary:
	var name := str(b.get("DisplayName", "")).strip_edges()
	if name == "" or b.has("ParentKeyName") or str(b.get("SystemComponent", "")) == "0x1" or b.has("ReleaseType"):
		return {}
	var lower := name.to_lower()
	for w in STORE_SKIP_NAMES:
		if lower == w or lower.begins_with(w + " "):
			return {}
	var key := str(b.get("_key", ""))
	var uninstall := str(b.get("UninstallString", ""))
	var u := uninstall.to_lower()
	var icon_exe := _exe_from(str(b.get("DisplayIcon", "")))
	var item := {"name": name, "kind": "game"}
	if u.contains("riotclientservices.exe") and u.contains("--uninstall-product="):
		var product := _flag(uninstall, "--uninstall-product=")
		if product == "" or product == "riot_client":
			return {}
		item["source"] = "riot"
		item["path"] = _exe_from(uninstall)
		item["args"] = "--launch-product=%s --launch-patchline=%s" % [product, _flag(uninstall, "--uninstall-patchline=", "live")]
	elif key.begins_with("Uplay Install "):
		item["source"] = "ubisoft"
		item["path"] = "uplay://launch/%s/0" % key.trim_prefix("Uplay Install ").strip_edges()
	elif u.contains("amazon game remover") and u.contains(" -p "):
		item["source"] = "amazon"
		item["path"] = "amazon-games://play/" + uninstall.get_slice(" -p ", 1).strip_edges().get_slice(" ", 0)
	elif u.contains("battle.net") and u.contains("--uid="):
		if icon_exe == "" or _flag(uninstall, "--uid=").begins_with("battle.net"):
			return {}
		item["source"] = "battlenet"
		item["path"] = icon_exe
	elif u.contains("eainstaller") or u.contains("touchup.exe") or u.contains("ea desktop"):
		if icon_exe == "":
			return {}
		item["source"] = "ea"
		item["path"] = icon_exe
	elif key.begins_with("Steam App "):
		return {}
	elif _looks_like_game(b):
		var exe := icon_exe if icon_exe != "" and not Catalog.is_clutter("x", icon_exe) else ""
		if exe == "":
			exe = _guess_exe(str(b.get("InstallLocation", "")).replace("\\", "/"))
		if exe == "":
			return {}
		item["source"] = "custom"
		item["path"] = exe
	else:
		return {}
	return item


## A standalone install (no launcher): a known game publisher, or a program
## living in a "Games" folder.
static func _looks_like_game(b: Dictionary) -> bool:
	var name := " " + str(b.get("DisplayName", "")).to_lower() + " "
	for w in NOT_GAME_WORDS:
		if name.contains(w):
			return false
	var publisher := str(b.get("Publisher", "")).to_lower()
	for p in GAME_PUBLISHERS:
		if publisher.begins_with(p):
			return true
	var where := (str(b.get("InstallLocation", "")) + "|" + str(b.get("DisplayIcon", ""))).replace("\\", "/").to_lower()
	return where.contains("/games/") and not where.contains("/windowsapps/")


## The main executable in an install folder: the biggest .exe that isn't a helper.
static func _guess_exe(dir: String) -> String:
	if dir == "" or not DirAccess.dir_exists_absolute(dir):
		return ""
	var best := ""
	var best_size := 0
	for f in DirAccess.get_files_at(dir):
		if not f.to_lower().ends_with(".exe") or Catalog.is_clutter(f.get_basename(), f):
			continue
		var fa := FileAccess.open(dir.path_join(f), FileAccess.READ)
		if fa == null:
			continue
		var size := fa.get_length()
		fa.close()
		if size > best_size:
			best_size = size
			best = dir.path_join(f)
	return best


## The executable in a quoted or unquoted command line / icon path ("x.exe,0").
static func _exe_from(text: String) -> String:
	var s := text.strip_edges()
	if s.begins_with("\""):
		s = s.substr(1).get_slice("\"", 0)
	else:
		var at := s.to_lower().find(".exe")
		if at < 0:
			return ""
		s = s.substr(0, at + 4)
	s = s.get_slice(",", 0).strip_edges().replace("\\", "/")
	return s if s.to_lower().ends_with(".exe") else ""


static func _flag(cmd: String, flag: String, fallback: String = "") -> String:
	var at := cmd.find(flag)
	if at < 0:
		return fallback
	var v := cmd.substr(at + flag.length()).strip_edges()
	if v.begins_with("\""):
		return v.substr(1).get_slice("\"", 0)
	return v.get_slice(" ", 0)


# --- Xbox app / Game Pass ----------------------------------------------------------

static func xbox_roots() -> PackedStringArray:
	var roots := PackedStringArray()
	for i in range(67, 91):
		var dir := "%s:/XboxGames" % char(i)
		if DirAccess.dir_exists_absolute(dir):
			roots.append(dir)
	return roots


## Xbox app games live in <drive>:/XboxGames/<game>/Content with a
## MicrosoftGame.config describing the title and its executable.
static func scan_xbox(roots: PackedStringArray) -> Array:
	var found: Array = []
	for root in roots:
		for game in DirAccess.get_directories_at(root):
			var content := root.path_join(game).path_join("Content")
			var config := content.path_join("MicrosoftGame.config")
			if not FileAccess.file_exists(config):
				continue
			var item := xbox_item(FileAccess.get_file_as_string(config), content)
			if not item.is_empty():
				found.append(item)
	return found


static func xbox_item(xml: String, content: String) -> Dictionary:
	var identity := _xml_attr(xml, "Identity", "Name")
	var exe := _xml_attr(xml, "Executable", "Name")
	var name := _xml_attr(xml, "ShellVisuals", "DefaultDisplayName")
	if name == "" or name.begins_with("ms-resource:"):
		name = Fmt.pretty_name(content.get_base_dir())
	if exe == "" and identity == "":
		return {}
	return {
		"name": name,
		"source": "xbox",
		"kind": "game",
		"path": content.path_join(exe.replace("\\", "/")) if exe != "" else "",
		"xbox_package": identity,
	}


static func _xml_attr(xml: String, tag: String, attr: String) -> String:
	var re := RegEx.create_from_string("<%s\\b[^>]*\\b%s=\"([^\"]*)\"" % [tag, attr])
	var m := re.search(xml)
	return m.get_string(1).strip_edges() if m else ""


## Store-packaged games must start through their app id; the exe alone is locked.
func _resolve_xbox_launch(item: Dictionary) -> void:
	var pkg := str(item.get("xbox_package", "")).to_lower()
	if pkg == "":
		return
	for a in Catalog.apps:
		var id := str(a["id"])
		if id.to_lower().begins_with(pkg + "_") and id.contains("!"):
			item["path"] = "shell:AppsFolder\\" + id
			return



static func import_key(item: Dictionary) -> String:
	return ("%s|%s|%s|%s" % [item.get("source", ""), item.get("steam_appid", ""), item.get("path", ""), item.get("args", "")]).to_lower()


# --- Your own games (Games folders, Godot exports) ------------------------------

## Folders worth looking in: any drive's Games folder and ~/Games hold games;
## Desktop, Documents and Downloads only count for Godot exports.
static func game_folders() -> Array:
	var out: Array = []
	for i in range(67, 91):
		var dir := "%s:/Games" % char(i)
		if DirAccess.dir_exists_absolute(dir):
			out.append({"path": dir, "any": true})
	var home := OS.get_environment("USERPROFILE").replace("\\", "/")
	if home != "":
		if DirAccess.dir_exists_absolute(home.path_join("Games")):
			out.append({"path": home.path_join("Games"), "any": true})
		for sub in ["Desktop", "Documents", "Downloads", "OneDrive/Desktop", "OneDrive/Documents"]:
			if DirAccess.dir_exists_absolute(home.path_join(sub)):
				out.append({"path": home.path_join(sub), "any": false})
	return out


static func scan_game_folders(folders: Array) -> Array:
	var found: Array = []
	for f in folders:
		var root := str(f["path"])
		var any := bool(f["any"])
		# Loose exes right in the folder.
		for file in DirAccess.get_files_at(root):
			var p := root.path_join(file)
			if file.to_lower().ends_with(".exe") and (is_godot_exe(p) or (any and not Catalog.is_clutter(file.get_basename(), file))):
				found.append(_own_game(Fmt.pretty_name(p), p))
		# One folder per game.
		for sub in DirAccess.get_directories_at(root):
			var dir := root.path_join(sub)
			var exe := _godot_exe_in(dir)
			if exe == "" and any:
				exe = _guess_exe(dir)
			if exe != "":
				found.append(_own_game(sub, exe))
	return found


static func _own_game(name: String, exe: String) -> Dictionary:
	return {"name": name, "source": "custom", "kind": "game", "path": exe, "auto": true}


static func _godot_exe_in(dir: String) -> String:
	for file in DirAccess.get_files_at(dir):
		if file.to_lower().ends_with(".exe") and is_godot_exe(dir.path_join(file)):
			return dir.path_join(file)
	return ""


## A Godot export: the game data is embedded (the exe ends with "GDPC") or sits
## next to it as <name>.pck.
static func is_godot_exe(path: String) -> bool:
	if path.get_file().to_lower().begins_with("oazylauncher"):
		return false
	if FileAccess.file_exists(path.get_basename() + ".pck"):
		return true
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null or f.get_length() < 512:
		return false
	f.seek_end(-4)
	var godot := f.get_buffer(4).get_string_from_ascii() == "GDPC"
	if not godot:
		# Signed exports carry the data in a PE section named "pck" instead.
		f.seek(0x3C)
		var pe := f.get_32()
		if pe > 0 and pe < 4096:
			f.seek(pe + 6)
			var sections := f.get_16()
			f.seek(pe + 20)
			var opt := f.get_16()
			var table := pe + 24 + opt
			for i in mini(sections, 32):
				f.seek(table + i * 40)
				if f.get_buffer(8).get_string_from_ascii() == "pck":
					godot = true
					break
	f.close()
	return godot
