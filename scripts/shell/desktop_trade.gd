class_name DesktopTrade
extends Control
## The desktop's third screen, two scrolls down: a trading desk on Hyperliquid.
## A row of the coins you follow, then the chart, the order book and the latest
## trades for the one you picked, and your open positions with their P&L along
## the bottom. View-only for now (see HlExchange).
##
## Prices and positions keep updating in the background, so they're current
## the moment you arrive; the book, trades and live candles only stream while
## this screen is in view. Nothing on screen is touched while it's parked.

const UP := DesktopBelow.UP
const DOWN := DesktopBelow.DOWN
const GAP := 22.0
const STRIP_H := 86.0
const TICKER_MAX_W := 300.0
## A position's row in the table.
const ROW_H := 46.0
const INTERVAL_LABELS := {"5m": "5m", "15m": "15m", "1h": "1H", "4h": "4H", "1d": "1D"}
## Coins Hyperliquid people know by colour.
const COIN_COLORS := {
	"BTC": "f7931a", "ETH": "8a9cf0", "SOL": "a77bf3", "HYPE": "97fce4", "XRP": "b8c4cc",
	"DOGE": "d8b44a", "BNB": "f0b90b", "AVAX": "e84142", "LINK": "4f7bf0", "SUI": "6fbcf0",
}
## Column widths in the positions table (stretch ratios), and their names.
const POS_COLS := [["Coin", 1.5], ["Size", 1.15], ["Value", 1.0], ["Entry", 0.9], ["Price", 0.9], ["Liq. price", 0.9], ["Margin", 0.85], ["P&L (ROE)", 1.25]]

var main: Node
var hl: Hyperliquid
## The height this screen wants (it may be taller than one screen).
var wanted_height := 0.0

var _active := false
var _dirty := {"prices": true, "market": true, "account": true, "coins": true}
var _timer: Timer

var _strip: Control
var _tickers := {}
var _strip_side: HBoxContainer
var _status_dot: Panel
var _status: Label
var _coins_btn: FxButton
var _coins_box: HBoxContainer
var _coins_edit: LineEdit

var _chart_panel: GlassPanel
var _badge: Control
var _coin_name: Label
var _coin_sub: Label
var _big_price: Label
var _big_change: Label
var _stats: HBoxContainer
var _intervals: HBoxContainer
var _chart: CandleChart

var _book_panel: GlassPanel
var _book: OrderBookView
var _trades_panel: GlassPanel
var _tape: TradeTape

var _pos_panel: GlassPanel
var _pos_count: Label
var _summary: HBoxContainer
var _sum_labels := {}
var _addr_btn: Button
var _pos_body: VBoxContainer
var _pos_rows: VBoxContainer
var _pos_more: Label
var _pos_sig := ""
var _pos_live := []
var _addr_box: VBoxContainer
var _addr_edit: LineEdit
var _addr_note: Label
var _editing_addr := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	hl = Hyperliquid.new()
	add_child(hl)
	_build_strip()
	_build_chart()
	_build_book()
	_build_trades()
	_build_positions()

	# Four looks a second is plenty for the eye, however fast the feed is.
	_timer = Timer.new()
	_timer.wait_time = 0.25
	_timer.timeout.connect(_flush)
	add_child(_timer)

	hl.prices_changed.connect(func() -> void: _dirty["prices"] = true)
	hl.market_changed.connect(func() -> void: _dirty["market"] = true)
	hl.account_changed.connect(func() -> void: _dirty["account"] = true)
	hl.status_changed.connect(func() -> void: _dirty["prices"] = true)
	Settings.changed.connect(func(key: String, _v: Variant) -> void:
		match key:
			"hl_coins", "hl_coin":
				_dirty["coins"] = true
				_dirty["market"] = true
			"hl_interval":
				_dirty["market"] = true
			"hl_address":
				_editing_addr = false
				_pos_sig = "-"
				_dirty["account"] = true
		if _active and key.begins_with("hl_"):
			_flush.call_deferred()
	)
	App.accent_changed.connect(func(_c: Color) -> void: _dirty["coins"] = true)
	# Prices and your positions tick along from the start.
	hl.start()


## Called as this screen scrolls into view (true) or fully out of it (false).
func set_active(on: bool) -> void:
	if on == _active:
		return
	_active = on
	hl.set_focus(on)
	if on:
		_timer.start()
		_flush()
	else:
		_timer.stop()
		if _coins_box.visible:
			_close_coins_edit()


