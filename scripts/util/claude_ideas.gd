class_name ClaudeIdeas
extends Node
## Claude's own thoughts: every so often, hidden in the background, Claude
## picks one of your GitHub projects at random, pulls its latest version,
## reads it and comes up with one idea for it, short enough for the avatar to
## say from the roof of the orb popup.
##
## It's the same Claude Code that runs the popup, on this PC and signed in as
## you, just headless: Sonnet at medium effort, read-only tools, nothing saved
## to your past chats. A run starts 5 to 20 minutes (at random) after the last
## idea was seen, never while one is still waiting for you, so an idea you
## haven't looked at yet costs nothing more. Off with setting "claude_ideas".

## A new idea is waiting to be seen: {idea, why, repo, path, at}.
signal arrived(idea: Dictionary)

const MODEL := "claude-sonnet-5-5"
const EFFORT := "medium"
const MIN_WAIT := 5.0 * 60.0
const MAX_WAIT := 20.0 * 60.0
## A run that takes longer than this is stopped (and tried again later).
const TIMEOUT := 8.0 * 60.0
## Your project list is asked for again after this long.
const LIST_AGE := 6 * 3600
const DIR := "user://claude/ideas"

const PROMPT := """You are Claude, living as a small avatar in Oazy, the desktop shell on your user's PC. Now and then you quietly look at one of their projects and share one idea, like a friend who just had a thought. This time it's their GitHub project %s, checked out at its latest version in the current folder.

Take your time and really get to know it: the README, how it's laid out, several of the main source files, and recent changes (CHANGELOG, patch notes, TODOs) if there are any. Pick a corner of it to look at closely, so your ideas don't always land in the same place. Then come up with ONE idea: a new feature, a real improvement, something delightful, a clever simplification or a bug worth fixing. It can be as big or as small as you like, but it must be specific to this project, something they'd be glad to hear and haven't obviously done already. Avoid generic advice (add tests, write docs, refactor, add CI, improve error handling) unless the code makes a striking case for it.

Answer with only this JSON, nothing before or after it:
{"idea": "...", "why": "..."}

"idea" is what you say out loud: about 10 words (never more than 14), plain and friendly, no quotes, no Markdown, no project name, ending without a full stop. "why" is two or three sentences on what you mean and where in the code it would go, for when they ask you about it.
%s"""

var mock := false
## The idea waiting for you (or the last one, once seen); {} when there's none.
var current := {}

var _timer: Timer
var _running := false
## What's running out of sight right now.
var _pids: Array[int] = []


func _ready() -> void:
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.timeout.connect(_run)
	add_child(_timer)
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(DIR.path_join("idea.json")))
	if saved is Dictionary and str(saved.get("idea", "")) != "":
		current = saved
	Settings.changed.connect(func(key: String, _v: Variant) -> void:
		if key == "claude_ideas":
			_schedule()
	)
	_schedule()


## An idea is waiting that you haven't seen yet.
func waiting() -> bool:
	return not current.is_empty() and not bool(current.get("seen", false))


## You've seen it: the next one comes 5 to 20 minutes from now.
func seen() -> void:
	if not waiting():
		return
	current["seen"] = true
	_save()
	_schedule()


## You're done with it (dismissed, or asked about it): it won't show again.
func clear() -> void:
	var was_waiting := waiting()
	current = {}
	_save()
	if was_waiting:
		_schedule()


func _schedule() -> void:
	_timer.stop()
	if mock or waiting() or _running or not bool(Settings.get_value("claude_ideas")):
		return
	_timer.start(randf_range(MIN_WAIT, MAX_WAIT))


func _save() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var f := FileAccess.open(DIR.path_join("idea.json"), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(current))


func _exit_tree() -> void:
	_kill()


func _kill(pid: int = 0) -> void:
	for p in ([pid] if pid > 0 else _pids.duplicate()):
		if App.is_windows():
			OS.execute("taskkill", PackedStringArray(["/T", "/F", "/PID", str(p)]))
		else:
			OS.kill(p)
		_pids.erase(p)


