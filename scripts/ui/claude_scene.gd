class_name ClaudeScene
extends RefCounted
## A little act Claude's jelly (ClaudeBlob) puts on while it works on
## something, picked from what the conversation is about: a chart and coins
## for money, chalk on a board for physics and maths, a laptop for code,
## a pot and a chef's hat for cooking, a telescope under the stars, and so on.
##
## Each one is a prop on the roof's floor (drawn behind the jelly), things it
## wears or holds (drawn in front), and where it stands, looks and reaches.
## Everything is drawn with plain canvas calls in the roof's own pixels, and
## all of it is made up as it goes, so no two runs look the same. While
## Claude is busy the act keeps going; once the reply is in it gets a small
## finish (a check on the laptop, a bloom, the candle blown out) and is put away.

const TOPICS := ["finance", "physics", "math", "code", "music", "art", "science", "space", "weather", "food", "games", "sport", "travel", "books", "health", "nature", "party", "film", "language", "planning", "security", "ai"]

## How wide the prop on the floor is (0: nothing on the floor) and how far
## left of its middle the jelly stands.
const STAGE := {
	"finance": [80.0, 66.0], "physics": [92.0, 30.0], "math": [92.0, 30.0], "code": [62.0, 56.0],
	"art": [46.0, 50.0], "science": [34.0, 44.0], "space": [40.0, 37.0], "food": [40.0, 46.0],
	"games": [64.0, 60.0], "travel": [36.0, 46.0], "books": [30.0, 52.0], "health": [60.0, 58.0],
	"nature": [30.0, 46.0], "party": [36.0, 46.0], "film": [26.0, 40.0], "planning": [50.0, 54.0],
	"security": [30.0, 46.0],
}

const INK := Color(0.035, 0.06, 0.11)
const CHALK := Color(0.95, 0.97, 0.93, 0.9)
const GOLD := Color(1.0, 0.8, 0.33)
const UP := Color(0.38, 0.88, 0.62)
const DOWN := Color(1.0, 0.43, 0.46)
const PAPER := Color(0.97, 0.96, 0.92)
const PALETTE := [Color(1.0, 0.45, 0.5), Color(1.0, 0.78, 0.3), Color(0.42, 0.85, 0.6), Color(0.38, 0.7, 1.0), Color(0.74, 0.55, 1.0), Color(1.0, 0.6, 0.85)]

var kind := ""
## Seconds since it started.
var t := 0.0
## How far it's shown, 0..1 (pops in and out).
var k := 0.0
## Wanted: false puts it away.
var on := true
## Claude still working on it; false plays the finish.
var busy := true
## Paused while Claude waits for an OK (the jelly goes to the middle).
var paused := false
## The prop's middle on the floor, in roof pixels.
var at := 0.0
var floor_y := 0.0
## The roof's width, for things that use all of it (stars, confetti).
var width := 400.0
var mood := "calm"
var accent := Color(0.22, 0.84, 0.77)
var accent2 := Color(0.25, 0.55, 1.0)
## Bumped when the jelly should bob (a header, a heartbeat).
var kicks := 0
## Set by the jelly each frame: where it is and where its hand ended up.
var me := {}

var _rng := RandomNumberGenerator.new()
## Seconds of real work, only while the jelly is at its place.
var _w := 0.0
var _fin := 0.0
var _parts: Array = []
var _s := {}
var _fill: StyleBoxFlat


static func has(topic: String) -> bool:
	return TOPICS.has(topic)


static func make(topic: String, blob_x: float, lo: float, hi: float, floor_at: float, wide: float) -> ClaudeScene:
	var s := ClaudeScene.new()
	s.kind = topic
	s.floor_y = floor_at
	s.width = wide
	s._rng.randomize()
	var st: Array = STAGE.get(topic, [0.0, 0.0])
	if float(st[0]) > 0.0:
		var half := float(st[0]) * 0.5
		# The jelly stands on the left of its prop.
		s.at = clampf(blob_x + float(st[1]), maxf(lo + float(st[1]), lo + half - 20.0), hi - half + 14.0)
	else:
		s.at = clampf(blob_x, lo, hi)
	s._setup()
	return s


## Where the jelly stands for this act.
func stand() -> float:
	var st: Array = STAGE.get(kind, [0.0, 0.0])
	if float(st[0]) <= 0.0:
		return at
	return at - float(st[1])


func has_prop() -> bool:
	return float(STAGE.get(kind, [0.0])[0]) > 0.0


## Ends the act after its finish has played.
func finished() -> bool:
	return not busy and _fin > 7.0


func done() -> bool:
	return not on and k <= 0.001


# --- Running ---------------------------------------------------------------------------------

func step(dt: float, arrived: bool) -> void:
	t += dt
	k = move_toward(k, 1.0 if on else 0.0, dt * (3.2 if on else 4.0))
	if arrived and not paused:
		_w += dt * (1.0 if busy else 1.6)
	if not busy:
		_fin += dt
	var m := "_step_" + kind
	if has_method(m):
		call(m, dt, arrived and not paused)
	for p: Dictionary in _parts:
		p["age"] = float(p["age"]) + dt
		var v: Vector2 = p["v"]
		v.y += float(p.get("g", 0.0)) * dt
		v *= 1.0 - float(p.get("drag", 0.0)) * dt
		p["v"] = v
		p["p"] = (p["p"] as Vector2) + v * dt
		p["rot"] = float(p.get("rot", 0.0)) + float(p.get("spin", 0.0)) * dt
	_parts = _parts.filter(func(p: Dictionary) -> bool: return float(p["age"]) < float(p["life"]))


## Where the hand reaches (roof pixels), or INF for no arm.
func hand() -> Vector2:
	var m := "_hand_" + kind
	if paused or not has_method(m):
		return Vector2.INF
	return call(m)


## Where the jelly looks (roof pixels), or INF for its own way.
func look() -> Vector2:
	var m := "_look_" + kind
	if paused or not has_method(m):
		return Vector2.INF
	return call(m)


## A face of its own for the act, used while Claude's mood is calm.
func face() -> String:
	match kind:
		"music":
			return "happy" if fmod(t, 9.0) < 6.0 else "whistle"
		"party":
			return "excited"
		"space":
			return "amazed" if _s.get("gazing", false) else "curious"
		"film":
			return "chomp" if _s.get("chomp", 0.0) > 0.0 else "curious"
		"games":
			return "determined"
		"code", "physics", "math", "planning", "security":
			return "focused"
		"sport":
			return "happy" if not busy else "determined"
		"nature", "art", "food":
			return "happy"
		"weather":
			return "concerned" if _s.get("rain", true) else "happy"
		"language":
			return "playful"
		"books":
			return "thoughtful"
	return ""


## Squash added to the jelly's rest pose (rhythm, effort).
func bob() -> float:
	match kind:
		"music":
			if Music.on and Music.presence > 0.3:
				return Music.pulse * -0.07
			return _beat(1.0) * -0.06
		"health":
			return _beat(0.85) * 0.05
		"games":
			return sin(t * 9.0) * 0.012
	return 0.0


## Lean added to the jelly's (a sway to the music, dodging in a game).
func lean() -> float:
	match kind:
		"music":
			if Music.on and Music.presence > 0.3:
				return sin(Music.beat_phase * PI) * 0.09 * (1.0 if int(t * Music.bpm / 60.0) % 2 == 0 else -1.0)
			return sin(t * PI * 2.0 / 2.0) * 0.09
		"games":
			return clampf(float(_s.get("dodge", 0.0)), -0.2, 0.2)
	return 0.0


## The mouth moves as if talking.
func talking() -> bool:
	return kind == "language" and fmod(t, 2.6) < 1.2


func _beat(period: float) -> float:
	var ph := fmod(t, period) / period
	return exp(-ph * 9.0)


# --- Drawing ---------------------------------------------------------------------------------

## The prop, behind the jelly.
func draw_back(ci: CanvasItem) -> void:
	var m := "_back_" + kind
	if not has_method(m):
		return
	var pop := _pop()
	ci.draw_set_transform(Vector2(at, floor_y), 0.0, Vector2(pop, pop))
	if has_prop():
		_shadow(ci, 0.0, float(STAGE[kind][0]) * 0.55)
	call(m, ci)
	ci.draw_set_transform(Vector2.ZERO)


## What it wears and holds, and what flies about, in front of it.
func draw_front(ci: CanvasItem) -> void:
	var m := "_front_" + kind
	if has_method(m):
		call(m, ci)
	ci.draw_set_transform(Vector2.ZERO)
	_draw_parts(ci)


func _pop() -> float:
	var e := k * k * (3.0 - 2.0 * k)
	return lerpf(0.6, 1.0, e)


func _shadow(ci: CanvasItem, x: float, w: float) -> void:
	for i in 3:
		var r := w * (1.0 - i * 0.24)
		_ellipse(ci, Vector2(x, 0.5), r, r * 0.16, Color(0, 0, 0, 0.07))


func _ellipse(ci: CanvasItem, c: Vector2, rx: float, ry: float, col: Color) -> void:
	ci.draw_colored_polygon(_oval(c, rx, ry, 0.0, TAU, 28), col)


func _oval(c: Vector2, rx: float, ry: float, a0: float, a1: float, n: int, rot: float = 0.0) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n + 1:
		var a := lerpf(a0, a1, float(i) / n)
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry).rotated(rot))
	return pts


