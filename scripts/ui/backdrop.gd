class_name Backdrop
extends Control
## The living background: aurora shader tinted by the current accent, with the
## selected game's hero art cross-faded on top (slow Ken Burns drift included).

const AURORA := preload("res://shaders/aurora.gdshader")
const HERO := preload("res://shaders/hero.gdshader")

var _aurora: ColorRect
var _aurora_mat: ShaderMaterial
var _heroes: Array[TextureRect] = []
var _front := 0
var _current_tex: Texture2D
var _accent_tween: Tween
var _cur_a := App.DEFAULT_ACCENT
var _cur_b := App.accent_pair(App.DEFAULT_ACCENT)
var _from_a := Color.BLACK
var _from_b := Color.BLACK
var _to_a := Color.BLACK
var _to_b := Color.BLACK


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_aurora_mat = ShaderMaterial.new()
	_aurora_mat.shader = AURORA
	_aurora = ColorRect.new()
	_aurora.material = _aurora_mat
	_aurora.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_aurora.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_aurora)
	for i in 2:
		var t := TextureRect.new()
		t.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var m := ShaderMaterial.new()
		m.shader = HERO
		t.material = m
		t.modulate.a = 0.0
		add_child(t)
		_heroes.append(t)
	resized.connect(_on_resized)
	App.accent_changed.connect(set_accent)
	Settings.changed.connect(_on_setting)
	_apply_effects()
	_apply_accent(App.accent, App.accent_pair(App.accent))
	_on_resized()


func set_hero(tex: Texture2D) -> void:
	if tex == _current_tex:
		return
	_current_tex = tex
	var old := _heroes[_front]
	_front = 1 - _front
	var fresh := _heroes[_front]
	var t := create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(old, "modulate:a", 0.0, 0.6)
	if tex != null:
		fresh.texture = tex
		fresh.pivot_offset = size / 2.0
		fresh.scale = Vector2.ONE * 1.07
		move_child(fresh, -1)
		t.tween_property(fresh, "modulate:a", 1.0, 0.75)
		var drift := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		drift.tween_property(fresh, "scale", Vector2.ONE * 1.0, 9.0)


func set_accent(color: Color) -> void:
	var target_b := App.accent_pair(color)
	if _accent_tween and _accent_tween.is_valid():
		_accent_tween.kill()
	_from_a = _cur_a
	_from_b = _cur_b
	_to_a = color
	_to_b = target_b
	_accent_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_accent_tween.tween_method(_blend_accent, 0.0, 1.0, 0.9)


func _blend_accent(k: float) -> void:
	_apply_accent(_from_a.lerp(_to_a, k), _from_b.lerp(_to_b, k))


func set_loading_mode(amount: float) -> void:
	_aurora_mat.set_shader_parameter("focus_center", amount)


func _apply_accent(a: Color, b: Color) -> void:
	_cur_a = a
	_cur_b = b
	_aurora_mat.set_shader_parameter("accent", a)
	_aurora_mat.set_shader_parameter("accent2", b)


func _on_resized() -> void:
	if size.y > 0.0:
		_aurora_mat.set_shader_parameter("aspect", size.x / size.y)
	for h in _heroes:
		h.pivot_offset = size / 2.0


func _on_setting(key: String, _v: Variant) -> void:
	if key == "effects":
		_apply_effects()


func _apply_effects() -> void:
	var eco: bool = Settings.get_value("effects") == "eco"
	_aurora_mat.set_shader_parameter("speed", 0.5 if eco else 1.0)
	_aurora_mat.set_shader_parameter("stars", 0.0 if eco else 1.0)
