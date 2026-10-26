extends Node
## Oazy Claude: Claude Code in Oazy's glass. A chat window over the Claude Code
## installed on this PC (signed in as you), run headless: your folders, your
## conversations (shared with the terminal), streamed replies, a card for every
## edit and command, and Allow / Deny when Claude asks.
##
## It lives in native/claude and is built like Oazy Terminal (see WebApp):
## compiled on first use into user://claude/app-<hash>, run as its own process,
## settings in user://claude/data. A second launch brings the window up.
## "Terminal" in its window continues a conversation in Oazy Terminal, so the
## terminal is built alongside it and handed over.

const REF := "oazy:claude"
const SRC := "res://native/claude"
const EXE := "OazyClaude.exe"
const UI := ["claude.html", "claude.css", "claude.js", "markdown.js", "icons.js"]

var _exe := ""
var _terminal := ""
var _building := false
var _queue: Array[Dictionary] = []
var _runtime := 0 # 0 unknown, 1 there, -1 missing


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--claude-selftest="):
			_selftest.call_deferred(a.get_slice("=", 1))


func data_dir() -> String:
	return ProjectSettings.globalize_path("user://claude/data")


## Opens the window (or brings it up). `opts`: cwd, a folder to start a
## conversation in; resume (+ title), a conversation to carry on.
func open(opts: Dictionary = {}) -> bool:
	if not App.is_windows():
		App.toast("Claude runs on Windows")
		return false
	if _runtime == 0 and Host.available:
		Host.request(["webview2"], func(d: Dictionary) -> void:
			if d.get("ok", false):
				_runtime = 1 if str(d.get("version", "")) != "" else -1
			_open_now(opts)
		)
		return true
	_open_now(opts)
	return true


func _open_now(opts: Dictionary) -> void:
	if _runtime == -1:
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
			App.toast("Getting Claude ready…")
	)
	WorkerThreadPool.add_task(func() -> void:
		var r := build()
		# Its Terminal button continues a conversation in Oazy Terminal.
		var t := Terminal.build()
		r["terminal"] = str(t.get("exe", ""))
		_built.call_deferred(r)
	, false, "Build Oazy Claude")


func _built(r: Dictionary) -> void:
	_building = false
	if not r.has("exe"):
		_queue.clear()
		App.toast("Couldn't start Claude: %s" % str(r.get("error", "unknown error")), &"error")
		push_warning("Oazy Claude: " + str(r.get("error", "")))
		return
	_exe = str(r["exe"])
	_terminal = str(r.get("terminal", ""))
	_flush()


func _flush() -> void:
	for q in _queue:
		var args := PackedStringArray(["--data", data_dir(), "--accent", "#" + App.accent.to_html(false)])
		if _terminal != "":
			args.append_array(["--terminal", _terminal, "--terminal-data", Terminal.data_dir()])
		if str(q.get("cwd", "")) != "":
			args.append_array(["--cwd", str(q["cwd"])])
		if str(q.get("resume", "")) != "":
			args.append_array(["--resume", str(q["resume"])])
			# Godot doesn't escape quotes inside an argument on Windows.
			var title := str(q.get("title", "")).replace("\"", "'").strip_edges()
			if title != "":
				args.append_array(["--title", title])
		if OS.create_process(_exe, args) <= 0:
			App.toast("Couldn't start Claude", &"error")
	_queue.clear()


## Unpacks and compiles the app if this version isn't there yet.
## Returns {"exe": path} or {"error": text}. Safe to call from a worker thread.
static func build() -> Dictionary:
	return WebApp.build("claude", EXE, "oazy_claude.cs", "oazy_claude.ico", files())


## Everything it needs: {path in its folder: res:// path}.
static func files() -> Dictionary:
	var files := WebApp.WEBVIEW2.duplicate()
	files.merge(WebApp.FONTS)
	files["oazy_claude.cs"] = SRC.path_join("oazy_claude.cs")
	files["oazy_claude.ico"] = SRC.path_join("oazy_claude.ico")
	for f in UI:
		files["ui/" + f] = SRC.path_join("ui").path_join(f)
	return files


## Is this real window one of Oazy Claude's?
static func owns_window(w: Dictionary) -> bool:
	return WebApp.owns_window(w, "claude", EXE)


## CI: build the app, run its self-test (the real window and page, on a
## stand-in for claude; screenshots into `dir`) and exit with its result.
func _selftest(dir: String) -> void:
	print("CLAUDE SELFTEST: building")
	var r := build()
	if not r.has("exe"):
		print("CLAUDE SELFTEST: FAIL ", r.get("error", ""))
		get_tree().quit(1)
		return
	print("CLAUDE SELFTEST: built ", r["exe"])
	var pid := OS.create_process(str(r["exe"]), ["--selftest", dir])
	if pid <= 0:
		print("CLAUDE SELFTEST: FAIL couldn't start the app")
		get_tree().quit(1)
		return
	var started := Time.get_ticks_msec()
	while OS.is_process_running(pid) and Time.get_ticks_msec() - started < 200000:
		await get_tree().create_timer(0.25).timeout
	var code := OS.get_process_exit_code(pid)
	var f := FileAccess.open(dir.path_join("claude-exit.txt"), FileAccess.WRITE)
	if f:
		f.store_string(str(code))
		f.close()
	print("CLAUDE SELFTEST: %s (exit %d)" % ["PASS" if code == 0 else "FAIL", code])
	get_tree().quit(code)
