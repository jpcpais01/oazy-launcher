class_name ClaudeBlob
extends Control
## Claude, as a small jelly of Oazy's water living on the roof of the orb
## popup, outside it. It walks the whole width in little hops, breathes, blinks and looks
## around, and everything it does follows the conversation:
##
## - What Claude is doing comes from the stream itself, so it's always true:
##   thinking (looks up, sways, hand on its chin), reading and searching (a
##   magnifier), running commands (a little terminal), making changes (a
##   hammer), waiting for your OK (comes to the middle and points at the
##   card), writing (its mouth moves with the words), and trouble (a wince).
## - How Claude feels comes from Claude: a hidden [[mood:...]] tag at the
##   start of each reply (ClaudeMood), shown the moment it arrives, with eyes
##   to match (hearts, stars, >< when laughing) and a little sign over its head.
## - What it's about comes from Claude too ([[topic:...]]), or from your own
##   words first: then it puts on a little act while it works (ClaudeScene),
##   a chart and coins for money, chalk on a board for physics, and many more.
## - What you do gets noticed: it watches you type, follows the pointer, waves
##   hello, reacts to what you send before Claude has answered, goes shy when
##   you hover it, giggles when poked and gets dizzy when poked a lot.
## - Left alone it has a life: stretches, whistles, blows bubbles, chases a
##   butterfly, sneezes, dances, does a flip, bops along when music plays,
##   and in the end dozes off.
## - Now and then it has an idea of its own (ClaudeIdeas): it hops home and
##   turns to the bubble it says it in.
##
## The jelly is one shader (claude_blob.gdshader); props and signs are plain
## canvas drawing on layers around it. This script only eases the numbers.
## Nothing runs while the popup is closed.

## The shader's rect: wide, so the arm can reach a prop beside it.
const BOX := Vector2(220, 92)
## What you can poke.
const HIT := Vector2(58, 56)
const GROUND := 9.0
const R := 23.0
## The floor sits this far above the bottom of the strip.
const FLOOR := 1.0
const GRAVITY := 1500.0
const HOP := 170.0
## Furthest one hop goes.
const STRIDE := 30.0

## [joy, smile, lid, worry, eyes, mouth open, blush, mouth width,
##  hearts, stars, squint, swirl]; missing ones are 0.
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
	"loving": [0.0, 0.9, 0.0, 0.0, 1.05, 0.18, 0.75, 0.95, 1.0],
	"amazed": [0.0, 0.7, 0.0, 0.0, 1.1, 0.5, 0.3, 0.85, 0.0, 1.0],
	"laughing": [0.0, 1.0, 0.0, 0.0, 1.0, 0.75, 0.6, 1.15, 0.0, 0.0, 1.0],
	"shy": [0.55, 0.5, 0.25, 0.15, 0.94, 0.0, 1.0, 0.55],
	"confused": [0.0, -0.1, 0.12, 0.5, 1.08, 0.06, 0.0, 0.6],
	"determined": [0.0, 0.1, 0.36, -0.35, 1.0, 0.0, 0.0, 0.7],
	# Not moods Claude picks: how it looks while doing things.
	"focused": [0.0, 0.05, 0.42, 0.0, 0.95, 0.0, 0.0, 0.55],
	"asking": [0.0, 0.25, 0.0, 0.25, 1.12, 0.06, 0.0, 0.8],
	"oops": [0.0, -0.45, 0.0, 0.7, 1.16, 0.18, 0.0, 0.7],
	"giggle": [1.0, 1.0, 0.0, 0.0, 1.0, 0.42, 0.7, 1.05],
	"sleepy": [0.0, 0.25, 0.68, 0.0, 0.92, 0.0, 0.0, 0.6],
	"dizzy": [0.0, 0.1, 0.0, 0.25, 1.1, 0.3, 0.0, 0.7, 0.0, 0.0, 0.0, 1.0],
	"whistle": [0.0, 0.0, 0.3, 0.0, 1.0, 0.42, 0.0, 0.3],
	"yawn": [0.0, 0.0, 0.8, 0.1, 0.94, 0.9, 0.0, 0.62],
	"achoo": [0.0, 0.0, 0.1, 0.35, 1.0, 0.45, 0.2, 0.5],
	"squeeze": [0.0, 0.2, 0.0, 0.0, 1.0, 0.7, 0.3, 0.9, 0.0, 0.0, 1.0],
	"chomp": [0.6, 0.5, 0.0, 0.0, 1.0, 0.2, 0.4, 0.75],
}
## A sign over its head for some moods.
const SIGNS := {"curious": "?", "confused": "?", "surprised": "!", "concerned": "sweat", "sorry": "tear", "oops": "sweat"}

## Room kept free on the right.
var reserve_right := 0.0
## Kept clear of at both ends (the popup's rounded corners).
var inset := 0.0
## The popup it lives in: the pointer is followed while it's over it.
var area: Control

var _body: ColorRect
var _hit: Control
var _front: Control
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
var _face := _face_of("calm")

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
var _hover_since := -1.0
var _next_idle := 1.5
var _busy_since := 0.0
var _quiet_since := 0.0
var _pokes: Array[float] = []
var _beat := 0.0
## Saying an idea: stays home, turned to its bubble.
var _presenting := false

