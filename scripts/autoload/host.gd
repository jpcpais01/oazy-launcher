extends Node
## Bridge to the native companion (native/oazy_host.cs): real Windows windows,
## live thumbnails, app icons, installed apps, system stats and the global
## Ctrl+Alt+O "home" hotkey.
##
## The companion is compiled on first run with the C# compiler that ships with
## Windows, cached in user://host, and spoken to over a stdin/stdout pipe.
## Everywhere else (Linux dev runs, CI screenshots) Oazy keeps working with
## whatever windows `set_mock_windows` provides.

signal windows_changed
signal hotkey(was_foreground: bool)
## Ctrl+Alt+D, from any app.
signal desktop_hotkey
signal status_changed(available: bool)
## Alt+Tab while Oazy's switcher is on: "open", "open_back", "next", "prev",
## "left", "right", "up", "down", "close", "done" (Alt let go) or "cancel".
signal switch_key(key: String)
## Another app went fullscreen (a game, a video) or came back out of it.
signal fullscreen_changed(on: bool)

const SOURCE := "res://native/oazy_host.cs"
const CSC := [
	"C:/Windows/Microsoft.NET/Framework64/v4.0.30319/csc.exe",
	"C:/Windows/Microsoft.NET/Framework/v4.0.30319/csc.exe",
]

var available := false
var failed := false
var fail_reason := ""
var hotkey_ok := false
## Real application windows, Alt+Tab order: {hwnd, title, pid, exe, name, aumid, class, min, max}.
var windows: Array[Dictionary] = []
var foreground := 0
## True while Oazy itself is the foreground window.
var self_foreground := true
var self_hwnd := 0
## A fullscreen app is in front: Oazy's taskbar steps aside.
var fullscreen_app := false
## Set by set_mock_windows: the real window list stops replacing the mock one.
var mocked := false

var _pipe: FileAccess
var _pid := 0
var _reader: Thread
var _next_id := 1
var _pending := {}
var _quitting := false
var _starting := false
var _restarts := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


## Builds (first run only) and starts the companion in the background.
func start() -> void:
	if _starting or available or not App.is_windows():
		return
	_starting = true
	self_hwnd = DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE)
	WorkerThreadPool.add_task(_prepare_worker, false, "Prepare Oazy host")


func _prepare_worker() -> void:
	var result := build()
	_launch.call_deferred(result)


## Compiles the companion if this version of it isn't cached yet. Returns
## {"exe": path} or {"error": text}. Safe to call from a worker thread.
static func build() -> Dictionary:
	var src := FileAccess.get_file_as_string(SOURCE)
	if src.is_empty():
		return {"error": "Companion source missing from the package"}
	var dir := ProjectSettings.globalize_path("user://host")
	DirAccess.make_dir_recursive_absolute(dir)
	var exe := dir.path_join("OazyHost-%s.exe" % src.md5_text().substr(0, 10))
	if FileAccess.file_exists(exe):
		return {"exe": exe}
	var cs := dir.path_join("oazy_host.cs")
	var f := FileAccess.open(cs, FileAccess.WRITE)
	if f == null:
		return {"error": "Can't write to %s" % dir}
	f.store_string(src)
	f.close()
	var log := ""
	for csc in CSC:
		if not FileAccess.file_exists(csc):
			continue
		var out := []
		var code := OS.execute(csc, ["/nologo", "/optimize+", "/target:winexe", "/r:System.Drawing.dll", "/out:" + exe.replace("/", "\\"), cs.replace("/", "\\")], out, true)
		if code == 0 and FileAccess.file_exists(exe):
			for old in DirAccess.get_files_at(dir):
				if old.begins_with("OazyHost-") and old.ends_with(".exe") and dir.path_join(old) != exe:
					DirAccess.remove_absolute(dir.path_join(old))
			return {"exe": exe}
		log = "\n".join(out).strip_edges().substr(0, 600)
	if log == "":
		return {"error": "The .NET Framework C# compiler wasn't found"}
	return {"error": "Couldn't build the companion: " + log}


func _launch(result: Dictionary) -> void:
	_starting = false
	if not result.has("exe"):
		_fail(str(result.get("error", "Unknown error")))
		return
	var info := OS.execute_with_pipe(str(result["exe"]), PackedStringArray([str(OS.get_process_id())]), true)
	if info.is_empty() or info.get("stdio") == null:
		_fail("Couldn't start the companion")
		return
	_pipe = info["stdio"]
	_pid = int(info.get("pid", 0))
	_reader = Thread.new()
	_reader.start(_read_loop)
	available = true
	failed = false
	request(["hello", str(self_hwnd)])
	refresh()
	status_changed.emit(true)