# --- One run ---------------------------------------------------------------------------------

func _run() -> void:
	if mock or _running or waiting() or not bool(Settings.get_value("claude_ideas")):
		return
	var claude := ClaudeCli.find()
	var git := _find_git()
	if claude == "" or git == "":
		_schedule()
		return
	_running = true
	var got := await _think(claude, git)
	_running = false
	if not is_inside_tree():
		return
	if got.is_empty():
		_schedule()
		return
	current = got
	_save()
	arrived.emit(current)


## The whole thing: pick a project, bring it up to date, ask Claude. {} if
## any step didn't work out.
func _think(claude: String, git: String) -> Dictionary:
	var dir := ProjectSettings.globalize_path(DIR)
	DirAccess.make_dir_recursive_absolute(dir)
	var gh := _find_gh()
	var skip: Array = Settings.get_value("claude_projects_skip")
	var repos := (await _repos(gh)).filter(func(r: String) -> bool: return not skip.has(r))
	if repos.is_empty():
		return {}
	var last := str(current.get("repo", ""))
	if repos.size() > 1:
		repos.erase(last)
	var repo: String = repos.pick_random()
	var path := dir.path_join("repos").path_join(repo.replace("/", "__"))

	# The latest version: a shallow copy kept between runs, only ever pulled.
	var git_args := PackedStringArray(["-c", "core.longpaths=true"])
	if gh != "":
		# Private projects sign in through the GitHub CLI, never a prompt.
		git_args.append_array(["-c", "credential.helper=", "-c", "credential.helper=!\"%s\" auth git-credential" % gh.replace("\\", "/")])
	var env := {"GIT_TERMINAL_PROMPT": "0", "GCM_INTERACTIVE": "never"}
	if DirAccess.dir_exists_absolute(path.path_join(".git")):
		var a := git_args.duplicate()
		a.append_array(["fetch", "--depth", "1", "--quiet", "origin", "HEAD"])
		if await _exec(path, git, a, env, "", 240.0) != 0:
			return {}
		a = git_args.duplicate()
		a.append_array(["reset", "--hard", "--quiet", "FETCH_HEAD"])
		if await _exec(path, git, a, env, "", 60.0) != 0:
			return {}
	else:
		_remove(path)
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		var a := git_args.duplicate()
		a.append_array(["clone", "--depth", "1", "--quiet", "https://github.com/%s.git" % repo, path])
		if await _exec(path.get_base_dir(), git, a, env, "", 300.0) != 0:
			_remove(path)
			return {}

	var before := ""
	if not current.is_empty():
		before = "\nYour last idea (for %s) was: %s. Make this one different." % [last, current.get("idea", "")]
	var prompt_file := dir.path_join("prompt.txt")
	var f := FileAccess.open(prompt_file, FileAccess.WRITE)
	if f == null:
		return {}
	f.store_string(PROMPT % [repo, before])
	f.close()
	var out_file := dir.path_join("out.json")
	DirAccess.remove_absolute(out_file)
	var args := PackedStringArray([
		"-p", "--model", MODEL, "--effort", EFFORT, "--output-format", "json",
		"--tools", "Read,Glob,Grep", "--strict-mcp-config", "--no-session-persistence",
		"--max-turns", "40",
	])
	var cenv := {}
	if ClaudeCli.drop_api_key():
		cenv["ANTHROPIC_API_KEY"] = ""
	if await _exec(path, claude, args, cenv, prompt_file, TIMEOUT, out_file) != 0:
		return {}
	var res: Variant = JSON.parse_string(FileAccess.get_file_as_string(out_file))
	if not res is Dictionary or bool(res.get("is_error", false)):
		return {}
	var said := _parse(str(res.get("result", "")))
	if said.is_empty():
		return {}
	said["repo"] = repo
	said["path"] = path
	said["at"] = int(Time.get_unix_time_from_system())
	return said


