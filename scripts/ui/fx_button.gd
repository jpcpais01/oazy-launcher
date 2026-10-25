class_name FxButton
extends Button
## Button with personality: springy hover/focus scale, press bounce, UI sounds
## and a handful of visual variants.

enum Style { GHOST, PRIMARY, ICON, CHIP, DANGER, ACCENT, PLAIN }

var variant := Style.GHOST
var hover_scale := 1.04
var selected := false: set = set_selected
var _scale_tween: Tween


static func make(label_text: String, icon_name: String = "", v: Style = Style.GHOST, height: int = 44) -> FxButton:
	var b := FxButton.new()
	b.variant = v
	b.text = label_text
	b.custom_minimum_size.y = height
	if icon_name != "":
		b.icon = Icons.tex(icon_name, 20, Color.WHITE)
	b._apply_style()
	return b


static func icon_only(icon_name: String, tip: String = "", px: int = 20, size: int = 44) -> FxButton:
	var b := FxButton.new()
	b.variant = Style.ICON
	b.icon = Icons.tex(icon_name, px, Color.WHITE)
	b.tooltip_text = tip
	b.custom_minimum_size = Vector2(size, size)
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b._apply_style()
	return b


func _init() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE


func _ready() -> void:
	resized.connect(func() -> void: pivot_offset = size / 2.0)
	pivot_offset = size / 2.0
	mouse_entered.connect(_on_hover.bind(true))
	mouse_exited.connect(_on_hover.bind(false))
	focus_entered.connect(_on_focus.bind(true))
	focus_exited.connect(_on_focus.bind(false))
	button_down.connect(func() -> void: _animate_scale(0.96, 0.08))
	button_up.connect(func() -> void: _animate_scale(hover_scale if is_hovered() else 1.0, 0.35))
	pressed.connect(func() -> void: Sfx.play(&"toggle" if variant == Style.CHIP else &"select"))


func set_icon_name(icon_name: String, color: Color = Color.WHITE) -> void:
	icon = Icons.tex(icon_name, 20, color)


func set_selected(v: bool) -> void:
	selected = v
	if is_inside_tree() or variant == Style.CHIP:
		_apply_style()


func _on_hover(on: bool) -> void:
	if disabled:
		return
	_animate_scale(hover_scale if on else (hover_scale if has_focus() else 1.0), 0.3)
	if on:
		Sfx.play(&"move", 1.15)


func _on_focus(on: bool) -> void:
	_animate_scale(hover_scale if on or is_hovered() else 1.0, 0.3)
	if on and not is_hovered():
		Sfx.play(&"move")


func _animate_scale(target: float, time: float) -> void:
	if _scale_tween and _scale_tween.is_valid():
		_scale_tween.kill()
	_scale_tween = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_scale_tween.tween_property(self, "scale", Vector2.ONE * target, time)


func _apply_style() -> void:
	var r := 999
	match variant:
		Style.PRIMARY:
			_set_boxes(Color("f4f5f8"), Color.WHITE, Color("dcdde3"), r, 26, Color(0, 0, 0, 0))
			for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
				add_theme_color_override(c, Color("0b0c12"))
			for c in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_focus_color"]:
				add_theme_color_override(c, Color("0b0c12"))
			add_theme_font_override("font", Kit.font(700))
			add_theme_font_size_override("font_size", 17)
			var focus := Kit.box(Color(0, 0, 0, 0), r, Color(1, 1, 1, 0.9), 2)
			focus.set_expand_margin_all(4)
			add_theme_stylebox_override("focus", focus)
			hover_scale = 1.05
		Style.ACCENT:
			_set_boxes(App.accent, App.accent.lightened(0.12), App.accent.darkened(0.1), r, 22, Color(0, 0, 0, 0))
			add_theme_font_override("font", Kit.font(700))
		Style.ICON:
			_set_boxes(Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.1), Color(1, 1, 1, 0.16), r, 0, Color(0, 0, 0, 0))
			hover_scale = 1.08
		Style.CHIP:
			if selected:
				_set_boxes(Color("f4f5f8"), Color.WHITE, Color("dcdde3"), r, 18, Color(0, 0, 0, 0))
				for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
					add_theme_color_override(c, Color("0b0c12"))
			else:
				_set_boxes(Color(1, 1, 1, 0.06), Color(1, 1, 1, 0.12), Color(1, 1, 1, 0.16), r, 18, Color(1, 1, 1, 0.07))
				for c in ["font_color", "font_focus_color"]:
					add_theme_color_override(c, App.TEXT_DIM)
				for c in ["font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
					add_theme_color_override(c, Color.WHITE)
			add_theme_font_size_override("font_size", 15)
			hover_scale = 1.03
		Style.DANGER:
			_set_boxes(Color(1.0, 0.36, 0.48, 0.16), Color(1.0, 0.36, 0.48, 0.28), Color(1.0, 0.36, 0.48, 0.36), r, 22, Color(1.0, 0.36, 0.48, 0.3))
			add_theme_color_override("font_color", Color("ffb3c1"))
			add_theme_color_override("font_hover_color", Color.WHITE)
		Style.PLAIN:
			_set_boxes(Color(0, 0, 0, 0), Color(1, 1, 1, 0.06), Color(1, 1, 1, 0.1), 10, 10, Color(0, 0, 0, 0))
			add_theme_color_override("font_color", App.TEXT_DIM)
			hover_scale = 1.0
		_:
			_set_boxes(Color(1, 1, 1, 0.08), Color(1, 1, 1, 0.14), Color(1, 1, 1, 0.2), r, 22, Color(1, 1, 1, 0.07))


func _set_boxes(normal: Color, hover: Color, pressed_c: Color, radius: int, pad: int, border: Color) -> void:
	var pv := 8 if variant != Style.ICON else 0
	var n := Kit.box(normal, radius, border, 1, pad, pv)
	var h := Kit.box(hover, radius, border, 1, pad, pv)
	var p := Kit.box(pressed_c, radius, border, 1, pad, pv)
	if variant == Style.PRIMARY:
		Kit.shadowed(h, Color(1, 1, 1, 0.22), 18, Vector2.ZERO)
	add_theme_stylebox_override("normal", n)
	add_theme_stylebox_override("hover", h)
	add_theme_stylebox_override("pressed", p)
	add_theme_stylebox_override("hover_pressed", p)
	add_theme_stylebox_override("disabled", Kit.box(Color(1, 1, 1, 0.03), radius, Color(0, 0, 0, 0), 1, pad, pv))
	if variant != Style.PRIMARY:
		var focus := Kit.box(Color(0, 0, 0, 0), radius, Color(1, 1, 1, 0.85), 2)
		focus.set_expand_margin_all(3)
		add_theme_stylebox_override("focus", focus)
