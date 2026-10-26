class_name GlassPanel
extends Control
## A pane of liquid glass (shaders/glass.gdshader). Children added to it draw
## on top of the glass. `isolate` grabs a fresh copy of the screen first, so the
## panel also blurs other glass and windows underneath it (used by windows, the
## taskbar and popups; desktop widgets share the first copy and skip it).
## In shell mode, panels on Oazy's layers draw the wallpaper behind them
## instead, since each layer is its own window.

const SHADER := preload("res://shaders/glass.gdshader")

## Tints for the common surfaces: a cool, nearly neutral smoke.
const TINT_WINDOW := Color(0.055, 0.065, 0.085, 0.66)
const TINT_BAR := Color(0.05, 0.06, 0.08, 0.4)
const TINT_POPUP := Color(0.055, 0.065, 0.085, 0.58)
const TINT_WIDGET := Color(0.05, 0.06, 0.08, 0.3)

var radius := 22.0: set = set_radius
var tint := TINT_WIDGET: set = set_tint
var glow := 0.0: set = set_glow
var mat: ShaderMaterial
var _copy: BackBufferCopy
var _rect: ColorRect
var _shadow: Panel
var _mirror := false
var _shadow_spread := 0.0
var _shadow_off := 0.0


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
	_mirror = Shell.surface_of(self) != null
	if _mirror and _copy:
		_copy.copy_mode = BackBufferCopy.COPY_MODE_DISABLED
	apply_effects()
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
	_shadow_spread = spread
	_shadow_off = offset_y


## Fades the shadow on its own. Modulate isn't group opacity, so when a whole
## card fades, a shadow left at full strength shows through it as a dark smudge.
func set_shadow_fade(v: float) -> void:
	if _shadow:
		_shadow.modulate.a = v


## The panel and its shadow in global coordinates: what a shell layer keeps on
## screen so the shadow fades out instead of being cut off.
func shadow_rect() -> Rect2:
	var r := get_global_rect()
	if _shadow == null:
		return r.grow(2.0)
	var s := _shadow_spread + 2.0
	var top := maxf(2.0, s - _shadow_off)
	return Rect2(r.position.x - s, r.position.y - top, r.size.x + s * 2.0, r.size.y + top + s + _shadow_off)


## Eco mode skips the screen blur and uses a more solid tint.
func apply_effects() -> void:
	var eco: bool = Settings.get_value("effects") == "eco"
	if _mirror:
		mat.set_shader_parameter("source", 2)
		sync_wall()
		mat.set_shader_parameter("tint", tint)
		return
	mat.set_shader_parameter("source", 0 if eco else 1)
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
		set_shadow_strength(0.26, 24, 8.0)
	elif _shadow:
		var s: StyleBoxFlat = _shadow.get_theme_stylebox("panel")
		s.set_corner_radius_all(int(radius))


## Copies the wallpaper's look, for panels that draw it themselves.
func sync_wall() -> void:
	if not _mirror:
		return
	for k in Wallpaper.shared:
		mat.set_shader_parameter(k, Wallpaper.shared[k])
	mat.set_shader_parameter("screen_px", Vector2(Shell.screen_px))


static func refresh_all(tree: SceneTree) -> void:
	for g in tree.get_nodes_in_group("glass"):
		if g is GlassPanel:
			g.apply_effects()
