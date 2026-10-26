class_name Desktop
extends Control
## What's on the desktop behind your windows. Your games are the centrepiece:
## a big banner for the one you're playing and a row of large cover cards for
## the rest. Beside them, a quiet column: the clock with the weather, your
## favourites and recent apps, and a glance at this PC.

const TOP := 52.0
const SIDE := 64.0
const COLUMN := 384.0
const GAP := 22.0
const COVER := Vector2(150, 225)
const COVER_GAP := 18.0
const RADIUS := 26.0
const RING := preload("res://shaders/ring.gdshader")
const CLOCK := preload("res://shaders/clock.gdshader")
const SHADE := preload("res://shaders/hero_shade.gdshader")

var main: Node
var _clock: Control
var _date: Label
var _time: Label
var _greeting: Label
var _greet_row: HBoxContainer
var _weather_dot: Label
var _weather_icon: TextureRect
var _weather_text: Label
var _clock_mat: ShaderMaterial
var _hero_glass: GlassPanel
var _hero_art: CoverArt
var _hero_kicker: Label
var _hero_logo: TextureRect
var _hero_title: Label
var _hero_meta: Label
var _hero_play: FxButton
var _hero_box: VBoxContainer
var _empty_box: VBoxContainer
var _games: Control
var _games_title: Label
var _library_tile: Button
var _zoom_tween: Tween
var _system: GlassPanel
var _favs_glass: GlassPanel
var _favs: GridContainer
var _favs_hint: Label
var _recent_head: HBoxContainer
var _recent_apps: HBoxContainer
var _cpu: Array = []
var _mem: Array = []
var _gpu: Array = []
var _battery: Array = []
var _hz: Label
var _hero_id := ""
var _last_minute := -1
var _stats_timer: Timer
var _dim_tween: Tween


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_clock()
	_build_favorites()
	_build_hero()
	_build_system()

	var tick := Timer.new()
	tick.wait_time = 1.0
	tick.autostart = true
	tick.timeout.connect(_tick)
	add_child(tick)
	_stats_timer = Timer.new()
	_stats_timer.wait_time = 2.0
	_stats_timer.autostart = true
	_stats_timer.timeout.connect(_poll_stats)
	add_child(_stats_timer)

	Library.changed.connect(refresh)
	Catalog.favorites_changed.connect(_fill_favorites)
	Catalog.apps_changed.connect(_fill_favorites)
	Library.entry_changed.connect(func(id: String) -> void:
		if id == _hero_id:
			_show_hero(id)
	)
	Art.art_ready.connect(func(id: String, kind: StringName) -> void:
		if id == _hero_id and kind == &"logo":
			_apply_logo(id)
	)
	Host.status_changed.connect(func(_ok: bool) -> void:
		_sync_system()
		_layout()
	)
	App.accent_changed.connect(func(_c: Color) -> void: _tint_accent())
	Settings.changed.connect(func(key: String, _v: Variant) -> void:
		if key == "user_name":
			_last_minute = -1
			_tick()
		elif key == "recent_apps":
			_fill_favorites.call_deferred()
		elif key == "effects":
			_clock_mat.set_shader_parameter("speed", 0.0 if Settings.get_value("effects") == "eco" else 1.0)
	)
	resized.connect(_layout)
	_tick()
	refresh()
	_sync_system()
	_tint_accent()
	_layout()


# --- Clock -------------------------------------------------------------------------

func _build_clock() -> void:
	_clock = Control.new()
	_clock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_clock)
	_greeting = Kit.label("", 20, 600, Color(1, 1, 1, 0.86))
	_shadow(_greeting, 4)
	_clock.add_child(_greeting)
	_time = Kit.label("", 132, 500, Color.WHITE, true)
	var tv := FontVariation.new()
	tv.base_font = Kit.font(500, true)
	tv.spacing_glyph = -4
	_time.add_theme_font_override("font", tv)
	_time.add_theme_color_override("font_shadow_color", Color(0, 0.03, 0.06, 0.18))
	_time.add_theme_constant_override("shadow_offset_y", 4)
	_time.add_theme_constant_override("shadow_outline_size", 16)
	_clock_mat = ShaderMaterial.new()
	_clock_mat.shader = CLOCK
	_clock_mat.set_shader_parameter("speed", 0.0 if Settings.get_value("effects") == "eco" else 1.0)
	_time.material = _clock_mat
	_time.resized.connect(func() -> void: _clock_mat.set_shader_parameter("height", _time.size.y))
	_clock.add_child(_time)
	# The date, and the weather beside it when there is some.
	_greet_row = Kit.hbox(10)
	_greet_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clock.add_child(_greet_row)
	_date = Kit.label("", 17, 500, Color(1, 1, 1, 0.74))
	_shadow(_date, 4)
	_greet_row.add_child(_date)
	_weather_dot = Kit.label("·", 17, 700, Color(1, 1, 1, 0.4))
	_greet_row.add_child(_weather_dot)
	_weather_icon = TextureRect.new()
	_weather_icon.custom_minimum_size = Vector2(26, 26)
	_weather_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_weather_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_weather_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_greet_row.add_child(_weather_icon)
	_weather_text = Kit.label("", 17, 500, Color(1, 1, 1, 0.74))
	_shadow(_weather_text, 4)
	_greet_row.add_child(_weather_text)
	Weather.changed.connect(_update_weather)
	_update_weather()


