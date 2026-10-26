class_name Markets
extends Node
## Stock, index and crypto prices for the desktop, from Yahoo Finance's public
## chart endpoint: free and keyless. Fetched only while someone is looking,
## at most every few minutes, and cached on disk so the numbers are there
## straight away next time (and stay put while offline).

signal changed

const CACHE := "user://markets.json"
const REFRESH := 5 * 60
const RETRY := 90
const HOSTS := ["https://query1.finance.yahoo.com", "https://query2.finance.yahoo.com"]
const CHART := "/v8/finance/chart/%s?range=1d&interval=5m&includePrePost=false"
## Yahoo turns away requests that don't look like a browser.
const UA := "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36"
const MAX_POINTS := 96
## Friendlier names for the symbols people actually type.
const NAMES := {
	"^GSPC": "S&P 500", "^IXIC": "Nasdaq", "^DJI": "Dow Jones", "^RUT": "Russell 2000",
	"^FTSE": "FTSE 100", "^GDAXI": "DAX", "^FCHI": "CAC 40", "^STOXX50E": "Euro Stoxx 50",
	"PSI20.LS": "PSI", "^N225": "Nikkei 225", "^HSI": "Hang Seng", "^VIX": "VIX",
	"BTC-USD": "Bitcoin", "ETH-USD": "Ethereum", "SOL-USD": "Solana",
	"EURUSD=X": "EUR / USD", "GBPUSD=X": "GBP / USD", "GC=F": "Gold", "CL=F": "Crude oil",
}

## symbol -> {symbol, name, price, prev, currency, points, at}
var quotes := {}
var busy := false
## Why the last request failed (for logs), "" when it worked.
var last_error := ""
var offline := false
var _last_try := 0


func _ready() -> void:
	_load()


static func symbols() -> PackedStringArray:
	var out := PackedStringArray()
	for s in Settings.get_value("market_symbols"):
		var t := str(s).strip_edges().to_upper()
		if t != "" and not out.has(t):
			out.append(t)
	return out


## "aapl, ^gspc  btc-usd" -> ["AAPL", "^GSPC", "BTC-USD"]
static func parse_symbols(text: String) -> PackedStringArray:
	var out := PackedStringArray()
	for part in text.replace(";", ",").replace(" ", ",").split(",", false):
		var t := part.strip_edges().to_upper()
		if t != "" and not out.has(t) and out.size() < 8:
			out.append(t)
	return out


static func label_for(sym: String) -> String:
	if NAMES.has(sym):
		return NAMES[sym]
	return sym.trim_prefix("^").get_slice("=", 0)


func _now() -> int:
	return int(Time.get_unix_time_from_system())


## Fetches whatever is stale. Cheap to call often: it does nothing in between.
func refresh(force: bool = false) -> void:
	if busy or (App.smoke_test and not force):
		return
	var syms := symbols()
	var now := _now()
	var stale := false
	for s in syms:
		if now - int((quotes.get(s, {}) as Dictionary).get("at", 0)) >= REFRESH:
			stale = true
	if not force and (not stale or (offline and now - _last_try < RETRY)):
		return
	busy = true
	_last_try = now
	var ok := 0
	for s in syms:
		var q := await _fetch(s)
		if not q.is_empty():
			quotes[s] = q
			ok += 1
			changed.emit()
	offline = ok == 0 and not syms.is_empty()
	busy = false
	if ok > 0:
		_save()
	changed.emit()


func _fetch(sym: String) -> Dictionary:
	for host in HOSTS:
		var http := HTTPRequest.new()
		http.timeout = 10.0
		http.use_threads = true
		add_child(http)
		var out := {}
		if http.request(host + CHART % sym.uri_encode(), ["User-Agent: " + UA, "Accept: application/json"]) == OK:
			var res: Array = await http.request_completed
			last_error = "" if int(res[0]) == HTTPRequest.RESULT_SUCCESS and int(res[1]) == 200 else "result %d, HTTP %d" % [int(res[0]), int(res[1])]
			if last_error == "":
				out = parse_chart(JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8()))
		http.queue_free()
		if out.is_empty() and last_error == "":
			last_error = "nothing usable in the answer"
		if not out.is_empty():
			out["at"] = _now()
			return out
	return {}


