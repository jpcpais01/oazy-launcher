class_name CoverArt
extends Control
## Rounded artwork for one library entry, with a procedural fallback cover,
## focus ring, accent glow and a light sweep. Updates itself when art arrives.

const SHADER := preload("res://shaders/cover.gdshader")

var entry_id := ""
var kind: StringName = &"cover"
var radius := 16.0
var focus_amount := 0.0: set = set_focus_amount
var glow_enabled := true

var _rect: ColorRect
var _mat: ShaderMaterial
var _initials: Label
var _glow: Panel
var _sweep_tween: Tween


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func setup(id: String, r: float = 16.0, art_kind: StringName = &"cover") -> CoverArt:
	entry_id = id
	radius = r
	kind = art_kind
	if is_inside_tree():
		refresh()
	return self


func _ready() -> void:
	_glow = Panel.new()
	_glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glow.modulate.a = 0.0
	add_child(_glow)
	_update_glow_style()

	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_rect = ColorRect.new()
	_rect.color = Color.WHITE
	_rect.material = _mat
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rect)

	_initials = Kit.label("", 40, 800, Color(1, 1, 1, 0.92), true)
	_initials.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_initials.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_initials.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_initials)

	resized.connect(_sync_size)
	Art.art_ready.connect(_on_art_ready)
	Library.entry_changed.connect(_on_entry_changed)
	App.accent_changed.connect(func(_c: Color) -> void: _update_glow_style())
	_sync_size()
	refresh()


func refresh() -> void:
	if _mat == null:
		return
	var e := Library.get_entry(entry_id)
	var tex := Art.get_art(entry_id, kind)
	if tex == null and kind == &"cover" and Art.is_resolved(entry_id, &"cover"):
		tex = Art.get_art(entry_id, &"hero")
	if tex != null:
		_mat.set_shader_parameter("art", tex)
		_mat.set_shader_parameter("has_art", true)
		_mat.set_shader_parameter("art_size", tex.get_size())
		_initials.visible = false
	else:
		var name := str(e.get("name", "?"))
		var cols := Kit.cover_colors(name, str(e.get("color", "")))
		_mat.set_shader_parameter("has_art", false)
		_mat.set_shader_parameter("color_a", cols[0])
		_mat.set_shader_parameter("color_b", cols[1])
		_mat.set_shader_parameter("seed", float(absi(name.hash()) % 1000) / 1000.0)
		_initials.text = Fmt.initials(name)
		_initials.visible = true


func sweep(delay: float = 0.0) -> void:
	if _mat == null:
		return
	if _sweep_tween and _sweep_tween.is_valid():
		_sweep_tween.kill()
	_sweep_tween = create_tween()
	_sweep_tween.tween_interval(delay)
	_sweep_tween.tween_method(func(v: float) -> void: _mat.set_shader_parameter("sweep", v), -0.3, 1.9, 0.85).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func set_focus_amount(v: float) -> void:
	focus_amount = v
	if _mat:
		_mat.set_shader_parameter("focus", v)
	if _glow:
		_glow.modulate.a = v if glow_enabled else 0.0


func set_dim(v: float) -> void:
	if _mat:
		_mat.set_shader_parameter("dim", v)


func set_zoom(v: float) -> void:
	if _mat:
		_mat.set_shader_parameter("zoom", v)


func _sync_size() -> void:
	if _mat == null:
		return
	_mat.set_shader_parameter("rect_size", size)
	_mat.set_shader_parameter("radius", radius)
	_initials.add_theme_font_size_override("font_size", int(clampf(minf(size.x, size.y) * 0.32, 16.0, 88.0)))
	_update_glow_style()


func _update_glow_style() -> void:
	if _glow == null:
		return
	var s := Kit.box(Color(0, 0, 0, 0), int(radius))
	Kit.shadowed(s, Color(App.accent, 0.55), 26, Vector2(0, 8))
	_glow.add_theme_stylebox_override("panel", s)


func _on_art_ready(id: String, _k: StringName) -> void:
	if id == entry_id:
		refresh()


func _on_entry_changed(id: String) -> void:
	if id == entry_id:
		refresh()


## Preview mode for things not in the library yet (the Add dialog).
func preview(name: String, image_path: String) -> void:
	if _mat == null:
		await ready
	var tex: Texture2D = null
	if image_path != "" and FileAccess.file_exists(image_path):
		var img := Art.decode(FileAccess.get_file_as_bytes(image_path))
		if img:
			if img.get_width() > 800:
				img.resize(800, int(800.0 * img.get_height() / img.get_width()), Image.INTERPOLATE_BILINEAR)
			img.generate_mipmaps()
			tex = ImageTexture.create_from_image(img)
	if tex:
		_mat.set_shader_parameter("art", tex)
		_mat.set_shader_parameter("has_art", true)
		_mat.set_shader_parameter("art_size", tex.get_size())
		_initials.visible = false
	else:
		var cols := Kit.cover_colors(name if name != "" else "?")
		_mat.set_shader_parameter("has_art", false)
		_mat.set_shader_parameter("color_a", cols[0])
		_mat.set_shader_parameter("color_b", cols[1])
		_mat.set_shader_parameter("seed", float(absi(name.hash()) % 1000) / 1000.0)
		_initials.text = Fmt.initials(name) if name != "" else "+"
		_initials.visible = true
