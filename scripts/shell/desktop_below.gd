class_name DesktopBelow
extends Control
## The desktop's second screen, one scroll down: a row of ten covers (your most
## played favourites), then markets, news, the week's weather and the month.
## Nothing here fetches or ticks until it's first scrolled into view, and it
## all goes quiet again once you scroll back up.

const CARDS := 10
const CARD_GAP := 16.0
const PANEL_GAP := 22.0
const PAD := 22.0
const RADIUS := 22.0
const UP := Color("4fdc9b")
const DOWN := Color("ff6b81")
const MONTHS := ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]

var main: Node
var markets: Markets
var news: News
## The height this section wants (it may be taller than one screen).
var wanted_height := 0.0

var _cards: Control
var _cards_sig := ""
var _market_panel: GlassPanel
var _market_rows: VBoxContainer
var _market_status: Label
static var _num_fonts := {}
var _market_edit_box: VBoxContainer
var _market_edit: LineEdit
var _market_edit_btn: FxButton
var _news_panel: GlassPanel
var _news_list: VBoxContainer
var _news_tabs: HBoxContainer
var _news_status: Label
var _weather_panel: GlassPanel
var _weather_body: VBoxContainer
var _cal_panel: GlassPanel
var _cal_body: VBoxContainer
var _cal_day := ""
var _timer: Timer
var _active := false
var _dirty := {"cards": true, "markets": true, "news": true, "weather": true, "calendar": true}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	markets = Markets.new()
	add_child(markets)
	news = News.new()
	add_child(news)
	_cards = Control.new()
	_cards.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_cards)
	_build_markets()
	_build_news()
	_build_weather()
	_build_calendar()

	_timer = Timer.new()
	_timer.wait_time = 30.0
	_timer.timeout.connect(_tick)
	add_child(_timer)

	markets.changed.connect(func() -> void: _mark("markets"))
	news.changed.connect(func() -> void: _mark("news"))
	Weather.changed.connect(func() -> void: _mark("weather"))
	Library.changed.connect(func() -> void: _mark("cards"))
	Catalog.favorites_changed.connect(func() -> void: _mark("cards"))
	Catalog.apps_changed.connect(func() -> void: _mark("cards"))
	Settings.changed.connect(func(key: String, _v: Variant) -> void:
		match key:
			"market_symbols":
				_mark("markets")
				if _active:
					markets.refresh(true)
			"news_topic":
				_mark("news")
				if _active:
					news.refresh()
			"weather_unit":
				_mark("weather")
	)
	App.accent_changed.connect(func(_c: Color) -> void:
		_cal_day = ""
		_mark("calendar")
		_mark("news")
	)


## Called as the section scrolls into view (true) or fully out of it (false).
## Work only happens while it's active; changes made meanwhile wait for it.
func set_active(on: bool) -> void:
	if on == _active:
		return
	_active = on
	if on:
		_timer.start()
		_flush()
		_tick()
	else:
		_timer.stop()
		if _market_edit_box.visible:
			_close_market_edit()


func _mark(what: String) -> void:
	_dirty[what] = true
	if _active:
		_flush.call_deferred()


func _flush() -> void:
	if not _active:
		return
	if _dirty.get("cards", false):
		_fill_cards()
	if _dirty.get("markets", false):
		_fill_markets()
	if _dirty.get("news", false):
		_fill_news()
	if _dirty.get("weather", false):
		_fill_weather()
	if _dirty.get("calendar", false):
		_fill_calendar()
	_dirty.clear()
	_layout()


func _tick() -> void:
	markets.refresh()
	news.refresh()
	var today := Time.get_date_string_from_system()
	if today != _cal_day:
		_fill_calendar()
		_layout()
	# The "2h ago" times keep moving.
	if _news_list.get_child_count() > 0 and Time.get_ticks_msec() - int(_news_list.get_meta("at", 0)) > 120000:
		_fill_news()


# --- Shared pieces -------------------------------------------------------------------------

func _panel() -> Array:
	var p := GlassPanel.new(false, RADIUS, GlassPanel.TINT_WIDGET)
	p.set_shadow_strength(0.22, 26, 10.0)
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(p)
	var rim := Panel.new()
	rim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rim.add_theme_stylebox_override("panel", Kit.box(Color(0, 0, 0, 0), int(RADIUS), Color(1, 1, 1, 0.07), 1))
	p.add_child(rim)
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right"]:
		m.add_theme_constant_override("margin_" + side, int(PAD))
	m.add_theme_constant_override("margin_top", 18)
	m.add_theme_constant_override("margin_bottom", 16)
	p.add_child(m)
	var col := Kit.vbox(12)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(col)
	var head := Kit.hbox(10)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.custom_minimum_size.y = 30
	col.add_child(head)
	return [p, col, head]


