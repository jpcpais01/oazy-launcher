class_name GlassPanel
extends Control
## A pane of liquid glass (shaders/glass.gdshader). Children added to it draw
## on top of the glass. `isolate` grabs a fresh copy of the screen first, so the
## panel also blurs other glass and windows underneath it (used by windows, the
## taskbar and popups; desktop widgets share the first copy and skip it).

const SHADER := preload("res://shaders/glass.gdshader")

## Tints for the common surfaces.
const TINT_WINDOW := Color(0.035, 0.085, 0.11, 0.7)
const TINT_BAR := Color(0.03, 0.08, 0.1, 0.42)
const TINT_POPUP := Color(0.035, 0.085, 0.11, 0.62)
const TINT_WIDGET := Color(0.03, 0.08, 0.1, 0.38)

var radius := 22.0: set = set_radius
var tint := TINT_WIDGET: set = set_tint
var glow := 0.0: set = set_glow
var mat: ShaderMaterial
var _copy: BackBufferCopy
var _rect: ColorRect
var _shadow: Panel


func _init(isolate: bool = false, r: float = 22.0, t: Color = TINT_WIDGET, shadow: bool = true) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_to_group("glass")
	# The copy comes first so the panel's own shadow never tints the glass.
	if isolate:
		_copy = BackBufferCopy.new()
		_copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
		add_child(_copy)
	if shadow:
		_shadow = Panel.new()
		_shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_shadow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(_shadow)
	mat = ShaderMaterial.new()
	mat.shader = SHADER
	_rect = ColorRect.new()
	_rect.color = Color.WHITE
	_rect.material = mat
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_rect)
	radius = r
	tint = t
	resized.connect(_sync)
	apply_effects()


func _ready() -> void:
	_sync()


func set_radius(v: float) -> void:
	radius = v
	if mat:
		mat.set_shader_parameter("radius", v)
		_sync_shadow()


func set_tint(c: Color) -> void:
	tint = c
	if mat:
		mat.set_shader_parameter("tint", c)


func set_glow(v: float) -> void:
	glow = v
	if mat:
		mat.set_shader_parameter("glow", v)
		mat.set_shader_parameter("glow_color", App.accent.lightened(0.2))


func set_shadow_strength(a: float, spread: int = 34, offset_y: float = 14.0) -> void:
	if _shadow == null:
		return
	var s := Kit.box(Color(0, 0, 0, 0), int(radius))
	Kit.shadowed(s, Color(0, 0.02, 0.04, a), spread, Vector2(0, offset_y))
	_shadow.add_theme_stylebox_override("panel", s)


## Eco mode skips the screen blur and uses a more solid tint.
func apply_effects() -> void:
	var eco: bool = Settings.get_value("effects") == "eco"
	mat.set_shader_parameter("use_screen", 0.0 if eco else 1.0)
	if eco:
		var solid := tint
		solid.a = 1.0
		mat.set_shader_parameter("tint", solid.lerp(Color(0.05, 0.11, 0.14), 0.4))
	else:
		mat.set_shader_parameter("tint", tint)


func _sync() -> void:
	mat.set_shader_parameter("rect_size", size)
	_sync_shadow()


func _sync_shadow() -> void:
	if _shadow and not _shadow.has_theme_stylebox_override("panel"):
		set_shadow_strength(0.38)
	elif _shadow:
		var s: StyleBoxFlat = _shadow.get_theme_stylebox("panel")
		s.set_corner_radius_all(int(radius))


static func refresh_all(tree: SceneTree) -> void:
	for g in tree.get_nodes_in_group("glass"):
		if g is GlassPanel:
			g.apply_effects()