## {idea, why} from Claude's answer, tidied; {} if it didn't say one.
static func _parse(text: String) -> Dictionary:
	var a := text.find("{")
	var b := text.rfind("}")
	if a < 0 or b <= a:
		return {}
	var data: Variant = JSON.parse_string(text.substr(a, b - a + 1))
	if not data is Dictionary:
		return {}
	var idea := str(data.get("idea", "")).replace("\n", " ").strip_edges().trim_suffix(".").strip_edges()
	idea = idea.trim_prefix("\"").trim_suffix("\"")
	if idea == "":
		return {}
	var words := idea.split(" ", false)
	if words.size() > 18:
		idea = " ".join(words.slice(0, 18)) + "…"
	return {"idea": idea, "why": str(data.get("why", "")).strip_edges()}


## Your GitHub projects ("owner/name"), for the popup's project picker.
## `fresh` asks GitHub again instead of using the list from the last hours.
func projects(fresh: bool = false) -> Array:
	if mock:
		return ["jpcpais01/oazy-launcher", "jpcpais01/hyperliquid-bot", "jpcpais01/portfolio", "jpcpais01/flow"]
	if fresh:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR).path_join("repos.json"))
	var list := await _repos(_find_gh())
	list.sort_custom(func(a: String, b: String) -> bool: return a.to_lower() < b.to_lower())
	return list


## Your GitHub projects, "owner/name": everything the GitHub CLI can see
## (private ones too) when it's signed in, otherwise the public ones of
## whoever Oazy belongs to. Asked for every few hours, kept in between.
func _repos(gh: String) -> Array:
	DirAccess.make_dir_recursive_absolute(DIR)
	var cache_file := DIR.path_join("repos.json")
	var cached: Variant = JSON.parse_string(FileAccess.get_file_as_string(cache_file))
	if cached is Dictionary and Time.get_unix_time_from_system() - float(cached.get("at", 0)) < LIST_AGE and cached.get("repos") is Array and not cached["repos"].is_empty():
		return cached["repos"].duplicate()
	var list: Array = []
	if gh != "":
		var out_file := ProjectSettings.globalize_path(DIR).path_join("gh.json")
		DirAccess.remove_absolute(out_file)
		var args := PackedStringArray(["repo", "list", "--limit", "200", "--no-archived", "--source", "--json", "nameWithOwner,isEmpty"])
		if await _exec(ProjectSettings.globalize_path(DIR), gh, args, {"GH_PROMPT_DISABLED": "1"}, "", 60.0, out_file) == 0:
			var got: Variant = JSON.parse_string(FileAccess.get_file_as_string(out_file))
			if got is Array:
				for r in got:
					if r is Dictionary and not bool(r.get("isEmpty", false)):
						list.append(str(r.get("nameWithOwner", "")))
	if list.is_empty():
		list = await _public_repos(App.REPO.get_slice("/", 0))
	list = list.filter(func(r: String) -> bool: return r.contains("/"))
	if list.is_empty():
		# Offline or rate limited: an older list still does.
		if cached is Dictionary and cached.get("repos") is Array:
			return cached["repos"].duplicate()
		return []
	DirAccess.make_dir_recursive_absolute(DIR)
	var f := FileAccess.open(cache_file, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"at": int(Time.get_unix_time_from_system()), "repos": list}))
	return list


func _public_repos(owner: String) -> Array:
	var http := HTTPRequest.new()
	http.timeout = 20.0
	add_child(http)
	var url := "https://api.github.com/users/%s/repos?per_page=100&sort=pushed&type=owner" % owner
	var list: Array = []
	if http.request(url, PackedStringArray(["Accept: application/vnd.github+json", "User-Agent: Oazy"])) == OK:
		var r: Array = await http.request_completed
		if int(r[0]) == HTTPRequest.RESULT_SUCCESS and int(r[1]) == 200:
			var got: Variant = JSON.parse_string((r[3] as PackedByteArray).get_string_from_utf8())
			if got is Array:
				for repo in got:
					if repo is Dictionary and not bool(repo.get("archived", false)) and not bool(repo.get("fork", false)) and int(repo.get("size", 0)) > 0:
						list.append(str(repo.get("full_name", "")))
	http.queue_free()
	return list


