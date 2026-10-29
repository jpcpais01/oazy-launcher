class_name Hyperliquid
extends Node
## Prices, charts, the order book, trades and your own positions from
## Hyperliquid's public API: crypto on the main exchange, plus the stocks,
## indices and more on its builder-deployed exchanges (HIP-3, e.g. "xyz:XYZ100").
## Reading needs nothing but your wallet address, which is public anyway.
##
## Prices (one WebSocket feed of every coin's mid) and your positions keep
## ticking in the background. The order book, trades and live candles for the
## coin on screen only stream while the trading page is in view (`set_focus`).
## Placing orders goes through HlExchange.

signal prices_changed
## The focused coin's book, trades, candles or stats moved.
signal market_changed
signal account_changed
signal status_changed

const INFO := "https://api.hyperliquid.xyz/info"
const WS_URL := "wss://api.hyperliquid.xyz/ws"
const INTERVALS := {"5m": 300, "15m": 900, "1h": 3600, "4h": 14400, "1d": 86400}
## The chart view for stocks and ETFs: from the open of the US trading day.
const TODAY := "today"
## The regular session: 9:30 to 16:00 New York time.
const SESSION_OPEN_S := 34200
const SESSION_LEN_S := 23400
const CANDLES := 160
const MAX_TRADES := 80
## Seconds between REST polls: every coin's 24h stats, your account (in the
## background and while you look), and the ticker's day lines.
const CTX_EVERY := 60.0
const ACCOUNT_EVERY := 20.0
const ACCOUNT_EVERY_FOCUS := 4.0
const SPARK_EVERY := 600.0
## The builder exchanges are looked up again this often.
const DEXES_EVERY := 900
const PING_EVERY := 30.0

## coin -> mid price, straight from the feed (strings; read with price()).
var mids := {}
## coin -> {mark, prev, vol, oi, funding, oracle}
var ctxs := {}
## coin -> {sz: size decimals, lev: max leverage, asset: order id, dex, isolated}
var meta := {}
## The perp exchanges by index: "" is Hyperliquid's own, the rest are builders'.
var dexes: Array = [""]
## Your resting orders on every exchange (parse_orders), while the page is open.
var orders: Array = []
## coin -> the last 24 hourly closes, for the ticker.
var sparks := {}
## The focused coin's candles, oldest first: [t (s), open, high, low, close, volume].
var candles: Array = []
## In the Today view: the last trading day's 4pm New York close (no
## after-hours), 0 when unknown.
var prev_close := 0.0
## {bids: [[px, sz]], asks: [[px, sz]], time}, best price first on both sides.
var book := {}
## Newest first: {px, sz, side ("B" buy / "A" sell), time (ms), tid, seen (ticks ms)}.
var trades: Array = []
## compose_account() of your wallet, {} until it's known: perps on every
## exchange plus your spot balances, counted the way your account mode does.
var account := {}
## Your account mode from userAbstraction: "unifiedAccount", "portfolioMargin",
## "disabled" (standard), "dexAbstraction" or "" until known.
var mode := ""
## Spot token -> USD price, for valuing balances.
var spot_px := {}
## True while the WebSocket feed is open.
var live := false
var focused := false
var last_error := ""

var _ws: WebSocketPeer
var _was_open := false
var _retry_in := 0.0
var _backoff := 2.0
var _ping_in := PING_EVERY
var _ctx_in := 0.0
var _acct_in := 0.0
var _subs := {}
var _mock := false
var _started := false
var _ctx_busy := false
var _acct_busy := false
var _spark_busy := false
var _spark_at := 0
var _candle_key := ""
var _candle_at := 0
var _dexes_at := 0
var _mode_addr := ""
var _spot_px_at := 0


func _ready() -> void:
	set_process(false)
	Settings.changed.connect(func(key: String, _v: Variant) -> void:
		match key:
			"hl_coin", "hl_interval":
				candles = []
				prev_close = 0.0
				book = {}
				trades = []
				_candle_key = ""
				market_changed.emit()
				if focused:
					_fetch_candles()
				_sync_subs()
			"hl_address":
				account = {}
				orders = []
				mode = ""
				_mode_addr = ""
				account_changed.emit()
				_acct_in = 0.0
			"hl_coins":
				_sync_subs()
				_spark_at = 0
				if focused:
					_fetch_sparks()
	)


## Starts the background feed. Nothing connects in tests unless forced.
func start(force: bool = false) -> void:
	if _started or _mock or (App.smoke_test and not force):
		return
	_started = true
	set_process(true)
	_connect()