func _title(text: String) -> Label:
	var l := Kit.label(text, 16, 700, App.TEXT, true)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return l


func _quiet(text: String) -> Label:
	var l := Kit.label(text, 13, 500, App.TEXT_MUTE)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return l


## A flat, full-width row that lights up faintly under the pointer.
func _row_button(tip: String = "") -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.tooltip_text = tip
	b.add_theme_stylebox_override("normal", Kit.empty())
	b.add_theme_stylebox_override("hover", Kit.box(Color(1, 1, 1, 0.05), 12))
	b.add_theme_stylebox_override("pressed", Kit.box(Color(1, 1, 1, 0.08), 12))
	b.add_theme_stylebox_override("hover_pressed", Kit.box(Color(1, 1, 1, 0.08), 12))
	return b


static func _clear(c: Node) -> void:
	for k in c.get_children():
		c.remove_child(k)
		k.queue_free()


static func open_link(url: String) -> void:
	if url == "":
		return
	if Browser.handles_links():
		Browser.open(url)
	else:
		OS.shell_open(url)


# --- Ten covers ------------------------------------------------------------------------------

## The most played favourites, best first; topped up with the most played of
## the rest of the Library when there are fewer than ten favourites.
static func top_refs(n: int = CARDS) -> Array[String]:
	var favs := Catalog.favorites()
	var scored := []
	for i in favs.size():
		var ref: String = favs[i]
		var e := Library.get_entry(ref.substr(4)) if ref.begins_with("lib:") else {}
		if ref.begins_with("lib:") and e.is_empty():
			continue
		scored.append([ref, int(e.get("playtime", 0)), int(e.get("launches", 0)), i])
	scored.sort_custom(func(a: Array, b: Array) -> bool:
		if a[1] != b[1]:
			return a[1] > b[1]
		if a[2] != b[2]:
			return a[2] > b[2]
		return a[3] < b[3]
	)
	var out: Array[String] = []
	for s in scored.slice(0, n):
		out.append(str(s[0]))
	if out.size() < n:
		var rest: Array[Dictionary] = []
		for e in Library.entries:
			if not out.has("lib:" + str(e["id"])) and (int(e["playtime"]) > 0 or int(e["launches"]) > 0 or e["kind"] == "game"):
				rest.append(e)
		rest.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if int(a["playtime"]) != int(b["playtime"]):
				return int(a["playtime"]) > int(b["playtime"])
			return int(a["last_played"]) > int(b["last_played"])
		)
		for e in rest:
			if out.size() >= n:
				break
			out.append("lib:" + str(e["id"]))
	return out


func _fill_cards() -> void:
	var refs := top_refs()
	var sig := ",".join(refs)
	if sig == _cards_sig and _cards.get_child_count() == refs.size():
		return
	_cards_sig = sig
	_clear(_cards)
	for ref in refs:
		_cards.add_child(_card(ref))


func _card(ref: String) -> Control:
	var it := Catalog.item(ref)
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_STOP
	holder.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	holder.tooltip_text = str(it["name"])
	var inner := Control.new()
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.add_child(inner)
	var cover := CoverArt.new()
	cover.glow_enabled = false
	cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inner.add_child(cover)
	var entry := str(it.get("entry_id", ""))
	if entry != "":
		cover.setup(entry, 14.0)
	else:
		_plate(cover, it)
	holder.mouse_entered.connect(func() -> void:
		inner.pivot_offset = Vector2(holder.size.x * 0.5, holder.size.y)
		var t := Kit.hover_tween(inner).set_parallel(true).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
		t.tween_property(inner, "scale", Vector2.ONE * 1.03, 0.22)
		t.tween_property(inner, "position:y", -4.0, 0.22)
		t.tween_property(cover, "focus_amount", 1.0, 0.18)
		Sfx.play(&"move", 1.15)
	)
	holder.mouse_exited.connect(func() -> void:
		var t := Kit.hover_tween(inner).set_parallel(true).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		t.tween_property(inner, "scale", Vector2.ONE, 0.3)
		t.tween_property(inner, "position:y", 0.0, 0.3)
		t.tween_property(cover, "focus_amount", 0.0, 0.2)
	)
	holder.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed:
			if ev.button_index == MOUSE_BUTTON_LEFT:
				Sfx.play(&"select")
				Catalog.launch(ref)
			elif ev.button_index == MOUSE_BUTTON_RIGHT and main:
				main.show_ref_menu(ref, holder.get_global_mouse_position())
	)
	return holder


