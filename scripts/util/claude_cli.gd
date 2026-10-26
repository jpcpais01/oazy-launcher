class_name ClaudeCli
extends Node
## One Claude Code conversation, run headless on this PC and signed in as you:
##
##   claude -p --input-format stream-json --output-format stream-json --verbose
##          --include-partial-messages --permission-prompt-tool stdio
##
## The same plumbing as Oazy Claude (native/claude), driven straight from
## Godot so the Start orb's assistant can be drawn in Oazy's own UI. Every JSON
## line claude prints arrives as `message`; it asks before using a tool with a
## control request, answered with `answer()`. The conversation is Claude
## Code's own (~/.claude/projects), so it resumes anywhere.

signal message(m: Dictionary)
## The process ended without being asked to: `err` is the end of its stderr.
signal exited(code: int, err: String)

## Told to Claude on top of Claude Code's own instructions.
const SYSTEM := "You are Claude, opened from the Start orb of Oazy, the desktop shell on this user's PC. This is a small assistant popup next to the taskbar, so keep replies friendly and short (a few sentences or a short list) unless the user asks for more. You start in the user's home folder. Reading is fine; anything that changes files or runs commands is shown to the user first and only happens if they allow it. Use plain Markdown."

## The folder claude runs in.
var cwd := ""
## Claude Code's session id, once it has one: the next start resumes it.
var session := ""

var _pipe: FileAccess
var _pid := 0
## Which process the lines belong to, so an old one's last words are ignored.
var _gen := 0
var _threads := {}
var _err_tail := ""
var _mutex := Mutex.new()
var _ctl := 1

static var _found := ""
static var _missed_at := -100000


func running() -> bool:
	return _pid > 0


## Starts claude for this conversation. Returns "" when it's up, "missing" if
## Claude Code isn't installed, or why it couldn't start.
func start() -> String:
	if _pid > 0:
		return ""
	var exe := find()
	if exe == "":
		return "missing"
	var args := PackedStringArray([
		"-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose",
		"--include-partial-messages", "--permission-prompt-tool", "stdio",
		# Questions come back as plain replies; their card is Claude Code's own UI.
		"--disallowedTools", "AskUserQuestion",
		"--append-system-prompt", SYSTEM,
	])
	if session != "":
		args.append_array(["--resume", session])
	var dir := cwd if cwd != "" and DirAccess.dir_exists_absolute(cwd) else home()
	var info: Dictionary
	if App.is_windows():
		# Godot can't start a process in another folder, so cmd does: Godot
		# quotes the whole line once and /s takes those quotes off again.
		var line := "cd /d %s && %s" % [_quote(dir.replace("/", "\\")), _quote(exe.replace("/", "\\"))]
		for a in args:
			line += " " + _quote(a)
		var cmd := OS.get_environment("ComSpec")
		if cmd == "":
			cmd = "C:\\Windows\\System32\\cmd.exe"
		info = OS.execute_with_pipe(cmd, PackedStringArray(["/d", "/s", "/c", line]), true)
	else:
		var sh_args := PackedStringArray(["-c", "cd \"$1\" && shift && exec \"$@\"", "sh", dir, exe])
		sh_args.append_array(args)
		info = OS.execute_with_pipe("/bin/sh", sh_args, true)
	if info.is_empty() or info.get("stdio") == null:
		return "Couldn't start Claude Code (%s)" % exe.get_file()
	_gen += 1
	_pipe = info["stdio"]
	_pid = int(info.get("pid", 0))
	_mutex.lock()
	_err_tail = ""
	_mutex.unlock()
	var out := Thread.new()
	out.start(_read_out.bind(_pipe, _gen))
	var list: Array[Thread] = [out]
	var err_pipe: Variant = info.get("stderr")
	if err_pipe is FileAccess:
		var err := Thread.new()
		err.start(_read_err.bind(err_pipe))
		list.append(err)
	_threads[_gen] = list
	return ""


## Sends what you typed.
func send_text(text: String) -> void:
	_write({"type": "user", "message": {"role": "user", "content": text}, "parent_tool_use_id": null, "session_id": session if session != "" else "default"})


## Stops the reply that's running (claude stays up for the next message).
func interrupt() -> void:
	_control({"subtype": "interrupt"})


