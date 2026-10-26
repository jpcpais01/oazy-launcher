class_name Desktop
extends Control
## What's on the desktop behind your windows. One calm composition: a centred
## glass clock with the date and a greeting, and a single shelf of widgets on
## the horizon above the taskbar: your favourites, the game you're playing
## (with the next few one click away), and a glance at this PC.

const SHELF_H := 250.0
const GAP := 18.0
const SIDE := 56.0
const HERO_MIN := 470.0
const HERO_MAX := 660.0
const PC_W := 258.0
const RADIUS := 28.0
const RING := preload("res://shaders/ring.gdshader")
const CLOCK := preload("res://shaders/clock.gdshader")
const SHADE := preload("res://shaders/hero_shade.gdshader")

var main: Node
var _clock: Control
var _date: Label
var _time: Label
var _greeting: Label
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
var _all_games: FxButton
var _recent: HBoxContainer
var _system: GlassPanel
var _favs_glass: GlassPanel
var _favs: GridContainer
var _favs_hint: Label
var _recent_head: HBoxContainer
var _recent_apps: HBoxContainer
var _cpu: Array = []
var _mem: Array = []
var _battery: Array = []
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
	_date = Kit.label("", 19, 600, Color(1, 1, 1, 0.86))
	var dv := FontVariation.new()
	dv.base_font = Kit.font(600)
	dv.spacing_glyph = 1
	_date.add_theme_font_override("font", dv)
	_date.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_shadow(_date, 4)
	_clock.add_child(_date)
	_time = Kit.label("", 156, 500, Color.WHITE, true)
	var tv := FontVariation.new()
	tv.base_font = Kit.font(500, true)
	tv.spacing_glyph = -5
	_time.add_theme_font_override("font", tv)
	_time.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_time.add_theme_color_override("font_shadow_color", Color(0, 0.03, 0.06, 0.18))
	_time.add_theme_constant_override("shadow_offset_y", 4)
	_time.add_theme_constant_override("shadow_outline_size", 18)
	_clock_mat = ShaderMaterial.new()
	_clock_mat.shader = CLOCK
	_clock_mat.set_shader_parameter("speed", 0.0 if Settings.get_value("effects") == "eco" else 1.0)
	_time.material = _clock_mat
	_time.resized.connect(func() -> void: _clock_mat.set_shader_parameter("height", _time.size.y))
	_clock.add_child(_time)
	_greeting = Kit.label("", 17, 500, Color(1, 1, 1, 0.66))
	_greeting.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_shadow(_greeting, 4)
	_clock.add_child(_greeting)


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
	for m in [_cpu, _mem, _battery]:
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
	_hero_box.offset_left = 28
	_hero_box.offset_bottom = -24
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
	_hero_title = Kit.label("", 32, 800, Color.WHITE, true)
	_hero_title.custom_minimum_size.x = 300
	_hero_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hero_title.max_lines_visible = 2
	_hero_title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.35))
	_hero_title.add_theme_constant_override("shadow_outline_size", 10)
	_hero_box.add_child(_hero_title)
	_hero_meta = Kit.label("", 14, 500, Color(1, 1, 1, 0.76))
	_hero_box.add_child(_hero_meta)
	_hero_box.add_child(Kit.spacer(0, 6))
	var buttons := Kit.hbox(10)
	_hero_box.add_child(buttons)
	_hero_play = FxButton.make("Play", "play", FxButton.Style.PRIMARY, 44)
	_hero_play.custom_minimum_size.x = 128
	_hero_play.pressed.connect(func() -> void:
		if _hero_id != "":
			main.launch(_hero_id)
	)
	buttons.add_child(_hero_play)
	var more := FxButton.icon_only("more", "More", 20, 44)
	more.variant = FxButton.Style.GHOST
	more._apply_style()
	more.pressed.connect(func() -> void:
		if _hero_id != "":
			main.show_entry_menu(_hero_id, more.global_position + Vector2(0, more.size.y + 8))
	)
	buttons.add_child(more)

	_all_games = FxButton.make("Library", "grid", FxButton.Style.GHOST, 34)
	_all_games.add_theme_font_size_override("font_size", 13)
	_all_games.icon = Icons.tex("grid", 15, Color.WHITE)
	_all_games.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_all_games.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_all_games.offset_right = -18
	_all_games.offset_top = 18
	_all_games.pressed.connect(func() -> void: main.open_app(&"library"))
	_hero_glass.add_child(_all_games)

	_recent = Kit.hbox(10)
	_hero_glass.add_child(_recent)
	_hero_glass.resized.connect(_place_recent)

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
	_all_games.visible = has
	if has:
		var keep := _hero_id if Library.has_entry(_hero_id) else str(games[0]["id"])
		_show_hero(keep)
	else:
		_hero_id = ""
	for c in _recent.get_children():
		_recent.remove_child(c)
		c.queue_free()
	if games.size() > 1:
		for e in games.slice(0, 4):
			_recent.add_child(_recent_tile(str(e["id"])))
	_mark_recent()
	_layout()
	_place_recent()


