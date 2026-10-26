extends Node
## The engine behind the Cleaner app: finds Windows bloat, startup apps, junk
## files and settings worth changing, applies only what you pick, keeps a
## record of every change and puts it all back on request.
##
## The work happens in native/cleaner.ps1 (Windows PowerShell, which every
## Windows 10/11 has), started on a worker thread. Changes that need an
## administrator (a restore point, machine-wide settings) run in a second,
## elevated pass, so Windows asks once per apply. Everywhere else (Linux dev
## runs, CI screenshots) a mock PC built from the catalog stands in.

signal state_changed
signal scanned
signal applied(run: Dictionary)
signal undone(run: Dictionary, results: Array)
signal selection_changed

const SCRIPT := "res://native/cleaner.ps1"
const CATALOG := "res://native/cleaner_catalog.json"
const DIR := "user://cleaner"
const HISTORY := "user://cleaner/history.json"
const MAX_RUNS := 30
## How long after Oazy starts it quietly checks nothing came back.
const WATCH_DELAY := 120.0

## &"idle", &"scanning", &"applying" or &"undoing".
var state := &"idle"
## What's happening right now, for the busy screen.
var phase := ""
var scan: Dictionary = {}
var scanned_at := 0
## Runs, newest first: {id, time, entries, restore, logs, undone, freed}.
var history: Array = []
var catalog: Dictionary = {}
## Things Windows quietly brought back since you cleaned them: [label].
var came_back: Array[String] = []
## Picked changes: "app:<pkg>", "tweak:<id>", "junk:<id>" -> true, and
## "startup:<loc>:<key>" -> the on/off state you want.
var picks := {}
var restore_point := true

var _thread: Thread
var _mock := false
var _mock_pc := {}


func _ready() -> void:
	# The smoke test drives the whole flow on CI's Windows runner too, so it
	# gets the mock PC there as well.
	_mock = not App.is_windows() or App.smoke_test
	var f := FileAccess.get_file_as_string(CATALOG)
	var data: Variant = JSON.parse_string(f)
	if data is Dictionary:
		catalog = data
	DirAccess.make_dir_recursive_absolute(DIR)
	_load_history()
	if not _mock and not App.smoke_test and bool(Settings.get_value("cleaner_watch")) and not history.is_empty():
		get_tree().create_timer(WATCH_DELAY).timeout.connect(func() -> void:
			if state == &"idle":
				start_scan(true)
		)


func busy() -> bool:
	return state != &"idle"


func has_scan() -> bool:
	return not scan.is_empty()


# --- Scan ----------------------------------------------------------------------------

## Looks the PC over without changing anything. `quick` skips measuring junk.
func start_scan(quick: bool = false) -> void:
	if busy():
		return
	_set_state(&"scanning", "Looking around your PC…")
	_run(func() -> Dictionary: return _scan_job(quick), _on_scanned.bind(quick))


func _scan_job(quick: bool) -> Dictionary:
	if _mock:
		OS.delay_msec(2200 if not quick else 300)
		return _mock_scan()
	var out := _file("scan.json")
	var args := ["-Mode", "scan", "-Out", out]
	if quick:
		args.append("-Quick")
	_ps(args)
	return _read(out)


func _on_scanned(d: Dictionary, quick: bool) -> void:
	_set_state(&"idle", "")
	if not d.get("ok", false):
		if not quick:
			App.toast("Couldn't look around: %s" % str(d.get("error", "PowerShell didn't answer")), &"error")
		return
	var fresh := not has_scan()
	if quick and has_scan():
		d["junk"] = scan.get("junk", [])
	scan = d
	scanned_at = int(Time.get_unix_time_from_system())
	_check_came_back(quick)
	if fresh or not quick:
		pick_recommended()
	scanned.emit()