# --- Settings ----------------------------------------------------------------------------

static func coins() -> PackedStringArray:
	var out := PackedStringArray()
	for c in Settings.get_value("hl_coins"):
		var t := str(c).strip_edges()
		if t != "" and not out.has(t):
			out.append(t)
	return out


static func coin() -> String:
	var c := str(Settings.get_value("hl_coin"))
	return c if c != "" else "BTC"


## The chart view picked: an interval, or TODAY on a stock / ETF market.
static func view() -> String:
	var i := str(Settings.get_value("hl_interval"))
	if i == TODAY:
		return TODAY if has_session(coin()) else "1h"
	return i if INTERVALS.has(i) else "1h"


## The candle size behind the view. Today uses 5m candles, or 15m once the
## span gets long (the weekend, before Monday's open).
static func interval() -> String:
	var v := view()
	if v != TODAY:
		return v
	var now := int(Time.get_unix_time_from_system())
	return "5m" if now - session_open(now) <= 10 * 3600 else "15m"


## Stocks, ETFs and indices: the markets on builder exchanges (HIP-3).
static func has_session(c: String) -> bool:
	return dex_of(c) != ""


## New York's offset from UTC at `utc`, in seconds: −4h in summer time
## (second Sunday of March to first Sunday of November, 2am local), else −5h.
static func ny_offset(utc: int) -> int:
	var y := int(Time.get_datetime_dict_from_unix_time(utc)["year"])
	var start := _nth_sunday(y, 3, 2) + 7 * 3600
	var end := _nth_sunday(y, 11, 1) + 6 * 3600
	return -4 * 3600 if utc >= start and utc < end else -5 * 3600


## Midnight UTC of the n-th Sunday of a month.
static func _nth_sunday(y: int, m: int, n: int) -> int:
	var first := Time.get_unix_time_from_datetime_dict({"year": y, "month": m, "day": 1, "hour": 0, "minute": 0, "second": 0})
	var wd := int(Time.get_datetime_dict_from_unix_time(first)["weekday"])
	return first + (((7 - wd) % 7) + 7 * (n - 1)) * 86400


## The 4pm New York close of the trading day before the one opening at `open`.
static func session_close_before(open: int) -> int:
	return session_open(open - 1) + SESSION_LEN_S


## When the latest US trading day opened (9:30 New York), as a UTC unix time:
## today's open once it has passed, else the last weekday's.
static func session_open(now: int) -> int:
	var local := now + ny_offset(now)
	var open := local - posmod(local, 86400) + SESSION_OPEN_S
	if local < open:
		open -= 86400
	while int(Time.get_datetime_dict_from_unix_time(open)["weekday"]) in [0, 6]:
		open -= 86400
	# Never a Sunday 2am, so the offset 5h later is the one that applied.
	return open - ny_offset(open + 5 * 3600)


static func address() -> String:
	var a := str(Settings.get_value("hl_address")).strip_edges()
	return a.to_lower() if is_address(a) else ""


## A wallet address: 0x and 40 hex digits. Never a private key (that's 64).
static func is_address(text: String) -> bool:
	var t := text.strip_edges()
	if t.length() != 42 or not t.begins_with("0x"):
		return false
	return t.substr(2).is_valid_hex_number()


## "btc, eth  kpepe" -> ["BTC", "ETH", "kPEPE"], spelt the way Hyperliquid does
## when it knows the coin.
func parse_coins(text: String) -> PackedStringArray:
	var known := {}
	# Full names ("xyz:XYZ100") and short ones; Hyperliquid's own coins (loaded
	# first) win a short name over a builder's.
	for c in meta.keys():
		known[str(c).to_upper()] = c
	for c in meta.keys():
		var short := display(str(c)).to_upper()
		if not known.has(short):
			known[short] = c
	var out := PackedStringArray()
	for part in text.replace(";", ",").replace(" ", ",").split(",", false):
		var t := part.strip_edges().trim_suffix("-USD").trim_suffix("/USD")
		if t == "":
			continue
		t = str(known.get(t.to_upper(), t.to_upper()))
		if not out.has(t) and out.size() < 8:
			out.append(t)
	return out


# --- Reading -------------------------------------------------------------------------------------

## "xyz:XYZ100" -> "XYZ100"
static func display(c: String) -> String:
	return c.get_slice(":", 1) if c.contains(":") else c