## The arm: how far out (0..1), and the hand, in the shader's pixels.
var _arm := 0.0
var _hand := Vector2(30, 30)
var _handv := Vector2.ZERO
## A flip in the air.
var _spin := 0.0
var _flip_at := -1.0
var _flip_len := 0.0
var _flip_dir := 1.0
## Something it's doing on its own, from _act_at for _act_len seconds.
var _act := ""
var _act_at := 0.0
var _act_len := 0.0
var _act_side := 1.0
var _act_spot := Vector2.ZERO
var _act_beat := 0
## A sign over its head (?, !, ..., a bulb, a drop of sweat, a tear).
var _sign := ""
var _sign_at := 0.0
var _sign_until := 0.0
## What it's about, and the act it puts on for it.
var _topic := ""
var _scene: ClaudeScene
var _gone: Array[ClaudeScene] = []
var _layers := {}
var _kicks := 0
## Its own sparkles, notes, hearts and z's, drawn with a scene's helpers.
var _fx := ClaudeScene.new()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body = ColorRect.new()
	_body.size = BOX
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://shaders/claude_blob.gdshader")
	_mat.set_shader_parameter("box", BOX)
	_mat.set_shader_parameter("ground", GROUND)
	_mat.set_shader_parameter("radius", R)
	_body.material = _mat
	_sync_colors()
	App.accent_changed.connect(func(_c: Color) -> void: _sync_colors())
	add_child(_body)
	_hit = Control.new()
	_hit.size = HIT
	_hit.mouse_filter = Control.MOUSE_FILTER_STOP
	_hit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_hit.tooltip_text = "Claude · Claude Code in your home folder"
	_hit.gui_input.connect(_on_body_input)
	add_child(_hit)
	_front = Control.new()
	_front.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_front.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_front.draw.connect(_draw_front)
	add_child(_front)
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
			_reaction("happy", 1.2)
			_start_act("wave", 1.6)


## It just had an idea: a little jump of surprise and a bulb over its head,
## then home to say it, looking over at its bubble. Off again when the
## bubble goes.
func present(on: bool) -> void:
	if on == _presenting:
		return
	_presenting = on
	if on:
		_end_scene()
		_act = ""
		_quiet_since = _t
		_goal = _home_x()
		_reaction("surprised", 0.55)
		_show_sign("bulb", 2.2)
		_mood = "excited"
		_mood_until = _t + 6.0
		_beat = _t + 0.5
		_jump(230.0)
	else:
		_goal = clampf(_x, _min_x(), _max_x())


## Where its body is on screen (pokes land there, not on the popup behind).
func get_body_rect() -> Rect2:
	return _hit.get_global_rect() if _hit else Rect2()


## How much room it needs on the left to say an idea from home.
func home_room() -> float:
	return _home_x() + R + 14.0


## A fresh conversation: back home, calm.
func reset() -> void:
	_doing = "idle"
	_mood = "calm"
	_react = ""
	_act = ""
	_sign = ""
	_topic = ""
	_end_scene()
	_talk = 0.0
	_error = 0.0
	_goal = _home_x()
	_jump(150.0)


## You're typing: it watches the box, nodding along.
func typing() -> void:
	_typed_at = _t
	_quiet_since = _t
	_sqv += 0.5
	if _act != "" and _act != "wave":
		_act = ""
	if _doing == "idle":
		_doing = "listening"


## You sent something: a quick reaction to it, then it gets thinking (and,
## if it can tell what it's about, gets its props out).
func heard(text: String) -> void:
	_quiet_since = _t
	_act = ""
	var how := ClaudeMood.hearing(text)
	_reaction(how, 1.3)
	match how:
		"happy", "loving":
			_jump(210.0)
			if how == "loving":
				_hearts(4)
		"excited":
			_jump(230.0)
			_beat = _t + 0.42
		"laughing":
			_start_act("laugh", 1.3)
		"surprised":
			_jump(190.0)
			_show_sign("!", 1.2)
		"concerned":
			_sqv += 2.4
		"curious":
			_leanv += 1.4
	if ClaudeMood.greeting(text):
		_start_act("wave", 1.6)
	_mood = "calm"
	_set_doing("thinking")
	var about := ClaudeMood.topic(text)
	if about != "":
		_topic = about
	if _topic != "":
		_play(_topic)


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
	if _scene:
		_scene.mood = mood
	if mood == "playful":
		_wink_until = _t + 0.7
	if not changed:
		return
	if SIGNS.has(mood):
		_show_sign(SIGNS[mood], 2.4)
	match mood:
		"excited", "amazed":
			_jump(220.0)
			_sparkles(5)
		"happy", "proud":
			_jump(160.0)
			if mood == "proud":
				_sparkles(3)
		"loving":
			_jump(170.0)
			_hearts(5)
		"laughing":
			_start_act("laugh", 1.6)
		"surprised":
			_sqv -= 3.0
		"sorry", "concerned":
			_sqv += 2.0
		"confused":
			_leanv -= 2.0
		"determined":
			_sqv += 1.2
			_leanv += 1.6
		"shy":
			_look = Vector2(-0.7, -0.6)
			_look_until = _t + 1.6


## Claude said what this is about ("none" puts the act away).
func topic(about: String) -> void:
	about = about.to_lower()
	if about == "none" or about == "":
		_topic = ""
		_end_scene()
		return
	if not ClaudeScene.has(about):
		return
	_topic = about
	if _doing != "idle" or _scene:
		_play(about)


## Claude is waiting for your OK.
func asking() -> void:
	_set_doing("asking")
	_goal = _mid_x()
	_look_until = 0.0
	_show_sign("?", 1.6)
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
	_show_sign("sweat", 2.6)
	_error = 0.7
	_sqv += 3.4
	_leanv += 4.0
	_set_doing("idle")


func _set_doing(what: String) -> void:
	if what != _doing:
		_busy_since = _t
	_doing = what
	_quiet_since = _t
	if _scene:
		_scene.paused = what == "asking"
		if what != "idle" and what != "listening":
			_scene.busy = true
		elif what == "idle":
			_scene.busy = false


func _reaction(face: String, secs: float) -> void:
	_react = face
	_react_until = _t + secs


func _show_sign(what: String, secs: float) -> void:
	_sign = what
	_sign_at = _t
	_sign_until = _t + secs


