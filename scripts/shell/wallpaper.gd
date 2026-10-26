class_name Wallpaper
extends ColorRect
## The desktop background (shaders/oasis.gdshader): one of a few calm, slowly
## moving styles, lit by colours that follow the local time of day unless a
## fixed light is picked in Settings.

const SHADER := preload("res://shaders/oasis.gdshader")
## base, pool a, pool b, pool c, glow
const PALETTES := {
	"night": [Color("05070d"), Color("1d2b5a"), Color("0d404d"), Color("281a3c"), Color("8fb4ff")],
	"dawn": [Color("0a1020"), Color("2f3c72"), Color("1b5566"), Color("b5786a"), Color("ffd2b0")],
	"day": [Color("1c68ad"), Color("3a98dc"), Color("2aa0cf"), Color("7cc3e6"), Color("ffffff")],
	"dusk": [Color("0b0919"), Color("3f2a61"), Color("173d55"), Color("b0594f"), Color("ffc0a0")],
}
## Settings id -> [name, wall_style], in the order Settings shows them.
const STYLES := {
	"oasis": ["Oasis", 0],
	"aurora": ["Aurora", 1],
	"tide": ["Tide", 2],
	"drift": ["Drift", 3],
}
const PARAMS := ["wall_base", "wall_a", "wall_b", "wall_c", "wall_glow"]
## Hour -> palette keyframes for "auto".
const KEYS := [[0.0, "night"], [5.0, "night"], [7.0, "dawn"], [9.5, "day"], [16.5, "day"], [19.0, "dusk"], [21.0, "night"], [24.0, "night"]]

## The wallpaper's current shader parameters, for glass that draws it itself.
static var shared := {}

var mat: ShaderMaterial
var _accent_tween: Tween
var _fade_tween: Tween
var _accent := App.accent


func _init() -> void:
	mat = ShaderMaterial.new()
	mat.shader = SHADER
	material = mat
	color = Color.WHITE
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(func() -> void:
		if size.y > 0.0:
			_param("aspect", size.x / size.y)
			_publish()
	)
	App.accent_changed.connect(_tween_accent)
	Settings.changed.connect(func(key: String, _v: Variant) -> void:
		if key == "effects":
			apply_effects()
		elif key == "wallpaper_light":
			update_sky()
		elif key == "wallpaper":
			apply_style()
	)
	var timer := Timer.new()
	timer.wait_time = 60.0
	timer.autostart = true
	timer.timeout.connect(update_sky)
	add_child(timer)
	_param("accent", _accent)
	apply_style()
	apply_effects()
	update_sky()


func apply_effects() -> void:
	var eco: bool = Settings.get_value("effects") == "eco"
	_param("speed", 0.35 if eco else 1.0)
	_publish()


## Switches to the style picked in Settings, crossfading from the old one.
func apply_style() -> void:
	var to := style_index(str(Settings.get_value("wallpaper")))
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
	if not is_inside_tree() or not mat.get_shader_parameter("wall_style") is int or to == mat.get_shader_parameter("wall_style"):
		_param("wall_style", to)
		_param("wall_fade", 1.0)
		_publish()
		return
	_param("wall_from", mat.get_shader_parameter("wall_style"))
	_param("wall_style", to)
	_fade_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_fade_tween.tween_method(func(k: float) -> void:
		_param("wall_fade", k)
		_publish()
	, 0.0, 1.0, 0.9)


static func style_index(id: String) -> int:
	return int(STYLES.get(id, STYLES["oasis"])[1])


## Palette for a fixed light, or blended from the clock for "auto".
static func palette_for(light: String, hour: float) -> Array:
	if PALETTES.has(light):
		return PALETTES[light]
	for i in KEYS.size() - 1:
		var a: Array = KEYS[i]
		var b: Array = KEYS[i + 1]
		if hour >= float(a[0]) and hour <= float(b[0]):
			var k := 0.0 if is_equal_approx(float(a[0]), float(b[0])) else (hour - float(a[0])) / (float(b[0]) - float(a[0]))
			k = k * k * (3.0 - 2.0 * k)
			var pa: Array = PALETTES[a[1]]
			var pb: Array = PALETTES[b[1]]
			var out := []
			for j in pa.size():
				out.append((pa[j] as Color).lerp(pb[j], k))
			return out
	return PALETTES["night"]


func update_sky() -> void:
	var t := Time.get_time_dict_from_system()
	var hour := float(t["hour"]) + float(t["minute"]) / 60.0
	var p := palette_for(str(Settings.get_value("wallpaper_light")), hour)
	for i in PARAMS.size():
		_param(PARAMS[i], p[i])
	_publish()


func _tween_accent(c: Color) -> void:
	if _accent_tween and _accent_tween.is_valid():
		_accent_tween.kill()
	var from := _accent
	_accent_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_accent_tween.tween_method(func(k: float) -> void:
		_accent = from.lerp(c, k)
		_param("accent", _accent)
		_publish()
	, 0.0, 1.0, 0.8)


func _param(param: String, value: Variant) -> void:
	mat.set_shader_parameter(param, value)
	if is_inside_tree() and get_tree().current_scene == get_parent():
		shared[param] = value


func _publish() -> void:
	if is_inside_tree() and get_tree().current_scene == get_parent():
		get_tree().call_group("glass", "sync_wall")
