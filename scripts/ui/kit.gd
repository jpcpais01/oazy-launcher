class_name Kit
## Design system: fonts, theme, style boxes and small widget factories.

static var _fonts := {}


static func font(weight: int = 500, display: bool = false) -> Font:
	var key := ("D" if display else "I") + str(weight)
	if _fonts.has(key):
		return _fonts[key]
	var family := "Outfit" if display else "Inter"
	var path := "res://assets/fonts/%s-%d.woff2" % [family, weight]
	var f: Font = load(path)
	if display:
		# Display type reads better slightly tighter.
		var v := FontVariation.new()
		v.base_font = f
		v.spacing_glyph = -1 if weight >= 700 else 0
		f = v
	_fonts[key] = f
	return f


static func italic_font() -> Font:
	if _fonts.has("italic"):
		return _fonts["italic"]
	var v := FontVariation.new()
	v.base_font = font(400)
	v.variation_transform = Transform2D(Vector2(1, 0), Vector2(0.18, 1), Vector2.ZERO)
	_fonts["italic"] = v
	return v


static func mono_font() -> Font:
	if _fonts.has("mono"):
		return _fonts["mono"]
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Cascadia Mono", "Consolas", "DejaVu Sans Mono", "monospace"])
	_fonts["mono"] = f
	return f