func _disc(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	ci.draw_circle(c, r, col, true, -1.0, true)


func _ring(ci: CanvasItem, c: Vector2, r: float, col: Color, w: float = 1.0) -> void:
	ci.draw_arc(c, r, 0.0, TAU, maxi(16, int(r * 3.0)), col, w, true)


func _line(ci: CanvasItem, a: Vector2, b: Vector2, col: Color, w: float = 1.0) -> void:
	ci.draw_line(a, b, col, w, true)


func _poly(ci: CanvasItem, pts: PackedVector2Array, col: Color, w: float = 1.0) -> void:
	if pts.size() >= 2:
		ci.draw_polyline(pts, col, w, true)


## Dark glass, like the idea bubble.
func _panel(ci: CanvasItem, r: Rect2, radius: int = 7, bg: Color = Color(0.075, 0.1, 0.14, 0.9)) -> void:
	if _fill == null:
		_fill = StyleBoxFlat.new()
		_fill.anti_aliasing = true
		_fill.border_color = Color(1, 1, 1, 0.1)
		_fill.set_border_width_all(1)
	_fill.bg_color = bg
	_fill.set_corner_radius_all(radius)
	ci.draw_style_box(_fill, r)


func _text(ci: CanvasItem, pos: Vector2, s: String, sz: int, col: Color, italic: bool = false, weight: int = 600) -> void:
	var f: Font = Kit.italic_font() if italic else Kit.font(weight)
	ci.draw_string(f, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)


func _text_w(s: String, sz: int, italic: bool = false, weight: int = 600) -> float:
	var f: Font = Kit.italic_font() if italic else Kit.font(weight)
	return f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x


func _heart(ci: CanvasItem, c: Vector2, s: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 24:
		var a := float(i) / 24.0 * TAU
		var x := 16.0 * pow(sin(a), 3.0)
		var y := 13.0 * cos(a) - 5.0 * cos(2.0 * a) - 2.0 * cos(3.0 * a) - cos(4.0 * a)
		pts.append(c + Vector2(x, -y) * s / 32.0)
	ci.draw_colored_polygon(pts, col)


func _sparkle(ci: CanvasItem, c: Vector2, s: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 8:
		var a := float(i) / 8.0 * TAU - PI * 0.5
		var r := s if i % 2 == 0 else s * 0.28
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	ci.draw_colored_polygon(pts, col)


func _note(ci: CanvasItem, c: Vector2, s: float, col: Color, double: bool) -> void:
	_ellipse_rot(ci, c, s * 0.32, s * 0.23, -0.4, col)
	var top := c + Vector2(s * 0.28, -s)
	_line(ci, c + Vector2(s * 0.28, -s * 0.05), top, col, maxf(1.0, s * 0.11))
	if double:
		var c2 := c + Vector2(s * 0.7, -s * 0.15)
		_ellipse_rot(ci, c2, s * 0.32, s * 0.23, -0.4, col)
		_line(ci, c2 + Vector2(s * 0.28, -s * 0.05), top + Vector2(s * 0.7, -s * 0.15), col, maxf(1.0, s * 0.11))
		_line(ci, top, top + Vector2(s * 0.7, -s * 0.15), col, maxf(1.4, s * 0.2))
	else:
		_poly(ci, PackedVector2Array([top, top + Vector2(s * 0.3, s * 0.25), top + Vector2(s * 0.34, s * 0.55)]), col, maxf(1.0, s * 0.12))


func _ellipse_rot(ci: CanvasItem, c: Vector2, rx: float, ry: float, rot: float, col: Color) -> void:
	ci.draw_colored_polygon(_oval(c, rx, ry, 0.0, TAU, 20, rot), col)


func _part(kind_: String, p: Vector2, v: Vector2, life: float, extra: Dictionary = {}) -> void:
	var d := {"k": kind_, "p": p, "v": v, "age": 0.0, "life": life}
	d.merge(extra, true)
	_parts.append(d)


func _draw_parts(ci: CanvasItem) -> void:
	for p: Dictionary in _parts:
		var u := float(p["age"]) / float(p["life"])
		var fade := clampf(minf(u * 6.0, (1.0 - u) * 3.0), 0.0, 1.0)
		var pos: Vector2 = p["p"]
		var col: Color = p.get("c", Color.WHITE)
		col.a *= fade
		var sz := float(p.get("s", 4.0))
		match str(p["k"]):
			"note":
				_note(ci, pos, sz, col, bool(p.get("two", false)))
			"heart":
				_heart(ci, pos, sz, col)
			"spark":
				_sparkle(ci, pos, sz * (0.6 + 0.4 * sin(float(p["age"]) * 9.0)), col)
			"dot":
				_disc(ci, pos, sz, col)
			"puff":
				col.a *= 0.5
				_disc(ci, pos, sz * (0.6 + u), col)
			"confetti":
				var a := float(p.get("rot", 0.0))
				var w := Vector2(cos(a), sin(a)) * sz
				var h := Vector2(-sin(a), cos(a)) * sz * 0.45 * absf(sin(float(p["age"]) * 6.0 + a))
				ci.draw_colored_polygon(PackedVector2Array([pos - w - h, pos + w - h, pos + w + h, pos - w + h]), col)
			"coin":
				var squeeze := absf(cos(float(p.get("rot", 0.0))))
				_ellipse(ci, pos, sz * maxf(squeeze, 0.12), sz, GOLD.darkened(0.25) * Color(1, 1, 1, col.a))
				_ellipse(ci, pos, sz * maxf(squeeze, 0.12) * 0.72, sz * 0.72, GOLD * Color(1, 1, 1, col.a))
			"text":
				var s := str(p.get("t", ""))
				var f := Kit.font(700)
				ci.draw_string_outline(f, pos, s, HORIZONTAL_ALIGNMENT_CENTER, -1, int(sz), 3, Color(INK, col.a * 0.6))
				ci.draw_string(f, pos, s, HORIZONTAL_ALIGNMENT_CENTER, -1, int(sz), col)
			"food":
				var a := float(p.get("rot", 0.0))
				match int(p.get("i", 0)):
					0:
						var dir := Vector2(cos(a), sin(a))
						ci.draw_colored_polygon(PackedVector2Array([pos - dir * 5.0 + dir.orthogonal() * 2.2, pos - dir * 5.0 - dir.orthogonal() * 2.2, pos + dir * 5.0]), Color(1.0, 0.55, 0.2, col.a))
						_line(ci, pos - dir * 5.0, pos - dir * 7.5, Color(0.4, 0.8, 0.4, col.a), 1.6)
					1:
						_disc(ci, pos, 3.6, Color(0.95, 0.3, 0.3, col.a))
						_disc(ci, pos + Vector2(-1.2, -1.2), 1.0, Color(1, 1, 1, col.a * 0.6))
					_:
						_ellipse_rot(ci, pos, 4.0, 1.8, a, Color(0.4, 0.82, 0.42, col.a))


# --- Where the jelly is (set by ClaudeBlob) ---------------------------------------------------

func _me(key: String, fallback: Variant) -> Variant:
	return me.get(key, fallback)


func _hand_now() -> Vector2:
	return _me("hand", Vector2(at, floor_y - 30.0))


func _head() -> Vector2:
	return _me("head", Vector2(stand(), floor_y - 46.0))


func _face() -> Vector2:
	return _me("face", Vector2(stand(), floor_y - 26.0))


func _local(v: Vector2) -> Vector2:
	return Vector2(at, floor_y) + v


func _setup() -> void:
	match kind:
		"finance":
			_s = {"candles": [], "next": 0.0, "live": 0.0, "price": 0.0, "coins": 0, "tap": 0.0}
			var v := 0.0
			for i in 5:
				var c := _rng.randf_range(-0.6, 0.9)
				_s["candles"].append(_candle(v, v + c))
				v += c
			_s["price"] = v
		"physics", "math":
			_s = {"lesson": _rng.randi() % 3, "wipe": -1.0}
		"code":
			_s = {"lines": [], "line": 0, "chars": 0.0}
			for i in 7:
				_s["lines"].append(_code_line())
		"art":
			_s = {"order": _rng.randi() % 2}
		"science":
			_s = {"hue": _rng.randf(), "to": _rng.randf(), "pour": 0.0, "fizz": 0.0}
		"space":
			var stars := []
			for i in 26:
				stars.append([_rng.randf_range(6.0, width - 6.0), _rng.randf_range(4.0, 40.0), _rng.randf_range(0.6, 1.6), _rng.randf() * TAU])
			_s = {"stars": stars, "shoot": 2.0, "gazing": false}
		"weather":
			_s = {"rain": true, "cloud_x": at}
		"food":
			_s = {"toss": 2.0}
		"games":
			_s = {"obs": [70.0, 120.0], "y": 0.0, "vy": 0.0, "score": 0, "dodge": 0.0}
		"sport":
			_s = {"u": 0.0, "h": 26.0, "y": 30.0}
		"travel":
			_s = {"spin": 0.6, "rot": 0.0, "swipe": 3.0}
		"books":
			_s = {"flip": 3.0}
		"nature":
			_s = {"grow": 0.0}
		"party":
			_s = {"out": false}
		"film":
			_s = {"eat": 1.5, "chomp": 0.0}
		"language":
			_s = {"next": 0.3, "i": _rng.randi() % 9}
		"planning":
			_s = {"card": 0}
		"security":
			_s = {}


# --- Finance: a live chart, and coins for a good tick ------------------------------------------

func _candle(o: float, c: float) -> Array:
	return [o, c, maxf(o, c) + _rng.randf_range(0.05, 0.35), minf(o, c) - _rng.randf_range(0.05, 0.35)]


func _trend() -> float:
	return -0.32 if mood == "sorry" or mood == "concerned" else 0.3


func _step_finance(dt: float, working: bool) -> void:
	var candles: Array = _s["candles"]
	var last: Array = candles[candles.size() - 1]
	# The live candle wanders, leaning with the trend.
	var drift := _trend() * (2.4 if not busy else 1.0)
	_s["price"] = float(_s["price"]) + (drift + _rng.randf_range(-1.6, 1.6)) * dt * 1.1
	last[1] = _s["price"]
	last[2] = maxf(float(last[2]), float(last[1]))
	last[3] = minf(float(last[3]), float(last[1]))
	_s["tap"] = maxf(0.0, float(_s["tap"]) - dt * 4.0)
	if working and _w > float(_s["next"]):
		_s["next"] = _w + _rng.randf_range(0.75, 1.1)
		var up := float(last[1]) > float(last[0])
		candles.append(_candle(float(last[1]), float(last[1])))
		if candles.size() > 9:
			candles.pop_front()
		_s["tap"] = 1.0
		if up and _rng.randf() < 0.7:
			# A coin jumps out of the chart onto the pile.
			var from := _local(Vector2(_rng.randf_range(-10.0, 24.0), -48.0))
			_part("coin", from, Vector2(_rng.randf_range(-34.0, -20.0), -70.0), 0.85, {"g": 260.0, "spin": 12.0, "s": 4.2})
			_s["coins"] = mini(int(_s["coins"]) + 1, 6)


func _price_y(v: float, lo: float, hi: float) -> float:
	return lerpf(-12.0, -42.0, (v - lo) / maxf(hi - lo, 0.001))


func _back_finance(ci: CanvasItem) -> void:
	_panel(ci, Rect2(-36, -54, 72, 50))
	var candles: Array = _s["candles"]
	var lo := INF
	var hi := -INF
	for c: Array in candles:
		lo = minf(lo, float(c[3]))
		hi = maxf(hi, float(c[2]))
	var pad := (hi - lo) * 0.12 + 0.1
	lo -= pad
	hi += pad
	for i in 3:
		var gy := -14.0 - i * 13.0
		_line(ci, Vector2(-30, gy), Vector2(30, gy), Color(1, 1, 1, 0.06))
	var n := candles.size()
	var step_x := 6.6
	var x0 := 24.0 - (n - 1) * step_x
	var closes := PackedVector2Array()
	for i in n:
		var c: Array = candles[i]
		var x := x0 + i * step_x
		var col := UP if float(c[1]) >= float(c[0]) else DOWN
		_line(ci, Vector2(x, _price_y(float(c[2]), lo, hi)), Vector2(x, _price_y(float(c[3]), lo, hi)), Color(col, 0.75), 1.0)
		var y0 := _price_y(float(c[0]), lo, hi)
		var y1 := _price_y(float(c[1]), lo, hi)
		ci.draw_rect(Rect2(x - 2.0, minf(y0, y1), 4.0, maxf(absf(y1 - y0), 1.2)), col)
		closes.append(Vector2(x, y1))
	_poly(ci, closes, Color(accent, 0.55), 1.0)
	var live: Array = candles[n - 1]
	var ly := _price_y(float(live[1]), lo, hi)
	var lc := UP if float(live[1]) >= float(live[0]) else DOWN
	for i in 6:
		_line(ci, Vector2(-30 + i * 10.0, ly), Vector2(-26 + i * 10.0, ly), Color(lc, 0.3), 1.0)
	_disc(ci, Vector2(x0 + (n - 1) * step_x, ly), 1.6 + sin(t * 6.0) * 0.4, lc)
	var first: Array = candles[0]
	var pct := (float(live[1]) - float(first[0])) * 0.9
	var label := "%s%.1f%%" % ["+" if pct >= 0.0 else "", pct]
	_text(ci, Vector2(30 - _text_w(label, 8), -45), label, 8, UP if pct >= 0.0 else DOWN)
	_text(ci, Vector2(-30, -45), "OAZY", 7, Color(1, 1, 1, 0.45), false, 700)
	# The pile of coins it has made, against the chart's corner.
	for i in int(_s["coins"]):
		var cy := -2.0 - i * 2.6
		var cx := -38.0 + (i % 2) * 0.8
		_ellipse(ci, Vector2(cx, cy + 0.9), 5.4, 1.9, GOLD.darkened(0.35))
		_ellipse(ci, Vector2(cx, cy), 5.4, 1.9, GOLD)


func _hand_finance() -> Vector2:
	var tap := float(_s.get("tap", 0.0))
	return _local(Vector2(-33.0 + tap * 1.5, -30.0 + sin(t * 2.0) * 6.0 - tap * 3.0))


func _look_finance() -> Vector2:
	return _local(Vector2(20.0, -32.0))


# --- Physics and maths: chalk on a board ------------------------------------------------------

## Each lesson is a list of strokes, drawn in order: [text, at, size] or a
## list of points. Laid out for the jelly standing on the board's left.
func _lesson() -> Array:
	var L := int(_s["lesson"])
	if kind == "physics":
		match L:
			0:
				return [["F = ma", Vector2(-14, -60), 10], _arc_pts(Vector2(22, -30), 16.0, 22.0), [Vector2(-2, -29), Vector2(44, -29)], ["g", Vector2(36, -58), 8]]
			1:
				return [["E = mc²", Vector2(-14, -60), 10], _oval(Vector2(26, -44), 13, 4.5, 0.0, TAU, 30, 0.0), _oval(Vector2(26, -44), 13, 4.5, 0.0, TAU, 30, PI / 3.0), _oval(Vector2(26, -44), 13, 4.5, 0.0, TAU, 30, -PI / 3.0)]
			_:
				return [["v = fλ", Vector2(-14, -60), 10], _wave(Vector2(-6, -36), 48.0, 6.0, 2.0), ["λ", Vector2(8, -44), 8]]
	match L:
		0:
			return [["a² + b² = c²", Vector2(-14, -60), 9], [Vector2(6, -30), Vector2(40, -30), Vector2(40, -52), Vector2(6, -30)], [Vector2(36, -30), Vector2(36, -34), Vector2(40, -34)], ["c", Vector2(16, -42), 7]]
		1:
			return [["y = x²", Vector2(-14, -60), 10], [Vector2(-2, -30), Vector2(42, -30)], [Vector2(20, -28), Vector2(20, -54)], _parabola(Vector2(20, -31), 16.0, 21.0)]
		_:
			return [["π ≈ 3.14", Vector2(-14, -60), 10], _oval(Vector2(24, -40), 11.0, 11.0, -PI * 0.5, PI * 1.5, 34, 0.0), [Vector2(24, -40), Vector2(35, -40)], ["r", Vector2(27, -42), 7]]


func _arc_pts(c: Vector2, rx: float, ry: float) -> PackedVector2Array:
	# A thrown ball's path.
	var pts := PackedVector2Array()
	for i in 21:
		var u := float(i) / 20.0
		pts.append(c + Vector2((u - 0.5) * rx * 2.0, -ry * 4.0 * u * (1.0 - u) + 1.0))
	return pts


func _parabola(c: Vector2, half: float, h: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 21:
		var u := float(i) / 20.0 * 2.0 - 1.0
		pts.append(c + Vector2(u * half, -u * u * h))
	return pts


func _wave(from: Vector2, w: float, amp: float, waves: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 41:
		var u := float(i) / 40.0
		pts.append(from + Vector2(u * w, -sin(u * waves * TAU) * amp))
	return pts


## How long each stroke takes to draw.
func _stroke_len(s: Variant) -> float:
	if s is Array and s.size() == 3 and s[0] is String:
		return 0.18 * str(s[0]).length() + 0.2
	var pts: PackedVector2Array = PackedVector2Array(s)
	var l := 0.0
	for i in range(1, pts.size()):
		l += pts[i].distance_to(pts[i - 1])
	return 0.25 + l / 70.0


## How far through the lesson we are: [stroke index, 0..1 through it], and
## where the chalk is.
func _board_pen() -> Array:
	var strokes := _lesson()
	var left := _w - float(_s.get("began", 0.0))
	for i in strokes.size():
		var d := _stroke_len(strokes[i])
		if left < d:
			return [i, left / d, _stroke_point(strokes[i], left / d)]
		left -= d
	return [strokes.size(), 1.0, Vector2(-10, -40)]


func _stroke_point(s: Variant, u: float) -> Vector2:
	if s is Array and s.size() == 3 and s[0] is String:
		var txt := str(s[0])
		var n := int(ceil(u * txt.length()))
		return (s[1] as Vector2) + Vector2(_text_w(txt.left(n), int(s[2]), true), -2.0)
	var pts: PackedVector2Array = PackedVector2Array(s)
	var f := u * (pts.size() - 1)
	var i := mini(int(f), pts.size() - 2)
	return pts[i].lerp(pts[i + 1], f - i)


func _step_physics(dt: float, working: bool) -> void:
	_step_board(dt, working)


func _step_math(dt: float, working: bool) -> void:
	_step_board(dt, working)


func _step_board(_dt: float, _working: bool) -> void:
	var pen := _board_pen()
	var total := 0.0
	for s: Variant in _lesson():
		total += _stroke_len(s)
	var since := _w - float(_s.get("began", 0.0))
	if since > total + 3.0 and busy:
		# Wiped clean for the next one.
		_s["began"] = _w
		_s["lesson"] = (int(_s["lesson"]) + 1) % 3
		_s["wipe"] = t
	_s["pen"] = pen


func _back_physics(ci: CanvasItem) -> void:
	_back_board(ci)


func _back_math(ci: CanvasItem) -> void:
	_back_board(ci)


func _back_board(ci: CanvasItem) -> void:
	var wood := Color(0.6, 0.44, 0.3)
	_line(ci, Vector2(-34, -20), Vector2(-40, 0), wood.darkened(0.2), 2.0)
	_line(ci, Vector2(34, -20), Vector2(40, 0), wood.darkened(0.2), 2.0)
	_panel(ci, Rect2(-46, -76, 92, 56), 4, wood)
	_panel(ci, Rect2(-43, -73, 86, 50), 2, Color(0.11, 0.19, 0.17, 1.0))
	ci.draw_rect(Rect2(-44, -22, 88, 2.5), wood.lightened(0.1))
	# Old chalk dust.
	_ellipse(ci, Vector2(-14, -50), 26, 8, Color(1, 1, 1, 0.025))
	var pen: Array = _s.get("pen", [0, 0.0, Vector2.ZERO])
	var strokes := _lesson()
	var wipe := clampf((t - float(_s.get("wipe", -9.0))) / 0.5, 0.0, 1.0)
	var a := CHALK
	a.a *= wipe
	for i in mini(int(pen[0]) + 1, strokes.size()):
		var u := 1.0 if i < int(pen[0]) else float(pen[1])
		var s: Variant = strokes[i]
		if s is Array and s.size() == 3 and s[0] is String:
			var txt := str(s[0])
			_text(ci, s[1], txt.left(int(ceil(u * txt.length()))), int(s[2]), a, true)
		else:
			var pts: PackedVector2Array = PackedVector2Array(s)
			var f := u * (pts.size() - 1)
			var part := pts.slice(0, int(f) + 1)
			if int(f) < pts.size() - 1:
				part.append(pts[int(f)].lerp(pts[int(f) + 1], f - int(f)))
			_poly(ci, part, a, 1.3)
	# Once the drawing is up, it comes alive a little.
	if int(pen[0]) >= strokes.size():
		var L := int(_s["lesson"])
		if kind == "physics" and L == 0:
			var u := fmod(t * 0.6, 1.0)
			_disc(ci, _arc_pts(Vector2(22, -30), 16.0, 22.0)[int(u * 20.0)], 1.8, Color(accent, wipe))
		elif kind == "physics" and L == 1:
			for j in 3:
				var ang := t * 3.0 + j * 2.1
				_disc(ci, Vector2(26, -44) + Vector2(cos(ang) * 13.0, sin(ang) * 4.5).rotated(j * PI / 3.0 - PI / 3.0), 1.4, Color(accent, wipe))
			_disc(ci, Vector2(26, -44), 2.0, Color(1.0, 0.75, 0.4, wipe))
	if wipe < 1.0:
		# The eraser going over it.
		var ex := lerpf(-40.0, 40.0, wipe)
		_panel(ci, Rect2(ex - 6, -60, 12, 6), 2, Color(0.82, 0.74, 0.6, 1.0 - wipe * 0.5))


func _board_chalk() -> Vector2:
	var pen: Array = _s.get("pen", [0, 0.0, Vector2(-10, -40)])
	return _local(pen[2])


func _hand_physics() -> Vector2:
	return _board_hand()


func _hand_math() -> Vector2:
	return _board_hand()


func _board_hand() -> Vector2:
	var pen: Array = _s.get("pen", [0, 0.0, Vector2(-10, -40)])
	if int(pen[0]) >= _lesson().size():
		# Done: points at it, proud.
		return _local(Vector2(-8.0, -44.0 + sin(t * 2.0) * 2.0))
	return _board_chalk() + Vector2(0.0, 2.0)


func _look_physics() -> Vector2:
	return _board_chalk()


func _look_math() -> Vector2:
	return _board_chalk()


func _front_physics(ci: CanvasItem) -> void:
	_front_board(ci)


func _front_math(ci: CanvasItem) -> void:
	_front_board(ci)


func _front_board(ci: CanvasItem) -> void:
	var h := _hand_now()
	var pen: Array = _s.get("pen", [0, 0.0, Vector2.ZERO])
	if int(pen[0]) < _lesson().size():
		ci.draw_set_transform(h, -0.7, Vector2.ONE)
		ci.draw_rect(Rect2(-1.2, -4.0, 2.4, 6.0), Color(1, 1, 1, 0.95))
		ci.draw_set_transform(Vector2.ZERO)
		if _rng.randf() < 0.3:
			_part("dot", h + Vector2(0, -3), Vector2(_rng.randf_range(-6, 6), 10.0), 0.5, {"s": 0.6, "c": Color(1, 1, 1, 0.6), "g": 30.0})


# --- Code: a laptop typing itself full ---------------------------------------------------------

func _code_line() -> Array:
	var indent := _rng.randi() % 3
	var parts := []
	var cols := [Color(0.78, 0.6, 1.0), Color(0.5, 0.78, 1.0), Color(0.55, 0.9, 0.62), Color(1.0, 0.78, 0.45), Color(0.85, 0.88, 0.95, 0.75)]
	for i in _rng.randi_range(1, 3):
		parts.append([_rng.randf_range(4.0, 11.0), cols[_rng.randi() % cols.size()]])
	return [indent, parts]


func _line_w(l: Array) -> float:
	var w := 0.0
	for p: Array in l[1]:
		w += float(p[0]) + 1.6
	return w


func _step_code(dt: float, working: bool) -> void:
	if not working or not busy:
		return
	var lines: Array = _s["lines"]
	var l: Array = lines[int(_s["line"]) % lines.size()]
	_s["chars"] = float(_s["chars"]) + dt * 30.0
	if float(_s["chars"]) > _line_w(l) + 2.0:
		_s["chars"] = 0.0
		_s["line"] = int(_s["line"]) + 1
		if int(_s["line"]) >= 5:
			lines.pop_front()
			lines.append(_code_line())
			_s["line"] = 4


func _back_code(ci: CanvasItem) -> void:
	# Screen, then the keyboard deck in front of it.
	_panel(ci, Rect2(-27, -50, 54, 40), 4, Color(0.16, 0.18, 0.22))
	_panel(ci, Rect2(-24, -47, 48, 34), 2, Color(0.05, 0.07, 0.1))
	var lines: Array = _s["lines"]
	var cur := int(_s["line"])
	var cursor := Vector2(-21, -42)
	for i in mini(cur + 1, 5):
		var l: Array = lines[i]
		var x := -21.0 + int(l[0]) * 3.5
		var y := -43.0 + i * 6.0
		var room := INF if i < cur else float(_s["chars"])
		for p: Array in l[1]:
			var w := minf(float(p[0]), room)
			if w <= 0.0:
				break
			ci.draw_rect(Rect2(x, y, w, 2.6), p[1])
			room -= float(p[0]) + 1.6
			x += float(p[0]) + 1.6
		if i == mini(cur, 4):
			cursor = Vector2(minf(x, -21.0 + int(l[0]) * 3.5 + float(_s["chars"])), y)
	if busy and fmod(t, 0.9) < 0.5:
		ci.draw_rect(Rect2(cursor.x + 0.5, cursor.y - 0.5, 1.4, 3.6), Color(1, 1, 1, 0.85))
	ci.draw_colored_polygon(PackedVector2Array([Vector2(-33, -1), Vector2(33, -1), Vector2(28, -10), Vector2(-28, -10)]), Color(0.3, 0.33, 0.38))
	ci.draw_colored_polygon(PackedVector2Array([Vector2(-33, -1), Vector2(33, -1), Vector2(33, 0.5), Vector2(-33, 0.5)]), Color(0.2, 0.22, 0.26))
	for r in 2:
		for c in 9:
			ci.draw_rect(Rect2(-24.5 + c * 5.4 - r * 0.8, -8.4 + r * 3.0, 4.2, 1.8), Color(0.18, 0.2, 0.24))
	if not busy:
		# It builds.
		var u := clampf(_fin * 3.0, 0.0, 1.0)
		var c := Vector2(14, -20)
		_disc(ci, c, 6.0 * u, Color(UP, 0.95))
		if u >= 1.0:
			_poly(ci, PackedVector2Array([c + Vector2(-2.8, 0.2), c + Vector2(-0.8, 2.2), c + Vector2(3.0, -2.2)]), INK, 1.6)


func _hand_code() -> Vector2:
	if not busy:
		return Vector2.INF
	return _local(Vector2(-16.0 + sin(t * 3.1) * 5.0, -9.0 - absf(sin(t * 17.0)) * 2.5))


func _look_code() -> Vector2:
	return _local(Vector2(-4.0, -32.0))


func _front_code(ci: CanvasItem) -> void:
	_glasses(ci, Color(0.1, 0.1, 0.14, 0.95))


# --- Music: headphones on, bopping, notes in the air ------------------------------------------

func _step_music(dt: float, _working: bool) -> void:
	_s["note"] = float(_s.get("note", 0.0)) - dt
	if float(_s["note"]) <= 0.0:
		_s["note"] = _rng.randf_range(0.35, 0.7)
		var side := -1.0 if _rng.randf() < 0.5 else 1.0
		var from := _face() + Vector2(side * 22.0, -6.0)
		_part("note", from, Vector2(side * _rng.randf_range(6.0, 16.0), -_rng.randf_range(18.0, 26.0)), 1.8, {"s": _rng.randf_range(5.0, 7.0), "c": Color(PALETTE[_rng.randi() % PALETTE.size()]).lightened(0.2), "two": _rng.randf() < 0.4})


func _front_music(ci: CanvasItem) -> void:
	_headphones(ci)


# --- Art: an easel, a brush and a beret ---------------------------------------------------------

func _art_strokes() -> Array:
	# Canvas pixels, origin at its middle: sky, sun, two hills, a tree.
	var sky := [Vector2(-15, -10), Vector2(15, -9), Vector2(15, -5), Vector2(-15, -4)]
	var sun := _oval(Vector2(8, -6), 3.8, 3.8, 0.0, TAU, 16, 0.0)
	var hill := [Vector2(-16, 6), Vector2(-8, 1), Vector2(0, 3), Vector2(8, 0), Vector2(16, 4)]
	var hill2 := [Vector2(-16, 9), Vector2(-4, 5), Vector2(6, 8), Vector2(16, 6)]
	var tree := [Vector2(-8, 4), Vector2(-8, -3)]
	var crown := _oval(Vector2(-8, -4), 2.6, 2.6, 0.0, TAU, 12, 0.0)
	var cols := [Color(0.55, 0.78, 1.0), Color(1.0, 0.8, 0.3), Color(0.45, 0.8, 0.5), Color(0.3, 0.62, 0.42), Color(0.5, 0.35, 0.25), Color(0.3, 0.7, 0.4)]
	var pts := [sky, sun, hill, hill2, tree, crown]
	var out := []
	for i in pts.size():
		out.append([PackedVector2Array(pts[i]), cols[i], [3.5, 2.4, 2.6, 2.6, 1.4, 2.6][i]])
	return out


func _art_pen() -> Array:
	var strokes := _art_strokes()
	var left := _w
	for i in strokes.size():
		var d := 0.4 + _poly_len(strokes[i][0]) / 22.0
		if left < d:
			return [i, left / d]
		left -= d
	return [strokes.size(), 1.0]


func _poly_len(pts: PackedVector2Array) -> float:
	var l := 0.0
	for i in range(1, pts.size()):
		l += pts[i].distance_to(pts[i - 1])
	return l


func _canvas() -> Vector2:
	return Vector2(2, -40)


func _back_art(ci: CanvasItem) -> void:
	var wood := Color(0.62, 0.46, 0.32)
	_line(ci, Vector2(-10, -26), Vector2(-17, 0), wood, 2.0)
	_line(ci, Vector2(14, -26), Vector2(21, 0), wood, 2.0)
	_line(ci, Vector2(2, -60), Vector2(2, -2), wood.darkened(0.15), 2.0)
	var c := _canvas()
	ci.draw_rect(Rect2(c.x - 19, c.y - 15, 38, 30), Color(0.85, 0.82, 0.76))
	ci.draw_rect(Rect2(c.x - 18, c.y - 14, 36, 28), PAPER)
	ci.draw_rect(Rect2(c.x - 21, c.y + 15, 42, 2.2), wood)
	var pen := _art_pen()
	var strokes := _art_strokes()
	for i in mini(int(pen[0]) + 1, strokes.size()):
		var u := 1.0 if i < int(pen[0]) else float(pen[1])
		var s: Array = strokes[i]
		var pts: PackedVector2Array = s[0]
		var f := u * (pts.size() - 1)
		var part := PackedVector2Array()
		for j in int(f) + 1:
			part.append(c + pts[j])
		if int(f) < pts.size() - 1:
			part.append(c + pts[int(f)].lerp(pts[int(f) + 1], f - int(f)))
		if i == 1 and u >= 1.0:
			_disc(ci, c + Vector2(8, -6), 3.8, s[1])
		elif i == 2 or i == 3:
			# Hills fill in under their line as it's painted.
			var fill := part.duplicate()
			fill.append(Vector2(fill[fill.size() - 1].x, c.y + 14))
			fill.append(Vector2(c.x + pts[0].x, c.y + 14))
			if fill.size() >= 3:
				ci.draw_colored_polygon(fill, Color(s[1], 0.9))
		elif i == 5 and u >= 1.0:
			_disc(ci, c + Vector2(-8, -4), 2.8, s[1])
		if part.size() >= 2:
			_poly(ci, part, s[1], float(s[2]))


func _brush_tip() -> Vector2:
	var pen := _art_pen()
	var strokes := _art_strokes()
	if int(pen[0]) >= strokes.size():
		return _local(_canvas() + Vector2(-26.0, 6.0))
	var pts: PackedVector2Array = strokes[int(pen[0])][0]
	var f := float(pen[1]) * (pts.size() - 1)
	var i := mini(int(f), pts.size() - 2)
	return _local(_canvas() + pts[i].lerp(pts[i + 1], f - i))


func _hand_art() -> Vector2:
	return _brush_tip() + Vector2(-7.0, 5.0)


func _look_art() -> Vector2:
	return _brush_tip()


func _front_art(ci: CanvasItem) -> void:
	var h := _hand_now()
	var tip := h + Vector2(7.0, -5.0)
	var pen := _art_pen()
	var strokes := _art_strokes()
	var paint: Color = strokes[mini(int(pen[0]), strokes.size() - 1)][1]
	_line(ci, h + Vector2(-3, 2), tip, Color(0.7, 0.5, 0.32), 1.6)
	_line(ci, tip - (tip - h).normalized() * 1.5, tip + (tip - h).normalized() * 1.5, paint, 2.6)
	_beret(ci)


# --- Science: a fizzing flask and a test tube --------------------------------------------------

func _flask_hw(y: float) -> float:
	return lerpf(4.0, 15.0, clampf((-30.0 - y) / -26.0, 0.0, 1.0))


func _liquid() -> Color:
	return Color.from_hsv(fmod(float(_s["hue"]), 1.0), 0.6, 1.0, 0.75)


func _step_science(dt: float, working: bool) -> void:
	var h := float(_s["hue"])
	_s["hue"] = lerpf(h, float(_s["to"]), 1.0 - exp(-dt * 2.0))
	_s["pour"] = float(_s["pour"]) + (dt if working else 0.0)
	_s["fizz"] = maxf(0.0, float(_s["fizz"]) - dt * 0.5)
	if float(_s["pour"]) > 3.4:
		_s["pour"] = 0.0
		_s["to"] = float(_s["to"]) + _rng.randf_range(0.2, 0.5)
		_s["fizz"] = 1.0
	if float(_s["pour"]) > 1.6 and float(_s["pour"]) < 2.4 and _rng.randf() < dt * 10.0:
		_part("dot", _tube_mouth(), Vector2(0.0, 20.0), 0.45, {"g": 300.0, "s": 1.2, "c": Color.from_hsv(fmod(float(_s["to"]), 1.0), 0.6, 1.0)})
	var rate := 3.0 + float(_s["fizz"]) * 14.0
	if _rng.randf() < dt * rate:
		var col := _liquid().lightened(0.4)
		if _rng.randf() < 0.35:
			_part("puff", _local(Vector2(_rng.randf_range(-2, 2), -48)), Vector2(_rng.randf_range(-5, 5), -14), 1.4, {"s": 2.5, "c": Color(col, 0.6)})
		else:
			_part("dot", _local(Vector2(_rng.randf_range(-9, 9), -6)), Vector2(_rng.randf_range(-2, 2), -18), 1.2, {"s": _rng.randf_range(0.6, 1.3), "c": Color(1, 1, 1, 0.7)})


func _back_science(ci: CanvasItem) -> void:
	var outline := PackedVector2Array([Vector2(-4, -46), Vector2(-4, -30), Vector2(-15, -6), Vector2(-14, -2), Vector2(14, -2), Vector2(15, -6), Vector2(4, -30), Vector2(4, -46)])
	ci.draw_colored_polygon(outline, Color(1, 1, 1, 0.1))
	var level := -16.0 - float(_s["fizz"]) * 3.0
	var hw := _flask_hw(level)
	var liq := PackedVector2Array()
	for i in 9:
		var u := float(i) / 8.0
		liq.append(Vector2(lerpf(-hw, hw, u), level + sin(t * 5.0 + u * 6.0) * 0.8))
	liq.append_array(PackedVector2Array([Vector2(15, -6), Vector2(14, -2), Vector2(-14, -2), Vector2(-15, -6)]))
	ci.draw_colored_polygon(liq, _liquid())
	_poly(ci, outline, Color(1, 1, 1, 0.55), 1.2)
	_line(ci, Vector2(-6, -46), Vector2(6, -46), Color(1, 1, 1, 0.7), 1.6)
	_line(ci, Vector2(-9, -12), Vector2(-5, -24), Color(1, 1, 1, 0.35), 1.0)


func _tube_mouth() -> Vector2:
	return _hand_now() + Vector2(5.0, -9.0).rotated(_tube_tilt())


func _tube_tilt() -> float:
	var p := float(_s.get("pour", 0.0))
	return smoothstep(1.0, 1.6, p) * (1.0 - smoothstep(2.4, 3.0, p)) * 1.3


func _hand_science() -> Vector2:
	var p := float(_s.get("pour", 0.0))
	var over := smoothstep(0.4, 1.2, p) * (1.0 - smoothstep(2.6, 3.3, p))
	return _local(Vector2(lerpf(-24.0, -10.0, over), lerpf(-30.0, -54.0, over)))


func _look_science() -> Vector2:
	return _local(Vector2(0, -24))


func _front_science(ci: CanvasItem) -> void:
	var h := _hand_now()
	ci.draw_set_transform(h, _tube_tilt(), Vector2.ONE)
	var glass := PackedVector2Array([Vector2(-2.6, -12), Vector2(-2.6, 0), Vector2(2.6, 0), Vector2(2.6, -12)])
	ci.draw_rect(Rect2(-2.6, -12, 5.2, 12), Color(1, 1, 1, 0.12))
	ci.draw_rect(Rect2(-2.6, -6, 5.2, 6), Color.from_hsv(fmod(float(_s["to"]), 1.0), 0.6, 1.0, 0.85))
	_poly(ci, glass, Color(1, 1, 1, 0.7), 1.0)
	ci.draw_set_transform(Vector2.ZERO)
	_goggles(ci)


# --- Space: a telescope and the sky full of stars ---------------------------------------------

func _step_space(dt: float, _working: bool) -> void:
	_s["shoot"] = float(_s["shoot"]) - dt
	if float(_s["shoot"]) <= 0.0:
		_s["shoot"] = _rng.randf_range(2.5, 5.5)
		var from := Vector2(_rng.randf_range(width * 0.2, width * 0.95), _rng.randf_range(2.0, 14.0))
		_part("shoot", from, Vector2(-120, 46), 0.7)
	# Every so often it looks up from the eyepiece.
	_s["gazing"] = fmod(t, 9.0) > 6.5


func _back_space(ci: CanvasItem) -> void:
	ci.draw_set_transform(Vector2.ZERO)
	for s: Array in _s["stars"]:
		var tw := 0.45 + 0.55 * absf(sin(t * float(s[2]) + float(s[3])))
		var sp := Vector2(s[0], s[1])
		_disc(ci, sp, 0.7 + float(s[2]) * 0.35, Color(1, 1, 0.92, (0.4 + 0.5 * tw) * k))
		if float(s[2]) > 1.1:
			_sparkle(ci, sp, 1.6 + float(s[2]) * 1.6 * tw, Color(1, 1, 0.92, 0.55 * tw * k))
	# A ringed planet drifting across the far end.
	var pc := Vector2(width - 60.0 + sin(t * 0.2) * 8.0, 20.0)
	_disc(ci, pc, 6.0, Color(1.0, 0.78, 0.55, k))
	_disc(ci, pc + Vector2(-1.5, -1.5), 3.0, Color(1, 0.9, 0.75, 0.4 * k))
	_poly(ci, _oval(pc, 11.0, 2.6, -PI * 0.05, PI * 1.05, 18, -0.25), Color(1.0, 0.9, 0.7, 0.8 * k), 1.2)
	for p: Dictionary in _parts:
		if str(p["k"]) == "shoot":
			var u := float(p["age"]) / float(p["life"])
			var head: Vector2 = p["p"]
			_line(ci, head, head - (p["v"] as Vector2) * 0.18, Color(1, 1, 1, (1.0 - u) * 0.8 * k), 1.4)
	var pop := _pop()
	ci.draw_set_transform(Vector2(at, floor_y), 0.0, Vector2(pop, pop))
	var tube := Color(0.82, 0.86, 0.92)
	_line(ci, Vector2(2, -24), Vector2(-9, 0), Color(0.4, 0.44, 0.5), 1.6)
	_line(ci, Vector2(2, -24), Vector2(2, 0), Color(0.4, 0.44, 0.5), 1.6)
	_line(ci, Vector2(2, -24), Vector2(13, 0), Color(0.4, 0.44, 0.5), 1.6)
	ci.draw_set_transform(Vector2(at, floor_y) + Vector2(2, -27) * pop, -0.55, Vector2(pop, pop))
	ci.draw_rect(Rect2(-14, -4, 32, 8), tube)
	ci.draw_rect(Rect2(16, -5.5, 5, 11), tube.darkened(0.15))
	ci.draw_rect(Rect2(-14, -4, 32, 2.4), Color(1, 1, 1, 0.35))
	ci.draw_rect(Rect2(-19, -2.5, 5, 5), Color(0.35, 0.38, 0.44))
	ci.draw_set_transform(Vector2.ZERO)


func _look_space() -> Vector2:
	if _s.get("gazing", false):
		return _local(Vector2(40.0, -150.0))
	return _local(Vector2(-14.0, -22.0))


# --- Weather: a cloud of its own, an umbrella, then sun ---------------------------------------

func _step_weather(dt: float, _working: bool) -> void:
	var cycle := fmod(t, 12.0)
	_s["rain"] = cycle < 7.0
	var want := _head().x + (0.0 if _s["rain"] else 34.0)
	_s["cloud_x"] = lerpf(float(_s["cloud_x"]), want, 1.0 - exp(-dt * 2.0))
	if _s["rain"] and cycle > 0.6:
		for i in 2:
			if _rng.randf() < dt * 22.0:
				var x := float(_s["cloud_x"]) + _rng.randf_range(-14, 14)
				_part("rain", Vector2(x, 16.0), Vector2(-6, 120), 0.6)


func _back_weather(ci: CanvasItem) -> void:
	ci.draw_set_transform(Vector2.ZERO)
	var cycle := fmod(t, 12.0)
	var sun := smoothstep(6.5, 8.0, cycle) * (1.0 - smoothstep(11.2, 12.0, cycle))
	if sun > 0.0:
		var c := Vector2(float(_s["cloud_x"]) - 30.0, 18.0)
		for i in 8:
			var a := t * 0.6 + i * TAU / 8.0
			_line(ci, c + Vector2(cos(a), sin(a)) * 9.0, c + Vector2(cos(a), sin(a)) * 12.5, Color(1.0, 0.85, 0.4, sun * k), 1.6)
		_disc(ci, c, 6.5, Color(1.0, 0.85, 0.4, sun * k))
		# A rainbow behind it all.
		var rb := [Color(1.0, 0.45, 0.45), Color(1.0, 0.75, 0.35), Color(0.95, 0.95, 0.45), Color(0.45, 0.88, 0.55), Color(0.4, 0.7, 1.0), Color(0.65, 0.5, 1.0)]
		var center := Vector2(_head().x + 6.0, floor_y + 6.0)
		for i in rb.size():
			_poly(ci, _oval(center, 64.0 - i * 2.4, 54.0 - i * 2.4, PI * 1.08, PI * 1.92, 40, 0.0), Color(rb[i], 0.32 * sun * k), 2.4)
	for p: Dictionary in _parts:
		if str(p["k"]) == "rain":
			var pos: Vector2 = p["p"]
			var u_top := _umbrella_top()
			if absf(pos.x - u_top.x) < 19.0 and pos.y > u_top.y - 2.0 and _hand_weather() != Vector2.INF:
				continue
			if pos.y < floor_y:
				_line(ci, pos, pos + Vector2(-0.4, 4.0), Color(0.7, 0.85, 1.0, 0.75 * k), 1.0)
			else:
				_poly(ci, _oval(Vector2(pos.x, floor_y), 3.0, 1.2, PI, TAU, 8), Color(0.7, 0.85, 1.0, 0.5 * k), 1.0)
	var cx := float(_s["cloud_x"])
	var cy := 14.0 + sin(t * 1.2) * 1.5
	var cloud := Color(0.95, 0.97, 1.0, 0.95 * k) if _s["rain"] else Color(1, 1, 1, 0.9 * k)
	var under := Color(0.72, 0.78, 0.88, 0.95 * k)
	for c: Array in [[-10, 3, 6.5], [10, 3, 6.0], [-3, -1, 8.0], [5, 0, 7.0]]:
		_disc(ci, Vector2(cx + float(c[0]), cy + float(c[1]) + 1.2), float(c[2]), under)
	for c: Array in [[-10, 3, 6.5], [10, 3, 6.0], [-3, -1, 8.0], [5, 0, 7.0]]:
		_disc(ci, Vector2(cx + float(c[0]), cy + float(c[1])), float(c[2]), cloud)


func _hand_weather() -> Vector2:
	if not _s.get("rain", true):
		return Vector2.INF
	return _face() + Vector2(9.0, -4.0)


func _umbrella_top() -> Vector2:
	return Vector2(_head().x + 2.0, _head().y - 9.0)


func _look_weather() -> Vector2:
	return Vector2(float(_s["cloud_x"]), 14.0) if _s.get("rain", true) else Vector2(float(_s["cloud_x"]) - 30.0, 18.0)


func _front_weather(ci: CanvasItem) -> void:
	if not _s.get("rain", true):
		return
	var h := _hand_now()
	var top := _umbrella_top()
	_line(ci, h, top, Color(0.25, 0.28, 0.34), 1.4)
	_poly(ci, PackedVector2Array([h, h + Vector2(2, 2.5), h + Vector2(4, 1)]), Color(0.25, 0.28, 0.34), 1.4)
	var canopy := _oval(top + Vector2(0, 4), 19.0, 9.0, PI, TAU, 22)
	var scallop := PackedVector2Array()
	for i in 5:
		scallop.append_array(_oval(top + Vector2(15.2 - i * 7.6, 4.0), 3.8, 1.8, 0.0, PI, 6))
	canopy.append_array(scallop)
	ci.draw_colored_polygon(canopy, accent2.lerp(Color(1.0, 0.5, 0.55), 0.6))
	_poly(ci, _oval(top + Vector2(0, 4), 19.0, 9.0, PI * 1.12, PI * 1.45, 8), Color(1, 1, 1, 0.4), 1.2)
	_disc(ci, top - Vector2(0, 5.5), 1.2, Color(0.25, 0.28, 0.34))


# --- Food: a pot, a spoon and a chef's hat ----------------------------------------------------

func _step_food(dt: float, working: bool) -> void:
	_s["toss"] = float(_s["toss"]) - (dt if working else 0.0)
	if float(_s["toss"]) <= 0.0:
		_s["toss"] = _rng.randf_range(2.6, 4.0)
		var from := _local(Vector2(_rng.randf_range(-30.0, -24.0), -50.0))
		_part("food", from, Vector2(_rng.randf_range(34.0, 46.0), -50.0), 0.85, {"g": 300.0, "spin": _rng.randf_range(-8, 8), "i": _rng.randi() % 3})
	if _rng.randf() < dt * 3.0:
		_part("puff", _local(Vector2(_rng.randf_range(-8, 8), -26)), Vector2(_rng.randf_range(-3, 3), -16), 1.8, {"s": 3.0, "c": Color(1, 1, 1, 0.5)})


func _back_food(ci: CanvasItem) -> void:
	var metal := Color(0.3, 0.34, 0.4)
	ci.draw_rect(Rect2(-22, -18, 4, 2.2), metal.darkened(0.2))
	ci.draw_rect(Rect2(18, -18, 4, 2.2), metal.darkened(0.2))
	_panel(ci, Rect2(-18, -24, 36, 23), 6, metal)
	ci.draw_rect(Rect2(-17, -21, 34, 2.0), Color(1, 1, 1, 0.12))
	_ellipse(ci, Vector2(0, -24), 18.0, 3.4, metal.lightened(0.15))
	_ellipse(ci, Vector2(0, -24), 16.0, 2.6, Color(1.0, 0.62, 0.3))
	for i in 3:
		_disc(ci, Vector2(-8 + i * 7.0 + sin(t * 2.0 + i) * 2.0, -24.0), 1.1, Color(1.0, 0.85, 0.5))


func _hand_food() -> Vector2:
	var a := t * 3.4
	return _local(Vector2(-4.0 + cos(a) * 8.0, -32.0 + sin(a) * 2.2))


func _look_food() -> Vector2:
	return _local(Vector2(0, -24))


func _front_food(ci: CanvasItem) -> void:
	var h := _hand_now()
	var bowl := Vector2(_local(Vector2(0, -24)).x + (h.x - _local(Vector2(-4, 0)).x) * 0.6, _local(Vector2(0, -25)).y)
	_line(ci, h + (h - bowl).normalized() * 5.0, bowl, Color(0.72, 0.52, 0.34), 1.8)
	_chef_hat(ci)


# --- Games: a little runner on a screen, a gamepad in hand -------------------------------------

func _step_games(dt: float, _working: bool) -> void:
	var obs: Array = _s["obs"]
	for i in obs.size():
		obs[i] = float(obs[i]) - dt * 30.0
	if float(obs[0]) < -6.0:
		obs.pop_front()
		obs.append(float(obs[obs.size() - 1]) + _rng.randf_range(32.0, 60.0))
		_s["score"] = int(_s["score"]) + 1
	# Jumps just before the next one.
	var next := float(obs[0])
	if float(_s["y"]) <= 0.0 and next > 6.0 and next < 14.0:
		_s["vy"] = 58.0
		_s["dodge"] = 0.14
		kicks += 1
	_s["vy"] = float(_s["vy"]) - 170.0 * dt
	_s["y"] = maxf(0.0, float(_s["y"]) + float(_s["vy"]) * dt)
	_s["dodge"] = lerpf(float(_s["dodge"]), 0.0, 1.0 - exp(-dt * 4.0))


func _back_games(ci: CanvasItem) -> void:
	_panel(ci, Rect2(-30, -56, 60, 42), 6, Color(0.16, 0.18, 0.24))
	_panel(ci, Rect2(-27, -53, 54, 34), 3, Color(0.06, 0.08, 0.14))
	ci.draw_rect(Rect2(-6, -14, 12, 12), Color(0.16, 0.18, 0.24))
	ci.draw_rect(Rect2(-14, -3, 28, 3), Color(0.16, 0.18, 0.24))
	var base := Vector2(-22, -24)
	ci.draw_rect(Rect2(-26, -24, 52, 1), Color(accent, 0.6))
	for x: float in _s["obs"]:
		if x < 46.0:
			ci.draw_rect(Rect2(base.x + x, -29, 3, 5), UP)
	var y := -float(_s["y"])
	var px := Rect2(base.x + 6, -30 + y, 5, 6)
	ci.draw_rect(px, Color(1.0, 0.8, 0.35))
	ci.draw_rect(Rect2(px.position.x + 3, px.position.y + 1, 1, 1), INK)
	if fmod(t, 0.3) < 0.15 and y >= 0.0:
		ci.draw_rect(Rect2(px.position.x, -24, 1.5, 1), Color(1, 1, 1, 0.5))
	var sc := "%03d" % int(_s["score"])
	_text(ci, Vector2(24 - _text_w(sc, 7, false, 700), -45), sc, 7, Color(1, 1, 1, 0.7), false, 700)
	_sparkle(ci, Vector2(-20, -47), 1.6 + sin(t * 4.0) * 0.4, Color(1, 1, 1, 0.5))


func _look_games() -> Vector2:
	return _local(Vector2(-10, -32))


func _front_games(ci: CanvasItem) -> void:
	var f := _face() + Vector2(0, 13.0)
	ci.draw_set_transform(f, 0.0, Vector2(1.3, 1.3))
	_panel(ci, Rect2(-13, -4, 26, 9), 4, Color(0.2, 0.22, 0.28))
	ci.draw_rect(Rect2(-9.5, -0.5, 5, 1.6), Color(0.75, 0.78, 0.85))
	ci.draw_rect(Rect2(-7.7, -2.3, 1.6, 5), Color(0.75, 0.78, 0.85))
	var press := int(t * 6.0) % 4
	var cols := [Color(0.4, 0.85, 0.55), Color(1.0, 0.45, 0.5), Color(0.4, 0.65, 1.0), Color(1.0, 0.8, 0.35)]
	var spots := [Vector2(7, -1.6), Vector2(9.4, 0.6), Vector2(4.6, 0.6), Vector2(7, 2.6)]
	for i in 4:
		_disc(ci, spots[i], 1.1 if i != press else 1.3, cols[i] if i == press else cols[i].darkened(0.3))
	ci.draw_set_transform(Vector2.ZERO)


# --- Sport: keepy-uppies -----------------------------------------------------------------------

func _step_sport(dt: float, _working: bool) -> void:
	var period := 0.82
	var u := float(_s["u"]) + dt / period
	if u >= 1.0:
		u -= 1.0
		kicks += 1
		# Every few, a big one.
		_s["h"] = 46.0 if _rng.randf() < 0.22 else _rng.randf_range(20.0, 30.0)
	_s["u"] = u
	var h := float(_s["h"]) if busy or _fin < 2.0 else lerpf(float(_s["h"]), 0.0, minf(1.0, (_fin - 2.0) * 2.0))
	_s["y"] = _head().y - 6.5 - h * 4.0 * u * (1.0 - u)


func _front_sport(ci: CanvasItem) -> void:
	var c := Vector2(_head().x, float(_s["y"]))
	ci.draw_set_transform(c, 0.0, Vector2(1.15, 1.15))
	c = Vector2.ZERO
	_disc(ci, c, 6.5, Color(0.97, 0.97, 0.97))
	var a := t * 7.0
	var pent := PackedVector2Array()
	for i in 5:
		pent.append(c + Vector2(cos(a + i * TAU / 5.0), sin(a + i * TAU / 5.0)) * 2.6)
	ci.draw_colored_polygon(pent, INK)
	for i in 5:
		var d := Vector2(cos(a + i * TAU / 5.0 + PI / 5.0), sin(a + i * TAU / 5.0 + PI / 5.0))
		_line(ci, c + d * 2.4, c + d * 5.4, Color(INK, 0.55), 0.9)
	_ring(ci, c, 6.5, Color(INK, 0.4), 0.9)
	_disc(ci, c + Vector2(-2.2, -2.4), 1.4, Color(1, 1, 1, 0.8))
	ci.draw_set_transform(Vector2.ZERO)


func _look_sport() -> Vector2:
	return Vector2(_head().x, float(_s.get("y", 0.0)))


# --- Travel: a spinning globe and a plane going round -------------------------------------------

func _step_travel(dt: float, working: bool) -> void:
	_s["swipe"] = float(_s["swipe"]) - (dt if working else 0.0)
	if float(_s["swipe"]) <= 0.0:
		_s["swipe"] = _rng.randf_range(3.0, 4.6)
		_s["spin"] = 3.4
	_s["spin"] = lerpf(float(_s["spin"]), 0.5, 1.0 - exp(-dt * 0.9))
	_s["rot"] = float(_s["rot"]) + float(_s["spin"]) * dt


func _back_travel(ci: CanvasItem) -> void:
	var c := Vector2(0, -32)
	var stand := Color(0.6, 0.62, 0.68)
	_poly(ci, _oval(c, 17.0, 17.0, PI * 0.35, PI * 1.25, 20, 0.35), stand, 1.6)
	_line(ci, Vector2(0, -15), Vector2(0, -3), stand, 2.0)
	ci.draw_rect(Rect2(-9, -3, 18, 3), stand)
	_disc(ci, c, 14.0, Color(0.22, 0.5, 0.88))
	var rot := float(_s["rot"])
	var lands := [[0.0, 0.3, 5.0], [1.5, -0.25, 6.0], [2.6, 0.45, 4.0], [3.9, -0.1, 5.5], [5.0, 0.55, 3.5]]
	for l: Array in lands:
		var lon := float(l[0]) + rot
		var front := cos(lon)
		if front <= 0.05:
			continue
		var lat := float(l[1])
		var p := c + Vector2(sin(lon) * cos(lat), -sin(lat)) * 14.0
		_ellipse(ci, p, float(l[2]) * front * cos(lat) * 0.9, float(l[2]) * 0.7, Color(0.42, 0.8, 0.5))
	for i in 3:
		var lon := rot * 1.0 + i * PI / 3.0
		_poly(ci, _oval(c, absf(sin(lon)) * 14.0, 14.0, -PI * 0.5, PI * 0.5, 14, 0.0) if sin(lon) > 0.0 else _oval(c, absf(sin(lon)) * 14.0, 14.0, PI * 0.5, PI * 1.5, 14, 0.0), Color(1, 1, 1, 0.12), 0.8)
	_line(ci, c + Vector2(-14, 0), c + Vector2(14, 0), Color(1, 1, 1, 0.12), 0.8)
	_disc(ci, c + Vector2(-5, -6), 4.0, Color(1, 1, 1, 0.12))
	_ring(ci, c, 14.0, Color(1, 1, 1, 0.25), 1.0)
	# The plane, round and round over it.
	ci.draw_set_transform(Vector2.ZERO)
	var a := t * 0.9
	var center := Vector2(at - 10.0, floor_y - 52.0)
	var trail := PackedVector2Array()
	for i in 10:
		var b := a - i * 0.13
		trail.append(center + Vector2(cos(b) * 46.0, sin(b) * 10.0))
	for i in trail.size() - 1:
		if i % 2 == 0:
			_line(ci, trail[i], trail[i + 1], Color(1, 1, 1, (0.5 - i * 0.05) * k), 1.0)
	var pp := trail[0]
	var dir := Vector2(-sin(a) * 46.0, cos(a) * 10.0).normalized()
	ci.draw_set_transform(pp, dir.angle(), Vector2(1.0, 1.0) * (0.8 + 0.2 * sin(a)))
	var body := Color(1, 1, 1, k)
	ci.draw_colored_polygon(PackedVector2Array([Vector2(5, 0), Vector2(2, -1), Vector2(-4, -1), Vector2(-5, -3.5), Vector2(-5.5, 0), Vector2(-5, 1), Vector2(2, 1)]), body)
	ci.draw_colored_polygon(PackedVector2Array([Vector2(1, 0), Vector2(-2, -5), Vector2(-3, -5), Vector2(-1.5, 0)]), body)
	ci.draw_colored_polygon(PackedVector2Array([Vector2(1, 0), Vector2(-2, 5), Vector2(-3, 5), Vector2(-1.5, 0)]), body)
	ci.draw_set_transform(Vector2.ZERO)


func _hand_travel() -> Vector2:
	var s := float(_s.get("swipe", 3.0))
	var u := clampf(1.0 - s / 0.5, 0.0, 1.0) if s < 0.5 else 0.0
	if s > 2.5:
		u = clampf((s - 2.5) / 0.6, 0.0, 1.0)
		return _local(Vector2(lerpf(-12.0, -18.0, 1.0 - u), -30.0))
	return _local(Vector2(-16.0 + u * 4.0, -30.0)) if s < 0.5 else Vector2.INF


func _look_travel() -> Vector2:
	return _local(Vector2(0, -32))


# --- Books: a stack, an open book, reading glasses ---------------------------------------------

func _step_books(dt: float, working: bool) -> void:
	_s["flip"] = float(_s["flip"]) - (dt if working else 0.0)
	if float(_s["flip"]) < -0.6:
		_s["flip"] = _rng.randf_range(2.6, 3.6)


func _back_books(ci: CanvasItem) -> void:
	var cols := [Color(0.85, 0.36, 0.38), Color(0.32, 0.55, 0.85), Color(0.95, 0.75, 0.35), Color(0.4, 0.7, 0.5)]
	var y := 0.0
	for i in 4:
		var w := 26.0 - i * 2.0 + (i % 2) * 3.0
		var h := 5.0 + (i % 2)
		var x := -w * 0.5 + (i % 2) * 1.5
		_panel(ci, Rect2(x, y - h, w, h), 1, cols[i])
		ci.draw_rect(Rect2(x + 2, y - h + 1.2, w - 4, 0.8), Color(1, 1, 1, 0.3))
		y -= h


func _look_books() -> Vector2:
	var line := int(t * 0.8) % 4
	var u := fmod(t * 0.8, 1.0)
	return _face() + Vector2(lerpf(-12.0, 12.0, u), 22.0 + line * 2.0)


func _front_books(ci: CanvasItem) -> void:
	var c := _face() + Vector2(0, 19.0)
	var cover := Color(0.75, 0.32, 0.36)
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-17, -4), c + Vector2(0, -1), c + Vector2(17, -4), c + Vector2(17, 5), c + Vector2(0, 7), c + Vector2(-17, 5)]), cover)
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-16, -6), c + Vector2(0, -2.5), c + Vector2(0, 5.5), c + Vector2(-16, 3)]), PAPER)
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(16, -6), c + Vector2(0, -2.5), c + Vector2(0, 5.5), c + Vector2(16, 3)]), PAPER.darkened(0.06))
	for i in 3:
		var yy := -3.0 + i * 2.4
		_line(ci, c + Vector2(-13, yy - 0.8), c + Vector2(-3, yy + 1.4), Color(INK, 0.25), 0.8)
		_line(ci, c + Vector2(3, yy + 1.4), c + Vector2(13, yy - 0.8), Color(INK, 0.25), 0.8)
	var f := float(_s.get("flip", 3.0))
	if f < 0.0:
		var u := clampf(-f / 0.6, 0.0, 1.0)
		var x := cos(u * PI) * 16.0
		ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -2.5), c + Vector2(x, -6.0 - sin(u * PI) * 3.0), c + Vector2(x, 3.0 - sin(u * PI) * 3.0), c + Vector2(0, 5.5)]), PAPER.lightened(0.02))
	_glasses(ci, Color(0.85, 0.65, 0.35, 0.95))