func _update_weather() -> void:
	var now := Weather.current()
	var on := not now.is_empty()
	_weather_dot.visible = on
	_weather_icon.visible = on
	_weather_text.visible = on
	if on:
		var code := int(now["code"])
		_weather_icon.texture = WeatherIcons.tex(Weather.kind_for(code), bool(now["day"]), 48)
		_weather_text.text = "%s  %s" % [Weather.temp(now["temp"]), Weather.describe(code)]
	_layout_clock()


func _shadow(l: Label, size_px: int) -> void:
	l.add_theme_color_override("font_shadow_color", Color(0, 0.03, 0.06, 0.22))
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.add_theme_constant_override("shadow_outline_size", size_px)


func _tick() -> void:
	var t := Time.get_datetime_dict_from_system()
	if int(t["minute"]) == _last_minute:
		return
	_last_minute = int(t["minute"])
	_time.text = "%02d:%02d" % [t["hour"], t["minute"]]
	_date.text = Fmt.long_date(t)
	var h := int(t["hour"])
	var part := "Good evening"
	if h >= 5 and h < 12:
		part = "Good morning"
	elif h >= 12 and h < 18:
		part = "Good afternoon"
	elif h < 5:
		part = "Good night"
	var name := str(Settings.get_value("user_name")).strip_edges()
	if name == "":
		name = App.user_name()
	_greeting.text = part + (", " + name if name != "" else "")
	_layout_clock()


func _tint_accent() -> void:
	var tone := Color(1, 1, 1).lerp(App.accent, 0.22).lightened(0.1)
	tone.a = 0.9
	_clock_mat.set_shader_parameter("tone", tone)
	for m in [_cpu, _gpu, _mem, _battery]:
		if not m.is_empty():
			var mat: ShaderMaterial = m[2]
			mat.set_shader_parameter("color_a", App.accent.darkened(0.15))
			mat.set_shader_parameter("color_b", App.accent.lightened(0.3))


# --- Widget frame ---------------------------------------------------------------------

func _widget() -> GlassPanel:
	var g := GlassPanel.new(false, RADIUS, GlassPanel.TINT_WIDGET)
	g.set_shadow_strength(0.32, 36, 14.0)
	g.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(g)
	return g


func _header(icon_name: String, title: String) -> HBoxContainer:
	var head := Kit.hbox(8)
	var ic := Kit.icon_rect(icon_name, 14, Color(1, 1, 1, 0.55))
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(ic)
	var l := Kit.label(title.to_upper(), 11, 700, Color(1, 1, 1, 0.55))
	var v := FontVariation.new()
	v.base_font = Kit.font(700)
	v.spacing_glyph = 2
	l.add_theme_font_override("font", v)
	head.add_child(l)
	return head


# --- Favourites -----------------------------------------------------------------------------

const FAV_COLS := 4
const FAV_MAX := 8
const FAV_TILE := Vector2(82, 88)


