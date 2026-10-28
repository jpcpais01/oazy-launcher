class_name Desktop
extends Control
## What's on the desktop behind your windows: the clock, the date and the
## weather with a slim system glance under them, your favourites, a "Continue
## playing" card with the last game's artwork and recently played covers.
## One scroll down there's a second screen (DesktopBelow): ten covers,
## markets, news, the forecast and the month. The wheel glides between the
## two on a soft spring, and whichever screen is out of sight is parked.

const LEFT := 64.0
const TOP := 52.0
const HERO_W := 600.0
const RECENT_MAX := 5
const RECENT_GAP := 14.0
const FAV_COLS := 6
const FAV_MAX := 12
## Favourite tile sizes (setting fav_icon_size): tile, icon, label size, gap.
const FAV_SIZES := {
	"small": {"tile": Vector2(84, 88), "icon": 44, "font": 12, "gap": 7},
	"medium": {"tile": Vector2(100, 104), "icon": 56, "font": 13, "gap": 9},
	"large": {"tile": Vector2(124, 130), "icon": 74, "font": 14, "gap": 10},
}
## How far the desktop eases back while Start is open.
const DIM_SCALE := 0.97
## How quickly scrolling settles (a critically damped spring; higher is snappier).
const SPRING := 10.5
## Wheel notch inside the second screen, once it's taller than one.
const STEP := 120.0
const CLOCK := preload("res://shaders/clock.gdshader")
const SHADE := preload("res://shaders/hero_shade.gdshader")

var main: Node
## The first screen (everything above) and the second one, below it.
var _top: Control
var below: DesktopBelow
var _scrim: ColorRect
var _hint: Button
var _scroll := 0.0
var _goal := 0.0
var _vel := 0.0
var _pan_timer: Timer
var _pan_dir := 0.0
var _greeting: Label
var _time: Label
var _date: Label
var _hero_glass: GlassPanel
var _hero_art: CoverArt
var _hero_kicker: Label
var _hero_logo: TextureRect
var _hero_title: Label
var _hero_meta: Label
var _hero_play: FxButton
var _hero_box: VBoxContainer
var _empty_box: VBoxContainer
var _recent_title: Label
var _recent: HBoxContainer
var _system: GlassPanel
var _favs_title: Label
var _favs: ReorderGrid
var _skip_fill := false
var _date_row: HBoxContainer
var _weather_icon: TextureRect
var _weather_text: Label
var _clock_mat: ShaderMaterial
var _zoom_tween: Tween
var _cpu: Array = []
var _gpu: Array = []
var _mem: Array = []
var _hero_id := ""
var _last_minute := -1
var _stats_timer: Timer
var _dim_tween: Tween
var _dim := 0.0
## The music wallpaper's clean view: 1 hides the whole desktop (see set_clean).
var _clean := 0.0
var _clean_tween: Tween


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)
	_scrim = ColorRect.new()
	_scrim.color = Color(0.01, 0.03, 0.05, 0.0)
	_scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scrim.visible = false
	add_child(_scrim)
	_top = Control.new()
	_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_top)
	below = DesktopBelow.new()
	below.main = main
	below.visible = false
	add_child(below)
	_pan_timer = Timer.new()
	_pan_timer.one_shot = true
	_pan_timer.wait_time = 0.16
	_pan_timer.timeout.connect(_settle)
	add_child(_pan_timer)
	_build_clock()
	_build_hero()
	_build_favorites()
	_build_system()
	_build_hint()

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
	Library.changed.connect(_fill_favorites)
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
	Host.status_changed.connect(func(_ok: bool) -> void: _sync_system())
	Account.changed.connect(func() -> void:
		_last_minute = -1
		_tick()
	)
	Settings.changed.connect(func(key: String, _v: Variant) -> void:
		if key == "user_name":
			_last_minute = -1
			_tick()
		elif key == "effects":
			_sync_clock_fx()
			_drift()
		elif key == "fav_icon_size":
			_fill_favorites()
	)
	App.accent_changed.connect(func(_c: Color) -> void: _sync_clock_fx())
	resized.connect(_layout)
	_tick()
	refresh()
	_fill_favorites()
	_sync_system()
	_layout()


# --- Clock -------------------------------------------------------------------------

