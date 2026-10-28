class_name NowPlaying
extends Control
## The music wallpaper's player, drawn straight onto the desktop with no box
## around it: the song title low on the left, and at the bottom centre
## a hairline timeline (a little live waveform rides the playhead; click or
## drag to seek) over previous, play/pause and next, with the time beside.
## It follows whatever Windows' media controls report (Music.media), Chrome
## first. The title and the play bar can each be turned off in Personalise.
## Hidden while the music wallpaper is off or nothing is playing, and with the
## rest of the desktop in the clean view.

const TRACK_W := 460.0
## Above the taskbar: the timeline, then the buttons under it.
const TRACK_UP := 78.0
const ROW_GAP := 26.0

var main: Node
var _title: Label
var _time: Label
var _track: _Track
var _play: _Glyph
var _prev: _Glyph
var _next: _Glyph
var _shown := 0.0
var _want := false
var _dim := 0.0
var _clean := false
var _scroll := 0.0
var _top_a := 1.0
var _fade: Tween


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	modulate.a = 0.0
	visible = false

	_title = Kit.label("", 26, 400, Color(1, 1, 1, 0.94))
	var airy := FontVariation.new()
	airy.base_font = Kit.font(400)
	airy.spacing_glyph = 1
	_title.add_theme_font_override("font", airy)
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_title.clip_text = true
	add_child(_title)

	_track = _Track.new()
	_track.seek.connect(func(sec: float) -> void: Music.media_do("seek", sec))
	add_child(_track)
	_prev = _Glyph.new("prev", 15.0)
	_prev.pressed.connect(func() -> void: Music.media_do("prev"))
	add_child(_prev)
	_play = _Glyph.new("play", 19.0)
	_play.pressed.connect(func() -> void: Music.media_do("toggle"))
	add_child(_play)
	_next = _Glyph.new("next", 15.0)
	_next.pressed.connect(func() -> void: Music.media_do("next"))
	add_child(_next)
	_time = Kit.label("", 12, 500, Color(1, 1, 1, 0.66))
	_time.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_time)

	resized.connect(_layout)
	Music.media_changed.connect(_sync)
	Music.toggled.connect(func(_on: bool) -> void: _sync())
	Settings.changed.connect(func(key: String, _v: Variant) -> void:
		if key == "music_show_song" or key == "music_show_controls":
			_sync()
	)
	_sync()
	_layout()


func _layout() -> void:
	var w := size.x
	var y := size.y - Taskbar.RESERVE - TRACK_UP
	_track.position = Vector2(roundf((w - TRACK_W) * 0.5), y - 10.0)
	_track.size = Vector2(TRACK_W, 20.0)
	var row := y + ROW_GAP
	_play.position = Vector2(roundf(w * 0.5 - 18.0), row - 18.0)
	_prev.position = _play.position - Vector2(46.0, 0.0)
	_next.position = _play.position + Vector2(46.0, 0.0)
	_time.size = Vector2(140.0, 20.0)
	_time.position = Vector2(_track.position.x + TRACK_W - 140.0, row - 10.0)
	var left := 64.0
	var title_w := clampf(w * 0.34, 260.0, 620.0)
	_title.size = Vector2(title_w, 36.0)
	_title.position = Vector2(left, row - 18.0)


func _sync() -> void:
	var m := Music.media
	var has: bool = m.get("has", false) and str(m.get("title", "")) != ""
	_title.text = str(m.get("title", ""))
	_title.tooltip_text = _title.text
	_play.kind = "pause" if m.get("playing", false) else "play"
	_prev.disabled = not m.get("can_prev", true)
	_next.disabled = not m.get("can_next", true)
	_track.can_seek = m.get("can_seek", false) and float(m.get("dur", 0.0)) > 0.0
	var song := bool(Settings.get_value("music_show_song"))
	var controls := bool(Settings.get_value("music_show_controls"))
	_title.visible = song
	for c: Control in [_track, _prev, _play, _next, _time]:
		c.visible = controls
	_set_shown(Music.on and has and not _clean and (song or controls))


## Fades out with the desktop behind Start.
func dim(on: bool) -> void:
	_dim = 1.0 if on else 0.0
	_apply()


## It belongs to the desktop's first screen: it scrolls away with it,
## fading out the same way, so it never sits over the second screen.
func follow_scroll(px: float, top_alpha: float) -> void:
	_scroll = px
	_top_a = top_alpha
	_apply()


## The clean view (see Desktop.set_clean): off with everything else.
func set_clean(on: bool) -> void:
	_clean = on
	_sync()


func _set_shown(on: bool) -> void:
	if on == _want:
		return
	_want = on
	if _fade and _fade.is_valid():
		_fade.kill()
	if on:
		visible = true
	_fade = create_tween().set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	_fade.tween_method(func(v: float) -> void:
		_shown = v
		_apply()
	, _shown, 1.0 if on else 0.0, 0.45 if on else 0.4)
	if not on:
		_fade.tween_callback(func() -> void: visible = false)


func _apply() -> void:
	modulate.a = _shown * (1.0 - _dim) * _top_a
	position.y = (1.0 - _shown) * 10.0 - roundf(_scroll)