## The builder exchange a coin trades on ("" for Hyperliquid's own).
static func dex_of(c: String) -> String:
	return c.get_slice(":", 0) if c.contains(":") else ""

## The latest price: the live mid, else the stats feed's mid, else its mark.
func price(c: String) -> float:
	if mids.has(c):
		return float(mids[c])
	var x: Dictionary = ctxs.get(c, {})
	return float(x.get("mid", 0.0)) if float(x.get("mid", 0.0)) > 0.0 else float(x.get("mark", 0.0))


## Yesterday's price at this time (for the 24h change), 0 when unknown.
func prev(c: String) -> float:
	return float((ctxs.get(c, {}) as Dictionary).get("prev", 0.0))


func change_pct(c: String) -> float:
	var p := prev(c)
	return (price(c) - p) / p * 100.0 if p > 0.0 else 0.0


func sz_decimals(c: String) -> int:
	return int((meta.get(c, {}) as Dictionary).get("sz", 4))


## Unrealised P&L of a position at the live price.
func live_pnl(pos: Dictionary) -> float:
	var m := price(str(pos["coin"]))
	if m <= 0.0:
		return float(pos["upnl"])
	return float(pos["szi"]) * (m - float(pos["entry"]))


## Account value with every position marked at the live price.
func live_value() -> float:
	if account.is_empty():
		return 0.0
	var v := float(account["value"])
	for p in account["positions"]:
		v += live_pnl(p) - float(p["upnl"])
	return v


## The best bid and ask: [bid, ask], or [] when there's no book yet.
func top_of_book() -> Array:
	if book.is_empty() or (book["bids"] as Array).is_empty() or (book["asks"] as Array).is_empty():
		return []
	return [float(book["bids"][0][0]), float(book["asks"][0][0])]


# --- Focus: what streams while the page is in view ---------------------------------------------

func set_focus(on: bool) -> void:
	if on == focused:
		return
	focused = on
	if _mock:
		return
	if on:
		start()
		_acct_in = 0.0
		if candles.is_empty() or _candle_key != coin() + "|" + view() or _now() - _candle_at > 60:
			_fetch_candles()
		if _now() - _spark_at > SPARK_EVERY:
			_fetch_sparks()
	else:
		# Old book and trades would be wrong next time; start clean.
		book = {}
		trades = []
	_sync_subs()


func _wanted() -> Dictionary:
	var out := {"mids": {"type": "allMids"}}
	# Every coin you follow or hold also gets its own small stats feed (mid,
	# mark, 24h change), so the ticker and your P&L tick even without allMids.
	var held := []
	for p in account.get("positions", []):
		held.append(str(p["coin"]))
	for c in Array(coins()) + held:
		out["ctx:" + c] = {"type": "activeAssetCtx", "coin": c}
	if focused:
		var c := coin()
		out["book:" + c] = {"type": "l2Book", "coin": c}
		out["trades:" + c] = {"type": "trades", "coin": c}
		out["candle:" + c + ":" + interval()] = {"type": "candle", "coin": c, "interval": interval()}
	return out


func _sync_subs() -> void:
	if not live:
		return
	var want := _wanted()
	for key in _subs.keys():
		if not want.has(key):
			_send({"method": "unsubscribe", "subscription": _subs[key]})
			_subs.erase(key)
	for key in want:
		if not _subs.has(key):
			_send({"method": "subscribe", "subscription": want[key]})
			_subs[key] = want[key]


# --- WebSocket -------------------------------------------------------------------------------------

func _connect() -> void:
	_ws = WebSocketPeer.new()
	# Every coin's mid in one message: give it room.
	_ws.inbound_buffer_size = 4 << 20
	_ws.max_queued_packets = 8192
	_was_open = false
	if _ws.connect_to_url(WS_URL) != OK:
		_ws = null
		_retry_in = _backoff
		_backoff = minf(_backoff * 2.0, 60.0)


func _send(msg: Dictionary) -> void:
	if _ws and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_ws.send_text(JSON.stringify(msg))


func _process(delta: float) -> void:
	_poll_ws(delta)
	_ctx_in -= delta
	if _ctx_in <= 0.0:
		_ctx_in = CTX_EVERY
		_fetch_ctxs()
	_acct_in -= delta
	if _acct_in <= 0.0:
		_acct_in = ACCOUNT_EVERY_FOCUS if focused else ACCOUNT_EVERY
		_fetch_account()


