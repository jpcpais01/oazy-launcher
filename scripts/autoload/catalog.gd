extends Node
## Everything Oazy can open, behind one "ref" string:
##   oazy:<app>  Oazy's own apps (Library, Settings)
##   app:<id>    an installed Windows app (Start menu's All apps; id = AppsFolder id)
##   lib:<id>    a game or app from the library
##   win:<exe>   a running program that matches nothing above
## Also owns taskbar pins, recents, search, window matching and app icons.

signal apps_changed
signal pins_changed
signal icon_ready(key: String)

const CACHE := "user://apps.json"
const ICON_DIR := "user://icons"
const ICON_PX := 128
const OAZY_APPS := {
	"oazy:library": {"name": "Library", "glyph": "grid", "desc": "Your games and apps"},
	"oazy:settings": {"name": "Settings", "glyph": "settings", "desc": "Make Oazy yours"},
}
## Start menu clutter that ships next to real apps.
const SKIP_WORDS := ["uninstall", "readme", "read me", "help", "documentation", "release notes", "website", "license", "manual", "changelog", "what's new", "support", "faq", "eula", "recovery", "debug"]
## First-run taskbar pins, in order, matched against installed app names.
const DEFAULT_PINS := ["google chrome", "file explorer", "claude", "steam", "discord", "spotify", "visual studio code", "terminal"]
const SHELLS := ["cmd.exe", "powershell.exe", "pwsh.exe", "wt.exe", "windowsterminal.exe", "conhost.exe", "openconsole.exe"]
const MAX_RECENT := 10

var apps: Array[Dictionary] = []
var apps_loaded := false

var _icons := {}
var _colors := {}
var _icon_pending := {}
var _by_id := {}


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ICON_DIR)
	if not App.smoke_test:
		_load_cache()
	Host.status_changed.connect(_on_host_status)


# --- Installed apps -------------------------------------------------------------------

func _load_cache() -> void:
	if not FileAccess.file_exists(CACHE):
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(CACHE))
	if data is Array:
		_set_apps(data, false)


func refresh_apps() -> void:
	Host.list_apps(func(d: Dictionary) -> void:
		if d.get("ok", false) and d.get("apps") is Array:
			_set_apps(d["apps"], not App.smoke_test)
	)


## Used by screenshot runs and tests.
func set_mock_apps(list: Array) -> void:
	_set_apps(list, false)


func _set_apps(raw: Array, save: bool) -> void:
	var list: Array[Dictionary] = []
	var seen := {}
	for a in raw:
		if not a is Dictionary:
			continue
		var name := str(a.get("name", "")).strip_edges()
		var id := str(a.get("id", ""))
		if name == "" or id == "" or seen.has(id.to_lower()) or is_clutter(name, id):
			continue
		seen[id.to_lower()] = true
		list.append({"name": name, "id": id})
	list.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
		return str(x["name"]).naturalnocasecmp_to(str(y["name"])) < 0
	)
	apps = list
	_by_id.clear()
	for a in apps:
		_by_id[str(a["id"]).to_lower()] = a
	apps_loaded = true
	if save:
		var f := FileAccess.open(CACHE, FileAccess.WRITE)
		if f:
			f.store_string(JSON.stringify(apps))
			f.close()
	_ensure_default_pins()
	apps_changed.emit()


static func is_clutter(name: String, id: String) -> bool:
	var lower := " " + name.to_lower() + " "
	for w in SKIP_WORDS:
		if lower.contains(w):
			return true
	var l := id.to_lower()
	return l.begins_with("http") or l.ends_with(".url") or l.ends_with(".txt") or l.ends_with(".pdf") or l.ends_with(".chm") or l.ends_with(".html")


func find_app(id: String) -> Dictionary:
	return _by_id.get(id.to_lower(), {})


func find_app_by_name(name: String) -> Dictionary:
	var n := name.to_lower()
	for a in apps:
		if str(a["name"]).to_lower() == n:
			return a
	return {}


# --- Items --------------------------------------------------------------------------------

## Describes a ref: {ref, name, kind (oazy|app|game|libapp|window), glyph,
## icon_key, entry_id, sub}.
func item(ref: String) -> Dictionary:
	var it := {"ref": ref, "name": "", "kind": "app", "glyph": "", "icon_key": "", "entry_id": "", "sub": ""}
	if OAZY_APPS.has(ref):
		var o: Dictionary = OAZY_APPS[ref]
		it["name"] = o["name"]
		it["kind"] = "oazy"
		it["glyph"] = o["glyph"]
		it["sub"] = o["desc"]
	elif ref.begins_with("app:"):
		var id := ref.substr(4)
		var a := find_app(id)
		it["name"] = str(a.get("name", id.get_file().get_basename()))
		it["icon_key"] = "shell:AppsFolder\\" + id
		it["sub"] = "App"
	elif ref.begins_with("lib:"):
		var e := Library.get_entry(ref.substr(4))
		it["entry_id"] = ref.substr(4)
		it["name"] = str(e.get("name", "Missing"))
		it["kind"] = "game" if e.get("kind", "game") == "game" else "libapp"
		it["sub"] = Library.source_label(e) if not e.is_empty() else ""
		var path := str(e.get("path", ""))
		if it["kind"] == "libapp" and path != "" and not path.contains("://") and path.get_file().to_lower() not in SHELLS:
			it["icon_key"] = path.replace("/", "\\")
	elif ref.begins_with("win:"):
		it["kind"] = "window"
		it["icon_key"] = ref.substr(4)
		it["name"] = Fmt.pretty_name(ref.substr(4))
	return it