func _build_favorites() -> void:
	_favs_glass = _widget()
	var col := Kit.vbox(10)
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 18
	col.offset_right = -18
	col.offset_top = 18
	col.offset_bottom = -14
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_favs_glass.add_child(col)
	var head := _header("heart_fill", "Favourites")
	head.add_child(Kit.spacer(0, 0, true))
	col.add_child(head)
	_favs = GridContainer.new()
	_favs.columns = FAV_COLS
	_favs.add_theme_constant_override("h_separation", 2)
	_favs.add_theme_constant_override("v_separation", 2)
	_favs.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_favs.size_flags_vertical = Control.SIZE_SHRINK_CENTER | Control.SIZE_EXPAND
	col.add_child(_favs)
	_favs_hint = Kit.label("Right-click any app or game\nand choose Add to favourites.\nThey'll wait for you here.", 14, 500, Color(1, 1, 1, 0.6))
	_favs_hint.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_favs_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_favs_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_favs_hint)
	_recent_head = _header("clock", "Recent")
	col.add_child(_recent_head)
	_recent_apps = Kit.hbox(2)
	_recent_apps.alignment = BoxContainer.ALIGNMENT_CENTER
	_recent_apps.size_flags_vertical = Control.SIZE_SHRINK_CENTER | Control.SIZE_EXPAND
	col.add_child(_recent_apps)


func _fill_favorites() -> void:
	if _favs == null:
		return
	for c in _favs.get_children():
		_favs.remove_child(c)
		c.queue_free()
	for c in _recent_apps.get_children():
		_recent_apps.remove_child(c)
		c.queue_free()
	var refs := Catalog.favorites().slice(0, FAV_MAX)
	_favs.visible = not refs.is_empty()
	for ref in refs:
		_favs.add_child(_fav_tile(ref))
	# One row of favourites leaves room for what you used last.
	var recent: Array[String] = []
	if refs.size() <= FAV_COLS:
		for ref in Catalog.recent_apps():
			if ref not in refs and str(Catalog.item(ref)["name"]) != "" and recent.size() < FAV_COLS:
				recent.append(ref)
	for ref in recent:
		_recent_apps.add_child(_fav_tile(ref))
	_recent_head.visible = not recent.is_empty()
	_recent_apps.visible = not recent.is_empty()
	_favs_hint.visible = refs.is_empty() and recent.is_empty()
	if refs.is_empty() and not recent.is_empty():
		_favs.visible = false
	_layout()


func _fav_tile(ref: String) -> Control:
	var it := Catalog.item(ref)
	var b := Button.new()
	b.custom_minimum_size = FAV_TILE
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.tooltip_text = str(it["name"])
	b.pivot_offset = FAV_TILE * 0.5
	b.add_theme_stylebox_override("normal", Kit.empty())
	b.add_theme_stylebox_override("hover", Kit.box(Color(1, 1, 1, 0.08), 18, Color(1, 1, 1, 0.07), 1))
	b.add_theme_stylebox_override("pressed", Kit.box(Color(1, 1, 1, 0.13), 18))
	var c := Kit.vbox(8)
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.alignment = BoxContainer.ALIGNMENT_CENTER
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(c)
	var ic := AppIcon.new()
	ic.custom_minimum_size = Vector2(46, 46)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ic.set_item(it)
	c.add_child(ic)
	var l := Kit.label(str(it["name"]), 12, 500, Color(1, 1, 1, 0.82))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.custom_minimum_size.x = FAV_TILE.x - 8.0
	l.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	c.add_child(l)
	b.mouse_entered.connect(func() -> void:
		Kit.ease_tween(b, Tween.TRANS_BACK).tween_property(b, "scale", Vector2.ONE * 1.05, 0.25)
	)
	b.mouse_exited.connect(func() -> void:
		Kit.ease_tween(b).tween_property(b, "scale", Vector2.ONE, 0.25)
	)
	b.pressed.connect(func() -> void:
		Sfx.play(&"select")
		Catalog.launch(ref)
	)
	b.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_RIGHT:
			main.show_ref_menu(ref, b.get_global_mouse_position())
	)
	return b


# --- Now playing -----------------------------------------------------------------------