## Answers a can_use_tool request: allowed as asked, or refused.
func answer(request_id: String, allow: bool, input: Dictionary) -> void:
	var response: Dictionary
	if allow:
		response = {"behavior": "allow", "updatedInput": input}
	else:
		response = {"behavior": "deny", "message": "The user said no to this. Don't try it again; ask what they want instead.", "interrupt": false}
	_write({"type": "control_response", "response": {"subtype": "success", "request_id": request_id, "response": response}})


## Turns down a control request this UI doesn't handle.
func refuse(request_id: String) -> void:
	_write({"type": "control_response", "response": {"subtype": "error", "request_id": request_id, "error": "Not supported in Oazy"}})


## Ends the process (and whatever it was running). Quietly: no `exited`.
func stop() -> void:
	if _pid <= 0:
		return
	var pid := _pid
	_pid = 0
	_pipe = null
	if App.is_windows():
		# The whole tree: cmd, claude and anything it started.
		OS.create_process("taskkill", PackedStringArray(["/T", "/F", "/PID", str(pid)]))
	else:
		OS.kill(pid)


func _exit_tree() -> void:
	var pid := _pid
	stop()
	if App.is_windows() and pid > 0:
		OS.execute("taskkill", PackedStringArray(["/T", "/F", "/PID", str(pid)]))
	for gen in _threads.keys():
		for t: Thread in _threads[gen]:
			t.wait_to_finish()
	_threads.clear()


func _control(request: Dictionary) -> void:
	_write({"type": "control_request", "request_id": "oazy-%d" % _ctl, "request": request})
	_ctl += 1


func _write(obj: Dictionary) -> void:
	if _pid <= 0 or _pipe == null:
		return
	_pipe.store_line(JSON.stringify(obj).replace("\n", " "))
	_pipe.flush()


func _read_out(pipe: FileAccess, gen: int) -> void:
	var buf := PackedByteArray()
	while true:
		var chunk := pipe.get_buffer(1)
		if chunk.is_empty():
			break
		var more := pipe.get_length()
		if more > 0:
			chunk.append_array(pipe.get_buffer(more))
		buf.append_array(chunk)
		var nl := buf.find(10)
		while nl >= 0:
			var line := buf.slice(0, nl).get_string_from_utf8().strip_edges()
			buf = buf.slice(nl + 1)
			if line.begins_with("{"):
				_on_line.call_deferred(line, gen)
			nl = buf.find(10)
	_on_end.call_deferred(gen)


func _read_err(pipe: FileAccess) -> void:
	while true:
		var chunk := pipe.get_buffer(1)
		if chunk.is_empty():
			break
		var more := pipe.get_length()
		if more > 0:
			chunk.append_array(pipe.get_buffer(more))
		_mutex.lock()
		_err_tail = (_err_tail + chunk.get_string_from_utf8()).right(3000)
		_mutex.unlock()


func _on_line(line: String, gen: int) -> void:
	if gen != _gen or _pid <= 0:
		return
	var data: Variant = JSON.parse_string(line)
	if data is Dictionary:
		var m: Dictionary = data
		if str(m.get("type", "")) == "system" and str(m.get("session_id", "")) != "":
			session = str(m["session_id"])
		elif str(m.get("type", "")) == "result" and str(m.get("session_id", "")) != "":
			session = str(m["session_id"])
		message.emit(m)


func _on_end(gen: int) -> void:
	var list: Array = _threads.get(gen, [])
	_threads.erase(gen)
	for t: Thread in list:
		t.wait_to_finish()
	if gen != _gen or _pid <= 0:
		return
	var code := OS.get_process_exit_code(_pid)
	_pid = 0
	_pipe = null
	_mutex.lock()
	var tail := _err_tail
	_mutex.unlock()
	exited.emit(code, tail.strip_edges())


# --- Finding Claude Code --------------------------------------------------------------------

static func home() -> String:
	var h := OS.get_environment("USERPROFILE") if App.is_windows() else OS.get_environment("HOME")
	return h.replace("\\", "/") if h != "" else OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS).get_base_dir()


