class_name StartOrb
extends Control
## The Start button: Oazy's own app icon, with a soft halo in the accent colour
## that blooms on hover and while Start is open.

signal pressed

const SIZE := 50.0
const ICON := preload("res://assets/icon.png")

var open := false: set = set_open
var _halo: Panel
var _icon: TextureRect
var _hot := false


func _ready() -> void:
	custom_minimum_size = Vector2(SIZE, SIZE)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tooltip_text = "Start"
	pivot_offset = Vector2(SIZE, SIZE) / 2.0
	_halo = Panel.new()
	_halo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_halo.position = Vector2(4, 4)
	_halo.size = Vector2(SIZE - 8.0, SIZE - 8.0)
	_halo.modulate.a = 0.0
	add_child(_halo)
	_icon = TextureRect.new()
	_icon.texture = ICON
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon.position = Vector2(3, 3)
	_icon.size = Vector2(SIZE - 6.0, SIZE - 6.0)
	add_child(_icon)
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
	var s := Kit.box(Color(a, 0.0), 12)
	Kit.shadowed(s, Color(a.lightened(0.2), 0.42), 14, Vector2.ZERO)
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