func _start_act(what: String, secs: float) -> void:
	_act = what
	_act_at = _t
	_act_len = secs
	_act_beat = 0
	_act_side = 1.0 if _x < _mid_x() else -1.0


func _act_u() -> float:
	return clampf((_t - _act_at) / maxf(_act_len, 0.01), 0.0, 1.0)


func _on_body_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		_pokes = _pokes.filter(func(at: float) -> bool: return _t - at < 2.0)
		_pokes.append(_t)
		_quiet_since = _t
		if _act != "wave":
			_act = ""
		if _pokes.size() >= 4:
			_reaction("dizzy", 2.2)
			_sparkles(6)
			_pokes.clear()
		elif _pokes.size() == 3:
			_reaction("laughing", 1.0)
			_start_act("laugh", 0.9)
		else:
			_reaction("giggle", 1.0)
		_jump(240.0)
		Sfx.play(&"move")
		_hit.accept_event()


# --- Acts on a topic ---------------------------------------------------------------------------

func _play(about: String) -> void:
	if _presenting or size.x <= 0.0:
		return
	if _scene and _scene.kind == about and _scene.on:
		_scene.busy = _doing != "idle"
		return
	_end_scene()
	_scene = ClaudeScene.make(about, _x, _min_x(), _max_x(), size.y - FLOOR, size.x)
	_scene.accent = App.accent
	_scene.accent2 = App.accent_pair(App.accent)
	_scene.mood = _mood
	_scene.busy = _doing != "idle" and _doing != "listening"
	_scene.paused = _doing == "asking"
	_kicks = 0
	var back := Control.new()
	var front := Control.new()
	for c: Control in [back, front]:
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		c.modulate.a = 0.0
		add_child(c)
	move_child(back, _body.get_index())
	move_child(front, _front.get_index())
	var s := _scene
	back.draw.connect(func() -> void: s.draw_back(back))
	front.draw.connect(func() -> void: s.draw_front(front))
	_layers[s] = [back, front]


func _end_scene() -> void:
	if _scene:
		_scene.on = false
		_gone.append(_scene)
		_scene = null


func _staged() -> bool:
	return _scene != null and _scene.on and not _scene.paused


func _step_scenes(dt: float) -> void:
	if _scene and _scene.finished():
		_end_scene()
	var me := _me()
	var all: Array[ClaudeScene] = _gone.duplicate()
	if _scene:
		all.append(_scene)
	for s: ClaudeScene in all:
		s.me = me
		var arrived := s == _scene and absf(_x - s.stand()) < 7.0 and not _air
		s.step(dt, arrived)
		var ls: Array = _layers.get(s, [])
		for c: Control in ls:
			c.modulate.a = s.k
			c.queue_redraw()
	for s: ClaudeScene in _gone.duplicate():
		if s.done():
			_gone.erase(s)
			for c: Control in _layers.get(s, []):
				c.queue_free()
			_layers.erase(s)
	if _scene and _scene.kicks != _kicks:
		_kicks = _scene.kicks
		match _scene.kind:
			"sport":
				_sqv += 2.6
				if not _air and randf() < 0.3:
					_jump(110.0)
			"games":
				_leanv += 1.2
			_:
				_sqv += 1.4


## Where it is, for the act to draw on it: head, face, eyes, hand.
func _me() -> Dictionary:
	var g := _gaze
	var fb := Vector2(g.x * R * 0.2, R * 0.06 + g.y * R * 0.1)
	var spread := R * 0.36 * (1.0 - absf(g.x) * 0.08)
	var off := g * Vector2(R * 0.06, R * 0.04)
	return {
		"x": _x,
		"head": _to_strip(Vector2(0.0, R)),
		"face": _to_strip(fb),
		"eyes": [_to_strip(fb + Vector2(-spread, 0.0) + off), _to_strip(fb + Vector2(spread, 0.0) + off)],
		"eye_r": R * 0.2 * float(_face[4]),
		"half_w": R * (1.0 + _sq),
		"tilt": atan(_lean) - _spin,
		"hand": _hand_strip(),
	}


func _origin() -> Vector2:
	return Vector2(_body.position.x + BOX.x * 0.5, size.y - FLOOR)


## A point on the body (the shader's body space, y up) in roof pixels.
func _to_strip(bv: Vector2) -> Vector2:
	var sx := 1.0 + _sq
	var sy := 1.0 / sx
	var b := bv
	b.x /= 1.0 + 0.07 * clampf(b.y / R, 0.0, 1.0)
	var q := (b + Vector2(0.0, R)) * Vector2(sx, sy)
	q.x += _lean * q.y
	var p := q + Vector2(0.0, _y)
	if _spin != 0.0:
		var c := Vector2(0.0, _y + R * sy)
		p = (p - c).rotated(_spin) + c
	return _origin() + Vector2(p.x, -p.y)


func _hand_strip() -> Vector2:
	var sx := 1.0 + _sq
	var sy := 1.0 / sx
	var sh := Vector2(signf(_hand.x) * R * 0.42 * sx, _y + R * 0.72 * sy)
	var tip := sh.lerp(_hand, smoothstep(0.0, 1.0, _arm))
	return _origin() + Vector2(tip.x, -tip.y)


# --- Moving ------------------------------------------------------------------------------------

func _min_x() -> float:
	return inset + R + 8.0


func _max_x() -> float:
	if _presenting:
		return _home_x()
	return maxf(_min_x(), size.x - reserve_right - inset - R - 8.0)


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


func _flip() -> void:
	if _air:
		return
	_goal = _x
	_jump(330.0)
	_flip_at = _t
	_flip_len = 2.0 * 330.0 / GRAVITY
	_flip_dir = -1.0 if randf() < 0.5 else 1.0


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
	var d := minf(delta, 0.1)
	_eyes(d)
	_expression(d)
	_reach(d)
	_step_scenes(d)
	_fx.step(d, false)
	_apply()
	_front.queue_redraw()


