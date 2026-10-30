class_name HlExchange
extends Node
## Places, closes and cancels orders on Hyperliquid, with real money.
##
## How it stays safe:
## - Orders are signed by an *agent* (API) wallet, never your main wallet. An
##   agent can trade but can't withdraw or move funds, and you approve it (and
##   can revoke it) on Hyperliquid's own site. Oazy never sees your main key.
## - The agent's key is made on this PC by the Windows companion (HlWallet),
##   which keeps it wrapped by Windows (DPAPI, your Windows user only) and only
##   unwraps it for the moment of signing. It never comes back to Oazy.
## - Nothing is sent unless the desk is armed, and it disarms itself when you
##   scroll away or after a few idle minutes. Every order goes through a
##   confirm step showing its size, price, leverage and cost first.

signal changed

const EXCHANGE := "https://api.hyperliquid.xyz/exchange"
const KEY_FILE := "user://hyperliquid/agent.key"
const APPROVE_URL := "https://app.hyperliquid.xyz/API"
## A market order is an IOC limit this far past the price, so a thin book
## can't fill it somewhere silly.
const SLIPPAGE := 0.03
## How far a triggered take profit / stop loss may fill from its trigger
## (what Hyperliquid's own app allows).
const TPSL_SLIPPAGE := 0.1
## Hyperliquid's base taker fee, for the estimate in the confirm step.
const TAKER_FEE := 0.00045
## The same for spot.
const SPOT_TAKER_FEE := 0.0007
const ARM_IDLE := 300.0

var hl: Hyperliquid
## The agent's address, "" when this PC has no trading key.
var agent := ""
## Whether Hyperliquid lists the agent as approved for your wallet, and until when (ms).
var approved := false
var approved_until := 0
var approved_name := ""
var checked := false
var armed := false
var busy := false

var _nonce := 0
var _mock := false
var _idle := 0.0


func _init(h: Hyperliquid = null) -> void:
	hl = h


func _ready() -> void:
	set_process(false)
	Settings.changed.connect(func(key: String, _v: Variant) -> void:
		if key == "hl_address":
			disarm()
			check_approval()
	)
	# The companion starts a moment after Oazy does.
	Host.status_changed.connect(func(ok: bool) -> void:
		if ok:
			refresh()
	)
	refresh()


## Trading needs Windows (the companion keeps the key).
func supported() -> bool:
	return Host.available or _mock


## Screenshots: an approved key without a companion. Nothing can be sent.
func set_mock(address: String) -> void:
	_mock = true
	agent = address
	approved = true
	checked = true
	approved_name = "Oazy"
	changed.emit()


static func key_path() -> String:
	return ProjectSettings.globalize_path(KEY_FILE)


## Ready to trade: a key, approved for the wallet you're watching.
func ready_to_trade() -> bool:
	return supported() and agent != "" and approved and Hyperliquid.address() != ""


func refresh() -> void:
	if not supported():
		return
	var d := await _host(["hl_key_address", key_path()])
	agent = str(d.get("address", ""))
	changed.emit()
	check_approval()


## Makes a new trading key on this PC.
func create_key() -> Dictionary:
	var d := await _host(["hl_key_new", key_path()])
	if bool(d.get("ok", false)):
		agent = str(d["address"])
		approved = false
		checked = false
		changed.emit()
	return d


## Uses a key made on Hyperliquid's API page instead. The text is handed to
## the companion and forgotten here straight away.
func import_key(hex: String) -> Dictionary:
	var d := await _host(["hl_key_import", key_path(), hex.strip_edges()])
	if bool(d.get("ok", false)):
		agent = str(d["address"])
		approved = false
		changed.emit()
		check_approval()
	return d


func forget_key() -> void:
	disarm()
	await _host(["hl_key_forget", key_path()])
	agent = ""
	approved = false
	changed.emit()