func _build_clock() -> void:
	_greeting = Kit.label("", 21, 600, Color(1, 1, 1, 0.88))
	_top.add_child(_greeting)
	_time = Kit.label("", 128, 500, Color.WHITE, true)
	var tv := FontVariation.new()
	tv.base_font = Kit.font(500, true)
	tv.spacing_glyph = -3
	_time.add_theme_font_override("font", tv)
	_clock_mat = ShaderMaterial.new()
	_clock_mat.shader = CLOCK
	_time.material = _clock_mat
	_time.resized.connect(func() -> void: _clock_mat.set_shader_parameter("height", _time.size.y))
	_top.add_child(_time)
	_date_row = Kit.hbox(10)
	_date_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_top.add_child(_date_row)
	_date = Kit.label("", 22, 500, Color(1, 1, 1, 0.78))
	_date_row.add_child(_date)
	# The weather, quietly, after the date.
	_weather_icon = TextureRect.new()
	_weather_icon.custom_minimum_size = Vector2(28, 28)
	_weather_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_weather_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_weather_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_date_row.add_child(Kit.spacer(4, 0))
	_date_row.add_child(_weather_icon)
	_weather_text = Kit.label("", 22, 500, Color(1, 1, 1, 0.78))
	_date_row.add_child(_weather_text)
	Weather.changed.connect(_update_weather)
	_update_weather()
	_sync_clock_fx()


func _update_weather() -> void:
	var now := Weather.current()
	var on := not now.is_empty()
	_weather_icon.visible = on
	_weather_text.visible = on
	if on:
		var code := int(now["code"])
		_weather_icon.texture = WeatherIcons.tex(Weather.kind_for(code), bool(now["day"]), 56)
		_weather_text.text = Weather.temp(now["temp"])
		var tip := Weather.describe(code)
		if Weather.city() != "":
			tip += " in " + Weather.city()
		_weather_icon.tooltip_text = tip
		_weather_text.tooltip_text = tip


func _sync_clock_fx() -> void:
	var tone := Color(1, 1, 1).lerp(App.accent, 0.18).lightened(0.12)
	tone.a = 0.94
	_clock_mat.set_shader_parameter("tone", tone)
	_clock_mat.set_shader_parameter("speed", 0.0 if Settings.get_value("effects") == "eco" else 1.0)


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
	var name := Account.first_name()
	_greeting.text = part + (", " + name if name != "" else "")


# --- Continue playing -------------------------------------------------------------------

func _build_hero() -> void:
	_hero_glass = GlassPanel.new(false, 26.0, GlassPanel.TINT_WIDGET)
	_hero_glass.set_shadow_strength(0.28, 30, 12.0)
	_hero_glass.mouse_filter = Control.MOUSE_FILTER_STOP
	_top.add_child(_hero_glass)
	_hero_art = CoverArt.new()
	_hero_art.glow_enabled = false
	_hero_art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hero_glass.add_child(_hero_art)
	# Shade for the words, clipped to the card's rounded corners.
	var shade := ColorRect.new()
	shade.color = Color.WHITE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sm := ShaderMaterial.new()
	sm.shader = SHADE
	sm.set_shader_parameter("radius", 26.0)
	shade.material = sm
	shade.resized.connect(func() -> void: sm.set_shader_parameter("rect_size", shade.size))
	_hero_glass.add_child(shade)
	var rim := Panel.new()
	rim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rim.add_theme_stylebox_override("panel", Kit.box(Color(0, 0, 0, 0), 26, Color(1, 1, 1, 0.12), 1))
	_hero_glass.add_child(rim)

	_hero_box = Kit.vbox(8)
	_hero_box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_hero_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_hero_box.offset_left = 32
	_hero_box.offset_bottom = -28
	_hero_glass.add_child(_hero_box)
	_hero_kicker = Kit.label("CONTINUE PLAYING", 12, 700, Color(1, 1, 1, 0.75))
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
	_hero_title = Kit.label("", 36, 700, Color.WHITE, true)
	_hero_title.custom_minimum_size.x = 440
	_hero_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hero_title.max_lines_visible = 2
	_hero_box.add_child(_hero_title)
	_hero_meta = Kit.label("", 15, 500, Color(1, 1, 1, 0.78))
	_hero_box.add_child(_hero_meta)
	_hero_box.add_child(Kit.spacer(0, 4))
	var buttons := Kit.hbox(10)
	_hero_box.add_child(buttons)
	_hero_play = FxButton.make("Play", "play", FxButton.Style.PRIMARY, 48)
	_hero_play.custom_minimum_size.x = 150
	_hero_play.pressed.connect(func() -> void:
		if _hero_id != "":
			main.launch(_hero_id)
	)
	buttons.add_child(_hero_play)
	var details := FxButton.icon_only("more", "More", 20, 48)
	details.variant = FxButton.Style.GHOST
	details._apply_style()
	details.pressed.connect(func() -> void:
		if _hero_id != "":
			main.show_entry_menu(_hero_id, details.global_position + Vector2(0, details.size.y + 8))
	)
	buttons.add_child(details)

	_empty_box = Kit.vbox(12)
	_empty_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	_empty_box.grow_vertical = Control.GROW_DIRECTION_BOTH
	_empty_box.offset_left = 32
	_hero_glass.add_child(_empty_box)
	_empty_box.add_child(Kit.label("Bring your games in", 30, 700, Color.WHITE, true))
	var sub := Kit.label("Oazy finds Steam, Epic Games and GOG installs in a second.\nOr drop any .exe or shortcut onto the desktop.", 15, 500, Color(1, 1, 1, 0.75))
	_empty_box.add_child(sub)
	var row := Kit.hbox(10)
	_empty_box.add_child(Kit.spacer(0, 4))
	_empty_box.add_child(row)
	var scan := FxButton.make("Scan this PC", "sparkles", FxButton.Style.PRIMARY, 46)
	scan.pressed.connect(func() -> void: main.scan_stores())
	row.add_child(scan)
	var add := FxButton.make("Add manually", "plus", FxButton.Style.GHOST, 46)
	add.pressed.connect(func() -> void: main.open_add({}))
	row.add_child(add)

	_recent_title = Kit.label("Recently played", 15, 700, Color(1, 1, 1, 0.82))
	_top.add_child(_recent_title)
	_recent = Kit.hbox(14)
	_top.add_child(_recent)