## Apps outside the Library: Oazy's own art for well-known apps, otherwise
## the app's icon on a plate tinted to match, with its name under it.
func _plate(cover: CoverArt, it: Dictionary) -> void:
	var name := str(it["name"])
	var brand := Art.brand_art(name, &"cover")
	cover.preview(name, brand)
	if brand != "":
		return
	var ic := AppIcon.new()
	ic.set_item(it)
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cover.add_child(ic)
	var l := Kit.label(name, 13, 600, Color(1, 1, 1, 0.9))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cover.add_child(l)
	var place := func() -> void:
		var s := roundf(clampf(cover.size.x * 0.42, 24.0, 80.0))
		ic.size = Vector2(s, s)
		ic.position = Vector2((cover.size.x - s) * 0.5, cover.size.y * 0.42 - s * 0.5).round()
		l.size = Vector2(cover.size.x - 16.0, 20.0)
		l.position = Vector2(8.0, ic.position.y + s + 12.0)
		# The plate's own initials sit under the icon; hide them.
		for c in cover.get_children():
			if c is Label and c != l:
				c.visible = false
	cover.resized.connect(place)
	place.call_deferred()


# --- Markets -----------------------------------------------------------------------------------

func _build_markets() -> void:
	var parts := _panel()
	_market_panel = parts[0]
	var col: VBoxContainer = parts[1]
	var head: HBoxContainer = parts[2]
	head.add_child(_title("Markets"))
	head.add_child(Kit.spacer(0, 0, true))
	var status := Kit.hbox(6)
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status.visible = false
	head.add_child(status)
	var dot := Panel.new()
	dot.custom_minimum_size = Vector2(6, 6)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dot.add_theme_stylebox_override("panel", Kit.box(Color.WHITE, 3))
	status.add_child(dot)
	_market_status = Kit.label("", 12, 600, App.TEXT_MUTE)
	_market_status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	status.add_child(_market_status)
	status.add_child(Kit.spacer(4, 0))
	_market_edit_btn = FxButton.icon_only("edit", "Choose what to follow", 14, 28)
	_market_edit_btn.variant = FxButton.Style.PLAIN
	_market_edit_btn._apply_style()
	_market_edit_btn.pressed.connect(_open_market_edit)
	head.add_child(_market_edit_btn)

	_market_rows = Kit.vbox(0)
	_market_rows.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_market_rows)

	_market_edit_box = Kit.vbox(10)
	_market_edit_box.visible = false
	col.add_child(_market_edit_box)
	_market_edit = LineEdit.new()
	_market_edit.placeholder_text = "AAPL, NVDA, ^GSPC, BTC-USD"
	_market_edit.custom_minimum_size.y = 42
	_market_edit.add_theme_font_size_override("font_size", 15)
	_market_edit.text_submitted.connect(func(_t: String) -> void: _save_market_edit())
	_market_edit.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventKey and ev.pressed and ev.keycode == KEY_ESCAPE:
			_close_market_edit()
			_market_edit.accept_event()
	)
	_market_edit_box.add_child(_market_edit)
	var hint := Kit.label("Up to eight Yahoo Finance symbols, separated by commas: stocks (MSFT), indices (^GSPC, ^STOXX50E), crypto (BTC-USD), currencies (EURUSD=X).", 12, 500, App.TEXT_MUTE)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_market_edit_box.add_child(hint)
	var buttons := Kit.hbox(8)
	_market_edit_box.add_child(buttons)
	var save := FxButton.make("Save", "check", FxButton.Style.PRIMARY, 36)
	save.pressed.connect(_save_market_edit)
	buttons.add_child(save)
	var cancel := FxButton.make("Cancel", "", FxButton.Style.GHOST, 36)
	cancel.pressed.connect(_close_market_edit)
	buttons.add_child(cancel)