## What it wants to do right now, from what's going on.
func _think(_dt: float) -> void:
	if _react != "" and _t > _react_until:
		_react = ""
	if _mood != "calm" and _t > _mood_until:
		_mood = "calm"
	if _sign != "" and _t > _sign_until:
		_sign = ""
	if _act != "" and _t > _act_at + _act_len:
		_end_act()
	if _doing == "listening" and _t - _typed_at > 1.6:
		_doing = "idle"
	var mouse := get_global_mouse_position()
	if mouse.distance_squared_to(_mouse) > 4.0:
		_mouse = mouse
		_mouse_at = _t
	if get_body_rect().has_point(mouse) and _active:
		if _hover_since < 0.0:
			_hover_since = _t
	else:
		_hover_since = -1.0
	if _beat > 0.0 and _t > _beat and not _air:
		_beat = 0.0
		_jump(190.0)
	if _doing == "thinking" and _t - _busy_since > 1.4 and _sign == "" and not _staged():
		_show_sign("...", 30.0)
	elif _sign == "..." and _doing != "thinking":
		_sign = ""
	if _sleepy() and fmod(_t, 1.5) < _dt:
		_fx._part("text", _to_strip(Vector2(R * 0.5, R * 0.9)), Vector2(7.0, -9.0), 2.4, {"t": "z", "s": 8.0 + randf() * 3.0, "c": Color(1, 1, 1, 0.75)})

	var staged := _staged()
	if staged:
		_goal = clampf(_scene.stand(), _min_x(), _max_x())
	match _doing:
		"idle":
			if _presenting:
				_goal = _home_x()
			elif _act != "":
				_act_think()
			elif not staged and _t > _next_idle:
				_next_idle = _t + randf_range(2.6, 6.0)
				_idle_pick()
		"thinking":
			# Paces a little, slowly, in thought.
			if not staged and _t > _next_idle and not _chin():
				_next_idle = _t + randf_range(2.2, 3.4)
				_goal = clampf(_x + randf_range(-46.0, 46.0), _min_x(), _max_x())
		"working":
			if staged:
				pass
			elif _work == "read" or _work == "web":
				if _t > _next_idle:
					_next_idle = _t + randf_range(1.4, 2.2)
					var span := minf(70.0, (_max_x() - _min_x()) * 0.5)
					_goal = clampf(_x + (span if _x < _mid_x() else -span), _min_x(), _max_x())
			elif _work == "make":
				if _t > _next_idle and not _air:
					_next_idle = _t + randf_range(0.9, 1.4)
					_goal = clampf(_x + randf_range(-18.0, 18.0), _min_x(), _max_x())
					_jump(130.0)
					_fx._part("spark", Vector2(_x + _tool_side() * 30.0, size.y - FLOOR - 2.0), Vector2(_tool_side() * 20.0, -30.0), 0.4, {"s": 2.6, "c": Color(1.0, 0.85, 0.45), "drag": 3.0})
		"asking":
			_goal = _mid_x()
		"writing":
			pass
	if _act == "wave" or _act == "laugh":
		_act_think()
	# A hop at a time towards where it's going.
	if not _air and _t > _rest_until and absf(_goal - _x) > 3.0:
		_jump(HOP)


## Something to do when nothing's going on.
func _idle_pick() -> void:
	if _sleepy():
		return
	if _music_on() and randf() < 0.5:
		_play("music")
		return
	var r := randf()
	if r < 0.3:
		# Wander somewhere else along the strip.
		var to := randf_range(_min_x(), _max_x())
		if absf(to - _x) < 50.0:
			to = clampf(_x + signf(to - _x + 0.01) * 80.0, _min_x(), _max_x())
		_goal = to
	elif r < 0.5:
		_look = Vector2(randf_range(-1.0, 1.0), randf_range(-0.5, 0.7))
		_look_until = _t + randf_range(0.9, 1.8)
	elif r < 0.55:
		_jump(150.0)
	elif r < 0.59:
		_look = Vector2.ZERO
		_look_until = _t + 1.4
	elif r < 0.65:
		_start_act("stretch", 2.4)
	elif r < 0.71:
		_start_act("whistle", 3.4)
	elif r < 0.77:
		_start_act("bubble", 4.2)
		_act_spot = Vector2.ZERO
	elif r < 0.82:
		_start_act("butterfly", 5.5)
		_act_spot = Vector2(_x + randf_range(-90.0, 90.0), 20.0)
	elif r < 0.87:
		_start_act("dance", 3.6)
	elif r < 0.91:
		_start_act("peek", 2.4)
	elif r < 0.94:
		_start_act("sneeze", 2.2)
	elif r < 0.97:
		_start_act("hum", 3.0)
	else:
		_flip()


func _music_on() -> bool:
	return Music.on and Music.presence > 0.3


## How its own little acts move it.
func _act_think() -> void:
	var u := _act_u()
	match _act:
		"dance":
			var b := int(u * 6.0)
			if b != _act_beat and not _air:
				_act_beat = b
				_jump(120.0)
				if b % 2 == 0:
					_notes(1)
		"whistle", "hum":
			var b := int(u * 6.0)
			if b != _act_beat:
				_act_beat = b
				_notes(1)
		"butterfly":
			if u > 0.45 and _act_beat == 0:
				_act_beat = 1
				_goal = clampf(_fly_at().x, _min_x(), _max_x())
				_jump(230.0)
		"sneeze":
			if u > 0.62 and _act_beat == 0:
				_act_beat = 1
				_sqv += 4.0
				_leanv -= _act_side * 5.0
				for i in 7:
					_fx._part("dot", _to_strip(Vector2(_act_side * R * 0.5, R * 0.2)), Vector2(_act_side * randf_range(30.0, 70.0), randf_range(-30.0, 10.0)), 0.6, {"g": 120.0, "s": randf_range(0.7, 1.3), "c": Color(0.8, 0.92, 1.0, 0.8)})
		"bubble":
			if u > 0.88 and _act_beat == 0:
				_act_beat = 1
				var at := _bubble_at()
				for i in 8:
					var a := i * TAU / 8.0
					_fx._part("dot", at, Vector2(cos(a), sin(a)) * 40.0, 0.4, {"s": 1.0, "c": Color(0.85, 0.95, 1.0, 0.8), "drag": 3.0})
				_reaction("surprised", 0.5)
		"peek":
			_goal = _x


