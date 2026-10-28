class_name ClaudeBlob
extends Control
## Claude, as a small jelly of Oazy's water living along the top of the orb
## popup. It walks the whole width in little hops, breathes, blinks and looks
## around, and everything it does follows the conversation:
##
## - What Claude is doing comes from the stream itself, so it's always true:
##   thinking (looks up, sways), reading and searching (paces, scanning),
##   running commands (focused), waiting for your OK (comes to the middle and
##   looks from the card to you), writing (its mouth moves with the words),
##   and trouble (a wince).
## - How Claude feels comes from Claude: a hidden [[mood:...]] tag at the
##   start of each reply (ClaudeMood), shown the moment it arrives.
## - What you do gets noticed: it watches you type, follows the pointer, reacts
##   to what you send before Claude has answered, and giggles when poked.
##
## The shape is one shader (claude_blob.gdshader); this script only eases the
## numbers it draws with. Nothing runs while the popup is closed.

const BOX := Vector2(104, 92)
const GROUND := 9.0
const R := 23.0
## The floor line sits this far above the bottom of the strip.
const FLOOR := 3.0
const GRAVITY := 1500.0
const HOP := 170.0
## Furthest one hop goes.
const STRIDE := 30.0

## [joy, smile, lid, worry, eyes, mouth open, blush, mouth width].
const FACES := {
	"calm": [0.0, 0.35, 0.08, 0.0, 1.0, 0.0, 0.0, 1.0],
	"happy": [0.9, 0.85, 0.0, 0.0, 1.0, 0.22, 0.55, 1.05],
	"excited": [1.0, 1.0, 0.0, 0.0, 1.08, 0.5, 0.65, 1.1],
	"curious": [0.0, 0.2, 0.0, -0.15, 1.16, 0.1, 0.0, 0.7],
	"thoughtful": [0.0, 0.05, 0.32, 0.1, 0.96, 0.0, 0.0, 0.6],
	"concerned": [0.0, -0.4, 0.05, 0.75, 1.04, 0.05, 0.0, 0.85],
	"sorry": [0.0, -0.25, 0.3, 0.9, 0.96, 0.0, 0.15, 0.75],
	"playful": [0.45, 0.9, 0.0, 0.0, 1.0, 0.2, 0.35, 1.0],
	"proud": [0.7, 0.75, 0.25, 0.0, 1.0, 0.1, 0.3, 1.0],
	"surprised": [0.0, 0.0, 0.0, 0.1, 1.32, 0.62, 0.0, 0.48],
	# Not moods Claude picks: how it looks while doing things.
	"focused": [0.0, 0.05, 0.42, 0.0, 0.95, 0.0, 0.0, 0.55],
	"asking": [0.0, 0.25, 0.0, 0.25, 1.12, 0.06, 0.0, 0.8],
	"oops": [0.0, -0.45, 0.0, 0.7, 1.16, 0.18, 0.0, 0.7],
	"giggle": [1.0, 1.0, 0.0, 0.0, 1.0, 0.42, 0.7, 1.05],
	"sleepy": [0.0, 0.25, 0.68, 0.0, 0.92, 0.0, 0.0, 0.6],
}

## Room kept free on the right for the header's buttons.
var reserve_right := 0.0
## The popup it lives in: the pointer is followed while it's over it.
var area: Control

var _body: ColorRect
var _mat: ShaderMaterial
var _t := 0.0
var _active := false
## What Claude is doing: idle, listening, thinking, working, asking, writing.
var _doing := "idle"
var _work := ""
## How it feels, until when (then calm again).
var _mood := "calm"
var _mood_until := 0.0
## A quick look over the mood: a reaction to you, a poke, a wince.
var _react := ""
var _react_until := 0.0
var _face := FACES["calm"].duplicate()