# --- Health: a heart monitor ------------------------------------------------------------------

func _ecg(x: float) -> float:
	var ph := fmod(x, 1.0)
	return 0.15 * exp(-pow((ph - 0.1) / 0.03, 2.0)) - 0.2 * exp(-pow((ph - 0.2) / 0.012, 2.0)) + 1.0 * exp(-pow((ph - 0.23) / 0.012, 2.0)) - 0.3 * exp(-pow((ph - 0.26) / 0.012, 2.0)) + 0.25 * exp(-pow((ph - 0.45) / 0.05, 2.0))


func _step_health(_dt: float, _working: bool) -> void:
	var beat := int(t / 0.85)
	if beat != int(_s.get("beat", -1)):
		_s["beat"] = beat
		kicks += 1


func _back_health(ci: CanvasItem) -> void:
	_panel(ci, Rect2(-28, -52, 56, 46))
	var pts := PackedVector2Array()
	for i in 49:
		var u := float(i) / 48.0
		var x := -24.0 + u * 48.0
		pts.append(Vector2(x, -22.0 - _ecg(t / 0.85 - (1.0 - u) * 1.6) * 14.0))
	for i in pts.size() - 1:
		var fade := float(i) / pts.size()
		_line(ci, pts[i], pts[i + 1], Color(UP, 0.25 + 0.75 * fade), 1.2)
	_disc(ci, pts[pts.size() - 1], 1.6, UP)
	var pulse := 1.0 + _beat(0.85) * 0.25
	_heart(ci, Vector2(-19, -44), 7.0 * pulse, DOWN)
	_text(ci, Vector2(-12, -41), "72", 8, Color(1, 1, 1, 0.8), false, 700)
	_text(ci, Vector2(1, -41), "bpm", 6, Color(1, 1, 1, 0.45))


