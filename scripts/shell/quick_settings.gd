class_name QuickSettings
extends Flyout
## Quick settings from the tray: speaker volume and mute, media controls for
## whatever is playing, and shortcuts to the Windows settings people reach for
## most (Wi-Fi, Bluetooth, display, sound). Talks to the native host for audio.

signal volume_changed(level: float, muted: bool)

var level := -1.0
var muted := false
var _slider: HSlider
var _pct: Label
var _mute_btn: FxButton
var _device: Label
var _battery: Label
var _play_btn: FxButton
var _send_timer: Timer
var _sent := -1.0


func _init() -> void:
	width = 380.0


func _build() -> void:
	var head := Kit.hbox(8)
	content.add_child(head)
	head.add_child(Kit.label("Sound", 15, 700, App.TEXT))
	head.add_child(Kit.spacer(0, 0, true))
	_device = Kit.label("", 12, 500, App.TEXT_MUTE)
	_device.clip_text = true
	_device.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_device.custom_minimum_size.x = 200
	_device.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	head.add_child(_device)

	var row := Kit.hbox(12)
	content.add_child(row)
	_mute_btn = FxButton.icon_only("volume", "Mute", 20, 40)
	_mute_btn.focus_mode = Control.FOCUS_NONE
	_mute_btn.pressed.connect(func() -> void: set_muted(not muted))
	row.add_child(_mute_btn)
	_slider = HSlider.new()
	_slider.min_value = 0
	_slider.max_value = 100
	_slider.step = 1
	_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_slider.focus_mode = Control.FOCUS_NONE
	_slider.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_slider.value_changed.connect(_on_slider)
	row.add_child(_slider)
	_pct = Kit.label("–", 14, 700, App.TEXT)
	_pct.custom_minimum_size.x = 40
	_pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_pct.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_pct)

	var media := Kit.hbox(8)
	media.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_child(media)
	var prev := FxButton.icon_only("skip_back", "Previous", 18, 42)
	prev.pressed.connect(func() -> void: media_key("prev"))
	_play_btn = FxButton.icon_only("play", "Play / pause", 20, 48)
	_play_btn.variant = FxButton.Style.GHOST
	_play_btn._apply_style()
	_play_btn.pressed.connect(func() -> void: media_key("play"))
	var next := FxButton.icon_only("skip_forward", "Next", 18, 42)
	next.pressed.connect(func() -> void: media_key("next"))
	for b in [prev, _play_btn, next]:
		b.focus_mode = Control.FOCUS_NONE
		media.add_child(b)

	var line := HSeparator.new()
	line.add_theme_stylebox_override("separator", Kit._line_box())
	content.add_child(line)

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	content.add_child(grid)
	for t in [
		["wifi", "Wi-Fi", "ms-settings:network-wifi"],
		["bluetooth", "Bluetooth", "ms-settings:bluetooth"],
		["monitor", "Display", "ms-settings:display"],
		["moon", "Night light", "ms-settings:nightlight"],
		["volume", "Sound", "ms-settings:sound"],
		["settings", "All settings", "ms-settings:"],
	]:
		var uri: String = t[2]
		grid.add_child(Flyout.tile(t[0], t[1], func() -> void:
			close()
			_open_uri(uri)
		))

	_battery = Kit.label("", 13, 600, App.TEXT_DIM)
	_battery.visible = false
	content.add_child(_battery)

	_send_timer = Timer.new()
	_send_timer.wait_time = 0.06
	_send_timer.one_shot = true
	_send_timer.timeout.connect(_flush)
	add_child(_send_timer)


func _on_open() -> void:
	refresh()


# --- Volume -----------------------------------------------------------------------------

## Asks the host for the current volume (also used by the tray icon).
func refresh() -> void:
	Host.request(["volume"], _apply)


func _apply(d: Dictionary) -> void:
	if not _send_timer.is_stopped():
		return
	if not d.get("ok", false):
		_device.text = "Sound controls need Windows" if not App.is_windows() else ""
		return
	level = float(d.get("level", 0.0))
	muted = bool(d.get("muted", false))
	_device.text = str(d.get("device", ""))
	_sync_ui()
	volume_changed.emit(level, muted)


func _sync_ui() -> void:
	_slider.set_value_no_signal(roundf(level * 100.0))
	_pct.text = "Muted" if muted else "%d%%" % int(roundf(level * 100.0))
	_mute_btn.icon = Icons.tex(icon_for(level, muted), 20, Color.WHITE)
	_mute_btn.tooltip_text = "Unmute" if muted else "Mute"


func _on_slider(v: float) -> void:
	level = v / 100.0
	if level > 0.0:
		muted = false
	_sync_ui()
	if _send_timer.is_stopped():
		_send_timer.start()


func _flush() -> void:
	if absf(_sent - level) < 0.001:
		return
	_sent = level
	Host.request(["volume_set", "%.3f" % level], _apply)


func set_volume(v: float) -> void:
	level = clampf(v, 0.0, 1.0)
	if level > 0.0:
		muted = false
	_sync_ui()
	_sent = level
	Host.request(["volume_set", "%.3f" % level], _apply)
	volume_changed.emit(level, muted)


## Scroll on the tray icon: two percent per notch, like Windows.
func nudge(delta: float) -> void:
	if level < 0.0:
		return
	set_volume(roundf((level + delta) * 50.0) / 50.0)


func set_muted(on: bool) -> void:
	muted = on
	_sync_ui()
	Host.request(["mute", "1" if on else "0"], _apply)
	volume_changed.emit(level, muted)


static func icon_for(v: float, is_muted: bool) -> String:
	if is_muted or v <= 0.0:
		return "volume_x"
	return "volume_low" if v < 0.5 else "volume"


# --- Media and settings -----------------------------------------------------------------

func media_key(which: String) -> void:
	Host.request(["media", which])


func set_battery(percent: int, charging: bool) -> void:
	_battery.visible = percent >= 0
	_battery.text = "Battery %d%%%s" % [percent, ", charging" if charging else ""]


func _open_uri(uri: String) -> void:
	if not App.is_windows():
		App.toast("That opens on Windows")
		return
	OS.shell_open(uri)
