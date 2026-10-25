class_name Desktop
extends Control
## What's on the desktop behind your windows: the clock and a greeting, a
## "Continue playing" card with the last game's artwork, recently played
## covers, and a small system glance (CPU, memory, battery).

const LEFT := 64.0
const TOP := 52.0
const HERO_W := 600.0

var main: Node
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
var _cpu: Array = []
var _mem: Array = []
var _hero_id := ""
var _last_minute := -1
var _stats_timer: Timer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_clock()
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
	Library.entry_changed.connect(func(id: String) -> void:
		if id == _hero_id:
			_show_hero(id)
	)
	Art.art_ready.connect(func(id: String, kind: StringName) -> void:
		if id == _hero_id and kind == &"logo":
			_apply_logo(id)
	)
	Host.status_changed.connect(func(_ok: bool) -> void: _sync_system())
	Settings.changed.connect(func(key: String, _v: Variant) -> void:
		if key == "user_name":
			_last_minute = -1
			_tick()
	)
	resized.connect(_layout)
	_tick()
	refresh()
	_sync_system()
	_layout()


# --- Clock -------------------------------------------------------------------------

func _build_clock() -> void:
	_greeting = Kit.label("", 21, 600, Color(1, 1, 1, 0.88))
	_shadow(_greeting, 3)
	add_child(_greeting)
	_time = Kit.label("", 128, 500, Color.WHITE, true)
	var tv := FontVariation.new()
	tv.base_font = Kit.font(500, true)
	tv.spacing_glyph = -4
	_time.add_theme_font_override("font", tv)
	_shadow(_time, 3)
	add_child(_time)
	_date = Kit.label("", 22, 500, Color(1, 1, 1, 0.78))
	_shadow(_date, 3)
	add_child(_date)


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


# --- Continue playing -------------------------------------------------------------------

func _build_hero() -> void:
	_hero_glass = GlassPanel.new(false, 26.0, GlassPanel.TINT_WIDGET)
	_hero_glass.set_shadow_strength(0.4, 40, 18.0)
	_hero_glass.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_hero_glass)
	_hero_art = CoverArt.new()
	_hero_art.glow_enabled = false
	_hero_art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hero_glass.add_child(_hero_art)
	var shade := TextureRect.new()
	var g := Gradient.new()
	g.set_color(0, Color(0.01, 0.04, 0.06, 0.0))
	g.set_color(1, Color(0.01, 0.04, 0.06, 0.85))
	g.add_point(0.45, Color(0.01, 0.04, 0.06, 0.1))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	shade.texture = gt
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hero_glass.add_child(shade)

	_hero_box = Kit.vbox(8)
	_hero_box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_hero_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_hero_box.offset_left = 28
	_hero_box.offset_bottom = -24
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
	_hero_title = Kit.label("", 36, 800, Color.WHITE, true)
	_hero_title.custom_minimum_size.x = 440
	_hero_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hero_title.max_lines_visible = 2
	_hero_title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.35))
	_hero_title.add_theme_constant_override("shadow_outline_size", 10)
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
	_empty_box.add_child(Kit.label("Bring your games in", 30, 800, Color.WHITE, true))
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
	_shadow(_recent_title, 3)
	add_child(_recent_title)
	_recent = Kit.hbox(14)
	add_child(_recent)


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
		c.queue_free()
	_recent_title.visible = games.size() > 1
	for e in games.slice(0, 5):
		_recent.add_child(_recent_tile(str(e["id"])))
	_layout()


