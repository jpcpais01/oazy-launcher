extends Node
## The music wallpaper's ears and its sense of a song's "vibe".
##
## While it's on, the companion listens to what's playing (Chrome alone by
## default, so a minimised YouTube Music drives it and nothing else does; or
## everything the speakers play) and sends a frame of analysis about sixty
## times a second: a 16-band spectrum, loudness, onsets and kicks, tempo and
## beat phase, brightness, noisiness and a running key estimate.
##
## Here those are eased into what the picture shows (the music_* shader
## globals read by wall.gdshaderinc), and folded into a vibe: where the song
## sits between calm and intense (arousal) and between dark and bright
## (valence). That picks the colours: serene songs lean turquoise, joyful
## ones amber and coral, tense ones violet and magenta, sad ones deep blue,
## and the key nudges the hue around the circle of fifths.
##
## Party mode (the taskbar's star) turns the picture into a celebration:
## the same bars on a lake at dusk, with fireworks opening on the beat. The
## bursts are timed here and handed to the shader as music_burst*.

signal toggled(on: bool)
## "chrome", "all", or "" while nothing is being heard.
signal source_changed(src: String)
## The song Windows' media controls report changed (see media).
signal media_changed
signal party_changed(on: bool)

const BANDS := 16
## Bands climb fast and fall slower, so hits read and nothing flickers.
const RISE := 30.0
const FALL := 9.0
const SLOW := 2.2
## How long the picture keeps easing after the wallpaper is turned off.
const LINGER := 1.6
## Russell's circumplex corners -> hue: [valence, arousal, hue].
const MOODS := [[1.0, 1.0, 0.065], [1.0, 0.0, 0.48], [-1.0, 1.0, 0.84], [-1.0, 0.0, 0.62]]
## Fireworks: at most one per this many seconds on the beat (calm to
## intense songs), and one anyway after a lull (playing, or silent).
const BURST_GAP := [0.95, 0.5]
const BURST_LULL := [1.4, 2.8]

var on := false
## Party mode: only while the music wallpaper is on.
var party := false
var source := ""
## Eased spectrum (0..1, low to high), quick and slow.
var bands := PackedFloat32Array()
var slow := PackedFloat32Array()
var level := 0.0
var bass := 0.0
var mid := 0.0
var high := 0.0
## 1 on a kick, fading; the same for any onset.
var pulse := 0.0
var flash := 0.0
## 0 in silence, 1 while something is playing.
var presence := 0.0
var bpm := 0.0
var beat_phase := 0.0
## The vibe: valence -1 (dark) .. 1 (bright), arousal 0 (calm) .. 1 (intense).
var valence := -0.1
var arousal := 0.3
var key := 0
var major := 0.0

## What's playing, from Windows' media controls: {has, app, title, artist,
## album, playing, can_seek, can_next, can_prev, dur, pos}.
var media := {}

var _media_at := 0
var _target := PackedFloat32Array()
var _frame := {}
var _frame_age := 10.0
var _rings := [9.0, 9.0, 9.0, 9.0]
var _ring_power := [0.0, 0.0, 0.0, 0.0]
var _next_ring := 0
var _phase := Vector4.ZERO
var _palette: Array = []
var _linger := 0.0
var _mocked := false
var _demo_t := 0.0
var _paused := false
var _burst := [9.0, 9.0, 9.0, 9.0]
var _burst_seed := [0.0, 0.0, 0.0, 0.0]
var _burst_power := [0.0, 0.0, 0.0, 0.0]
var _since_burst := 9.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	bands.resize(BANDS)
	slow.resize(BANDS)
	_target.resize(BANDS)
	_palette = _vibe_palette()
	on = bool(Settings.get_value("music_wallpaper"))
	Host.audio_frame.connect(_on_frame)
	Host.audio_source.connect(func(src: String) -> void:
		source = src
		source_changed.emit(src)
	)
	Host.status_changed.connect(func(ok: bool) -> void:
		if ok and on:
			_listen()
	)
	Host.media_changed.connect(_on_media)
	Host.fullscreen_changed.connect(func(fs: bool) -> void:
		# Nobody sees the desktop under a fullscreen game: stop listening.
		_paused = fs
		if on:
			if fs:
				Host.stop_listening()
			else:
				_listen()
	)
	Settings.changed.connect(func(k: String, v: Variant) -> void:
		if k == "music_wallpaper" and bool(v) != on:
			set_on(bool(v))
		elif k == "music_source" and on:
			_listen()
	)
	set_process(on)
	if on:
		_listen.call_deferred()
	_publish()


## Turns the music wallpaper on or off (the taskbar's toggle).
func set_on(v: bool) -> void:
	if v == on:
		return
	on = v
	if Settings.get_value("music_wallpaper") != v:
		Settings.set_value("music_wallpaper", v)
	if v:
		_linger = 0.0
		set_process(true)
		_listen()
	else:
		_linger = LINGER
		Host.stop_listening()
		source = ""
		source_changed.emit("")
		set_party(false)
	toggled.emit(v)


