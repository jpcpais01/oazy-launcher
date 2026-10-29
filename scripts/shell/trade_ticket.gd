class_name TradeTicket
extends VBoxContainer
## The order ticket on the trading desk. Until trading is set up it walks you
## through it (a trading key made on this PC, approved on Hyperliquid); after
## that it's a buy / sell form behind an Armed switch. Nothing is sent without
## the confirm step.

const UP := DesktopBelow.UP
const DOWN := DesktopBelow.DOWN
const ARMED := Color("ffb547")
const INK := Color(0.03, 0.05, 0.07)

var hl: Hyperliquid
var ex: HlExchange
var main: Node

var _arm_box: HBoxContainer
var _arm_label: Label
var _arm: ToggleSwitch
var _setup: VBoxContainer
var _setup_sig := ""
var _form: VBoxContainer
var _side: Array = []
var _types: Array = []
var _usd: LineEdit
var _px: LineEdit
var _px_box: VBoxContainer
var _lev: HSlider
var _lev_label: Label
var _reduce: CheckBox
var _tpsl: CheckBox
var _tpsl_box: HBoxContainer
var _tp: LineEdit
var _sl: LineEdit
var _avail: Label
var _quick: HBoxContainer
var _est: Label
var _note: Label
var _go: Button
var _foot: HBoxContainer
var _foot_label: Label
var _buy := true
var _market := true
var _coin := ""
var _sending := false


func setup(h: Hyperliquid, e: HlExchange, m: Node) -> void:
	hl = h
	ex = e
	main = m


func _ready() -> void:
	add_theme_constant_override("separation", 12)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var head := Kit.hbox(10)
	head.custom_minimum_size.y = 30
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(head)
	head.add_child(DesktopTrade._panel_title("Trade"))
	head.add_child(Kit.spacer(0, 0, true))
	_arm_box = Kit.hbox(8)
	_arm_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(_arm_box)
	_arm_label = Kit.label("Off", 13, 700, App.TEXT_MUTE)
	_arm_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_arm_box.add_child(_arm_label)
	_arm = ToggleSwitch.new()
	_arm.tooltip_text = "Armed: orders can be sent (after you confirm each one). Turns itself off when you leave the page or after five idle minutes."
	_arm.toggled.connect(func(on: bool) -> void:
		if on:
			ex.arm()
		else:
			ex.disarm()
		_sync()
	)
	_arm_box.add_child(_arm)

	_setup = Kit.vbox(10)
	_setup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_setup.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_setup)
	_build_form()
	ex.changed.connect(_sync)
	# The market list can land after the ticket is built; pick up the real cap.
	hl.prices_changed.connect(func() -> void:
		var top := int((hl.meta.get(_coin, {}) as Dictionary).get("lev", 0))
		if top > 0 and top != int(_lev.max_value):
			_on_coin()
	)
	Settings.changed.connect(func(key: String, _v: Variant) -> void:
		if key == "hl_coin":
			_on_coin()
		elif key == "hl_address":
			_sync()
	)
	_on_coin()
	_sync()


# --- Pieces -----------------------------------------------------------------------------------