func _end_act() -> void:
	match _act:
		"stretch":
			_sqv += 2.0
		"bubble":
			_reaction("giggle", 0.8)
		"butterfly":
			_reaction("happy", 0.8)
		"sneeze":
			_reaction("shy", 1.2)
	_act = ""


## The bubble it blows: grows at its mouth, then floats up.
func _bubble_at() -> Vector2:
	var u := _act_u()
	var mouth := _to_strip(Vector2(_act_side * R * 0.25, R * 0.6 - R * 0.85))
	if u < 0.45:
		return mouth + Vector2(_act_side * (3.0 + u * 14.0), 0.0)
	var f := (u - 0.45) / 0.55
	return mouth + Vector2(_act_side * (9.3 + f * 26.0) + sin(f * 9.0) * 3.0, -f * 44.0)


func _bubble_r() -> float:
	var u := _act_u()
	return clampf(u / 0.45, 0.0, 1.0) * 7.0


## The butterfly: flutters round it, then away.
func _fly_at() -> Vector2:
	var u := _act_u()
	var base := Vector2(lerpf(_act_spot.x, _x, smoothstep(0.0, 0.4, u)), size.y - FLOOR - 58.0)
	var away := smoothstep(0.7, 1.0, u)
	return base + Vector2(sin(_t * 2.3) * 16.0 + away * 90.0 * _act_side, sin(_t * 3.7) * 7.0 - away * 50.0)


func _move(dt: float) -> void:
	if _air:
		_x += _vx * dt
		_vy -= GRAVITY * dt
		_y += _vy * dt
		if _flip_at >= 0.0:
			var u := clampf((_t - _flip_at) / _flip_len, 0.0, 1.0)
			_spin = _flip_dir * TAU * (u * u * (3.0 - 2.0 * u))
		if _y <= 0.0:
			var impact := -_vy
			_y = 0.0
			_vy = 0.0
			_vx = 0.0
			_air = false
			_sqv += impact * 0.016
			_wob = minf(1.4, _wob + impact * 0.0025)
			_rest_until = _t + randf_range(0.08, 0.16)
			if _flip_at >= 0.0:
				_flip_at = -1.0
				_spin = 0.0
				_reaction("proud", 1.2)
				_sparkles(4)
	_x = clampf(_x, _min_x(), _max_x())

	# Jelly: squash and lean spring back with a soft wobble.
	var breathe := sin(_t * 1.7) * (0.014 if _doing != "thinking" else 0.024)
	var rest := breathe
	if _air:
		rest = -clampf(absf(_vy) / 900.0, 0.0, 0.14)
	if _doing == "working" and _work == "run" and not _staged():
		rest += sin(_t * 8.0) * 0.022
	if _sleepy():
		rest += 0.08 + sin(_t * 0.9) * 0.025
	rest += _talk * sin(_t * 13.0) * 0.02
	var lean_to := clampf(_vx / 700.0, -0.2, 0.2)
	if _scene and _scene.on:
		rest += _scene.bob() * _scene.k
		lean_to += _scene.lean() * _scene.k
	var u := _act_u()
	match _act:
		"stretch":
			rest -= 0.17 * sin(u * PI)
		"dance":
			lean_to += sin(u * TAU * 3.0) * 0.16
		"hum":
			lean_to += sin(u * TAU * 2.0) * 0.07
		"laugh":
			rest += sin(_t * 30.0) * 0.035
			lean_to += sin(_t * 15.0) * 0.04
		"sneeze":
			if u < 0.62:
				rest -= 0.1 * smoothstep(0.0, 0.62, u)
				lean_to += _act_side * 0.1 * smoothstep(0.2, 0.62, u)
		"peek":
			lean_to += _act_side * 0.2 * sin(u * PI)
			rest += 0.04 * sin(u * PI)
	if _react == "dizzy":
		lean_to += sin(_t * 6.0) * 0.12
	_sqv += (-180.0 * (_sq - rest) - 15.0 * _sqv) * dt
	_sq = clampf(_sq + _sqv * dt, -0.24, 0.3)
	if _doing == "thinking" and not _staged():
		lean_to += sin(_t * 1.1) * 0.07
	elif _face_name() == "curious":
		lean_to += 0.12
	elif _face_name() == "confused":
		lean_to -= 0.14
	elif _face_name() == "determined":
		lean_to += 0.08
	_leanv += (-120.0 * (_lean - lean_to) - 11.0 * _leanv) * dt
	_lean = clampf(_lean + _leanv * dt, -0.32, 0.32)
	var calm_wob := 0.3 + (0.25 if _doing == "working" else 0.0) + _talk * 0.2
	_wob = lerpf(_wob, calm_wob, 1.0 - exp(-dt * 1.6))
	_phase += dt * (2.0 + _wob * 2.4)
	_error = maxf(0.0, _error - dt * 0.35)
	_talk = maxf(0.0, _talk - dt * 1.8)


## Hand on its chin, every so often while it thinks.
func _chin() -> bool:
	return _doing == "thinking" and not _staged() and _t - _busy_since > 1.2 and fmod(_t - _busy_since, 7.0) < 3.6