func toggle() -> void:
	set_on(not on)


## Party mode on or off (the taskbar's star); it opens with a firework.
func set_party(v: bool) -> void:
	v = v and on
	if v == party:
		return
	party = v
	if v:
		_launch(0.8)
		_since_burst = -0.6
	party_changed.emit(v)


## Fixed fireworks for screenshots: [age, seed, power] each.
func set_mock_bursts(bursts: Array) -> void:
	for i in 4:
		var b: Array = bursts[i] if i < bursts.size() else [9.0, 0.0, 0.0]
		_burst[i] = float(b[0])
		_burst_seed[i] = float(b[1])
		_burst_power[i] = float(b[2])
	_publish()


## A firework from whichever slot is oldest.
func _launch(power: float) -> void:
	var slot := 0
	for i in 4:
		if _burst[i] > _burst[slot]:
			slot = i
	_burst[slot] = 0.0
	_burst_seed[slot] = randf()
	_burst_power[slot] = clampf(power, 0.3, 1.0)
	_since_burst = 0.0


func _listen() -> void:
	var src := str(Settings.get_value("music_source"))
	Host.media_command("prefer", src)
	if _paused:
		return
	Host.listen(src)


func _on_media(d: Dictionary) -> void:
	if _mocked:
		return
	media = d
	_media_at = Time.get_ticks_msec()
	media_changed.emit()


## Where the song is now, in seconds, carried forward while it plays.
func media_position() -> float:
	var pos := float(media.get("pos", 0.0))
	if media.get("playing", false):
		pos += float(Time.get_ticks_msec() - _media_at) / 1000.0
	var dur := float(media.get("dur", 0.0))
	return clampf(pos, 0.0, dur) if dur > 0.0 else maxf(pos, 0.0)


## Play/pause, next, previous, or a jump to `seconds`; the shown state moves
## at once and Windows' answer follows.
func media_do(cmd: String, seconds: float = 0.0) -> void:
	if cmd == "seek":
		media["pos"] = seconds
		_media_at = Time.get_ticks_msec()
		Host.media_command("seek", str(seconds))
	else:
		if cmd == "toggle":
			media["pos"] = media_position()
			_media_at = Time.get_ticks_msec()
			media["playing"] = not media.get("playing", false)
		Host.media_command(cmd)
	media_changed.emit()


## A fixed song for screenshots and tests.
func set_mock_media(d: Dictionary) -> void:
	media = d
	_media_at = Time.get_ticks_msec()
	media_changed.emit()


## Feeds a fixed frame (screenshots, tests) and settles everything on it;
## an empty one goes back to listening.
func set_mock(frame: Dictionary, vibe_valence: float = 0.2, vibe_arousal: float = 0.25) -> void:
	_mocked = not frame.is_empty()
	if not _mocked:
		return
	_on_frame(frame)
	major = float(frame.get("m", 0.0)) * clampf(float(frame.get("kc", 0.0)) * 1.6, 0.0, 1.0)
	valence = vibe_valence
	arousal = vibe_arousal
	presence = 1.0
	for i in BANDS:
		bands[i] = _target[i]
		slow[i] = _target[i] * 0.85
	_palette = _vibe_palette()
	_rings = [0.35, 0.9, 1.4, 9.0]
	_ring_power = [1.0, 0.8, 0.6, 0.0]
	pulse = 0.6
	_derive()
	_publish()


func _on_frame(d: Dictionary) -> void:
	_frame = d
	_frame_age = 0.0
	var b: Array = d.get("b", [])
	for i in mini(b.size(), BANDS):
		_target[i] = float(b[i]) / 999.0
	var k := float(d.get("k", 0.0))
	if k > 0.2:
		pulse = maxf(pulse, k)
		_rings[_next_ring] = 0.0
		_ring_power[_next_ring] = clampf(k, 0.4, 1.0)
		_next_ring = (_next_ring + 1) % 4
		if party and _since_burst > lerpf(BURST_GAP[0], BURST_GAP[1], arousal):
			_launch(k)
	flash = maxf(flash, float(d.get("o", 0.0)) * 0.7)
	var new_bpm := float(d.get("bpm", 0.0))
	if new_bpm > 0.0:
		bpm = new_bpm
	key = int(d.get("key", key))


