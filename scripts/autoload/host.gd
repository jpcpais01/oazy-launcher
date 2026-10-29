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
## Wi-Fi news from Windows: {"what": "scan"|"connecting"|"connected"|"failed"|"disconnected"|"radio"|"adapter", ...}.
signal wifi_event(d: Dictionary)
## Another app went fullscreen (a game, a video) or came back out of it.
signal fullscreen_changed(on: bool)
## About sixty times a second while music is being listened to (see Music).
signal audio_frame(d: Dictionary)
## What music is being listened to now: "chrome", "all" or "" (nothing).
signal audio_source(src: String)
## What Windows' media controls say is playing (see NowPlaying).
signal media_changed(d: Dictionary)

const SOURCE := "res://native/oazy_host.cs"
const MEDIA_SOURCE := "res://native/oazy_media.cs"
const CSC := [
	"C:/Windows/Microsoft.NET/Framework64/v4.0.30319/csc.exe",
	"C:/Windows/Microsoft.NET/Framework/v4.0.30319/csc.exe",
]

var available := false
var failed := false
var fail_reason := ""
var hotkey_ok := false
## The now-playing library: its path once built, or why it couldn't be.
var media_lib := ""
var media_error := ""
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
## Restarts in a row: one that ran for a while doesn't count against the next.
var _restarts := 0
var _launched_at := 0


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
	if result.has("exe"):
		var media := build_media()
		result["media"] = media.get("dll", "")
		result["media_error"] = media.get("error", "")
	_launch.call_deferred(result)


## Compiles the now-playing library (native/oazy_media.cs) against Windows'
## WinRT metadata, if this version isn't cached yet. Returns {"dll": path} or
## {"error": text}; the companion runs fine without it.
static func build_media() -> Dictionary:
	var src := FileAccess.get_file_as_string(MEDIA_SOURCE)
	if src.is_empty():
		return {"error": "Media source missing from the package"}
	var dir := ProjectSettings.globalize_path("user://host")
	DirAccess.make_dir_recursive_absolute(dir)
	var dll := dir.path_join("OazyMedia-%s.dll" % src.md5_text().substr(0, 10))
	if FileAccess.file_exists(dll):
		return {"dll": dll}
	var meta := "C:/Windows/System32/WinMetadata"
	if not DirAccess.dir_exists_absolute(meta):
		return {"error": "This Windows has no WinRT metadata"}
	var cs := dir.path_join("oazy_media.cs")
	var f := FileAccess.open(cs, FileAccess.WRITE)
	if f == null:
		return {"error": "Can't write to %s" % dir}
	f.store_string(src)
	f.close()
	var log := ""
	for csc in CSC:
		if not FileAccess.file_exists(csc):
			continue
		var fw: String = csc.get_base_dir()
		var args := ["/nologo", "/optimize+", "/target:library"]
		for facade in ["System.Runtime.dll"]:
			if FileAccess.file_exists(fw.path_join(facade)):
				args.append("/r:" + fw.path_join(facade).replace("/", "\\"))
		for md in DirAccess.get_files_at(meta):
			if md.ends_with(".winmd"):
				args.append("/r:" + meta.path_join(md).replace("/", "\\"))
		args.append("/out:" + dll.replace("/", "\\"))
		args.append(cs.replace("/", "\\"))
		var out := []
		var code := OS.execute(csc, args, out, true)
		if code == 0 and FileAccess.file_exists(dll):
			for old in DirAccess.get_files_at(dir):
				if old.begins_with("OazyMedia-") and old.ends_with(".dll") and dir.path_join(old) != dll:
					DirAccess.remove_absolute(dir.path_join(old))
			return {"dll": dll}
		log = "\n".join(out).strip_edges().substr(0, 600)
	return {"error": "Couldn't build the media library: " + log if log != "" else "The .NET Framework C# compiler wasn't found"}


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
		var code := OS.execute(csc, ["/nologo", "/optimize+", "/target:winexe", "/r:System.Drawing.dll", "/r:System.Management.dll", "/r:System.Numerics.dll", "/r:System.Security.dll", "/out:" + exe.replace("/", "\\"), cs.replace("/", "\\")], out, true)
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
	_launched_at = Time.get_ticks_msec()
	available = true
	failed = false
	request(["hello", str(self_hwnd)])
	media_lib = str(result.get("media", ""))
	media_error = str(result.get("media_error", ""))
	if media_lib != "":
		request(["media_load", media_lib.replace("/", "\\")], func(d: Dictionary) -> void:
			if not d.get("ok", false):
				media_error = str(d.get("error", "couldn't load"))
				push_warning("Now playing unavailable: " + media_error)
		)
	elif media_error != "":
		push_warning("Now playing unavailable: " + media_error)
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
			"wifi":
				wifi_event.emit(d)
			"audio":
				audio_frame.emit(d)
			"audio_src":
				audio_source.emit(str(d.get("src", "")))
			"media":
				media_changed.emit(d)
			"picture":
				# A newer kept picture: loaded when something asks for it.
				var hw := int(d.get("hwnd", 0))
				if float(d.get("dev", 0.0)) >= 1.0:
					_kept[hw] = Vector2i(int(d.get("w", 0)), int(d.get("h", 0)))
					captures.erase(hw)
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
	# Nothing is known about other apps until it's back: don't keep the
	# taskbar out of the way of a fullscreen app that may be long gone.
	if fullscreen_app:
		fullscreen_app = false
		fullscreen_changed.emit(false)
	if Time.get_ticks_msec() - _launched_at > 60000:
		_restarts = 0
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
		# Let the companion put Windows' pointers, taskbar and work area back,
		# then go.
		_pipe.store_line("0\tcursors_off")
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
	if not captures.is_empty():
		var alive := {}
		for w in list:
			alive[int(w["hwnd"])] = true
		for k in captures.keys():
			if not alive.has(k):
				captures.erase(k)
	if not _kept.is_empty():
		var alive_k := {}
		for w in list:
			alive_k[int(w["hwnd"])] = true
		for k in _kept.keys():
			if not alive_k.has(k):
				_kept.erase(k)
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