## Asks Hyperliquid whether the agent is approved for your wallet.
func check_approval() -> void:
	if _mock:
		return
	var user := Hyperliquid.address()
	if agent == "" or user == "":
		approved = false
		changed.emit()
		return
	var j: Variant = await hl._post({"type": "extraAgents", "user": user})
	var ok := false
	if j is Array:
		for a in j:
			if a is Dictionary and str(a.get("address", "")).to_lower() == agent.to_lower():
				var until := int(a.get("validUntil", 0))
				if until == 0 or until > int(Time.get_unix_time_from_system() * 1000.0):
					ok = true
					approved_until = until
					approved_name = str(a.get("name", ""))
	checked = j is Array
	if approved != ok:
		approved = ok
		if not ok:
			disarm()
	changed.emit()


func arm() -> void:
	if not ready_to_trade():
		return
	armed = true
	_idle = 0.0
	set_process(true)
	changed.emit()


func disarm() -> void:
	if not armed:
		return
	armed = false
	set_process(false)
	changed.emit()


## Something was done on the desk: the idle timer starts over.
func touch() -> void:
	_idle = 0.0


func _process(delta: float) -> void:
	_idle += delta
	if _idle > ARM_IDLE and not busy:
		disarm()


# --- Orders ---------------------------------------------------------------------------------

## A limit price the exchange accepts: five significant figures, and no more
## decimals than 6 (perps) or 8 (spot) minus the coin's size decimals
## (integers always pass).
static func round_px(px: float, sz_decimals: int, spot: bool = false) -> float:
	if px <= 0.0:
		return 0.0
	var mag := floori(log(px) / log(10.0))
	var digits := mini(4 - mag, (8 if spot else 6) - sz_decimals)
	if digits <= 0:
		return roundf(px)
	return snappedf(px, pow(10.0, -digits))


## A size rounded down to what the coin allows.
static func round_sz(sz: float, sz_decimals: int) -> float:
	var step := pow(10.0, -sz_decimals)
	return floorf(sz / step + 0.000001) * step


## A number the way Hyperliquid's SDK writes it: up to 8 decimals, no trailing zeros.
static func wire(x: float) -> String:
	var s := "%.8f" % x
	if s.contains("."):
		s = s.rstrip("0").rstrip(".")
	return "0" if s == "-0" or s == "" else s


## One order on the wire. `o` is {asset, buy, px, sz, reduce, tif}, or for a
## take profit / stop loss {asset, buy, px, sz, trigger, tpsl} (a market order
## when it triggers; `px` is its worst fill). Key order matters: it's hashed.
static func order_wire(o: Dictionary) -> Dictionary:
	var t := {"limit": {"tif": str(o.get("tif", "Gtc"))}}
	if float(o.get("trigger", 0.0)) > 0.0:
		t = {"trigger": {"isMarket": true, "triggerPx": wire(float(o["trigger"])), "tpsl": str(o["tpsl"])}}
	return {"a": int(o["asset"]), "b": bool(o["buy"]), "p": wire(float(o["px"])), "s": wire(float(o["sz"])),
		"r": bool(o.get("reduce", false)), "t": t}


## The action for one order.
static func order_action(o: Dictionary) -> Dictionary:
	return orders_action([o])


## Several orders at once. "normalTpsl" ties a TP / SL to the order before it;
## "positionTpsl" ties them to the whole position.
static func orders_action(list: Array, grouping: String = "na") -> Dictionary:
	return {"type": "order", "orders": list.map(func(o: Dictionary) -> Dictionary: return order_wire(o)), "grouping": grouping}


## A take profit or stop loss that closes `sz` of a position (long when
## `long`) at market once the price touches `trigger`.
static func tpsl_order(asset: int, long: bool, sz: float, trigger: float, kind: String, sz_decimals: int) -> Dictionary:
	var px := round_px(trigger, sz_decimals)
	return {"asset": asset, "buy": not long, "sz": sz, "trigger": px, "tpsl": kind, "reduce": true,
		"px": round_px(px * (1.0 + TPSL_SLIPPAGE if not long else 1.0 - TPSL_SLIPPAGE), sz_decimals)}