func refresh() -> void:
	var games: Array[Dictionary] = []
	for e in Library.recent():
		if e["kind"] == "game":
			games.append(e)
	if games.is_empty():
		_hero_id = ""
		_hero_art.visible = false
		_hero_box.visible = false
		_empty_box.visible = true
	else:
		_empty_box.visible = false
		_hero_box.visible = true
		_hero_art.visible = true
		var keep := _hero_id if Library.has_entry(_hero_id) else str(games[0]["id"])
		_show_hero(keep)
	for c in _recent.get_children():
		_recent.remove_child(c)
		c.queue_free()
	_recent_title.visible = games.size() > 1
	_recent.visible = games.size() > 1
	for e in games.slice(0, RECENT_MAX):
		_recent.add_child(_recent_tile(str(e["id"])))
	_mark_recent()
	_layout()


func _show_hero(id: String) -> void:
	var e := Library.get_entry(id)
	if e.is_empty():
		return
	var changed := id != _hero_id
	_hero_id = id
	_hero_art.setup(id, 26.0, &"hero")
	if changed and is_visible_in_tree():
		_hero_art.sweep()
		_hero_art.modulate.a = 0.4
		Kit.ease_tween(_hero_art, Tween.TRANS_SINE).tween_property(_hero_art, "modulate:a", 1.0, 0.45)
		_hero_box.modulate.a = 0.0
		Kit.ease_tween(_hero_box).tween_property(_hero_box, "modulate:a", 1.0, 0.4)
	if changed:
		_drift()
	_hero_title.text = str(e["name"])
	_hero_title.visible = true
	_hero_logo.visible = false
	var parts := PackedStringArray()
	if int(e["playtime"]) > 0:
		parts.append(Fmt.playtime(int(e["playtime"])))
	if int(e["last_played"]) > 0:
		parts.append("Last played " + Fmt.ago(int(e["last_played"])).to_lower())
	if parts.is_empty():
		parts.append(Library.source_label(e) + "  ·  Ready to play")
	_hero_meta.text = "  ·  ".join(parts)
	_hero_kicker.text = "CONTINUE PLAYING" if int(e["last_played"]) > 0 else "READY TO PLAY"
	_apply_logo(id)
	_mark_recent()


## The game on the card is ringed in the row below; the rest sit back a touch.
func _mark_recent() -> void:
	for c in _recent.get_children():
		if not c.has_meta("id") or c.get_meta("hot", false):
			continue
		var on := str(c.get_meta("id")) == _hero_id
		var cover: CoverArt = c.get_child(0)
		var t := Kit.hover_tween(c).set_parallel(true).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		t.tween_property(c, "scale", Vector2.ONE, 0.3)
		t.tween_property(cover, "focus_amount", 0.85 if on else 0.0, 0.2)
		cover.set_dim(0.0 if on else 0.14)


## A slow drift across the banner's art, so it never feels like a still.
func _drift() -> void:
	if _zoom_tween and _zoom_tween.is_valid():
		_zoom_tween.kill()
	_hero_art.set_zoom(0.0)
	if Settings.get_value("effects") == "eco" or _hero_id == "":
		return
	_zoom_tween = create_tween().set_loops().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_zoom_tween.tween_method(_hero_art.set_zoom, 0.0, 0.06, 16.0)
	_zoom_tween.tween_method(_hero_art.set_zoom, 0.06, 0.0, 16.0)


func _apply_logo(id: String) -> void:
	var tex := Art.get_art(id, &"logo")
	if tex == null:
		return
	var sz := tex.get_size()
	var s := minf(360.0 / sz.x, 110.0 / sz.y)
	_hero_logo.texture = tex
	_hero_logo.custom_minimum_size = sz * s
	_hero_logo.visible = true
	_hero_title.visible = false