func _look_health() -> Vector2:
	return _local(Vector2(4, -28))


# --- Nature: a sprout that grows and blooms -------------------------------------------------------

func _step_nature(dt: float, working: bool) -> void:
	if working:
		_s["grow"] = minf(1.0, float(_s["grow"]) + dt * (0.07 if busy else 0.5))
		if _rng.randf() < dt * 14.0 and busy:
			var spout := _hand_now() + Vector2(13.0, -4.0)
			_part("dot", spout, Vector2(_rng.randf_range(8.0, 18.0), -4.0), 0.5, {"g": 240.0, "s": 0.9, "c": Color(0.6, 0.82, 1.0, 0.9)})
	if float(_s["grow"]) >= 1.0 and _rng.randf() < dt * 0.6:
		_part("butterfly", _local(Vector2(_rng.randf_range(-6, 6), -50)), Vector2.ZERO, 4.0, {"seed": _rng.randf() * 10.0})


func _back_nature(ci: CanvasItem) -> void:
	var g := float(_s["grow"])
	var hgt := 6.0 + g * 34.0
	var sway := sin(t * 1.4) * 2.0 * g
	var stem := PackedVector2Array()
	for i in 9:
		var u := float(i) / 8.0
		stem.append(Vector2(sin(u * 2.0) * 3.0 * g + sway * u * u, -14.0 - u * hgt))
	_poly(ci, stem, Color(0.36, 0.72, 0.4), 1.8)
	var leaves := [[0.3, -1.0, 0.15], [0.45, 1.0, 0.3], [0.65, -1.0, 0.5], [0.8, 1.0, 0.68]]
	for l: Array in leaves:
		var grown := clampf((g - float(l[2])) * 4.0, 0.0, 1.0)
		if grown <= 0.0:
			continue
		var at_stem := stem[int(float(l[0]) * 8.0)]
		var dir := float(l[1])
		_ellipse_rot(ci, at_stem + Vector2(dir * 4.0 * grown, -1.0), 4.5 * grown, 2.0 * grown, dir * -0.5, Color(0.42, 0.82, 0.48))
	var top := stem[stem.size() - 1]
	if g > 0.85:
		var b := smoothstep(0.85, 1.0, g)
		for i in 5:
			var a := i * TAU / 5.0 + t * 0.3
			_disc(ci, top + Vector2(cos(a), sin(a)) * 3.4 * b, 2.8 * b, Color(1.0, 0.6, 0.75))
		_disc(ci, top, 2.0 * b, Color(1.0, 0.85, 0.35))
	else:
		_disc(ci, top, 1.6, Color(0.5, 0.85, 0.5))
	ci.draw_colored_polygon(PackedVector2Array([Vector2(-12, -16), Vector2(12, -16), Vector2(9, 0), Vector2(-9, 0)]), Color(0.82, 0.48, 0.34))
	ci.draw_rect(Rect2(-13, -18, 26, 3.5), Color(0.88, 0.55, 0.4))
	_ellipse(ci, Vector2(0, -15.8), 11.0, 1.4, Color(0.35, 0.24, 0.18))


