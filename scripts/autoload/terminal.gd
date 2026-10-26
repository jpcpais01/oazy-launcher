extends Node
## Oazy Terminal: PowerShell, Command Prompt, WSL, Git Bash and Claude Code
## on Windows pseudoconsoles, drawn by xterm.js in Oazy's glass window.
##
## It lives in native/terminal and is built like Oazy Browser (see WebApp):
## compiled on first use into user://terminal/app-<hash>, run as its own
## process (closing or updating Oazy never kills your shells), settings in
## user://terminal/data. A second launch opens a tab in the running one.
##
## The Terminal icon, Command Prompt and PowerShell open here while setting
## `terminal_oazy` is on, and so does Claude Code from the library.

const REF := "oazy:terminal"
const SRC := "res://native/terminal"
const EXE := "OazyTerminal.exe"
## The page, relative to SRC/ui; fonts come from SRC/fonts.
const UI := [
	"term.html", "term.css", "term.js", "icons.js",
	"vendor/xterm.js", "vendor/xterm.css", "vendor/addon-fit.js", "vendor/addon-search.js",
	"vendor/addon-unicode11.js", "vendor/addon-web-links.js", "vendor/LICENSE-xterm.txt",
]
const FONTS := [
	"jetbrains-mono-latin-400-normal.woff2", "jetbrains-mono-latin-700-normal.woff2",
	"jetbrains-mono-latin-ext-400-normal.woff2", "jetbrains-mono-latin-ext-700-normal.woff2",
	"jetbrains-mono-latin-400-italic.woff2",
]

var _exe := ""
var _building := false
var _queue: Array[Dictionary] = []
var _runtime := 0 # 0 unknown, 1 there, -1 missing


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--terminal-selftest="):
			_selftest.call_deferred(a.get_slice("=", 1))


func data_dir() -> String:
	return ProjectSettings.globalize_path("user://terminal/data")


## Whether shells should open in Oazy Terminal rather than their own windows.
func enabled() -> bool:
	return App.is_windows() and bool(Settings.get_value("terminal_oazy"))


## Opens a tab. `opts`: profile (pwsh, powershell, cmd, wsl:<distro>, gitbash,
## claude), run (a command line of its own), cwd, title, new_window.
## `fallback` runs instead if Oazy Terminal can't (no WebView2).
func open(opts: Dictionary = {}, fallback: Callable = Callable()) -> bool:
	if not App.is_windows():
		App.toast("Oazy Terminal runs on Windows")
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
			App.toast("Getting Oazy Terminal ready…")
	)
	WorkerThreadPool.add_task(func() -> void:
		var r := build()
		_built.call_deferred(r)
	, false, "Build Oazy Terminal")


func _built(r: Dictionary) -> void:
	_building = false
	if not r.has("exe"):
		_queue.clear()
		App.toast("Couldn't start Oazy Terminal: %s" % str(r.get("error", "unknown error")), &"error")
		push_warning("Oazy Terminal: " + str(r.get("error", "")))
		return
	_exe = str(r["exe"])
	_flush()


func _flush() -> void:
	for q in _queue:
		var args := PackedStringArray(["--data", data_dir(), "--accent", "#" + App.accent.to_html(false)])
		for k in ["profile", "run", "cwd", "title"]:
			if str(q.get(k, "")) != "":
				args.append_array(["--" + k, str(q[k])])
		if q.get("new_window", false):
			args.append("--new-window")
		if OS.create_process(_exe, args) <= 0:
			App.toast("Couldn't start Oazy Terminal", &"error")
	_queue.clear()


## Unpacks and compiles the terminal if this version isn't there yet.
## Returns {"exe": path} or {"error": text}. Safe to call from a worker thread.
static func build() -> Dictionary:
	return WebApp.build("terminal", EXE, "oazy_terminal.cs", "oazy_terminal.ico", files())


## Everything the terminal needs: {path in its folder: res:// path}.
static func files() -> Dictionary:
	var files := WebApp.WEBVIEW2.duplicate()
	files.merge(WebApp.FONTS)
	files["oazy_terminal.cs"] = SRC.path_join("oazy_terminal.cs")
	files["oazy_terminal.ico"] = SRC.path_join("oazy_terminal.ico")
	files["OFL-JetBrainsMono.txt"] = SRC.path_join("fonts/OFL-JetBrainsMono.txt")
	for f in UI:
		files["ui/" + f] = SRC.path_join("ui").path_join(f)
	# Shipped as .bin so Godot packs them untouched instead of importing them.
	for f in FONTS:
		files["ui/fonts/" + f] = SRC.path_join("fonts").path_join(f + ".bin")
	return files


## Is this real window one of Oazy Terminal's?
static func owns_window(w: Dictionary) -> bool:
	return WebApp.owns_window(w, "terminal", EXE)


## The profile a Windows shell app (Terminal, Command Prompt, PowerShell)
## opens as here, or "-" when it isn't one Oazy Terminal takes over.
static func profile_for(it: Dictionary) -> String:
	var name := str(it.get("name", "")).to_lower()
	if name.contains("ise") or name.contains("developer"):
		return "-"
	var id := (str(it.get("ref", "")) + "|" + str(it.get("icon_key", "")) + "|").to_lower().replace("\\", "/")
	if id.contains("windowsterminal") or id.contains("/wt.exe|") or name in ["terminal", "windows terminal"]:
		return ""
	if id.contains("/cmd.exe|") or name == "command prompt":
		return "cmd"
	if id.contains("/pwsh.exe|") or name.begins_with("powershell 7"):
		return "pwsh"
	if id.contains("/powershell.exe|") or name == "windows powershell" or name == "powershell":
		return "powershell"
	return "-"


## The shells a library entry can be (cmd.exe /k claude and the like).
static func runs_shell(path: String) -> bool:
	return path.replace("\\", "/").get_file().to_lower() in ["cmd.exe", "powershell.exe", "pwsh.exe", "wt.exe"]


## CI: build the terminal, run its self-test (real ConPTY and WebView2,
## screenshots into `dir`) and exit with its result.
func _selftest(dir: String) -> void:
	print("TERMINAL SELFTEST: building")
	var r := build()
	if not r.has("exe"):
		print("TERMINAL SELFTEST: FAIL ", r.get("error", ""))
		get_tree().quit(1)
		return
	print("TERMINAL SELFTEST: built ", r["exe"])
	var pid := OS.create_process(str(r["exe"]), ["--selftest", dir])
	if pid <= 0:
		print("TERMINAL SELFTEST: FAIL couldn't start the terminal")
		get_tree().quit(1)
		return
	var started := Time.get_ticks_msec()
	while OS.is_process_running(pid) and Time.get_ticks_msec() - started < 200000:
		await get_tree().create_timer(0.25).timeout
	var code := OS.get_process_exit_code(pid)
	var f := FileAccess.open(dir.path_join("terminal-exit.txt"), FileAccess.WRITE)
	if f:
		f.store_string(str(code))
		f.close()
	print("TERMINAL SELFTEST: %s (exit %d)" % ["PASS" if code == 0 else "FAIL", code])
	get_tree().quit(code)