static func box(bg: Color, radius: int = 14, border: Color = Color(0, 0, 0, 0), border_w: int = 1, pad_h: int = 0, pad_v: int = 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.corner_detail = 10
	s.anti_aliasing = true
	if border.a > 0.0:
		s.border_color = border
		s.set_border_width_all(border_w)
	s.content_margin_left = pad_h
	s.content_margin_right = pad_h
	s.content_margin_top = pad_v
	s.content_margin_bottom = pad_v
	return s


static func shadowed(s: StyleBoxFlat, color: Color, size: int, offset: Vector2 = Vector2(0, 6)) -> StyleBoxFlat:
	s.shadow_color = color
	s.shadow_size = size
	s.shadow_offset = offset
	return s


static func empty(pad_h: int = 0, pad_v: int = 0) -> StyleBoxEmpty:
	var s := StyleBoxEmpty.new()
	s.content_margin_left = pad_h
	s.content_margin_right = pad_h
	s.content_margin_top = pad_v
	s.content_margin_bottom = pad_v
	return s


static func label(text: String, size: int = 16, weight: int = 500, color: Color = Color("f4f5f8"), display: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font(weight, display))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func icon_rect(name: String, px: int = 20, color: Color = Color.WHITE) -> TextureRect:
	var t := TextureRect.new()
	t.texture = Icons.tex(name, px, color)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.custom_minimum_size = Vector2(px, px)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t


static func spacer(w: float = 0.0, h: float = 0.0, expand: bool = false) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if expand:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c


static func hbox(sep: int = 10) -> HBoxContainer:
	var b := HBoxContainer.new()
	b.add_theme_constant_override("separation", sep)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


static func vbox(sep: int = 10) -> VBoxContainer:
	var b := VBoxContainer.new()
	b.add_theme_constant_override("separation", sep)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


static func panel(bg: Color = Color("12131c"), radius: int = 22, pad: int = 24) -> PanelContainer:
	var p := PanelContainer.new()
	var s := box(bg, radius, Color(1, 1, 1, 0.08), 1, pad, pad)
	shadowed(s, Color(0, 0, 0, 0.45), 40, Vector2(0, 18))
	p.add_theme_stylebox_override("panel", s)
	return p


static func ease_tween(node: Node, trans: Tween.TransitionType = Tween.TRANS_EXPO, ease_type: Tween.EaseType = Tween.EASE_OUT) -> Tween:
	var t := node.create_tween()
	t.set_trans(trans).set_ease(ease_type)
	return t


## A colour pair for procedural covers, stable per name.
static func cover_colors(name: String, accent_hex: String = "") -> Array[Color]:
	var h := absi(name.hash())
	var base_h := float(h % 360) / 360.0
	if accent_hex != "":
		base_h = Color(accent_hex).h
	var a := Color.from_hsv(base_h, 0.62, 0.78)
	var b := Color.from_hsv(fposmod(base_h + 0.12 + float((h / 360) % 10) / 100.0, 1.0), 0.75, 0.42)
	return [a, b]


static func build_theme() -> Theme:
	var t := Theme.new()
	t.default_font = font(500)
	t.default_font_size = 16

	t.set_color("font_color", "Label", App.TEXT)

	# Buttons (neutral "ghost" look; FxButton restyles per variant).
	t.set_stylebox("normal", "Button", box(Color(1, 1, 1, 0.07), 12, Color(1, 1, 1, 0.06), 1, 16, 10))
	t.set_stylebox("hover", "Button", box(Color(1, 1, 1, 0.13), 12, Color(1, 1, 1, 0.12), 1, 16, 10))
	t.set_stylebox("pressed", "Button", box(Color(1, 1, 1, 0.18), 12, Color(1, 1, 1, 0.14), 1, 16, 10))
	t.set_stylebox("hover_pressed", "Button", box(Color(1, 1, 1, 0.2), 12, Color(1, 1, 1, 0.16), 1, 16, 10))
	t.set_stylebox("disabled", "Button", box(Color(1, 1, 1, 0.03), 12, Color(0, 0, 0, 0), 1, 16, 10))
	var focus := box(Color(0, 0, 0, 0), 14, Color(1, 1, 1, 0.85), 2)
	focus.set_expand_margin_all(3)
	t.set_stylebox("focus", "Button", focus)
	for c in ["font_color", "font_focus_color", "icon_normal_color", "icon_focus_color"]:
		t.set_color(c, "Button", App.TEXT)
	for c in ["font_hover_color", "font_pressed_color", "font_hover_pressed_color", "icon_hover_color", "icon_pressed_color", "icon_hover_pressed_color"]:
		t.set_color(c, "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", App.TEXT_MUTE)
	t.set_color("icon_disabled_color", "Button", App.TEXT_MUTE)
	t.set_constant("h_separation", "Button", 10)
	t.set_font("font", "Button", font(600))

	# Text input.
	var le := box(Color(1, 1, 1, 0.06), 12, Color(1, 1, 1, 0.1), 1, 14, 11)
	t.set_stylebox("normal", "LineEdit", le)
	var le_focus := box(Color(1, 1, 1, 0.09), 12, Color(1, 1, 1, 0.55), 1, 14, 11)
	t.set_stylebox("focus", "LineEdit", le_focus)
	t.set_stylebox("read_only", "LineEdit", box(Color(1, 1, 1, 0.03), 12, Color(1, 1, 1, 0.06), 1, 14, 11))
	t.set_color("font_color", "LineEdit", App.TEXT)
	t.set_color("font_placeholder_color", "LineEdit", App.TEXT_MUTE)
	t.set_color("caret_color", "LineEdit", Color.WHITE)
	t.set_color("selection_color", "LineEdit", Color(0.49, 0.42, 1.0, 0.45))
	t.set_color("clear_button_color", "LineEdit", App.TEXT_DIM)

	# Menus.
	var menu := box(Color("161722"), 14, Color(1, 1, 1, 0.1), 1, 6, 6)
	shadowed(menu, Color(0, 0, 0, 0.5), 28, Vector2(0, 12))
	t.set_stylebox("panel", "PopupMenu", menu)
	t.set_stylebox("hover", "PopupMenu", box(Color(1, 1, 1, 0.09), 9))
	t.set_stylebox("separator", "PopupMenu", _line_box())
	t.set_color("font_color", "PopupMenu", App.TEXT)
	t.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	t.set_color("font_disabled_color", "PopupMenu", App.TEXT_MUTE)
	t.set_constant("v_separation", "PopupMenu", 12)
	t.set_constant("h_separation", "PopupMenu", 12)
	t.set_constant("item_start_padding", "PopupMenu", 12)
	t.set_constant("item_end_padding", "PopupMenu", 18)
	t.set_font("font", "PopupMenu", font(500))
	t.set_font_size("font_size", "PopupMenu", 15)

	# Tooltips.
	t.set_stylebox("panel", "TooltipPanel", box(Color("1b1c28"), 10, Color(1, 1, 1, 0.1), 1, 12, 8))
	t.set_color("font_color", "TooltipLabel", App.TEXT)
	t.set_font_size("font_size", "TooltipLabel", 14)

	# Scrollbars: slim and quiet.
	for sb in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", sb, empty(4, 4))
		t.set_stylebox("scroll_focus", sb, empty(4, 4))
		t.set_stylebox("grabber", sb, box(Color(1, 1, 1, 0.16), 4, Color(0, 0, 0, 0), 0, 3, 3))
		t.set_stylebox("grabber_highlight", sb, box(Color(1, 1, 1, 0.28), 4, Color(0, 0, 0, 0), 0, 3, 3))
		t.set_stylebox("grabber_pressed", sb, box(Color(1, 1, 1, 0.38), 4, Color(0, 0, 0, 0), 0, 3, 3))

	# Slider.
	var track := box(Color(1, 1, 1, 0.12), 3)
	track.content_margin_top = 3
	track.content_margin_bottom = 3
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", box(Color(1, 1, 1, 0.85), 3))
	t.set_stylebox("grabber_area_highlight", "HSlider", box(Color.WHITE, 3))
	var knob := _circle_texture(18, Color.WHITE)
	t.set_icon("grabber", "HSlider", knob)
	t.set_icon("grabber_highlight", "HSlider", knob)

	# Rich text (patch notes).
	t.set_font("normal_font", "RichTextLabel", font(400))
	t.set_font("bold_font", "RichTextLabel", font(700))
	t.set_font("italics_font", "RichTextLabel", italic_font())
	t.set_font("mono_font", "RichTextLabel", mono_font())
	t.set_font_size("normal_font_size", "RichTextLabel", 16)
	t.set_font_size("bold_font_size", "RichTextLabel", 16)
	t.set_font_size("italics_font_size", "RichTextLabel", 16)
	t.set_font_size("mono_font_size", "RichTextLabel", 14)
	t.set_color("default_color", "RichTextLabel", Color("c9ccd8"))
	t.set_constant("line_separation", "RichTextLabel", 5)

	t.set_stylebox("panel", "PanelContainer", box(Color(1, 1, 1, 0.05), 18, Color(1, 1, 1, 0.07)))
	return t


static func _line_box() -> StyleBoxLine:
	var l := StyleBoxLine.new()
	l.color = Color(1, 1, 1, 0.08)
	l.thickness = 1
	l.grow_begin = -8
	l.grow_end = -8
	return l


static func _circle_texture(px: int, color: Color) -> Texture2D:
	var svg := "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"%d\" height=\"%d\"><circle cx=\"%f\" cy=\"%f\" r=\"%f\" fill=\"#%s\"/></svg>" % [px, px, px / 2.0, px / 2.0, px / 2.0 - 0.5, color.to_html(false)]
	var img := Image.new()
	img.load_svg_from_string(svg, 1.0)
	return ImageTexture.create_from_image(img)