func _open_market_edit() -> void:
	_market_edit.text = ", ".join(Markets.symbols())
	_market_rows.visible = false
	_market_edit_box.visible = true
	_market_edit_btn.visible = false
	_market_edit.grab_focus()
	_market_edit.caret_column = _market_edit.text.length()


func _save_market_edit() -> void:
	var list := Markets.parse_symbols(_market_edit.text)
	_close_market_edit()
	if not list.is_empty():
		Settings.set_value("market_symbols", Array(list))


func _close_market_edit() -> void:
	_market_edit.release_focus()
	_market_edit_box.visible = false
	_market_rows.visible = true
	_market_edit_btn.visible = true


func _fill_markets() -> void:
	_clear(_market_rows)
	var shown := 0
	var lead_open: Variant = null
	for s in Markets.symbols():
		var q: Dictionary = markets.quotes.get(s, {})
		if q.is_empty():
			continue
		if shown == 0:
			# The first one you follow leads, with the day drawn out in full.
			_market_rows.add_child(_market_lead(s, q))
			lead_open = Markets.is_open(q)
		else:
			_market_rows.add_child(_hairline())
			_market_rows.add_child(_market_row(s, q))
		shown += 1
	if shown == 0:
		var l := _quiet("Fetching prices…" if markets.busy or not markets.offline else "Markets are out of reach right now.")
		l.size_flags_vertical = Control.SIZE_EXPAND_FILL
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_market_rows.add_child(l)
	if markets.offline and shown > 0:
		_set_market_status("Offline", App.TEXT_MUTE)
	elif lead_open == null:
		_set_market_status("", App.TEXT_MUTE)
	else:
		_set_market_status("Open" if lead_open else "Closed", UP if lead_open else App.TEXT_MUTE)


func _set_market_status(text: String, dot: Color) -> void:
	_market_status.text = text
	_market_status.get_parent().visible = text != ""
	(_market_status.get_parent().get_child(0) as Control).modulate = dot


## Prices in tabular figures, so digits line up and don't shuffle as they tick.
static func _num_font(weight: int) -> Font:
	var key := "num%d" % weight
	if not _num_fonts.has(key):
		var v := FontVariation.new()
		v.base_font = Kit.font(weight)
		v.opentype_features = {TextServerManager.get_primary_interface().name_to_tag("tnum"): 1}
		_num_fonts[key] = v
	return _num_fonts[key]


static func _num(text: String, px: int, weight: int, color: Color) -> Label:
	var l := Kit.label(text, px, weight, color)
	l.add_theme_font_override("font", _num_font(weight))
	return l


static func _change_text(change: float, pct: float) -> String:
	return "%s%.2f%%" % ["+" if change >= 0.0 else "−", absf(pct)]


func _quote_parts(sym: String, q: Dictionary) -> Dictionary:
	var price := float(q["price"])
	var prev := float(q["prev"])
	var change := price - prev
	var friendly := Markets.label_for(sym)
	return {
		"price": price, "prev": prev, "change": change,
		"pct": change / prev * 100.0 if prev != 0.0 else 0.0,
		"tone": UP if change >= 0.0 else DOWN,
		"name": friendly,
		# Under the name: the company for a ticker, the ticker for a nickname.
		"sub": (str(q.get("name", "")) if friendly == sym else sym),
		# Indices are points, not money.
		"text": Markets.format_price(price, "" if sym.begins_with("^") else str(q.get("currency", ""))),
	}


func _quote_button(sym: String, q: Dictionary) -> Button:
	var name := str(q.get("name", ""))
	var b := _row_button((name + " · " if name != "" else "") + "Open on Yahoo Finance")
	b.pressed.connect(func() -> void: open_link("https://finance.yahoo.com/quote/" + sym.uri_encode()))
	return b