## Checks a take profit / stop loss against the price it's measured from:
## "" when it makes sense, else why not.
static func tpsl_problem(long: bool, ref_px: float, tp: float, sl: float) -> String:
	if tp > 0.0 and (tp <= ref_px if long else tp >= ref_px):
		return "Take profit should be %s the price." % ("above" if long else "below")
	if sl > 0.0 and (sl >= ref_px if long else sl <= ref_px):
		return "Stop loss should be %s the price." % ("below" if long else "above")
	return ""


func asset_of(c: String) -> int:
	return int((hl.meta.get(c, {}) as Dictionary).get("asset", -1))


## Works out an order from the ticket: {coin, buy, market, usd or sz, px (limit),
## lev, reduce}. Answers everything the confirm step shows, or {error}.
func quote(t: Dictionary) -> Dictionary:
	var c := str(t["coin"])
	var m: Dictionary = hl.meta.get(c, {})
	if m.is_empty() or asset_of(c) < 0:
		return {"error": "%s isn't tradable right now." % Hyperliquid.display(c)}
	var dec := int(m["sz"])
	var mid := hl.price(c)
	if mid <= 0.0:
		return {"error": "No price for %s yet." % Hyperliquid.display(c)}
	var buy := bool(t["buy"])
	var market := bool(t["market"])
	var ref_px: float = mid if market else float(t.get("px", 0.0))
	if ref_px <= 0.0:
		return {"error": "Enter a limit price."}
	if bool(m.get("spot", false)):
		return _quote_spot(t, c, dec, buy, market, ref_px)
	var sz := float(t.get("sz", 0.0))
	if sz <= 0.0:
		sz = float(t.get("usd", 0.0)) / ref_px
	sz = round_sz(sz, dec)
	if sz <= 0.0:
		return {"error": "That's smaller than the smallest size for %s." % Hyperliquid.display(c)}
	var px := round_px(ref_px * (1.0 + SLIPPAGE if buy else 1.0 - SLIPPAGE) if market else ref_px, dec)
	var notional := sz * ref_px
	if notional < 10.0 and not bool(t.get("reduce", false)):
		return {"error": "Hyperliquid's smallest order is $10."}
	var lev := clampi(int(t.get("lev", 1)), 1, maxi(1, int(m.get("lev", 1))))
	var tp := round_px(float(t.get("tp", 0.0)), dec)
	var sl := round_px(float(t.get("sl", 0.0)), dec)
	if not bool(t.get("reduce", false)):
		var why := tpsl_problem(buy, ref_px, tp, sl)
		if why != "":
			return {"error": why}
	else:
		tp = 0.0
		sl = 0.0
	return {
		"tp": tp, "sl": sl,
		"tp_pnl": sz * (tp - ref_px) * (1.0 if buy else -1.0) if tp > 0.0 else 0.0,
		"sl_pnl": sz * (sl - ref_px) * (1.0 if buy else -1.0) if sl > 0.0 else 0.0,
		"coin": c, "asset": asset_of(c), "buy": buy, "market": market, "sz": sz, "px": px, "ref_px": ref_px,
		"notional": notional, "lev": lev, "margin": notional / lev, "fee": notional * TAKER_FEE,
		"reduce": bool(t.get("reduce", false)), "tif": "Ioc" if market else "Gtc",
		"cross": not bool(m.get("isolated", false)), "decimals": dec,
	}