func _build_hero() -> void:
	_hero_glass = _widget()
	_hero_glass.set_shadow_strength(0.42, 44, 18.0)
	_hero_glass.clip_contents = false
	_hero_art = CoverArt.new()
	_hero_art.glow_enabled = false
	_hero_art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hero_glass.add_child(_hero_art)
	var shade := ColorRect.new()
	shade.color = Color.WHITE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sm := ShaderMaterial.new()
	sm.shader = SHADE
	sm.set_shader_parameter("radius", RADIUS)
	shade.material = sm
	shade.resized.connect(func() -> void: sm.set_shader_parameter("rect_size", shade.size))
	_hero_glass.add_child(shade)
	var rim := Panel.new()
	rim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rim.add_theme_stylebox_override("panel", Kit.box(Color(0, 0, 0, 0), int(RADIUS), Color(1, 1, 1, 0.13), 1))
	_hero_glass.add_child(rim)

	_hero_box = Kit.vbox(6)
	_hero_box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_hero_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_hero_box.offset_left = 36
	_hero_box.offset_bottom = -32
	_hero_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hero_glass.add_child(_hero_box)
	_hero_kicker = Kit.label("CONTINUE PLAYING", 11, 700, Color(1, 1, 1, 0.7))
	var kv := FontVariation.new()
	kv.base_font = Kit.font(700)
	kv.spacing_glyph = 3
	_hero_kicker.add_theme_font_override("font", kv)
	_hero_box.add_child(_hero_kicker)
	_hero_logo = TextureRect.new()
	_hero_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_hero_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	_hero_logo.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_hero_logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hero_box.add_child(_hero_logo)
	_hero_title = Kit.label("", 40, 800, Color.WHITE, true)
	_hero_title.custom_minimum_size.x = 300
	_hero_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hero_title.max_lines_visible = 2
	_hero_title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.35))
	_hero_title.add_theme_constant_override("shadow_outline_size", 10)
	_hero_box.add_child(_hero_title)
	_hero_meta = Kit.label("", 15, 500, Color(1, 1, 1, 0.78))
	_hero_box.add_child(_hero_meta)
	_hero_box.add_child(Kit.spacer(0, 6))
	var buttons := Kit.hbox(10)
	_hero_box.add_child(buttons)
	_hero_play = FxButton.make("Play", "play", FxButton.Style.PRIMARY, 48)
	_hero_play.custom_minimum_size.x = 150
	_hero_play.pressed.connect(func() -> void:
		if _hero_id != "":
			main.launch(_hero_id)
	)
	buttons.add_child(_hero_play)
	var more := FxButton.icon_only("more", "More", 20, 48)
	more.variant = FxButton.Style.GHOST
	more._apply_style()
	more.pressed.connect(func() -> void:
		if _hero_id != "":
			main.show_entry_menu(_hero_id, more.global_position + Vector2(0, more.size.y + 8))
	)
	buttons.add_child(more)


	_games = Control.new()
	_games.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_games)
	_games_title = Kit.label("Your games", 15, 700, Color(1, 1, 1, 0.82))
	_shadow(_games_title, 3)
	add_child(_games_title)
	_library_tile = _make_library_tile()

	_empty_box = Kit.vbox(10)
	_empty_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	_empty_box.grow_vertical = Control.GROW_DIRECTION_BOTH
	_empty_box.offset_left = 30
	_hero_glass.add_child(_empty_box)
	_empty_box.add_child(Kit.label("Bring your games in", 28, 800, Color.WHITE, true))
	_empty_box.add_child(Kit.label("Oazy finds Steam, Epic Games, GOG and more in a second.\nOr drop any .exe or shortcut onto the desktop.", 14, 500, Color(1, 1, 1, 0.72)))
	_empty_box.add_child(Kit.spacer(0, 4))
	var row := Kit.hbox(10)
	_empty_box.add_child(row)
	var scan := FxButton.make("Scan this PC", "sparkles", FxButton.Style.PRIMARY, 44)
	scan.pressed.connect(func() -> void: main.scan_stores())
	row.add_child(scan)
	var add := FxButton.make("Add manually", "plus", FxButton.Style.GHOST, 44)
	add.pressed.connect(func() -> void: main.open_add({}))
	row.add_child(add)


func refresh() -> void:
	_fill_favorites()
	var games: Array[Dictionary] = []
	for e in Library.recent():
		if e["kind"] == "game":
			games.append(e)
	var has := not games.is_empty()
	_empty_box.visible = not has
	_hero_box.visible = has
	_hero_art.visible = has
	if has:
		var keep := _hero_id if Library.has_entry(_hero_id) else str(games[0]["id"])
		_show_hero(keep)
	else:
		_hero_id = ""
	for c in _games.get_children():
		if c != _library_tile:
			_games.remove_child(c)
			c.queue_free()
	for e in games.slice(0, 12):
		_games.add_child(_cover_card(str(e["id"])))
	_games.move_child(_library_tile, -1)
	_games.visible = has
	_games_title.visible = has
	_mark_recent()
	_layout()


