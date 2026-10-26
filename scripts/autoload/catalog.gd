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
	"oazy:claude": {"name": "Claude", "glyph": "claude", "desc": "Claude Code in Oazy's glass: chat, edits and commands in your folders"},
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
## Oazy's own apps that can sit in the Library as a card with cover art
## (assets/brand, by name), like any app from Start.
const LIBRARY_OAZY := ["oazy:flow", "oazy:claude"]

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
## Library entries by normalised name, for canonical().
var _lib_names := {}
var _tidy_queued := false
## Install folder -> the exe its icon comes from (entry_icon_key).
var _dir_exes := {}


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ICON_DIR)
	if not App.smoke_test:
		_load_cache()
	Host.status_changed.connect(_on_host_status)
	apps_changed.connect(_forget_items)
	apps_changed.connect(_queue_tidy)
	Library.changed.connect(_forget_items)
	Library.changed.connect(_queue_tidy)
	Library.entry_changed.connect(func(_id: String) -> void: _forget_items())


func _forget_items() -> void:
	_items_dirty = true
	_lib_names.clear()


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
	_ensure_flow_in_library()
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


# --- One thing, one ref ---------------------------------------------------------------------
# A game you have in the Library can also be a Start shortcut, a running
# window or an app you added. Wherever it turns up it is its library entry,
# so it has one icon, one favourite, one pin and one menu.

## The ref everything else should use for `ref`: an installed app or a
## program that's in your Library (added from Start, or the same name / exe as
## an entry) becomes that entry; anything else stays as it is.
func canonical(ref: String) -> String:
	var id := ""
	if ref.begins_with("app:"):
		var app_id := ref.substr(4)
		id = library_entry_for_app(app_id)
		if id == "":
			var a := find_app(app_id)
			if not a.is_empty():
				id = library_entry_named(str(a["name"]))
	elif ref.begins_with("win:"):
		id = library_entry_for_exe(ref.substr(4))
	elif LIBRARY_OAZY.has(ref):
		id = library_entry_for_oazy(ref)
	return "lib:" + id if id != "" else ref


## The library entry one of Oazy's own apps became, or "".
func library_entry_for_oazy(ref: String) -> String:
	for e in Library.entries:
		if str(e.get("oazy", "")) == ref:
			return str(e["id"])
	return ""


## The library entry called `name` (ignoring case, symbols and ™), or "".
func library_entry_named(name: String) -> String:
	if _lib_names.is_empty():
		for e in Library.entries:
			# Oazy's own apps go by their ref, never by name (Oazy's Claude isn't the Claude app).
			if str(e.get("oazy", "")) != "":
				continue
			var key := Art.norm_title(str(e["name"]))
			# Games win over apps, the first one found over later ones.
			if key != "" and (not _lib_names.has(key) or (e["kind"] == "game" and Library.get_entry(_lib_names[key])["kind"] != "game")):
				_lib_names[key] = str(e["id"])
		_lib_names[""] = ""
	return str(_lib_names.get(Art.norm_title(name), ""))


## The library entry an exe belongs to (its own path, or inside a store
## game's folder), or "".
func library_entry_for_exe(exe: String) -> String:
	exe = exe.replace("\\", "/").to_lower()
	var file := exe.get_file()
	if not file.ends_with(".exe") or file in SHELLS:
		return ""
	for e in Library.entries:
		var path := str(e["path"]).replace("\\", "/").to_lower()
		if path == "" or path.contains("://") or path.get_file() in SHELLS:
			continue
		if path == exe or (e["source"] != "custom" and exe.begins_with(path.trim_suffix("/") + "/")):
			return str(e["id"])
		if path.get_file() == file:
			return str(e["id"])
	return ""


## The installed app a library entry stands for (added from Start, or the
## Start shortcut with its name), or {}.
func app_for_entry(id: String) -> Dictionary:
	var e := Library.get_entry(id)
	if e.is_empty():
		return {}
	var a := find_app(str(e.get("app_id", "")))
	if a.is_empty():
		a = find_app_by_norm_name(str(e["name"]))
	return a