func _tool_side() -> float:
	return 1.0 if _x < _mid_x() else -1.0


## Where the hand goes, in roof pixels (INF: arm in).
func _want_hand() -> Vector2:
	var u := _act_u()
	if _act == "wave":
		var s := _act_side
		return _to_strip(Vector2(s * R * 1.25 + sin(_t * 16.0) * 5.0, R * 1.05))
	if _act == "butterfly" and u > 0.35 and u < 0.7:
		return _fly_at() + Vector2(0, 6)
	if _doing == "asking":
		return _origin() + Vector2(_tool_side() * 30.0, -6.0)
	if _scene and _scene.on:
		var h := _scene.hand()
		if h != Vector2.INF and absf(_x - _scene.stand()) < 10.0:
			return h
		if not _scene.paused:
			return Vector2.INF
	if _doing == "working":
		var s := _tool_side()
		match _work:
			"read":
				return _to_strip(Vector2(s * R * 1.3 + sin(_t * 2.6) * 4.0, R * 0.05 + cos(_t * 2.6) * 2.0))
			"web":
				return _to_strip(Vector2(s * R * 1.3 + sin(_t * 1.6) * 6.0, R * 0.45))
			"run":
				return _to_strip(Vector2(s * R * 1.25, -R * 0.35))
			"make":
				return _to_strip(Vector2(s * R * 1.2, -R * 0.15))
	if _chin():
		return _to_strip(Vector2(R * 0.3, -R * 0.55))
	return Vector2.INF


func _reach(dt: float) -> void:
	var want := _want_hand()
	var o := _origin()
	if want != Vector2.INF:
		var rel := Vector2(want.x - o.x, o.y - want.y)
		rel.x = clampf(rel.x, -BOX.x * 0.5 + 6.0, BOX.x * 0.5 - 6.0)
		rel.y = clampf(rel.y, 3.0, BOX.y - GROUND - 5.0)
		if absf(rel.x) < 1.0:
			rel.x = 1.0 if _hand.x >= 0.0 else -1.0
		if _arm < 0.05 or signf(rel.x) != signf(_hand.x):
			# Starts from the side it grows out of.
			_hand = rel
			_handv = Vector2.ZERO
		# A soft spring, in small steps so a slow frame can't upset it.
		var left := dt
		while left > 0.0:
			var h := minf(left, 1.0 / 120.0)
			left -= h
			_handv += ((rel - _hand) * 260.0 - _handv * 24.0) * h
			_hand += _handv * h
		_arm = move_toward(_arm, 1.0, dt * 5.0)
	else:
		_arm = move_toward(_arm, 0.0, dt * 4.0)


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
						to = Vector2(_tool_side() * 0.8, -0.2 + cos(_t * 2.6) * 0.15)
					"web":
						to = Vector2(_tool_side() * 0.7 + sin(_t * 1.6) * 0.2, 0.45)
					"run":
						to = Vector2(_tool_side() * 0.6, -0.7)
					_:
						to = Vector2(_tool_side() * 0.6, -0.6)
			"asking":
				# From the card below to you, and back.
				to = Vector2(0.0, -0.95) if fmod(_t - _busy_since, 2.8) < 1.5 else Vector2(0.0, 0.05)
			"writing":
				to = Vector2(sin(_t * 0.7) * 0.15, -0.2)
			_:
				to = Vector2(0.0, -0.1)
		if _presenting and _doing == "idle":
			# Over at its idea, with a glance back at you now and then.
			to = Vector2(0.85, 0.25) if fmod(_t, 5.0) < 3.8 else Vector2(0.1, -0.15)
		var u := _act_u()
		match _act:
			"bubble":
				to = _toward(_bubble_at())
			"butterfly":
				to = _toward(_fly_at())
			"whistle":
				to = Vector2(0.5 * _act_side, 0.6)
			"peek":
				to = Vector2(_act_side * 0.6, -1.0)
			"stretch":
				to = Vector2(0.0, 0.8 * sin(u * PI))
			"sneeze":
				to = Vector2(_act_side * 0.4, 0.5)
		if _staged():
			var at := _scene.look()
			if at != Vector2.INF:
				to = _toward(at)
		elif _doing == "thinking" and _chin():
			to = Vector2(0.55, 0.7)
		# The pointer, when it's moving over the popup.
		if (_doing == "idle" or _doing == "writing") and _act == "" and not _staged() and _t - _mouse_at < 2.2 and _over_area(_mouse):
			var face := global_position + Vector2(_x, size.y - FLOOR - R * 1.1 - _y)
			var v := _mouse - face
			to = Vector2(clampf(v.x / 170.0, -1.0, 1.0), clampf(-v.y / 140.0, -1.0, 1.0))
		if _hover_since >= 0.0 and _t - _hover_since > 0.9 and _act == "":
			# Shy: looks away and back.
			to = Vector2(-0.7, -0.5) if fmod(_t - _hover_since, 3.0) < 1.8 else Vector2(0.2, 0.1)
	if _air and _doing == "idle" and _act == "":
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


## A gaze from its face towards a point on the roof.
func _toward(p: Vector2) -> Vector2:
	var face := _origin() + Vector2(0.0, -R * 1.1 - _y)
	var v := p - face
	v.y = -v.y
	return v.normalized() * clampf(v.length() / 34.0, 0.0, 1.0) if v.length() > 0.5 else Vector2.ZERO


func _expression(dt: float) -> void:
	var target := _face_of(_face_name())
	var k := 1.0 - exp(-dt * 9.0)
	for i in _face.size():
		_face[i] = lerpf(float(_face[i]), float(target[i]), k)


static func _face_of(name: String) -> Array:
	var f: Array = FACES.get(name, FACES["calm"]).duplicate()
	while f.size() < 12:
		f.append(0.0)
	return f


