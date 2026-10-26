class_name LaunchOverlay
extends Control
## Cinematic launch moment: the artwork rises, the name settles in, a light
## bar sweeps, and Oazy politely steps aside once the game's window is up.

const BAR := preload("res://shaders/shine_bar.gdshader")
const HERO := preload("res://shaders/hero.gdshader")
## Seconds before the status admits the game is taking a while.
const SLOW_AFTER := 9.0
## Seconds before Oazy stops waiting and gets out of the way.
const GIVE_UP_AFTER := 45.0
## Without the companion Oazy can't see the game's window, so it leaves after
## a short, fixed beat (the old timing).
const BLIND_HOLD := 1.9

signal finished

var entry_id := ""
## Opens the entry's details when a launch fails.
var on_edit := Callable()
var _entry := {}
var _dim: ColorRect
var _hero: TextureRect
var _cover: CoverArt
var _kicker: Label
var _name: Label
var _bar_mat: ShaderMaterial
var _status: Label
var _actions: HBoxContainer
var _progress := 0.0
var _started := false
var _watching := false
var _slow := false
var _failed := false
var _done := false
var _elapsed := 0.0
var _start_fg := 0
var _start_windows := {}


func setup(id: String) -> LaunchOverlay:
	entry_id = id
	return self


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_to_group("modal")
	_entry = Library.get_entry(entry_id)
	var is_game: bool = _entry.get("kind", "game") == "game"
	_start_fg = Host.foreground
	for w in Host.windows:
		_start_windows[int(w["hwnd"])] = true

	_dim = ColorRect.new()
	_dim.color = Color(0.015, 0.015, 0.03, 0.9)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dim)

	_hero = TextureRect.new()
	_hero.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hero.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_hero.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_hero.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hm := ShaderMaterial.new()
	hm.shader = HERO
	hm.set_shader_parameter("darken", 0.5)
	_hero.material = hm
	_hero.texture = Art.get_art(entry_id, &"hero")
	_hero.modulate.a = 0.0
	_hero.resized.connect(func() -> void: _hero.pivot_offset = _hero.size / 2.0)
	add_child(_hero)
	Art.art_ready.connect(_on_art_ready)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var col := Kit.vbox(18)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(col)

	var cover_holder := CenterContainer.new()
	col.add_child(cover_holder)
	_cover = CoverArt.new()
	_cover.custom_minimum_size = Vector2(210, 315)
	cover_holder.add_child(_cover)
	_cover.setup(entry_id, 20.0)

	col.add_child(Kit.spacer(0, 10))
	_kicker = Kit.label("LAUNCHING" if is_game else "OPENING", 14, 700, App.accent.lightened(0.4))
	var kv := FontVariation.new()
	kv.base_font = Kit.font(700)
	kv.spacing_glyph = 5
	_kicker.add_theme_font_override("font", kv)
	_kicker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_kicker)
	_name = Kit.label(str(_entry.get("name", "")), 54, 700, Color.WHITE, true)
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_name)

	var bar_holder := CenterContainer.new()
	col.add_child(bar_holder)
	var bar := ColorRect.new()
	bar.custom_minimum_size = Vector2(300, 4)
	_bar_mat = ShaderMaterial.new()
	_bar_mat.shader = BAR
	_bar_mat.set_shader_parameter("rect_size", Vector2(300, 4))
	_bar_mat.set_shader_parameter("color_a", App.accent)
	_bar_mat.set_shader_parameter("color_b", App.accent_pair(App.accent))
	bar.material = _bar_mat
	bar_holder.add_child(bar)
	_status = Kit.label("Have fun!" if is_game else "", 15, 500, App.TEXT_DIM)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.modulate.a = 0.0
	col.add_child(_status)
	_actions = Kit.hbox(10)
	_actions.alignment = BoxContainer.ALIGNMENT_CENTER
	_actions.modulate.a = 0.0
	col.add_child(_actions)

	# Choreography: same beats as before, with soft ease-outs instead of a spring.
	modulate.a = 0.0
	_cover.pivot_offset = Vector2(105, 157)
	_cover.scale = Vector2.ONE * 0.9
	_name.modulate.a = 0.0
	_kicker.modulate.a = 0.0
	_hero.scale = Vector2.ONE * 1.04
	var t := create_tween().set_parallel(true).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	t.tween_property(self, "modulate:a", 1.0, 0.3).set_trans(Tween.TRANS_QUART)
	t.tween_property(_hero, "modulate:a", 1.0, 1.0).set_delay(0.1).set_trans(Tween.TRANS_SINE)
	t.tween_property(_hero, "scale", Vector2.ONE, 1.6)
	t.tween_property(_cover, "scale", Vector2.ONE, 0.8)
	t.tween_property(_cover, "focus_amount", 1.0, 0.6).set_delay(0.15)
	t.tween_property(_kicker, "modulate:a", 1.0, 0.5).set_delay(0.2).set_trans(Tween.TRANS_SINE)
	t.tween_property(_name, "modulate:a", 1.0, 0.6).set_delay(0.3).set_trans(Tween.TRANS_SINE)
	# The bar runs to about two thirds on its own, then waits for the game.
	t.tween_method(_set_progress, 0.0, 0.62, 1.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_cover.sweep(0.35)


## The launch went out: wait for the game's window.
func success() -> void:
	if _done:
		return
	_started = true
	_elapsed = 0.0
	create_tween().tween_property(_status, "modulate:a", 1.0, 0.4)
	if Host.available and not Host.mocked:
		_watching = true
		Host.windows_changed.connect(_check_game)
		Host.fullscreen_changed.connect(func(_on: bool) -> void: _check_game())
		_check_game()
	else:
		var t := create_tween()
		t.tween_interval(BLIND_HOLD)
		t.tween_callback(hand_off)


func fail() -> void:
	if _done:
		return
	_failed = true
	_watching = false
	_kicker.text = "COULDN'T START"
	_kicker.add_theme_color_override("font_color", App.DANGER)
	var store := Library.source_label(_entry)
	_status.text = ("%s didn't open it. Its details may need a look." % store) if store not in ["Game", "App"] else "Its file or launch options may need a look."
	_status.modulate.a = 1.0
	var edit := FxButton.make("Edit details", "edit", FxButton.Style.GHOST, 40)
	edit.pressed.connect(func() -> void:
		dismiss()
		if on_edit.is_valid():
			on_edit.call(entry_id)
	)
	var close := FxButton.make("Close", "", FxButton.Style.GHOST, 40)
	close.custom_minimum_size.x = 100
	close.pressed.connect(dismiss)
	_actions.add_child(edit)
	_actions.add_child(close)
	create_tween().tween_property(_actions, "modulate:a", 1.0, 0.3).set_delay(0.1)
	edit.grab_focus.call_deferred()


## The launcher is taking its time: say so, and how to get back to work.
func show_slow() -> void:
	_slow = true
	var store := Library.source_label(_entry)
	var text := ("%s can take a moment. " % store if store not in ["Game", "App"] else "Still starting. ") + "Press Esc to wait on your desktop."
	var t := create_tween()
	t.tween_property(_status, "modulate:a", 0.0, 0.18)
	t.tween_callback(func() -> void: _status.text = text)
	t.tween_property(_status, "modulate:a", 1.0, 0.3)


## The game is on screen: finish the bar and fade into it.
func hand_off() -> void:
	if _done:
		return
	_done = true
	_watching = false
	remove_from_group("modal")
	if Settings.get_value("minimize_for_games") and not App.smoke_test:
		get_window().mode = Window.MODE_MINIMIZED
	var t := create_tween().set_parallel(true)
	t.tween_method(_set_progress, _progress, 1.0, 0.25).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	t.tween_property(self, "modulate:a", 0.0, 0.35).set_delay(0.15).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.chain().tween_callback(_finish)


## Leave without waiting for the game (Esc, a click, Close, or giving up).
func dismiss() -> void:
	if _done:
		return
	_done = true
	_watching = false
	remove_from_group("modal")
	var t := create_tween()
	t.tween_property(self, "modulate:a", 0.0, 0.3).set_trans(Tween.TRANS_SINE)
	t.tween_callback(_finish)


func close() -> void:
	dismiss()


func _finish() -> void:
	finished.emit()
	queue_free()


func _set_progress(v: float) -> void:
	_progress = v
	_bar_mat.set_shader_parameter("progress", v)


func _process(delta: float) -> void:
	if not _started or _done or _failed:
		return
	_elapsed += delta
	# No real progress to read, so the bar creeps on ever more slowly.
	if _elapsed > 1.4:
		_set_progress(maxf(_progress, 0.62 + 0.3 * (1.0 - exp(-(_elapsed - 1.4) / 8.0))))
	if _watching and not _slow and _elapsed > SLOW_AFTER:
		show_slow()
	if _watching and _elapsed > GIVE_UP_AFTER:
		App.toast("%s is still starting" % str(_entry.get("name", "Your game")))
		dismiss()


## Steps aside as soon as anything but Oazy takes the screen: the game, or a
## launcher dialog that would otherwise sit hidden under this layer.
func _check_game() -> void:
	if not _watching or _done:
		return
	if Host.fullscreen_app or (not Host.self_foreground and Host.foreground != 0 and Host.foreground != _start_fg):
		hand_off()
		return
	# A game Oazy started itself may show its window before it takes focus.
	var image := Library.session_image(entry_id)
	if image == "":
		return
	for w in Host.windows:
		if not _start_windows.has(int(w["hwnd"])) and str(w["exe"]).replace("\\", "/").get_file().to_lower() == image:
			hand_off()
			return


func _on_art_ready(id: String, kind: StringName) -> void:
	if id == entry_id and kind == &"hero" and _hero.texture == null and not _done:
		_hero.texture = Art.get_art(entry_id, &"hero")


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		dismiss()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		dismiss()
		get_viewport().set_input_as_handled()
