class_name ShellWindow
extends Control
## A window of one of Oazy's own apps: liquid glass, a title bar you can drag
## (to the top edge to maximise, to the sides to snap), resizable edges,
## minimise to its taskbar button, and springy open/close.

signal closed(win: ShellWindow)
signal state_changed(win: ShellWindow)

const TITLE_H := 50.0
const EDGE := 7.0
const MIN_SIZE := Vector2(560, 380)

var app_ref := ""
var title := ""
var layer: WindowLayer
var body: MarginContainer
var active := false
var maximized := false
var minimized := false
var restore_rect := Rect2()

var _glass: GlassPanel
var _bar: Control
var _title_label: Label
var _icon: AppIcon
var _max_btn: FxButton
var _anim: Tween
var _dragging := false
var _drag_from := Vector2.ZERO
var _rect_from := Rect2()
var _resize_edge := -1
var _snap := ""
var _closing := false
## The last picture of this window (see snapshot), kept while it's minimised.
var _pic: Texture2D


func setup(ref: String, window_title: String) -> ShellWindow:
	app_ref = ref
	title = window_title
	return self


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = false
	_glass = GlassPanel.new(true, 22.0, GlassPanel.TINT_WINDOW)
	_glass.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_glass.set_shadow_strength(0.34, 32, 12.0)
	add_child(_glass)

	_bar = Control.new()
	_bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_bar.offset_bottom = TITLE_H
	_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	_bar.gui_input.connect(_on_bar_input)
	add_child(_bar)
	var row := Kit.hbox(10)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 16
	row.offset_right = -10
	_bar.add_child(row)
	_icon = AppIcon.new()
	_icon.custom_minimum_size = Vector2(22, 22)
	_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_icon.set_item(Catalog.item(app_ref))
	row.add_child(_icon)
	_title_label = Kit.label(title, 15, 600, App.TEXT)
	_title_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_title_label)
	row.add_child(Kit.spacer(0, 0, true))
	var min_btn := _chrome_button("minimize", "Minimise")
	min_btn.pressed.connect(minimize)
	row.add_child(min_btn)
	_max_btn = _chrome_button("maximize", "Maximise")
	_max_btn.pressed.connect(toggle_maximize)
	row.add_child(_max_btn)
	var close_btn := _chrome_button("close", "Close")
	close_btn.add_theme_stylebox_override("hover", Kit.box(Color(1.0, 0.36, 0.42, 0.9), 999))
	close_btn.add_theme_stylebox_override("pressed", Kit.box(Color(1.0, 0.36, 0.42, 1.0), 999))
	close_btn.pressed.connect(close)
	row.add_child(close_btn)

	var line := ColorRect.new()
	line.color = Color(1, 1, 1, 0.06)
	line.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	line.offset_top = TITLE_H
	line.offset_bottom = TITLE_H + 1
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(line)

	body = MarginContainer.new()
	body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	body.offset_top = TITLE_H + 1
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.clip_contents = true
	add_child(body)

	_add_grips()
	set_active(true)


func _chrome_button(icon_name: String, tip: String) -> FxButton:
	var b := FxButton.icon_only(icon_name, tip, 16, 32)
	b.focus_mode = Control.FOCUS_NONE
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.hover_scale = 1.0
	return b


func set_active(on: bool) -> void:
	active = on
	if _title_label:
		_title_label.add_theme_color_override("font_color", App.TEXT if on else App.TEXT_MUTE)
	if _glass:
		_glass.glow = 0.18 if on else 0.0
		if Shell.native:
			# Tighter in shell mode: the shadow's ring is part of the layer's
			# shape, so it would catch clicks meant for the apps around it.
			_glass.set_shadow_strength(0.32 if on else 0.2, 20 if on else 14, 7.0 if on else 5.0)
		else:
			_glass.set_shadow_strength(0.36 if on else 0.22, 36 if on else 24, 14.0 if on else 8.0)


## The window and its shadow (what its layer keeps on screen in shell mode).
func shell_rect() -> Rect2:
	return _glass.shadow_rect() if _glass else get_global_rect()


# --- Open / close / minimise --------------------------------------------------------

func play_open() -> void:
	pivot_offset = size / 2.0
	scale = Vector2.ONE * 0.97
	modulate.a = 0.0
	_kill_anim()
	_anim = create_tween().set_parallel(true).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	_anim.tween_property(self, "scale", Vector2.ONE, 0.26)
	_anim.tween_property(self, "modulate:a", 1.0, 0.16)


func close() -> void:
	if _closing:
		return
	_closing = true
	Sfx.play(&"back")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	pivot_offset = size / 2.0
	_kill_anim()
	_anim = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_anim.tween_property(self, "scale", Vector2.ONE * 0.97, 0.12)
	_anim.tween_property(self, "modulate:a", 0.0, 0.12)
	_anim.chain().tween_callback(func() -> void:
		closed.emit(self)
		queue_free()
	)