func launch(ref: String) -> bool:
	if OAZY_APPS.has(ref):
		App.open_page.emit(StringName(ref.substr(5)))
		return true
	if ref.begins_with("lib:"):
		App.launch_requested.emit(ref.substr(4))
		return true
	if ref.begins_with("app:"):
		note_recent(ref)
		if not App.is_windows():
			App.toast("Opening apps works on Windows")
			return false
		return OS.create_process("explorer.exe", ["shell:AppsFolder\\" + ref.substr(4)]) > 0
	if ref.begins_with("win:"):
		var exe := ref.substr(4)
		if FileAccess.file_exists(exe):
			return OS.create_process(exe, []) > 0
	return false


func note_recent(ref: String) -> void:
	var list: Array = Settings.get_value("recent_apps").duplicate()
	list.erase(ref)
	list.push_front(ref)
	Settings.set_value("recent_apps", list.slice(0, MAX_RECENT))


func recent_apps() -> Array[String]:
	var out: Array[String] = []
	for r in Settings.get_value("recent_apps"):
		var ref := str(r)
		if ref.begins_with("app:") and not apps_loaded:
			out.append(ref)
		elif not ref.begins_with("app:") or not find_app(ref.substr(4)).is_empty():
			out.append(ref)
	return out


## Every launchable thing for Start's "All apps": installed apps, library apps
## and Oazy's own, by name.
func all_items() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for ref in OAZY_APPS.keys():
		list.append(item(ref))
	for a in apps:
		list.append(item("app:" + str(a["id"])))
	for e in Library.entries:
		if e["kind"] == "app":
			list.append(item("lib:" + str(e["id"])))
	list.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
		return str(x["name"]).naturalnocasecmp_to(str(y["name"])) < 0
	)
	return list


## Ranked matches across apps, games and Oazy apps.
func search(text: String, limit: int = 24) -> Array[Dictionary]:
	var needle := text.strip_edges().to_lower()
	var scored: Array = []
	if needle == "":
		return []
	var candidates: Array[Dictionary] = all_items()
	for e in Library.entries:
		if e["kind"] == "game":
			candidates.append(item("lib:" + str(e["id"])))
	for it in candidates:
		var s := match_score(str(it["name"]), needle)
		if s > 0:
			scored.append([s, it])
	scored.sort_custom(func(a: Array, b: Array) -> bool:
		if a[0] != b[0]:
			return a[0] > b[0]
		return str(a[1]["name"]).naturalnocasecmp_to(str(b[1]["name"])) < 0
	)
	var out: Array[Dictionary] = []
	for s in scored.slice(0, limit):
		out.append(s[1])
	return out


static func match_score(name: String, needle: String) -> int:
	var n := name.to_lower()
	if n == needle:
		return 100
	if n.begins_with(needle):
		return 80
	for w in n.split(" ", false):
		if w.begins_with(needle):
			return 60
	# Initials: "vsc" -> Visual Studio Code.
	var initials := ""
	for w in n.split(" ", false):
		initials += w[0]
	if needle.length() >= 2 and initials.begins_with(needle):
		return 50
	if n.contains(needle):
		return 30
	return 0


# --- Windows -> items -------------------------------------------------------------------

## Which item a running window belongs to (so it groups with its pin).
func ref_for_window(w: Dictionary) -> String:
	var aumid := str(w.get("aumid", ""))
	if aumid != "" and not find_app(aumid).is_empty():
		return "app:" + str(find_app(aumid)["id"])
	var exe := str(w.get("exe", "")).replace("\\", "/")
	var file := exe.get_file().to_lower()
	var title := str(w.get("title", "")).to_lower()
	for e in Library.entries:
		var path := str(e["path"]).replace("\\", "/").to_lower()
		if path == "" or path.contains("://"):
			continue
		if path.get_file() in SHELLS:
			if file in SHELLS and title.contains(str(e["name"]).to_lower().get_slice(" ", 0)):
				return "lib:" + str(e["id"])
			continue
		if path == exe.to_lower() or (e["source"] != "custom" and exe.to_lower().begins_with(path.trim_suffix("/") + "/")):
			return "lib:" + str(e["id"])
		if path.get_file() == file and file.ends_with(".exe"):
			return "lib:" + str(e["id"])
	if file != "" and file != "applicationframehost.exe":
		for a in apps:
			var id := str(a["id"]).replace("\\", "/").to_lower()
			if id.get_file() == file:
				return "app:" + str(a["id"])
	var name := str(w.get("name", ""))
	if name != "":
		var byname := find_app_by_name(name)
		if not byname.is_empty():
			return "app:" + str(byname["id"])
	if aumid != "":
		return "win:" + "shell:AppsFolder\\" + aumid
	return "win:" + (exe if exe != "" else "hwnd:%d" % int(w.get("hwnd", 0)))


