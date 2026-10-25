class_name StartOrb
extends Control
## The Start button: a small orb in the accent colour, with a soft halo that
## blooms on hover and while Start is open.

signal pressed

const SIZE := 50.0
const PLATE := preload("res://shaders/plate.gdshader")

var open := false: set = set_open
var _halo: Panel
var _plate_mat: ShaderMaterial
var _glyph: TextureRect
var _hot := false


func _ready() -> void:
	custom_minimum_size = Vector2(SIZE, SIZE)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tooltip_text = "Start"
	pivot_offset = Vector2(SIZE, SIZE) / 2.0
	_halo = Panel.new()
	_halo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_halo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_halo.modulate.a = 0.0
	add_child(_halo)
	var plate := ColorRect.new()
	_plate_mat = ShaderMaterial.new()
	_plate_mat.shader = PLATE
	_plate_mat.set_shader_parameter("rect_size", Vector2(SIZE - 6.0, SIZE - 6.0))
	_plate_mat.set_shader_parameter("radius", (SIZE - 6.0) / 2.0)
	plate.material = _plate_mat
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.position = Vector2(3, 3)
	plate.size = Vector2(SIZE - 6.0, SIZE - 6.0)
	add_child(plate)
	_glyph = Kit.icon_rect("leaf", 22, Color.WHITE)
	_glyph.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_glyph)
	mouse_entered.connect(_set_hot.bind(true))
	mouse_exited.connect(_set_hot.bind(false))
	App.accent_changed.connect(func(_c: Color) -> void: _restyle())
	_restyle()


func set_open(v: bool) -> void:
	open = v
	if _halo:
		_fade_halo()


func _restyle() -> void:
	var a := App.accent
	_plate_mat.set_shader_parameter("color_a", a.lightened(0.12))
	_plate_mat.set_shader_parameter("color_b", a.darkened(0.3))
	var s := Kit.box(Color(a, 0.0), 999)
	Kit.shadowed(s, Color(a, 0.38), 14, Vector2.ZERO)
	_halo.add_theme_stylebox_override("panel", s)


func _set_hot(on: bool) -> void:
	_hot = on
	_fade_halo()
	var t := create_tween()
	t.tween_property(self, "scale", Vector2.ONE * (1.07 if on else 1.0), 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if on:
		Sfx.play(&"move", 1.25)


func _fade_halo() -> void:
	var t := create_tween()
	t.tween_property(_halo, "modulate:a", 1.0 if (_hot or open) else 0.0, 0.25)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var t := create_tween()
		t.tween_property(self, "scale", Vector2.ONE * 0.9, 0.06)
		t.tween_property(self, "scale", Vector2.ONE * (1.07 if _hot else 1.0), 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		pressed.emit()
		accept_event()