func _recent_tile(id: String) -> Control:
	var holder := Control.new()
	holder.set_meta("id", id)
	holder.custom_minimum_size = Vector2(110, 165)
	holder.mouse_filter = Control.MOUSE_FILTER_STOP
	holder.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	holder.tooltip_text = str(Library.get_entry(id).get("name", ""))
	var cover := CoverArt.new()
	cover.glow_enabled = false
	cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.add_child(cover)
	cover.setup(id, 14.0)
	holder.mouse_entered.connect(func() -> void:
		holder.set_meta("hot", true)
		cover.set_dim(0.0)
		var t := Kit.hover_tween(holder).set_parallel(true).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
		t.tween_property(holder, "scale", Vector2.ONE * 1.03, 0.22)
		t.tween_property(cover, "focus_amount", 1.0, 0.18)
		Sfx.play(&"move", 1.15)
	)
	holder.mouse_exited.connect(func() -> void:
		holder.set_meta("hot", false)
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


# --- Favourites -----------------------------------------------------------------------------
# Straight on the wallpaper, like the recent covers opposite: no box, just
# your apps, a little lift and a glow when you point at one.

func _build_favorites() -> void:
	_favs_title = Kit.label("Favourites", 15, 700, Color(1, 1, 1, 0.82))
	_top.add_child(_favs_title)
	_favs = ReorderGrid.new()
	_favs.columns = FAV_COLS
	_favs.reordered.connect(_on_favs_reordered)
	_top.add_child(_favs)


func _fill_favorites() -> void:
	if _favs == null:
		return
	if _skip_fill:
		# Our own drag saved this order; the tiles are already there.
		_skip_fill = false
		return
	var tiles: Array[Control] = []
	var refs := Catalog.favorites().slice(0, FAV_MAX)
	for ref in refs:
		tiles.append(_fav_tile(Catalog.item(ref)))
	if refs.is_empty():
		# Nothing yet: one quiet tile that says how, and opens Start.
		var add := _fav_tile({"ref": "", "name": "Add favourites"})
		add.set_meta("fixed", true)
		tiles.append(add)
	_favs.set_tiles(tiles, fav_spec()["tile"])
	_layout()


## Dragged into a new order: saved for Start's favourites too.
func _on_favs_reordered(from: int, to: int) -> void:
	var refs := Catalog.favorites()
	if from < 0 or from >= refs.size():
		return
	_skip_fill = true
	Catalog.move_favorite(refs[from], to)
	_skip_fill = false


static func fav_spec() -> Dictionary:
	return FAV_SIZES.get(str(Settings.get_value("fav_icon_size")), FAV_SIZES["medium"])


func _fav_tile(it: Dictionary) -> Control:
	var ref := str(it.get("ref", ""))
	var spec := fav_spec()
	var tile: Vector2 = spec["tile"]
	var b := Button.new()
	b.custom_minimum_size = tile
	b.pivot_offset = tile / 2.0
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.tooltip_text = str(it["name"]) if ref != "" else "Right-click any app or game and choose Add to favourites"
	b.add_theme_stylebox_override("normal", Kit.empty())
	b.add_theme_stylebox_override("hover", Kit.box(Color(1, 1, 1, 0.07), 18, Color(1, 1, 1, 0.1), 1))
	b.add_theme_stylebox_override("pressed", Kit.box(Color(1, 1, 1, 0.12), 18, Color(1, 1, 1, 0.12), 1))
	b.add_theme_stylebox_override("hover_pressed", Kit.box(Color(1, 1, 1, 0.12), 18, Color(1, 1, 1, 0.12), 1))
	var c := Kit.vbox(int(spec["gap"]))
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.alignment = BoxContainer.ALIGNMENT_CENTER
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(c)
	var ic: Control
	if ref == "":
		ic = Panel.new()
		ic.add_theme_stylebox_override("panel", Kit.box(Color(1, 1, 1, 0.05), 16, Color(1, 1, 1, 0.22), 1))
		var plus := Kit.icon_rect("plus", int(spec["icon"]) * 3 / 7, Color(1, 1, 1, 0.7))
		plus.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		plus.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ic.add_child(plus)
	else:
		ic = AppIcon.new()
		(ic as AppIcon).set_item(it)
	ic.custom_minimum_size = Vector2.ONE * float(spec["icon"])
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(ic)
	var l := Kit.label(str(it["name"]), int(spec["font"]), 600, Color(1, 1, 1, 0.9 if ref != "" else 0.6))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.custom_minimum_size.x = tile.x - 10.0
	l.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(l)
	b.mouse_entered.connect(func() -> void:
		var t := Kit.hover_tween(b).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
		t.tween_property(b, "scale", Vector2.ONE * 1.03, 0.2)
		Sfx.play(&"move", 1.2)
	)
	b.mouse_exited.connect(func() -> void:
		var t := Kit.hover_tween(b).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		t.tween_property(b, "scale", Vector2.ONE, 0.3)
	)
	b.pressed.connect(func() -> void:
		if _favs.consume_drag():
			return
		Sfx.play(&"select")
		if ref == "":
			main.start.open()
		else:
			Catalog.launch(ref)
	)
	if ref != "":
		b.gui_input.connect(func(e: InputEvent) -> void:
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_RIGHT:
				main.show_ref_menu(ref, b.get_global_mouse_position())
		)
	return b


# --- System glance -------------------------------------------------------------------------
# One slim glass strip under the date: processor, graphics and memory, each a
# number over a hairline bar. Clocks and temperatures are in the tooltips.

func _build_system() -> void:
	_system = GlassPanel.new(false, 20.0, GlassPanel.TINT_WIDGET)
	_system.set_shadow_strength(0.25, 24, 8.0)
	_system.mouse_filter = Control.MOUSE_FILTER_PASS
	_top.add_child(_system)
	var row := Kit.hbox(18)
	row.position = Vector2(18, 0)
	_system.add_child(row)
	_system.set_meta("col", row)
	_cpu = _meter(row, "cpu", "CPU", "Processor")
	_gpu = _meter(row, "monitor", "GPU", "Graphics")
	_gpu[4].visible = false
	_mem = _meter(row, "memory", "RAM", "Memory")


func _meter(parent: Control, icon_name: String, title: String, full: String) -> Array:
	var row := Kit.hbox(9)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	row.tooltip_text = full
	row.set_meta("full", full)
	parent.add_child(row)
	var ic := Kit.icon_rect(icon_name, 16, Color(1, 1, 1, 0.75))
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(ic)
	var col := Kit.vbox(5)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)
	var head := Kit.hbox(6)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(head)
	var name := Kit.label(title, 12, 600, Color(1, 1, 1, 0.55))
	head.add_child(name)
	head.add_child(Kit.spacer(0, 0, true))
	var pct := Kit.label("–", 13, 700, App.TEXT)
	head.add_child(pct)
	# Clock speed, temperature or size, when the PC tells us (in the tooltip).
	var detail := Kit.label("", 12, 500, Color(1, 1, 1, 0.42))
	detail.visible = false
	head.add_child(detail)
	var track := Panel.new()
	track.custom_minimum_size = Vector2(64, 4)
	track.add_theme_stylebox_override("panel", Kit.box(Color(1, 1, 1, 0.12), 2))
	col.add_child(track)
	var fill := Panel.new()
	fill.add_theme_stylebox_override("panel", Kit.box(App.accent, 2))
	fill.size = Vector2(0, 4)
	track.add_child(fill)
	# A meter that was hidden has no width yet: fill it once it gets one.
	track.resized.connect(func() -> void:
		fill.size.x = maxf(4.0, track.size.x * clampf(float(track.get_meta("v", 0.0)), 0.0, 1.0))
	)
	return [pct, track, fill, detail, row]


