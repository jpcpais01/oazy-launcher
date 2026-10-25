class_name LaunchOverlay
extends Control
## Cinematic launch moment: the artwork rises, the name settles in, a light
## bar sweeps, and Oazy politely steps aside.

const BAR := preload("res://shaders/shine_bar.gdshader")
const HERO := preload("res://shaders/hero.gdshader")

signal finished

var entry_id := ""
var _dim: ColorRect
var _hero: TextureRect
var _cover: CoverArt
var _kicker: Label
var _name: Label
var _bar_mat: ShaderMaterial
var _status: Label
var _done := false


func setup(id: String) -> LaunchOverlay:
	entry_id = id
	return self


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_to_group("modal")
	var e := Library.get_entry(entry_id)
	var is_game: bool = e.get("kind", "game") == "game"

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
	hm.set_shader_parameter("darken", 0.55)
	_hero.material = hm
	_hero.texture = Art.get_art(entry_id, &"hero")
	_hero.modulate.a = 0.0
	add_child(_hero)

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
	_name = Kit.label(str(e.get("name", "")), 54, 800, Color.WHITE, true)
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

	# Choreography.
	modulate.a = 0.0
	_cover.pivot_offset = Vector2(105, 157)
	_cover.scale = Vector2.ONE * 0.86
	_name.modulate.a = 0.0
	_kicker.modulate.a = 0.0
	var t := create_tween().set_parallel(true).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	t.tween_property(self, "modulate:a", 1.0, 0.3)
	t.tween_property(_hero, "modulate:a", 1.0, 1.2).set_delay(0.1)
	t.tween_property(_cover, "scale", Vector2.ONE, 0.9).set_trans(Tween.TRANS_BACK)
	t.tween_property(_cover, "focus_amount", 1.0, 0.6).set_delay(0.15)
	t.tween_property(_kicker, "modulate:a", 1.0, 0.5).set_delay(0.2)
	t.tween_property(_name, "modulate:a", 1.0, 0.6).set_delay(0.3)
	t.tween_method(func(v: float) -> void: _bar_mat.set_shader_parameter("progress", v), 0.0, 1.0, 1.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_cover.sweep(0.35)


func success() -> void:
	var t := create_tween()
	t.tween_property(_status, "modulate:a", 1.0, 0.4)
	t.tween_interval(1.5)
	t.tween_callback(func() -> void:
		if Settings.get_value("minimize_on_launch") and not App.smoke_test:
			get_window().mode = Window.MODE_MINIMIZED
	)
	t.tween_interval(0.2)
	t.tween_callback(dismiss)


func fail() -> void:
	_kicker.text = "COULDN'T START"
	_kicker.add_theme_color_override("font_color", App.DANGER)
	_status.text = "Check the details with right-click → Edit."
	_status.modulate.a = 1.0
	var t := create_tween()
	t.tween_interval(1.8)
	t.tween_callback(dismiss)


func dismiss() -> void:
	if _done:
		return
	_done = true
	remove_from_group("modal")
	var t := create_tween()
	t.tween_property(self, "modulate:a", 0.0, 0.35)
	t.tween_callback(func() -> void:
		finished.emit()
		queue_free()
	)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		dismiss()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		dismiss()
		get_viewport().set_input_as_handled()
