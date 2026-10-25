class_name GameDetail
extends Control
## A game's page inside the Library window: big artwork with its logo, Play,
## favourite and edit, and a few numbers about your time with it.

signal back

var main: Node
var entry_id := ""
var _banner: Control
var _hero: CoverArt
var _kicker: Label
var _logo: TextureRect
var _title: Label
var _meta: Label
var _play: FxButton
var _fav: FxButton
var _stats: HBoxContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var col := Kit.vbox(18)
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 20
	col.offset_right = -20
	col.offset_top = 18
	col.offset_bottom = -20
	add_child(col)

	_banner = Control.new()
	_banner.custom_minimum_size.y = 300
	_banner.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_banner.size_flags_stretch_ratio = 1.6
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_banner)
	_hero = CoverArt.new()
	_hero.glow_enabled = false
	_hero.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_banner.add_child(_hero)
	var shade := TextureRect.new()
	var g := Gradient.new()
	g.set_color(0, Color(0.01, 0.04, 0.06, 0.0))
	g.set_color(1, Color(0.01, 0.04, 0.06, 0.8))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0.35)
	gt.fill_to = Vector2(0, 1)
	shade.texture = gt
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.add_child(shade)
	var back_btn := FxButton.make("Library", "chevron_left", FxButton.Style.GHOST, 38)
	back_btn.position = Vector2(16, 16)
	back_btn.add_theme_font_size_override("font_size", 14)
	back_btn.pressed.connect(func() -> void:
		Sfx.play(&"back")
		back.emit()
	)
	_banner.add_child(back_btn)
	var info := Kit.vbox(8)
	info.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	info.grow_vertical = Control.GROW_DIRECTION_BEGIN
	info.offset_left = 28
	info.offset_bottom = -24
	_banner.add_child(info)
	_kicker = Kit.label("", 12, 700, Color(1, 1, 1, 0.75))
	var kv := FontVariation.new()
	kv.base_font = Kit.font(700)
	kv.spacing_glyph = 3
	_kicker.add_theme_font_override("font", kv)
	info.add_child(_kicker)
	_logo = TextureRect.new()
	_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	_logo.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(_logo)
	_title = Kit.label("", 44, 800, Color.WHITE, true)
	_title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.35))
	_title.add_theme_constant_override("shadow_outline_size", 12)
	info.add_child(_title)
	_meta = Kit.label("", 15, 500, Color(1, 1, 1, 0.8))
	info.add_child(_meta)

	var actions := Kit.hbox(12)
	col.add_child(actions)
	_play = FxButton.make("Play", "play", FxButton.Style.PRIMARY, 52)
	_play.custom_minimum_size.x = 180
	_play.pressed.connect(func() -> void: main.launch(entry_id))
	actions.add_child(_play)
	_fav = FxButton.icon_only("heart", "Favourite", 22, 52)
	_fav.variant = FxButton.Style.GHOST
	_fav._apply_style()
	_fav.pressed.connect(func() -> void: Catalog.toggle_favorite("lib:" + entry_id))
	actions.add_child(_fav)
	var edit := FxButton.make("Edit", "edit", FxButton.Style.GHOST, 52)
	edit.pressed.connect(func() -> void: main.open_edit(entry_id))
	actions.add_child(edit)
	var more := FxButton.icon_only("more", "More", 22, 52)
	more.variant = FxButton.Style.GHOST
	more._apply_style()
	more.pressed.connect(func() -> void: main.show_entry_menu(entry_id, more.global_position + Vector2(0, more.size.y + 8)))
	actions.add_child(more)

	_stats = Kit.hbox(12)
	col.add_child(_stats)

	Library.entry_changed.connect(func(id: String) -> void:
		if id == entry_id and visible:
			show_entry(id)
	)
	Art.art_ready.connect(func(id: String, kind: StringName) -> void:
		if id == entry_id and kind == &"logo":
			_apply_logo()
	)


func show_entry(id: String) -> void:
	entry_id = id
	var e := Library.get_entry(id)
	if e.is_empty():
		return
	var is_game: bool = e["kind"] == "game"
	_hero.setup(id, 18.0, &"hero")
	_kicker.text = Library.source_label(e).to_upper()
	_title.text = str(e["name"])
	_title.visible = true
	_logo.visible = false
	_apply_logo()
	var parts := PackedStringArray()
	parts.append(Fmt.playtime(int(e["playtime"])) if is_game else ("Opened %d times" % int(e["launches"])))
	if int(e["last_played"]) > 0:
		parts.append(("Last played " if is_game else "Last used ") + Fmt.ago(int(e["last_played"])).to_lower())
	_meta.text = "  ·  ".join(parts)
	_play.text = "Play" if is_game else "Open"
	_play.set_icon_name("play" if is_game else "external")
	var fav: bool = e["favorite"]
	_fav.set_icon_name("heart_fill" if fav else "heart", Color("ff6b8a") if fav else Color.WHITE)
	_fav.tooltip_text = "Remove from favourites" if fav else "Add to favourites"
	for c in _stats.get_children():
		c.queue_free()
	_stats.add_child(_stat("clock", "Played", Fmt.playtime(int(e["playtime"])).replace(" played", "") if int(e["playtime"]) >= 60 else "–"))
	_stats.add_child(_stat("bolt", "Launches", str(int(e["launches"]))))
	_stats.add_child(_stat("star", "Last played", Fmt.ago(int(e["last_played"])) if int(e["last_played"]) > 0 else "Never"))
	_stats.add_child(_stat("layers", "From", Library.source_label(e)))


func _apply_logo() -> void:
	var tex := Art.get_art(entry_id, &"logo")
	if tex == null:
		return
	var sz := tex.get_size()
	var s := minf(420.0 / sz.x, 130.0 / sz.y)
	_logo.texture = tex
	_logo.custom_minimum_size = sz * s
	_logo.visible = true
	_title.visible = false


func _stat(icon_name: String, label: String, value: String) -> Control:
	var p := PanelContainer.new()
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.add_theme_stylebox_override("panel", Kit.box(Color(1, 1, 1, 0.05), 16, Color(1, 1, 1, 0.07), 1, 18, 14))
	var row := Kit.hbox(12)
	p.add_child(row)
	var ic := Kit.icon_rect(icon_name, 18, App.accent.lightened(0.25))
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(ic)
	var col := Kit.vbox(2)
	row.add_child(col)
	col.add_child(Kit.label(label, 12, 600, App.TEXT_MUTE))
	col.add_child(Kit.label(value, 16, 700, App.TEXT))
	return p