## Things you cleaned that are back (Windows feature updates like to do this).
func _check_came_back(announce: bool) -> void:
	came_back.clear()
	var apps := {}
	for a in scan.get("apps", []):
		apps[str(a["pkg"])] = true
	var tweaks := {}
	for t in scan.get("tweaks", []):
		tweaks[str(t["id"])] = bool(t["done"])
	var seen := {}
	for run in history:
		if run.get("undone", false):
			continue
		for e in run.get("entries", []):
			if not e.get("ok", false) or seen.has(str(e["id"])):
				continue
			seen[str(e["id"])] = true
			if e["kind"] == "app" and apps.has(str(e["id"])):
				came_back.append(str(e["label"]))
			elif e["kind"] == "tweak" and tweaks.has(str(e["id"])) and not tweaks[str(e["id"])]:
				came_back.append(str(e["label"]))
	if announce and not came_back.is_empty():
		App.toast("Windows brought back %d thing%s you cleaned up. Open Cleaner to tidy again." % [came_back.size(), "" if came_back.size() == 1 else "s"])


# --- Picks -----------------------------------------------------------------------------

## Selects what Oazy recommends and drops everything else.
func pick_recommended() -> void:
	picks.clear()
	for a in scan.get("apps", []):
		if a["rec"]:
			picks["app:" + str(a["pkg"])] = true
	for t in scan.get("tweaks", []):
		if t["rec"] and not t["done"]:
			picks["tweak:" + str(t["id"])] = true
	for j in scan.get("junk", []):
		if j["rec"] and str(j.get("busy", "")) == "" and (int(j["size"]) > 0 or int(j["size"]) < 0):
			picks["junk:" + str(j["id"])] = true
	selection_changed.emit()


func set_pick(key: String, on: bool) -> void:
	if on:
		picks[key] = true
	else:
		picks.erase(key)
	selection_changed.emit()


func is_picked(key: String) -> bool:
	return picks.has(key)


## Turns a startup app on or off (takes effect when you apply).
func want_startup(row: Dictionary, on: bool) -> void:
	var key := startup_key(row)
	if on == bool(row["enabled"]):
		picks.erase(key)
	else:
		picks[key] = on
	selection_changed.emit()


func startup_wanted(row: Dictionary) -> bool:
	var key := startup_key(row)
	return bool(picks[key]) if picks.has(key) else bool(row["enabled"])


static func startup_key(row: Dictionary) -> String:
	return "startup:%s:%s" % [row["loc"], row["key"]]


## Picks for one group: "apps", "startup", "junk", "perf" or "privacy".
func picks_in(group: String) -> int:
	var n := 0
	for key in picks.keys():
		if _group_of(key) == group:
			n += 1
	return n


func _group_of(key: String) -> String:
	if key.begins_with("app:"):
		return "apps"
	if key.begins_with("startup:"):
		return "startup"
	if key.begins_with("junk:"):
		return "junk"
	var t := tweak(key.substr(6))
	return str(t.get("group", ""))


func tweak(id: String) -> Dictionary:
	for t in scan.get("tweaks", []):
		if t["id"] == id:
			return t
	return {}


func junk_item(id: String) -> Dictionary:
	for j in scan.get("junk", []):
		if j["id"] == id:
			return j
	return {}


func bytes_picked() -> int:
	var total := 0
	for key in picks.keys():
		if key.begins_with("junk:"):
			total += maxi(0, int(junk_item(key.substr(5)).get("size", 0)))
	return total


## True when applying the picks needs Windows' permission (one prompt).
func needs_admin() -> bool:
	if picks.is_empty():
		return false
	if restore_point:
		return true
	for key in picks.keys():
		if key.begins_with("tweak:") and tweak(key.substr(6)).get("admin", false):
			return true
		if key.begins_with("junk:") and junk_item(key.substr(5)).get("admin", false):
			return true
		if key.begins_with("startup:hklm") or key.begins_with("startup:common"):
			return true
	return false


## 0..100: how much of what Oazy recommends is already done.
func health() -> float:
	if not has_scan():
		return 0.0
	var todo := 0.0
	for a in scan.get("apps", []):
		if a["rec"]:
			todo += 3.0
	for t in scan.get("tweaks", []):
		if t["rec"] and not t["done"]:
			todo += 4.0
	for s in scan.get("startup", []):
		if s["enabled"] and str(s.get("hint", "")) != "" and not s.get("protected", false):
			todo += 2.0
	var gb := 0.0
	for j in scan.get("junk", []):
		if j["rec"]:
			gb += maxf(0.0, float(j["size"])) / 1073741824.0
	todo += minf(gb * 4.0, 16.0)
	return clampf(100.0 - todo, 30.0, 100.0)