## One Yahoo chart answer -> a quote, or {} if it isn't one.
static func parse_chart(j: Variant) -> Dictionary:
	if not (j is Dictionary) or not (j.get("chart") is Dictionary):
		return {}
	var results: Variant = j["chart"].get("result")
	if not (results is Array) or results.is_empty() or not (results[0] is Dictionary):
		return {}
	var r: Dictionary = results[0]
	var meta: Dictionary = r.get("meta", {}) if r.get("meta") is Dictionary else {}
	if meta.get("regularMarketPrice") == null:
		return {}
	var closes: Array = []
	var ind: Variant = r.get("indicators")
	if ind is Dictionary and ind.get("quote") is Array and not ind["quote"].is_empty() and ind["quote"][0] is Dictionary:
		var c: Variant = ind["quote"][0].get("close")
		if c is Array:
			closes = c
	var points := []
	for v in closes:
		if v != null:
			points.append(float(v))
	# Keep the line light: an even sample of the day.
	if points.size() > MAX_POINTS:
		var thin := []
		for i in MAX_POINTS:
			thin.append(points[int(round(float(i) * (points.size() - 1) / (MAX_POINTS - 1)))])
		points = thin
	var price := float(meta["regularMarketPrice"])
	var prev: Variant = meta.get("chartPreviousClose", meta.get("previousClose"))
	var sym := str(meta.get("symbol", ""))
	var name := str(meta.get("shortName", meta.get("longName", "")))
	# Today's regular session, to tell open from closed.
	var session := {}
	var period: Variant = meta.get("currentTradingPeriod")
	if period is Dictionary and period.get("regular") is Dictionary:
		session = period["regular"]
	return {
		"open_from": int(session.get("start", 0)), "open_to": int(session.get("end", 0)),
		"symbol": sym, "name": name, "price": price,
		"prev": float(prev) if prev != null else (points[0] if not points.is_empty() else price),
		"currency": str(meta.get("currency", "")), "points": points,
	}


## True while the quote's market is in its regular session, false when it's
## closed, null when Yahoo didn't say.
static func is_open(q: Dictionary) -> Variant:
	var a := int(q.get("open_from", 0))
	var b := int(q.get("open_to", 0))
	if a <= 0 or b <= a:
		return null
	var now := int(Time.get_unix_time_from_system())
	return now >= a and now < b


static func format_price(v: float, currency: String = "") -> String:
	var digits := 2 if absf(v) < 10000.0 else 0
	if absf(v) < 1.0:
		digits = 4
	var a := snappedf(absf(v), pow(10.0, -digits))
	var whole := int(floor(a + 0.0000001))
	var groups := PackedStringArray()
	var s := str(whole)
	while s.length() > 3:
		groups.insert(0, s.substr(s.length() - 3))
		s = s.substr(0, s.length() - 3)
	groups.insert(0, s)
	var out := ",".join(groups)
	if digits > 0:
		# "%.2f" % 0.5 is "0.50": keep only the decimals.
		out += (("%." + str(digits) + "f") % maxf(0.0, a - whole)).substr(1)
	var sym := {"USD": "$", "EUR": "€", "GBP": "£", "JPY": "¥"}.get(currency, "")
	return ("-" if v < 0.0 else "") + sym + out


func _load() -> void:
	if App.smoke_test or not FileAccess.file_exists(CACHE):
		return
	var j: Variant = JSON.parse_string(FileAccess.get_file_as_string(CACHE))
	if j is Dictionary and j.get("quotes") is Dictionary:
		quotes = j["quotes"]


func _save() -> void:
	var f := FileAccess.open(CACHE, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"quotes": quotes}))


## Screenshots and tests: these quotes instead of fetching any.
func set_mock(q: Dictionary) -> void:
	quotes = q
	offline = false
	changed.emit()