func _flush() -> void:
	if not _active:
		return
	var relayout := false
	if _dirty.get("coins", false):
		_fill_tickers()
		_sync_intervals()
		relayout = true
	if _dirty.get("prices", false) or _dirty.get("coins", false):
		_update_tickers()
		_update_header()
		_update_live_pnl()
	if _dirty.get("market", false) or _dirty.get("coins", false):
		_update_market()
	if _dirty.get("account", false):
		_fill_positions()
		relayout = true
	_dirty.clear()
	if relayout:
		_layout()


# --- Shared pieces ------------------------------------------------------------------------------

func _panel() -> Array:
	return DesktopBelow.glass_panel(self)


static func _quiet(text: String, px: int = 13) -> Label:
	var l := Kit.label(text, px, 500, App.TEXT_MUTE)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return l


static func _tone(v: float) -> Color:
	return UP if v >= 0.0 else DOWN


static func _pct(v: float) -> String:
	return "%s%.2f%%" % ["+" if v >= 0.0 else "−", absf(v)]


## A round coin badge: the coin's colour with its first letter.
static func coin_badge(c: String, px: float) -> Control:
	var col := Color(COIN_COLORS[c]) if COIN_COLORS.has(c) else Kit.cover_colors(c)[0].lightened(0.15)
	var dot := Panel.new()
	dot.custom_minimum_size = Vector2(px, px)
	dot.size = Vector2(px, px)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dot.add_theme_stylebox_override("panel", Kit.box(Color(col, 0.95), int(px)))
	var letter := c.trim_prefix("k").substr(0, 1).to_upper()
	var l := Kit.label(letter, int(px * 0.46), 700, Color(0.04, 0.06, 0.08) if col.get_luminance() > 0.55 else Color.WHITE)
	l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	dot.add_child(l)
	return dot


func _tab_style(b: Button, on: bool) -> void:
	b.add_theme_color_override("font_color", App.TEXT if on else App.TEXT_DIM)
	b.add_theme_color_override("font_hover_color", App.TEXT)
	b.add_theme_stylebox_override("normal", Kit.box(Color(1, 1, 1, 0.1), 999, Color(0, 0, 0, 0), 0, 11, 4) if on else Kit.empty(11, 4))


func _tab(text: String) -> Button:
	var t := Button.new()
	t.text = text
	t.focus_mode = Control.FOCUS_NONE
	t.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	t.add_theme_font_override("font", Kit.font(600))
	t.add_theme_font_size_override("font_size", 13)
	t.add_theme_stylebox_override("normal", Kit.empty(11, 4))
	t.add_theme_stylebox_override("hover", Kit.box(Color(1, 1, 1, 0.06), 999, Color(0, 0, 0, 0), 0, 11, 4))
	t.add_theme_stylebox_override("pressed", Kit.box(Color(1, 1, 1, 0.1), 999, Color(0, 0, 0, 0), 0, 11, 4))
	t.add_theme_stylebox_override("hover_pressed", Kit.box(Color(1, 1, 1, 0.1), 999, Color(0, 0, 0, 0), 0, 11, 4))
	return t


# --- The coins you follow -------------------------------------------------------------------------

func _build_strip() -> void:
	_strip = Control.new()
	_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_strip)
	_strip_side = Kit.hbox(10)
	_strip_side.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_strip_side)
	_status_dot = Panel.new()
	_status_dot.custom_minimum_size = Vector2(7, 7)
	_status_dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_status_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_dot.add_theme_stylebox_override("panel", Kit.box(Color.WHITE, 4))
	_strip_side.add_child(_status_dot)
	_status = Kit.label("", 13, 600, App.TEXT_DIM)
	_status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_strip_side.add_child(_status)
	var view := _quiet("·  View only", 13)
	view.tooltip_text = "Prices and your positions, straight from Hyperliquid. Trading comes later."
	view.mouse_filter = Control.MOUSE_FILTER_PASS
	_strip_side.add_child(view)
	_coins_btn = FxButton.icon_only("edit", "Choose your coins", 14, 30)
	_coins_btn.variant = FxButton.Style.PLAIN
	_coins_btn._apply_style()
	_coins_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_coins_btn.pressed.connect(_open_coins_edit)
	_strip_side.add_child(_coins_btn)

	_coins_box = Kit.hbox(10)
	_coins_box.visible = false
	add_child(_coins_box)
	_coins_edit = LineEdit.new()
	_coins_edit.placeholder_text = "BTC, ETH, SOL, HYPE"
	_coins_edit.custom_minimum_size = Vector2(420, 42)
	_coins_edit.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_coins_edit.add_theme_font_size_override("font_size", 15)
	_coins_edit.text_submitted.connect(func(_t: String) -> void: _save_coins_edit())
	_coins_edit.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventKey and ev.pressed and ev.keycode == KEY_ESCAPE:
			_close_coins_edit()
			_coins_edit.accept_event()
	)
	_coins_box.add_child(_coins_edit)
	var save := FxButton.make("Save", "check", FxButton.Style.PRIMARY, 38)
	save.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	save.pressed.connect(_save_coins_edit)
	_coins_box.add_child(save)
	var cancel := FxButton.make("Cancel", "", FxButton.Style.GHOST, 38)
	cancel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cancel.pressed.connect(_close_coins_edit)
	_coins_box.add_child(cancel)
	var hint := _quiet("Up to eight Hyperliquid perps, separated by commas.", 12)
	_coins_box.add_child(hint)


