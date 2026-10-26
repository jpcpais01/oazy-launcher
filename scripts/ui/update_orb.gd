class_name UpdateOrb
extends ColorRect
## The water-filled glass orb from shaders/update_orb.gdshader. `progress` is
## eased towards `target` every frame so jumpy download numbers still pour in
## smoothly; the other looks are tweened with set_look().

const SHADER := preload("res://shaders/update_orb.gdshader")
const LOOK_DEFAULTS := {"waves": 1.0, "swirl": 0.0, "error": 0.0, "ripples": 1.0, "pulse": -1.0}

var mat: ShaderMaterial
var target := 0.0
var shown := 0.0


func _init(px: float = 400.0, orb_size: float = 0.56) -> void:
	custom_minimum_size = Vector2(px, px)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	color = Color.WHITE
	mat = ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("orb", orb_size)
	for key in LOOK_DEFAULTS:
		mat.set_shader_parameter(key, LOOK_DEFAULTS[key])
	material = mat


func _ready() -> void:
	mat.set_shader_parameter("color_a", App.accent)
	mat.set_shader_parameter("color_b", App.accent_pair(App.accent))
	mat.set_shader_parameter("warn", App.WARNING)


func _process(delta: float) -> void:
	shown = lerpf(shown, target, 1.0 - exp(-delta * 5.0))
	if absf(shown - target) < 0.0005:
		shown = target
	mat.set_shader_parameter("progress", shown)


func snap(value: float) -> void:
	target = value
	shown = value
	mat.set_shader_parameter("progress", value)


## Tweens shader looks: waves, swirl, error, ripples.
func set_look(look: Dictionary, time: float = 0.6) -> Tween:
	var t := create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	for key in look:
		var from: float = mat.get_shader_parameter(key)
		t.tween_method(func(v: float) -> void: mat.set_shader_parameter(key, v), from, float(look[key]), time)
	return t


## One bright ring that runs out over the ripples.
func shockwave(time: float = 1.3) -> void:
	var t := create_tween()
	t.tween_method(func(v: float) -> void: mat.set_shader_parameter("pulse", v), 0.0, 1.0, time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_callback(func() -> void: mat.set_shader_parameter("pulse", -1.0))
