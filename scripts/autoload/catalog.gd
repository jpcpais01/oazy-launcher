extends Node
## Everything Oazy can open, behind one "ref" string:
##   oazy:<app>  Oazy's own apps (Library, Settings, Cleaner)
##   app:<id>    an installed Windows app (Start menu's All apps; id = AppsFolder id)
##   lib:<id>    a game or app from the library
##   win:<exe>   a running program that matches nothing above
## Also owns taskbar pins, recents, search, window matching and app icons.

signal apps_changed
signal pins_changed
signal favorites_changed
signal icon_ready(key: String)

const CACHE := "user://apps.json"
const ICON_DIR := "user://icons"
const ICON_PX := 128
const OAZY_APPS := {
	"oazy:library": {"name": "Library", "glyph": "grid", "desc": "Your games and apps"},
	"oazy:settings": {"name": "Settings", "glyph": "settings", "desc": "Make Oazy yours"},
	"oazy:browser": {"name": "Browser", "glyph": "browser", "desc": "Oazy's web browser"},
	"oazy:terminal": {"name": "Terminal", "glyph": "terminal", "desc": "PowerShell, WSL and Claude Code in Oazy's glass"},
	"oazy:flow": {"name": "Flow", "glyph": "sparkles", "desc": "Make images and videos with Google Flow, in Oazy's look"},
	"oazy:files": {"name": "Files", "glyph": "folder", "desc": "Your folders in Oazy's glass"},
	"oazy:cleaner": {"name": "Cleaner", "glyph": "wand", "desc": "Keep Windows lean, fast and private"},
}
## Start menu clutter that ships next to real apps.
const SKIP_WORDS := ["uninstall", "uninstaller", "readme", "read me", "help", "documentation", "release notes", "website", "license", "manual", "changelog", "what's new", "support", "faq", "eula", "recovery", "debug", "setup", "installer", "updater", "crash reporter", "bug reporter", "repair", "safe mode", "migration assistant"]
## Executables that are never what you meant to open.
const SKIP_EXES := ["unins000.exe", "uninstall.exe", "uninst.exe", "setup.exe", "updater.exe", "update.exe", "crashreporter.exe", "crashpad_handler.exe", "vc_redist.x64.exe", "vc_redist.x86.exe", "dxsetup.exe"]
## First-run taskbar pins, in order, matched against installed app names.
const DEFAULT_PINS := ["google chrome", "file explorer", "claude", "steam", "discord", "spotify", "visual studio code"]
const SHELLS := ["cmd.exe", "powershell.exe", "pwsh.exe", "wt.exe", "windowsterminal.exe", "conhost.exe", "openconsole.exe"]
const MAX_RECENT := 10

var apps: Array[Dictionary] = []
var apps_loaded := false

var _icons := {}
var _colors := {}
var _icon_pending := {}
var _by_id := {}
## all_items() and search's candidates, kept until apps or the library change
## (search runs on every key press).
var _items: Array[Dictionary] = []
var _candidates: Array = []
var _items_dirty := true


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ICON_DIR)
	if not App.smoke_test:
		_load_cache()
	Host.status_changed.connect(_on_host_status)
	apps_changed.connect(_forget_items)
	Library.changed.connect(_forget_items)
	Library.entry_changed.connect(func(_id: String) -> void: _forget_items())


func _forget_items() -> void:
	_items_dirty = true


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
		# The same app is often in Start twice (per-user and all-users shortcuts).
		var name_key := "name:" + name.to_lower()
		if name == "" or id == "" or seen.has(id.to_lower()) or seen.has(name_key) or is_clutter(name, id):
			continue
		seen[id.to_lower()] = true
		seen[name_key] = true
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
	# Whole words only, so "Debugger" or "Helpdesk Pro" stay.
	var lower := " "
	for c in name.to_lower():
		lower += c if (c >= "a" and c <= "z") or (c >= "0" and c <= "9") or c == "'" else " "
	lower += " "
	for w in SKIP_WORDS:
		if lower.contains(" " + w + " "):
			return true
	var l := id.to_lower()
	if l.replace("\\", "/").get_file() in SKIP_EXES:
		return true
	return l.begins_with("http") or l.ends_with(".url") or l.ends_with(".txt") or l.ends_with(".pdf") or l.ends_with(".chm") or l.ends_with(".html")


func find_app(id: String) -> Dictionary:
	return _by_id.get(id.to_lower(), {})


func _file_explorer() -> Dictionary:
	var fe := find_app("Microsoft.Windows.Explorer")
	return fe if not fe.is_empty() else find_app_by_name("File Explorer")


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