func _open_coins_edit() -> void:
	_coins_edit.text = ", ".join(Hyperliquid.coins())
	_strip.visible = false
	_strip_side.visible = false
	_coins_box.visible = true
	_coins_edit.grab_focus()
	_coins_edit.caret_column = _coins_edit.text.length()


func _save_coins_edit() -> void:
	var list := hl.parse_coins(_coins_edit.text)
	_close_coins_edit()
	if list.is_empty():
		return
	Settings.set_value("hl_coins", Array(list))
	if not list.has(Hyperliquid.coin()):
		Settings.set_value("hl_coin", list[0])


func _close_coins_edit() -> void:
	_coins_edit.release_focus()
	_coins_box.visible = false
	_strip.visible = true
	_strip_side.visible = true


func _fill_tickers() -> void:
	DesktopBelow._clear(_strip)
	_tickers.clear()
	for c in Hyperliquid.coins():
		_strip.add_child(_ticker(c))


func _ticker(c: String) -> Control:
	var on := c == Hyperliquid.coin()
	var card := GlassPanel.new(false, 18.0, GlassPanel.TINT_WIDGET)
	card.set_shadow_strength(0.16, 20, 8.0)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.tooltip_text = "%s perpetual" % c
	var wash := Panel.new()
	wash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wash.add_theme_stylebox_override("panel", Kit.box(Color(1, 1, 1, 0.075 if on else 0.0), 18, Color(1, 1, 1, 0.12 if on else 0.06), 1))
	card.add_child(wash)
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right"]:
		m.add_theme_constant_override("margin_" + side, 16)
	m.add_theme_constant_override("margin_top", 14)
	m.add_theme_constant_override("margin_bottom", 12)
	card.add_child(m)
	var col := Kit.vbox(6)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(col)
	var top := Kit.hbox(9)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(top)
	top.add_child(coin_badge(c, 24))
	var name := Kit.label(c, 15, 700, App.TEXT if on else App.TEXT_DIM)
	name.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(name)
	top.add_child(Kit.spacer(0, 0, true))
	var price := DesktopBelow._num("—", 16, 600, App.TEXT)
	price.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(price)
	var bottom := Kit.hbox(10)
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(bottom)
	var spark := Sparkline.new()
	spark.width = 1.4
	spark.fill = 0.14
	spark.smooth = 1
	spark.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spark.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spark.custom_minimum_size = Vector2(40, 22)
	bottom.add_child(spark)
	var change := DesktopBelow._num("", 13, 600, App.TEXT_MUTE)
	change.size_flags_vertical = Control.SIZE_SHRINK_END
	change.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	change.custom_minimum_size.x = 64
	bottom.add_child(change)
	card.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			if c != Hyperliquid.coin():
				Sfx.play(&"move", 1.1)
				Settings.set_value("hl_coin", c)
	)
	card.mouse_entered.connect(func() -> void:
		if c != Hyperliquid.coin():
			wash.add_theme_stylebox_override("panel", Kit.box(Color(1, 1, 1, 0.04), 18, Color(1, 1, 1, 0.09), 1))
	)
	card.mouse_exited.connect(func() -> void:
		var now_on := c == Hyperliquid.coin()
		wash.add_theme_stylebox_override("panel", Kit.box(Color(1, 1, 1, 0.075 if now_on else 0.0), 18, Color(1, 1, 1, 0.12 if now_on else 0.06), 1))
	)
	_tickers[c] = {"card": card, "price": price, "change": change, "spark": spark, "sig": ""}
	return card