static func _text(t: String, px: int = 13, color: Color = App.TEXT_DIM) -> Label:
	var l := Kit.label(t, px, 500, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 120
	return l


static func _link(t: String) -> Button:
	var b := Button.new()
	b.text = t
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_override("font", Kit.font(600))
	b.add_theme_font_size_override("font_size", 12)
	b.add_theme_color_override("font_color", App.TEXT_MUTE)
	b.add_theme_color_override("font_hover_color", App.TEXT)
	for st in ["normal", "hover", "pressed", "hover_pressed"]:
		b.add_theme_stylebox_override(st, Kit.empty())
	return b


static func _field_label(t: String) -> Label:
	return Kit.label(t, 11, 600, App.TEXT_MUTE)


func _field(px_w: float, placeholder: String) -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	e.custom_minimum_size = Vector2(px_w, 40)
	e.add_theme_font_override("font", DesktopBelow._num_font(600))
	e.add_theme_font_size_override("font_size", 15)
	e.text_changed.connect(func(_t: String) -> void:
		ex.touch()
		refresh_quote()
	)
	return e


## Two or more buttons acting as one choice.
func _segment(labels: Array, on_pick: Callable) -> Array:
	var row := Kit.hbox(6)
	_form.add_child(row)
	var out := []
	for i in labels.size():
		var b := Button.new()
		b.text = labels[i]
		b.focus_mode = Control.FOCUS_NONE
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size.y = 36
		b.add_theme_font_override("font", Kit.font(700))
		b.add_theme_font_size_override("font_size", 14)
		b.pressed.connect(func() -> void:
			Sfx.play(&"move", 1.1)
			ex.touch()
			on_pick.call(i)
		)
		row.add_child(b)
		out.append(b)
	return out


static func _paint(b: Button, on: bool, tone: Color) -> void:
	var fill := Color(tone, 0.18) if on else Color(1, 1, 1, 0.04)
	var line := Color(tone, 0.35) if on else Color(1, 1, 1, 0.06)
	b.add_theme_stylebox_override("normal", Kit.box(fill, 12, line, 1))
	b.add_theme_stylebox_override("hover", Kit.box(Color(tone, 0.22) if on else Color(1, 1, 1, 0.08), 12, line, 1))
	b.add_theme_stylebox_override("pressed", Kit.box(Color(tone, 0.26), 12, line, 1))
	b.add_theme_stylebox_override("disabled", Kit.box(fill, 12, line, 1))
	b.add_theme_color_override("font_color", tone if on else App.TEXT_DIM)
	b.add_theme_color_override("font_hover_color", tone if on else App.TEXT)
	b.add_theme_color_override("font_disabled_color", Color(tone if on else App.TEXT_DIM, 0.6))


# --- The form ---------------------------------------------------------------------------------

func _build_form() -> void:
	_form = Kit.vbox(9)
	_form.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_form.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_form)
	_side = _segment(["Buy / Long", "Sell / Short"], func(i: int) -> void:
		_buy = i == 0
		_paint_choices()
		refresh_quote()
	)
	_types = _segment(["Market", "Limit"], func(i: int) -> void:
		_market = i == 0
		if not _market and _px.text.strip_edges() == "":
			_px.text = _px_text(hl.price(_coin))
		_paint_choices()
		refresh_quote()
	)

	var size_box := Kit.vbox(5)
	_form.add_child(size_box)
	var size_head := Kit.hbox(6)
	size_box.add_child(size_head)
	var sl_ := _field_label("Size (USD)")
	sl_.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_head.add_child(sl_)
	_avail = DesktopBelow._num("", 11, 600, App.TEXT_MUTE)
	_avail.tooltip_text = "Free to trade with, times your leverage, is what you can open."
	_avail.mouse_filter = Control.MOUSE_FILTER_PASS
	size_head.add_child(_avail)
	_usd = _field(120, "100")
	size_box.add_child(_usd)
	# Quick sizes: a share of what you can open at this leverage.
	var quick := Kit.hbox(5)
	_quick = quick
	size_box.add_child(quick)
	for pct in [0.1, 0.25, 0.5, 1.0]:
		var qb := _chip("Max" if pct == 1.0 else "%d%%" % roundi(pct * 100.0))
		qb.pressed.connect(func() -> void:
			var power := _buying_power()
			if power <= 0.0:
				return
			Sfx.play(&"move", 1.1)
			# A hair under, so fees and rounding never push it over.
			_usd.text = HlExchange.wire(floorf(power * pct * (0.98 if pct == 1.0 else 1.0)))
			ex.touch()
			refresh_quote()
		)
		quick.add_child(qb)

	_px_box = Kit.vbox(5)
	_form.add_child(_px_box)
	var px_head := Kit.hbox(6)
	_px_box.add_child(px_head)
	var pl := _field_label("Limit price")
	pl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	px_head.add_child(pl)
	var mid := _link("Use mid")
	mid.pressed.connect(func() -> void:
		_px.text = _px_text(hl.price(_coin))
		refresh_quote()
	)
	px_head.add_child(mid)
	_px = _field(120, "Price")
	_px_box.add_child(_px)

	var lev_box := Kit.vbox(4)
	_form.add_child(lev_box)
	var lev_head := Kit.hbox(6)
	lev_box.add_child(lev_head)
	var ll := _field_label("Leverage")
	ll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lev_head.add_child(ll)
	_lev_label = DesktopBelow._num("1×", 13, 700, App.TEXT)
	lev_head.add_child(_lev_label)
	_lev = HSlider.new()
	_lev.min_value = 1
	_lev.max_value = 10
	_lev.step = 1
	_lev.custom_minimum_size.y = 22
	_lev.focus_mode = Control.FOCUS_NONE
	_lev.value_changed.connect(func(v: float) -> void:
		_lev_label.text = "%d×" % int(v)
		ex.touch()
		refresh_quote()
	)
	lev_box.add_child(_lev)

	var opts := Kit.hbox(6)
	_form.add_child(opts)
	_tpsl = _check("TP / SL", "Add a take profit and a stop loss: market orders that close this position when the price gets there.")
	opts.add_child(_tpsl)
	_reduce = _check("Reduce only", "Can only shrink or close a position, never open or flip one.")
	opts.add_child(_reduce)
	_tpsl.toggled.connect(func(on: bool) -> void:
		_tpsl_box.visible = on and not _reduce.button_pressed
		if on and _tp.text == "" and _sl.text == "":
			_suggest_tpsl()
	)
	_reduce.toggled.connect(func(on: bool) -> void:
		_tpsl.disabled = on or not ex.armed
		_tpsl_box.visible = _tpsl.button_pressed and not on
	)
	_tpsl_box = Kit.hbox(8)
	_tpsl_box.visible = false
	_form.add_child(_tpsl_box)
	for spec in [["Take profit", "tp"], ["Stop loss", "sl"]]:
		var b := Kit.vbox(5)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_tpsl_box.add_child(b)
		b.add_child(_field_label(spec[0]))
		var e := _field(60, "Price")
		b.add_child(e)
		if spec[1] == "tp":
			_tp = e
		else:
			_sl = e

	_est = DesktopBelow._num("", 12, 500, App.TEXT_MUTE)
	_est.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_est.custom_minimum_size.x = 120
	_form.add_child(_est)
	# The send button sits at the bottom of the panel, under everything else.
	var push := Kit.spacer(0, 0)
	push.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_form.add_child(push)
	_go = Button.new()
	_go.focus_mode = Control.FOCUS_NONE
	_go.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_go.custom_minimum_size.y = 44
	_go.add_theme_font_override("font", Kit.font(700))
	_go.add_theme_font_size_override("font_size", 15)
	_go.pressed.connect(_review)
	_form.add_child(_go)
	_note = _text("", 12, DOWN)
	_form.add_child(_note)

	_foot = Kit.hbox(6)
	_foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_form.add_child(_foot)
	_foot_label = Kit.label("", 11, 500, App.TEXT_MUTE)
	_foot_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_foot_label.clip_text = true
	_foot_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_foot.add_child(_foot_label)
	var forget := _link("Remove key")
	forget.add_theme_font_size_override("font_size", 11)
	forget.pressed.connect(_confirm_forget)
	_foot.add_child(forget)
	_paint_choices()