func _show_hero(id: String) -> void:
	var e := Library.get_entry(id)
	if e.is_empty():
		return
	var changed := id != _hero_id
	_hero_id = id
	_hero_art.setup(id, RADIUS, &"hero")
	_hero_title.text = str(e["name"])
	_hero_title.visible = true
	_hero_logo.visible = false
	var parts := PackedStringArray()
	if int(e["playtime"]) > 0:
		parts.append(Fmt.playtime(int(e["playtime"])))
	if int(e["last_played"]) > 0:
		parts.append(Fmt.ago(int(e["last_played"])))
	if parts.is_empty():
		parts.append(Library.source_label(e))
	_hero_meta.text = "  ·  ".join(parts)
	_hero_kicker.text = "CONTINUE PLAYING" if int(e["last_played"]) > 0 else "READY TO PLAY"
	_apply_logo(id)
	_mark_recent()
	if changed and is_visible_in_tree():
		_hero_art.sweep()
		_hero_art.modulate.a = 0.35
		Kit.ease_tween(_hero_art, Tween.TRANS_SINE).tween_property(_hero_art, "modulate:a", 1.0, 0.5)
		_hero_box.modulate.a = 0.0
		var t := Kit.ease_tween(_hero_box)
		t.tween_property(_hero_box, "modulate:a", 1.0, 0.45)
	if changed:
		_drift()


## A slow Ken Burns drift on the banner, so the art feels alive.
func _drift() -> void:
	if _zoom_tween and _zoom_tween.is_valid():
		_zoom_tween.kill()
	_hero_art.set_zoom(0.0)
	if Settings.get_value("effects") == "eco":
		return
	_zoom_tween = create_tween().set_loops().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_zoom_tween.tween_method(_hero_art.set_zoom, 0.0, 0.07, 18.0)
	_zoom_tween.tween_method(_hero_art.set_zoom, 0.07, 0.0, 18.0)


func _mark_recent() -> void:
	for c in _games.get_children():
		if c.has_meta("id"):
			var on := str(c.get_meta("id")) == _hero_id
			c.set_meta("on", on)
			if c.get_meta("hot", false):
				continue
			var cover: CoverArt = c.get_child(0)
			cover.focus_amount = 1.0 if on else 0.0
			cover.set_dim(0.0 if on else 0.18)


func _apply_logo(id: String) -> void:
	var tex := Art.get_art(id, &"logo")
	if tex == null:
		return
	var sz := tex.get_size()
	var s := minf(380.0 / sz.x, 130.0 / sz.y)
	_hero_logo.texture = tex
	_hero_logo.custom_minimum_size = sz * s
	_hero_logo.visible = true
	_hero_title.visible = false


func _cover_card(id: String) -> Control:
	var holder := Control.new()
	holder.set_meta("id", id)
	holder.custom_minimum_size = COVER
	holder.size = COVER
	holder.mouse_filter = Control.MOUSE_FILTER_STOP
	holder.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	holder.tooltip_text = str(Library.get_entry(id).get("name", ""))
	holder.pivot_offset = Vector2(COVER.x * 0.5, COVER.y)
	var cover := CoverArt.new()
	cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.add_child(cover)
	cover.setup(id, 16.0)
	holder.mouse_entered.connect(func() -> void:
		holder.set_meta("hot", true)
		cover.sweep()
		cover.set_dim(0.0)
		var t := Kit.ease_tween(holder, Tween.TRANS_BACK).set_parallel(true)
		t.tween_property(holder, "scale", Vector2.ONE * 1.06, 0.3)
		t.tween_property(cover, "focus_amount", 1.0, 0.25)
		Sfx.play(&"move", 1.15)
	)
	holder.mouse_exited.connect(func() -> void:
		holder.set_meta("hot", false)
		Kit.ease_tween(holder).tween_property(holder, "scale", Vector2.ONE, 0.3)
		_mark_recent()
	)
	holder.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed:
			if ev.button_index == MOUSE_BUTTON_LEFT and ev.double_click:
				main.launch(id)
			elif ev.button_index == MOUSE_BUTTON_LEFT:
				Sfx.play(&"select")
				_show_hero(id)
			elif ev.button_index == MOUSE_BUTTON_RIGHT:
				main.show_entry_menu(id, holder.get_global_mouse_position())
	)
	return holder