func _update_tickers() -> void:
	for c in _tickers:
		var t: Dictionary = _tickers[c]
		var p := hl.price(c)
		(t["price"] as Label).text = Hyperliquid.fmt_px(p) if p > 0.0 else "—"
		var ch := hl.change_pct(c)
		var chl: Label = t["change"]
		chl.text = _pct(ch) if hl.prev(c) > 0.0 else ""
		chl.add_theme_color_override("font_color", _tone(ch))
		var pts: Array = hl.sparks.get(c, [])
		if not pts.is_empty():
			# The day's line ends at the live price.
			var line := pts.duplicate()
			if p > 0.0:
				line[line.size() - 1] = p
			var sig := "%d:%s" % [line.size(), str(line[line.size() - 1])]
			if sig != t["sig"]:
				t["sig"] = sig
				(t["spark"] as Sparkline).set_data(line, float(pts[0]), _tone(ch))
	var ok := hl.live
	_status.text = "Live" if ok else "Connecting…"
	_status_dot.modulate = UP if ok else App.TEXT_MUTE


# --- Chart ----------------------------------------------------------------------------------------

func _build_chart() -> void:
	var parts := _panel()
	_chart_panel = parts[0]
	var col: VBoxContainer = parts[1]
	var head: HBoxContainer = parts[2]
	col.add_theme_constant_override("separation", 10)
	head.custom_minimum_size.y = 44
	head.add_theme_constant_override("separation", 12)
	_badge = Control.new()
	_badge.custom_minimum_size = Vector2(36, 36)
	_badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(_badge)
	var names := Kit.vbox(0)
	names.alignment = BoxContainer.ALIGNMENT_CENTER
	names.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(names)
	_coin_name = Kit.label("", 19, 700, App.TEXT, true)
	names.add_child(_coin_name)
	_coin_sub = Kit.label("", 12, 500, App.TEXT_MUTE)
	names.add_child(_coin_sub)
	head.add_child(Kit.spacer(10, 0))
	_big_price = DesktopBelow._num("—", 30, 600, App.TEXT)
	_big_price.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_big_price)
	_big_change = DesktopBelow._num("", 13, 600, UP)
	_big_change.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_big_change.custom_minimum_size.x = 74
	_big_change.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_child(_big_change)
	head.add_child(Kit.spacer(0, 0, true))
	_intervals = Kit.hbox(2)
	_intervals.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_intervals.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_intervals)
	for id in INTERVAL_LABELS:
		var t := _tab(INTERVAL_LABELS[id])
		t.set_meta("interval", id)
		t.pressed.connect(func() -> void:
			Sfx.play(&"move", 1.1)
			Settings.set_value("hl_interval", id)
		)
		_intervals.add_child(t)

	_stats = Kit.hbox(28)
	_stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_stats)
	for spec in [["mark", "Mark"], ["oracle", "Oracle"], ["vol", "24h volume"], ["oi", "Open interest"], ["funding", "Funding / 1h"]]:
		var s := Kit.vbox(2)
		s.mouse_filter = Control.MOUSE_FILTER_IGNORE
		s.add_child(Kit.label(spec[1], 11, 600, App.TEXT_MUTE))
		var v := DesktopBelow._num("—", 14, 600, App.TEXT_DIM)
		s.add_child(v)
		s.set_meta("value", v)
		s.name = spec[0]
		_stats.add_child(s)

	col.add_child(Kit.spacer(0, 2))
	_chart = CandleChart.new()
	_chart.up = UP
	_chart.down = DOWN
	_chart.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_chart.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(_chart)


func _sync_intervals() -> void:
	for t in _intervals.get_children():
		_tab_style(t as Button, str(t.get_meta("interval")) == Hyperliquid.interval())


func _update_header() -> void:
	var c := Hyperliquid.coin()
	if _coin_name.text != c:
		_coin_name.text = c
		DesktopBelow._clear(_badge)
		_badge.add_child(coin_badge(c, 36))
	var lev := int((hl.meta.get(c, {}) as Dictionary).get("lev", 0))
	_coin_sub.text = "%s-USD perpetual" % c + ("  ·  up to %d×" % lev if lev > 0 else "")
	var p := hl.price(c)
	_big_price.text = Hyperliquid.fmt_px(p) if p > 0.0 else "—"
	var ch := hl.change_pct(c)
	_big_change.visible = hl.prev(c) > 0.0
	_big_change.text = _pct(ch)
	_big_change.add_theme_color_override("font_color", _tone(ch))
	_big_change.add_theme_stylebox_override("normal", Kit.box(Color(_tone(ch), 0.12), 8, Color(0, 0, 0, 0), 0, 8, 3))
	var x: Dictionary = hl.ctxs.get(c, {})
	_stat("mark", Hyperliquid.fmt_px(float(x["mark"])) if float(x.get("mark", 0)) > 0.0 else "—")
	_stat("oracle", Hyperliquid.fmt_px(float(x["oracle"])) if float(x.get("oracle", 0)) > 0.0 else "—")
	_stat("vol", Hyperliquid.fmt_usd_short(float(x["vol"])) if x.has("vol") else "—")
	_stat("oi", Hyperliquid.fmt_usd_short(float(x["oi"]) * p) if x.has("oi") and p > 0.0 else "—")
	if x.has("funding"):
		var fr := float(x["funding"]) * 100.0
		_stat("funding", "%s%.4f%%" % ["+" if fr >= 0.0 else "−", absf(fr)], _tone(fr))
	else:
		_stat("funding", "—")