func set_stats(cpu: float, mem: float) -> void:
	_set_meter(_cpu, cpu)
	_set_meter(_mem, mem)


func _set_meter(m: Array, v: float) -> void:
	if m.is_empty() or v < 0.0:
		return
	var pct: Label = m[0]
	var track: Panel = m[1]
	var fill: Panel = m[2]
	track.set_meta("v", v)
	pct.text = "%d%%" % int(round(v * 100.0))
	var col := App.accent if v < 0.85 else App.WARNING
	fill.add_theme_stylebox_override("panel", Kit.box(col, 2))
	if track.size.x <= 0.0:
		return
	var t := create_tween().set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	t.tween_property(fill, "size:x", maxf(4.0, track.size.x * clampf(v, 0.0, 1.0)), 0.6)


## Clocks and temperatures from the companion's sensor thread. Anything it
## couldn't read is -1 (or missing) and simply isn't shown.
func set_sensors(d: Dictionary) -> void:
	var cpu_temp := float(d.get("cpu_temp", -1.0)) if Settings.get_value("cpu_temp") else -1.0
	_set_detail(_cpu, float(d.get("cpu_mhz", -1.0)), cpu_temp, 90.0)
	var load := float(d.get("gpu_load", -1.0))
	var temp := float(d.get("gpu_temp", -1.0))
	var on := load >= 0.0 or temp >= 0.0
	if _gpu[4].visible != on:
		_gpu[4].visible = on
		_layout()
	if on:
		var name := _short_gpu(str(d.get("gpu_name", "")))
		(_gpu[4] as Control).tooltip_text = str(d.get("gpu_name", ""))
		if load >= 0.0:
			_set_meter(_gpu, load / 100.0)
		else:
			_set_meter(_gpu, temp / 100.0)
			(_gpu[0] as Label).text = "%d°" % roundi(temp)
		_set_detail(_gpu, float(d.get("gpu_mhz", -1.0)), temp if load >= 0.0 else -1.0, 85.0, name)
	var total := float(d.get("mem_total", 0.0)) / 1073741824.0
	var mem := float(d.get("mem", -1.0))
	if total > 0.0 and mem >= 0.0:
		(_mem[3] as Label).text = "%.1f of %d GB" % [mem * total, roundi(total)]
		_tip(_mem)


