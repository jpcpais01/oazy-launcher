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
## The pointer moved somewhere none of Oazy's windows can see (another
## app's window, Explorer's desktop). Hover is dropped everywhere then.
var pointer_away := false
## Frame cap used when vsync turns out not to pace the frame (0 = none).
var _vsync_cap := 0
var _probe_at := 0
var _probe_frames := 0
var _probed := false
## Any of Oazy's windows got a mouse event since the last frame.
var _heard := false
var _guard_pos := Vector2i.ZERO
## When the pointer started moving without any of Oazy's windows hearing it.
var _unheard_at := 0
var _unheard_frames := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Every scroll view in every window scrolls smoothly (see SmoothScroll).
	get_tree().node_added.connect(func(n: Node) -> void:
		if n is ScrollContainer or n is RichTextLabel:
			_smooth.call_deferred(n)
		elif n is Window:
			_listen(n as Window)
	)
	_listen(get_window())
	version = str(ProjectSettings.get_setting("application/config/version", "0.0.0-dev"))
	var args := OS.get_cmdline_user_args()
	smoke_test = args.has("--smoke-test") or OS.get_cmdline_args().has("--smoke-test")
	for a in args:
		if a.begins_with("--screenshots="):
			screenshot_dir = a.get_slice("=", 1)
			smoke_test = true
	if Array(args).any(func(a: String) -> bool: return a.begins_with("--render-icon=")):
		add_child.call_deferred(load("res://tools/render_icon.gd").new())
	elif screenshot_dir != "":
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
		# Another app is in front. Whatever of Oazy's the pointer is on (the
		# taskbar, the desktop, a menu) still runs at the screen's full rate;
		# with the pointer elsewhere only the clock and the bar are moving.
		if pointer_on_bar or not pointer_away:
			Engine.max_fps = 60 if eco else _vsync_cap
		else:
			Engine.max_fps = 30
	elif not focused:
		# Behind another app: keep the desktop alive but nearly free.
		if not pointer_away and not game_running:
			Engine.max_fps = 60 if eco else _vsync_cap
		else:
			Engine.max_fps = 8 if game_running else 24
	else:
		Engine.max_fps = 60 if eco else _vsync_cap


func _smooth(n: Node) -> void:
	if is_instance_valid(n) and n.is_inside_tree():
		SmoothScroll.attach(n as Control)


func _process(_delta: float) -> void:
	_guard_hover()
	_probe_refresh()


# --- Hover that lets go. -----------------------------------------------------
# Godot learns the pointer left one of its windows from Windows (a
# WM_MOUSELEAVE it asks for once per window it enters). That request is
# sometimes made for the wrong window, after a click or a drag between two of
# Oazy's layers, and then moving onto another app's window tells Godot
# nothing: whatever was under the pointer stayed lit until it came back.
# Windows sends mouse moves to whichever window is under the pointer, so if
# the pointer keeps moving and none of Oazy's windows hears about it, it is
# not over Oazy: let go of hover everywhere.

func _listen(w: Window) -> void:
	if not w.window_input.is_connected(_on_window_input):
		w.window_input.connect(_on_window_input)


func _on_window_input(ev: InputEvent) -> void:
	if ev is InputEventMouse:
		_heard = true


func _guard_hover() -> void:
	var pos := DisplayServer.mouse_get_position()
	if _heard:
		_heard = false
		_unheard_at = 0
		if pointer_away:
			pointer_away = false
			refresh_fps()
	elif pos != _guard_pos and _unheard_at == 0:
		_unheard_at = Time.get_ticks_msec()
		_unheard_frames = 0
	_guard_pos = pos
	if _unheard_at == 0 or pointer_away:
		return
	# A move can land a frame after the cursor does, so give it a moment.
	_unheard_frames += 1
	if _unheard_frames < 3 or Time.get_ticks_msec() - _unheard_at < 60:
		return
	pointer_away = true
	for w in _native_windows():
		w.notify_mouse_exited()
	refresh_fps()


func _native_windows() -> Array[Window]:
	var out: Array[Window] = [get_window()]
	for w in get_tree().get_nodes_in_group("shell_surface"):
		var win := w as Window
		if win.visible and win.get_window_id() != DisplayServer.INVALID_WINDOW_ID:
			out.append(win)
	return out


# --- Frame pacing. -----------------------------------------------------------
## Only Oazy's main window waits for the screen's refresh (its layers don't,
## or each would cost a refresh of its own). Should a driver ignore that and
## let frames run free, cap them at the refresh rate instead. Should waiting
## end up costing two refreshes a frame (half of 120 Hz), stop waiting and
## pace by the clock at the refresh rate: Windows composes Oazy's windows
## anyway, so that can't tear.
func _probe_refresh() -> void:
	if _probed or smoke_test or Engine.max_fps != 0 or not Shell.native or Time.get_ticks_msec() < 6000:
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
		var fps := _probe_frames * 1000.0 / float(now - _probe_at)
		if fps > hz * 1.3:
			_vsync_cap = int(round(hz))
			refresh_fps()
		elif fps < hz * 0.8 and is_windows():
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
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