func _hand_nature() -> Vector2:
	if float(_s.get("grow", 0.0)) >= 1.0 or not busy:
		return Vector2.INF
	return _local(Vector2(-28.0, -38.0 + sin(t * 2.0) * 1.5))


func _look_nature() -> Vector2:
	var g := float(_s.get("grow", 0.0))
	return _local(Vector2(0, -14.0 - (6.0 + g * 34.0)))


func _front_nature(ci: CanvasItem) -> void:
	if _hand_nature() != Vector2.INF:
		var h := _hand_now()
		ci.draw_set_transform(h + Vector2(4, -2), 0.25, Vector2.ONE)
		var can := Color(0.45, 0.68, 0.95)
		_panel(ci, Rect2(-5, -5, 10, 8), 2, can)
		_line(ci, Vector2(4, -2), Vector2(11, -4), can, 1.6)
		_poly(ci, _oval(Vector2(-5, -1), 3.0, 3.0, PI * 0.5, PI * 1.5, 8), can.darkened(0.2), 1.2)
		ci.draw_set_transform(Vector2.ZERO)
	for p: Dictionary in _parts:
		if str(p["k"]) == "butterfly":
			var age := float(p["age"])
			var sd := float(p["seed"])
			var pos := _local(Vector2(sin(age * 1.3 + sd) * 18.0, -52.0 + sin(age * 2.1 + sd) * 8.0))
			var flap := absf(sin(age * 16.0))
			var col := Color(PALETTE[int(sd) % PALETTE.size()], clampf(minf(age, 4.0 - age), 0.0, 1.0))
			_ellipse_rot(ci, pos + Vector2(-2.0 * flap, -1), 2.6 * flap + 0.4, 2.2, 0.3, col)
			_ellipse_rot(ci, pos + Vector2(2.0 * flap, -1), 2.6 * flap + 0.4, 2.2, -0.3, col)
			_line(ci, pos + Vector2(0, -2), pos + Vector2(0, 1.5), Color(INK, col.a), 1.0)


