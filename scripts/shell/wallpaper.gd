class_name Wallpaper
extends ColorRect
## The desktop background (shaders/oasis.gdshader). Its sky follows the local
## time of day unless a fixed light is picked in Settings.

const SHADER := preload("res://shaders/oasis.gdshader")
## sky_top, sky_mid, horizon, ground, sun
const PALETTES := {
	"night": [Color("04121d"), Color("0a2f3c"), Color("6a4a5e"), Color("030a0f"), Color("bcd6ff")],
	"dawn": [Color("0f2747"), Color("2b647b"), Color("f0a47c"), Color("0c151e"), Color("ffd8b6")],
	"day": [Color("0a3f60"), Color("17808f"), Color("ecca94"), Color("0b1f25"), Color("fff3da")],
	"dusk": [Color("141a3d"), Color("304b69"), Color("ee8f6b"), Color("0a0f1e"), Color("ffc49c")],
}
const PARAMS := ["sky_top", "sky_mid", "horizon", "ground", "sun_color"]
## Hour -> palette keyframes for "auto".
const KEYS := [[0.0, "night"], [5.0, "night"], [7.0, "dawn"], [9.5, "day"], [16.5, "day"], [19.0, "dusk"], [21.0, "night"], [24.0, "night"]]

var mat: ShaderMaterial
var _accent_tween: Tween
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
			mat.set_shader_parameter("aspect", size.x / size.y)
	)
	App.accent_changed.connect(_tween_accent)
	Settings.changed.connect(func(key: String, _v: Variant) -> void:
		if key == "effects":
			apply_effects()
		elif key == "wallpaper_light":
			update_sky()
	)
	var timer := Timer.new()
	timer.wait_time = 60.0
	timer.autostart = true
	timer.timeout.connect(update_sky)
	add_child(timer)
	mat.set_shader_parameter("accent", _accent)
	apply_effects()
	update_sky()


func apply_effects() -> void:
	var eco: bool = Settings.get_value("effects") == "eco"
	mat.set_shader_parameter("speed", 0.35 if eco else 1.0)
	mat.set_shader_parameter("bubbles", 0.0 if eco else 1.0)


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
		mat.set_shader_parameter(PARAMS[i], p[i])


func _tween_accent(c: Color) -> void:
	if _accent_tween and _accent_tween.is_valid():
		_accent_tween.kill()
	var from := _accent
	_accent_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_accent_tween.tween_method(func(k: float) -> void:
		_accent = from.lerp(c, k)
		mat.set_shader_parameter("accent", _accent)
	, 0.0, 1.0, 0.8)