# --- Running things out of sight ---------------------------------------------------------------

## Runs `exe args` in `dir` with no window, `stdin` fed from a file and stdout
## saved to `out` when given. Waits for it (up to `limit` seconds, then stops
## it) and returns its exit code, or -1.
func _exec(dir: String, exe: String, args: PackedStringArray, env: Dictionary, stdin: String, limit: float, out: String = "") -> int:
	var pid := 0
	if App.is_windows():
		var line := "cd /d %s" % ClaudeCli._quote(dir.replace("/", "\\"))
		for k in env:
			line = "set \"%s=%s\" && " % [k, env[k]] + line
		line += " && " + ClaudeCli._quote(exe.replace("/", "\\"))
		for a in args:
			line += " " + ClaudeCli._quote(a)
		line += " < " + (ClaudeCli._quote(stdin.replace("/", "\\")) if stdin != "" else "NUL")
		line += " > " + (ClaudeCli._quote(out.replace("/", "\\")) if out != "" else "NUL") + " 2> NUL"
		var cmd := OS.get_environment("ComSpec")
		if cmd == "":
			cmd = "C:\\Windows\\System32\\cmd.exe"
		pid = OS.create_process(cmd, PackedStringArray(["/d", "/s", "/c", line]))
	else:
		var script := ""
		for k in env:
			script += ("unset %s; " % k) if str(env[k]) == "" else "export %s='%s'; " % [k, str(env[k])]
		script += "cd \"$1\" && in=\"$2\" && out=\"$3\" && shift 3 && exec \"$@\" < \"$in\" > \"$out\" 2> /dev/null"
		var sh_args := PackedStringArray(["-c", script, "sh", dir, stdin if stdin != "" else "/dev/null", out if out != "" else "/dev/null", exe])
		sh_args.append_array(args)
		pid = OS.create_process("/bin/sh", sh_args)
	if pid <= 0:
		return -1
	_pids.append(pid)
	var waited := 0.0
	while OS.is_process_running(pid):
		await get_tree().create_timer(0.5, true, false, true).timeout
		if not is_inside_tree():
			return -1
		waited += 0.5
		if waited > limit:
			_kill(pid)
			return -1
	_pids.erase(pid)
	return OS.get_process_exit_code(pid)


static func _remove(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for d in DirAccess.get_directories_at(path):
		_remove(path.path_join(d))
	for f in DirAccess.get_files_at(path):
		# Git keeps its objects read-only, which stops a plain delete on Windows.
		FileAccess.set_read_only_attribute(path.path_join(f), false)
		DirAccess.remove_absolute(path.path_join(f))
	DirAccess.remove_absolute(path)


static func _find_git() -> String:
	return _find_tool("git", [
		"C:/Program Files/Git/cmd/git.exe",
		OS.get_environment("LOCALAPPDATA").replace("\\", "/").path_join("Programs/Git/cmd/git.exe"),
	])


static func _find_gh() -> String:
	return _find_tool("gh", [
		"C:/Program Files/GitHub CLI/gh.exe",
		OS.get_environment("LOCALAPPDATA").replace("\\", "/").path_join("Programs/GitHub CLI/gh.exe"),
	])


static func _find_tool(name: String, extra: Array) -> String:
	var sep := ";" if App.is_windows() else ":"
	var file := name + (".exe" if App.is_windows() else "")
	for raw in OS.get_environment("PATH").split(sep, false):
		var dir := str(raw).strip_edges().trim_prefix("\"").trim_suffix("\"").replace("\\", "/")
		if dir != "" and FileAccess.file_exists(dir.path_join(file)):
			return dir.path_join(file)
	if App.is_windows():
		for p in extra:
			if FileAccess.file_exists(str(p)):
				return str(p)
	return ""