# --- Party: a cake, a hat, confetti -----------------------------------------------------------

func _step_party(dt: float, _working: bool) -> void:
	if _rng.randf() < dt * (10.0 if busy else 30.0):
		_part("confetti", Vector2(_rng.randf_range(10.0, width - 10.0), -4.0), Vector2(_rng.randf_range(-8, 8), _rng.randf_range(28, 44)), 3.0, {"c": PALETTE[_rng.randi() % PALETTE.size()], "s": 2.0, "spin": _rng.randf_range(-6, 6), "rot": _rng.randf() * TAU})
	if not busy and not bool(_s["out"]) and _fin > 1.2:
		_s["out"] = true
		for i in 4:
			_part("puff", _local(Vector2(0, -40)), Vector2(_rng.randf_range(-4, 4), -12), 1.6, {"s": 1.8, "c": Color(0.8, 0.8, 0.85, 0.6)})


func _back_party(ci: CanvasItem) -> void:
	_panel(ci, Rect2(-17, -14, 34, 13), 3, Color(1.0, 0.75, 0.8))
	_panel(ci, Rect2(-12, -26, 24, 12), 3, Color(1.0, 0.9, 0.85))
	ci.draw_rect(Rect2(-19, -2, 38, 2.5), Color(0.9, 0.92, 0.96))
	for i in 5:
		_disc(ci, Vector2(-12 + i * 6.0, -13.5), 2.0, Color(1.0, 0.95, 0.95))
	for i in 3:
		_disc(ci, Vector2(-6 + i * 6.0, -6), 1.2, PALETTE[i])
	ci.draw_rect(Rect2(-1, -36, 2, 10), Color(0.5, 0.75, 1.0))
	if not bool(_s["out"]):
		var lean := 0.0 if busy else clampf(_fin - 0.4, 0.0, 0.8) * 3.0
		var fl := 1.0 + sin(t * 20.0) * 0.12
		ci.draw_colored_polygon(PackedVector2Array([Vector2(0, -36), Vector2(-2.2, -39), Vector2(lean, -44.5 * fl), Vector2(2.2, -39)]), Color(1.0, 0.75, 0.3))
		_disc(ci, Vector2(0, -38.5), 1.0, Color(1.0, 0.95, 0.7))


