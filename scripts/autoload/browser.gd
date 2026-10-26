extends Node
## Oazy Browser: Chromium (the WebView2 runtime that comes with Windows 11)
## in Oazy's own glass window, with Oazy's tabs, address bar and new tab page.
##
## It lives in native/browser: a C# 5 program plus its HTML chrome and the two
## WebView2 SDK DLLs. Like the shell companion it's compiled on first use with
## the csc.exe that ships with Windows, into user://browser/app-<hash>, so
## Oazy stays a single exe. The browser runs as its own process (closing or
## updating Oazy never takes your tabs with it) and keeps its profile in
## user://browser/data. A second launch hands the url to the running one.

## Emitted when the WebView2 runtime is missing, so the shell can explain.
signal runtime_missing

const REF := "oazy:browser"
const SRC := "res://native/browser"
const EXE := "OazyBrowser.exe"
## Everything the browser needs next to its exe, relative to SRC.
const FILES := [
	"oazy_browser.cs",
	"oazy_browser.ico",
	"bin/Microsoft.Web.WebView2.Core.dll",
	"bin/WebView2Loader.dll",
	"bin/LICENSE.txt",
	"ui/chrome.html",
	"ui/chrome.css",
	"ui/chrome.js",
	"ui/common.css",
	"ui/icons.js",
	"ui/newtab.html",
]
const RUNTIME_URL := "https://go.microsoft.com/fwlink/p/?LinkId=2124703"

var _exe := ""
var _building := false
var _queue: Array = []
var _runtime_checked := false


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--browser-selftest="):
			_selftest.call_deferred(a.get_slice("=", 1))


func data_dir() -> String:
	return ProjectSettings.globalize_path("user://browser/data")


## Opens `url` (or a new window when empty) in Oazy Browser. Returns false
## when it can't run here.
func open(url: String = "", new_window: bool = false) -> bool:
	if not App.is_windows():
		if url != "":
			OS.shell_open(url)
		else:
			App.toast("Oazy Browser runs on Windows")
		return false
	if not _runtime_checked and Host.available:
		Host.request(["webview2"], func(d: Dictionary) -> void:
			_runtime_checked = d.get("ok", false)
			if d.get("ok", false) and str(d.get("version", "")) == "":
				_runtime_checked = false
				runtime_missing.emit()
			else:
				_open_now(url, new_window)
		)
		return true
	_open_now(url, new_window)
	return true


## Whether web links from Start should open here rather than the default browser.
func handles_links() -> bool:
	return App.is_windows() and bool(Settings.get_value("browser_links"))


func _open_now(url: String, new_window: bool) -> void:
	_queue.append([url, new_window])
	if _exe != "":
		_flush()
		return
	if _building:
		return
	_building = true
	var slow := get_tree().create_timer(0.8)
	slow.timeout.connect(func() -> void:
		if _building:
			App.toast("Getting Oazy Browser ready…")
	)
	WorkerThreadPool.add_task(func() -> void:
		var r := build()
		_built.call_deferred(r)
	, false, "Build Oazy Browser")


func _built(r: Dictionary) -> void:
	_building = false
	if not r.has("exe"):
		_queue.clear()
		App.toast("Couldn't start Oazy Browser: %s" % str(r.get("error", "unknown error")), &"error")
		push_warning("Oazy Browser: " + str(r.get("error", "")))
		return
	_exe = str(r["exe"])
	_flush()


func _flush() -> void:
	for q in _queue:
		var args := PackedStringArray(["--data", data_dir(), "--accent", "#" + App.accent.to_html(false)])
		if q[1]:
			args.append("--new-window")
		if str(q[0]) != "":
			args.append(str(q[0]))
		if OS.create_process(_exe, args) <= 0:
			App.toast("Couldn't start Oazy Browser", &"error")
	_queue.clear()


