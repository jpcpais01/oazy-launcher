extends Node
## Interface sounds, synthesised at startup so the exe needs no audio assets.
## Soft, short and quiet: they should feel like texture, not noise.

const RATE := 44100

var _streams := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _last_play := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 6:
		var p := AudioStreamPlayer.new()
		p.bus = &"Master"
		add_child(p)
		_players.append(p)
	# Synthesis takes a moment in GDScript, so keep it off the main thread
	# to leave the loading screen perfectly smooth.
	WorkerThreadPool.add_task(_generate_all, true, "Synthesise UI sounds")


func _generate_all() -> void:
	var built := {
		&"move": _make(_tone_move, 0.07),
		&"select": _make(_tone_select, 0.22),
		&"back": _make(_tone_back, 0.14),
		&"toggle": _make(_tone_toggle, 0.08),
		&"notify": _make(_tone_notify, 0.7),
		&"error": _make(_tone_error, 0.3),
		&"open": _make(_tone_open, 0.3),
		&"launch": _make(_tone_launch, 1.6),
	}
	_install.call_deferred(built)


func _install(built: Dictionary) -> void:
	_streams = built


func play(name: StringName, pitch: float = 1.0) -> void:
	if not Settings.get_value("ui_sounds") or not _streams.has(name):
		return
	# Debounce identical sounds fired in the same few milliseconds.
	var now := Time.get_ticks_msec()
	if now - int(_last_play.get(name, -1000)) < 28:
		return
	_last_play[name] = now
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = _streams[name]
	p.pitch_scale = pitch
	var vol: float = clampf(float(Settings.get_value("volume")), 0.0, 1.0)
	p.volume_db = linear_to_db(maxf(vol, 0.0001)) - 6.0
	p.play()


func _make(gen: Callable, seconds: float) -> AudioStreamWAV:
	var count := int(seconds * RATE)
	var data := PackedByteArray()
	data.resize(count * 2)
	for i in count:
		var t := float(i) / RATE
		var v: float = gen.call(t)
		# Gentle fade in/out to avoid clicks.
		var edge := minf(1.0, minf(t / 0.002, (seconds - t) / 0.01))
		data.encode_s16(i * 2, int(clampf(v * edge, -1.0, 1.0) * 32000.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = data
	return s


static func _sine(f: float, t: float) -> float:
	return sin(TAU * f * t)


func _tone_move(t: float) -> float:
	var env := exp(-t * 70.0)
	return (_sine(2100.0, t) * 0.6 + _sine(3150.0, t) * 0.2) * env * 0.22


func _tone_toggle(t: float) -> float:
	var env := exp(-t * 55.0)
	return (_sine(1500.0, t) + _sine(2250.0, t) * 0.4) * env * 0.2


func _tone_select(t: float) -> float:
	var a := _sine(880.0, t) * exp(-t * 18.0)
	var b := _sine(1318.5, t) * exp(-maxf(t - 0.045, 0.0) * 16.0) * (1.0 if t > 0.045 else 0.0)
	return (a * 0.55 + b * 0.45) * 0.26


func _tone_back(t: float) -> float:
	var f := lerpf(900.0, 560.0, minf(t / 0.12, 1.0))
	return sin(TAU * f * t) * exp(-t * 26.0) * 0.22


func _tone_open(t: float) -> float:
	var f := lerpf(520.0, 1040.0, minf(t / 0.2, 1.0))
	return sin(TAU * f * t) * exp(-t * 12.0) * 0.16 * minf(t / 0.03, 1.0)


func _tone_notify(t: float) -> float:
	var a := (_sine(987.8, t) + _sine(1975.5, t) * 0.25) * exp(-t * 7.0)
	var t2 := t - 0.11
	var b := 0.0
	if t2 > 0.0:
		b = (_sine(1318.5, t2) + _sine(2637.0, t2) * 0.25) * exp(-t2 * 6.0)
	return (a * 0.5 + b * 0.5) * 0.2


func _tone_error(t: float) -> float:
	var v := _sine(220.0, t) * 0.6 + _sine(233.0, t) * 0.4
	return v * exp(-t * 11.0) * 0.28


func _tone_launch(t: float) -> float:
	# Rising arpeggio with a shimmering tail and a soft airy swell.
	var notes := [523.25, 659.25, 783.99, 1046.5, 1318.5]
	var v := 0.0
	for i in notes.size():
		var start := i * 0.075
		var tt := t - start
		if tt > 0.0:
			var f: float = notes[i]
			v += (sin(TAU * f * tt) + sin(TAU * f * 2.003 * tt) * 0.18) * exp(-tt * 3.2) * 0.2
	var swell := sin(t / 1.6 * PI)
	var air := sin(TAU * 130.81 * t) * 0.12 + sin(TAU * 196.0 * t) * 0.08
	v += air * swell * 0.5
	return v * 0.5
