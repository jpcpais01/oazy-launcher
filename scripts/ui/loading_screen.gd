class_name LoadingScreen
extends Control
## Boot sequence. Animates on the GPU only (shaders + tweens) while work happens
## in small steps and on worker threads, so it never stutters. The UI behind it
## is already built and drawn, which also warms every shader before reveal.

signal finished
## Emitted right as the fade starts so Home can choreograph its entrance under it.
signal finished_early

const MIN_TIME := 0.85

var _orb: UpdateOrb
var _logo: TextureRect
var _word: Label
var _word_font: FontVariation
var _tag: Label
var _status: Label
var _mark: Control
var _skip := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var bg := Wallpaper.new()
	add_child(bg)
	bg.mat.set_shader_parameter("focus_center", 1.0)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var col := Kit.vbox(0)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(col)

	# The same glass orb the updater uses: it fills with water as Oazy loads,
	# with the logo floating in it and ripples running out over the wallpaper.
	_mark = Control.new()
	_mark.custom_minimum_size = Vector2(420, 420)
	_mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mark.pivot_offset = Vector2(210, 210)
	# The ripples may run under the wordmark, so the holder is shorter than the orb.
	var mark_holder := Control.new()
	mark_holder.custom_minimum_size = Vector2(420, 330)
	mark_holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	mark_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mark_holder.add_child(_mark)
	col.add_child(mark_holder)
	_orb = UpdateOrb.new(420, 0.5)
	_orb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_mark.add_child(_orb)
	_logo = TextureRect.new()
	_logo.texture = load("res://assets/icon.png")
	_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_logo.position = Vector2(160, 160)
	_logo.size = Vector2(100, 100)
	_logo.pivot_offset = Vector2(50, 50)
	_logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mark.add_child(_logo)

	_word = Kit.label("OAZY", 46, 800, Color.WHITE, true)
	_word_font = FontVariation.new()
	_word_font.base_font = Kit.font(800, true)
	_word_font.spacing_glyph = 14
	_word.add_theme_font_override("font", _word_font)
	_word.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_word)
	col.add_child(Kit.spacer(0, 6))
	_tag = Kit.label("Welcome home", 17, 500, Color(1, 1, 1, 0.66))
	_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_tag)

	_status = Kit.label("Starting up", 14, 500, Color(1, 1, 1, 0.5))
	_status.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_status.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_status.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_status.offset_bottom = -64
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_status)

	var version := Kit.label("v" + App.version, 12, 500, Color(1, 1, 1, 0.3))
	version.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	version.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	version.grow_vertical = Control.GROW_DIRECTION_BEGIN
	version.offset_right = -24
	version.offset_bottom = -20
	add_child(version)

	_intro()


## A drop lands: the orb springs up with a shockwave, the logo bobs to the
## surface and the wordmark draws its letters together.
func _intro() -> void:
	_mark.scale = Vector2.ONE * 0.6
	_mark.modulate.a = 0.0
	_logo.scale = Vector2.ONE * 0.4
	_logo.modulate.a = 0.0
	_word.modulate.a = 0.0
	_tag.modulate.a = 0.0
	_status.modulate.a = 0.0
	_word_font.spacing_glyph = 42
	_orb.snap(0.06)
	_orb.shockwave(1.1)
	var t := create_tween().set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(_mark, "scale", Vector2.ONE, 0.6)
	t.tween_property(_mark, "modulate:a", 1.0, 0.25).set_trans(Tween.TRANS_SINE)
	t.tween_property(_logo, "scale", Vector2.ONE, 0.65).set_delay(0.08)
	t.tween_property(_logo, "modulate:a", 1.0, 0.3).set_delay(0.08)
	t.tween_property(_word, "modulate:a", 1.0, 0.45).set_delay(0.15).set_trans(Tween.TRANS_SINE)
	t.tween_property(_word_font, "spacing_glyph", 14, 0.7).set_delay(0.1).set_trans(Tween.TRANS_EXPO)
	t.tween_property(_tag, "modulate:a", 1.0, 0.45).set_delay(0.3).set_trans(Tween.TRANS_SINE)
	t.tween_property(_status, "modulate:a", 1.0, 0.45).set_delay(0.4).set_trans(Tween.TRANS_SINE)
	var bob := _logo.create_tween().set_loops().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	bob.tween_property(_logo, "position:y", 152.0, 1.4)
	bob.tween_property(_logo, "position:y", 160.0, 1.4)


func _step(text: String, progress: float) -> void:
	_status.text = text
	_orb.target = maxf(_orb.target, progress)


## Runs the boot steps. Every await yields a frame so animation stays fluid.
func run() -> void:
	var start := Time.get_ticks_msec()
	var fast := App.smoke_test
	_step("Preparing your library", 0.15)
	await get_tree().process_frame

	# First run: look for installed games straight away.
	if Library.entries.is_empty() and not Settings.get_value("first_scan_done") and not fast:
		_step("Looking for your games", 0.3)
		Settings.set_value("first_scan_done", true)
		Library.import_stores()
		var waited := 0.0
		while Library.importing and waited < 4.0 and not _skip:
			await get_tree().process_frame
			waited += get_process_delta_time()

	_step("Loading artwork", 0.55)
	var warm := Library.recent().slice(0, 8)
	for e in warm:
		Art.get_art(str(e["id"]), &"cover")
	if not warm.is_empty():
		Art.get_art(str(warm[0]["id"]), &"hero")
		Art.get_art(str(warm[0]["id"]), &"logo")
	var waited_art := 0.0
	while waited_art < 0.9 and not fast and not _skip:
		var all_done := true
		for e in warm:
			if not Art.is_resolved(str(e["id"]), &"cover"):
				all_done = false
				break
		if all_done:
			break
		await get_tree().process_frame
		waited_art += get_process_delta_time()

	_step("Almost there", 0.85)
	if Settings.get_value("auto_check_updates") and App.is_packaged() and not fast:
		Updater.check()
	await get_tree().process_frame

	var min_ms := 0 if fast else int(MIN_TIME * 1000.0)
	while Time.get_ticks_msec() - start < min_ms and not _skip:
		await get_tree().process_frame
	_step("Ready", 1.0)
	if not fast:
		await get_tree().create_timer(0.18).timeout
	_outro()


## The orb fills to the brim, sends one last ripple out, and everything lifts
## away so the desktop can come in underneath.
func _outro() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_orb.shockwave(0.7)
	var t := create_tween().set_parallel(true).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(_mark, "scale", Vector2.ONE * 1.25, 0.5)
	t.tween_property(_word, "modulate:a", 0.0, 0.25)
	t.tween_property(_tag, "modulate:a", 0.0, 0.2)
	t.tween_property(_status, "modulate:a", 0.0, 0.2)
	t.tween_property(_word_font, "spacing_glyph", 26, 0.4)
	t.tween_property(self, "modulate:a", 0.0, 0.42).set_delay(0.06)
	t.chain().tween_callback(func() -> void:
		finished.emit()
		queue_free()
	)
	await get_tree().create_timer(0.08).timeout
	finished_early.emit()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_skip = true


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		_skip = true