## Oazy's apps that run as their own windows rather than inside the shell.
static func is_own_window_app(ref: String) -> bool:
	return ref == Browser.REF or ref == Terminal.REF or ref == Files.REF or Browser.APPS.has(ref)


func launch(ref: String) -> bool:
	if ref == Browser.REF:
		note_recent(ref)
		return Browser.open()
	if ref == Terminal.REF:
		note_recent(ref)
		return Terminal.open()
	if Browser.APPS.has(ref):
		note_recent(ref)
		return Browser.open_app(ref)
	if ref == Files.REF:
		note_recent(ref)
		return Files.open()
	if OAZY_APPS.has(ref):
		App.open_page.emit(StringName(ref.substr(5)))
		return true
	if ref.begins_with("lib:"):
		App.launch_requested.emit(ref.substr(4))
		return true
	if ref.begins_with("app:"):
		note_recent(ref)
		return launch_app(ref.substr(4))
	if ref.begins_with("win:"):
		var exe := ref.substr(4)
		if FileAccess.file_exists(exe):
			return OS.create_process(exe, []) > 0
	return false


## Opens an installed app by its Start id (also how library apps added from
## Start open).
func launch_app(id: String) -> bool:
	if not App.is_windows():
		App.toast("Opening apps works on Windows")
		return false
	var run_app := func() -> bool: return OS.create_process("explorer.exe", ["shell:AppsFolder\\" + id]) > 0
	# Terminal, Command Prompt and PowerShell open in Oazy Terminal.
	var profile := Terminal.profile_for(item("app:" + id)) if Terminal.enabled() else "-"
	if profile != "-":
		return Terminal.open({"profile": profile}, run_app)
	# File Explorer opens Oazy Files.
	if Files.enabled() and Files.is_explorer(item("app:" + id)):
		return Files.open({}, run_app)
	return run_app.call()


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
	_build_items()
	return _items.duplicate()


func _build_items() -> void:
	if not _items_dirty:
		return
	_items_dirty = false
	var list: Array[Dictionary] = []
	for ref in OAZY_APPS.keys():
		list.append(item(ref))
	var games := {}
	for e in Library.entries:
		if e["kind"] == "game":
			games[Art.norm_title(str(e["name"]))] = true
	var in_library := library_app_ids()
	for a in apps:
		# A game's Start shortcut would duplicate its library tile, and an app
		# in the library shows as its library entry.
		if games.has(Art.norm_title(str(a["name"]))) or in_library.has(str(a["id"]).to_lower()):
			continue
		list.append(item("app:" + str(a["id"])))
	for e in Library.entries:
		if e["kind"] == "app":
			list.append(item("lib:" + str(e["id"])))
	list.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
		return str(x["name"]).naturalnocasecmp_to(str(y["name"])) < 0
	)
	_items = list
	_candidates.clear()
	for it in list:
		_candidates.append(it)
	for e in Library.entries:
		if e["kind"] == "game":
			_candidates.append(item("lib:" + str(e["id"])))


## Ranked matches across apps, games and Oazy apps.
func search(text: String, limit: int = 24) -> Array[Dictionary]:
	var needle := text.strip_edges().to_lower()
	var scored: Array = []
	if needle == "":
		return []
	_build_items()
	var candidates := _candidates
	# What you open often floats up among equally good matches.
	var recent: Array = Settings.get_value("recent_apps")
	for it in candidates:
		var s := match_score(str(it["name"]), needle)
		if s > 0:
			var ref := str(it["ref"])
			var at := recent.find(ref)
			if at >= 0:
				s += MAX_RECENT - at
			elif ref.begins_with("lib:"):
				var played := int(Library.get_entry(ref.substr(4)).get("last_played", 0))
				if played > 0 and Time.get_unix_time_from_system() - played < 14 * 86400:
					s += 6
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
	var ref := _window_ref(w)
	if ref.begins_with("app:"):
		var entry := library_entry_for_app(ref.substr(4))
		if entry != "":
			return "lib:" + entry
	return ref


