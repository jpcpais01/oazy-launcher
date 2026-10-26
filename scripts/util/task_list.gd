class_name TaskList
## Turns the companion's process list into what the task manager shows: one
## row per app (its windows plus every process it started), the rest grouped
## by program into Background (yours) and Windows (the system's).

## Windows can't run without these: no End button, and the companion refuses too.
const CRITICAL := ["system", "registry", "smss.exe", "csrss.exe", "wininit.exe", "winlogon.exe", "services.exe", "lsass.exe", "lsaiso.exe", "memory compression", "secure system", "dwm.exe", "fontdrvhost.exe", "svchost.exe", "sihost.exe", "ctfmon.exe", "audiodg.exe", "explorer.exe", "msmpeng.exe", "nissrv.exe", "securityhealthservice.exe", "spoolsv.exe", "wudfhost.exe", "conhost.exe", "applicationframehost.exe", "textinputhost.exe", "startmenuexperiencehost.exe", "shellexperiencehost.exe"]
## Their windows are closed politely instead: the process is shared (UWP
## frames) or is the Windows shell itself (File Explorer).
const CLOSE_ONLY := ["explorer.exe", "applicationframehost.exe"]
## Apps where ending loses unsaved work: End asks first.
const RISKY := ["winword.exe", "excel.exe", "powerpnt.exe", "onenote.exe", "outlook.exe", "msaccess.exe", "notepad.exe", "notepad++.exe", "wordpad.exe", "mspaint.exe", "code.exe", "cursor.exe", "devenv.exe", "sublime_text.exe", "idea64.exe", "pycharm64.exe", "rider64.exe", "webstorm64.exe", "studio64.exe", "photoshop.exe", "illustrator.exe", "indesign.exe", "afterfx.exe", "adobe premiere pro.exe", "lightroom.exe", "blender.exe", "gimp-2.10.exe", "gimp.exe", "krita.exe", "inkscape.exe", "audacity.exe", "resolve.exe", "unity.exe", "unrealeditor.exe", "obs64.exe", "fl64.exe", "ableton live 12 suite.exe", "acad.exe", "sketchup.exe", "affinity photo 2.exe", "affinity designer 2.exe", "obsidian.exe", "notion.exe"]


## {apps, background, system: [group], cpu, mem_used, mem_total, count}.
## A group: {key, ref, item, name, sub, exe, pids, cpu, mem, windows,
## section, protected, risky, close_only}.
static func build(snap: Dictionary, windows: Array) -> Dictionary:
	var procs: Array = snap.get("procs", [])
	var self_pid := int(snap.get("self", OS.get_process_id()))
	var by_pid := {}
	for p in procs:
		by_pid[int(p["pid"])] = p
	var groups := {}
	var order: Array[String] = []
	# Apps first: every process that owns a window starts (or joins) its app's group.
	var roots := {}
	for w in windows:
		var pid := int(w.get("pid", 0))
		var ref := Catalog.ref_for_window(w)
		var file := str(w.get("exe", "")).replace("\\", "/").get_file().to_lower()
		var g := _group(groups, order, "ref:" + ref)
		if g["ref"] == "":
			g["ref"] = ref
			g["item"] = Catalog.item(ref)
			g["name"] = str(g["item"].get("name", ""))
			if ref.begins_with("win:") or g["name"] == "":
				g["name"] = Catalog.window_group_name(w)
			g["exe"] = str(w.get("exe", ""))
			g["section"] = "apps"
		g["windows"].append(w)
		if file in CLOSE_ONLY:
			g["close_only"] = true
			continue
		if by_pid.has(pid) and not roots.has(pid):
			roots[pid] = g["key"]
		if file in RISKY or _unsaved_title(str(w.get("title", ""))):
			g["risky"] = true
	# Programs that also run in the background join their app (Discord's main
	# process, Spotify's helpers), matched by exe.
	var app_exes := {}
	for k in order:
		var g: Dictionary = groups[k]
		if not g["close_only"] and g["exe"] != "":
			app_exes[str(g["exe"]).to_lower()] = k
	for p in procs:
		var pid := int(p["pid"])
		var key := ""
		if pid == self_pid:
			key = "oazy"
		else:
			key = _root_of(p, by_pid, roots, self_pid)
		var exe := str(p.get("exe", ""))
		if key == "" and app_exes.has(exe.to_lower()) and int(p.get("s", 0)) != 0:
			key = app_exes[exe.to_lower()]
		if key == "" and _under(p, by_pid, self_pid):
			key = "oazy"
		var name := str(p.get("n", "")).to_lower()
		if key == "":
			key = "exe:" + (exe.to_lower() if exe != "" else name)
		var g := _group(groups, order, key)
		if g["section"] == "":
			_fill_program(g, p, key == "oazy")
		g["pids"].append(pid)
		g["cpu"] = float(g["cpu"]) + float(p.get("cpu", 0.0))
		g["mem"] = float(g["mem"]) + float(p.get("mem", 0))
		if name in CRITICAL and g["section"] != "apps":
			g["protected"] = true
	var out := {"apps": [], "background": [], "system": [], "count": procs.size(),
		"cpu": float(snap.get("cpu", -1.0)), "mem_used": float(snap.get("mem_used", 0)), "mem_total": float(snap.get("mem_total", 0))}
	for k in order:
		var g: Dictionary = groups[k]
		# A window whose process isn't listed (it just closed) leaves nothing to show.
		if g["section"] == "apps" and g["pids"].is_empty() and not g["close_only"]:
			continue
		if g["section"] == "apps":
			var n: int = g["windows"].size()
			var extra: int = g["pids"].size()
			g["sub"] = ("%d windows" % n if n > 1 else str(g["windows"][0].get("title", "")))
			if extra > 1:
				g["sub"] = "%d processes · %s" % [extra, g["sub"]] if n > 1 else "%d processes" % extra
		elif g["pids"].size() > 1:
			g["sub"] = "%d processes" % g["pids"].size()
		out[g["section"]].append(g)
	return out


