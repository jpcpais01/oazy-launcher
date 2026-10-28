class_name MusicGlyph
extends Control
## The taskbar's music wallpaper toggle: five rounded bars. Off, they rest as
## a small still equaliser; on, they dance with what Music hears.

const BARS := 5
## Resting heights (of the 24 grid), a gentle arch.
const REST := [6.0, 10.0, 13.0, 9.0, 5.0]
## Which of Music's bands each bar follows.
const BAND := [1, 3, 6, 9, 12]

var color := Color(1, 1, 1, 0.85)
var _h := PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0])


func _init(px: int = 18) -> void:
	custom_minimum_size = Vector2(px, px)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	for i in BARS:
		_h[i] = REST[i]


func _ready() -> void:
	Music.toggled.connect(func(_on: bool) -> void: set_process(true))
	set_process(Music.on)


func _process(delta: float) -> void:
	var settled := true
	for i in BARS:
		var want: float = REST[i]
		if Music.on and Music.presence > 0.05:
			want = lerpf(3.0, 18.0, clampf(Music.bands[BAND[i]] * 1.2, 0.0, 1.0))
		_h[i] += (want - _h[i]) * (1.0 - exp(-delta * 18.0))
		settled = settled and absf(want - _h[i]) < 0.05
	queue_redraw()
	if settled and not Music.on:
		set_process(false)


func _draw() -> void:
	var s := minf(minf(size.x, size.y), custom_minimum_size.x) / 24.0
	var o := (size - Vector2(24.0, 24.0) * s) / 2.0
	var w := 2.4 * s
	for i in BARS:
		var x := o.x + (4.0 + 4.0 * float(i)) * s
		var h := maxf(_h[i] * s, w)
		var r := Rect2(x - w / 2.0, o.y + 12.0 * s - h / 2.0, w, h)
		draw_style_box(_bar(color, w / 2.0), r)


static func _bar(c: Color, radius: float) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(int(ceilf(radius)))
	sb.anti_aliasing = true
	return sb