## A spot order: no leverage, no TP / SL; a buy spends USDC, a sell spends the
## token. Same answer shape as quote(), with "spot" set and "margin" = what it
## spends in dollars.
func _quote_spot(t: Dictionary, c: String, dec: int, buy: bool, market: bool, ref_px: float) -> Dictionary:
	var sz := float(t.get("sz", 0.0))
	if sz <= 0.0:
		sz = float(t.get("usd", 0.0)) / ref_px
	sz = round_sz(sz, dec)
	if sz <= 0.0:
		return {"error": "That's smaller than the smallest size for %s." % Hyperliquid.display(c)}
	var notional := sz * ref_px
	if notional < 10.0:
		return {"error": "Hyperliquid's smallest order is $10."}
	var px := round_px(ref_px * (1.0 + SLIPPAGE if buy else 1.0 - SLIPPAGE) if market else ref_px, dec, true)
	var sp: Dictionary = Hyperliquid.spot_pairs.get(c, {})
	return {
		"spot": true, "base": str(sp.get("base", Hyperliquid.display(c))), "quote": str(sp.get("quote", "USDC")),
		"tp": 0.0, "sl": 0.0, "tp_pnl": 0.0, "sl_pnl": 0.0,
		"coin": c, "asset": asset_of(c), "buy": buy, "market": market, "sz": sz, "px": px, "ref_px": ref_px,
		"notional": notional, "lev": 0, "margin": notional if buy else 0.0, "fee": notional * SPOT_TAKER_FEE,
		"reduce": false, "tif": "Ioc" if market else "Gtc", "cross": true, "decimals": dec,
	}


## Sends a quoted order (setting its leverage first when it changed).
func place(q: Dictionary) -> Dictionary:
	if bool(q.get("spot", false)):
		return await send(order_action(q))
	if not q.get("reduce", false) and int(q.get("lev", 0)) > 0 and int(q["lev"]) != current_leverage(str(q["coin"])):
		var lv := await send({"type": "updateLeverage", "asset": int(q["asset"]), "isCross": bool(q["cross"]), "leverage": int(q["lev"])})
		if not lv.get("ok", false):
			return lv
		_lev_cache[str(q["coin"])] = int(q["lev"])
	var list := [q]
	for kind in ["tp", "sl"]:
		if float(q.get(kind, 0.0)) > 0.0:
			list.append(tpsl_order(int(q["asset"]), bool(q["buy"]), float(q["sz"]), float(q[kind]), kind, int(q["decimals"])))
	return await send(orders_action(list, "normalTpsl" if list.size() > 1 else "na"))


## Sets (or replaces) the take profit and stop loss on a whole position. A
## price of 0 leaves that side as it is; -1 removes it.
func set_tpsl(p: Dictionary, tp: float, sl: float) -> Dictionary:
	var c := str(p["coin"])
	var dec := hl.sz_decimals(c)
	if asset_of(c) < 0:
		return {"ok": false, "error": "%s isn't tradable right now." % Hyperliquid.display(c)}
	var long := float(p["szi"]) > 0.0
	var why := tpsl_problem(long, hl.price(c), maxf(tp, 0.0), maxf(sl, 0.0))
	if why != "":
		return {"ok": false, "error": why}
	# The old ones go first, so there's only ever one of each.
	var old := []
	for o in hl.orders:
		if str(o["coin"]) == c and bool(o["reduce"]) and str(o["tpsl"]) != "":
			if (str(o["tpsl"]) == "tp" and tp != 0.0) or (str(o["tpsl"]) == "sl" and sl != 0.0):
				old.append({"a": asset_of(c), "o": int(o["oid"])})
	if not old.is_empty():
		var gone := await send({"type": "cancel", "cancels": old})
		if not gone.get("ok", false):
			return gone
	var list := []
	if tp > 0.0:
		list.append(tpsl_order(asset_of(c), long, absf(float(p["szi"])), tp, "tp", dec))
	if sl > 0.0:
		list.append(tpsl_order(asset_of(c), long, absf(float(p["szi"])), sl, "sl", dec))
	if list.is_empty():
		return {"ok": true}
	return await send(orders_action(list, "positionTpsl"))


## Closes a whole position at market (reduce-only, so it can't flip it).
func close_position(p: Dictionary) -> Dictionary:
	var c := str(p["coin"])
	var dec := hl.sz_decimals(c)
	var mid := hl.price(c)
	if mid <= 0.0 or asset_of(c) < 0:
		return {"ok": false, "error": "No price for %s yet." % Hyperliquid.display(c)}
	var buy := float(p["szi"]) < 0.0
	return await send(order_action({"asset": asset_of(c), "buy": buy, "px": round_px(mid * (1.0 + SLIPPAGE if buy else 1.0 - SLIPPAGE), dec),
		"sz": absf(float(p["szi"])), "reduce": true, "tif": "Ioc"}))