func _poll_ws(delta: float) -> void:
	if _ws == null:
		_retry_in -= delta
		if _retry_in <= 0.0:
			_connect()
		return
	_ws.poll()
	var st := _ws.get_ready_state()
	if st == WebSocketPeer.STATE_OPEN:
		if not _was_open:
			_was_open = true
			_backoff = 2.0
			_ping_in = PING_EVERY
			live = true
			_subs.clear()
			_sync_subs()
			status_changed.emit()
		var mids_moved := false
		var market_moved := false
		while _ws.get_available_packet_count() > 0:
			var j: Variant = JSON.parse_string(_ws.get_packet().get_string_from_utf8())
			if not (j is Dictionary):
				continue
			match _on_message(j):
				1:
					mids_moved = true
				2:
					market_moved = true
		if mids_moved:
			prices_changed.emit()
		if market_moved:
			market_changed.emit()
		_ping_in -= delta
		if _ping_in <= 0.0:
			_ping_in = PING_EVERY
			_send({"method": "ping"})
	elif st == WebSocketPeer.STATE_CLOSED:
		last_error = "feed closed (%d %s)" % [_ws.get_close_code(), _ws.get_close_reason()]
		_ws = null
		_subs.clear()
		_retry_in = _backoff
		_backoff = minf(_backoff * 2.0, 60.0)
		if live or _was_open:
			live = false
			status_changed.emit()


## One feed message. 1 = prices moved, 2 = the focused market moved, 0 = nothing.
func _on_message(j: Dictionary) -> int:
	var data: Variant = j.get("data")
	match str(j.get("channel", "")):
		"allMids":
			if data is Dictionary and data.get("mids") is Dictionary:
				mids = data["mids"]
				return 1
		"l2Book":
			if data is Dictionary and str(data.get("coin", "")) == coin():
				var b := parse_book(data)
				if not b.is_empty():
					book = b
					return 2
		"trades":
			if data is Array and focused:
				return 2 if add_trades(data) else 0
		"candle":
			if data is Dictionary and str(data.get("s", "")) == coin() and str(data.get("i", "")) == interval():
				_merge_candle(data)
				return 2
		"activeAssetCtx":
			if data is Dictionary and data.get("ctx") is Dictionary:
				var c := str(data.get("coin", ""))
				ctxs[c] = parse_ctx(data["ctx"])
				return 2 if focused and c == coin() else 1
		"error":
			last_error = str(data)
	return 0


func add_trades(list: Array) -> bool:
	var c := coin()
	var seen := {}
	for t in trades:
		seen[t["tid"]] = true
	var now := Time.get_ticks_msec()
	var fresh: Array = []
	for d in list:
		if not (d is Dictionary) or str(d.get("coin", "")) != c:
			continue
		var tid: Variant = d.get("tid", str(d.get("hash", "")) + str(d.get("time", "")))
		if seen.has(tid):
			continue
		seen[tid] = true
		# The first batch is history, so it doesn't flash.
		fresh.append({"px": float(d.get("px", 0)), "sz": float(d.get("sz", 0)), "side": str(d.get("side", "B")),
			"time": int(d.get("time", 0)), "tid": tid, "seen": now if not trades.is_empty() else 0})
	if fresh.is_empty():
		return false
	trades.append_array(fresh)
	trades.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["time"]) > int(b["time"]))
	if trades.size() > MAX_TRADES:
		trades.resize(MAX_TRADES)
	return true


func _merge_candle(d: Dictionary) -> void:
	var row := [int(d.get("t", 0)) / 1000, float(d.get("o", 0)), float(d.get("h", 0)), float(d.get("l", 0)), float(d.get("c", 0)), float(d.get("v", 0))]
	if candles.is_empty():
		return
	var last: Array = candles[candles.size() - 1]
	if int(row[0]) == int(last[0]):
		candles[candles.size() - 1] = row
	elif int(row[0]) > int(last[0]):
		candles.append(row)
		if candles.size() > CANDLES + 40 and view() != TODAY:
			candles = candles.slice(candles.size() - CANDLES)


## Looks at your account again as soon as it can (after an order).
func poke_account() -> void:
	_acct_in = 0.6


# --- REST ----------------------------------------------------------------------------------------

func _now() -> int:
	return int(Time.get_unix_time_from_system())


func _post(body: Dictionary) -> Variant:
	var http := HTTPRequest.new()
	http.timeout = 12.0
	http.use_threads = true
	add_child(http)
	var out: Variant = null
	if http.request(INFO, ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify(body)) == OK:
		var res: Array = await http.request_completed
		if int(res[0]) == HTTPRequest.RESULT_SUCCESS and int(res[1]) == 200:
			out = JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8())
		else:
			last_error = "%s: result %d, HTTP %d" % [str(body.get("type")), int(res[0]), int(res[1])]
	http.queue_free()
	return out