## Unpacks and compiles the browser if this version isn't there yet. Returns
## {"exe": path} or {"error": text}. Safe to call from a worker thread.
static func build() -> Dictionary:
	var hashes := PackedStringArray()
	var blobs := {}
	for f in FILES:
		var bytes := FileAccess.get_file_as_bytes(SRC.path_join(f))
		if bytes.is_empty():
			return {"error": "%s is missing from the package" % f}
		blobs[f] = bytes
		hashes.append(f + ":" + _md5(bytes))
	var key := "\n".join(hashes).md5_text().substr(0, 10)
	var root := ProjectSettings.globalize_path("user://browser")
	var dir := root.path_join("app-" + key)
	var exe := dir.path_join(EXE)
	if FileAccess.file_exists(exe):
		return {"exe": exe}
	for f in FILES:
		var path := dir.path_join(f.trim_prefix("bin/"))
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		var out := FileAccess.open(path, FileAccess.WRITE)
		if out == null:
			return {"error": "Can't write to %s" % dir}
		out.store_buffer(blobs[f])
		out.close()
	var log := ""
	for csc in Host.CSC:
		if not FileAccess.file_exists(csc):
			continue
		var out := []
		var w := func(p: String) -> String: return dir.path_join(p).replace("/", "\\")
		var args := ["/nologo", "/optimize+", "/target:winexe", "/platform:x64",
			"/win32icon:" + w.call("oazy_browser.ico"),
			"/r:System.dll", "/r:System.Core.dll", "/r:System.Drawing.dll", "/r:System.Windows.Forms.dll", "/r:System.Web.Extensions.dll",
			"/r:" + w.call("Microsoft.Web.WebView2.Core.dll"),
			"/out:" + w.call(EXE + ".tmp"), w.call("oazy_browser.cs")]
		var code := OS.execute(csc, args, out, true)
		if code == 0 and FileAccess.file_exists(dir.path_join(EXE + ".tmp")):
			DirAccess.rename_absolute(dir.path_join(EXE + ".tmp"), exe)
			_clean_old(root, "app-" + key)
			return {"exe": exe}
		log = "\n".join(out).strip_edges().substr(0, 600)
	if log == "":
		return {"error": "The .NET Framework C# compiler wasn't found"}
	return {"error": "build failed: " + log}


static func _md5(bytes: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_MD5)
	ctx.update(bytes)
	return ctx.finish().hex_encode()


## Older builds go, unless a browser from one is still running (its files are locked).
static func _clean_old(root: String, keep: String) -> void:
	for d in DirAccess.get_directories_at(root):
		if not d.begins_with("app-") or d == keep:
			continue
		var path := root.path_join(d)
		if DirAccess.remove_absolute(path.path_join(EXE)) != OK and FileAccess.file_exists(path.path_join(EXE)):
			continue
		_remove_tree(path)


static func _remove_tree(path: String) -> void:
	for f in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(f))
	for d in DirAccess.get_directories_at(path):
		_remove_tree(path.path_join(d))
	DirAccess.remove_absolute(path)


## Is this real window one of Oazy Browser's?
static func owns_window(w: Dictionary) -> bool:
	var exe := str(w.get("exe", "")).replace("\\", "/").to_lower()
	return exe.get_file() == EXE.to_lower() and exe.contains("/browser/app-")


## CI: build the browser, run its self-test (real WebView2, screenshots into
## `dir`) and exit with its result.
func _selftest(dir: String) -> void:
	print("BROWSER SELFTEST: building")
	var r := build()
	if not r.has("exe"):
		print("BROWSER SELFTEST: FAIL ", r.get("error", ""))
		get_tree().quit(1)
		return
	print("BROWSER SELFTEST: built ", r["exe"])
	# Don't block the main thread for the whole run: start it and poll.
	var pid := OS.create_process(str(r["exe"]), ["--selftest", dir])
	if pid <= 0:
		print("BROWSER SELFTEST: FAIL couldn't start the browser")
		get_tree().quit(1)
		return
	var started := Time.get_ticks_msec()
	while OS.is_process_running(pid) and Time.get_ticks_msec() - started < 200000:
		await get_tree().create_timer(0.25).timeout
	var code := OS.get_process_exit_code(pid)
	var f := FileAccess.open(dir.path_join("browser-exit.txt"), FileAccess.WRITE)
	if f:
		f.store_string(str(code))
		f.close()
	print("BROWSER SELFTEST: %s (exit %d)" % ["PASS" if code == 0 else "FAIL", code])
	get_tree().quit(code)