var _x := -1.0
var _vx := 0.0
var _goal := -1.0
var _y := 0.0
var _vy := 0.0
var _air := false
var _rest_until := 0.0
var _sq := 0.0
var _sqv := 0.0
var _lean := 0.0
var _leanv := 0.0
var _wob := 0.3
var _phase := 0.0
var _gaze := Vector2.ZERO
var _look := Vector2.ZERO
var _look_until := 0.0
var _blink := 0.0
var _blink_at := 2.0
var _blinks := 0
var _wink := 0.0
var _wink_until := 0.0
var _talk := 0.0
var _error := 0.0
var _typed_at := -100.0
var _mouse := Vector2.ZERO
var _mouse_at := -100.0
var _next_idle := 1.5
var _busy_since := 0.0
var _quiet_since := 0.0
var _pokes: Array[float] = []
var _beat := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size.y = 78
	_body = ColorRect.new()
	_body.size = BOX
	_body.mouse_filter = Control.MOUSE_FILTER_STOP
	_body.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_body.tooltip_text = "Claude · Claude Code in your home folder"
	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://shaders/claude_blob.gdshader")
	_mat.set_shader_parameter("box", BOX)
	_mat.set_shader_parameter("ground", GROUND)
	_mat.set_shader_parameter("radius", R)
	_body.material = _mat
	_sync_colors()
	App.accent_changed.connect(func(_c: Color) -> void: _sync_colors())
	_body.gui_input.connect(_on_body_input)
	add_child(_body)
	resized.connect(func() -> void:
		if _x < 0.0:
			_x = _home_x()
			_goal = _x
		_x = clampf(_x, _min_x(), _max_x())
		_goal = clampf(_goal, _min_x(), _max_x())
		queue_redraw()
		_apply()
	)
	set_process(false)


## The same water as the orb: the accent and its partner.
func _sync_colors() -> void:
	_mat.set_shader_parameter("color_a", App.accent)
	_mat.set_shader_parameter("color_b", App.accent_pair(App.accent))


func _draw() -> void:
	# The floor it sits on: one hairline fading out at both ends.
	var y := size.y - FLOOR
	var clear := Color(1, 1, 1, 0)
	draw_polyline_colors(PackedVector2Array([Vector2(0, y), Vector2(size.x * 0.5, y), Vector2(size.x, y)]),
		PackedColorArray([clear, Color(1, 1, 1, 0.07), clear]), 1.0)


# --- What the popup tells it -------------------------------------------------------------------

## Shown or hidden with the popup; nothing runs while it's closed.
func set_active(on: bool) -> void:
	if _active == on:
		return
	_active = on
	set_process(on)
	if on:
		var long := _t - _quiet_since > 40.0
		_quiet_since = _t
		_look = Vector2.ZERO
		_look_until = _t + 1.2
		_jump(150.0)
		if long:
			_reaction("happy", 0.9)


## A fresh conversation: back home, calm.
func reset() -> void:
	_doing = "idle"
	_mood = "calm"
	_react = ""
	_talk = 0.0
	_error = 0.0
	_goal = _home_x()
	_jump(150.0)


## You're typing: it watches the box, nodding along.
func typing() -> void:
	_typed_at = _t
	_quiet_since = _t
	_sqv += 0.5
	if _doing == "idle":
		_doing = "listening"


## You sent something: a quick reaction to it, then it gets thinking.
func heard(text: String) -> void:
	_quiet_since = _t
	var how := ClaudeMood.hearing(text)
	_reaction(how, 1.3)
	match how:
		"happy":
			_jump(210.0)
		"excited":
			_jump(230.0)
			_beat = _t + 0.42
		"surprised":
			_jump(190.0)
		"concerned":
			_sqv += 2.4
		"curious":
			_leanv += 1.4
	_mood = "calm"
	_set_doing("thinking")


func thinking() -> void:
	_set_doing("thinking")


## A tool started: how it moves depends on what kind.
func working(tool_name: String) -> void:
	match tool_name:
		"Read", "NotebookRead", "Glob", "Grep", "LS":
			_work = "read"
		"WebFetch", "WebSearch":
			_work = "web"
		"Bash", "PowerShell", "BashOutput", "KillShell":
			_work = "run"
		"Edit", "MultiEdit", "Write", "NotebookEdit", "TodoWrite":
			_work = "make"
		_:
			_work = "read"
	_set_doing("working")


## The reply's words are arriving.
func writing() -> void:
	_set_doing("writing")