func _market_lead(sym: String, q: Dictionary) -> Control:
	var p := _quote_parts(sym, q)
	var b := _quote_button(sym, q)
	b.custom_minimum_size.y = 168
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right"]:
		m.add_theme_constant_override("margin_" + side, 8)
	m.add_theme_constant_override("margin_top", 4)
	m.add_theme_constant_override("margin_bottom", 12)
	b.add_child(m)
	var col := Kit.vbox(2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(col)
	var names := Kit.hbox(8)
	names.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(names)
	names.add_child(Kit.label(str(p["name"]), 14, 600, App.TEXT_DIM))
	var sub := Kit.label(str(p["sub"]), 12, 500, App.TEXT_MUTE)
	sub.clip_text = true
	sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sub.size_flags_vertical = Control.SIZE_SHRINK_END
	names.add_child(sub)
	var figures := Kit.hbox(12)
	figures.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(figures)
	var big := _num(str(p["text"]), 30, 600, App.TEXT)
	figures.add_child(big)
	var tone: Color = p["tone"]
	var delta := _num(_change_text(p["change"], p["pct"]), 14, 600, tone)
	delta.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	figures.add_child(delta)
	var points := _num(("+" if float(p["change"]) >= 0.0 else "−") + Markets.format_price(absf(p["change"])), 14, 500, Color(tone, 0.7))
	points.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	figures.add_child(points)
	var line := Sparkline.new()
	line.width = 1.8
	line.fill = 0.2
	line.smooth = 1
	line.size_flags_vertical = Control.SIZE_EXPAND_FILL
	line.custom_minimum_size.y = 64
	line.set_data(q.get("points", []), p["prev"], tone)
	col.add_child(Kit.spacer(0, 6))
	col.add_child(line)
	return b


func _hairline() -> Control:
	var h := ColorRect.new()
	h.color = Color(1, 1, 1, 0.055)
	h.custom_minimum_size.y = 1
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return h


func _market_row(sym: String, q: Dictionary) -> Control:
	var p := _quote_parts(sym, q)
	var tone: Color = p["tone"]
	var b := _quote_button(sym, q)
	b.size_flags_vertical = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size.y = 52
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_theme_constant_override("margin_left", 8)
	m.add_theme_constant_override("margin_right", 8)
	b.add_child(m)
	var row := Kit.hbox(14)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(row)
	var names := Kit.vbox(2)
	names.alignment = BoxContainer.ALIGNMENT_CENTER
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.size_flags_stretch_ratio = 1.15
	names.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(names)
	for spec in [[p["name"], 14, 600, App.TEXT], [p["sub"], 12, 500, App.TEXT_MUTE]]:
		var l := Kit.label(str(spec[0]), spec[1], spec[2], spec[3])
		l.clip_text = true
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		l.custom_minimum_size.x = 60
		names.add_child(l)
	var line := Sparkline.new()
	line.width = 1.4
	line.fill = 0.13
	line.smooth = 2
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.size_flags_vertical = Control.SIZE_EXPAND_FILL
	line.custom_minimum_size = Vector2(56, 26)
	line.set_data(q.get("points", []), p["prev"], tone)
	var line_box := MarginContainer.new()
	line_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line_box.add_theme_constant_override("margin_top", 12)
	line_box.add_theme_constant_override("margin_bottom", 12)
	line_box.add_child(line)
	row.add_child(line_box)
	var nums := Kit.vbox(4)
	nums.alignment = BoxContainer.ALIGNMENT_CENTER
	nums.custom_minimum_size.x = 96
	nums.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(nums)
	var price := _num(str(p["text"]), 14, 600, App.TEXT)
	price.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	nums.add_child(price)
	var chip := _num(_change_text(p["change"], p["pct"]), 12, 600, tone)
	chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chip.custom_minimum_size.x = 66
	chip.add_theme_stylebox_override("normal", Kit.box(Color(tone, 0.1), 6, Color(0, 0, 0, 0), 0, 0, 1))
	chip.size_flags_horizontal = Control.SIZE_SHRINK_END
	nums.add_child(chip)
	return b


# --- News ----------------------------------------------------------------------------------------

func _build_news() -> void:
	var parts := _panel()
	_news_panel = parts[0]
	var col: VBoxContainer = parts[1]
	var head: HBoxContainer = parts[2]
	head.add_child(_title("News"))
	_news_status = _quiet("")
	head.add_child(_news_status)
	head.add_child(Kit.spacer(0, 0, true))
	_news_tabs = Kit.hbox(2)
	_news_tabs.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(_news_tabs)
	for id in News.TOPICS:
		var t := Button.new()
		t.text = str(News.TOPICS[id][0])
		t.focus_mode = Control.FOCUS_NONE
		t.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		t.set_meta("topic", id)
		t.add_theme_font_override("font", Kit.font(600))
		t.add_theme_font_size_override("font_size", 13)
		t.add_theme_stylebox_override("normal", Kit.empty(10, 4))
		t.add_theme_stylebox_override("hover", Kit.box(Color(1, 1, 1, 0.06), 999, Color(0, 0, 0, 0), 0, 10, 4))
		t.add_theme_stylebox_override("pressed", Kit.box(Color(1, 1, 1, 0.1), 999, Color(0, 0, 0, 0), 0, 10, 4))
		t.add_theme_stylebox_override("hover_pressed", Kit.box(Color(1, 1, 1, 0.1), 999, Color(0, 0, 0, 0), 0, 10, 4))
		t.pressed.connect(func() -> void:
			Sfx.play(&"move", 1.1)
			Settings.set_value("news_topic", id)
		)
		_news_tabs.add_child(t)
	_news_list = Kit.vbox(0)
	_news_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_news_list.clip_contents = true
	col.add_child(_news_list)


func _sync_tabs() -> void:
	var now := News.topic()
	for t in _news_tabs.get_children():
		var on := str(t.get_meta("topic")) == now
		var c := App.TEXT if on else App.TEXT_DIM
		t.add_theme_color_override("font_color", c)
		t.add_theme_color_override("font_hover_color", App.TEXT)
		t.add_theme_stylebox_override("normal", Kit.box(Color(1, 1, 1, 0.1), 999, Color(0, 0, 0, 0), 0, 10, 4) if on else Kit.empty(10, 4))


func _fill_news() -> void:
	_sync_tabs()
	_clear(_news_list)
	_news_list.set_meta("at", Time.get_ticks_msec())
	var list := news.items()
	_news_status.text = ""
	if list.is_empty():
		var l := _quiet("Fetching headlines…" if news.busy or not news.feeds.has(News.topic()) else "Headlines are out of reach right now.")
		l.size_flags_vertical = Control.SIZE_EXPAND_FILL
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_news_list.add_child(l)
		return
	var room := _news_room()
	var used := 0.0
	for i in list.size():
		var it: Dictionary = list[i]
		var lead := i == 0
		var h := 92.0 if lead else 66.0
		if i > 0 and used + h > room:
			break
		if i > 0:
			_news_list.add_child(_hairline())
		_news_list.add_child(_news_row(it, lead, h))
		used += h + 1.0


## Height available for headlines inside the panel.
func _news_room() -> float:
	return maxf(120.0, _news_panel.size.y - 18.0 - 16.0 - 30.0 - 12.0)


func _news_row(it: Dictionary, lead: bool, h: float) -> Control:
	var b := _row_button(str(it["title"]))
	b.custom_minimum_size.y = h
	b.pressed.connect(func() -> void: open_link(str(it["link"])))
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_theme_constant_override("margin_left", 10)
	m.add_theme_constant_override("margin_right", 10)
	b.add_child(m)
	var col := Kit.vbox(5)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(col)
	var meta := Kit.hbox(6)
	meta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(meta)
	var src := Kit.label(str(it["source"]).to_upper(), 11, 700, App.accent.lightened(0.25) if lead else App.TEXT_DIM)
	var sv := FontVariation.new()
	sv.base_font = Kit.font(700)
	sv.spacing_glyph = 1
	src.add_theme_font_override("font", sv)
	meta.add_child(src)
	if int(it["at"]) > 0:
		meta.add_child(Kit.label("·  " + _since(int(it["at"])), 11, 600, App.TEXT_MUTE))
	var t := Kit.label(str(it["title"]), 18 if lead else 15, 700 if lead else 600, App.TEXT)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.max_lines_visible = 2
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(t)
	return b


static func _since(unix: int) -> String:
	var d := maxi(0, int(Time.get_unix_time_from_system()) - unix)
	if d < 3600:
		return "%dm ago" % maxi(1, d / 60)
	if d < 86400:
		return "%dh ago" % (d / 3600)
	return "%dd ago" % (d / 86400)


# --- Weather ---------------------------------------------------------------------------------------

func _build_weather() -> void:
	var parts := _panel()
	_weather_panel = parts[0]
	var col: VBoxContainer = parts[1]
	var head: HBoxContainer = parts[2]
	head.get_parent().remove_child(head)
	head.queue_free()
	_weather_body = Kit.vbox(14)
	_weather_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_weather_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_weather_body)