# --- Apply ---------------------------------------------------------------------------

func apply_picks() -> void:
	if busy() or picks.is_empty():
		return
	var run_id := Time.get_datetime_string_from_system(false, false).replace(":", "").replace("-", "").replace("T", "-")
	var plan := {"run": run_id, "sid": scan.get("sid", ""), "restore_point": restore_point, "tweaks": [], "apps": [], "startup": [], "junk": []}
	for key in picks.keys():
		var k := str(key)
		if k.begins_with("tweak:"):
			plan["tweaks"].append(k.substr(6))
		elif k.begins_with("app:"):
			plan["apps"].append(k.substr(4))
		elif k.begins_with("junk:"):
			plan["junk"].append(k.substr(5))
		elif k.begins_with("startup:"):
			for s in scan.get("startup", []):
				if startup_key(s) == k:
					plan["startup"].append({"loc": s["loc"], "key": s["key"], "enable": bool(picks[key])})
	var admin := needs_admin()
	_set_state(&"applying", "Waiting for Windows' permission…" if admin else "Tidying up…")
	_run(func() -> Dictionary: return _apply_job(plan, admin), _on_applied)


func _apply_job(plan: Dictionary, admin: bool) -> Dictionary:
	if _mock:
		OS.delay_msec(1800)
		return _mock_apply(plan)
	var plan_path := _file("plan-%s.json" % plan["run"])
	var f := FileAccess.open(plan_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(plan))
	f.close()
	var run := {"id": plan["run"], "time": int(Time.get_unix_time_from_system()), "entries": [], "restore": {}, "logs": {}, "undone": false}
	if admin:
		var admin_log := _file("log-%s-admin.json" % plan["run"])
		_set_phase.call_deferred("Making a restore point, this can take a minute…" if plan["restore_point"] else "Changing Windows settings…")
		_ps(["-Mode", "apply", "-Scope", "admin", "-Plan", plan_path, "-Out", admin_log, "-Elevate"])
		var d := _read(admin_log)
		if not d.get("ok", false):
			DirAccess.remove_absolute(admin_log)
			return {"ok": false, "denied": d.get("denied", false), "error": str(d.get("error", "Windows didn't allow the change"))}
		run["logs"]["admin"] = admin_log
		run["restore"] = d.get("restore", {})
		for e in d.get("entries", []):
			e["scope"] = "admin"
			run["entries"].append(e)
	_set_phase.call_deferred("Tidying up…")
	var user_log := _file("log-%s-user.json" % plan["run"])
	_ps(["-Mode", "apply", "-Scope", "user", "-Plan", plan_path, "-Out", user_log])
	var u := _read(user_log)
	if u.get("ok", false):
		run["logs"]["user"] = user_log
		for e in u.get("entries", []):
			e["scope"] = "user"
			run["entries"].append(e)
	DirAccess.remove_absolute(plan_path)
	run["ok"] = true
	return run


func _on_applied(run: Dictionary) -> void:
	_set_state(&"idle", "")
	if not run.get("ok", false):
		if run.get("denied", false):
			App.toast("Windows didn't give permission, so nothing changed")
		else:
			App.toast("Couldn't apply: %s" % str(run.get("error", "")), &"error")
		applied.emit(run)
		return
	var freed := 0
	for e in run["entries"]:
		freed += int(e.get("freed", 0))
	run["freed"] = freed
	run.erase("ok")
	if not run["entries"].is_empty():
		history.push_front(run)
		_trim_history()
		_save_history()
	picks.clear()
	run["ok"] = true
	applied.emit(run)
	start_scan()


# --- Undo ----------------------------------------------------------------------------

func run_by_id(id: String) -> Dictionary:
	for r in history:
		if r["id"] == id:
			return r
	return {}


static func undoable(run: Dictionary) -> int:
	var n := 0
	for e in run.get("entries", []):
		if e.get("ok", false) and e.get("undo") != null:
			n += 1
	return n