## Some more words came: the mouth moves with them.
func talk(chars: int) -> void:
	_talk = minf(1.0, _talk + chars * 0.035)


## Claude said how it feels.
func feel(mood: String) -> void:
	if not FACES.has(mood) or not ClaudeMood.MOODS.has(mood):
		return
	var changed := mood != _mood
	_mood = mood
	_mood_until = _t + 14.0
	if mood == "playful":
		_wink_until = _t + 0.7
	if changed:
		match mood:
			"excited":
				_jump(220.0)
			"happy", "proud":
				_jump(160.0)
			"surprised":
				_sqv -= 3.0
			"sorry", "concerned":
				_sqv += 2.0


## Claude is waiting for your OK.
func asking() -> void:
	_set_doing("asking")
	_goal = _mid_x()
	_look_until = 0.0
	if not _air:
		_jump(190.0)


func answered(allow: bool) -> void:
	_reaction("happy" if allow else "calm", 1.0)
	if allow:
		_jump(170.0)
	else:
		_sqv += 1.6
	_set_doing("thinking")


## The reply is finished.
func done(reply: String) -> void:
	_talk = 0.0
	if _mood_until < _t or _mood == "calm":
		var guess := ClaudeMood.guess(reply)
		if guess != "calm":
			feel(guess)
	_set_doing("idle")
	_next_idle = _t + 2.5
	if _mood == "excited":
		_beat = _t + 0.5


## Something went wrong.
func oops() -> void:
	_reaction("oops", 3.0)
	_error = 0.7
	_sqv += 3.4
	_leanv += 4.0
	_set_doing("idle")


func _set_doing(what: String) -> void:
	if what != _doing:
		_busy_since = _t
	_doing = what
	_quiet_since = _t


func _reaction(face: String, secs: float) -> void:
	_react = face
	_react_until = _t + secs


func _on_body_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		_pokes = _pokes.filter(func(at: float) -> bool: return _t - at < 2.0)
		_pokes.append(_t)
		_quiet_since = _t
		if _pokes.size() >= 4:
			_reaction("surprised", 0.8)
			_wink_until = _t + 0.9
			_pokes.clear()
		else:
			_reaction("giggle", 1.0)
		_jump(240.0)
		Sfx.play(&"move")
		accept_event()


# --- Moving ------------------------------------------------------------------------------------

func _min_x() -> float:
	return R + 8.0


func _max_x() -> float:
	return maxf(_min_x(), size.x - reserve_right - R - 8.0)


func _home_x() -> float:
	return _min_x() + 14.0


func _mid_x() -> float:
	return clampf(size.x * 0.5, _min_x(), _max_x())


func _jump(v: float) -> void:
	if _air:
		return
	_air = true
	_vy = v
	_sqv -= v * 0.012
	var away := _goal - _x
	var air_time := 2.0 * v / GRAVITY
	_vx = signf(away) * minf(absf(away), STRIDE * v / HOP) / air_time if absf(away) > 2.0 else 0.0


func _process(delta: float) -> void:
	if size.x <= 0.0:
		return
	# Real time for what it decides; small steps for the jelly, so a slow
	# frame never makes it jump or stall.
	var left := minf(delta, 0.25)
	while left > 0.0:
		var dt := minf(left, 1.0 / 60.0)
		left -= dt
		_t += dt
		_think(dt)
		_move(dt)
	_eyes(minf(delta, 0.1))
	_expression(minf(delta, 0.1))
	_apply()