func _fail(reason: String) -> void:
	failed = true
	fail_reason = reason
	available = false
	push_warning("Oazy host unavailable: " + reason)
	status_changed.emit(false)


# --- Pipe ------------------------------------------------------------------------

## Sends a command; `done` receives the reply Dictionary (or {"ok": false} if
## the companion isn't running).
func request(parts: Array, done: Callable = Callable()) -> void:
	if not available or _pipe == null:
		if done.is_valid():
			done.call({"ok": false})
		return
	var id := _next_id
	_next_id += 1
	if done.is_valid():
		_pending[id] = done
	var clean := PackedStringArray([str(id)])
	for p in parts:
		clean.append(str(p).replace("\t", " ").replace("\n", " ").replace("\r", " "))
	_pipe.store_line("\t".join(clean))


func _read_loop() -> void:
	var buf := PackedByteArray()
	while not _quitting:
		var chunk := _pipe.get_buffer(1)
		if chunk.is_empty():
			break
		var more := _pipe.get_length()
		if more > 0:
			chunk.append_array(_pipe.get_buffer(more))
		buf.append_array(chunk)
		var nl := buf.find(10)
		while nl >= 0:
			var line := buf.slice(0, nl).get_string_from_utf8()
			buf = buf.slice(nl + 1)
			_on_line.call_deferred(line)
			nl = buf.find(10)
	_on_dead.call_deferred()


func _on_line(line: String) -> void:
	var data: Variant = JSON.parse_string(line)
	if not data is Dictionary:
		return
	var d: Dictionary = data
	if d.has("ev"):
		match str(d["ev"]):
			"windows":
				_apply_windows(d)
			"hotkey":
				hotkey.emit(bool(d.get("was_fg", false)))
			"desktop_key":
				desktop_hotkey.emit()
			"switch":
				var key := str(d.get("key", ""))
				if key.begins_with("open"):
					# Tells the companion Oazy is alive; if this never arrives the
					# next Alt+Tab goes to Windows' own switcher.
					request(["switcher_ack"])
				switch_key.emit(key)
			"ready":
				hotkey_ok = bool(d.get("hotkey", false))
		return
	var id := int(d.get("id", 0))
	if _pending.has(id):
		var cb: Callable = _pending[id]
		_pending.erase(id)
		if cb.is_valid():
			cb.call(d)


func _on_dead() -> void:
	if _quitting:
		return
	available = false
	for cb in _pending.values():
		if cb.is_valid():
			cb.call({"ok": false, "error": "companion stopped"})
	_pending.clear()
	if _reader:
		_reader.wait_to_finish()
		_reader = null
	_pipe = null
	_pid = 0
	if _restarts >= 3:
		_fail("The companion stopped")
		return
	# Come back on our own a few times so a crash doesn't cost the taskbar.
	_restarts += 1
	push_warning("Oazy host stopped, restarting")
	status_changed.emit(false)
	await get_tree().create_timer(1.0).timeout
	if not _quitting:
		start()


func _exit_tree() -> void:
	shutdown()


func shutdown() -> void:
	if _quitting:
		return
	_quitting = true
	if available and _pipe != null:
		# Let the companion put the Windows taskbar and work area back, then go.
		_pipe.store_line("0\tunshell")
		_pipe.flush()
		var waited := 0
		while waited < 600 and _pid > 0 and OS.is_process_running(_pid):
			OS.delay_msec(50)
			waited += 50
			if waited == 150:
				_pipe.close()
	if _pid > 0 and OS.is_process_running(_pid):
		OS.kill(_pid)
	_pid = 0
	available = false


# --- Windows ----------------------------------------------------------------------

func refresh() -> void:
	request(["windows"], func(d: Dictionary) -> void:
		if d.get("ok", false):
			_apply_windows(d)
	)