func _stat(id: String, text: String, color: Color = App.TEXT_DIM) -> void:
	var l: Label = _stats.get_node(id).get_meta("value")
	l.text = text
	l.add_theme_color_override("font_color", color)


# --- Book and trades --------------------------------------------------------------------------------

func _build_book() -> void:
	var parts := _panel()
	_book_panel = parts[0]
	var head: HBoxContainer = parts[2]
	head.add_child(_panel_title("Order book"))
	_book = OrderBookView.new()
	_book.up = UP
	_book.down = DOWN
	_book.size_flags_vertical = Control.SIZE_EXPAND_FILL
	(parts[1] as VBoxContainer).add_child(_book)


func _build_trades() -> void:
	var parts := _panel()
	_trades_panel = parts[0]
	var head: HBoxContainer = parts[2]
	head.add_child(_panel_title("Trades"))
	_tape = TradeTape.new()
	_tape.up = UP
	_tape.down = DOWN
	_tape.size_flags_vertical = Control.SIZE_EXPAND_FILL
	(parts[1] as VBoxContainer).add_child(_tape)


static func _panel_title(text: String) -> Label:
	var l := Kit.label(text, 16, 700, App.TEXT, true)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return l


func _update_market() -> void:
	var c := Hyperliquid.coin()
	var dec := hl.sz_decimals(c)
	_chart.set_rows(hl.candles, int(Hyperliquid.INTERVALS[Hyperliquid.interval()]))
	_book.last_dir = 0 if hl.trades.is_empty() else (1 if str(hl.trades[0]["side"]) == "B" else -1)
	_book.set_book(hl.book, dec, c)
	_tape.set_trades(hl.trades, dec, c)
	_update_header()


# --- Positions -----------------------------------------------------------------------------------

func _build_positions() -> void:
	var parts := _panel()
	_pos_panel = parts[0]
	var col: VBoxContainer = parts[1]
	var head: HBoxContainer = parts[2]
	head.custom_minimum_size.y = 40
	head.add_child(_panel_title("Positions"))
	_pos_count = _quiet("")
	head.add_child(_pos_count)
	head.add_child(Kit.spacer(0, 0, true))
	_summary = Kit.hbox(30)
	_summary.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(_summary)
	for spec in [["value", "Account value"], ["upnl", "Unrealised P&L"], ["margin", "Margin used"], ["free", "Withdrawable"]]:
		var s := Kit.vbox(1)
		s.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var k := Kit.label(spec[1], 11, 600, App.TEXT_MUTE)
		k.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		s.add_child(k)
		var v := DesktopBelow._num("—", 16, 600, App.TEXT)
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		s.add_child(v)
		_summary.add_child(s)
		_sum_labels[spec[0]] = v
	_summary.add_child(Kit.spacer(2, 0))
	_addr_btn = Button.new()
	_addr_btn.focus_mode = Control.FOCUS_NONE
	_addr_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_addr_btn.tooltip_text = "Change the wallet you're watching"
	_addr_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_addr_btn.icon = Icons.tex("edit", 13, App.TEXT_MUTE)
	_addr_btn.add_theme_font_override("font", DesktopBelow._num_font(600))
	_addr_btn.add_theme_font_size_override("font_size", 12)
	_addr_btn.add_theme_color_override("font_color", App.TEXT_DIM)
	_addr_btn.add_theme_color_override("font_hover_color", App.TEXT)
	_addr_btn.add_theme_constant_override("h_separation", 6)
	_addr_btn.add_theme_stylebox_override("normal", Kit.box(Color(1, 1, 1, 0.05), 999, Color(1, 1, 1, 0.06), 1, 11, 5))
	_addr_btn.add_theme_stylebox_override("hover", Kit.box(Color(1, 1, 1, 0.09), 999, Color(1, 1, 1, 0.1), 1, 11, 5))
	_addr_btn.add_theme_stylebox_override("pressed", Kit.box(Color(1, 1, 1, 0.12), 999, Color(1, 1, 1, 0.1), 1, 11, 5))
	_addr_btn.pressed.connect(func() -> void:
		_editing_addr = true
		_pos_sig = "-"
		_fill_positions()
		_layout()
	)
	head.add_child(_addr_btn)

	_pos_body = Kit.vbox(0)
	_pos_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_pos_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_pos_body)
	_build_address_box()