func _fetch_ctxs() -> void:
	if _ctx_busy or _mock:
		return
	_ctx_busy = true
	if _now() - _dexes_at > DEXES_EVERY:
		var list := parse_dexes(await _post({"type": "perpDexs"}))
		if not list.is_empty():
			dexes = list
			_dexes_at = _now()
	for i in dexes.size():
		var body := {"type": "metaAndAssetCtxs"}
		if dexes[i] != "":
			body["dex"] = dexes[i]
		if parse_meta_and_ctxs(await _post(body), meta, ctxs, dexes[i], i):
			prices_changed.emit()
	_ctx_busy = false


func _fetch_account() -> void:
	var addr := address()
	if _acct_busy or _mock or addr == "":
		return
	_acct_busy = true
	if _mode_addr != addr:
		var m: Variant = await _post({"type": "userAbstraction", "user": addr})
		if m is String:
			mode = m
			_mode_addr = addr
	if _now() - _spot_px_at > CTX_EVERY:
		var px := parse_spot_prices(await _post({"type": "spotMetaAndAssetCtxs"}))
		if not px.is_empty():
			spot_px = px
			_spot_px_at = _now()
	var spot_j: Variant = await _post({"type": "spotClearinghouseState", "user": addr})
	var spot := parse_spot_balances(spot_j)
	# Each exchange keeps its own margin: add them up.
	var total := {}
	var open := []
	for d in dexes:
		var body := {"type": "clearinghouseState", "user": addr}
		if d != "":
			body["dex"] = d
		var a := parse_account(await _post(body), d)
		if not a.is_empty():
			total = a if total.is_empty() else merge_accounts(total, a)
		if focused:
			body["type"] = "frontendOpenOrders"
			open.append_array(parse_orders(await _post(body), d))
	_acct_busy = false
	if addr != address():
		return
	if focused:
		orders = open
	# A unified account's money is all in spot: without that answer, keep the last numbers.
	if (not total.is_empty() or not spot.is_empty()) and (spot_j is Dictionary or not unified(mode)):
		account = compose_account(total, spot, spot_px, unified(mode))
		account_changed.emit()
		_sync_subs()


func _fetch_candles() -> void:
	if _mock:
		return
	var c := coin()
	var iv := interval()
	var key := c + "|" + view()
	var end := _now() * 1000
	var start := end - int(INTERVALS[iv]) * 1000 * CANDLES
	if view() == TODAY:
		start = session_open(_now()) * 1000
	var j: Variant = await _post({"type": "candleSnapshot", "req": {"coin": c, "interval": iv, "startTime": start, "endTime": end}})
	var ref := 0.0
	if view() == TODAY:
		# The 5m candle that ends at the last trading day's 4pm bell.
		var bell := (session_close_before(session_open(_now())) - 300) * 1000
		var last := parse_candles(await _post({"type": "candleSnapshot", "req": {"coin": c, "interval": "5m", "startTime": bell, "endTime": bell + 1000}}))
		if not last.is_empty():
			ref = float(last[last.size() - 1][4])
	if key != coin() + "|" + view():
		return
	prev_close = ref
	var rows := parse_candles(j)
	if not rows.is_empty():
		candles = rows
		_candle_key = key
		_candle_at = _now()
		market_changed.emit()


func _fetch_sparks() -> void:
	if _spark_busy or _mock:
		return
	_spark_busy = true
	_spark_at = _now()
	var end := _now() * 1000
	for c in coins():
		var rows := parse_candles(await _post({"type": "candleSnapshot", "req": {"coin": c, "interval": "1h", "startTime": end - 24 * 3600 * 1000, "endTime": end}}))
		if not rows.is_empty():
			var closes := []
			for r in rows:
				closes.append(r[4])
			sparks[c] = closes
			prices_changed.emit()
	_spark_busy = false


# --- Parsing (static, so tests can feed it answers) --------------------------------------------------

## perpDexs -> ["", "xyz", ...] (index = the exchange's number in asset ids).
static func parse_dexes(j: Variant) -> Array:
	if not (j is Array) or j.is_empty():
		return []
	var out := []
	for d in j:
		out.append(str(d.get("name", "")) if d is Dictionary else "")
	out[0] = ""
	return out