func _fill_weather() -> void:
	_clear(_weather_body)
	var now := Weather.current()
	if now.is_empty():
		var l := _quiet("The forecast shows up once Oazy knows roughly where you are.")
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_vertical = Control.SIZE_EXPAND_FILL
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_weather_body.add_child(l)
		return
	var days := Weather.days()
	# Now: the temperature, the sky, where.
	var top := Kit.hbox(14)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_weather_body.add_child(top)
	var ic := WeatherIcons.rect(Weather.kind_for(int(now["code"])), bool(now["day"]), 52)
	ic.custom_minimum_size = Vector2(52, 52)
	top.add_child(ic)
	var big := Kit.label(Weather.temp(now["temp"]), 44, 500, App.TEXT, true)
	big.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(big)
	var words := Kit.vbox(2)
	words.alignment = BoxContainer.ALIGNMENT_CENTER
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(words)
	var place := Weather.city() if Weather.city() != "" else "Weather"
	var where := Kit.label(place, 15, 700, App.TEXT)
	where.clip_text = true
	where.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	words.add_child(where)
	var desc := Weather.describe(int(now["code"]))
	if not days.is_empty():
		desc += "  ·  H %s  L %s" % [Weather.temp(days[0]["max"]), Weather.temp(days[0]["min"])]
	words.add_child(Kit.label(desc, 13, 500, App.TEXT_DIM))

	# The next hours.
	var hours := Weather.hours(6, 2)
	if hours.size() >= 2:
		var strip := PanelContainer.new()
		strip.add_theme_stylebox_override("panel", Kit.box(Color(1, 1, 1, 0.04), 14, Color(1, 1, 1, 0.05), 1, 4, 10))
		_weather_body.add_child(strip)
		var row := Kit.hbox(0)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		strip.add_child(row)
		for i in hours.size():
			var h: Dictionary = hours[i]
			var c := Kit.vbox(4)
			c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			c.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(c)
			var t := Kit.label("Now" if i == 0 else str(h["time"]).substr(11, 5), 11, 600, App.TEXT if i == 0 else App.TEXT_MUTE)
			t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			c.add_child(t)
			var hi := WeatherIcons.rect(Weather.kind_for(int(h["code"])), bool(h["day"]), 26)
			hi.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			c.add_child(hi)
			var tl := Kit.label(Weather.temp(h["temp"]), 13, 700, App.TEXT)
			tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			c.add_child(tl)

	# The days ahead, as many as fit.
	if days.size() > 1:
		var room := _weather_panel.size.y - 18.0 - 16.0 - 52.0 - 14.0 - 76.0 - 14.0
		var fit := clampi(floori(room / 30.0), 0, days.size() - 1)
		var lo := INF
		var hi := -INF
		for d in days.slice(0, fit + 1):
			lo = minf(lo, float(d["min"]))
			hi = maxf(hi, float(d["max"]))
		var list := Kit.vbox(0)
		list.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_weather_body.add_child(list)
		for i in range(1, fit + 1):
			var d: Dictionary = days[i]
			var r := Kit.hbox(10)
			r.custom_minimum_size.y = 30
			r.mouse_filter = Control.MOUSE_FILTER_IGNORE
			list.add_child(r)
			var dn := Kit.label("Tomorrow" if i == 1 else WeatherFlyout._weekday(str(d["date"])), 13, 600, App.TEXT)
			dn.custom_minimum_size.x = 74
			dn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			r.add_child(dn)
			var di := WeatherIcons.rect(Weather.kind_for(int(d["code"])), true, 22)
			di.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			r.add_child(di)
			var low := Kit.label(Weather.temp(d["min"]), 13, 600, App.TEXT_DIM)
			low.custom_minimum_size.x = 36
			low.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			low.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			r.add_child(low)
			var bar := WeatherFlyout.TempBar.new()
			bar.setup(lo, hi, float(d["min"]), float(d["max"]), NAN)
			bar.custom_minimum_size.x = 40
			bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			r.add_child(bar)
			var high := Kit.label(Weather.temp(d["max"]), 13, 700, App.TEXT)
			high.custom_minimum_size.x = 36
			high.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			high.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			r.add_child(high)