func _apply_windows(d: Dictionary) -> void:
	if mocked:
		return
	var list: Array[Dictionary] = []
	var raw: Variant = d.get("windows", [])
	if raw is Array:
		for w in raw:
			if w is Dictionary:
				var item: Dictionary = w
				item["hwnd"] = int(item.get("hwnd", 0))
				item["pid"] = int(item.get("pid", 0))
				list.append(item)
	windows = list
	foreground = int(d.get("fg", 0))
	self_foreground = bool(d.get("self_fg", false)) or not available
	var fs := bool(d.get("fs", false))
	if fs != fullscreen_app:
		fullscreen_app = fs
		fullscreen_changed.emit(fs)
	windows_changed.emit()


## Screenshot runs and non-Windows dev builds show these instead.
func set_mock_windows(list: Array, fg: int = 0) -> void:
	mocked = true
	windows.clear()
	for w in list:
		var item: Dictionary = {"hwnd": 0, "title": "", "pid": 0, "exe": "", "name": "", "aumid": "", "class": "", "min": false, "max": false}
		item.merge(w, true)
		windows.append(item)
	foreground = fg
	self_foreground = fg == 0
	windows_changed.emit()


func get_window_info(hwnd: int) -> Dictionary:
	for w in windows:
		if int(w["hwnd"]) == hwnd:
			return w
	return {}


func focus(hwnd: int) -> void:
	request(["focus", hwnd])


## One of Oazy's layers just emptied while it had focus: Windows activates the
## next window in line, as if it had closed. Ignored if it has come back since.
func release_focus(hwnd: int) -> void:
	if hwnd != 0:
		request(["release", hwnd])


## Lifts a window to the top of its band (topmost or not) without focusing it.
func raise_window(hwnd: int) -> void:
	if hwnd != 0:
		request(["raise", hwnd])


## Focus it, or minimise it if it is already the active window (taskbar click).
func toggle(hwnd: int) -> void:
	request(["toggle", hwnd])


func minimize(hwnd: int) -> void:
	request(["minimize", hwnd])


func close_window(hwnd: int) -> void:
	request(["close", hwnd])


## Brings Oazy itself to the front.
func go_home() -> void:
	request(["home"])


# --- Icons, apps, stats, thumbnails ---------------------------------------------------

func render_icon(key: String, px: int, out_path: String, done: Callable) -> void:
	request(["icon", key, px, ProjectSettings.globalize_path(out_path).replace("/", "\\")], done)


func list_apps(done: Callable) -> void:
	request(["apps"], done)


func stats(done: Callable) -> void:
	request(["stats"], done)


## Shows a live DWM preview of `hwnd` inside `rect` (pixels of the window
## `dest`, Oazy's main window when 0), at `opacity` (0 hides it). `done`
## gets the fitted rect. Cheap enough to call every frame while it moves.
func thumb(hwnd: int, rect: Rect2i, done: Callable = Callable(), dest: int = 0, opacity: int = 255) -> void:
	request(["thumb", hwnd, rect.position.x, rect.position.y, rect.size.x, rect.size.y, opacity, dest], done)


func thumb_clear() -> void:
	request(["thumb_clear"])


## Alt+Tab opens Oazy's switcher instead of Windows' own (see switch_key).
func set_switcher(on: bool) -> void:
	request(["switcher", 1 if on else 0])


func lock_pc() -> void:
	request(["lock"])


func sleep_pc() -> void:
	request(["sleep"])


# --- Shell mode ----------------------------------------------------------------------

## Makes Oazy the desktop: `desktop` stays at the bottom, the work area stops
## `reserve_px` above the bottom of the screen and the Windows taskbar hides.
func enter_shell(desktop: int, reserve_px: int, hide_taskbar: bool, done: Callable = Callable()) -> void:
	request(["shell", desktop, reserve_px, 1 if hide_taskbar else 0], done)


func exit_shell() -> void:
	request(["unshell"])


## Window looks for one of Oazy's native windows: "surface", "overlay" or
## "window". `done` gets {backdrop: bool}.
func style_window(hwnd: int, kind: String, done: Callable = Callable()) -> void:
	request(["style", hwnd, kind], done)


## Gives other apps' title bars and borders Oazy's colours.
func theme_apps(on: bool, border: Color, caption: Color, text: Color) -> void:
	request(["theme", 1 if on else 0, _colorref(border), _colorref(caption), _colorref(text)])


func show_desktop() -> void:
	request(["show_desktop"])


static func _colorref(c: Color) -> int:
	return (int(c.b8) << 16) | (int(c.g8) << 8) | int(c.r8)
