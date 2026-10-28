class_name StarGlyph
extends Control
## Party mode's glyph beside the music toggle: a four-pointed star with a
## small one at its shoulder. While the party is on it warms to gold and the
## small star twinkles with the beat.

const GOLD := Color(1.0, 0.9, 0.72, 0.95)
const PLAIN := Color(1, 1, 1, 0.85)

var _warm := 0.0
var _twinkle := 0.0


func _init(px: int = 16) -> void:
	custom_minimum_size = Vector2(px, px)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	Music.party_changed.connect(func(_on: bool) -> void: set_process(true))
	_warm = 1.0 if Music.party else 0.0
	set_process(Music.party)


func _process(delta: float) -> void:
	var want := 1.0 if Music.party else 0.0
	_warm += (want - _warm) * (1.0 - exp(-delta * 8.0))
	_twinkle = Music.pulse * _warm if Music.party else _twinkle * exp(-delta * 8.0)
	queue_redraw()
	if not Music.party and _warm < 0.01:
		_warm = 0.0
		_twinkle = 0.0
		queue_redraw()
		set_process(false)


func _draw() -> void:
	var s := minf(size.x, size.y) / 24.0
	var o := (size - Vector2(24.0, 24.0) * s) / 2.0
	var c := PLAIN.lerp(GOLD, _warm)
	_star(o + Vector2(11.0, 13.0) * s, 8.0 * s, c)
	var small := 3.0 * s * (1.0 + 0.3 * _twinkle)
	_star(o + Vector2(18.5, 5.5) * s, small, Color(c, c.a * (0.75 + 0.25 * _twinkle)))


## A four-pointed star with softly concave sides.
func _star(at: Vector2, r: float, c: Color) -> void:
	var pts := PackedVector2Array()
	for i in 48:
		var t := TAU * float(i) / 48.0
		var cx := cos(t)
		var sy := sin(t)
		pts.append(at + Vector2(signf(cx) * pow(absf(cx), 3.0), signf(sy) * pow(absf(sy), 3.0)) * r)
	draw_colored_polygon(pts, c)
	# A hairline of the same colour smooths the polygon's edge.
	pts.append(pts[0])
	draw_polyline(pts, c, 0.75, true)