# --- Calendar ------------------------------------------------------------------------------------------

func _build_calendar() -> void:
	var parts := _panel()
	_cal_panel = parts[0]
	var col: VBoxContainer = parts[1]
	var head: HBoxContainer = parts[2]
	head.get_parent().remove_child(head)
	head.queue_free()
	_cal_body = Kit.vbox(8)
	_cal_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cal_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_cal_body)


func _fill_calendar() -> void:
	_cal_day = Time.get_date_string_from_system()
	_clear(_cal_body)
	var now := Time.get_datetime_dict_from_system()
	var year := int(now["year"])
	var mon := int(now["month"])
	var head := Kit.hbox(8)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cal_body.add_child(head)
	head.add_child(_title(MONTHS[mon - 1]))
	head.add_child(Kit.spacer(0, 0, true))
	head.add_child(_quiet(str(year)))
	var lead := CalendarFlyout.first_weekday(year, mon)
	var count := CalendarFlyout.days_in_month(year, mon)
	var weeks := ceili((lead + count) / 7.0)
	var room := _cal_panel.size.y - 18.0 - 16.0 - 30.0 - 8.0
	var cell_h := clampf(floorf(room / float(weeks + 1)), 18.0, 30.0)
	var grid := GridContainer.new()
	grid.columns = 7
	grid.add_theme_constant_override("h_separation", 0)
	grid.add_theme_constant_override("v_separation", 0)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cal_body.add_child(grid)
	for d in CalendarFlyout.DAYS:
		var l := Kit.label(d.substr(0, 2), 11, 600, App.TEXT_MUTE)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.custom_minimum_size.y = cell_h
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(l)
	for i in lead:
		var s := Kit.spacer(0, cell_h)
		s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(s)
	var dot := minf(cell_h - 2.0, 28.0)
	for day in range(1, count + 1):
		var today := day == int(now["day"])
		var cell := CenterContainer.new()
		cell.custom_minimum_size.y = cell_h
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		grid.add_child(cell)
		var past := day < int(now["day"])
		var weekend := (lead + day - 1) % 7 >= 5
		var col := App.TEXT_MUTE if past else (App.TEXT_DIM if weekend else App.TEXT)
		var l := Kit.label(str(day), 13, 700 if today else 500, Color.WHITE if today else col)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.custom_minimum_size = Vector2(dot, dot)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if today:
			l.add_theme_stylebox_override("normal", Kit.box(App.accent.darkened(0.15), 999))
		cell.add_child(l)