func undo_run(id: String) -> void:
	var run := run_by_id(id)
	if busy() or run.is_empty() or run.get("undone", false):
		return
	var admin := false
	for e in run["entries"]:
		if e.get("scope", "") == "admin" and e.get("ok", false) and e.get("undo") != null:
			admin = true
	_set_state(&"undoing", "Waiting for Windows' permission…" if admin else "Putting things back…")
	_run(func() -> Dictionary: return _undo_job(run, admin), _on_undone.bind(id))


func _undo_job(run: Dictionary, admin: bool) -> Dictionary:
	if _mock:
		OS.delay_msec(1200)
		return _mock_undo(run)
	var results: Array = []
	var logs: Dictionary = run.get("logs", {})
	if logs.has("user"):
		var out := _file("undo-%s-user.json" % run["id"])
		_ps(["-Mode", "undo", "-Log", str(logs["user"]), "-Out", out])
		var d := _read(out)
		DirAccess.remove_absolute(out)
		if not d.get("ok", false):
			return {"ok": false, "error": str(d.get("error", "PowerShell didn't answer"))}
		results.append_array(d.get("entries", []))
	if admin and logs.has("admin"):
		_set_phase.call_deferred("Waiting for Windows' permission…")
		var out := _file("undo-%s-admin.json" % run["id"])
		_ps(["-Mode", "undo", "-Scope", "admin", "-Log", str(logs["admin"]), "-Out", out, "-Elevate"])
		var d := _read(out)
		DirAccess.remove_absolute(out)
		if not d.get("ok", false):
			return {"ok": false, "denied": d.get("denied", false), "partial": results, "error": str(d.get("error", "Windows didn't allow the change"))}
		results.append_array(d.get("entries", []))
	return {"ok": true, "entries": results}


func _on_undone(d: Dictionary, id: String) -> void:
	_set_state(&"idle", "")
	var run := run_by_id(id)
	var results: Array = d.get("entries", d.get("partial", []))
	if not d.get("ok", false) and results.is_empty():
		App.toast("Windows didn't give permission, so nothing changed" if d.get("denied", false) else "Couldn't undo: %s" % str(d.get("error", "")), &"error")
		return
	run["undone"] = d.get("ok", false)
	run["undo_results"] = results
	_save_history()
	undone.emit(run, results)
	start_scan()


# --- History ---------------------------------------------------------------------------

func _load_history() -> void:
	if App.smoke_test or not FileAccess.file_exists(HISTORY):
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(HISTORY))
	if data is Array:
		history = data


func _save_history() -> void:
	if App.smoke_test:
		return
	var f := FileAccess.open(HISTORY, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(history, "\t"))
		f.close()


func _trim_history() -> void:
	while history.size() > MAX_RUNS:
		var old: Dictionary = history.pop_back()
		for path in old.get("logs", {}).values():
			DirAccess.remove_absolute(str(path))


# --- Plumbing --------------------------------------------------------------------------

func _set_state(s: StringName, text: String) -> void:
	state = s
	phase = text
	state_changed.emit()


func _set_phase(text: String) -> void:
	phase = text
	state_changed.emit()


func _run(job: Callable, done: Callable) -> void:
	if _thread and _thread.is_started():
		_thread.wait_to_finish()
	_thread = Thread.new()
	_thread.start(func() -> void:
		var result: Dictionary = job.call()
		_finish.call_deferred(done, result)
	)


func _finish(done: Callable, result: Dictionary) -> void:
	if _thread:
		_thread.wait_to_finish()
		_thread = null
	done.call(result)


func _exit_tree() -> void:
	if _thread and _thread.is_started():
		_thread.wait_to_finish()


## A path in Oazy's cleaner folder, the Windows way.
func _file(name: String) -> String:
	return ProjectSettings.globalize_path(DIR.path_join(name)).replace("/", "\\")