## The last card in the row: everything else, in the Library.
func _make_library_tile() -> Button:
	var b := Button.new()
	b.custom_minimum_size = COVER
	b.size = COVER
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.pivot_offset = Vector2(COVER.x * 0.5, COVER.y)
	b.add_theme_stylebox_override("normal", Kit.box(Color(1, 1, 1, 0.05), 16, Color(1, 1, 1, 0.1), 1))
	b.add_theme_stylebox_override("hover", Kit.box(Color(1, 1, 1, 0.1), 16, Color(1, 1, 1, 0.18), 1))
	b.add_theme_stylebox_override("pressed", Kit.box(Color(1, 1, 1, 0.14), 16, Color(1, 1, 1, 0.18), 1))
	var c := Kit.vbox(12)
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.alignment = BoxContainer.ALIGNMENT_CENTER
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(c)
	var ic := Kit.icon_rect("grid", 30, Color(1, 1, 1, 0.85))
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	c.add_child(ic)
	var l := Kit.label("All games", 14, 600, Color(1, 1, 1, 0.85))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	c.add_child(l)
	b.mouse_entered.connect(func() -> void:
		Kit.ease_tween(b, Tween.TRANS_BACK).tween_property(b, "scale", Vector2.ONE * 1.06, 0.3)
	)
	b.mouse_exited.connect(func() -> void:
		Kit.ease_tween(b).tween_property(b, "scale", Vector2.ONE, 0.3)
	)
	b.pressed.connect(func() -> void:
		Sfx.play(&"select")
		main.open_app(&"library")
	)
	_games.add_child(b)
	return b


# --- This PC ------------------------------------------------------------------------------

func _build_system() -> void:
	_system = _widget()
	var col := Kit.vbox(10)
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 18
	col.offset_right = -18
	col.offset_top = 16
	col.offset_bottom = -14
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_system.add_child(col)
	var head := _header("cpu", "This PC")
	head.add_child(Kit.spacer(0, 0, true))
	_hz = Kit.label("", 11, 700, Color(1, 1, 1, 0.55))
	_hz.tooltip_text = "Display refresh rate"
	_hz.mouse_filter = Control.MOUSE_FILTER_PASS
	head.add_child(_hz)
	col.add_child(head)
	var rings := Kit.hbox(6)
	rings.alignment = BoxContainer.ALIGNMENT_CENTER
	rings.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(rings)
	_cpu = _ring(rings, "Processor")
	_gpu = _ring(rings, "Graphics")
	_gpu[3].visible = false
	_mem = _ring(rings, "Memory")
	_battery = _ring(rings, "Battery")
	_battery[3].visible = false


## [value label, caption, ring material, holder, detail line]
func _ring(parent: Control, title: String) -> Array:
	var holder := Kit.vbox(8)
	holder.alignment = BoxContainer.ALIGNMENT_CENTER
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(holder)
	var ring := ColorRect.new()
	ring.custom_minimum_size = Vector2(74, 74)
	ring.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ring.color = Color.WHITE
	var mat := ShaderMaterial.new()
	mat.shader = RING
	mat.set_shader_parameter("progress", 0.0)
	mat.set_shader_parameter("thickness", 0.1)
	mat.set_shader_parameter("glow", 0.6)
	mat.set_shader_parameter("track", Color(1, 1, 1, 0.09))
	mat.set_shader_parameter("color_a", App.accent.darkened(0.15))
	mat.set_shader_parameter("color_b", App.accent.lightened(0.3))
	ring.material = mat
	holder.add_child(ring)
	var pct := Kit.label("–", 18, 700, Color.WHITE, true)
	pct.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pct.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ring.add_child(pct)
	var text := Kit.vbox(1)
	holder.add_child(text)
	var cap := Kit.label(title, 12, 600, Color(1, 1, 1, 0.6))
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text.add_child(cap)
	# Always laid out (even empty) so the rings don't shift when data arrives.
	var detail := Kit.label("", 11, 600, Color(1, 1, 1, 0.42))
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text.add_child(detail)
	return [pct, cap, mat, holder, detail]


func set_stats(cpu: float, mem: float) -> void:
	_set_ring(_cpu, cpu)
	_set_ring(_mem, mem)