static func _group(groups: Dictionary, order: Array[String], key: String) -> Dictionary:
	if not groups.has(key):
		groups[key] = {"key": key, "ref": "", "item": {}, "name": "", "sub": "", "exe": "", "pids": [], "cpu": 0.0, "mem": 0.0,
			"windows": [], "section": "", "protected": false, "risky": false, "close_only": false}
		order.append(key)
	return groups[key]


## A background program's look: its description (or file name) and exe icon.
static func _fill_program(g: Dictionary, p: Dictionary, oazy: bool) -> void:
	var exe := str(p.get("exe", ""))
	var name := str(p.get("n", ""))
	g["exe"] = exe
	g["ref"] = "win:" + exe if exe != "" else ""
	g["item"] = Catalog.item(g["ref"]) if exe != "" else {"name": name, "kind": "window", "glyph": "cpu", "icon_key": ""}
	var desc := str(p.get("d", "")).strip_edges()
	g["name"] = "Oazy" if oazy else (desc if desc != "" else Fmt.pretty_name(name))
	g["item"]["name"] = g["name"]
	if g["item"].get("icon_key", "") == "":
		g["item"]["glyph"] = "cpu"
	g["sub"] = name if desc != "" and not oazy else ""
	var win_dir := exe.replace("\\", "/").to_lower().begins_with("c:/windows/")
	g["section"] = "background" if oazy or (int(p.get("s", 0)) != 0 and exe != "" and not win_dir) else "system"
	if oazy:
		g["protected"] = true


## The app whose window-owning process started this one, if any. Oazy and
## Explorer launch everything, so they never pull what they start into a group.
static func _root_of(p: Dictionary, by_pid: Dictionary, roots: Dictionary, self_pid: int) -> String:
	var q := p
	for _i in 24:
		var pid := int(q["pid"])
		if roots.has(pid):
			return roots[pid]
		var ppid := int(q.get("ppid", 0))
		if ppid == self_pid or not by_pid.has(ppid) or ppid == pid:
			return ""
		var parent: Dictionary = by_pid[ppid]
		# A parent that started after its child is a reused pid, not the parent.
		if int(parent.get("t", 0)) > int(q.get("t", 0)):
			return ""
		q = parent
	return ""


## Started by Oazy and not part of any app: Oazy's own helpers.
static func _under(p: Dictionary, by_pid: Dictionary, self_pid: int) -> bool:
	var exe := str(p.get("exe", "")).get_file().to_lower()
	return int(p.get("ppid", 0)) == self_pid and exe.begins_with("oazy")


static func _unsaved_title(title: String) -> bool:
	var t := title.strip_edges()
	return t.begins_with("*") or t.begins_with("●") or t.contains(" • ") or t.to_lower().contains("unsaved") or t.contains("(modified)")


static func is_critical(name: String) -> bool:
	return name.to_lower() in CRITICAL


# --- Stand-in PC (screenshots, Linux) ---------------------------------------------------