## Lifts a window to the top of its band without focusing it. `topmost` also
## makes sure it is (back) in the always-on-top band.
func raise_window(hwnd: int, topmost: bool = false) -> void:
	if hwnd != 0:
		request(["raise", hwnd, 1 if topmost else 0])


## Focus it, or minimise it if it is already the active window (taskbar click).
func toggle(hwnd: int) -> void:
	request(["toggle", hwnd])


## Something is about to be launched: its first window comes up in front with
## focus, even when started from the taskbar (which never takes focus, so the
## new app wouldn't get to come forward by itself).
func expect_window() -> void:
	request(["expect"])


## Un-minimises a window without activating it (Oazy's desktop after Win+D).
func restore_quietly(hwnd: int) -> void:
	if hwnd != 0:
		request(["restore_quietly", hwnd])


func minimize(hwnd: int) -> void:
	request(["minimize", hwnd])


func close_window(hwnd: int) -> void:
	request(["close", hwnd])


## Brings Oazy itself to the front.
func go_home() -> void:
	request(["home"])


# --- Icons, apps, stats, thumbnails ---------------------------------------------------

## The last picture taken of each window (hwnd -> ImageTexture), so a window
## that has since been minimised still has one.
var captures := {}
## hwnd -> size of the picture the companion keeps of it (see keep_pictures).
var _kept := {}


## Takes a picture of `hwnd` (PrintWindow) at most `max_px` in size. `done`
## gets the ImageTexture, or null when it couldn't (minimised, gone, blank).
func capture(hwnd: int, max_px: Vector2i, done: Callable) -> void:
	var dir := ProjectSettings.globalize_path("user://host/caps")
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join("%d.rgba" % hwnd)
	request(["capture", hwnd, max_px.x, max_px.y, path.replace("/", "\\")], func(d: Dictionary) -> void:
		var tex: ImageTexture = null
		var w := int(d.get("w", 0))
		var h := int(d.get("h", 0))
		if d.get("ok", false) and w > 0 and h > 0 and float(d.get("dev", 0.0)) >= 1.0:
			var bytes := FileAccess.get_file_as_bytes(path)
			if bytes.size() == w * h * 4:
				var img := Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, bytes)
				img.generate_mipmaps()
				tex = ImageTexture.create_from_image(img)
				captures[hwnd] = tex
		if done.is_valid():
			done.call(tex)
	)


## Has the companion keep a recent picture of every open window, so Alt+Tab
## has one for windows that are minimised (Windows can't draw those).
func keep_pictures(on: bool, max_px: Vector2i = Vector2i(800, 500)) -> void:
	var dir := ""
	if on:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://host/caps"))
		dir = ProjectSettings.globalize_path("user://host/caps").replace("/", "\\")
	request(["keep_pictures", dir, max_px.x, max_px.y])


## The latest picture of a window: the last capture, or the one the companion
## kept. Null if there's none.
func picture_of(hwnd: int) -> Texture2D:
	if captures.has(hwnd):
		return captures[hwnd]
	if not _kept.has(hwnd):
		return null
	var size: Vector2i = _kept[hwnd]
	var bytes := FileAccess.get_file_as_bytes("user://host/caps/%d.kept.rgba" % hwnd)
	if size.x <= 0 or size.y <= 0 or bytes.size() != size.x * size.y * 4:
		return null
	var img := Image.create_from_data(size.x, size.y, false, Image.FORMAT_RGBA8, bytes)
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	captures[hwnd] = tex
	return tex