## Where claude is, as Oazy Claude looks for it: one picked by hand, the
## native installer's, anything on PATH, npm / pnpm / bun / scoop / volta /
## winget, the old local install, then the Claude desktop app's own copy.
## "" if there's none.
static func find() -> String:
	if _found != "" and FileAccess.file_exists(_found):
		return _found
	# Not there a moment ago: don't walk the folders again on every open.
	if Time.get_ticks_msec() - _missed_at < 15000:
		return ""
	_found = _search()
	if _found == "":
		_missed_at = Time.get_ticks_msec()
	return _found


static func _search() -> String:
	var over := OS.get_environment("OAZY_CLAUDE")
	if over != "" and FileAccess.file_exists(over):
		return over
	if not App.is_windows():
		for dir in OS.get_environment("PATH").split(":", false):
			if FileAccess.file_exists(dir.path_join("claude")):
				return dir.path_join("claude")
		return ""
	var prefs: Variant = JSON.parse_string(FileAccess.get_file_as_string(ProjectSettings.globalize_path("user://claude/data").path_join("prefs.json")))
	if prefs is Dictionary and str(prefs.get("claudePath", "")) != "" and FileAccess.file_exists(str(prefs["claudePath"])):
		return str(prefs["claudePath"])
	var h := home()
	var roaming := OS.get_environment("APPDATA").replace("\\", "/")
	var local := OS.get_environment("LOCALAPPDATA").replace("\\", "/")
	if FileAccess.file_exists(h.path_join(".local/bin/claude.exe")):
		return h.path_join(".local/bin/claude.exe")
	var dirs := Array(OS.get_environment("PATH").split(";", false))
	dirs.append_array([
		roaming.path_join("npm"), local.path_join("pnpm"), h.path_join(".bun/bin"),
		h.path_join("scoop/shims"), local.path_join("Volta/bin"), local.path_join("Microsoft/WinGet/Links"),
		h.path_join(".claude/local"), h.path_join(".claude/local/node_modules/.bin"),
	])
	for raw in dirs:
		var dir := str(raw).strip_edges().trim_prefix("\"").trim_suffix("\"").replace("\\", "/")
		var low := dir.to_lower()
		# The Claude desktop app's folder holds Claude.exe, which isn't the CLI.
		if dir == "" or low.contains("anthropicclaude") or low.contains("windowsapps/claude"):
			continue
		for f in ["claude.exe", "claude.cmd", "claude.bat"]:
			if FileAccess.file_exists(dir.path_join(f)):
				return dir.path_join(f)
	# The Claude desktop app keeps a Claude Code of its own, one folder per
	# version: the newest.
	var roots := [roaming.path_join("Claude"), local.path_join("AnthropicClaude"), local.path_join("Claude")]
	for pkg in DirAccess.get_directories_at(local.path_join("Packages")):
		if pkg.to_lower().contains("claude"):
			roots.append(local.path_join("Packages").path_join(pkg).path_join("LocalCache/Roaming/Claude"))
	var best := {"path": "", "at": 0, "budget": 400}
	for r in roots:
		_scan(str(r), 0, best)
	return str(best["path"])


static func _scan(dir: String, depth: int, best: Dictionary) -> void:
	best["budget"] = int(best["budget"]) - 1
	if depth > 4 or int(best["budget"]) < 0 or not DirAccess.dir_exists_absolute(dir):
		return
	if dir.to_lower().contains("claude-code"):
		var p := dir.path_join("claude.exe")
		if FileAccess.file_exists(p):
			var at := FileAccess.get_modified_time(p)
			if at > int(best["at"]):
				best["path"] = p
				best["at"] = at
	for sub in DirAccess.get_directories_at(dir):
		var n := sub.to_lower()
		# Electron's own folders are big and never hold it.
		if n in ["cache", "code cache", "gpucache", "indexeddb", "local storage", "logs", "crashpad", "blob_storage", "service worker", "session storage"]:
			continue
		_scan(dir.path_join(sub), depth + 1, best)


## One argument for a Windows command line.
static func _quote(s: String) -> String:
	if s == "":
		return "\"\""
	if not (s.contains(" ") or s.contains("\t") or s.contains("\"")):
		return s
	return "\"" + s.replace("\\\"", "\\\\\"").replace("\"", "\\\"") + "\""
