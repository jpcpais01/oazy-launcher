class_name StartOrb
extends Control
## The Start button: Oazy's icon, live. The water in the orb turns slowly,
## stirs faster on hover and while Start is open, and sends a ripple out when
## pressed, with a soft halo in the accent colour behind it.

signal pressed

const SIZE := 40.0
const CALM := {"swirl": -0.3, "waves": 0.4}
const STIRRED := {"swirl": -0.7, "waves": 0.7}

var open := false: set = set_open
var _halo: Panel
var _orb: UpdateOrb
var _look: Tween
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
	_orb = UpdateOrb.icon(SIZE, 0.9, CALM["swirl"])
	_orb.size = Vector2(SIZE, SIZE)
	add_child(_orb)
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
	Kit.shadowed(s, Color(a.lightened(0.2), 0.26), 10, Vector2.ZERO)
	_halo.add_theme_stylebox_override("panel", s)


func _set_hot(on: bool) -> void:
	_hot = on
	_fade_halo()
	var t := Kit.hover_tween(self)
	t.tween_property(self, "scale", Vector2.ONE * (1.04 if on else 1.0), 0.22).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	if on:
		Sfx.play(&"move", 1.25)


func _fade_halo() -> void:
	var t := Kit.hover_tween(_halo)
	t.tween_property(_halo, "modulate:a", 1.0 if (_hot or open) else 0.0, 0.25)
	if _look:
		_look.kill()
	# A slow, soft ease so the water gathers speed and settles back calmly.
	_look = _orb.set_look(STIRRED if (_hot or open) else CALM, 1.1, Tween.TRANS_CUBIC, Tween.EASE_OUT)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var t := Kit.hover_tween(self)
		t.tween_property(self, "scale", Vector2.ONE * 0.93, 0.06)
		t.tween_property(self, "scale", Vector2.ONE * (1.04 if _hot else 1.0), 0.24).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
		_orb.shockwave(0.6)
		pressed.emit()
		accept_event()
