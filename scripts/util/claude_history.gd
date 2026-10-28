class_name ClaudeHistory
## Claude Code's own record of past conversations (~/.claude/projects), read
## the way Oazy Claude reads it (native/claude Transcripts), for the Start
## orb's past chats. Plain file reads: call these off the main thread.


static func config_dir() -> String:
	var d := OS.get_environment("CLAUDE_CONFIG_DIR")
	return (d if d != "" else ClaudeCli.home().path_join(".claude")).replace("\\", "/")


## Claude Code keeps a folder's conversations under its path with everything
## but letters and digits turned into dashes.
static func project_dir(cwd: String) -> String:
	var name := ""
	for ch in cwd:
		var c := ch.unicode_at(0)
		var ok := (c >= 48 and c <= 57) or (c >= 65 and c <= 90) or (c >= 97 and c <= 122)
		name += ch if ok else "-"
	return config_dir().path_join("projects").path_join(name)


## The latest conversations started in `cwd`, newest first: {id, title, at, path}.
static func recent(cwd: String, most: int = 40) -> Array[Dictionary]:
	var files := _files(project_dir(cwd))
	var match_cwd := false
	if files.is_empty():
		# Another spelling of the folder: look everywhere, keep the ones from it.
		match_cwd = true
		var root := config_dir().path_join("projects")
		for d in DirAccess.get_directories_at(root):
			files.append_array(_files(root.path_join(d)))
	files.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["at"]) > int(b["at"]))
	var want := cwd.replace("\\", "/").trim_suffix("/").to_lower()
	var out: Array[Dictionary] = []
	for f in files:
		if out.size() >= most:
			break
		var s := peek(str(f["path"]))
		if s.is_empty():
			continue
		if match_cwd and str(s["cwd"]).replace("\\", "/").trim_suffix("/").to_lower() != want:
			continue
		s["at"] = f["at"]
		s["path"] = f["path"]
		out.append(s)
	return out


static func _files(dir: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not DirAccess.dir_exists_absolute(dir):
		return out
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".jsonl"):
			var p := dir.path_join(f)
			out.append({"path": p, "at": FileAccess.get_modified_time(p)})
	return out


## {id, cwd, title} from the start of a transcript, or {} for one that isn't a
## conversation (a helper's, or empty).
static func peek(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var cwd := ""
	var title := ""
	var first := ""
	var sidechain := false
	var n := 0
	while not f.eof_reached() and n < 400 and f.get_position() < 2 * 1024 * 1024:
		var line := f.get_line()
		n += 1
		if line.contains("\"type\":\"summary\"") or line.contains("\"type\":\"custom-title\"") or line.contains("\"type\":\"ai-title\""):
			var m: Variant = JSON.parse_string(line)
			if m is Dictionary:
				for k in ["customTitle", "aiTitle", "summary"]:
					if str(m.get(k, "")) != "":
						title = str(m[k])
						break
			continue
		if first != "" and cwd != "" and n > 60:
			break
		if not line.contains("\"type\":\"user\""):
			continue
		var u: Variant = JSON.parse_string(line)
		if not u is Dictionary:
			continue
		if bool(u.get("isSidechain", false)):
			sidechain = true
			continue
		if cwd == "":
			cwd = str(u.get("cwd", ""))
		if first == "" and not bool(u.get("isMeta", false)):
			first = user_text(u)
	if (sidechain and first == "") or (first == "" and title == ""):
		return {}
	if title == "":
		title = first
	title = title.replace("\n", " ").strip_edges().left(90)
	return {"id": path.get_file().get_basename(), "cwd": cwd, "title": title}


## What you typed in a transcript's user line ("" for tool results and Claude
## Code's own notes).
static func user_text(u: Dictionary) -> String:
	var msg: Variant = u.get("message")
	if not msg is Dictionary:
		return ""
	var c: Variant = msg.get("content")
	var text := ""
	if c is String:
		text = c
	elif c is Array:
		for b in c:
			if b is Dictionary and str(b.get("type", "")) == "text":
				text = str(b.get("text", ""))
				break
	text = text.strip_edges()
	if text.begins_with("<") or text.begins_with("Caveat:") or text.begins_with("[Request interrupted"):
		return ""
	return text


## A conversation's user and assistant lines (not its helpers'), the last
## `most` of them, parsed.
static func lines(path: String, most: int = 400) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return out
	# A long conversation: the last 16 MB is plenty to read back.
	var cap := 16 * 1024 * 1024
	if f.get_length() > cap:
		f.seek(f.get_length() - cap)
		f.get_line()
	while not f.eof_reached():
		var line := f.get_line()
		if line.contains("\"isSidechain\":true"):
			continue
		if not line.contains("\"type\":\"user\"") and not line.contains("\"type\":\"assistant\""):
			continue
		var m: Variant = JSON.parse_string(line)
		if m is Dictionary and (str(m.get("type", "")) == "user" or str(m.get("type", "")) == "assistant"):
			out.append(m)
			if out.size() > most:
				out.pop_front()
	return out