## Clocks and temperatures from the companion's sensor thread. Anything it
## couldn't read is -1 (or missing) and simply isn't shown.
func set_sensors(d: Dictionary) -> void:
	var cpu_temp := float(d.get("cpu_temp", -1.0)) if Settings.get_value("cpu_temp") else -1.0
	_set_detail(_cpu, float(d.get("cpu_mhz", -1.0)), cpu_temp, 90.0)
	var load := float(d.get("gpu_load", -1.0))
	var temp := float(d.get("gpu_temp", -1.0))
	var on := load >= 0.0 or temp >= 0.0
	if _gpu[3].visible != on:
		_gpu[3].visible = on
		_layout()
	if on:
		var name := _short_gpu(str(d.get("gpu_name", "")))
		(_gpu[1] as Label).text = name if name != "" else "Graphics"
		_gpu[3].tooltip_text = str(d.get("gpu_name", ""))
		if load >= 0.0:
			_set_ring(_gpu, load / 100.0)
		else:
			# No load figure (some older drivers): the ring shows the temperature.
			_set_ring(_gpu, temp / 100.0)
			(_gpu[0] as Label).text = "%d°" % roundi(temp)
		_set_detail(_gpu, float(d.get("gpu_mhz", -1.0)), temp if load >= 0.0 else -1.0, 85.0)
	var total := float(d.get("mem_total", 0.0)) / 1073741824.0
	var mem := float(d.get("mem", -1.0))
	if total > 0.0 and mem >= 0.0:
		(_mem[4] as Label).text = "%.1f / %d GB" % [mem * total, roundi(total)]


func _set_detail(m: Array, mhz: float, temp: float, hot: float) -> void:
	var parts: PackedStringArray = []
	if mhz > 0.0:
		parts.append("%.1f GHz" % (mhz / 1000.0) if mhz >= 1000.0 else "%d MHz" % roundi(mhz))
	if temp > 0.0:
		parts.append("%d°" % roundi(temp))
	var l: Label = m[4]
	l.text = " · ".join(parts)
	l.add_theme_color_override("font_color", App.WARNING if temp >= hot else Color(1, 1, 1, 0.42))


## "NVIDIA GeForce RTX 4070 SUPER" -> "RTX 4070 SUPER", short enough for a caption.
static func _short_gpu(full: String) -> String:
	var n := full
	for prefix in ["NVIDIA ", "GeForce ", "AMD ", "Radeon(TM) ", "Radeon ", "Intel(R) ", "Intel ", "Arc(TM) "]:
		if n.begins_with(prefix):
			n = n.substr(prefix.length())
	n = n.replace("(TM)", "").replace(" Graphics", "").replace(" Laptop GPU", "").strip_edges()
	return n if n.length() <= 14 else ""


func _sync_hz() -> void:
	var hz := roundi(DisplayServer.screen_get_refresh_rate(get_window().current_screen))
	if _system.has_meta("mock_hz"):
		hz = int(_system.get_meta("mock_hz"))
	_hz.text = "%d Hz" % hz if hz > 0 else ""


func set_battery(level: int, charging: bool) -> void:
	var on := level >= 0
	if _battery[3].visible != on:
		_battery[3].visible = on
		_layout()
	if on:
		_set_ring(_battery, level / 100.0, false)
		(_battery[1] as Label).text = "Charging" if charging else "Battery"


func _set_ring(m: Array, v: float, warn_high: bool = true) -> void:
	if m.is_empty() or v < 0.0:
		return
	var pct: Label = m[0]
	var mat: ShaderMaterial = m[2]
	pct.text = "%d%%" % int(round(v * 100.0))
	var hot := (v >= 0.85) if warn_high else (v <= 0.15)
	mat.set_shader_parameter("color_a", App.WARNING.darkened(0.1) if hot else App.accent.darkened(0.15))
	mat.set_shader_parameter("color_b", App.WARNING.lightened(0.2) if hot else App.accent.lightened(0.3))
	var from := float(mat.get_shader_parameter("progress"))
	var t := create_tween().set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	t.tween_method(func(k: float) -> void: mat.set_shader_parameter("progress", k), from, clampf(v, 0.0, 1.0), 0.8)


func _sync_system() -> void:
	_system.visible = Host.available or _system.has_meta("mock")
	_sync_hz()


func show_mock_stats(cpu: float, mem: float, sensors: Dictionary = {}) -> void:
	_system.set_meta("mock", true)
	if sensors.has("hz"):
		_system.set_meta("mock_hz", sensors["hz"])
	_sync_system()
	_layout()
	await get_tree().process_frame
	set_stats(cpu, mem)
	set_sensors(sensors.merged({"mem": mem}))