func render_icon(key: String, px: int, out_path: String, done: Callable) -> void:
	request(["icon", key, px, ProjectSettings.globalize_path(out_path).replace("/", "\\")], done)


func list_apps(done: Callable) -> void:
	request(["apps"], done)


## CPU, memory and battery, plus clocks, GPU temperature and load once the
## sensor thread has a reading (keys are -1 or missing until then). The CPU
## temperature is only looked for when `cpu_temp` is on.
func stats(done: Callable, cpu_temp: bool = false) -> void:
	request(["stats", 1 if cpu_temp else 0], done)


## Every running process: {pid, ppid, s (session), t (start), n (image name),
## exe, d (description), cpu (share of all CPU time since the last call),
## mem (private bytes)}, plus totals (cpu, mem_used, mem_total, cores) and
## `self`, Oazy's own pid. For the task manager, only while it is open.
func procs(done: Callable) -> void:
	request(["procs"], done)


## Ends these processes. `done` gets {ended, denied: [pid] (Windows said no:
## elevated or another user's), refused: [pid] (critical, never ended)}.
func kill(pids: Array, done: Callable = Callable()) -> void:
	var parts := PackedStringArray()
	for p in pids:
		parts.append(str(int(p)))
	request(["kill", ",".join(parts)], done)


## Shows a live DWM preview of `hwnd` inside `rect` (pixels of the window
## `dest`, Oazy's main window when 0), at `opacity` (0 hides it). `done`
## gets the fitted rect. Cheap enough to call every frame while it moves.
func thumb(hwnd: int, rect: Rect2i, done: Callable = Callable(), dest: int = 0, opacity: int = 255) -> void:
	var parts := ["thumb", hwnd, rect.position.x, rect.position.y, rect.size.x, rect.size.y, opacity, dest]
	if done.is_valid():
		request(parts, done)
	else:
		_send_quiet(parts)


## A command nobody waits for: the companion sends no reply, so moving
## previews every frame costs neither side a JSON round trip.
func _send_quiet(parts: Array) -> void:
	if not available or _pipe == null:
		return
	var clean := PackedStringArray(["0"])
	for p in parts:
		clean.append(str(p))
	_pipe.store_line("\t".join(clean))


func thumb_clear() -> void:
	_send_quiet(["thumb_clear"])


## Alt+Tab opens Oazy's switcher instead of Windows' own (see switch_key).
func set_switcher(on: bool) -> void:
	request(["switcher", 1 if on else 0])


## Starts listening to what's playing: "chrome" (Chrome alone, or everything
## while Chrome is closed) or "all". Frames arrive as audio_frame.
func listen(source: String) -> void:
	request(["audio", source])


func stop_listening() -> void:
	request(["audio_stop"])


## Controls the playing media session: "toggle", "play", "pause", "next",
## "prev", "seek" (arg: seconds), "prefer" (arg: app to favour, or "all").
func media_command(cmd: String, arg: String = "", done: Callable = Callable()) -> void:
	request(["now_playing", cmd, arg], done)


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


## Styles one of Oazy's layer windows (`kind` is the layer's name): no
## Alt+Tab entry, no frame. A `topmost` one is kept above other apps: the
## companion puts it back there if it ever drops out.
func style_window(hwnd: int, kind: String, topmost: bool = false, done: Callable = Callable()) -> void:
	request(["style", hwnd, kind, 1 if topmost else 0], done)


## Puts one of Oazy's windows back over the whole screen Oazy's desktop is on,
## `inset_px` short of the bottom. Godot won't move or resize a window it
## counts as fullscreen, which a screen-sized one is.
func fit_window(hwnd: int, inset_px: int = 0) -> void:
	if hwnd != 0:
		request(["fit", hwnd, inset_px])


## Gives other apps' window borders Oazy's accent. (The companion ignores
## the caption and text colours: see Theme in oazy_host.cs.)
func theme_apps(on: bool, border: Color, caption: Color, text: Color) -> void:
	request(["theme", 1 if on else 0, _colorref(border), _colorref(caption), _colorref(text)])


## Show desktop for other apps' windows, decided together with Oazy's own:
## `oazy_open` says whether any of Oazy's windows (in the OS window `layer`)
## is showing. `done` gets {"action": "hide"} (minimise yours too) or
## {"action": "restore", "restored": bool, "oazy_front": bool} (bring yours
## back; `restored` if other apps came back, `oazy_front` if yours were in
## front of them and should get focus).
func show_desktop(oazy_open: bool, layer: int, done: Callable = Callable()) -> void:
	request(["show_desktop", 1 if oazy_open else 0, layer], done)


static func _colorref(c: Color) -> int:
	return (int(c.b8) << 16) | (int(c.g8) << 8) | int(c.r8)