func minimize() -> void:
	if minimized or _closing:
		return
	# A picture first, so Alt+Tab still shows what's in it while it's away.
	snapshot()
	minimized = true
	Sfx.play(&"back", 1.1)
	var target := layer.minimize_target(app_ref) if layer else Vector2(size.x / 2.0, 2000.0)
	pivot_offset = size / 2.0
	var shift := target - (position + size / 2.0)
	set_meta("min_from", position)
	_kill_anim()
	_anim = create_tween().set_parallel(true).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN)
	_anim.tween_property(self, "position", position + shift, 0.3)
	_anim.tween_property(self, "scale", Vector2.ONE * 0.12, 0.3)
	_anim.tween_property(self, "modulate:a", 0.0, 0.28)
	_anim.chain().tween_callback(func() -> void:
		visible = false
		state_changed.emit(self)
	)
	state_changed.emit(self)


func unminimize() -> void:
	if not minimized:
		return
	minimized = false
	visible = true
	var back: Vector2 = get_meta("min_from", position)
	_kill_anim()
	_anim = create_tween().set_parallel(true).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	_anim.tween_property(self, "position", back, 0.34)
	_anim.tween_property(self, "scale", Vector2.ONE, 0.32)
	_anim.tween_property(self, "modulate:a", 1.0, 0.2)
	Sfx.play(&"open", 1.1)
	state_changed.emit(self)


## A picture of the window as it is on screen now, cropped from its layer
## (`img`, when given, is that layer's frame, read back once for several
## windows). Minimised or hidden windows keep their last one. Null if none.
func snapshot(img: Image = null) -> Texture2D:
	if minimized or not visible or not is_visible_in_tree() or modulate.a < 0.9 or DisplayServer.get_name() == "headless":
		return _pic
	var vp := get_viewport()
	if img == null:
		img = vp.get_texture().get_image()
	if img == null or img.is_empty():
		return _pic
	var k := Vector2(img.get_size()) / vp.get_visible_rect().size
	var r := get_global_transform_with_canvas() * Rect2(Vector2.ZERO, size)
	var px := Rect2i(Rect2(r.position * k, r.size * k)).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	if px.size.x < 8 or px.size.y < 8:
		return _pic
	var part := img.get_region(px)
	part.generate_mipmaps()
	_pic = ImageTexture.create_from_image(part)
	return _pic


func _kill_anim() -> void:
	if _anim and _anim.is_valid():
		_anim.kill()


# --- Geometry ---------------------------------------------------------------------------

func set_rect(r: Rect2, animate: bool = false) -> void:
	r.size = r.size.max(MIN_SIZE)
	if not animate:
		position = r.position
		size = r.size
		return
	_kill_anim()
	_anim = create_tween().set_parallel(true).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	_anim.tween_property(self, "position", r.position, 0.32)
	_anim.tween_property(self, "size", r.size, 0.32)


func toggle_maximize() -> void:
	if maximized:
		maximized = false
		set_rect(restore_rect, true)
	else:
		restore_rect = Rect2(position, size)
		maximized = true
		set_rect(layer.work_rect() if layer else Rect2(Vector2.ZERO, get_parent_area_size()), true)
	_max_btn.icon = Icons.tex("restore" if maximized else "maximize", 16, Color.WHITE)
	_max_btn.tooltip_text = "Restore" if maximized else "Maximise"
	Sfx.play(&"toggle")


func _on_bar_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and event.double_click:
			_dragging = false
			toggle_maximize()
		elif event.pressed:
			_dragging = true
			_drag_from = get_global_mouse_position()
			_rect_from = Rect2(position, size)
		elif _dragging:
			_dragging = false
			_finish_snap()
		_bar.accept_event()
	elif event is InputEventMouseMotion and _dragging:
		var mouse := get_global_mouse_position()
		if maximized and mouse.distance_to(_drag_from) > 6.0:
			# Pull a maximised window off the top: keep the cursor at the same
			# relative spot on the title bar.
			var k := (_drag_from.x - _rect_from.position.x) / maxf(_rect_from.size.x, 1.0)
			maximized = false
			_max_btn.icon = Icons.tex("maximize", 16, Color.WHITE)
			_kill_anim()
			size = restore_rect.size
			_rect_from = Rect2(Vector2(mouse.x - restore_rect.size.x * k, _rect_from.position.y), restore_rect.size)
			_drag_from = mouse
		if not maximized:
			var p := _rect_from.position + (mouse - _drag_from)
			p.y = maxf(p.y, 0.0)
			position = p
			_update_snap(mouse)
		_bar.accept_event()