func _process(delta: float) -> void:
	if _mocked:
		return
	delta = minf(delta, 0.1)
	if on and not _mocked and not Host.available and not App.smoke_test:
		_demo(delta)
	_frame_age += delta
	if _frame_age > 0.3:
		# Nothing heard lately: let it all settle.
		for i in BANDS:
			_target[i] = 0.0
	var rise := 1.0 - exp(-delta * RISE)
	var fall := 1.0 - exp(-delta * FALL)
	var settle := 1.0 - exp(-delta * SLOW)
	for i in BANDS:
		var t := _target[i]
		bands[i] += (t - bands[i]) * (rise if t > bands[i] else fall)
		slow[i] += (t - slow[i]) * settle
	_derive()
	pulse *= exp(-delta * 5.0)
	flash *= exp(-delta * 8.0)
	for i in 4:
		_rings[i] = minf(_rings[i] + delta, 9.0)
		_burst[i] = minf(_burst[i] + delta, 9.0)
	_since_burst += delta
	if party and _since_burst > (BURST_LULL[0] if presence > 0.3 else BURST_LULL[1]):
		_launch(0.45 + 0.3 * level)
	var heard := 0.0
	if not _frame.is_empty() and _frame_age < 0.5:
		heard = smoothstep(-66.0, -46.0, float(_frame.get("db", -100.0)))
	presence += (heard - presence) * (1.0 - exp(-delta * 1.5))
	# The beat clock runs here every frame, leaning toward the companion's.
	if bpm > 0.0:
		beat_phase = fposmod(beat_phase + delta * bpm / 60.0, 1.0)
		if _frame.has("ph"):
			var err := wrapf(float(_frame["ph"]) - beat_phase, -0.5, 0.5)
			beat_phase = fposmod(beat_phase + err * minf(1.0, delta * 4.0), 1.0)
	# Flow quickens with the music; phases wrap at TAU and the shader only
	# multiplies them by whole numbers, so nothing jumps.
	var pace := (0.6 + 1.6 * level * presence) * TAU
	_phase.x = fposmod(_phase.x + delta * pace / 23.0, TAU)
	_phase.y = fposmod(_phase.y + delta * pace / 31.0, TAU)
	_phase.z = fposmod(_phase.z + delta * pace / 17.0, TAU)
	_phase.w = fposmod(_phase.w + delta * pace / 7.0, TAU)
	_update_vibe(delta)
	_publish()
	if not on:
		_linger -= delta
		if _linger <= 0.0:
			set_process(false)


func _derive() -> void:
	var lo := 0.0
	var mi := 0.0
	var hi := 0.0
	for i in BANDS:
		if i < 4:
			lo += bands[i]
		elif i < 11:
			mi += bands[i]
		else:
			hi += bands[i]
	bass = lo / 4.0
	mid = mi / 7.0
	high = hi / 5.0
	level = clampf(bass * 0.45 + mid * 0.4 + high * 0.25, 0.0, 1.0)


## The vibe, from the slow features: valence leans on mode (major/minor,
## weighted by how clear the key is), tempo, brightness and roughness;
## arousal on loudness, how busy the onsets are, tempo and the highs.
func _update_vibe(delta: float) -> void:
	var f := _frame
	if f.is_empty() or presence < 0.05:
		# Silence drifts back to a calm blue.
		valence += (-0.1 - valence) * (1.0 - exp(-delta / 6.0))
		arousal += (0.3 - arousal) * (1.0 - exp(-delta / 6.0))
	else:
		var conf := clampf(float(f.get("bc", 0.0)) * 1.5, 0.0, 1.0)
		var tempo := clampf((bpm - 70.0) / 90.0, 0.0, 1.0) * conf + 0.4 * (1.0 - conf)
		var loud := clampf((float(f.get("db", -60.0)) + 42.0) / 30.0, 0.0, 1.0)
		var busy := clampf(float(f.get("r", 0.0)) / 6.0, 0.0, 1.0)
		var bright := float(f.get("c", 0.5))
		var rough := clampf(float(f.get("f", 0.2)), 0.0, 1.0)
		major = float(f.get("m", 0.0)) * clampf(float(f.get("kc", 0.0)) * 1.6, 0.0, 1.0)
		var v := 0.5 * major + 0.2 * (tempo * 2.0 - 1.0) + 0.3 * clampf((bright - 0.4) * 2.5, -1.0, 1.0) - 0.25 * rough + 0.1
		var a := 0.35 * loud + 0.25 * busy + 0.2 * tempo + 0.2 * clampf(high * 1.6, 0.0, 1.0)
		var k := 1.0 - exp(-delta / 3.0)
		valence += (clampf(v, -1.0, 1.0) - valence) * k
		arousal += (clampf(a, 0.0, 1.0) - arousal) * k
	var want := _vibe_palette()
	var drift := 1.0 - exp(-delta / 2.0)
	for i in _palette.size():
		_palette[i] = (_palette[i] as Color).lerp(want[i], drift)