func _build_address_box() -> void:
	_addr_box = Kit.vbox(10)
	_addr_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_addr_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_addr_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t := Kit.label("See your positions and P&L", 17, 700, App.TEXT, true)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_addr_box.add_child(t)
	var d := Kit.label("Paste your Hyperliquid wallet address. It's public, like an account number: Oazy only reads it, and never needs a key or a seed phrase.", 13, 500, App.TEXT_MUTE)
	d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size.x = 560
	d.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_addr_box.add_child(d)
	var row := Kit.hbox(8)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_addr_box.add_child(row)
	_addr_edit = LineEdit.new()
	_addr_edit.placeholder_text = "0x…"
	_addr_edit.custom_minimum_size = Vector2(500, 42)
	_addr_edit.add_theme_font_size_override("font_size", 15)
	_addr_edit.add_theme_font_override("font", DesktopBelow._num_font(500))
	_addr_edit.text_submitted.connect(func(_t: String) -> void: _save_address())
	_addr_edit.text_changed.connect(func(_t: String) -> void: _check_address(false))
	_addr_edit.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventKey and ev.pressed and ev.keycode == KEY_ESCAPE and Hyperliquid.address() != "":
			_editing_addr = false
			_pos_sig = "-"
			_fill_positions()
			_layout()
			_addr_edit.accept_event()
	)
	row.add_child(_addr_edit)
	var save := FxButton.make("Watch", "eye", FxButton.Style.PRIMARY, 42)
	save.pressed.connect(_save_address)
	row.add_child(save)
	_addr_note = Kit.label("", 12, 600, DOWN)
	_addr_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_addr_box.add_child(_addr_note)


## Checks what's typed. A private key (64 hex digits) is wiped on sight.
func _check_address(submit: bool) -> bool:
	var t := _addr_edit.text.strip_edges()
	var hex := t.trim_prefix("0x")
	if hex.length() == 64 and hex.is_valid_hex_number():
		_addr_edit.text = ""
		_addr_note.text = "That looks like a private key, so Oazy wiped it. Never paste a key anywhere: only your public address (0x and 40 characters)."
		return false
	if Hyperliquid.is_address(t):
		_addr_note.text = ""
		return true
	_addr_note.text = "A wallet address is 0x followed by 40 letters and digits." if submit or t.length() >= 42 else ""
	return false


func _save_address() -> void:
	if not _check_address(true):
		return
	Sfx.play(&"select")
	_addr_edit.release_focus()
	_editing_addr = false
	_pos_sig = "-"
	Settings.set_value("hl_address", _addr_edit.text.strip_edges().to_lower())


func _fill_positions() -> void:
	var addr := Hyperliquid.address()
	var acct := hl.account
	var asking := addr == "" or _editing_addr
	_summary.visible = not asking and not acct.is_empty()
	_addr_btn.visible = not asking
	_addr_btn.text = Hyperliquid.short_address(addr)
	var positions: Array = acct.get("positions", [])
	_pos_count.text = str(positions.size()) if not asking and positions.size() > 0 else ""
	var sig := "ask" if asking else ("wait" if acct.is_empty() else ",".join(positions.map(func(p: Dictionary) -> String: return "%s:%s" % [p["coin"], p["szi"]])))
	if sig != _pos_sig:
		_pos_sig = sig
		if _addr_box.get_parent():
			_addr_box.get_parent().remove_child(_addr_box)
		DesktopBelow._clear(_pos_body)
		_pos_live.clear()
		_pos_rows = null
		if asking:
			_pos_body.add_child(_addr_box)
			_addr_edit.text = addr
			_addr_note.text = ""
		elif acct.is_empty():
			_pos_body.add_child(_centered("Looking up %s…" % Hyperliquid.short_address(addr)))
		elif positions.is_empty():
			_pos_body.add_child(_centered("No open positions right now."))
		else:
			_build_table(positions)
	_update_live_pnl()


func _centered(text: String) -> Label:
	var l := _quiet(text, 14)
	l.size_flags_vertical = Control.SIZE_EXPAND_FILL
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


func _cells(parent: HBoxContainer) -> Array:
	var out := []
	for i in POS_COLS.size():
		var l := DesktopBelow._num("", 14, 500, App.TEXT_DIM)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.size_flags_stretch_ratio = POS_COLS[i][1]
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if i == 0 else HORIZONTAL_ALIGNMENT_RIGHT
		l.clip_text = true
		parent.add_child(l)
		out.append(l)
	return out