func _set_detail(m: Array, mhz: float, temp: float, hot: float, prefix: String = "") -> void:
	var parts: PackedStringArray = []
	if prefix != "":
		parts.append(prefix)
	if mhz > 0.0:
		parts.append("%.1f GHz" % (mhz / 1000.0) if mhz >= 1000.0 else "%d MHz" % roundi(mhz))
	if temp > 0.0:
		parts.append("%d°" % roundi(temp))
	var l: Label = m[3]
	l.text = " · ".join(parts)
	l.add_theme_color_override("font_color", App.WARNING if temp >= hot else Color(1, 1, 1, 0.42))
	# A hot part shows its temperature in amber on the strip itself.
	var name: Label = (m[0] as Label).get_parent().get_child(0)
	name.add_theme_color_override("font_color", App.WARNING if temp >= hot else Color(1, 1, 1, 0.55))
	_tip(m)


func _tip(m: Array) -> void:
	var row: Control = m[4]
	var d := (m[3] as Label).text
	row.tooltip_text = str(row.get_meta("full")) + ("  ·  " + d if d != "" else "")


## "NVIDIA GeForce RTX 4070 SUPER" -> "RTX 4070 SUPER", short enough for a caption.
static func _short_gpu(full: String) -> String:
	var n := full
	for prefix in ["NVIDIA ", "GeForce ", "AMD ", "Radeon(TM) ", "Radeon ", "Intel(R) ", "Intel ", "Arc(TM) "]:
		if n.begins_with(prefix):
			n = n.substr(prefix.length())
	n = n.replace("(TM)", "").replace(" Graphics", "").replace(" Laptop GPU", "").strip_edges()
	return n if n.length() <= 14 else ""


func _sync_system() -> void:
	_system.visible = Host.available or _system.has_meta("mock")
	_layout()


func show_mock_stats(cpu: float, mem: float, sensors: Dictionary = {}) -> void:
	_system.set_meta("mock", true)
	_sync_system()
	await get_tree().process_frame
	set_stats(cpu, mem)
	set_sensors(sensors.merged({"mem": mem}))


func _poll_stats() -> void:
	if not Host.available or not is_visible_in_tree() or not _top.visible or not (Host.self_foreground or (Shell.native and not Host.fullscreen_app)):
		return
	Host.stats(func(d: Dictionary) -> void:
		if not d.get("ok", false):
			return
		set_stats(float(d.get("cpu", -1.0)), float(d.get("mem", -1.0)))
		set_sensors(d)
		if main and main.taskbar:
			main.taskbar.set_battery(int(d.get("battery", -1)), bool(d.get("charging", false)))
	, bool(Settings.get_value("cpu_temp")))


# --- Layout ------------------------------------------------------------------------------------

func _layout() -> void:
	if _time == null or _system == null or _hint == null:
		return
	_top.size = size
	below.size = size
	below.layout_for(size.x, size.y - Taskbar.RESERVE, LEFT)
	_hint.position = Vector2(roundf((size.x - _hint.size.x) * 0.5), size.y - Taskbar.RESERVE - _hint.size.y - 10.0)
	_goal = clampf(_goal, 0.0, max_scroll())
	_scroll = clampf(_scroll, 0.0, max_scroll())
	_apply_scroll()
	var w := size.x
	var hero_w := clampf(w * 0.4, 500.0, 760.0)
	var hero_h := roundf(hero_w * 9.0 / 16.0)
	var hero_x := w - LEFT - hero_w
	_greeting.position = Vector2(LEFT + 4.0, TOP)
	_time.position = Vector2(LEFT - 4.0, TOP + 18.0)
	_date_row.position = Vector2(LEFT + 4.0, TOP + 176.0)
	_date_row.size = _date_row.get_combined_minimum_size()
	_hero_glass.position = Vector2(hero_x, TOP + 8.0)
	_hero_glass.size = Vector2(hero_w, hero_h)
	# Recent covers span the card's width exactly.
	var n := maxi(1, _recent.get_child_count())
	var cw := floorf((hero_w - RECENT_GAP * (RECENT_MAX - 1)) / RECENT_MAX)
	var card := Vector2(cw, roundf(cw * 1.5))
	_recent.add_theme_constant_override("separation", int(RECENT_GAP))
	for c in _recent.get_children():
		var cc := c as Control
		cc.custom_minimum_size = card
		cc.pivot_offset = Vector2(card.x * 0.5, card.y)
	_recent_title.position = Vector2(hero_x + 4.0, TOP + 8.0 + hero_h + 24.0)
	_recent.position = Vector2(hero_x, _recent_title.position.y + 32.0)
	_recent.size = Vector2(n * cw + (n - 1) * RECENT_GAP, card.y)
	# The system strip sits under the date; favourites line up with the
	# recent covers across the way.
	var inner: Control = _system.get_meta("col")
	var ins := inner.get_combined_minimum_size()
	_system.size = Vector2(ins.x + 36.0, 50.0)
	inner.size = Vector2(ins.x, 50.0)
	_system.position = Vector2(LEFT, _date_row.position.y + 50.0)
	var room := hero_x - LEFT - 48.0
	var tile_w: float = (fav_spec()["tile"] as Vector2).x
	_favs.columns = clampi(floori((room + 4.0) / (tile_w + 4.0)), 2, FAV_COLS + 2)
	_favs_title.position = Vector2(LEFT + 4.0, _recent_title.position.y)
	_favs.position = Vector2(LEFT - 10.0, _recent.position.y - 6.0)
	_favs.size = _favs.get_combined_minimum_size()


