extends Node
## In-app updates from GitHub Releases: check, show what's new, download with
## live progress, verify (size, PE header, SHA-256 digest) and swap the exe.

signal state_changed(state: StringName)
signal progress(done: int, total: int, speed: float)

const API := "https://api.github.com/repos/%s/releases?per_page=30"
const UPDATE_DIR := "user://update"
const RECHECK_SECONDS := 3 * 3600

## idle, checking, current, available, downloading, ready, installing, error
var state: StringName = &"idle"
var releases: Array[Dictionary] = []
var newer: Array[Dictionary] = []
var latest: Dictionary = {}
var error_text := ""
var last_checked := 0

var _check_http: HTTPRequest
var _dl_http: HTTPRequest
var _part_path := ""
var _speed := 0.0
var _sample_bytes := 0
var _sample_time := 0.0
var _recheck_timer: Timer


func _ready() -> void:
	_check_http = HTTPRequest.new()
	_check_http.timeout = 20.0
	_check_http.request_completed.connect(_on_check_completed)
	add_child(_check_http)
	_dl_http = HTTPRequest.new()
	_dl_http.use_threads = true
	_dl_http.download_chunk_size = 256 * 1024
	_dl_http.request_completed.connect(_on_download_completed)
	add_child(_dl_http)
	_recheck_timer = Timer.new()
	_recheck_timer.wait_time = RECHECK_SECONDS
	_recheck_timer.timeout.connect(func() -> void:
		if Settings.get_value("auto_check_updates"):
			check()
	)
	add_child(_recheck_timer)
	set_process(false)
	_cleanup_previous_install()


func can_install() -> bool:
	return App.is_packaged() and App.is_windows()


# --- Checking ----------------------------------------------------------------------

func check() -> void:
	if state in [&"checking", &"downloading", &"installing", &"ready"]:
		return
	_set_state(&"checking")
	var err := _check_http.request(API % App.REPO, _headers("application/vnd.github+json"))
	if err != OK:
		_fail("Couldn't start the update check (%s)." % error_string(err))


func _on_check_completed(result: int, code: int, _headers_in: PackedStringArray, body: PackedByteArray) -> void:
	last_checked = int(Time.get_unix_time_from_system())
	_recheck_timer.start()
	if result != HTTPRequest.RESULT_SUCCESS:
		_fail("Couldn't reach GitHub. Check your internet connection.")
		return
	if code == 403 or code == 429:
		_fail("GitHub is rate limiting update checks. Try again in a little while.")
		return
	if code != 200:
		_fail("GitHub answered with HTTP %d." % code)
		return
	var data: Variant = JSON.parse_string(body.get_string_from_utf8())
	apply_releases(data, App.version)
	_set_state(&"available" if not newer.is_empty() else &"current")


## Parses the GitHub releases payload. Public so the smoke test can feed it fixtures.
func apply_releases(data: Variant, current: String) -> void:
	releases.clear()
	newer.clear()
	latest = {}
	if not data is Array:
		return
	for r in data:
		if not r is Dictionary or bool(r.get("draft", false)) or bool(r.get("prerelease", false)):
			continue
		var asset := {}
		var assets: Variant = r.get("assets", [])
		if assets is Array:
			for a in assets:
				if a is Dictionary and str(a.get("name", "")).to_lower().ends_with(".exe"):
					asset = a
					break
		if asset.is_empty():
			continue
		var tag := str(r.get("tag_name", ""))
		var body: Variant = r.get("body", "")
		releases.append({
			"version": tag.trim_prefix("v"),
			"tag": tag,
			"name": str(r.get("name", tag)) if r.get("name") != null else tag,
			"notes": str(body) if body != null else "",
			"url": str(asset.get("browser_download_url", "")),
			"size": int(asset.get("size", 0)),
			"digest": str(asset.get("digest", "")) if asset.get("digest") != null else "",
			"date": str(r.get("published_at", "")),
			"html": str(r.get("html_url", "")),
		})
	releases.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return Semver.compare(a["version"], b["version"]) > 0
	)
	for r in releases:
		if Semver.is_newer(r["version"], current):
			newer.append(r)
	if not newer.is_empty():
		latest = newer[0]


## Markdown for every release between the installed version and the newest one.
func combined_notes(list: Array[Dictionary] = []) -> String:
	var src := list if not list.is_empty() else newer
	var parts := PackedStringArray()
	for r in src:
		var notes := str(r["notes"]).strip_edges()
		if notes.is_empty():
			notes = "- Behind-the-scenes improvements and fixes."
		parts.append("## Version %s\n%s" % [r["version"], notes])
	return "\n\n".join(parts)


# --- Downloading -------------------------------------------------------------------

func download() -> void:
	if latest.is_empty() or state == &"downloading":
		return
	DirAccess.make_dir_recursive_absolute(UPDATE_DIR)
	_part_path = UPDATE_DIR.path_join(App.EXE_NAME + ".part")
	if FileAccess.file_exists(_part_path):
		DirAccess.remove_absolute(_part_path)
	_dl_http.download_file = _part_path
	var err := _dl_http.request(str(latest["url"]), _headers("application/octet-stream"))
	if err != OK:
		_fail("Couldn't start the download (%s)." % error_string(err))
		return
	_speed = 0.0
	_sample_bytes = 0
	_sample_time = 0.0
	_set_state(&"downloading")
	set_process(true)