func _build_table(positions: Array) -> void:
	var head := Kit.hbox(16)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.custom_minimum_size.y = 26
	var head_m := MarginContainer.new()
	head_m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right"]:
		head_m.add_theme_constant_override("margin_" + side, 10)
	head_m.add_child(head)
	_pos_body.add_child(head_m)
	var hc := _cells(head)
	for i in hc.size():
		(hc[i] as Label).text = POS_COLS[i][0]
		(hc[i] as Label).add_theme_font_size_override("font_size", 11)
		(hc[i] as Label).add_theme_font_override("font", DesktopBelow._num_font(600))
		(hc[i] as Label).add_theme_color_override("font_color", App.TEXT_MUTE)
	_pos_rows = Kit.vbox(0)
	_pos_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pos_rows.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_pos_body.add_child(_pos_rows)
	for p in positions:
		var line := ColorRect.new()
		line.color = Color(1, 1, 1, 0.055)
		line.custom_minimum_size.y = 1
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_pos_rows.add_child(line)
		_pos_rows.add_child(_position_row(p))
	_pos_more = _quiet("", 12)
	_pos_more.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pos_more.custom_minimum_size.y = 22
	_pos_rows.add_child(_pos_more)
	_fit_rows()


## Shows the biggest positions that fit, and says how many more there are.
func _fit_rows() -> void:
	if _pos_rows == null or not is_instance_valid(_pos_rows):
		return
	var room := _pos_panel.size.y - 18.0 - 16.0 - 40.0 - 12.0 - 26.0
	var total := (_pos_rows.get_child_count() - 1) / 2
	var fit := clampi(floori(room / (ROW_H + 1.0)), 1, total)
	if fit < total:
		fit = clampi(floori((room - 22.0) / (ROW_H + 1.0)), 1, total)
	for i in total:
		_pos_rows.get_child(i * 2).visible = i < fit
		_pos_rows.get_child(i * 2 + 1).visible = i < fit
	_pos_more.visible = fit < total
	_pos_more.text = "+%d smaller position%s" % [total - fit, "" if total - fit == 1 else "s"]


func _position_row(p: Dictionary) -> Control:
	var c := str(p["coin"])
	var long := float(p["szi"]) > 0.0
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.tooltip_text = "Show %s on the chart" % c
	b.custom_minimum_size.y = ROW_H
	b.add_theme_stylebox_override("normal", Kit.empty())
	b.add_theme_stylebox_override("hover", Kit.box(Color(1, 1, 1, 0.045), 12))
	b.add_theme_stylebox_override("pressed", Kit.box(Color(1, 1, 1, 0.07), 12))
	b.add_theme_stylebox_override("hover_pressed", Kit.box(Color(1, 1, 1, 0.07), 12))
	b.pressed.connect(func() -> void:
		if c != Hyperliquid.coin():
			Sfx.play(&"move", 1.1)
			if not Hyperliquid.coins().has(c):
				var list := Array(Hyperliquid.coins())
				list.append(c)
				Settings.set_value("hl_coins", list.slice(maxi(0, list.size() - 8)))
			Settings.set_value("hl_coin", c)
	)
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right"]:
		m.add_theme_constant_override("margin_" + side, 10)
	b.add_child(m)
	var row := Kit.hbox(16)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(row)
	var cells := _cells(row)
	# The coin cell: badge, name, and a Long / Short chip with the leverage.
	var first: Label = cells[0]
	var coin_box := Kit.hbox(10)
	coin_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	coin_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	coin_box.size_flags_stretch_ratio = POS_COLS[0][1]
	row.add_child(coin_box)
	row.move_child(coin_box, 0)
	first.queue_free()
	coin_box.add_child(coin_badge(c, 26))
	var nm := Kit.label(c, 15, 700, App.TEXT)
	nm.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	coin_box.add_child(nm)
	var tone := UP if long else DOWN
	var chip := Kit.label("%s %d×" % ["Long" if long else "Short", int(p["lev"])], 11, 700, tone)
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.add_theme_stylebox_override("normal", Kit.box(Color(tone, 0.12), 7, Color(0, 0, 0, 0), 0, 7, 2))
	chip.tooltip_text = "Cross margin" if bool(p["cross"]) else "Isolated margin"
	chip.mouse_filter = Control.MOUSE_FILTER_PASS
	coin_box.add_child(chip)
	var dec := hl.sz_decimals(c)
	(cells[1] as Label).text = Hyperliquid.fmt_sz(absf(float(p["szi"])), dec) + " " + c
	(cells[1] as Label).add_theme_color_override("font_color", App.TEXT)
	(cells[3] as Label).text = Hyperliquid.fmt_px(float(p["entry"]))
	(cells[5] as Label).text = Hyperliquid.fmt_px(float(p["liq"])) if float(p["liq"]) > 0.0 else "—"
	(cells[5] as Label).add_theme_color_override("font_color", Color(DOWN, 0.8) if float(p["liq"]) > 0.0 else App.TEXT_MUTE)
	(cells[6] as Label).text = Hyperliquid.fmt_usd(float(p["margin"]))
	(cells[7] as Label).add_theme_font_override("font", DesktopBelow._num_font(600))
	_pos_live.append({"p": p, "value": cells[2], "price": cells[4], "pnl": cells[7]})
	return b