## Two exchanges' accounts as one.
static func merge_accounts(a: Dictionary, b: Dictionary) -> Dictionary:
	var out := a.duplicate(true)
	for k in ["value", "ntl", "margin", "withdrawable"]:
		out[k] = float(a[k]) + float(b[k])
	(out["positions"] as Array).append_array(b["positions"])
	(out["positions"] as Array).sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return absf(float(x["value"])) > absf(float(y["value"])))
	return out


## Unified and portfolio-margin accounts keep all their money in the spot
## balances; the perp exchanges' own summaries then only show what's in use.
static func unified(account_mode: String) -> bool:
	return account_mode in ["unifiedAccount", "portfolioMargin"]


## spotClearinghouseState -> [{coin, total, hold, entry}], biggest holdings first.
static func parse_spot_balances(j: Variant) -> Array:
	var out := []
	if not (j is Dictionary) or not (j.get("balances") is Array):
		return out
	for b in j["balances"]:
		if b is Dictionary and _f(b.get("total")) != 0.0:
			out.append({"coin": str(b.get("coin", "")), "total": _f(b.get("total")), "hold": _f(b.get("hold")), "entry": _f(b.get("entryNtl"))})
	return out


## spotMetaAndAssetCtxs -> token -> USD price, from each token's pair against
## USDC (token 0). Dollar stablecoins without a pair count as $1.
static func parse_spot_prices(j: Variant) -> Dictionary:
	var out := {"USDC": 1.0}
	if not (j is Array) or j.size() < 2 or not (j[0] is Dictionary) or not (j[1] is Array):
		return {}
	var names := {}
	for t in j[0].get("tokens", []):
		if t is Dictionary:
			names[int(t.get("index", -1))] = str(t.get("name", ""))
	var ctx_by_coin := {}
	for x in j[1]:
		if x is Dictionary:
			ctx_by_coin[str(x.get("coin", ""))] = x
	for u in j[0].get("universe", []):
		if not (u is Dictionary) or not (u.get("tokens") is Array) or (u["tokens"] as Array).size() < 2:
			continue
		if int(u["tokens"][1]) != 0:
			continue
		var x: Variant = ctx_by_coin.get(str(u.get("name", "")))
		if not (x is Dictionary):
			continue
		var px := _f(x.get("midPx")) if x.get("midPx") != null else _f(x.get("markPx"))
		var nm := str(names.get(int(u["tokens"][0]), ""))
		if nm != "" and px > 0.0 and not out.has(nm):
			out[nm] = px
	for nm in names.values():
		if str(nm).begins_with("USD") and not out.has(nm):
			out[nm] = 1.0
	return out


## Perps (merged parse_account) + spot balances -> the account the desk shows:
## {value, perps, spot, margin, withdrawable, ntl, upnl, positions, balances,
## unified}. In a unified account the spot balances are the money and the
## positions' unrealised P&L sits on top; otherwise the perp accounts and the
## spot balances are separate pots and both count.
static func compose_account(perp: Dictionary, balances: Array, prices: Dictionary, is_unified: bool) -> Dictionary:
	var positions: Array = perp.get("positions", [])
	var upnl := 0.0
	var pos_margin := 0.0
	for p in positions:
		upnl += float(p["upnl"])
		pos_margin += float(p["margin"])
	var spot_usd := 0.0
	var usdc_free := 0.0
	var rows := []
	for b in balances:
		var px := float(prices.get(b["coin"], 0.0))
		var usd := float(b["total"]) * px if px > 0.0 else float(b["entry"])
		spot_usd += usd
		if str(b["coin"]) == "USDC":
			usdc_free = maxf(0.0, float(b["total"]) - float(b["hold"]))
		var row: Dictionary = b.duplicate()
		row["usd"] = usd
		rows.append(row)
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["usd"]) > float(b["usd"]))
	var perps := float(perp.get("value", 0.0))
	var out := {
		"positions": positions, "balances": rows, "unified": is_unified, "upnl": upnl,
		"ntl": float(perp.get("ntl", 0.0)), "spot": spot_usd,
		"margin": maxf(float(perp.get("margin", 0.0)), pos_margin),
		"at": int(Time.get_unix_time_from_system()),
	}
	if is_unified:
		out["value"] = spot_usd + upnl
		out["perps"] = perps
		out["withdrawable"] = usdc_free
	else:
		out["value"] = perps + spot_usd
		out["perps"] = perps
		out["withdrawable"] = float(perp.get("withdrawable", 0.0)) + usdc_free
	return out