func _show_hero(id: String) -> void:
	var e := Library.get_entry(id)
	if e.is_empty():
		return
	_hero_id = id
	_hero_art.setup(id, 26.0, &"hero")
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
	for c in _recent.get_children():
		if c.has_meta("id"):
			c.modulate = Color.WHITE if str(c.get_meta("id")) == id else Color(1, 1, 1, 0.72)


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
	holder.custom_minimum_size = Vector2(106, 159)
	holder.mouse_filter = Control.MOUSE_FILTER_STOP
	holder.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	holder.tooltip_text = str(Library.get_entry(id).get("name", ""))
	holder.pivot_offset = Vector2(53, 80)
	var cover := CoverArt.new()
	cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.add_child(cover)
	cover.setup(id, 14.0)
	holder.mouse_entered.connect(func() -> void:
		cover.sweep()
		var t := holder.create_tween().set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t.tween_property(holder, "scale", Vector2.ONE * 1.06, 0.3)
		t.tween_property(cover, "focus_amount", 1.0, 0.25)
		Sfx.play(&"move", 1.15)
	)
	holder.mouse_exited.connect(func() -> void:
		var t := holder.create_tween().set_parallel(true).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		t.tween_property(holder, "scale", Vector2.ONE, 0.3)
		t.tween_property(cover, "focus_amount", 0.0, 0.25)
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


# --- System glance -------------------------------------------------------------------------

func _build_system() -> void:
	_system = GlassPanel.new(false, 22.0, GlassPanel.TINT_WIDGET)
	_system.set_shadow_strength(0.3, 30, 12.0)
	add_child(_system)
	var col := Kit.vbox(12)
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 22
	col.offset_right = -22
	col.offset_top = 18
	col.offset_bottom = -18
	_system.add_child(col)
	_cpu = _meter(col, "cpu", "Processor")
	_mem = _meter(col, "memory", "Memory")


func _meter(parent: Control, icon_name: String, title: String) -> Array:
	var row := Kit.hbox(12)
	parent.add_child(row)
	var ic := Kit.icon_rect(icon_name, 18, Color(1, 1, 1, 0.8))
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(ic)
	var col := Kit.vbox(6)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	var head := Kit.hbox(6)
	col.add_child(head)
	head.add_child(Kit.label(title, 13, 600, App.TEXT_DIM))
	head.add_child(Kit.spacer(0, 0, true))
	var pct := Kit.label("–", 13, 700, App.TEXT)
	head.add_child(pct)
	var track := Panel.new()
	track.custom_minimum_size.y = 6
	track.add_theme_stylebox_override("panel", Kit.box(Color(1, 1, 1, 0.1), 3))
	col.add_child(track)
	var fill := Panel.new()
	fill.add_theme_stylebox_override("panel", Kit.box(App.accent, 3))
	fill.size = Vector2(0, 6)
	track.add_child(fill)
	return [pct, track, fill]


func set_stats(cpu: float, mem: float) -> void:
	_set_meter(_cpu, cpu)
	_set_meter(_mem, mem)


func _set_meter(m: Array, v: float) -> void:
	if m.is_empty() or v < 0.0:
		return
	var pct: Label = m[0]
	var track: Panel = m[1]
	var fill: Panel = m[2]
	pct.text = "%d%%" % int(round(v * 100.0))
	var col := App.accent if v < 0.85 else App.WARNING
	fill.add_theme_stylebox_override("panel", Kit.box(col, 3))
	var t := create_tween().set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	t.tween_property(fill, "size:x", maxf(6.0, track.size.x * clampf(v, 0.0, 1.0)), 0.6)


func _sync_system() -> void:
	_system.visible = Host.available or _system.has_meta("mock")


func show_mock_stats(cpu: float, mem: float) -> void:
	_system.set_meta("mock", true)
	_system.visible = true
	await get_tree().process_frame
	set_stats(cpu, mem)


func _poll_stats() -> void:
	if not Host.available or not is_visible_in_tree() or not Host.self_foreground:
		return
	Host.stats(func(d: Dictionary) -> void:
		if not d.get("ok", false):
			return
		set_stats(float(d.get("cpu", -1.0)), float(d.get("mem", -1.0)))
		if main and main.taskbar:
			main.taskbar.set_battery(int(d.get("battery", -1)), bool(d.get("charging", false)))
	)


# --- Layout ------------------------------------------------------------------------------------

func _layout() -> void:
	if _time == null:
		return
	var w := size.x
	var hero_w := clampf(w * 0.38, 480.0, HERO_W + 120.0)
	var hero_h := roundf(hero_w * 9.0 / 16.0)
	_greeting.position = Vector2(LEFT + 4.0, TOP)
	_time.position = Vector2(LEFT - 4.0, TOP + 18.0)
	_date.position = Vector2(LEFT + 4.0, TOP + 176.0)
	_hero_glass.position = Vector2(w - LEFT - hero_w, TOP + 8.0)
	_hero_glass.size = Vector2(hero_w, hero_h)
	_recent_title.position = Vector2(w - LEFT - hero_w + 4.0, TOP + 8.0 + hero_h + 22.0)
	_recent.position = Vector2(w - LEFT - hero_w, _recent_title.position.y + 30.0)
	_system.size = Vector2(340, 118)
	_system.position = Vector2(LEFT, size.y - Taskbar.HEIGHT - Taskbar.MARGIN * 2.0 - 30.0 - _system.size.y)


func intro() -> void:
	var items: Array[Control] = [_greeting, _time, _date, _hero_glass, _recent_title, _recent, _system]
	for i in items.size():
		var c := items[i]
		var y := c.position.y
		c.modulate.a = 0.0
		c.position.y = y + 18.0
		var t := create_tween().set_parallel(true).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		t.tween_property(c, "modulate:a", 1.0, 0.7).set_delay(0.12 + i * 0.05)
		t.tween_property(c, "position:y", y, 0.9).set_delay(0.12 + i * 0.05)
