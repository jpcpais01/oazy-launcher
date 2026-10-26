class_name PointerCard
extends Button
## One mouse pointer theme in Settings: arrow, hand, text and a busy spinner
## over a light-to-dark pane (so every theme shows how it reads on both),
## with the theme's name underneath. The spinner turns while hovered.

const PANE_H := 82.0
const GLYPH := 28.0

var theme_id := ""
var chosen := false: set = set_chosen
var _busy: TextureRect
var _spin: TextureRect
var _name: Label


static func make(id: String) -> PointerCard:
	var c := PointerCard.new()
	c.theme_id = id
	return c


func _init() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	custom_minimum_size = Vector2(0, PANE_H + 44)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _ready() -> void:
	var info := Cursors.theme_info(theme_id)
	tooltip_text = "Windows' own pointers" if info.is_empty() else ""
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
	var sky := TextureRect.new()
	sky.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sky.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sky.stretch_mode = TextureRect.STRETCH_SCALE
	sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sky.texture = _pane_texture()
	pane.add_child(sky)

	var row := Kit.hbox(10)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pane.add_child(row)
	if info.is_empty():
		var off := Kit.vbox(4)
		off.alignment = BoxContainer.ALIGNMENT_CENTER
		off.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ic := Kit.icon_rect("window", 26, Color(1, 1, 1, 0.92))
		ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		off.add_child(ic)
		var l := Kit.label("Windows default", 12, 600, Color(1, 1, 1, 0.85))
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		off.add_child(l)
		row.add_child(off)
	else:
		for glyph in ["arrow", "hand", "text"]:
			var t := TextureRect.new()
			t.texture = Cursors.preview(theme_id, glyph)
			t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			t.custom_minimum_size = Vector2(GLYPH, GLYPH)
			t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			t.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(t)
		_busy = TextureRect.new()
		_busy.texture = Cursors.preview(theme_id, "busy_base")
		_busy.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_busy.custom_minimum_size = Vector2(GLYPH, GLYPH)
		_busy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_busy.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_spin = TextureRect.new()
		_spin.texture = Cursors.preview(theme_id, "busy_spin")
		_spin.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_spin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_spin.pivot_offset = Vector2(GLYPH, GLYPH) / 2.0
		_spin.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_busy.add_child(_spin)
		row.add_child(_busy)

	_name = Kit.label(str(info.get("name", "Off")), 14, 600, App.TEXT)
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name.custom_minimum_size.y = 34
	_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	col.add_child(_name)

	mouse_entered.connect(_restyle)
	mouse_exited.connect(_restyle)
	focus_entered.connect(_restyle)
	focus_exited.connect(_restyle)
	_restyle()
	set_process(false)
	mouse_entered.connect(func() -> void: set_process(_busy != null))


func set_chosen(v: bool) -> void:
	chosen = v
	if is_inside_tree():
		_restyle()


func _restyle() -> void:
	var hover := is_hovered() or has_focus()
	var bg := Color(App.accent, 0.16) if chosen else Color(1, 1, 1, 0.07 if hover else 0.03)
	var edge := Color(App.accent, 0.85) if chosen else Color(1, 1, 1, 0.16 if hover else 0.06)
	var s := Kit.box(bg, 16, edge, 2 if chosen else 1)
	for st in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		add_theme_stylebox_override(st, s if st != "focus" else Kit.empty())
	if _name:
		_name.add_theme_color_override("font_color", Color.WHITE if chosen else App.TEXT)


func _process(delta: float) -> void:
	# One turn a second, like the real thing; settle once the mouse leaves.
	_spin.rotation = fmod(_spin.rotation + delta * TAU, TAU)
	if not is_hovered() and not has_focus():
		set_process(false)


## Morning sky into deep lagoon, corner to corner.
static func _pane_texture() -> Texture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	g.colors = PackedColorArray([Color("e9f4f6"), Color("8fb9c4"), Color("163240")])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_LINEAR
	t.fill_from = Vector2(0, 0)
	t.fill_to = Vector2(1, 0.6)
	t.width = 128
	t.height = 64
	return t
