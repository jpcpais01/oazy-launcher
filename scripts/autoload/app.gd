extends Node
## Global constants, shared signals and app-wide behaviour (eco mode, smoke tests).

signal toast_requested(text: String, kind: StringName)
signal accent_changed(color: Color)
signal open_page(page: StringName)
signal request_edit(entry_id: String)
signal request_add(prefill: Dictionary)

const REPO := "jpcpais01/oazy-launcher"
const EXE_NAME := "OazyLauncher.exe"
const USER_AGENT := "OazyLauncher"

const BG := Color("07080d")
const SURFACE := Color(1, 1, 1, 0.055)
const SURFACE_HI := Color(1, 1, 1, 0.1)
const STROKE := Color(1, 1, 1, 0.09)
const TEXT := Color("f4f5f8")
const TEXT_DIM := Color("a9adbd")
const TEXT_MUTE := Color("6d7286")
const DEFAULT_ACCENT := Color("7c6cff")
const SUCCESS := Color("3ddc97")
const WARNING := Color("ffb547")
const DANGER := Color("ff5c7a")
const ACCENT_SWATCHES := [
	Color("7c6cff"), Color("3d8bff"), Color("19c3b1"), Color("3ddc97"),
	Color("ffb547"), Color("ff7a45"), Color("ff5c7a"), Color("e45cff"),
]

var version := "0.0.0-dev"
var accent := DEFAULT_ACCENT
var smoke_test := false
var game_running := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	version = str(ProjectSettings.get_setting("application/config/version", "0.0.0-dev"))
	var args := OS.get_cmdline_user_args()
	smoke_test = args.has("--smoke-test") or OS.get_cmdline_args().has("--smoke-test")
	if smoke_test:
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
	if not focused:
		Engine.max_fps = 12 if game_running else 30
	else:
		Engine.max_fps = 60 if eco else 0


func refresh_fps() -> void:
	_update_fps(get_window().has_focus())


func data_dir() -> String:
	return ProjectSettings.globalize_path("user://")