# --- Scrolling ---------------------------------------------------------------------------------
# Two screens, one above the other. A wheel notch on the first glides all the
# way to the second (and back), on a critically damped spring so it starts
# softly, never overshoots and can be redirected mid-flight. Touchpads follow
# the fingers, then settle on whichever screen they were heading for.

## A faint chevron at the bottom of the first screen: there's more below.
func _build_hint() -> void:
	_hint = Button.new()
	_hint.focus_mode = Control.FOCUS_NONE
	_hint.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_hint.tooltip_text = "More below"
	_hint.custom_minimum_size = Vector2(56, 28)
	_hint.size = Vector2(56, 28)
	_hint.icon = Icons.tex("chevron_down", 20)
	_hint.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.expand_icon = false
	for st in ["normal", "hover", "pressed", "hover_pressed"]:
		_hint.add_theme_stylebox_override(st, Kit.empty())
	_hint.add_theme_color_override("icon_normal_color", Color(1, 1, 1, 0.38))
	_hint.add_theme_color_override("icon_hover_color", Color(1, 1, 1, 0.85))
	_hint.add_theme_color_override("icon_pressed_color", Color(1, 1, 1, 0.95))
	_hint.pressed.connect(func() -> void: page(1))
	_top.add_child(_hint)
	# The music wallpaper's player sits where the hint does.
	_hint.visible = not Music.on
	Music.toggled.connect(func(on: bool) -> void: _hint.visible = not on)


## The furthest the desktop scrolls: the second screen, or past it when the
## second screen is taller than one (a small window).
func max_scroll() -> float:
	return maxf(size.y, below.wanted_height + Taskbar.RESERVE)


## 1 = the second screen, -1 = back to the first.
func page(dir: int) -> void:
	scroll_to(size.y if dir > 0 else 0.0)


func scroll_to(y: float) -> void:
	_goal = clampf(y, 0.0, max_scroll())
	_sync_active()
	set_process(true)


func at_top() -> bool:
	return _goal <= 0.5


func _wheel_here() -> bool:
	if main == null or not main.loaded or main.modal_open() or main.start.is_open:
		return false
	var hov := get_viewport().gui_get_hovered_control()
	return hov == null or is_ancestor_of(hov)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_WHEEL_UP and mb.button_index != MOUSE_BUTTON_WHEEL_DOWN:
			return
		if not _wheel_here():
			return
		_wheel(1.0 if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1.0, mb.factor if mb.factor > 0.0 else 1.0)
		get_viewport().set_input_as_handled()
	elif event is InputEventPanGesture:
		if not _wheel_here():
			return
		var d := (event as InputEventPanGesture).delta.y * 18.0
		if absf(d) < 0.01:
			return
		_pan_dir = signf(d)
		_goal = clampf(_goal + d, 0.0, max_scroll())
		_sync_active()
		set_process(true)
		_pan_timer.start()
		get_viewport().set_input_as_handled()


func _wheel(dir: float, factor: float) -> void:
	var p := size.y
	if dir > 0.0:
		_goal = p if _goal < p - 1.0 else minf(_goal + STEP * factor, max_scroll())
	else:
		_goal = 0.0 if _goal <= p + 1.0 else maxf(_goal - STEP * factor, p)
	_sync_active()
	set_process(true)


## A touchpad let go between the screens: finish the trip it started.
func _settle() -> void:
	var p := size.y
	if _goal <= 0.0 or _goal >= p:
		return
	var k := _goal / p
	scroll_to(p if (k > 0.18 if _pan_dir > 0.0 else k > 0.82) else 0.0)