func _face_name() -> String:
	if _react != "":
		return _react
	if _sleepy():
		return "sleepy"
	var u := _act_u()
	match _act:
		"stretch":
			if u > 0.25 and u < 0.8:
				return "yawn"
		"whistle", "bubble":
			if _act == "whistle" or u < 0.45:
				return "whistle"
		"hum":
			return "happy"
		"dance":
			return "excited"
		"laugh":
			return "laughing"
		"sneeze":
			return "achoo" if u < 0.62 else "squeeze"
		"butterfly":
			return "curious" if u < 0.45 else "happy"
		"peek":
			return "curious"
		"wave":
			return "happy"
	if _hover_since >= 0.0 and _t - _hover_since > 0.9 and _doing == "idle":
		return "shy"
	if _doing == "asking":
		return "asking"
	if _scene and _scene.on and _mood == "calm" and _scene.face() != "":
		return _scene.face()
	match _doing:
		"thinking":
			return "thoughtful" if _mood == "calm" else _mood
		"working":
			return "focused" if _work != "make" else "determined"
	return _mood


func _sleepy() -> bool:
	return not _presenting and _doing == "idle" and _scene == null and _act == "" and _t - _quiet_since > 45.0 and _t - _mouse_at > 20.0


func _over_area(p: Vector2) -> bool:
	return area != null and is_instance_valid(area) and area.get_global_rect().has_point(p)


func _sparkles(n: int) -> void:
	for i in n:
		var a := randf_range(-PI * 0.95, -PI * 0.05)
		var from := _to_strip(Vector2(0.0, R * 0.2))
		_fx._part("spark", from + Vector2(cos(a), sin(a)) * R * 1.1, Vector2(cos(a), sin(a)) * randf_range(16.0, 30.0), randf_range(0.7, 1.1), {"s": randf_range(2.4, 3.6), "c": Color(1.0, 0.9, 0.55), "drag": 2.0})


func _hearts(n: int) -> void:
	for i in n:
		var from := _to_strip(Vector2(randf_range(-R, R), R * 0.6))
		_fx._part("heart", from, Vector2(randf_range(-10.0, 10.0), randf_range(-26.0, -16.0)), randf_range(1.2, 1.8), {"s": randf_range(6.0, 8.5), "c": Color(1.0, 0.42, 0.55)})


func _notes(n: int) -> void:
	for i in n:
		var s := _act_side if _act != "" else (1.0 if randf() < 0.5 else -1.0)
		var from := _to_strip(Vector2(s * R * 0.8, R * 0.3))
		_fx._part("note", from, Vector2(s * randf_range(6.0, 14.0), -randf_range(16.0, 24.0)), 1.6, {"s": randf_range(5.0, 6.5), "c": Color(ClaudeScene.PALETTE[randi() % ClaudeScene.PALETTE.size()]).lightened(0.25), "two": randf() < 0.35})


# --- Drawing what's around it ------------------------------------------------------------------

func _draw_front() -> void:
	var ci := _front
	var fx := _fx
	if _arm > 0.3 and not (_scene and _scene.on and _scene.hand() != Vector2.INF):
		_draw_tool(ci)
	match _act:
		"bubble":
			var at := _bubble_at()
			var r := _bubble_r()
			if _act_u() < 0.88 and r > 0.5:
				fx._disc(ci, at, r, Color(0.8, 0.95, 1.0, 0.12))
				fx._ring(ci, at, r, Color(1, 1, 1, 0.55), 1.0)
				fx._disc(ci, at + Vector2(-r * 0.35, -r * 0.4), r * 0.22, Color(1, 1, 1, 0.7))
		"butterfly":
			var p := _fly_at()
			var flap := absf(sin(_t * 15.0))
			var col := Color(1.0, 0.75, 0.35, clampf(minf(_act_u() * 8.0, (1.0 - _act_u()) * 6.0), 0.0, 1.0))
			fx._ellipse_rot(ci, p + Vector2(-2.2 * flap, -1), 3.0 * flap + 0.4, 2.5, 0.3, col)
			fx._ellipse_rot(ci, p + Vector2(2.2 * flap, -1), 3.0 * flap + 0.4, 2.5, -0.3, col)
			fx._line(ci, p + Vector2(0, -2.5), p + Vector2(0, 1.8), Color(ClaudeScene.INK, col.a), 1.0)
	fx._draw_parts(ci)
	_draw_sign(ci)


## What it holds while it works, when there's no act on.
func _draw_tool(ci: CanvasItem) -> void:
	var fx := _fx
	var h := _hand_strip()
	var s := _tool_side()
	if _doing == "working":
		match _work:
			"read", "web":
				var lens := h + Vector2(s * 5.0, -5.0)
				fx._line(ci, h + Vector2(-s * 1.5, 2.0), lens - Vector2(s * 3.0, -3.0), Color(0.55, 0.4, 0.3), 2.2)
				fx._disc(ci, lens, 5.0, Color(0.75, 0.92, 1.0, 0.25))
				fx._ring(ci, lens, 5.0, Color(0.85, 0.88, 0.95), 1.6)
				fx._disc(ci, lens + Vector2(-1.6, -1.8), 1.2, Color(1, 1, 1, 0.7))
			"run":
				var c := h + Vector2(s * 9.0, -4.0)
				fx._panel(ci, Rect2(c.x - 9.0, c.y - 6.0, 18.0, 12.0), 3)
				fx._text(ci, Vector2(c.x - 6.5, c.y + 2.5), ">_" if fmod(_t, 0.8) < 0.45 else ">", 7, Color(0.55, 0.92, 0.65), false, 700)
			"make":
				var swing := sin(_t * 9.0) * 0.6 - 0.3
				ci.draw_set_transform(h, s * swing, Vector2(s, 1.0))
				fx._line(ci, Vector2.ZERO, Vector2(10, -2), Color(0.62, 0.45, 0.3), 2.0)
				fx._panel(ci, Rect2(8, -6, 5, 8), 1, Color(0.7, 0.74, 0.8))
				ci.draw_set_transform(Vector2.ZERO)