func _poll_stats() -> void:
	if not Host.available or not is_visible_in_tree() or not (Host.self_foreground or (Shell.native and not Host.fullscreen_app)):
		return
	_sync_hz()
	Host.stats(func(d: Dictionary) -> void:
		if not d.get("ok", false):
			return
		set_stats(float(d.get("cpu", -1.0)), float(d.get("mem", -1.0)))
		set_sensors(d)
		set_battery(int(d.get("battery", -1)), bool(d.get("charging", false)))
		if main and main.taskbar:
			main.taskbar.set_battery(int(d.get("battery", -1)), bool(d.get("charging", false)))
	, bool(Settings.get_value("cpu_temp")))


# --- Layout ------------------------------------------------------------------------------------

func _layout() -> void:
	if _time == null or _system == null or _games == null:
		return
	var w := size.x
	var bottom := size.y - Taskbar.RESERVE - 34.0
	var right_x := SIDE + COLUMN + GAP * 2.0
	var right_w := w - right_x - SIDE
	# The cover row: as many cards as fit, then "All games", stretched a
	# touch so the row ends exactly where the banner does.
	var fit := maxi(2, int((right_w + COVER_GAP) / (COVER.x + COVER_GAP)))
	var card := Vector2((right_w - COVER_GAP * (fit - 1)) / fit, 0.0)
	card.y = roundf(card.x * 1.5)
	var per := card.x + COVER_GAP
	var shown := 0
	for c in _games.get_children():
		var cc := c as Control
		cc.custom_minimum_size = card
		cc.size = card
		cc.pivot_offset = Vector2(card.x * 0.5, card.y)
		if c == _library_tile:
			continue
		cc.visible = shown < fit - 1
		if cc.visible:
			cc.position = Vector2(shown * per, 0)
			shown += 1
	_library_tile.position = Vector2(shown * per, 0)
	var row_y := bottom - card.y
	_games.position = Vector2(right_x, row_y)
	_games.size = Vector2(right_w, card.y)
	_games_title.position = Vector2(right_x + 2.0, row_y - 34.0)
	var hero_bottom := (row_y - 50.0) if _games.visible else bottom
	_hero_glass.position = Vector2(right_x, TOP)
	_hero_glass.size = Vector2(right_w, maxf(260.0, hero_bottom - TOP))
	_hero_title.custom_minimum_size.x = clampf(right_w * 0.5, 300.0, 520.0)

	# The side column: the clock up top, This PC on the floor and your
	# favourites just above it.
	var y := bottom
	if _system.visible:
		_system.size = Vector2(COLUMN, 166.0)
		_system.position = Vector2(SIDE, bottom - 166.0)
		y = _system.position.y - GAP
	var rows := 0
	if _favs.visible:
		rows += 2 if _favs.get_child_count() > FAV_COLS else 1
	if _recent_apps.visible:
		rows += 1
	var fav_h := 32.0 + maxf(1.0, rows) * FAV_TILE.y + (36.0 if _recent_apps.visible and _favs.visible else 0.0) + 22.0
	_favs_glass.size = Vector2(COLUMN, fav_h)
	_favs_glass.position = Vector2(SIDE, y - fav_h)
	_layout_clock()


func _layout_clock() -> void:
	if _favs_glass == null:
		return
	var gh := _greeting.get_combined_minimum_size().y
	var th := _time.get_combined_minimum_size().y
	var rh := _greet_row.get_combined_minimum_size().y
	_clock.position = Vector2(SIDE + 2.0, TOP - 6.0)
	_greeting.position = Vector2(2, 0)
	_time.position = Vector2(-6, gh - 22.0)
	_greet_row.position = Vector2(2, gh + th - 42.0)
	_greet_row.size = Vector2(COLUMN, rh)
	_clock.size = Vector2(COLUMN, gh + th + rh - 42.0)


func intro() -> void:
	var items: Array[Control] = [_clock, _hero_glass, _games_title, _games, _favs_glass, _system]
	for i in items.size():
		var c := items[i]
		var y := c.position.y
		var a := c.modulate.a
		c.modulate.a = 0.0
		c.position.y = y + (14.0 if i == 0 else 26.0)
		var t := create_tween().set_parallel(true).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		t.tween_property(c, "modulate:a", a, 0.8).set_delay(0.1 + i * 0.07)
		t.tween_property(c, "position:y", y, 1.0).set_delay(0.1 + i * 0.07)


## Fades the desktop out while Start is open, so the two never fight for
## attention (or show a clock cut in half behind Start).
func dim(on: bool) -> void:
	if _dim_tween and _dim_tween.is_valid():
		_dim_tween.kill()
	_dim_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_dim_tween.tween_property(self, "modulate:a", 0.0 if on else 1.0, 0.22 if on else 0.35)