## frontendOpenOrders -> [{coin, buy, px, sz, orig, oid, reduce, kind, time,
## trigger (px, 0 if none), tpsl ("tp", "sl" or ""), position (whole-position TP/SL)}]
static func parse_orders(j: Variant, dex: String = "") -> Array:
	var out := []
	if not (j is Array):
		return out
	for o in j:
		if not (o is Dictionary):
			continue
		var c := str(o.get("coin", ""))
		if dex != "" and not c.contains(":"):
			c = dex + ":" + c
		out.append({"coin": c, "buy": str(o.get("side", "B")) == "B", "px": _f(o.get("limitPx")), "sz": _f(o.get("sz")),
			"orig": _f(o.get("origSz", o.get("sz"))), "oid": int(o.get("oid", 0)), "reduce": bool(o.get("reduceOnly", false)),
			"kind": str(o.get("orderType", "Limit")), "time": int(o.get("timestamp", 0)),
			"trigger": _f(o.get("triggerPx")) if bool(o.get("isTrigger", false)) else 0.0,
			"tpsl": tpsl_of(str(o.get("orderType", ""))), "position": bool(o.get("isPositionTpsl", false))})
	return out


## "Take Profit Market" -> "tp", "Stop Limit" -> "sl", anything else -> "".
static func tpsl_of(kind: String) -> String:
	if kind.begins_with("Take Profit"):
		return "tp"
	if kind.begins_with("Stop"):
		return "sl"
	return ""


## metaAndAssetCtxs -> fills `meta_out` and `ctx_out`. False if it wasn't one.
## `dex_index` places the coins in Hyperliquid's asset numbering: plain
## indices on its own exchange, 100000 + dex * 10000 + index on a builder's.
static func parse_meta_and_ctxs(j: Variant, meta_out: Dictionary, ctx_out: Dictionary, dex: String = "", dex_index: int = 0) -> bool:
	if not (j is Array) or j.size() < 2 or not (j[0] is Dictionary) or not (j[1] is Array):
		return false
	var uni: Variant = j[0].get("universe")
	if not (uni is Array):
		return false
	for i in mini(uni.size(), j[1].size()):
		var u: Variant = uni[i]
		var x: Variant = j[1][i]
		if not (u is Dictionary) or not (x is Dictionary):
			continue
		var name := str(u.get("name", ""))
		if dex != "" and not name.contains(":"):
			name = dex + ":" + name
		meta_out[name] = {"sz": int(u.get("szDecimals", 4)), "lev": int(u.get("maxLeverage", 1)), "dex": dex,
			"asset": i if dex_index == 0 else 100000 + dex_index * 10000 + i,
			"isolated": bool(u.get("onlyIsolated", false)) or str(u.get("marginMode", "")) in ["strictIsolated", "noCross"],
			"delisted": bool(u.get("isDelisted", false))}
		ctx_out[name] = parse_ctx(x)
	return true


static func parse_ctx(x: Dictionary) -> Dictionary:
	return {
		"mark": _f(x.get("markPx")), "mid": _f(x.get("midPx")), "prev": _f(x.get("prevDayPx")), "vol": _f(x.get("dayNtlVlm")),
		"oi": _f(x.get("openInterest")), "funding": _f(x.get("funding")), "oracle": _f(x.get("oraclePx")),
	}


static func _f(v: Variant) -> float:
	return float(v) if v != null else 0.0


## l2Book -> {bids, asks, time}, {} if it isn't one.
static func parse_book(d: Dictionary) -> Dictionary:
	var levels: Variant = d.get("levels")
	if not (levels is Array) or levels.size() < 2:
		return {}
	var sides := []
	for side in [levels[0], levels[1]]:
		var rows := []
		if side is Array:
			for l in side:
				if l is Dictionary:
					rows.append([float(l.get("px", 0)), float(l.get("sz", 0))])
		sides.append(rows)
	return {"bids": sides[0], "asks": sides[1], "time": int(d.get("time", 0))}


## candleSnapshot -> [[t (s), o, h, l, c, v]], oldest first.
static func parse_candles(j: Variant) -> Array:
	var out := []
	if not (j is Array):
		return out
	for d in j:
		if d is Dictionary and d.has("t") and d.has("c"):
			out.append([int(d["t"]) / 1000, float(d.get("o", 0)), float(d.get("h", 0)), float(d.get("l", 0)), float(d["c"]), float(d.get("v", 0))])
	out.sort_custom(func(a: Array, b: Array) -> bool: return int(a[0]) < int(b[0]))
	return out