func _check(text: String, tip: String) -> CheckBox:
	var c := CheckBox.new()
	c.text = text
	c.focus_mode = Control.FOCUS_NONE
	c.tooltip_text = tip
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.add_theme_font_override("font", Kit.font(600))
	c.add_theme_font_size_override("font_size", 13)
	c.toggled.connect(func(_on: bool) -> void:
		ex.touch()
		refresh_quote()
	)
	return c


func _chip(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size.y = 26
	b.add_theme_font_override("font", DesktopBelow._num_font(600))
	b.add_theme_font_size_override("font_size", 11)
	b.add_theme_color_override("font_color", App.TEXT_DIM)
	b.add_theme_color_override("font_hover_color", App.TEXT)
	b.add_theme_color_override("font_disabled_color", App.TEXT_MUTE)
	b.add_theme_stylebox_override("normal", Kit.box(Color(1, 1, 1, 0.04), 8, Color(1, 1, 1, 0.06), 1))
	b.add_theme_stylebox_override("hover", Kit.box(Color(1, 1, 1, 0.09), 8, Color(1, 1, 1, 0.1), 1))
	b.add_theme_stylebox_override("pressed", Kit.box(Color(1, 1, 1, 0.12), 8, Color(1, 1, 1, 0.1), 1))
	b.add_theme_stylebox_override("disabled", Kit.box(Color(1, 1, 1, 0.03), 8, Color(1, 1, 1, 0.04), 1))
	return b


## What you're free to trade with: the account's available money.
func _free() -> float:
	return float(hl.account.get("withdrawable", 0.0))


## The most you can open at the leverage picked.
func _buying_power() -> float:
	return _free() * int(_lev.value)


## A starting point when TP / SL is ticked: 2 % and 1 % of price either way.
func _suggest_tpsl() -> void:
	var ref := _ref_px()
	if ref <= 0.0:
		return
	var sign := 1.0 if _buy else -1.0
	_tp.text = _px_text(ref * (1.0 + 0.02 * sign))
	_sl.text = _px_text(ref * (1.0 - 0.01 * sign))
	refresh_quote()


func _ref_px() -> float:
	return hl.price(_coin) if _market else _px.text.replace(",", "").to_float()


## A price picked elsewhere (a level in the book): a limit order there.
func use_price(px: float) -> void:
	if px <= 0.0:
		return
	_market = false
	_px.text = _px_text(px)
	_paint_choices()
	refresh_quote()


func _px_text(v: float) -> String:
	return HlExchange.wire(HlExchange.round_px(v, hl.sz_decimals(_coin))) if v > 0.0 else ""


func _paint_choices() -> void:
	_paint(_side[0], _buy, UP)
	_paint(_side[1], not _buy, DOWN)
	_paint(_types[0], _market, App.TEXT)
	_paint(_types[1], not _market, App.TEXT)
	_px_box.visible = not _market


func _on_coin() -> void:
	_coin = Hyperliquid.coin()
	var m: Dictionary = hl.meta.get(_coin, {})
	var top := maxi(1, int(m.get("lev", 10)))
	_lev.max_value = top
	var now := ex.current_leverage(_coin)
	_lev.value = clampi(now if now > 0 else mini(5, top), 1, top)
	_lev_label.text = "%d×" % int(_lev.value)
	_px.text = ""
	_tp.text = ""
	_sl.text = ""
	if not _market:
		_px.text = _px_text(hl.price(_coin))
	if _tpsl.button_pressed:
		_suggest_tpsl()
	refresh_quote()


## The order the ticket describes, as HlExchange.quote() works it out.
func _ticket() -> Dictionary:
	return {"coin": _coin, "buy": _buy, "market": _market, "usd": _usd.text.replace(",", "").replace("$", "").to_float(),
		"px": _px.text.replace(",", "").to_float(), "lev": int(_lev.value), "reduce": _reduce.button_pressed,
		"tp": _tp.text.replace(",", "").to_float() if _tpsl_box.visible else 0.0,
		"sl": _sl.text.replace(",", "").to_float() if _tpsl_box.visible else 0.0}


func refresh_quote() -> void:
	if _go == null:
		return
	var name := Hyperliquid.display(_coin)
	var tone := UP if _buy else DOWN
	var q := ex.quote(_ticket()) if _usd.text.strip_edges() != "" else {}
	if q.has("error"):
		_est.text = ""
		_note.text = str(q["error"])
	else:
		_note.text = ""
		if q.is_empty():
			_est.text = "Up to %d× on %s." % [int(_lev.max_value), name]
		else:
			_est.text = "≈ %s %s  ·  margin %s\nFee ≈ %s" % [Hyperliquid.fmt_sz(float(q["sz"]), int(q["decimals"])), name,
				Hyperliquid.fmt_usd(float(q["margin"])), Hyperliquid.fmt_usd(float(q["fee"]))]
			if float(q["tp"]) > 0.0 or float(q["sl"]) > 0.0:
				var bits := [""]
				if float(q["tp"]) > 0.0:
					bits.append("TP %s" % Hyperliquid.fmt_usd(float(q["tp_pnl"]), true))
				if float(q["sl"]) > 0.0:
					bits.append("SL %s" % Hyperliquid.fmt_usd(float(q["sl_pnl"]), true))
				_est.text += "  ·  ".join(bits)
			if not bool(q["reduce"]) and _free() > 0.0 and float(q["margin"]) > _free():
				_note.text = "That needs more margin than you have free (%s)." % Hyperliquid.fmt_usd(_free())
	_avail.text = ("%s free" % Hyperliquid.fmt_usd(_free())) if not hl.account.is_empty() else ""
	_go.text = ("Review buy" if _buy else "Review sell") + " " + name
	if _sending:
		_go.text = "Sending…"
	var live := ex.armed and not q.is_empty() and not q.has("error") and not _sending
	_go.disabled = not live
	_go.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if live else Control.CURSOR_ARROW
	var a := 0.92 if live else 0.28
	_go.add_theme_stylebox_override("normal", Kit.box(Color(tone, a), 14))
	_go.add_theme_stylebox_override("hover", Kit.box(Color(tone.lightened(0.08), a), 14))
	_go.add_theme_stylebox_override("pressed", Kit.box(Color(tone.darkened(0.08), a), 14))
	_go.add_theme_stylebox_override("disabled", Kit.box(Color(tone, a), 14))
	for k in ["font_color", "font_hover_color", "font_pressed_color"]:
		_go.add_theme_color_override(k, INK)
	_go.add_theme_color_override("font_disabled_color", Color(INK, 0.7))
	if not ex.armed and ex.ready_to_trade():
		_note.text = "Arm trading (top right) to send orders."
		_note.add_theme_color_override("font_color", App.TEXT_MUTE)
	else:
		_note.add_theme_color_override("font_color", DOWN)
	_note.visible = _note.text != ""
	_est.visible = _est.text != ""


func _review() -> void:
	var q := ex.quote(_ticket())
	if q.has("error") or not ex.armed or main == null:
		return
	var name := Hyperliquid.display(str(q["coin"]))
	var tone := UP if bool(q["buy"]) else DOWN
	var d := OrderConfirm.new()
	d.title = "%s %s %s?" % ["Buy" if q["buy"] else "Sell", Hyperliquid.fmt_sz(float(q["sz"]), int(q["decimals"])), name]
	d.message = "This is a real order on Hyperliquid, with real money."
	d.tone = tone
	d.rows = [
		["Side", ("Buy / Long" if q["buy"] else "Sell / Short") + ("  ·  reduce only" if q["reduce"] else ""), tone],
		["Order", "Market (fills now, up to %d%% from the price)" % roundi(HlExchange.SLIPPAGE * 100.0) if q["market"] else "Limit at " + Hyperliquid.fmt_px(float(q["px"]))],
		["Size", "%s %s  ≈ %s" % [Hyperliquid.fmt_sz(float(q["sz"]), int(q["decimals"])), name, Hyperliquid.fmt_usd(float(q["notional"]))]],
		["Leverage", "%d×  %s" % [int(q["lev"]), "cross" if q["cross"] else "isolated"]],
		["Margin used", Hyperliquid.fmt_usd(float(q["margin"]))],
		["Fee (estimate)", Hyperliquid.fmt_usd(float(q["fee"]))],
	]
	if float(q["tp"]) > 0.0:
		d.rows.append(["Take profit", "%s  (%s)" % [Hyperliquid.fmt_px(float(q["tp"])), Hyperliquid.fmt_usd(float(q["tp_pnl"]), true)], UP])
	if float(q["sl"]) > 0.0:
		d.rows.append(["Stop loss", "%s  (%s)" % [Hyperliquid.fmt_px(float(q["sl"])), Hyperliquid.fmt_usd(float(q["sl_pnl"]), true)], DOWN])
	d.confirm_text = "%s %s" % ["Buy" if q["buy"] else "Sell", name]
	d.on_confirm = func() -> void: _submit(q)
	main.overlay_layer.add_child(d)


func _submit(q: Dictionary) -> void:
	_sending = true
	refresh_quote()
	var r := await ex.place(q)
	_sending = false
	refresh_quote()
	report(r, "Bought" if q["buy"] else "Sold", Hyperliquid.display(str(q["coin"])), int(q["decimals"]))


## A toast for an exchange answer.
static func report(r: Dictionary, verb: String, name: String, decimals: int) -> void:
	if not bool(r.get("ok", false)):
		App.toast("Hyperliquid said no: " + str(r.get("error", "unknown error")), &"error")
	elif r.has("filled"):
		App.toast("%s %s %s at %s" % [verb, Hyperliquid.fmt_sz(float(r["filled"]), decimals), name, Hyperliquid.fmt_px(float(r.get("avg", 0)))], &"success")
	elif r.get("resting", false):
		App.toast("Order placed on the book", &"success")
	else:
		App.toast("Done", &"success")


# --- Setup and state ------------------------------------------------------------------------------

func _sync() -> void:
	var state := "form"
	if not ex.supported():
		state = "unsupported"
	elif Hyperliquid.address() == "":
		state = "wallet"
	elif ex.agent == "":
		state = "key"
	elif not ex.approved:
		state = "approve"
	_arm_box.visible = state == "form"
	_arm.set_on(ex.armed)
	_arm_label.text = "Armed" if ex.armed else "Off"
	_arm_label.add_theme_color_override("font_color", ARMED if ex.armed else App.TEXT_MUTE)
	_form.visible = state == "form"
	_setup.visible = state != "form"
	var sig := state + ":" + ex.agent + ":" + str(ex.checked)
	if sig != _setup_sig:
		_setup_sig = sig
		DesktopBelow._clear(_setup)
		match state:
			"unsupported":
				_setup.add_child(_text("Trading runs through Oazy's Windows helper, which isn't running here."))
			"wallet":
				_build_wallet_step()
			"key":
				_build_key_step()
			"approve":
				_build_approve_step()
	var editable := ex.armed and not _sending
	for e in [_usd, _px, _tp, _sl]:
		(e as LineEdit).editable = editable
	_lev.editable = editable
	_reduce.disabled = not editable
	_tpsl.disabled = not editable or _reduce.button_pressed
	for qb in _quick.get_children():
		(qb as Button).disabled = not editable
	for b in _side + _types:
		(b as Button).disabled = not editable
	_form.modulate.a = 1.0 if ex.armed else 0.62
	_foot_label.text = "API wallet %s%s" % [Hyperliquid.short_address(ex.agent), (" · " + ex.approved_name) if ex.approved_name != "" else ""]
	refresh_quote()


## Step one: which account is yours. Same field as under Positions, here too.
func _build_wallet_step() -> void:
	_setup.add_child(Kit.label("Add your wallet", 15, 700, App.TEXT))
	_setup.add_child(_text("Paste the public address of the wallet you trade with on Hyperliquid (0x and 40 characters, shown at the top right of Hyperliquid's site). Never a private key or seed phrase."))
	var e := LineEdit.new()
	e.placeholder_text = "0x…"
	e.custom_minimum_size.y = 40
	e.add_theme_font_override("font", DesktopBelow._num_font(500))
	e.add_theme_font_size_override("font_size", 14)
	_setup.add_child(e)
	var note := _text("", 12, DOWN)
	_setup.add_child(note)
	var save := func() -> void:
		var t := e.text.strip_edges()
		var hex := t.trim_prefix("0x")
		if hex.length() == 64 and hex.is_valid_hex_number():
			e.text = ""
			note.text = "That looks like a private key, so Oazy wiped it. Only the public address goes here."
		elif Hyperliquid.is_address(t):
			Sfx.play(&"select")
			Settings.set_value("hl_address", t.to_lower())
		else:
			note.text = "A wallet address is 0x followed by 40 letters and digits."
	e.text_submitted.connect(func(_t: String) -> void: save.call())
	e.text_changed.connect(func(t: String) -> void:
		var hex := t.strip_edges().trim_prefix("0x")
		if hex.length() == 64 and hex.is_valid_hex_number():
			save.call()
	)
	var go := FxButton.make("Use this wallet", "", FxButton.Style.PRIMARY, 40)
	go.pressed.connect(save)
	_setup.add_child(go)


func _build_key_step() -> void:
	_setup.add_child(Kit.label("Set up trading", 15, 700, App.TEXT))
	_setup.add_child(_text("Oazy trades through an API wallet: its own key that can place orders but can never withdraw or move your money. It's made on this PC and locked by Windows."))
	var make := FxButton.make("Create a trading key", "lock", FxButton.Style.PRIMARY, 42)
	make.pressed.connect(func() -> void:
		make.disabled = true
		var d := await ex.create_key()
		if not bool(d.get("ok", false)):
			make.disabled = false
			App.toast("Couldn't make a key: " + str(d.get("error", "")), &"error")
	)
	_setup.add_child(make)
	var other := _link("I already have an API wallet key")
	_setup.add_child(other)
	var box := Kit.hbox(6)
	box.visible = false
	_setup.add_child(box)
	var secret := LineEdit.new()
	secret.secret = true
	secret.placeholder_text = "API wallet private key"
	secret.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	secret.custom_minimum_size.y = 40
	box.add_child(secret)
	var use := FxButton.make("Use", "", FxButton.Style.GHOST, 40)
	box.add_child(use)
	var note := _text("Only an API wallet's key, never your main wallet's. It goes straight into Windows' lock.", 11, App.TEXT_MUTE)
	note.visible = false
	_setup.add_child(note)
	other.pressed.connect(func() -> void:
		box.visible = true
		note.visible = true
		other.visible = false
		secret.grab_focus()
	)
	use.pressed.connect(func() -> void:
		var hex := secret.text
		secret.text = ""
		var d := await ex.import_key(hex)
		if not bool(d.get("ok", false)):
			App.toast(str(d.get("error", "That key didn't work.")), &"error")
	)


func _build_approve_step() -> void:
	_setup.add_child(Kit.label("Approve it on Hyperliquid", 15, 700, App.TEXT))
	_setup.add_child(_text("1.  Copy your trading key's address:"))
	var row := Kit.hbox(6)
	_setup.add_child(row)
	var addr := DesktopBelow._num(Hyperliquid.short_address(ex.agent), 14, 600, App.TEXT)
	addr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	addr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	addr.tooltip_text = ex.agent
	addr.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(addr)
	var copy := FxButton.make("Copy", "", FxButton.Style.GHOST, 36)
	copy.pressed.connect(func() -> void:
		DisplayServer.clipboard_set(ex.agent)
		App.toast("Address copied", &"success")
	)
	row.add_child(copy)
	_setup.add_child(_text("2.  On Hyperliquid's API page, paste it, name it Oazy and authorise it with your wallet."))
	var open := FxButton.make("Open Hyperliquid", "external", FxButton.Style.PRIMARY, 40)
	open.pressed.connect(func() -> void: DesktopBelow.open_link(HlExchange.APPROVE_URL))
	_setup.add_child(open)
	var wait := _text("Waiting for approval… Oazy checks every few seconds." if ex.checked else "Checking…", 12, App.TEXT_MUTE)
	_setup.add_child(wait)
	var links := Kit.hbox(14)
	_setup.add_child(links)
	var check := _link("Check now")
	check.pressed.connect(ex.check_approval)
	links.add_child(check)
	var forget := _link("Remove key")
	forget.pressed.connect(_confirm_forget)
	links.add_child(forget)


func _confirm_forget() -> void:
	if main == null:
		return
	var d := ConfirmDialog.new()
	d.title = "Remove the trading key?"
	d.message = "Oazy deletes it from this PC and can't trade until you set up a new one. Also revoke it on Hyperliquid's API page."
	d.confirm_text = "Remove"
	d.danger = true
	d.on_confirm = func() -> void: ex.forget_key()
	main.overlay_layer.add_child(d)