func _window_ref(w: Dictionary) -> String:
	if Browser.owns_window(w):
		var app := Browser.app_for_window(w)
		return app if app != "" else Browser.REF
	if Files.owns_window(w):
		# Groups with the File Explorer pin it stands in for.
		var fe := _file_explorer()
		return "app:" + str(fe["id"]) if not fe.is_empty() else Files.REF
	if Terminal.owns_window(w):
		# A Claude Code tab groups with its pin; any other tab is the Terminal's.
		var t := str(w.get("title", "")).to_lower()
		for e in Library.entries:
			if Terminal.runs_shell(str(e["path"])) and t.begins_with(str(e["name"]).to_lower() + " - "):
				return "lib:" + str(e["id"])
		return Terminal.REF
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
	var packaged := _app_for_package(exe)
	if packaged != "":
		return packaged
	if file == "explorer.exe":
		# Folder windows rarely carry an app id; they're File Explorer's.
		var fe := _file_explorer()
		if not fe.is_empty():
			return "app:" + str(fe["id"])
	# "WhatsApp.Root.exe" is WhatsApp: the first word of the file name.
	var stem := file.get_basename().get_slice(".", 0)
	if stem.length() >= 4:
		var bystem := find_app_by_name(stem)
		if not bystem.is_empty():
			return "app:" + str(bystem["id"])
	if aumid != "":
		return "win:" + "shell:AppsFolder\\" + aumid
	return "win:" + (exe if exe != "" else "hwnd:%d" % int(w.get("hwnd", 0)))


## A Store app's window: its exe lives in WindowsApps/<Name>_<ver>_<arch>__<publisher>/,
## and its Start id is <Name>_<publisher>!<App>. "" when it isn't one.
func _app_for_package(exe: String) -> String:
	var lower := exe.to_lower()
	var at := lower.find("/windowsapps/")
	if at < 0:
		return ""
	var folder := lower.substr(at + 13).get_slice("/", 0)
	if not folder.contains("__"):
		return ""
	var family := folder.get_slice("_", 0) + "_" + folder.get_slice("__", 1)
	for a in apps:
		if str(a["id"]).to_lower().begins_with(family + "!"):
			return "app:" + str(a["id"])
	return ""


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
		# Oazy Browser joins the taskbar once, next to Library, for people who
		# set up their pins before it existed.
		if not Settings.get_value("browser_pinned") and App.is_windows():
			var list: Array = Settings.get_value("pins").duplicate()
			if not list.has(Browser.REF):
				list.insert(mini(1, list.size()), Browser.REF)
				Settings.set_value("pins", list)
				pins_changed.emit()
			Settings.set_value("browser_pinned", true)
		if not Settings.get_value("terminal_pinned") and App.is_windows():
			_pin_terminal()
		if not Settings.get_value("flow_pinned") and App.is_windows():
			_pin_flow()
		return
	var list: Array = ["oazy:library", Browser.REF]
	Settings.set_value("browser_pinned", true)
	Settings.set_value("terminal_pinned", true)
	Settings.set_value("flow_pinned", true)
	for want in DEFAULT_PINS:
		for a in apps:
			if str(a["name"]).to_lower() == want:
				list.append("app:" + str(a["id"]))
				break
	list.append(Terminal.REF)
	if App.is_windows():
		list.append("oazy:flow")
	for e in Library.entries:
		if str(e["name"]) == "Claude Code":
			list.append("lib:" + str(e["id"]))
	Settings.set_value("pins", list)
	Settings.set_value("pins_initialized", true)
	pins_changed.emit()


## Oazy Terminal takes over the Windows Terminal pin once (or joins next to
## the Browser), for people who set up their pins before it existed.
func _pin_terminal() -> void:
	Settings.set_value("terminal_pinned", true)
	var list: Array = Settings.get_value("pins").duplicate()
	if list.has(Terminal.REF):
		return
	var at := -1
	for i in list.size():
		if str(list[i]).begins_with("app:") and Terminal.profile_for(item(str(list[i]))) == "":
			at = i
			break
	if at >= 0:
		list[at] = Terminal.REF
	else:
		list.insert(mini(list.find(Browser.REF) + 1, list.size()), Terminal.REF)
	Settings.set_value("pins", list)
	pins_changed.emit()


## Flow joins the taskbar once, after the Terminal, for people who set up
## their pins before it existed.
func _pin_flow() -> void:
	Settings.set_value("flow_pinned", true)
	var list: Array = Settings.get_value("pins").duplicate()
	if list.has("oazy:flow"):
		return
	var after := list.find(Terminal.REF)
	if after < 0:
		after = list.find(Browser.REF)
	list.insert(clampi(after + 1, 0, list.size()) if after >= 0 else list.size(), "oazy:flow")
	Settings.set_value("pins", list)
	pins_changed.emit()


# --- Library apps -------------------------------------------------------------------------
# Any installed app can join the Library, where it gets a cover and sits with
# your games. It then shows as that entry everywhere (Start, search, the
# taskbar), so its pins, favourites and recents move over with it, and back
# again if it leaves.

## Start ids of the apps already in the library, lowercase.
func library_app_ids() -> Dictionary:
	var out := {}
	for e in Library.entries:
		var id := str(e.get("app_id", ""))
		if id != "":
			out[id.to_lower()] = str(e["id"])
	return out


