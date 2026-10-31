class_name RoofVeil
extends ColorRect
## A soft frosted veil behind Claude on the orb popup's roof
## (shaders/roof_veil.gdshader), blurred most where it meets the glass and
## clear toward the top. It has no back buffer copy of its own: it draws right
## after the popup's glass and reuses the copy the glass just made, where the
## roof is still the untouched desktop. In shell mode it draws the wallpaper,
## like GlassPanel.

const SHADER := preload("res://shaders/roof_veil.gdshader")

var mat: ShaderMaterial
var _mirror := false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	color = Color.WHITE
	add_to_group("glass")
	mat = ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("tint", GlassPanel.TINT_POPUP)
	material = mat
	resized.connect(func() -> void: mat.set_shader_parameter("rect_size", size))


func _ready() -> void:
	_mirror = Shell.surface_of(self) != null
	apply_effects()
	mat.set_shader_parameter("rect_size", size)


func apply_effects() -> void:
	if _mirror:
		mat.set_shader_parameter("source", 2)
		sync_wall()
		return
	mat.set_shader_parameter("source", 0 if Settings.get_value("effects") == "eco" else 1)


func sync_wall() -> void:
	if not _mirror:
		return
	for k in Wallpaper.shared:
		mat.set_shader_parameter(k, Wallpaper.shared[k])
	mat.set_shader_parameter("screen_px", Vector2(Shell.screen_px))