func find_app_by_norm_name(name: String) -> Dictionary:
	var n := Art.norm_title(name)
	if n == "":
		return {}
	for a in apps:
		if Art.norm_title(str(a["name"])) == n:
			return a
	return {}


## `list` with every ref made canonical, without repeats or missing entries.
func _canonical_list(list: Array) -> Array:
	var out: Array = []
	for r in list:
		var ref := canonical(str(r))
		if out.has(ref) or (ref.begins_with("lib:") and not Library.has_entry(ref.substr(4))):
			continue
		out.append(ref)
	return out


func _queue_tidy() -> void:
	if not _tidy_queued:
		_tidy_queued = true
		_tidy.call_deferred()


## Rewrites saved pins, favourites and recents to canonical refs, so a game
## favourited as its Start shortcut (or from the taskbar while it ran) is the
## same favourite as the Library's heart.
func _tidy() -> void:
	_tidy_queued = false
	var pins_now: Array = Settings.get_value("pins")
	var pins_new := _canonical_list(pins_now)
	if pins_new != pins_now:
		Settings.set_value("pins", pins_new)
		pins_changed.emit()
	var recent_now: Array = Settings.get_value("recent_apps")
	var recent_new := _canonical_list(recent_now)
	if recent_new != recent_now:
		Settings.set_value("recent_apps", recent_new)
	var favs_now: Array = Settings.get_value("favorites")
	var favs_new := _canonical_list(favs_now)
	var hearts := false
	for r in favs_now:
		# A favourite that turned out to be a library entry wears its heart.
		var ref := canonical(str(r))
		if ref != str(r) and ref.begins_with("lib:") and Library.has_entry(ref.substr(4)) and not bool(Library.get_entry(ref.substr(4))["favorite"]):
			Library.update_entry(ref.substr(4), {"favorite": true})
			hearts = true
	if favs_new != favs_now or hearts:
		Settings.set_value("favorites", favs_new)
		favorites_changed.emit()


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
		# Oazy's own apps keep their own icons.
		it["oazy"] = str(e.get("oazy", ""))
		if not e.is_empty():
			it["icon_key"] = entry_icon_key(e)
	elif ref.begins_with("win:"):
		it["kind"] = "window"
		it["icon_key"] = ref.substr(4)
		it["name"] = Fmt.pretty_name(ref.substr(4))
	return it


## Where Windows draws a library entry's real icon from: the Start app it
## came from (or has its name), its exe, or for a store game the main exe in
## its install folder. "" when it has none (a web link, a shell command).
func entry_icon_key(e: Dictionary) -> String:
	var app_id := str(e.get("app_id", ""))
	if app_id != "":
		return "shell:AppsFolder\\" + app_id
	var path := str(e.get("path", "")).replace("\\", "/")
	if path.get_file().to_lower() in SHELLS:
		return ""
	if path == "" or path.contains("://"):
		var a := find_app_by_norm_name(str(e.get("name", "")))
		return "shell:AppsFolder\\" + str(a["id"]) if not a.is_empty() else ""
	if not path.get_extension().is_empty() and not DirAccess.dir_exists_absolute(path):
		return path.replace("/", "\\")
	# A folder (Steam installs): its biggest exe is the game. Looked up once.
	if not _dir_exes.has(path):
		_dir_exes[path] = Library._guess_exe(path).replace("/", "\\")
	return _dir_exes[path]


## Oazy's apps that run as their own windows rather than inside the shell.
static func is_own_window_app(ref: String) -> bool:
	return ref == Browser.REF or ref == Terminal.REF or ref == Files.REF or ref == ClaudeApp.REF or Browser.APPS.has(ref)


func launch(ref: String) -> bool:
	if not ref.begins_with("lib:") and (not OAZY_APPS.has(ref) or is_own_window_app(ref)):
		# Whatever window this opens comes up in front with focus.
		Host.expect_window()
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
	if ref == ClaudeApp.REF:
		note_recent(ref)
		return ClaudeApp.open()
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
	ref = canonical(ref)
	var list: Array = Settings.get_value("recent_apps").duplicate()
	list.erase(ref)
	list.push_front(ref)
	Settings.set_value("recent_apps", list.slice(0, MAX_RECENT))