## The library entry an installed app became, or "".
func library_entry_for_app(id: String) -> String:
	var l := id.to_lower()
	for e in Library.entries:
		if str(e.get("app_id", "")).to_lower() == l:
			return str(e["id"])
	return ""


func can_add_to_library(ref: String) -> bool:
	if ref.begins_with("app:"):
		return library_entry_for_app(ref.substr(4)) == ""
	if ref.begins_with("win:"):
		var exe := ref.substr(4)
		return exe.to_lower().ends_with(".exe") and FileAccess.file_exists(exe)
	return false


## Library fields for an installed app.
func app_entry_fields(id: String) -> Dictionary:
	return {
		"name": str(find_app(id).get("name", id.get_file().get_basename())),
		"kind": "app",
		"source": "custom",
		"path": "shell:AppsFolder\\" + id,
		"app_id": id,
	}


## Adds an installed app (or a running program) to the library and returns
## the entry id ("" if it can't be added).
func add_to_library(ref: String) -> String:
	var fields := {}
	if ref.begins_with("app:"):
		var have := library_entry_for_app(ref.substr(4))
		if have != "":
			return have
		fields = app_entry_fields(ref.substr(4))
	elif can_add_to_library(ref):
		fields = Library.infer_from_path(ref.substr(4).replace("\\", "/"))
	else:
		return ""
	var id := Library.add_entry(fields)
	_move_ref(ref, "lib:" + id)
	return id


## Call before an entry leaves the library: an installed app takes its pins
## and favourites back, anything else just loses them.
func forget_entry(id: String) -> void:
	var app_id := str(Library.get_entry(id).get("app_id", ""))
	if app_id != "" and not find_app(app_id).is_empty():
		_move_ref("lib:" + id, "app:" + app_id)
	else:
		set_pinned("lib:" + id, false)


func _move_ref(from: String, to: String) -> void:
	var pins_list: Array = Settings.get_value("pins").duplicate()
	var at := pins_list.find(from)
	if at >= 0:
		pins_list[at] = to
		Settings.set_value("pins", pins_list)
		pins_changed.emit()
	var recent: Array = Settings.get_value("recent_apps").duplicate()
	at = recent.find(from)
	if at >= 0:
		recent[at] = to
		Settings.set_value("recent_apps", recent)
	if is_favorite(from):
		var favs: Array = Settings.get_value("favorites").duplicate()
		at = favs.find(from)
		if at >= 0:
			favs[at] = to
		else:
			favs.append(to)
		Settings.set_value("favorites", favs)
		if to.begins_with("lib:"):
			var eid := to.substr(4)
			if not bool(Library.get_entry(eid).get("favorite", false)):
				Library.toggle_favorite(eid)
		favorites_changed.emit()


# --- Favourites ---------------------------------------------------------------------------
# Anything you can open can be a favourite. Library entries keep it on the
# entry itself (the Library's Favourites filter); everything else lives in a
# Settings list, which also remembers the order they were added in.

func can_favorite(ref: String) -> bool:
	return ref.begins_with("lib:") or ref.begins_with("app:") or OAZY_APPS.has(ref) or (ref.begins_with("win:") and ref.length() > 4)


func is_favorite(ref: String) -> bool:
	if ref.begins_with("lib:"):
		return bool(Library.get_entry(ref.substr(4)).get("favorite", false))
	return Settings.get_value("favorites").has(ref)


func set_favorite(ref: String, on: bool) -> void:
	if not can_favorite(ref):
		return
	var list: Array = Settings.get_value("favorites").duplicate()
	list.erase(ref)
	if on:
		list.append(ref)
	Settings.set_value("favorites", list)
	if ref.begins_with("lib:"):
		var id := ref.substr(4)
		if Library.has_entry(id) and bool(Library.get_entry(id)["favorite"]) != on:
			Library.toggle_favorite(id)
	favorites_changed.emit()


func toggle_favorite(ref: String) -> bool:
	var on := not is_favorite(ref)
	set_favorite(ref, on)
	return on


## Favourites in the order they were added (library favourites from before
## the list existed come last).
func favorites() -> Array[String]:
	var out: Array[String] = []
	for r in Settings.get_value("favorites"):
		var ref := str(r)
		if ref.begins_with("lib:"):
			if not is_favorite(ref):
				continue
		elif ref.begins_with("app:") and apps_loaded and find_app(ref.substr(4)).is_empty():
			continue
		out.append(ref)
	for e in Library.entries:
		var ref := "lib:" + str(e["id"])
		if bool(e["favorite"]) and not out.has(ref):
			out.append(ref)
	return out


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