## The next few games sit in the hero's bottom-right corner.
func _place_recent() -> void:
	var n := _recent.get_child_count()
	var sz := Vector2(n * 58.0 + maxf(0.0, n - 1.0) * 10.0, 87.0)
	_recent.size = sz
	_recent.position = _hero_glass.size - sz - Vector2(22, 22)


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
		_hero_box.modulate.a = 0.0
		Kit.ease_tween(_hero_box).tween_property(_hero_box, "modulate:a", 1.0, 0.4)


func _mark_recent() -> void:
	for c in _recent.get_children():
		if c.has_meta("id"):
			var on := str(c.get_meta("id")) == _hero_id
			c.modulate = Color.WHITE if on else Color(1, 1, 1, 0.62)
			var cover: CoverArt = c.get_child(0)
			cover.focus_amount = 1.0 if on else 0.0


func _apply_logo(id: String) -> void:
	var tex := Art.get_art(id, &"logo")
	if tex == null:
		return
	var sz := tex.get_size()
	var s := minf(260.0 / sz.x, 84.0 / sz.y)
	_hero_logo.texture = tex
	_hero_logo.custom_minimum_size = sz * s
	_hero_logo.visible = true
	_hero_title.visible = false


func _recent_tile(id: String) -> Control:
	var holder := Control.new()
	holder.set_meta("id", id)
	holder.custom_minimum_size = Vector2(58, 87)
	holder.mouse_filter = Control.MOUSE_FILTER_STOP
	holder.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	holder.tooltip_text = str(Library.get_entry(id).get("name", ""))
	holder.pivot_offset = Vector2(29, 87)
	var cover := CoverArt.new()
	cover.glow_enabled = false
	cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.add_child(cover)
	cover.setup(id, 10.0)
	holder.mouse_entered.connect(func() -> void:
		Kit.ease_tween(holder, Tween.TRANS_BACK).tween_property(holder, "scale", Vector2.ONE * 1.1, 0.28)
		holder.modulate = Color.WHITE
		Sfx.play(&"move", 1.15)
	)
	holder.mouse_exited.connect(func() -> void:
		Kit.ease_tween(holder).tween_property(holder, "scale", Vector2.ONE, 0.28)
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


# --- This PC ------------------------------------------------------------------------------

func _build_system() -> void:
	_system = _widget()
	var col := Kit.vbox(0)
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 18
	col.offset_right = -18
	col.offset_top = 18
	col.offset_bottom = -18
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_system.add_child(col)
	col.add_child(_header("cpu", "This PC"))
	var rings := Kit.hbox(6)
	rings.alignment = BoxContainer.ALIGNMENT_CENTER
	rings.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(rings)
	_cpu = _ring(rings, "Processor")
	_mem = _ring(rings, "Memory")
	_battery = _ring(rings, "Battery")
	_battery[3].visible = false


## [value label, caption, ring material, holder]
func _ring(parent: Control, title: String) -> Array:
	var holder := Kit.vbox(10)
	holder.alignment = BoxContainer.ALIGNMENT_CENTER
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(holder)
	var ring := ColorRect.new()
	ring.custom_minimum_size = Vector2(92, 92)
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
	var pct := Kit.label("–", 22, 700, Color.WHITE, true)
	pct.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pct.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ring.add_child(pct)
	var cap := Kit.label(title, 12, 600, Color(1, 1, 1, 0.6))
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	holder.add_child(cap)
	return [pct, cap, mat, holder]


func set_stats(cpu: float, mem: float) -> void:
	_set_ring(_cpu, cpu)
	_set_ring(_mem, mem)


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


func show_mock_stats(cpu: float, mem: float) -> void:
	_system.set_meta("mock", true)
	_sync_system()
	_layout()
	await get_tree().process_frame
	set_stats(cpu, mem)


func _poll_stats() -> void:
	if not Host.available or not is_visible_in_tree() or not (Host.self_foreground or (Shell.native and not Host.fullscreen_app)):
		return
	Host.stats(func(d: Dictionary) -> void:
		if not d.get("ok", false):
			return
		set_stats(float(d.get("cpu", -1.0)), float(d.get("mem", -1.0)))
		set_battery(int(d.get("battery", -1)), bool(d.get("charging", false)))
		if main and main.taskbar:
			main.taskbar.set_battery(int(d.get("battery", -1)), bool(d.get("charging", false)))
	)


# --- Layout ------------------------------------------------------------------------------------

func _layout() -> void:
	if _time == null or _system == null:
		return
	var w := size.x
	var bottom := size.y - Taskbar.RESERVE - 34.0
	var shelf_h := SHELF_H
	var fav_w := FAV_TILE.x * FAV_COLS + 2.0 * (FAV_COLS - 1) + 36.0
	var pc_w := PC_W + (110.0 if _battery[3].visible else 0.0)
	var avail := w - SIDE * 2.0
	var show_pc := _system.visible
	var hero_w := clampf(avail - fav_w - (pc_w + GAP if show_pc else 0.0) - GAP, HERO_MIN, HERO_MAX)
	if show_pc and fav_w + hero_w + pc_w + GAP * 2.0 > avail:
		show_pc = false
		hero_w = clampf(avail - fav_w - GAP, HERO_MIN, HERO_MAX)
	_system.modulate.a = 1.0 if show_pc else 0.0
	_system.mouse_filter = Control.MOUSE_FILTER_STOP if show_pc else Control.MOUSE_FILTER_IGNORE
	var total := fav_w + GAP + hero_w + (GAP + pc_w if show_pc else 0.0)
	var x := roundf((w - total) * 0.5)
	var y := roundf(bottom - shelf_h)
	_favs_glass.position = Vector2(x, y)
	_favs_glass.size = Vector2(fav_w, shelf_h)
	x += fav_w + GAP
	_hero_glass.position = Vector2(x, y)
	_hero_glass.size = Vector2(hero_w, shelf_h)
	x += hero_w + GAP
	_system.position = Vector2(x, y)
	_system.size = Vector2(pc_w, shelf_h)
	_hero_title.custom_minimum_size.x = clampf(hero_w * 0.5, 240.0, 340.0)
	_layout_clock()


func _layout_clock() -> void:
	if _favs_glass == null:
		return
	var w := size.x
	var shelf_top := _favs_glass.position.y
	for l in [_date, _time, _greeting]:
		l.size = Vector2(w, 0)
	var dh := _date.get_combined_minimum_size().y
	var th := _time.get_combined_minimum_size().y
	var gh := _greeting.get_combined_minimum_size().y
	var block := dh + th + gh - 40.0
	# Sit a little above the middle of the space over the shelf.
	var top := roundf(maxf(28.0, (shelf_top - block) * 0.4))
	_clock.position = Vector2(0, top)
	_clock.size = Vector2(w, block)
	_date.position = Vector2(0, 0)
	_time.position = Vector2(0, dh - 22.0)
	_greeting.position = Vector2(0, dh + th - 40.0)
	_date.size.x = w
	_time.size.x = w
	_greeting.size.x = w


func intro() -> void:
	var items: Array[Control] = [_clock, _favs_glass, _hero_glass, _system]
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