func recent_apps() -> Array[String]:
	var out: Array[String] = []
	for r in _canonical_list(Settings.get_value("recent_apps")):
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
	for a in apps:
		# Anything in the library (a game's Start shortcut, an app you added)
		# shows as its library entry instead.
		if canonical("app:" + str(a["id"])).begins_with("lib:"):
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
	return canonical(_window_ref(w))


func _window_ref(w: Dictionary) -> String:
	if Browser.owns_window(w):
		var app := Browser.app_for_window(w)
		return app if app != "" else Browser.REF
	if ClaudeApp.owns_window(w):
		return ClaudeApp.REF
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
	if file in SHELLS:
		for e in Library.entries:
			var path := str(e["path"]).replace("\\", "/").to_lower()
			if path.get_file() in SHELLS and title.contains(str(e["name"]).to_lower().get_slice(" ", 0)):
				return "lib:" + str(e["id"])
	var entry := library_entry_for_exe(exe)
	if entry != "":
		return "lib:" + entry
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
	out.assign(_canonical_list(Settings.get_value("pins")))
	return out


func is_pinned(ref: String) -> bool:
	return pins().has(canonical(ref))


func set_pinned(ref: String, on: bool) -> void:
	ref = canonical(ref)
	var list: Array = _canonical_list(Settings.get_value("pins"))
	if on and not list.has(ref):
		list.append(ref)
	elif not on:
		list.erase(ref)
	Settings.set_value("pins", list)
	pins_changed.emit()


func move_pin(ref: String, to_index: int) -> void:
	ref = canonical(ref)
	var list: Array = _canonical_list(Settings.get_value("pins"))
	if not list.has(ref):
		return
	list.erase(ref)
	list.insert(clampi(to_index, 0, list.size()), ref)
	Settings.set_value("pins", list)
	pins_changed.emit()


## Flow joins the Library once, as a card with its art (its pins and
## favourites move over with it).
func _ensure_flow_in_library() -> void:
	if Settings.get_value("flow_in_library") or not App.is_windows():
		return
	Settings.set_value("flow_in_library", true)
	add_to_library("oazy:flow")


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
		if not Settings.get_value("claude_app_pinned") and App.is_windows():
			_pin_claude()
		return
	var list: Array = ["oazy:library", Browser.REF]
	Settings.set_value("browser_pinned", true)
	Settings.set_value("terminal_pinned", true)
	Settings.set_value("flow_pinned", true)
	Settings.set_value("claude_app_pinned", true)
	for want in DEFAULT_PINS:
		for a in apps:
			if str(a["name"]).to_lower() == want:
				list.append("app:" + str(a["id"]))
				break
	list.append(Terminal.REF)
	if App.is_windows():
		list.append(ClaudeApp.REF)
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


## Oazy's Claude joins the taskbar once, just before the first Claude pin
## (the Claude app or Claude Code) or else after the Terminal, for people who
## set up their pins before it existed. Nothing else is unpinned.
func _pin_claude() -> void:
	Settings.set_value("claude_app_pinned", true)
	var list: Array = Settings.get_value("pins").duplicate()
	if list.has(ClaudeApp.REF):
		return
	var at := -1
	for i in list.size():
		var ref := str(list[i])
		if (ref.begins_with("app:") or ref.begins_with("lib:")) and str(item(ref).get("name", "")).to_lower().contains("claude"):
			at = i
			break
	if at < 0:
		at = list.find(Terminal.REF) + 1 if list.has(Terminal.REF) else list.size()
	list.insert(clampi(at, 0, list.size()), ClaudeApp.REF)
	Settings.set_value("pins", list)
	pins_changed.emit()


# --- Library apps -------------------------------------------------------------------------
# Any installed app can join the Library, where it gets a cover and sits with
# your games. It then shows as that entry everywhere (Start, search, the
# taskbar), so its pins, favourites and recents move over with it, and back
# again if it leaves.