## Runs the engine (a fresh copy of it, so updates take effect) and waits.
func _ps(args: Array) -> int:
	var dir := DIR.path_join("engine")
	DirAccess.make_dir_recursive_absolute(dir)
	for src in [SCRIPT, CATALOG]:
		var f := FileAccess.open(dir.path_join(src.get_file()), FileAccess.WRITE)
		if f:
			f.store_string(FileAccess.get_file_as_string(src))
			f.close()
	var script := ProjectSettings.globalize_path(dir.path_join(SCRIPT.get_file())).replace("/", "\\")
	var full := PackedStringArray(["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden", "-File", script])
	for a in args:
		full.append(str(a))
	var out := []
	return OS.execute("powershell.exe", full, out, true)


func _read(path: String) -> Dictionary:
	var gpath := path.replace("\\", "/")
	if not FileAccess.file_exists(gpath):
		return {"ok": false, "error": "PowerShell didn't answer"}
	var text := FileAccess.get_file_as_string(gpath).trim_prefix("\ufeff")
	var data: Variant = JSON.parse_string(text)
	return data if data is Dictionary else {"ok": false, "error": "Unreadable answer"}


# --- Mock PC (Linux, screenshots) ----------------------------------------------------------

func _mock_scan() -> Dictionary:
	if _mock_pc.is_empty():
		var apps: Array = []
		var want := ["Microsoft.BingNews", "Microsoft.BingWeather", "Microsoft.Getstarted", "Microsoft.MicrosoftOfficeHub", "Microsoft.MicrosoftSolitaireCollection", "Clipchamp.Clipchamp", "Microsoft.WindowsFeedbackHub", "Microsoft.ZuneVideo", "Microsoft.549981C3F5F10", "MicrosoftTeams", "Microsoft.Copilot", "Microsoft.GamingApp", "Microsoft.YourPhone", "SpotifyAB.SpotifyMusic"]
		for a in catalog.get("apps", []):
			if str(a["id"]) in want:
				apps.append({"id": a["id"], "pkg": a["id"], "full": [str(a["id"]) + "_1.0.0.0_x64"], "pfn": str(a["id"]) + "_8wekyb3d8bbwe", "name": a["name"], "desc": a["desc"], "rec": a["rec"], "aumid": "", "version": "1.0.0.0"})
		apps.append({"id": "king.com.*", "pkg": "king.com.CandyCrushSaga", "full": ["king.com.CandyCrushSaga_1.0_x86"], "pfn": "king.com.CandyCrushSaga_kgqvnymyfvs32", "name": "Candy Crush Saga", "desc": "A preinstalled game with ads and in-app purchases.", "rec": true, "aumid": "", "version": "1.0"})
		var startup := [
			{"loc": "hkcu_run", "key": "Steam", "name": "Steam", "exe": "C:/Program Files (x86)/Steam/steam.exe", "publisher": "Valve Corporation", "enabled": true, "admin": false, "protected": false, "hint": "Oazy starts Steam when you play."},
			{"loc": "hkcu_run", "key": "Discord", "name": "Discord", "exe": "", "publisher": "Discord Inc.", "enabled": true, "admin": false, "protected": false, "hint": "Discord opens in a second when you need it."},
			{"loc": "hkcu_run", "key": "Spotify", "name": "Spotify", "exe": "", "publisher": "Spotify AB", "enabled": true, "admin": false, "protected": false, "hint": "Spotify opens fast when you need it."},
			{"loc": "hkcu_run", "key": "EpicGamesLauncher", "name": "Epic Games Launcher", "exe": "", "publisher": "Epic Games, Inc.", "enabled": true, "admin": false, "protected": false, "hint": "Oazy starts Epic when you play."},
			{"loc": "hkcu_run", "key": "MicrosoftEdgeAutoLaunch_0A1B", "name": "Microsoft Edge", "exe": "", "publisher": "Microsoft Corporation", "enabled": true, "admin": false, "protected": false, "hint": "Edge preloads itself in the background."},
			{"loc": "hkcu_run", "key": "OneDrive", "name": "OneDrive", "exe": "", "publisher": "Microsoft Corporation", "enabled": true, "admin": false, "protected": false, "hint": ""},
			{"loc": "hklm_run", "key": "SecurityHealth", "name": "Windows Security", "exe": "", "publisher": "Microsoft Corporation", "enabled": true, "admin": true, "protected": true, "hint": ""},
			{"loc": "hklm_run", "key": "RtkAudUService", "name": "Realtek Audio", "exe": "", "publisher": "Realtek Semiconductor", "enabled": true, "admin": true, "protected": true, "hint": ""},
			{"loc": "user_folder", "key": "Logi Options+.lnk", "name": "Logi Options+", "exe": "", "publisher": "Logitech", "enabled": false, "admin": false, "protected": false, "hint": ""},
		]
		var tweaks: Array = []
		for t in catalog.get("tweaks", []):
			var admin := false
			for op in t["ops"]:
				if op["t"] == "service" or str(op.get("path", "")).begins_with("HKLM:") or str(op.get("path", "")).contains("\\Policies\\"):
					admin = true
			tweaks.append({"id": t["id"], "group": t["group"], "icon": t["icon"], "name": t["name"], "desc": t["desc"], "rec": t["rec"], "admin": admin, "done": t["id"] in ["game_mode", "feedback"]})
		var junk: Array = []
		var sizes := {"user_temp": 2_480_000_000, "win_temp": 612_000_000, "crash": 318_000_000, "browser": 1_140_000_000, "recycle": 3_900_000_000}
		for j in catalog.get("junk", []):
			junk.append({"id": j["id"], "icon": j["icon"], "name": j["name"], "desc": j["desc"], "rec": j["rec"], "admin": j.get("admin", false), "size": sizes.get(j["id"], 0), "count": 1200, "busy": "chrome" if j["id"] == "browser" else ""})
		_mock_pc = {"ok": true, "sid": "S-1-5-21-0", "battery": false, "elevated": false, "apps": apps, "startup": startup, "tweaks": tweaks, "junk": junk, "quick": false}
	return _mock_pc.duplicate(true)