## A friendly name for a window group that matched nothing.
func window_group_name(w: Dictionary) -> String:
	var name := str(w.get("name", ""))
	if name != "":
		return name
	var title := str(w.get("title", ""))
	if title.contains(" - "):
		return title.get_slice(" - ", title.get_slice_count(" - ") - 1)
	return title if title != "" else Fmt.pretty_name(str(w.get("exe", "App")))


# --- Pins -----------------------------------------------------------------------------------

func pins() -> Array[String]:
	var out: Array[String] = []
	for p in Settings.get_value("pins"):
		var ref := str(p)
		if ref.begins_with("lib:") and not Library.has_entry(ref.substr(4)):
			continue
		out.append(ref)
	return out


func is_pinned(ref: String) -> bool:
	return pins().has(ref)


func set_pinned(ref: String, on: bool) -> void:
	var list: Array = Settings.get_value("pins").duplicate()
	if on and not list.has(ref):
		list.append(ref)
	elif not on:
		list.erase(ref)
	Settings.set_value("pins", list)
	pins_changed.emit()


func move_pin(ref: String, to_index: int) -> void:
	var list: Array = Settings.get_value("pins").duplicate()
	if not list.has(ref):
		return
	list.erase(ref)
	list.insert(clampi(to_index, 0, list.size()), ref)
	Settings.set_value("pins", list)
	pins_changed.emit()


## Back to the suggested pins.
func reset_pins() -> void:
	Settings.set_value("pins_initialized", false)
	_ensure_default_pins()


func _ensure_default_pins() -> void:
	if Settings.get_value("pins_initialized"):
		return
	var list: Array = ["oazy:library"]
	for want in DEFAULT_PINS:
		for a in apps:
			if str(a["name"]).to_lower() == want:
				list.append("app:" + str(a["id"]))
				break
	for e in Library.entries:
		if str(e["name"]) == "Claude Code":
			list.append("lib:" + str(e["id"]))
	Settings.set_value("pins", list)
	Settings.set_value("pins_initialized", true)
	pins_changed.emit()


# --- Icons ----------------------------------------------------------------------------------

## The icon for a Host icon key ("shell:AppsFolder\\id", an exe path or
## "hwnd:<n>"), or null while it loads / if there is none.
func icon(key: String) -> Texture2D:
	if key == "":
		return null
	if _icons.has(key):
		return _icons[key]
	if _icon_pending.has(key):
		return null
	_icon_pending[key] = true
	var file := ICON_DIR.path_join(key.md5_text() + ".png")
	if FileAccess.file_exists(file):
		WorkerThreadPool.add_task(_load_icon.bind(key, file), false, "Load icon")
	elif Host.available:
		Host.render_icon(key, ICON_PX, file, func(d: Dictionary) -> void:
			if d.get("ok", false):
				WorkerThreadPool.add_task(_load_icon.bind(key, file), false, "Load icon")
			else:
				_icon_done.call_deferred(key, null, Color(0, 0, 0, 0))
		)
	else:
		_icon_pending.erase(key)
	return null


## The icon's dominant colour (for hover glows), transparent if unknown.
func icon_color(key: String) -> Color:
	return _colors.get(key, Color(0, 0, 0, 0))


func _load_icon(key: String, file: String) -> void:
	var img := Image.load_from_file(ProjectSettings.globalize_path(file))
	if img == null or img.is_empty():
		_icon_done.call_deferred(key, null, Color(0, 0, 0, 0))
		return
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	var accent := Art.extract_accent(img)
	img.generate_mipmaps()
	_icon_done.call_deferred(key, img, accent)


func _icon_done(key: String, img: Image, accent: Color) -> void:
	_icon_pending.erase(key)
	_icons[key] = ImageTexture.create_from_image(img) if img != null else null
	_colors[key] = accent
	icon_ready.emit(key)


func _on_host_status(ok: bool) -> void:
	if not ok:
		return
	# Retry icons that couldn't load before the companion was up.
	for k in _icons.keys():
		if _icons[k] == null:
			_icons.erase(k)
	refresh_apps()