## A believable process list for the mock windows; CPU drifts with `t` so the
## graphs move. Returns {snap, windows} with pids filled in.
static func mock(windows: Array, t: float) -> Dictionary:
	var procs: Array = []
	var wins: Array = []
	var next := [4100]
	var self_pid := OS.get_process_id()
	var add := func(n: String, exe: String, d: String, cpu: float, mem_mb: float, ppid: int, s: int = 1) -> int:
		next[0] += 4
		var pid: int = next[0]
		procs.append({"pid": pid, "ppid": ppid, "s": s, "t": 100 + pid, "n": n, "exe": exe, "d": d, "cpu": cpu, "mem": int(mem_mb * 1048576.0)})
		return pid
	var wobble := func(base: float, k: float) -> float: return maxf(0.0, base * (1.0 + 0.45 * sin(t * k + base * 40.0)))
	procs.append({"pid": self_pid, "ppid": 3000, "s": 1, "t": 50, "n": "OazyLauncher.exe", "exe": "C:/Users/joao/Apps/OazyLauncher.exe", "d": "Oazy", "cpu": wobble.call(0.012, 1.3), "mem": 212 * 1048576})
	add.call("OazyHost-1a2b3c4d5e.exe", "C:/Users/joao/AppData/Roaming/Oazy/host/OazyHost-1a2b3c4d5e.exe", "Oazy host", 0.002, 18.0, self_pid)
	for w in windows:
		var c: Dictionary = w.duplicate()
		var exe := str(c.get("exe", ""))
		var file := exe.get_file()
		var title := str(c.get("title", "")).to_lower()
		var root := 0
		if file.to_lower() == "chrome.exe":
			root = add.call(file, exe, "Google Chrome", wobble.call(0.031, 0.9), 412.0, 3000)
			for i in 9:
				add.call(file, exe, "Google Chrome", wobble.call(0.004 + 0.003 * i, 1.7 + i), 60.0 + 37.0 * i, root)
		elif file.to_lower() == "discord.exe":
			var main := add.call(file, exe, "Discord", 0.002, 96.0, 3000)
			root = add.call(file, exe, "Discord", wobble.call(0.009, 1.1), 288.0, main)
			add.call(file, exe, "Discord", 0.001, 74.0, main)
		elif file.to_lower() == "cmd.exe" and title.contains("claude"):
			root = add.call(file, exe, "Windows Command Processor", 0.0, 4.6, 3000)
			add.call("node.exe", "C:/Program Files/nodejs/node.exe", "Node.js JavaScript Runtime", wobble.call(0.018, 2.2), 236.0, root)
		else:
			root = add.call(file, exe, str(c.get("name", "")), wobble.call(0.006, 1.4), 120.0, 3000)
		c["pid"] = root
		wins.append(c)
	var background := [
		["steam.exe", "C:/Program Files (x86)/Steam/steam.exe", "Steam", 0.004, 182.0],
		["steamwebhelper.exe", "C:/Program Files (x86)/Steam/bin/cef/cef.win7x64/steamwebhelper.exe", "Steam Client WebHelper", 0.002, 140.0],
		["Spotify.exe", "C:/Users/joao/AppData/Roaming/Spotify/Spotify.exe", "Spotify", 0.011, 268.0],
		["OneDrive.exe", "C:/Program Files/Microsoft OneDrive/OneDrive.exe", "Microsoft OneDrive", 0.001, 64.0],
		["NVIDIA Overlay.exe", "C:/Program Files/NVIDIA Corporation/NVIDIA App/CEF/NVIDIA Overlay.exe", "NVIDIA Overlay", 0.003, 92.0],
		["EpicGamesLauncher.exe", "C:/Program Files (x86)/Epic Games/Launcher/Portal/Binaries/Win64/EpicGamesLauncher.exe", "Epic Games Launcher", 0.002, 156.0],
		["GoogleDriveFS.exe", "C:/Program Files/Google/Drive File Stream/GoogleDriveFS.exe", "Google Drive", 0.0, 88.0],
	]
	for b in background:
		add.call(b[0], b[1], b[2], wobble.call(b[3], 0.8), b[4], 3000)
	add.call("steamwebhelper.exe", "C:/Program Files (x86)/Steam/bin/cef/cef.win7x64/steamwebhelper.exe", "Steam Client WebHelper", 0.001, 96.0, 3000)
	var system := [
		["svchost.exe", "C:/Windows/System32/svchost.exe", "Host Process for Windows Services", 0.002, 22.0, 0],
		["svchost.exe", "C:/Windows/System32/svchost.exe", "Host Process for Windows Services", 0.001, 14.0, 0],
		["MsMpEng.exe", "", "", 0.006, 210.0, 0],
		["dwm.exe", "C:/Windows/System32/dwm.exe", "Desktop Window Manager", 0.014, 96.0, 1],
		["explorer.exe", "C:/Windows/explorer.exe", "Windows Explorer", 0.002, 118.0, 1],
		["SearchHost.exe", "C:/Windows/SystemApps/MicrosoftWindows.Client.CBS_cw5n1h2txyewy/SearchHost.exe", "Search", 0.0, 64.0, 1],
		["RuntimeBroker.exe", "C:/Windows/System32/RuntimeBroker.exe", "Runtime Broker", 0.0, 8.0, 1],
		["csrss.exe", "", "", 0.001, 2.0, 0],
	]
	for s in system:
		add.call(s[0], s[1], s[2], wobble.call(s[3], 0.6), s[4], 600, s[5])
	var cpu := 0.0
	var used := 0.0
	for p in procs:
		cpu += float(p["cpu"])
		used += float(p["mem"])
	var snap := {"ok": true, "self": self_pid, "cpu": cpu, "mem_total": 34359738368.0, "mem_used": used + 9.4e9, "cores": 16, "procs": procs}
	return {"snap": snap, "windows": wins}