func _process(delta: float) -> void:
	# Exact step of a critically damped spring, so it's stable at any frame rate.
	var x := _scroll - _goal
	var e := exp(-SPRING * delta)
	var a := _vel + SPRING * x
	var nx := (x + a * delta) * e
	_vel = (_vel - SPRING * a * delta) * e
	_scroll = _goal + nx
	if absf(nx) < 0.3 and absf(_vel) < 6.0:
		_scroll = _goal
		_vel = 0.0
		set_process(false)
	_apply_scroll()
	if not is_processing():
		_sync_active()


## The second screen wakes as soon as a trip down starts (so its data is on
## the way while it glides in) and sleeps once the first is fully back.
func _sync_active() -> void:
	below.set_active(_goal > 0.0 or _scroll > 0.5)


func _apply_scroll() -> void:
	var p := maxf(size.y, 1.0)
	var k := clampf(_scroll / p, 0.0, 1.0)
	_top.position.y = -roundf(_scroll)
	below.position.y = roundf(p - _scroll)
	var top_a := 1.0 - smoothstep(0.2, 0.95, k)
	var below_a := smoothstep(0.08, 0.8, k)
	_top.modulate.a = top_a
	below.modulate.a = below_a
	_top.visible = k < 0.999
	below.visible = k > 0.001
	_scrim.visible = k > 0.001
	_scrim.color.a = 0.14 * k
	_hint.modulate.a = 1.0 - smoothstep(0.0, 0.12, k)
	_sync_shadows()
	# Nothing on the first screen needs to move while it's out of sight.
	if _zoom_tween and _zoom_tween.is_valid():
		if _top.visible and not _zoom_tween.is_running():
			_zoom_tween.play()
		elif not _top.visible and _zoom_tween.is_running():
			_zoom_tween.pause()


## Modulate isn't group opacity: a fading card's shadow would show through it
## as a dark smudge, so shadows fade faster than what casts them.
func _sync_shadows() -> void:
	var shown := (1.0 - _dim) * (1.0 - _clean)
	var a := _top.modulate.a * shown
	_hero_glass.set_shadow_fade(a * a * a)
	var b := below.modulate.a * shown
	for c in below.parts():
		if c is GlassPanel:
			(c as GlassPanel).set_shadow_fade(b * b * b)


func intro() -> void:
	var items: Array[Control] = [_greeting, _time, _date_row, _system, _hero_glass, _favs_title, _favs, _recent_title, _recent]
	for i in items.size():
		var c := items[i]
		var y := c.position.y
		c.modulate.a = 0.0
		c.position.y = y + 18.0
		var t := create_tween().set_parallel(true).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		t.tween_property(c, "modulate:a", 1.0, 0.7).set_delay(0.12 + i * 0.05)
		t.tween_property(c, "position:y", y, 0.9).set_delay(0.12 + i * 0.05)


## Fades the desktop out while Start is open, so the two never fight for
## attention (or show a clock cut in half behind Start). The whole desktop
## eases back a touch as it fades, then settles forward again on close, as
## one move. `_dim` is 0 (shown) to 1 (gone).
func dim(on: bool) -> void:
	if _dim_tween and _dim_tween.is_valid():
		_dim_tween.kill()
	pivot_offset = size * 0.5
	_dim_tween = create_tween()
	if on:
		_dim_tween.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
		_dim_tween.tween_method(_set_dim, _dim, 1.0, 0.26)
	else:
		_dim_tween.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
		_dim_tween.tween_method(_set_dim, _dim, 0.0, 0.42)


func _set_dim(v: float) -> void:
	_dim = v
	_apply_fade()


## Clears the desktop away so only the music wallpaper shows (clicking the
## bare desktop while it plays), or brings it back.
func set_clean(on: bool) -> void:
	if _clean_tween and _clean_tween.is_valid():
		_clean_tween.kill()
	pivot_offset = size * 0.5
	if not on:
		visible = true
	_clean_tween = create_tween()
	if on:
		_clean_tween.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
		_clean_tween.tween_method(func(v: float) -> void:
			_clean = v
			_apply_fade()
		, _clean, 1.0, 0.5)
		# Hidden for real once it's gone, so clicks reach the wallpaper.
		_clean_tween.tween_callback(func() -> void: visible = false)
	else:
		_clean_tween.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
		_clean_tween.tween_method(func(v: float) -> void:
			_clean = v
			_apply_fade()
		, _clean, 0.0, 0.6)


func _apply_fade() -> void:
	var shown := (1.0 - _dim) * (1.0 - _clean)
	modulate.a = shown
	scale = Vector2.ONE * lerpf(1.0, DIM_SCALE, maxf(_dim, _clean))
	# Each layer of the card fades on its own, so the shadow under the art goes
	# first; otherwise it darkens the half-faded card on the way out.
	_sync_shadows()