## What it wants to do right now, from what's going on.
func _think(_dt: float) -> void:
	if _react != "" and _t > _react_until:
		_react = ""
	if _mood != "calm" and _t > _mood_until:
		_mood = "calm"
	if _doing == "listening" and _t - _typed_at > 1.6:
		_doing = "idle"
	var mouse := get_global_mouse_position()
	if mouse.distance_squared_to(_mouse) > 4.0:
		_mouse = mouse
		_mouse_at = _t
	if _beat > 0.0 and _t > _beat and not _air:
		_beat = 0.0
		_jump(190.0)

	match _doing:
		"idle":
			if _t > _next_idle:
				_next_idle = _t + randf_range(2.6, 6.0)
				var r := randf()
				if r < 0.42:
					# Wander somewhere else along the strip.
					var to := randf_range(_min_x(), _max_x())
					if absf(to - _x) < 50.0:
						to = clampf(_x + signf(to - _x + 0.01) * 80.0, _min_x(), _max_x())
					_goal = to
				elif r < 0.8:
					_look = Vector2(randf_range(-1.0, 1.0), randf_range(-0.5, 0.7))
					_look_until = _t + randf_range(0.9, 1.8)
				elif r < 0.9:
					_jump(150.0)
				else:
					_look = Vector2.ZERO
					_look_until = _t + 1.4
		"thinking":
			# Paces a little, slowly, in thought.
			if _t > _next_idle:
				_next_idle = _t + randf_range(2.2, 3.4)
				_goal = clampf(_x + randf_range(-46.0, 46.0), _min_x(), _max_x())
		"working":
			if _work == "read" or _work == "web":
				if _t > _next_idle:
					_next_idle = _t + randf_range(1.4, 2.2)
					var span := minf(70.0, (_max_x() - _min_x()) * 0.5)
					_goal = clampf(_x + (span if _x < _mid_x() else -span), _min_x(), _max_x())
			elif _work == "make":
				if _t > _next_idle and not _air:
					_next_idle = _t + randf_range(0.9, 1.4)
					_goal = clampf(_x + randf_range(-18.0, 18.0), _min_x(), _max_x())
					_jump(130.0)
		"asking":
			_goal = _mid_x()
		"writing":
			pass
	# A hop at a time towards where it's going.
	if not _air and _t > _rest_until and absf(_goal - _x) > 3.0:
		_jump(HOP)


func _move(dt: float) -> void:
	if _air:
		_x += _vx * dt
		_vy -= GRAVITY * dt
		_y += _vy * dt
		if _y <= 0.0:
			var impact := -_vy
			_y = 0.0
			_vy = 0.0
			_vx = 0.0
			_air = false
			_sqv += impact * 0.016
			_wob = minf(1.4, _wob + impact * 0.0025)
			_rest_until = _t + randf_range(0.08, 0.16)
	_x = clampf(_x, _min_x(), _max_x())

	# Jelly: squash and lean spring back with a soft wobble.
	var breathe := sin(_t * 1.7) * (0.014 if _doing != "thinking" else 0.024)
	var rest := breathe
	if _air:
		rest = -clampf(absf(_vy) / 900.0, 0.0, 0.14)
	if _doing == "working" and _work == "run":
		rest += sin(_t * 8.0) * 0.022
	if _sleepy():
		rest += 0.05 + sin(_t * 0.9) * 0.02
	rest += _talk * sin(_t * 13.0) * 0.02
	_sqv += (-180.0 * (_sq - rest) - 15.0 * _sqv) * dt
	_sq = clampf(_sq + _sqv * dt, -0.24, 0.3)
	var lean_to := clampf(_vx / 700.0, -0.2, 0.2)
	if _doing == "thinking":
		lean_to += sin(_t * 1.1) * 0.07
	elif _face_name() == "curious":
		lean_to += 0.12
	_leanv += (-120.0 * (_lean - lean_to) - 11.0 * _leanv) * dt
	_lean = clampf(_lean + _leanv * dt, -0.32, 0.32)
	var calm_wob := 0.3 + (0.25 if _doing == "working" else 0.0) + _talk * 0.2
	_wob = lerpf(_wob, calm_wob, 1.0 - exp(-dt * 1.6))
	_phase += dt * (2.0 + _wob * 2.4)
	_error = maxf(0.0, _error - dt * 0.35)
	_talk = maxf(0.0, _talk - dt * 1.8)


