class_name WallpaperCard
extends Button
## One wallpaper style in Settings: a small live copy of it, in the current
## light and accent, with the style's name underneath.

const SHADER := preload("res://shaders/oasis.gdshader")
const PANE_H := 96.0

var style_id := ""
var chosen := false: set = set_chosen
var _mat: ShaderMaterial
var _name: Label


static func make(id: String) -> WallpaperCard:
	var c := WallpaperCard.new()
	c.style_id = id
	return c


func _init() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	custom_minimum_size = Vector2(0, PANE_H + 44)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _ready() -> void:
	var col := Kit.vbox(0)
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 6
	col.offset_top = 6
	col.offset_right = -6
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(col)

	var pane := Panel.new()
	pane.custom_minimum_size.y = PANE_H
	pane.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pane.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	pane.add_theme_stylebox_override("panel", Kit.box(Color.WHITE, 12))
	col.add_child(pane)
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_mat.set_shader_parameter("wall_style", Wallpaper.style_index(style_id))
	var view := ColorRect.new()
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.color = Color.WHITE
	view.material = _mat
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.resized.connect(func() -> void:
		if view.size.y > 0.0:
			_mat.set_shader_parameter("aspect", view.size.x / view.size.y)
	)
	pane.add_child(view)

	_name = Kit.label(str(Wallpaper.STYLES.get(style_id, ["?"])[0]), 14, 600, App.TEXT)
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name.custom_minimum_size.y = 34
	_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	col.add_child(_name)

	mouse_entered.connect(_restyle)
	mouse_exited.connect(_restyle)
	focus_entered.connect(_restyle)
	focus_exited.connect(_restyle)
	visibility_changed.connect(sync_look)
	# Light and accent ease in over a moment; catch up once they settle.
	App.accent_changed.connect(func(_c: Color) -> void: _sync_soon())
	Settings.changed.connect(func(key: String, _v: Variant) -> void:
		if key == "wallpaper_light" or key == "effects":
			_sync_soon()
		elif key == "wallpaper":
			chosen = str(Settings.get_value("wallpaper")) == style_id
	)
	chosen = str(Settings.get_value("wallpaper")) == style_id
	sync_look()


func set_chosen(v: bool) -> void:
	chosen = v
	if is_inside_tree():
		_restyle()


## Copies the desktop wallpaper's light, accent and speed.
func sync_look() -> void:
	if _mat == null:
		return
	if Wallpaper.shared.is_empty():
		var t := Time.get_time_dict_from_system()
		var p := Wallpaper.palette_for(str(Settings.get_value("wallpaper_light")), float(t["hour"]) + float(t["minute"]) / 60.0)
		for i in Wallpaper.PARAMS.size():
			_mat.set_shader_parameter(Wallpaper.PARAMS[i], p[i])
		_mat.set_shader_parameter("accent", App.accent)
		return
	for k in ["accent", "speed"] + Wallpaper.PARAMS:
		if Wallpaper.shared.has(k):
			_mat.set_shader_parameter(k, Wallpaper.shared[k])


func _sync_soon() -> void:
	if is_inside_tree():
		get_tree().create_timer(0.9).timeout.connect(sync_look)


func _restyle() -> void:
	var hover := is_hovered() or has_focus()
	var bg := Color(App.accent, 0.16) if chosen else Color(1, 1, 1, 0.07 if hover else 0.03)
	var edge := Color(App.accent, 0.85) if chosen else Color(1, 1, 1, 0.16 if hover else 0.06)
	var s := Kit.box(bg, 16, edge, 2 if chosen else 1)
	for st in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		add_theme_stylebox_override(st, s if st != "focus" else Kit.empty())
	if _name:
		_name.add_theme_color_override("font_color", Color.WHITE if chosen else App.TEXT)