func _update_snap(mouse: Vector2) -> void:
	if layer == null:
		return
	var local := mouse - layer.global_position
	var s := ""
	if local.y <= 3.0:
		s = "max"
	elif local.x <= 3.0:
		s = "left"
	elif local.x >= layer.size.x - 3.0:
		s = "right"
	if s != _snap:
		_snap = s
		layer.show_snap_preview(_snap_rect(s) if s != "" else Rect2())


func _snap_rect(s: String) -> Rect2:
	var w := layer.work_rect()
	match s:
		"max":
			return w
		"left":
			return Rect2(w.position, Vector2(w.size.x / 2.0 - 4.0, w.size.y))
		"right":
			return Rect2(w.position + Vector2(w.size.x / 2.0 + 4.0, 0), Vector2(w.size.x / 2.0 - 4.0, w.size.y))
	return Rect2(position, size)


func _finish_snap() -> void:
	if _snap == "":
		return
	restore_rect = _rect_from
	if _snap == "max":
		maximized = true
		_max_btn.icon = Icons.tex("restore", 16, Color.WHITE)
	set_rect(_snap_rect(_snap), true)
	_snap = ""
	layer.show_snap_preview(Rect2())
	Sfx.play(&"toggle")


func _add_grips() -> void:
	# [left, top, right, bottom] flags, preset, cursor
	var specs := [
		[[1, 0, 0, 0], Control.PRESET_LEFT_WIDE, Control.CURSOR_HSIZE],
		[[0, 0, 1, 0], Control.PRESET_RIGHT_WIDE, Control.CURSOR_HSIZE],
		[[0, 0, 0, 1], Control.PRESET_BOTTOM_WIDE, Control.CURSOR_VSIZE],
		[[0, 1, 0, 0], Control.PRESET_TOP_WIDE, Control.CURSOR_VSIZE],
		[[1, 0, 0, 1], Control.PRESET_BOTTOM_LEFT, Control.CURSOR_BDIAGSIZE],
		[[0, 0, 1, 1], Control.PRESET_BOTTOM_RIGHT, Control.CURSOR_FDIAGSIZE],
		[[1, 1, 0, 0], Control.PRESET_TOP_LEFT, Control.CURSOR_FDIAGSIZE],
		[[0, 1, 1, 0], Control.PRESET_TOP_RIGHT, Control.CURSOR_BDIAGSIZE],
	]
	for i in specs.size():
		var s: Array = specs[i]
		var flags: Array = s[0]
		var g := Control.new()
		g.mouse_filter = Control.MOUSE_FILTER_STOP
		g.mouse_default_cursor_shape = s[2]
		var corner: bool = int(flags[0]) + int(flags[1]) + int(flags[2]) + int(flags[3]) == 2
		g.custom_minimum_size = Vector2(EDGE * 2, EDGE * 2) if corner else Vector2(EDGE, EDGE)
		g.set_anchors_and_offsets_preset(s[1], Control.PRESET_MODE_MINSIZE)
		if not corner:
			# Edges sit half outside the window so they're easy to grab.
			match s[1]:
				Control.PRESET_LEFT_WIDE:
					g.offset_left = -EDGE / 2.0
					g.offset_right = EDGE / 2.0
				Control.PRESET_RIGHT_WIDE:
					g.offset_left = -EDGE / 2.0
					g.offset_right = EDGE / 2.0
				Control.PRESET_BOTTOM_WIDE:
					g.offset_top = -EDGE / 2.0
					g.offset_bottom = EDGE / 2.0
				Control.PRESET_TOP_WIDE:
					g.offset_top = -EDGE / 2.0
					g.offset_bottom = EDGE / 2.0
		g.gui_input.connect(_on_grip_input.bind(flags, g))
		add_child(g)


func _on_grip_input(event: InputEvent, flags: Array, grip: Control) -> void:
	if maximized:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_resize_edge = 1
			_drag_from = get_global_mouse_position()
			_rect_from = Rect2(position, size)
		else:
			_resize_edge = -1
		grip.accept_event()
	elif event is InputEventMouseMotion and _resize_edge >= 0:
		var d := get_global_mouse_position() - _drag_from
		var r := _rect_from
		if int(flags[0]) == 1:
			var nx := minf(r.position.x + d.x, r.end.x - MIN_SIZE.x)
			r.size.x = r.end.x - nx
			r.position.x = nx
		if int(flags[2]) == 1:
			r.size.x = maxf(MIN_SIZE.x, r.size.x + d.x)
		if int(flags[1]) == 1:
			var ny := minf(maxf(0.0, r.position.y + d.y), r.end.y - MIN_SIZE.y)
			r.size.y = r.end.y - ny
			r.position.y = ny
		if int(flags[3]) == 1:
			r.size.y = maxf(MIN_SIZE.y, r.size.y + d.y)
		set_rect(r)
		grip.accept_event()