func _mock_apply(plan: Dictionary) -> Dictionary:
	var entries: Array = []
	for pkg in plan["apps"]:
		for a in _mock_pc["apps"].duplicate():
			if a["pkg"] == pkg:
				_mock_pc["apps"].erase(a)
				entries.append({"kind": "app", "id": pkg, "label": a["name"], "ok": true, "msg": "", "undo": {"pkg": pkg, "pfn": a["pfn"], "manifests": []}, "freed": 0, "scope": "user"})
	for id in plan["tweaks"]:
		for t in _mock_pc["tweaks"]:
			if t["id"] == id:
				t["done"] = true
				entries.append({"kind": "tweak", "id": id, "label": t["name"], "ok": true, "msg": "", "undo": {"ops": []}, "freed": 0, "scope": "admin" if t["admin"] else "user"})
	for s in plan["startup"]:
		for row in _mock_pc["startup"]:
			if row["loc"] == s["loc"] and row["key"] == s["key"]:
				row["enabled"] = s["enable"]
				entries.append({"kind": "startup", "id": "%s:%s" % [s["loc"], s["key"]], "label": row["name"], "ok": true, "msg": "", "undo": {"ops": []}, "freed": 0, "scope": "user"})
	for id in plan["junk"]:
		for j in _mock_pc["junk"]:
			if j["id"] == id:
				var busy_now := str(j["busy"]) != ""
				entries.append({"kind": "junk", "id": id, "label": j["name"], "ok": not busy_now, "msg": "Skipped while chrome is open" if busy_now else "Can't be undone", "undo": null, "freed": 0 if busy_now else int(j["size"]), "scope": "user"})
				if not busy_now:
					j["size"] = 0
	return {"ok": true, "id": plan["run"], "time": int(Time.get_unix_time_from_system()), "entries": entries, "restore": {"tried": plan["restore_point"], "ok": plan["restore_point"], "msg": ""}, "logs": {}, "undone": false}


func _mock_undo(run: Dictionary) -> Dictionary:
	var results: Array = []
	for e in run["entries"]:
		if e.get("ok", false) and e.get("undo") != null:
			results.append({"kind": e["kind"], "id": e["id"], "label": e["label"], "ok": true, "msg": "", "store": ""})
	_mock_pc.clear()
	return {"ok": true, "entries": results}