## clearinghouseState -> {value, ntl, margin, withdrawable, positions: [...]}.
static func parse_account(j: Variant, dex: String = "") -> Dictionary:
	if not (j is Dictionary) or not (j.get("marginSummary") is Dictionary):
		return {}
	var ms: Dictionary = j["marginSummary"]
	var positions := []
	var list: Variant = j.get("assetPositions", [])
	if list is Array:
		for ap in list:
			if not (ap is Dictionary) or not (ap.get("position") is Dictionary):
				continue
			var p: Dictionary = ap["position"]
			var szi := _f(p.get("szi"))
			if szi == 0.0:
				continue
			var lev: Variant = p.get("leverage", {})
			var pc := str(p.get("coin", ""))
			if dex != "" and not pc.contains(":"):
				pc = dex + ":" + pc
			positions.append({
				"coin": pc, "szi": szi, "entry": _f(p.get("entryPx")),
				"value": _f(p.get("positionValue")), "upnl": _f(p.get("unrealizedPnl")),
				"roe": _f(p.get("returnOnEquity")), "liq": _f(p.get("liquidationPx")),
				"margin": _f(p.get("marginUsed")),
				"lev": int((lev as Dictionary).get("value", 1)) if lev is Dictionary else 1,
				"cross": str((lev as Dictionary).get("type", "cross")) == "cross" if lev is Dictionary else true,
			})
	# Biggest first.
	positions.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return absf(float(a["value"])) > absf(float(b["value"])))
	return {
		"value": _f(ms.get("accountValue")), "ntl": _f(ms.get("totalNtlPos")),
		"margin": _f(ms.get("totalMarginUsed")), "withdrawable": _f(j.get("withdrawable")),
		"positions": positions, "at": int(Time.get_unix_time_from_system()),
	}


# --- Formatting --------------------------------------------------------------------------------------

## A price the way Hyperliquid shows it: five significant figures, grouped.
static func fmt_px(v: float) -> String:
	return group(v, px_digits(v)) if v != 0.0 else "0"


## Decimals a price of this size gets (five significant figures).
static func px_digits(v: float) -> int:
	if v == 0.0:
		return 0
	return clampi(4 - floori(log(absf(v)) / log(10.0)), 0, 8)


## A size in coins, to the coin's own precision.
static func fmt_sz(v: float, decimals: int) -> String:
	return group(v, clampi(decimals, 0, 8))


## $1.23B, $845.2M, $12.4K, $950.00
static func fmt_usd_short(v: float) -> String:
	var a := absf(v)
	var s := "-" if v < 0.0 else ""
	if a >= 1e9:
		return s + "$%.2fB" % (a / 1e9)
	if a >= 1e6:
		return s + "$%.1fM" % (a / 1e6)
	if a >= 1e4:
		return s + "$%.1fK" % (a / 1e3)
	return s + "$" + group(a, 2)


## $1,234.56, with a sign when asked (for P&L).
static func fmt_usd(v: float, signed: bool = false) -> String:
	var sign := ""
	if v < 0.0:
		sign = "−"
	elif signed:
		sign = "+"
	return sign + "$" + group(absf(v), 2)


static func group(v: float, digits: int) -> String:
	var a := snappedf(absf(v), pow(10.0, -digits))
	var whole := int(floor(a + 0.0000001))
	var s := str(whole)
	var groups := PackedStringArray()
	while s.length() > 3:
		groups.insert(0, s.substr(s.length() - 3))
		s = s.substr(0, s.length() - 3)
	groups.insert(0, s)
	var out := ",".join(groups)
	if digits > 0:
		out += (("%." + str(digits) + "f") % maxf(0.0, a - whole)).substr(1)
	return ("-" if v < 0.0 and a > 0.0 else "") + out


static func short_address(a: String) -> String:
	return a.substr(0, 6) + "…" + a.substr(a.length() - 4) if a.length() > 12 else a


# --- Screenshots and tests ------------------------------------------------------------------------

## Uses this data instead of the network: any of mids, ctxs, meta, sparks,
## candles, book, trades, account.
func set_mock(d: Dictionary) -> void:
	_mock = true
	set_process(false)
	if _ws:
		_ws.close()
		_ws = null
	for k in d:
		set(k, d[k])
	live = true
	status_changed.emit()
	prices_changed.emit()
	market_changed.emit()
	account_changed.emit()