## Marks every position, and the account, at the live price.
func _update_live_pnl() -> void:
	var acct := hl.account
	if acct.is_empty():
		return
	var total := 0.0
	for p in acct["positions"]:
		total += hl.live_pnl(p)
	for r in _pos_live:
		var p: Dictionary = r["p"]
		var c := str(p["coin"])
		var px := hl.price(c)
		var pnl := hl.live_pnl(p)
		(r["value"] as Label).text = Hyperliquid.fmt_usd(absf(float(p["szi"])) * px)
		(r["price"] as Label).text = Hyperliquid.fmt_px(px)
		var margin := float(p["margin"])
		var pl: Label = r["pnl"]
		pl.text = Hyperliquid.fmt_usd(pnl, true) + ("  (%s)" % _pct(pnl / margin * 100.0) if margin > 0.0 else "")
		pl.add_theme_color_override("font_color", _tone(pnl))
	var value := hl.live_value()
	(_sum_labels["value"] as Label).text = Hyperliquid.fmt_usd(value)
	var up_l: Label = _sum_labels["upnl"]
	up_l.text = Hyperliquid.fmt_usd(total, true)
	up_l.add_theme_color_override("font_color", _tone(total))
	var used := float(acct["margin"])
	(_sum_labels["margin"] as Label).text = Hyperliquid.fmt_usd(used) + ("  ·  %d%%" % roundi(used / value * 100.0) if value > 0.0 else "")
	(_sum_labels["free"] as Label).text = Hyperliquid.fmt_usd(float(acct["withdrawable"]))


# --- Layout ----------------------------------------------------------------------------------------

## Lays the screen out for a `w` × `h` screen (the space above the taskbar).
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
	var inner := w - left * 2.0

	# The coins, left to right, with the feed's status at the end.
	var side_w := _strip_side.get_combined_minimum_size().x
	_strip_side.size = Vector2(side_w, STRIP_H)
	_strip_side.position = Vector2(w - left - side_w, top)
	var n := _strip.get_child_count()
	var room := inner - side_w - GAP
	var cw := minf(TICKER_MAX_W, floorf((room - 14.0 * (n - 1)) / maxf(n, 1)))
	_strip.position = Vector2(left, top)
	_strip.size = Vector2(room, STRIP_H)
	for i in n:
		var c := _strip.get_child(i) as Control
		c.position = Vector2(i * (cw + 14.0), 0)
		c.size = Vector2(cw, STRIP_H)
	_coins_box.position = Vector2(left, top + (STRIP_H - 42.0) * 0.5)
	_coins_box.size = Vector2(inner, 42.0)

	# Chart, book and trades side by side; positions underneath.
	var y := top + STRIP_H + GAP
	var pos_h := clampf(roundf(h * 0.25), 236.0, 330.0)
	var main_h := maxf(400.0, h - y - GAP - pos_h - 34.0)
	var book_w := clampf(roundf(inner * 0.165), 300.0, 400.0)
	var trades_w := clampf(roundf(inner * 0.135), 260.0, 330.0)
	var chart_w := inner - book_w - trades_w - GAP * 2.0
	_chart_panel.position = Vector2(left, y)
	_chart_panel.size = Vector2(chart_w, main_h)
	_book_panel.position = Vector2(left + chart_w + GAP, y)
	_book_panel.size = Vector2(book_w, main_h)
	_trades_panel.position = Vector2(left + chart_w + book_w + GAP * 2.0, y)
	_trades_panel.size = Vector2(trades_w, main_h)
	_pos_panel.position = Vector2(left, y + main_h + GAP)
	_pos_panel.size = Vector2(inner, pos_h)
	_fit_rows()
	wanted_height = y + main_h + GAP + pos_h + 34.0


## The panels and cards that make up this screen, for fades.
func parts() -> Array[Control]:
	var out: Array[Control] = [_chart_panel, _book_panel, _trades_panel, _pos_panel]
	for c in _strip.get_children():
		out.append(c as Control)
	return out
