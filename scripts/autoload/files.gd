extends Node
## Oazy Files: your folders in Oazy's glass, with tabs, a sidebar of places
## and drives, icon and details views, search and the usual file operations
## (through Windows' shell, so the Recycle Bin and conflict prompts still work).
##
## It lives in native/files and is built like Oazy Terminal (see WebApp):
## compiled on first use into user://files/app-<hash>, run as its own process,
## settings in user://files/data. A second launch opens a tab in the running one.
##
## Folders opened from Oazy (Start, the File Explorer pin, search results,
## Settings) open here while setting `files_oazy` is on.

const REF := "oazy:files"
const SRC := "res://native/files"
const EXE := "OazyFiles.exe"
const UI := ["files.html", "files.css", "files.js", "icons.js"]
## For zip files (Extract here, Compress to ZIP).
const REFS := ["System.IO.Compression.dll", "System.IO.Compression.FileSystem.dll"]

var _exe := ""
var _building := false
var _queue: Array[Dictionary] = []
var _runtime := 0 # 0 unknown, 1 there, -1 missing


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--files-selftest="):
			_selftest.call_deferred(a.get_slice("=", 1))


func data_dir() -> String:
	return ProjectSettings.globalize_path("user://files/data")


## Whether folders should open in Oazy Files rather than Windows Explorer.
func enabled() -> bool:
	return App.is_windows() and bool(Settings.get_value("files_oazy"))


## Opens a folder (or the folder of a file, with it picked out); "" is Home.
## Falls back to Windows Explorer when Oazy Files is off or can't run.
func open_folder(path: String = "") -> void:
	var p := path.replace("/", "\\")
	var explorer := func() -> void:
		if not App.is_windows():
			if path != "":
				OS.shell_open(path)
			return
		if p == "":
			OS.create_process("explorer.exe", [])
		elif FileAccess.file_exists(path):
			OS.create_process("explorer.exe", ["/select," + p])
		else:
			OS.create_process("explorer.exe", [p])
	if not enabled():
		explorer.call()
		return
	open({"path": p}, explorer)


## Opens a window or tab. `opts`: path, new_window. `fallback` runs instead
## if Oazy Files can't (no WebView2, or the build failed).
func open(opts: Dictionary = {}, fallback: Callable = Callable()) -> bool:
	if not App.is_windows():
		App.toast("Oazy Files runs on Windows")
		return false
	if _runtime == 0 and Host.available:
		Host.request(["webview2"], func(d: Dictionary) -> void:
			if d.get("ok", false):
				_runtime = 1 if str(d.get("version", "")) != "" else -1
			_open_or_fall_back(opts, fallback)
		)
		return true
	_open_or_fall_back(opts, fallback)
	return true


func _open_or_fall_back(opts: Dictionary, fallback: Callable) -> void:
	if _runtime == -1:
		if fallback.is_valid():
			fallback.call()
		else:
			Browser.runtime_missing.emit()
		return
	opts["fallback"] = fallback
	_queue.append(opts)
	if _exe != "":
		_flush()
		return
	if _building:
		return
	_building = true
	var slow := get_tree().create_timer(0.8)
	slow.timeout.connect(func() -> void:
		if _building:
			App.toast("Getting Oazy Files ready…")
	)
	WorkerThreadPool.add_task(func() -> void:
		var r := build()
		_built.call_deferred(r)
	, false, "Build Oazy Files")


func _built(r: Dictionary) -> void:
	_building = false
	if not r.has("exe"):
		push_warning("Oazy Files: " + str(r.get("error", "")))
		App.toast("Couldn't start Oazy Files: %s" % str(r.get("error", "unknown error")), &"error")
		# Folders still open, in Windows Explorer.
		for q in _queue:
			var fb: Callable = q.get("fallback", Callable())
			if fb.is_valid():
				fb.call()
		_queue.clear()
		return
	_exe = str(r["exe"])
	_flush()


func _flush() -> void:
	for q in _queue:
		var args := PackedStringArray(["--data", data_dir(), "--accent", "#" + App.accent.to_html(false)])
		if q.get("new_window", false):
			args.append("--new-window")
		if str(q.get("path", "")) != "":
			args.append(str(q["path"]))
		if OS.create_process(_exe, args) <= 0:
			var fb: Callable = q.get("fallback", Callable())
			if fb.is_valid():
				fb.call()
			else:
				App.toast("Couldn't start Oazy Files", &"error")
	_queue.clear()


## Unpacks and compiles Oazy Files if this version isn't there yet.
## Returns {"exe": path} or {"error": text}. Safe to call from a worker thread.
static func build() -> Dictionary:
	return WebApp.build("files", EXE, "oazy_files.cs", "oazy_files.ico", files(), REFS)


## Everything it needs: {path in its folder: res:// path}.
static func files() -> Dictionary:
	var files := WebApp.WEBVIEW2.duplicate()
	files["oazy_files.cs"] = SRC.path_join("oazy_files.cs")
	files["oazy_files.ico"] = SRC.path_join("oazy_files.ico")
	for f in UI:
		files["ui/" + f] = SRC.path_join("ui").path_join(f)
	return files


## Is this real window one of Oazy Files'?
static func owns_window(w: Dictionary) -> bool:
	return WebApp.owns_window(w, "files", EXE)


## Is this app Windows' File Explorer (which opens Oazy Files instead)?
static func is_explorer(it: Dictionary) -> bool:
	var id := str(it.get("ref", "")).to_lower().replace("\\", "/")
	var name := str(it.get("name", "")).to_lower()
	return id.contains("microsoft.windows.explorer") or id.ends_with("/explorer.exe") or name == "file explorer"


## CI: build Oazy Files, run its self-test (real WebView2 and shell icons,
## file operations, screenshots into `dir`) and exit with its result.
func _selftest(dir: String) -> void:
	print("FILES SELFTEST: building")
	var r := build()
	if not r.has("exe"):
		print("FILES SELFTEST: FAIL ", r.get("error", ""))
		get_tree().quit(1)
		return
	print("FILES SELFTEST: built ", r["exe"])
	var pid := OS.create_process(str(r["exe"]), ["--selftest", dir])
	if pid <= 0:
		print("FILES SELFTEST: FAIL couldn't start Oazy Files")
		get_tree().quit(1)
		return
	var started := Time.get_ticks_msec()
	while OS.is_process_running(pid) and Time.get_ticks_msec() - started < 200000:
		await get_tree().create_timer(0.25).timeout
	var code := OS.get_process_exit_code(pid)
	var f := FileAccess.open(dir.path_join("files-exit.txt"), FileAccess.WRITE)
	if f:
		f.store_string(str(code))
		f.close()
	print("FILES SELFTEST: %s (exit %d)" % ["PASS" if code == 0 else "FAIL", code])
	get_tree().quit(code)