func cancel_download() -> void:
	if state != &"downloading":
		return
	_dl_http.cancel_request()
	set_process(false)
	if FileAccess.file_exists(_part_path):
		DirAccess.remove_absolute(_part_path)
	_set_state(&"available")


func _process(delta: float) -> void:
	var done := _dl_http.get_downloaded_bytes()
	var total := int(latest.get("size", 0))
	if total <= 0:
		total = maxi(_dl_http.get_body_size(), 0)
	_sample_time += delta
	if _sample_time >= 0.25:
		var inst := float(done - _sample_bytes) / _sample_time
		_speed = inst if _speed <= 0.0 else lerpf(_speed, inst, 0.3)
		_sample_bytes = done
		_sample_time = 0.0
	progress.emit(done, total, _speed)


func _on_download_completed(result: int, code: int, _h: PackedStringArray, _b: PackedByteArray) -> void:
	set_process(false)
	if state != &"downloading":
		return
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_fail("The download didn't finish (HTTP %d, result %d). Please try again." % [code, result])
		return
	var problem := verify_file(_part_path, int(latest.get("size", 0)), str(latest.get("digest", "")))
	if problem != "":
		DirAccess.remove_absolute(_part_path)
		_fail(problem)
		return
	var final_path := UPDATE_DIR.path_join(App.EXE_NAME)
	if FileAccess.file_exists(final_path):
		DirAccess.remove_absolute(final_path)
	DirAccess.rename_absolute(_part_path, final_path)
	var total := int(latest.get("size", 0))
	progress.emit(total, total, 0.0)
	_set_state(&"ready")


## Returns "" when the file looks like the exe we expect, otherwise a reason.
static func verify_file(path: String, expected_size: int, digest: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return "The downloaded file couldn't be opened."
	var length := f.get_length()
	var header := f.get_buffer(2)
	f.close()
	if expected_size > 0 and length != expected_size:
		return "The download was incomplete (%s of %s)." % [Fmt.bytes(length), Fmt.bytes(expected_size)]
	if header.size() < 2 or header[0] != 0x4D or header[1] != 0x5A:
		return "The download isn't a Windows program. It was discarded."
	if digest.begins_with("sha256:"):
		var want := digest.substr(7).to_lower()
		if FileAccess.get_sha256(path).to_lower() != want:
			return "The download failed its integrity check. It was discarded."
	return ""


# --- Installing --------------------------------------------------------------------

func install() -> void:
	if state != &"ready":
		return
	if not can_install():
		_fail("Downloaded and verified. Installing only works in the packaged Windows app.")
		return
	_set_state(&"installing")
	Settings.set_value("pending_update_version", str(latest["version"]))
	Settings.set_value("pending_update_notes", combined_notes())
	Settings.save()
	var exe := OS.get_executable_path()
	var fresh := ProjectSettings.globalize_path(UPDATE_DIR.path_join(App.EXE_NAME))
	var old := exe + ".old"
	if FileAccess.file_exists(old):
		DirAccess.remove_absolute(old)
	# Windows lets us rename a running exe, so swap in place and relaunch.
	if DirAccess.rename_absolute(exe, old) == OK:
		if DirAccess.copy_absolute(fresh, exe) == OK:
			OS.create_process(exe, [])
			get_tree().quit()
			return
		DirAccess.rename_absolute(old, exe)
	_install_elevated(exe, fresh)


## The folder isn't writable (e.g. Program Files): hand the swap to an elevated helper.
func _install_elevated(exe: String, fresh: String) -> void:
	var script_path := ProjectSettings.globalize_path(UPDATE_DIR.path_join("install.cmd"))
	var f := FileAccess.open(script_path, FileAccess.WRITE)
	if f == null:
		_fail("Couldn't prepare the installer. Try running Oazy as administrator.")
		return
	var w_exe := exe.replace("/", "\\")
	var w_new := fresh.replace("/", "\\")
	f.store_string("@echo off\r\nchcp 65001 >nul\r\nping 127.0.0.1 -n 3 >nul\r\ncopy /y \"%s\" \"%s\" >nul\r\nstart \"\" \"%s\"\r\n" % [w_new, w_exe, w_exe])
	f.close()
	var ps := "Start-Process -FilePath '%s' -Verb RunAs -WindowStyle Hidden" % script_path.replace("/", "\\").replace("'", "''")
	OS.create_process("powershell.exe", ["-NoProfile", "-WindowStyle", "Hidden", "-Command", ps])
	get_tree().quit()


func _cleanup_previous_install() -> void:
	if not can_install():
		return
	var old := OS.get_executable_path() + ".old"
	if not FileAccess.file_exists(old):
		return
	# The previous process may still be shutting down; try a few times.
	for attempt in 6:
		if DirAccess.remove_absolute(old) == OK:
			break
		await get_tree().create_timer(1.5).timeout
	var staged := UPDATE_DIR.path_join(App.EXE_NAME)
	if FileAccess.file_exists(staged):
		DirAccess.remove_absolute(staged)


# --- Helpers -----------------------------------------------------------------------

func _headers(accept: String) -> PackedStringArray:
	return PackedStringArray([
		"Accept: %s" % accept,
		"User-Agent: %s/%s" % [App.USER_AGENT, App.version],
		"X-GitHub-Api-Version: 2022-11-28",
	])


func _set_state(s: StringName) -> void:
	state = s
	state_changed.emit(s)


func _fail(message: String) -> void:
	error_text = message
	_set_state(&"error")