func _process(_delta: float) -> void:
	if not visible:
		return
	var dur := float(Music.media.get("dur", 0.0))
	var pos := Music.media_position()
	_track.progress = pos / dur if dur > 0.0 else 0.0
	_track.duration = dur
	_track.queue_redraw()
	_time.text = "%s / %s" % [_clock(pos), _clock(dur)] if dur > 0.0 else ""


static func _clock(sec: float) -> String:
	var s := int(sec)
	if s >= 3600:
		return "%d:%02d:%02d" % [s / 3600, (s / 60) % 60, s % 60]
	return "%02d:%02d" % [s / 60, s % 60]


## The hairline timeline with a small live waveform around the playhead.
class _Track:
	extends Control

	signal seek(seconds: float)

	var progress := 0.0
	var duration := 0.0
	var can_seek := false
	var _drag := -1.0
	var _hover := false

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_entered.connect(func() -> void:
			_hover = true
			queue_redraw()
		)
		mouse_exited.connect(func() -> void:
			_hover = false
			queue_redraw()
		)

	func _gui_input(e: InputEvent) -> void:
		if not can_seek:
			mouse_default_cursor_shape = Control.CURSOR_ARROW
			return
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
			if e.pressed:
				_drag = clampf(e.position.x / size.x, 0.0, 1.0)
			elif _drag >= 0.0:
				seek.emit(_drag * duration)
				progress = _drag
				_drag = -1.0
			accept_event()
			queue_redraw()
		elif e is InputEventMouseMotion and _drag >= 0.0:
			_drag = clampf(e.position.x / size.x, 0.0, 1.0)
			accept_event()
			queue_redraw()

	func _draw() -> void:
		var y := size.y * 0.5
		var at := (_drag if _drag >= 0.0 else clampf(progress, 0.0, 1.0)) * size.x
		var thick := 2.0 if _hover and can_seek else 1.0
		draw_line(Vector2(0, y), Vector2(size.x, y), Color(1, 1, 1, 0.2), thick, true)
		draw_line(Vector2(0, y), Vector2(at, y), Color(1, 1, 1, 0.62), thick, true)
		# The waveform: a few dozen hairlines, tallest at the playhead, moving
		# with what Music hears.
		var n := 26
		for k in range(-n, n + 1):
			var x := at + float(k) * 3.0
			if x < 0.0 or x > size.x:
				continue
			var fall := exp(-float(k * k) / 90.0)
			var band: float = Music.bands[mini(absi(k) * Music.BANDS / (n + 1), Music.BANDS - 1)]
			var h := (1.0 + 9.0 * band * Music.presence) * fall
			if h < 0.6:
				continue
			draw_line(Vector2(x, y - h), Vector2(x, y + h), Color(1, 1, 1, 0.35 + 0.5 * fall), 1.0, true)
		draw_circle(Vector2(at, y), 3.5 if _hover and can_seek else 2.5, Color(1, 1, 1, 0.95), true, -1.0, true)


## Previous, play, pause or next, drawn as fine filled glyphs.
class _Glyph:
	extends Button

	var kind := "play":
		set(v):
			kind = v
			queue_redraw()
	var px := 16.0

	func _init(k: String, glyph_px: float) -> void:
		kind = k
		px = glyph_px
		custom_minimum_size = Vector2(36, 36)
		size = Vector2(36, 36)
		focus_mode = Control.FOCUS_NONE
		flat = true
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		for st in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
			add_theme_stylebox_override(st, Kit.empty())
		mouse_entered.connect(queue_redraw)
		mouse_exited.connect(queue_redraw)
		button_down.connect(queue_redraw)
		button_up.connect(queue_redraw)

	func _draw() -> void:
		var a := 0.3 if disabled else (1.0 if is_hovered() else 0.8)
		var c := Color(1, 1, 1, a)
		var s := px * (0.92 if is_pressed() else 1.0)
		var o := size * 0.5
		match kind:
			"play":
				var w := s * 0.82
				draw_colored_polygon(PackedVector2Array([o + Vector2(-w * 0.4, -s * 0.5), o + Vector2(w * 0.6, 0), o + Vector2(-w * 0.4, s * 0.5)]), c)
			"pause":
				var bw := s * 0.22
				draw_rect(Rect2(o + Vector2(-s * 0.32, -s * 0.48), Vector2(bw, s * 0.96)), c)
				draw_rect(Rect2(o + Vector2(s * 0.1, -s * 0.48), Vector2(bw, s * 0.96)), c)
			"prev", "next":
				var d := -1.0 if kind == "prev" else 1.0
				var h := s * 0.5
				draw_colored_polygon(PackedVector2Array([o + Vector2(-h * 0.8 * d, -h), o + Vector2(h * 0.55 * d, 0), o + Vector2(-h * 0.8 * d, h)]), c)
				var bx := o.x + h * 0.62 * d - (s * 0.12 if d > 0 else 0.0)
				draw_rect(Rect2(Vector2(bx, o.y - h), Vector2(s * 0.12, s)), c)