func _look_party() -> Vector2:
	return _local(Vector2(0, -36))


func _front_party(ci: CanvasItem) -> void:
	_party_hat(ci)


# --- Film: popcorn and 3D glasses -------------------------------------------------------------

func _step_film(dt: float, working: bool) -> void:
	_s["eat"] = float(_s["eat"]) - (dt if working else 0.0)
	_s["chomp"] = maxf(0.0, float(_s["chomp"]) - dt)
	if float(_s["eat"]) < -1.0:
		_s["eat"] = _rng.randf_range(1.6, 2.8)
		_s["chomp"] = 0.9
	if _rng.randf() < dt * 1.5:
		_part("dot", _local(Vector2(_rng.randf_range(-6, 6), -24)), Vector2(_rng.randf_range(-12, 12), -50), 0.9, {"g": 160.0, "s": 1.6, "c": Color(1.0, 0.95, 0.8)})


func _back_film(ci: CanvasItem) -> void:
	ci.draw_colored_polygon(PackedVector2Array([Vector2(-10, -22), Vector2(10, -22), Vector2(7, 0), Vector2(-7, 0)]), Color(0.97, 0.96, 0.95))
	for i in 3:
		var x0 := -8.0 + i * 6.4
		ci.draw_colored_polygon(PackedVector2Array([Vector2(x0, -22), Vector2(x0 + 3.2, -22), Vector2(x0 * 0.7 + 2.2, 0), Vector2(x0 * 0.7, 0)]), Color(0.92, 0.3, 0.32))
	for c: Array in [[-7, -24, 3.2], [-2, -26, 3.6], [4, -25, 3.4], [8, -23, 2.8], [1, -22.5, 3.0], [-5, -22, 2.6]]:
		_disc(ci, Vector2(c[0], c[1]), float(c[2]), Color(1.0, 0.94, 0.75))
		_disc(ci, Vector2(float(c[0]) - 0.8, float(c[1]) - 0.8), float(c[2]) * 0.4, Color(1, 1, 1, 0.6))


func _hand_film() -> Vector2:
	var e := float(_s.get("eat", 1.0))
	if e > 0.0:
		return Vector2.INF
	var u := clampf(-e, 0.0, 1.0)
	var dip := _local(Vector2(-6.0, -26.0))
	var mouth := _face() + Vector2(6.0, 6.0)
	return dip.lerp(mouth, smoothstep(0.3, 0.8, u))


func _look_film() -> Vector2:
	return _local(Vector2(30.0, -60.0))


func _front_film(ci: CanvasItem) -> void:
	if _hand_film() != Vector2.INF:
		_disc(ci, _hand_now() + Vector2(1, -2), 1.8, Color(1.0, 0.94, 0.75))
	var eyes: Array = _me("eyes", [])
	if eyes.size() == 2:
		var r := float(_me("eye_r", 5.0)) + 1.4
		ci.draw_rect(Rect2((eyes[0] as Vector2) - Vector2(r, r * 0.8), Vector2(r * 2, r * 1.6)), Color(1.0, 0.35, 0.35, 0.55))
		ci.draw_rect(Rect2((eyes[1] as Vector2) - Vector2(r, r * 0.8), Vector2(r * 2, r * 1.6)), Color(0.35, 0.85, 1.0, 0.55))
		_line(ci, (eyes[0] as Vector2) + Vector2(r, 0), (eyes[1] as Vector2) - Vector2(r, 0), Color(0.95, 0.95, 0.95), 1.2)
		ci.draw_rect(Rect2((eyes[0] as Vector2) - Vector2(r, r * 0.8), Vector2(r * 2, r * 1.6)), Color(0.95, 0.95, 0.95), false, 1.0)
		ci.draw_rect(Rect2((eyes[1] as Vector2) - Vector2(r, r * 0.8), Vector2(r * 2, r * 1.6)), Color(0.95, 0.95, 0.95), false, 1.0)


# --- Language: hello in many languages ---------------------------------------------------------

const HELLOS := ["Olá", "Hello", "Hola", "Bonjour", "Ciao", "Hallo", "Hej", "Salut", "Ahoj"]


func _step_language(dt: float, _working: bool) -> void:
	_s["next"] = float(_s["next"]) - dt
	if float(_s["next"]) <= 0.0:
		_s["next"] = 1.3
		_s["i"] = (int(_s["i"]) + 1) % HELLOS.size()
		var side := -1.0 if int(_s["i"]) % 2 == 0 else 1.0
		_part("bubble", _head() + Vector2(side * 26.0, 8.0), Vector2(side * 4.0, -7.0), 2.4, {"t": HELLOS[int(_s["i"])], "side": side})


