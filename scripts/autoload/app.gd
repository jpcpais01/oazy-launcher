extends Node
## Global constants, shared signals and app-wide behaviour (eco mode, smoke tests).

signal toast_requested(text: String, kind: StringName)
signal accent_changed(color: Color)
signal open_page(page: StringName)
signal request_edit(entry_id: String)
signal request_add(prefill: Dictionary)
signal launch_requested(entry_id: String)

const REPO := "jpcpais01/oazy-launcher"
const EXE_NAME := "OazyLauncher.exe"
const USER_AGENT := "OazyLauncher"

const BG := Color("061017")
const SURFACE := Color(1, 1, 1, 0.055)
const SURFACE_HI := Color(1, 1, 1, 0.1)
const STROKE := Color(1, 1, 1, 0.09)
const TEXT := Color("f4f5f8")
const TEXT_DIM := Color("a9adbd")
const TEXT_MUTE := Color("6d7286")
const DEFAULT_ACCENT := Color("38d6c4")
const SUCCESS := Color("3ddc97")
const WARNING := Color("ffb547")
const DANGER := Color("ff5c7a")
const ACCENT_SWATCHES := [
	Color("38d6c4"), Color("4fb4ff"), Color("6fe08a"), Color("f2c46b"),
	Color("ff8f6b"), Color("ff6f91"), Color("a98bff"), Color("e8eef2"),
]

var version := "0.0.0-dev"
var accent := DEFAULT_ACCENT
var smoke_test := false
## Set by --screenshots=<dir>: renders the main screens to PNGs (CI visual check).
var screenshot_dir := ""
var game_running := false
## The pointer is over Oazy's taskbar (shell mode keeps it smooth then).
var pointer_on_bar := false: set = set_pointer_on_bar
## Oazy's Alt+Tab is on screen: it animates at full speed even while
## another app has focus (it never takes focus itself).
var switcher_open := false: set = set_switcher_open
## Frame cap used when vsync turns out not to pace the frame (0 = none).
var _vsync_cap := 0
var _probe_at := 0
var _probe_frames := 0
var _probed := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Every scroll view in every window scrolls smoothly (see SmoothScroll).
	get_tree().node_added.connect(func(n: Node) -> void:
		if n is ScrollContainer or n is RichTextLabel:
			_smooth.call_deferred(n)
	)
	version = str(ProjectSettings.get_setting("application/config/version", "0.0.0-dev"))
	var args := OS.get_cmdline_user_args()
	smoke_test = args.has("--smoke-test") or OS.get_cmdline_args().has("--smoke-test")
	for a in args:
		if a.begins_with("--screenshots="):
			screenshot_dir = a.get_slice("=", 1)
			smoke_test = true
	if screenshot_dir != "":
		print("Oazy Launcher %s screenshot run -> %s" % [version, screenshot_dir])
		var shooter: Node = load("res://tests/screenshots.gd").new()
		shooter.name = "Screenshots"
		add_child.call_deferred(shooter)
	elif smoke_test:
		print("Oazy Launcher %s smoke test starting" % version)
		var runner: Node = load("res://tests/smoke.gd").new()
		runner.name = "SmokeTest"
		add_child.call_deferred(runner)


func is_packaged() -> bool:
	return OS.has_feature("template")


func is_windows() -> bool:
	return OS.get_name() == "Windows"


func toast(text: String, kind: StringName = &"info") -> void:
	toast_requested.emit(text, kind)
	if kind == &"error":
		Sfx.play(&"error")
	elif kind == &"success":
		Sfx.play(&"notify")


func set_accent(color: Color) -> void:
	if color.is_equal_approx(accent):
		return
	accent = color
	accent_changed.emit(color)


## Second accent used for gradients: a hue-shifted, slightly brighter sibling.
func accent_pair(color: Color) -> Color:
	var c := Color.from_hsv(fposmod(color.h + 0.11, 1.0), clampf(color.s * 0.85, 0.0, 1.0), clampf(color.v * 1.05 + 0.05, 0.0, 1.0))
	return c


# --- Eco mode: render less when nobody is looking. ---------------------------

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			_update_fps(false)
		NOTIFICATION_APPLICATION_FOCUS_IN:
			_update_fps(true)


func _update_fps(focused: bool) -> void:
	if smoke_test:
		return
	var eco: bool = Settings.get_value("effects") == "eco"
	if switcher_open:
		Engine.max_fps = 60 if eco else _vsync_cap
	elif Shell.native and Host.fullscreen_app:
		# A game or video has the screen: nothing of Oazy's is visible.
		Engine.max_fps = 5
	elif Shell.native and not focused:
		# Another app is in front but the taskbar is still on screen; it
		# speeds up while the pointer is on it.
		Engine.max_fps = 60 if pointer_on_bar else 30
	elif not focused:
		# Behind another app: keep the desktop alive but nearly free.
		Engine.max_fps = 8 if game_running else 24
	else:
		Engine.max_fps = 60 if eco else _vsync_cap


func _smooth(n: Node) -> void:
	if is_instance_valid(n) and n.is_inside_tree():
		SmoothScroll.attach(n as Control)


## Only Oazy's main window waits for the screen's refresh (its layers don't,
## or each would cost a refresh of its own). Should a driver ignore that and
## let frames run free, cap them at the refresh rate instead.
func _process(_delta: float) -> void:
	if _probed or smoke_test or Engine.max_fps != 0 or not Shell.native:
		_probe_at = 0
		return
	var now := Time.get_ticks_msec()
	if _probe_at == 0:
		_probe_at = now
		_probe_frames = 0
		return
	_probe_frames += 1
	if now - _probe_at >= 2000:
		_probed = true
		var hz := DisplayServer.screen_get_refresh_rate()
		if hz <= 0.0:
			hz = 60.0
		if _probe_frames * 1000.0 / float(now - _probe_at) > hz * 1.3:
			_vsync_cap = int(round(hz))
			refresh_fps()


func refresh_fps() -> void:
	_update_fps(_app_focused())


func set_switcher_open(on: bool) -> void:
	if on == switcher_open:
		return
	switcher_open = on
	refresh_fps()


func set_pointer_on_bar(on: bool) -> void:
	if on == pointer_on_bar:
		return
	pointer_on_bar = on
	refresh_fps()


## Any of Oazy's windows has focus (shell mode has several).
func _app_focused() -> bool:
	if get_window().has_focus():
		return true
	for w in get_tree().get_nodes_in_group("shell_surface"):
		if (w as Window).has_focus():
			return true
	return false


## The Windows account name, tidied up ("joao.pais" -> "Joao").
func user_name() -> String:
	var raw := OS.get_environment("USERNAME")
	if raw == "":
		raw = OS.get_environment("USER")
	raw = raw.get_slice(".", 0).get_slice("_", 0).get_slice(" ", 0)
	if raw == "" or raw.to_lower() in ["user", "admin", "administrator", "runneradmin", "root"]:
		return ""
	return raw.substr(0, 1).to_upper() + raw.substr(1)


func data_dir() -> String:
	return ProjectSettings.globalize_path("user://")