func _eyes(dt: float) -> void:
	var to := Vector2.ZERO
	if _t < _look_until:
		to = _look
	else:
		match _doing:
			"listening":
				# Down at the box you're typing in.
				to = Vector2(clampf((_mid_x() - _x) / 260.0, -0.5, 0.5), -0.95)
			"thinking":
				to = Vector2(0.75 if fmod(_t - _busy_since, 4.4) < 2.2 else -0.75, 0.75)
			"working":
				match _work:
					"read":
						to = Vector2(sin(_t * 2.6) * 0.7, -0.45)
					"web":
						to = Vector2(sin(_t * 1.6) * 0.5, 0.55)
					_:
						to = Vector2(0.0, -0.4)
			"asking":
				# From the card below to you, and back.
				to = Vector2(0.0, -0.95) if fmod(_t - _busy_since, 2.8) < 1.5 else Vector2(0.0, 0.05)
			"writing":
				to = Vector2(sin(_t * 0.7) * 0.15, -0.2)
			_:
				to = Vector2(0.0, -0.1)
		# The pointer, when it's moving over the popup.
		if (_doing == "idle" or _doing == "writing") and _t - _mouse_at < 2.2 and _over_area(_mouse):
			var face := global_position + Vector2(_x, size.y - FLOOR - R * 1.1 - _y)
			var v := _mouse - face
			to = Vector2(clampf(v.x / 170.0, -1.0, 1.0), clampf(-v.y / 140.0, -1.0, 1.0))
	if _air and _doing == "idle":
		to.y += 0.3
	if _sleepy():
		to = Vector2(0.0, -0.5)
	_gaze = _gaze.lerp(to, 1.0 - exp(-dt * 11.0))

	if _t > _blink_at:
		var k := (_t - _blink_at) / 0.15
		_blink = sin(clampf(k, 0.0, 1.0) * PI)
		if k >= 1.0:
			_blink = 0.0
			if _blinks == 0 and randf() < 0.2:
				_blinks = 1
				_blink_at = _t + 0.09
			else:
				_blinks = 0
				_blink_at = _t + randf_range(2.2, 5.5)
	var wink_to := 1.0 if _t < _wink_until else 0.0
	_wink = lerpf(_wink, wink_to, 1.0 - exp(-dt * 16.0))


func _expression(dt: float) -> void:
	var target: Array = FACES[_face_name()]
	var k := 1.0 - exp(-dt * 9.0)
	for i in _face.size():
		_face[i] = lerpf(float(_face[i]), float(target[i]), k)


func _face_name() -> String:
	if _react != "":
		return _react
	if _sleepy():
		return "sleepy"
	match _doing:
		"thinking":
			return "thoughtful" if _mood == "calm" else _mood
		"working":
			return "focused" if _work != "make" else "calm"
		"asking":
			return "asking"
	return _mood


func _sleepy() -> bool:
	return _doing == "idle" and _t - _quiet_since > 45.0 and _t - _mouse_at > 20.0


func _over_area(p: Vector2) -> bool:
	return area != null and is_instance_valid(area) and area.get_global_rect().has_point(p)


func _apply() -> void:
	if _body == null:
		return
	_body.position = Vector2(roundf(_x - BOX.x * 0.5), size.y - FLOOR + GROUND - BOX.y)
	var m := _mat
	m.set_shader_parameter("lift", _y)
	m.set_shader_parameter("squash", _sq)
	m.set_shader_parameter("lean", _lean)
	m.set_shader_parameter("wobble", _wob)
	m.set_shader_parameter("wob_phase", _phase)
	m.set_shader_parameter("gaze", _gaze)
	m.set_shader_parameter("blink", _blink)
	m.set_shader_parameter("wink", _wink)
	m.set_shader_parameter("joy", _face[0])
	var talk_open := _talk * (0.3 + 0.32 * absf(sin(_t * 12.0 + sin(_t * 4.3) * 2.0)))
	m.set_shader_parameter("smile", _face[1])
	m.set_shader_parameter("lid", _face[2])
	m.set_shader_parameter("worry", _face[3])
	m.set_shader_parameter("eye_size", _face[4])
	m.set_shader_parameter("mouth_open", clampf(float(_face[5]) + talk_open, 0.0, 1.0))
	m.set_shader_parameter("blush", _face[6])
	m.set_shader_parameter("mouth_w", float(_face[7]) * (1.0 - _talk * 0.15))
	m.set_shader_parameter("error", _error)