func _front_language(ci: CanvasItem) -> void:
	for p: Dictionary in _parts:
		if str(p["k"]) != "bubble":
			continue
		var u := float(p["age"]) / float(p["life"])
		var a := clampf(minf(u * 8.0, (1.0 - u) * 4.0), 0.0, 1.0)
		var s := str(p["t"])
		var w := _text_w(s, 9, false, 600) + 10.0
		var pos: Vector2 = p["p"]
		pos.x = clampf(pos.x, w * 0.5 + 4.0, width - w * 0.5 - 4.0)
		pos.y = maxf(pos.y, 10.0)
		var sc := 0.7 + 0.3 * minf(1.0, u * 8.0)
		ci.draw_set_transform(pos, 0.0, Vector2(sc, sc))
		var side := float(p["side"])
		_panel(ci, Rect2(-w * 0.5, -8, w, 14), 7, Color(0.075, 0.1, 0.14, 0.9 * a))
		ci.draw_colored_polygon(PackedVector2Array([Vector2(-side * 4.0, 5.5), Vector2(-side * 10.0, 10.0), Vector2(-side * 1.0, 5.5)]), Color(0.075, 0.1, 0.14, 0.9 * a))
		_text(ci, Vector2(-w * 0.5 + 5.0, 2.5), s, 9, Color(1, 1, 1, 0.95 * a))
		ci.draw_set_transform(Vector2.ZERO)


# --- Planning: a checklist ticked off ------------------------------------------------------------

func _plan_ticks() -> float:
	return _w / 1.4


func _back_planning(ci: CanvasItem) -> void:
	var card := int(_plan_ticks() / 5.0)
	var ticks := fmod(_plan_ticks(), 5.0)
	var slide := clampf((ticks - 4.4) / 0.6, 0.0, 1.0) if busy else 0.0
	if not busy:
		ticks = maxf(ticks, 4.0 + minf(_fin, 0.9))
	ci.draw_set_transform(Vector2(at, floor_y) + Vector2(slide * 8.0, -slide * 4.0) * _pop(), slide * 0.2, Vector2(_pop(), _pop()))
	_panel(ci, Rect2(-23, -58, 46, 56), 4, Color(0.6, 0.45, 0.32))
	_panel(ci, Rect2(-20, -54, 40, 50), 2, PAPER)
	_panel(ci, Rect2(-7, -61, 14, 6), 2, Color(0.75, 0.78, 0.84))
	_s["tick_at"] = Vector2(-14, -44)
	for i in 4:
		var y := -44.0 + i * 10.0
		_panel(ci, Rect2(-16, y - 3.0, 6, 6), 1, Color(1, 1, 1))
		ci.draw_rect(Rect2(-16, y - 3.0, 6, 6), Color(INK, 0.4), false, 0.8)
		var bars: Array = [[22.0], [16.0], [19.0], [13.0]][(i + card) % 4]
		ci.draw_rect(Rect2(-7, y - 1.0, float(bars[0]), 2.0), Color(INK, 0.22))
		var u := clampf(ticks - i, 0.0, 1.0)
		if u > 0.0:
			var a := Vector2(-15, y)
			var m := Vector2(-13.4, y + 2.0)
			var b := Vector2(-9.0, y - 4.0)
			var pts := PackedVector2Array([a, a.lerp(m, minf(u * 2.0, 1.0))])
			if u > 0.5:
				pts.append(m.lerp(b, (u - 0.5) * 2.0))
			_poly(ci, pts, Color(0.22, 0.65, 0.42), 1.6)
		if u > 0.0 and u < 1.0:
			_s["tick_at"] = Vector2(-13.0, y)
	ci.draw_set_transform(Vector2.ZERO)


func _hand_planning() -> Vector2:
	return _local(_s.get("tick_at", Vector2(-14, -44)) + Vector2(-2.0, 3.0))


func _look_planning() -> Vector2:
	return _local(_s.get("tick_at", Vector2(-14, -44)))


func _front_planning(ci: CanvasItem) -> void:
	var h := _hand_now()
	_line(ci, h, h + Vector2(5, -6), Color(0.3, 0.5, 0.95), 1.8)
	_line(ci, h + Vector2(4, -4.8), h + Vector2(5, -6), Color(1.0, 0.8, 0.4), 1.8)


# --- Security: a padlock and its key -----------------------------------------------------------

func _lock_phase() -> float:
	return fmod(_w, 4.0)


func _step_security(_dt: float, _working: bool) -> void:
	var ph := _lock_phase()
	if ph > 2.0 and float(_s.get("was", 0.0)) <= 2.0:
		kicks += 1
		for i in 6:
			var a := i * TAU / 6.0
			_part("spark", _local(Vector2(0, -16)), Vector2(cos(a), sin(a)) * 30.0, 0.5, {"s": 2.0, "c": Color(1.0, 0.85, 0.4), "drag": 4.0})
	_s["was"] = ph


func _back_security(ci: CanvasItem) -> void:
	var ph := _lock_phase()
	var closed := ph > 2.0 or not busy
	var lift := 0.0 if closed else 5.0
	var steel := Color(0.75, 0.78, 0.84)
	var arc := _oval(Vector2(0, -26 - lift), 7.0, 8.0, PI, TAU, 16)
	arc.insert(0, Vector2(-7, -20 - lift))
	arc.append(Vector2(7, -20 - lift if closed else -26 - lift))
	_poly(ci, arc, steel, 2.6)
	_panel(ci, Rect2(-11, -24, 22, 22), 4, Color(1.0, 0.78, 0.35))
	ci.draw_rect(Rect2(-10, -22, 20, 2.0), Color(1, 1, 1, 0.3))
	_disc(ci, Vector2(0, -15), 2.2, Color(0.35, 0.25, 0.1))
	ci.draw_rect(Rect2(-0.8, -15, 1.6, 4.5), Color(0.35, 0.25, 0.1))


func _hand_security() -> Vector2:
	var ph := _lock_phase()
	var reach := smoothstep(0.3, 1.2, ph) * (1.0 - smoothstep(2.6, 3.4, ph))
	return _local(Vector2(lerpf(-24.0, -13.0, reach), -15.0))


func _look_security() -> Vector2:
	return _local(Vector2(0, -15))


func _front_security(ci: CanvasItem) -> void:
	var ph := _lock_phase()
	var turn := smoothstep(1.3, 2.0, ph) * (1.0 - smoothstep(2.6, 3.0, ph)) * PI * 0.5
	var h := _hand_now()
	var col := Color(0.95, 0.85, 0.5)
	ci.draw_set_transform(h, 0.0, Vector2(1.0, cos(turn) * 0.7 + 0.3))
	_ring(ci, Vector2(-1.5, 0), 2.6, col, 1.6)
	_line(ci, Vector2(1, 0), Vector2(10, 0), col, 1.6)
	_line(ci, Vector2(8, 0), Vector2(8, 2.4), col, 1.4)
	_line(ci, Vector2(6, 0), Vector2(6, 2.0), col, 1.4)
	ci.draw_set_transform(Vector2.ZERO)


# --- AI: an antenna and bits in the air --------------------------------------------------------

func _step_ai(dt: float, _working: bool) -> void:
	if _rng.randf() < dt * 3.0:
		var from := _head() + Vector2(_rng.randf_range(-26, 26), 4.0)
		_part("text", from, Vector2(0, -16), 1.6, {"t": "1" if _rng.randf() < 0.5 else "0", "s": 8.0, "c": Color(accent.lightened(0.4), 0.8)})


func _front_ai(ci: CanvasItem) -> void:
	var top := _head()
	var tip := top + Vector2(sin(t * 3.0) * 2.0, -11.0)
	_line(ci, top + Vector2(0, 2), tip, Color(0.85, 0.9, 0.98), 1.2)
	var glow := 0.5 + 0.5 * sin(t * 6.0)
	_disc(ci, tip, 3.6, Color(accent.lightened(0.4), 0.25 * glow))
	_disc(ci, tip, 2.0, accent.lightened(0.2 + 0.3 * glow))


# --- Things it wears -------------------------------------------------------------------------------

func _tilt() -> float:
	return float(_me("tilt", 0.0))


func _glasses(ci: CanvasItem, col: Color) -> void:
	var eyes: Array = _me("eyes", [])
	if eyes.size() != 2:
		return
	var r := float(_me("eye_r", 5.0)) + 0.9
	var l: Vector2 = eyes[0]
	var rr: Vector2 = eyes[1]
	_disc(ci, l, r, Color(1, 1, 1, 0.1))
	_disc(ci, rr, r, Color(1, 1, 1, 0.1))
	_ring(ci, l, r, col, 0.9)
	_ring(ci, rr, r, col, 0.9)
	_line(ci, l + (rr - l).normalized() * r, rr - (rr - l).normalized() * r, col, 0.9)


func _goggles(ci: CanvasItem) -> void:
	var eyes: Array = _me("eyes", [])
	if eyes.size() != 2:
		return
	var r := float(_me("eye_r", 5.0)) + 2.6
	var band := Color(0.3, 0.34, 0.42)
	var l: Vector2 = eyes[0]
	var rr: Vector2 = eyes[1]
	var side := (rr - l).normalized()
	_line(ci, l - side * 19.0, l - side * (r + 0.5), band, 2.2)
	_line(ci, rr + side * (r + 0.5), rr + side * 19.0, band, 2.2)
	_line(ci, l + side * r, rr - side * r, band, 1.4)
	for e: Vector2 in [l, rr]:
		_disc(ci, e, r, Color(0.7, 0.92, 1.0, 0.18))
		_ring(ci, e, r, band, 1.8)
		_disc(ci, e + Vector2(-r * 0.4, -r * 0.45), r * 0.18, Color(1, 1, 1, 0.5))


func _headphones(ci: CanvasItem) -> void:
	var top := _head()
	var f := _face()
	var w := float(_me("half_w", 23.0))
	var band := _oval(Vector2(top.x, f.y - 2.0), w + 1.5, f.y - top.y + 3.0, PI, TAU, 22, _tilt())
	_poly(ci, band, Color(0.2, 0.22, 0.28), 2.4)
	var bounce := _beat(1.0) * 1.2
	for s in [-1.0, 1.0]:
		var c := Vector2(f.x + s * (w + 0.5), f.y - 1.0 - bounce)
		_panel(ci, Rect2(c.x - 3.5, c.y - 6.0, 7.0, 12.0), 3, Color(0.2, 0.22, 0.28))
		ci.draw_rect(Rect2(c.x - 1.8 + s * 0.6, c.y - 4.0, 2.4, 8.0), accent.lightened(0.15))


func _beret(ci: CanvasItem) -> void:
	var top := _head()
	ci.draw_set_transform(top + Vector2(2, 2.5), _tilt() - 0.2, Vector2.ONE)
	_ellipse(ci, Vector2(0, 0), 14.0, 4.6, Color(0.62, 0.2, 0.3))
	_ellipse(ci, Vector2(-3, -1.5), 8.0, 2.0, Color(1, 1, 1, 0.12))
	ci.draw_rect(Rect2(-0.8, -6.5, 1.6, 3.0), Color(0.62, 0.2, 0.3))
	ci.draw_set_transform(Vector2.ZERO)


func _chef_hat(ci: CanvasItem) -> void:
	var top := _head()
	ci.draw_set_transform(top + Vector2(0, 3), _tilt(), Vector2.ONE)
	var white := Color(0.98, 0.98, 1.0)
	_disc(ci, Vector2(-6, -9), 6.0, white.darkened(0.06))
	_disc(ci, Vector2(6, -9), 6.0, white.darkened(0.06))
	_disc(ci, Vector2(0, -12), 7.0, white)
	ci.draw_rect(Rect2(-9, -7, 18, 7), white)
	ci.draw_rect(Rect2(-9, -2, 18, 2), Color(0.85, 0.87, 0.92))
	ci.draw_set_transform(Vector2.ZERO)


func _party_hat(ci: CanvasItem) -> void:
	var top := _head()
	ci.draw_set_transform(top + Vector2(3, 3), _tilt() + 0.2, Vector2.ONE)
	ci.draw_colored_polygon(PackedVector2Array([Vector2(-7, 0), Vector2(7, 0), Vector2(0, -17)]), Color(0.45, 0.6, 1.0))
	for i in 3:
		var y := -3.0 - i * 4.6
		var hw := 7.0 * (1.0 + y / 17.0)
		_line(ci, Vector2(-hw, y), Vector2(hw, y - 1.0), Color(1.0, 0.82, 0.35), 1.4)
	_disc(ci, Vector2(0, -17), 2.4, Color(1.0, 0.5, 0.6))
	ci.draw_set_transform(Vector2.ZERO)