## base (the sky), a, b, c (the lights behind the glass) and glow for the
## current vibe.
func _vibe_palette() -> Array:
	var wv := (valence + 1.0) * 0.5
	var corner := [wv * arousal, wv * (1.0 - arousal), (1.0 - wv) * arousal, (1.0 - wv) * (1.0 - arousal)]
	# Sharpened, so a song reads as one mood and blends only near the middle.
	var hv := Vector2.ZERO
	for i in MOODS.size():
		hv += Vector2.from_angle(TAU * float(MOODS[i][2])) * pow(float(corner[i]), 2.5)
	var h := hv.angle() / TAU
	# The key turns the hue a little around the circle of fifths.
	var fifths := float((key * 7) % 12) / 12.0
	h += 0.04 * absf(major) * sin(TAU * fifths)
	# A celestial sky, its hue pulled toward the violet of night, and three
	# lights behind the glass: the mood's own, a neighbour, and a soft
	# counter-light from across the wheel.
	var sky_h := lerp_angle(TAU * h, TAU * 0.7, 0.55) / TAU
	var bright := float(_frame.get("c", 0.5)) if not _frame.is_empty() else 0.5
	var glow := Color.from_hsv(fposmod(h + 0.03, 1.0), 0.1, 1.0)
	glow = glow.lerp(Color(1.0, 0.9, 0.8), 0.25 * (1.0 - bright)).lerp(Color(0.88, 0.94, 1.0), 0.25 * bright)
	var vibe := [
		Color.from_hsv(fposmod(sky_h, 1.0), 0.55, 0.26 + 0.05 * arousal),
		Color.from_hsv(_tidy(h), 0.42 + 0.25 * arousal, 1.0),
		Color.from_hsv(_tidy(h - 0.17), 0.48 + 0.2 * arousal, 0.95),
		Color.from_hsv(_tidy(h + 0.33), 0.45, 0.97).lerp(App.accent.lightened(0.4), 0.08),
		glow,
	]
	return vibe


## Keeps a light's hue out of the yellow-greens, which turn sickly behind
## glass: they slide to gold or cyan, whichever is nearer.
static func _tidy(h: float) -> float:
	h = fposmod(h, 1.0)
	if h > 0.15 and h < 0.46:
		return 0.13 if h < 0.3 else 0.48
	return h


func _publish() -> void:
	var rs := RenderingServer
	for i in 4:
		var j := i * 4
		rs.global_shader_parameter_set("music_bands%d" % i, Vector4(bands[j], bands[j + 1], bands[j + 2], bands[j + 3]) * presence)
		rs.global_shader_parameter_set("music_slow%d" % i, Vector4(slow[j], slow[j + 1], slow[j + 2], slow[j + 3]) * presence)
	rs.global_shader_parameter_set("music_level", Vector4(level, bass, mid, high) * presence)
	rs.global_shader_parameter_set("music_beat", Vector4(pulse * presence, flash * presence, presence, beat_phase))
	rs.global_shader_parameter_set("music_rings", Vector4(_rings[0], _rings[1], _rings[2], _rings[3]))
	rs.global_shader_parameter_set("music_ring_power", Vector4(_ring_power[0], _ring_power[1], _ring_power[2], _ring_power[3]) * presence)
	rs.global_shader_parameter_set("music_phase", _phase)
	rs.global_shader_parameter_set("music_burst", Vector4(_burst[0], _burst[1], _burst[2], _burst[3]))
	rs.global_shader_parameter_set("music_burst_seed", Vector4(_burst_seed[0], _burst_seed[1], _burst_seed[2], _burst_seed[3]))
	rs.global_shader_parameter_set("music_burst_power", Vector4(_burst_power[0], _burst_power[1], _burst_power[2], _burst_power[3]))
	var names := ["music_base", "music_a", "music_b", "music_c", "music_glow"]
	for i in names.size():
		var c: Color = _palette[i]
		rs.global_shader_parameter_set(names[i], Vector4(c.r, c.g, c.b, 1.0))


## Away from Windows (dev runs): a made-up song so the wallpaper still moves.
func _demo(delta: float) -> void:
	_demo_t += delta
	if _frame_age < 1.0 / 60.0:
		return
	var beat := _demo_t * 118.0 / 60.0
	var bt := fposmod(beat, 1.0)
	var b := []
	for i in BANDS:
		var x := float(i) / float(BANDS - 1)
		var v := 0.55 * exp(-x * 3.0) * exp(-bt * 5.0) + 0.35 * (0.6 + 0.4 * sin(_demo_t * 1.7 + x * 9.0)) * (1.0 - x * 0.6)
		b.append(int(clampf(v, 0.0, 1.0) * 999.0))
	var kick := 0.9 if bt < delta * 118.0 / 60.0 else 0.0
	_on_frame({"b": b, "db": -20.0, "o": kick, "k": kick, "bpm": 118.0, "bc": 0.8, "ph": bt, "c": 0.5, "f": 0.15, "r": 3.0, "m": 0.5, "key": 7, "kc": 0.7})
