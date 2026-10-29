class_name TpslDialog
extends Modal
## Take profit and stop loss for an open position: two prices, what each would
## make or lose, and one button that sends them (replacing any already set).
## Clearing a field removes that side.

const UP := DesktopBelow.UP
const DOWN := DesktopBelow.DOWN

var hl: Hyperliquid
var ex: HlExchange
## The position (parse_account row).
var pos := {}
## The TP / SL prices already set, 0 if none.
var tp_now := 0.0
var sl_now := 0.0

var _tp: LineEdit
var _sl: LineEdit
var _tp_est: Label
var _sl_est: Label
var _note: Label
var _go: Button
var _cancel: FxButton


func _init() -> void:
	width = 520.0


func _long() -> bool:
	return float(pos["szi"]) > 0.0


func _build() -> void:
	var c := str(pos["coin"])
	var name := Hyperliquid.display(c)
	title_block("TP / SL for your %s %s" % [name, "long" if _long() else "short"],
		"Market orders that close the whole position when the price gets there. Clear a box to remove it.", "shield")
	var facts := Kit.hbox(24)
	content.add_child(facts)
	for pair in [["Entry", Hyperliquid.fmt_px(float(pos["entry"]))], ["Price now", Hyperliquid.fmt_px(hl.price(c))],
			["Size", "%s %s" % [Hyperliquid.fmt_sz(absf(float(pos["szi"])), hl.sz_decimals(c)), name]]]:
		var b := Kit.vbox(2)
		b.add_child(Kit.label(pair[0], 11, 600, App.TEXT_MUTE))
		b.add_child(DesktopBelow._num(pair[1], 15, 600, App.TEXT))
		facts.add_child(b)
	var row := Kit.hbox(14)
	content.add_child(row)
	var tp_col := _price_box("Take profit", tp_now)
	row.add_child(tp_col[0])
	_tp = tp_col[1]
	_tp_est = tp_col[2]
	var sl_col := _price_box("Stop loss", sl_now)
	row.add_child(sl_col[0])
	_sl = sl_col[1]
	_sl_est = sl_col[2]
	_note = Kit.label("", 12, 600, DOWN)
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_note)
	var buttons := Kit.hbox(12)
	buttons.alignment = BoxContainer.ALIGNMENT_END
	content.add_child(buttons)
	_cancel = FxButton.make("Cancel", "", FxButton.Style.GHOST, 46)
	_cancel.pressed.connect(close)
	buttons.add_child(_cancel)
	_go = FxButton.make("Set TP / SL", "", FxButton.Style.PRIMARY, 46)
	_go.pressed.connect(_send)
	buttons.add_child(_go)
	_refresh()


func _price_box(label: String, now: float) -> Array:
	var col := Kit.vbox(6)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(Kit.label(label, 12, 600, App.TEXT_MUTE))
	var e := LineEdit.new()
	e.placeholder_text = "Price"
	e.text = HlExchange.wire(now) if now > 0.0 else ""
	e.custom_minimum_size.y = 44
	e.add_theme_font_override("font", DesktopBelow._num_font(600))
	e.add_theme_font_size_override("font_size", 16)
	e.text_changed.connect(func(_t: String) -> void: _refresh())
	e.text_submitted.connect(func(_t: String) -> void: _send())
	col.add_child(e)
	var est := DesktopBelow._num("", 12, 600, App.TEXT_MUTE)
	col.add_child(est)
	return [col, e, est]


static func _val(e: LineEdit) -> float:
	return e.text.replace(",", "").replace("$", "").strip_edges().to_float()


## What closing the whole position at `px` would make (+) or lose (−).
func _pnl_at(px: float) -> float:
	return float(pos["szi"]) * (px - float(pos["entry"]))


func _refresh() -> void:
	var tp := _val(_tp)
	var sl := _val(_sl)
	for pair in [[tp, _tp_est], [sl, _sl_est]]:
		var l: Label = pair[1]
		if float(pair[0]) > 0.0:
			var v := _pnl_at(float(pair[0]))
			var move := (float(pair[0]) / hl.price(str(pos["coin"])) - 1.0) * 100.0 if hl.price(str(pos["coin"])) > 0.0 else 0.0
			l.text = "%s  ·  %s%.2f%% from now" % [Hyperliquid.fmt_usd(v, true), "+" if move >= 0.0 else "−", absf(move)]
			l.add_theme_color_override("font_color", UP if v >= 0.0 else DOWN)
		else:
			l.text = "None"
			l.add_theme_color_override("font_color", App.TEXT_MUTE)
	_note.text = HlExchange.tpsl_problem(_long(), hl.price(str(pos["coin"])), tp, sl)
	_go.disabled = _note.text != "" or not ex.armed or ex.busy


func _send() -> void:
	_refresh()
	if _go.disabled:
		return
	var tp := _val(_tp)
	var sl := _val(_sl)
	# 0 keeps a side as it is, -1 removes it: an emptied box removes.
	var tp_arg := tp if tp > 0.0 else (-1.0 if tp_now > 0.0 else 0.0)
	var sl_arg := sl if sl > 0.0 else (-1.0 if sl_now > 0.0 else 0.0)
	if tp_arg == 0.0 and sl_arg == 0.0:
		close()
		return
	Sfx.play(&"select")
	_go.disabled = true
	var r := await ex.set_tpsl(pos, tp_arg, sl_arg)
	if bool(r.get("ok", false)):
		App.toast("TP / SL set for %s" % Hyperliquid.display(str(pos["coin"])), &"success")
		close()
	else:
		_note.text = "Hyperliquid said no: " + str(r.get("error", "unknown error"))
		_go.disabled = false


func _focus_first() -> void:
	(_tp if _tp.text == "" else _sl).grab_focus()