# --- Layout --------------------------------------------------------------------------------------------

## Lays the section out for a `w` × `h` screen (the space above the taskbar).
func layout_for(w: float, h: float, left: float) -> void:
	set_meta("w", w)
	set_meta("h", h)
	set_meta("left", left)
	_layout()


func _layout() -> void:
	if not has_meta("w"):
		return
	var w: float = get_meta("w")
	var h: float = get_meta("h")
	var left: float = get_meta("left")
	var top := 56.0
	var inner_w := w - left * 2.0
	# Ten covers across the full width.
	var cw := floorf((inner_w - CARD_GAP * (CARDS - 1)) / CARDS)
	var card := Vector2(cw, roundf(cw * 1.5))
	var n := _cards.get_child_count()
	_cards.position = Vector2(left, top)
	_cards.size = Vector2(inner_w, card.y)
	for i in n:
		var c := _cards.get_child(i) as Control
		c.position = Vector2(i * (cw + CARD_GAP), 0)
		c.size = card
	var y := top + (card.y + 34.0 if n > 0 else 0.0)
	var panel_h := maxf(360.0, h - y - 34.0)
	var side := clampf(inner_w * 0.27, 320.0, 440.0)
	var mid := inner_w - side * 2.0 - PANEL_GAP * 2.0
	_market_panel.position = Vector2(left, y)
	_market_panel.size = Vector2(side, panel_h)
	_news_panel.position = Vector2(left + side + PANEL_GAP, y)
	_news_panel.size = Vector2(mid, panel_h)
	var rx := left + side + mid + PANEL_GAP * 2.0
	var cal_h := clampf(roundf(panel_h * 0.4), 196.0, 250.0)
	var wh := panel_h - cal_h - PANEL_GAP
	var resized_w := not is_equal_approx(_weather_panel.size.y, wh) or not is_equal_approx(_cal_panel.size.y, cal_h) or not is_equal_approx(_news_panel.size.y, panel_h)
	_weather_panel.position = Vector2(rx, y)
	_weather_panel.size = Vector2(side, wh)
	_cal_panel.position = Vector2(rx, y + wh + PANEL_GAP)
	_cal_panel.size = Vector2(side, cal_h)
	wanted_height = y + panel_h + 34.0
	if resized_w and _active:
		# What fits depends on the panels' heights.
		_fill_news()
		_fill_weather()
		_fill_calendar()


## The panels and cards that make up this section, for the intro and fades.
func parts() -> Array[Control]:
	return [_cards, _market_panel, _news_panel, _weather_panel, _cal_panel]