func cancel(c: String, oid: int) -> Dictionary:
	return await send({"type": "cancel", "cancels": [{"a": asset_of(c), "o": oid}]})


var _lev_cache := {}


## The leverage set for a coin: from your position, else the last one Oazy set, else 0.
func current_leverage(c: String) -> int:
	for p in hl.account.get("positions", []):
		if str(p["coin"]) == c:
			return int(p["lev"])
	return int(_lev_cache.get(c, 0))


## Signs and posts one action. Answers {ok, error, filled, resting, avg}.
func send(action: Dictionary) -> Dictionary:
	if not armed:
		return {"ok": false, "error": "Arm trading first."}
	if not ready_to_trade() or _mock:
		return {"ok": false, "error": "Trading isn't set up."}
	busy = true
	_idle = 0.0
	var nonce := maxi(int(Time.get_unix_time_from_system() * 1000.0), _nonce + 1)
	_nonce = nonce
	var sig := await _host(["hl_sign", key_path(), MsgPack.pack(action).hex_encode(), str(nonce), "1"])
	if not bool(sig.get("ok", false)):
		busy = false
		return {"ok": false, "error": str(sig.get("error", "Couldn't sign the order."))}
	if str(sig.get("address", "")).to_lower() != agent.to_lower():
		busy = false
		return {"ok": false, "error": "The trading key changed; check it in the desk's setup."}
	var body := {"action": action, "nonce": nonce, "signature": {"r": sig["r"], "s": sig["s"], "v": int(sig["v"])}, "vaultAddress": null}
	var http := HTTPRequest.new()
	http.timeout = 15.0
	http.use_threads = true
	add_child(http)
	var out := {"ok": false, "error": "Hyperliquid didn't answer."}
	if http.request(EXCHANGE, ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify(body)) == OK:
		var res: Array = await http.request_completed
		var text := (res[3] as PackedByteArray).get_string_from_utf8()
		out = parse_response(JSON.parse_string(text), text)
	http.queue_free()
	busy = false
	# Positions and orders change: look again now.
	hl.poke_account()
	return out


## /exchange's answer -> {ok, error, filled, resting, avg, oid}. With several
## orders the first one (the main order) sets filled / resting.
static func parse_response(j: Variant, raw: String = "") -> Dictionary:
	if not (j is Dictionary):
		return {"ok": false, "error": raw.substr(0, 200) if raw != "" else "Unexpected answer."}
	if str(j.get("status", "")) != "ok":
		return {"ok": false, "error": str(j.get("response", "Rejected."))}
	var resp: Variant = j.get("response")
	var out := {"ok": true}
	if resp is Dictionary and resp.get("data") is Dictionary and resp["data"].get("statuses") is Array:
		for st in resp["data"]["statuses"]:
			if st is Dictionary:
				if st.has("error"):
					return {"ok": false, "error": str(st["error"])}
				if st.get("filled") is Dictionary and not out.has("filled"):
					out["filled"] = float(st["filled"].get("totalSz", 0))
					out["avg"] = float(st["filled"].get("avgPx", 0))
					out["oid"] = int(st["filled"].get("oid", 0))
				if st.get("resting") is Dictionary and not out.has("resting") and not out.has("filled"):
					out["resting"] = true
					out["oid"] = int(st["resting"].get("oid", 0))
	return out


func _host(parts: Array) -> Dictionary:
	var box := {}
	Host.request(parts, func(d: Dictionary) -> void: box["d"] = d)
	var until := Time.get_ticks_msec() + 20000
	while not box.has("d") and Time.get_ticks_msec() < until and is_inside_tree():
		await get_tree().process_frame
	return box.get("d", {"ok": false, "error": "The Windows helper didn't answer."})