## The library entry an installed app became, or "".
func library_entry_for_app(id: String) -> String:
	var l := id.to_lower()
	for e in Library.entries:
		if str(e.get("app_id", "")).to_lower() == l:
			return str(e["id"])
	return ""


func can_add_to_library(ref: String) -> bool:
	if canonical(ref) != ref:
		return false
	if ref.begins_with("app:") or LIBRARY_OAZY.has(ref):
		return true
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
	var have := canonical(ref)
	if have.begins_with("lib:"):
		return have.substr(4)
	var fields := {}
	var fav := is_favorite(ref)
	if ref.begins_with("app:"):
		fields = app_entry_fields(ref.substr(4))
	elif LIBRARY_OAZY.has(ref):
		fields = {"name": str(OAZY_APPS[ref]["name"]), "kind": "app", "source": "custom", "oazy": ref}
	elif can_add_to_library(ref):
		fields = Library.infer_from_path(ref.substr(4).replace("\\", "/"))
	else:
		return ""
	var id := Library.add_entry(fields)
	_move_ref(ref, "lib:" + id, fav)
	return id


## Takes an entry out of the library. The installed app it stood for (added
## from Start, or the Start shortcut with its name) takes its pins,
## favourites and recents back; anything else loses them.
func remove_from_library(id: String) -> void:
	var from := "lib:" + id
	var app := app_for_entry(id)
	var fav := is_favorite(from)
	var own := str(Library.get_entry(id).get("oazy", ""))
	Library.remove_entry(id)
	if own != "":
		_move_ref(from, own, fav)
	elif not app.is_empty():
		_move_ref(from, "app:" + str(app["id"]), fav)


func _move_ref(from: String, to: String, favorite: bool) -> void:
	for key in ["pins", "recent_apps", "favorites"]:
		var list: Array = Settings.get_value(key).duplicate()
		var at := list.find(from)
		if key == "favorites" and not favorite:
			list.erase(from)
		elif at >= 0:
			list[at] = to
		elif key == "favorites":
			list.append(to)
		Settings.set_value(key, _canonical_list(list))
	if favorite and to.begins_with("lib:"):
		var eid := to.substr(4)
		if Library.has_entry(eid) and not bool(Library.get_entry(eid)["favorite"]):
			Library.update_entry(eid, {"favorite": true})
	pins_changed.emit()
	favorites_changed.emit()


# --- Favourites ---------------------------------------------------------------------------
# Anything you can open can be a favourite. Library entries keep it on the
# entry itself (the Library's Favourites filter); everything else lives in a
# Settings list, which also remembers the order they were added in.

func can_favorite(ref: String) -> bool:
	ref = canonical(ref)
	return ref.begins_with("lib:") or ref.begins_with("app:") or OAZY_APPS.has(ref) or (ref.begins_with("win:") and ref.length() > 4)


func is_favorite(ref: String) -> bool:
	ref = canonical(ref)
	if ref.begins_with("lib:"):
		return bool(Library.get_entry(ref.substr(4)).get("favorite", false))
	return Settings.get_value("favorites").has(ref)


func set_favorite(ref: String, on: bool) -> void:
	ref = canonical(ref)
	if not can_favorite(ref):
		return
	var list: Array = _canonical_list(Settings.get_value("favorites"))
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


## Moves a favourite to `to_index` in favorites() order (what the desktop,
## Start and the second desktop screen all show).
func move_favorite(ref: String, to_index: int) -> void:
	var list := favorites()
	var at := list.find(canonical(ref))
	if at < 0:
		return
	list.remove_at(at)
	list.insert(clampi(to_index, 0, list.size()), canonical(ref))
	Settings.set_value("favorites", Array(list))
	favorites_changed.emit()


## Favourites in the order they were added or dragged into (library favourites from before
## the list existed come last).
func favorites() -> Array[String]:
	var out: Array[String] = []
	for r in _canonical_list(Settings.get_value("favorites")):
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