func _draw_sign(ci: CanvasItem) -> void:
	if _sign == "":
		return
	var fx := _fx
	var age := _t - _sign_at
	var pop := clampf(age * 6.0, 0.0, 1.0)
	var out := clampf((_sign_until - _t) * 4.0, 0.0, 1.0)
	var a := pop * out
	var sc := 0.6 + 0.4 * (1.0 - pow(1.0 - pop, 3.0))
	var head := _to_strip(Vector2(R * 0.55, R * 0.95))
	var p := head + Vector2(8.0, -10.0 + sin(_t * 3.0) * 1.5)
	match _sign:
		"?", "!":
			ci.draw_set_transform(p, sin(_t * 2.5) * 0.12, Vector2(sc, sc))
			var f := Kit.font(700)
			ci.draw_string_outline(f, Vector2(-4, 6), _sign, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, 4, Color(ClaudeScene.INK, 0.55 * a))
			ci.draw_string(f, Vector2(-4, 6), _sign, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 1, 1, a))
		"...":
			var b := _to_strip(Vector2(R * 0.6, R * 1.0))
			fx._disc(ci, b + Vector2(4, -3), 1.6, Color(1, 1, 1, 0.6 * a))
			fx._disc(ci, b + Vector2(8, -8), 2.4, Color(1, 1, 1, 0.7 * a))
			var c := b + Vector2(18, -16)
			ci.draw_set_transform(c, 0.0, Vector2(sc, sc))
			fx._panel(ci, Rect2(-11, -6.5, 22, 13), 7, Color(1, 1, 1, 0.9 * a))
			for i in 3:
				var up := maxf(0.0, sin(_t * 6.0 - i * 0.9)) * 1.6
				fx._disc(ci, Vector2(-5.5 + i * 5.5, -up), 1.5, Color(ClaudeScene.INK, 0.75 * a))
		"bulb":
			ci.draw_set_transform(_to_strip(Vector2(0.0, R)) + Vector2(0, -14), 0.0, Vector2(sc, sc))
			for i in 5:
				var ang := -PI * 0.5 + (i - 2) * 0.55
				var d := Vector2(cos(ang), sin(ang))
				fx._line(ci, d * 8.5, d * (11.5 + sin(_t * 8.0) * 0.8), Color(1.0, 0.88, 0.45, a), 1.4)
			fx._disc(ci, Vector2.ZERO, 6.0, Color(1.0, 0.9, 0.5, a))
			fx._disc(ci, Vector2(-1.8, -2.0), 1.8, Color(1, 1, 1, 0.8 * a))
			ci.draw_rect(Rect2(-3, 5, 6, 4), Color(0.7, 0.74, 0.8, a))
		"sweat":
			var d := _to_strip(Vector2(R * 0.78, R * 0.55)) + Vector2(0, age * 3.0)
			ci.draw_set_transform(d, 0.0, Vector2(sc, sc))
			ci.draw_colored_polygon(PackedVector2Array([Vector2(0, -5), Vector2(2.8, 0), Vector2(2.4, 1.8), Vector2(0, 3), Vector2(-2.4, 1.8), Vector2(-2.8, 0)]), Color(0.7, 0.9, 1.0, 0.9 * a))
			fx._disc(ci, Vector2(-0.8, 0.6), 0.8, Color(1, 1, 1, 0.8 * a))
		"tear":
			var me := _me()
			var eye: Vector2 = (me["eyes"] as Array)[0]
			var d := eye + Vector2(-1.5, 5.0 + fmod(age * 7.0, 9.0))
			ci.draw_set_transform(d, 0.0, Vector2(0.8, 0.8))
			ci.draw_colored_polygon(PackedVector2Array([Vector2(0, -4), Vector2(2.2, 0), Vector2(1.8, 1.6), Vector2(0, 2.4), Vector2(-1.8, 1.6), Vector2(-2.2, 0)]), Color(0.7, 0.9, 1.0, 0.85 * a))
	ci.draw_set_transform(Vector2.ZERO)


func _apply() -> void:
	if _body == null:
		return
	_body.position = Vector2(roundf(_x - BOX.x * 0.5), size.y - FLOOR + GROUND - BOX.y)
	_hit.position = Vector2(_x - HIT.x * 0.5, size.y - FLOOR - HIT.y + 4.0 - _y)
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
	var talking := _talk
	if _scene and _scene.on and _scene.talking():
		talking = maxf(talking, 0.7)
	var talk_open := talking * (0.3 + 0.32 * absf(sin(_t * 12.0 + sin(_t * 4.3) * 2.0)))
	if _face_name() == "chomp":
		talk_open += absf(sin(_t * 14.0)) * 0.35
	m.set_shader_parameter("smile", _face[1])
	m.set_shader_parameter("lid", _face[2])
	m.set_shader_parameter("worry", _face[3])
	m.set_shader_parameter("eye_size", _face[4])
	m.set_shader_parameter("mouth_open", clampf(float(_face[5]) + talk_open, 0.0, 1.0))
	m.set_shader_parameter("blush", _face[6])
	m.set_shader_parameter("mouth_w", float(_face[7]) * (1.0 - talking * 0.15))
	m.set_shader_parameter("hearts", _face[8])
	m.set_shader_parameter("stars", _face[9])
	m.set_shader_parameter("squint", _face[10])
	m.set_shader_parameter("swirl", _face[11])
	m.set_shader_parameter("error", _error)
	m.set_shader_parameter("arm", _arm)
	m.set_shader_parameter("hand", _hand)
	m.set_shader_parameter("spin", _spin)
