class_name LoadingScreen
extends Control
## Boot sequence. Animates on the GPU only (shaders + tweens) while work happens
## in small steps and on worker threads, so it never stutters. The UI behind it
## is already built and drawn, which also warms every shader before reveal.

signal finished
## Emitted right as the fade starts so Home can choreograph its entrance under it.
signal finished_early

const AURORA := preload("res://shaders/aurora.gdshader")
const RING := preload("res://shaders/ring.gdshader")
const BAR := preload("res://shaders/shine_bar.gdshader")
const MIN_TIME := 1.35

var _bg_mat: ShaderMaterial
var _ring: ColorRect
var _logo: TextureRect
var _word: Label
var _tag: Label
var _status: Label
var _bar_mat: ShaderMaterial
var _progress := 0.0
var _shown := 0.0
var _skip := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var bg := ColorRect.new()
	_bg_mat = ShaderMaterial.new()
	_bg_mat.shader = AURORA
	_bg_mat.set_shader_parameter("focus_center", 1.0)
	_bg_mat.set_shader_parameter("intensity", 1.15)
	_bg_mat.set_shader_parameter("accent", App.DEFAULT_ACCENT)
	_bg_mat.set_shader_parameter("accent2", App.accent_pair(App.DEFAULT_ACCENT))
	bg.material = _bg_mat
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	resized.connect(func() -> void:
		if size.y > 0.0:
			_bg_mat.set_shader_parameter("aspect", size.x / size.y)
	)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var col := Kit.vbox(0)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(col)

	var mark := Control.new()
	mark.custom_minimum_size = Vector2(190, 190)
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mark_holder := CenterContainer.new()
	mark_holder.add_child(mark)
	col.add_child(mark_holder)
	_ring = ColorRect.new()
	var rm := ShaderMaterial.new()
	rm.shader = RING
	rm.set_shader_parameter("indeterminate", 1.0)
	rm.set_shader_parameter("thickness", 0.035)
	rm.set_shader_parameter("color_a", App.DEFAULT_ACCENT)
	rm.set_shader_parameter("color_b", App.accent_pair(App.DEFAULT_ACCENT))
	rm.set_shader_parameter("track", Color(1, 1, 1, 0.05))
	_ring.material = rm
	_ring.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mark.add_child(_ring)
	_logo = TextureRect.new()
	_logo.texture = load("res://assets/icon.png")
	_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_logo.position = Vector2(43, 43)
	_logo.size = Vector2(104, 104)
	_logo.pivot_offset = Vector2(52, 52)
	_logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mark.add_child(_logo)

	col.add_child(Kit.spacer(0, 26))
	_word = Kit.label("OAZY", 46, 800, Color.WHITE, true)
	var wv := FontVariation.new()
	wv.base_font = Kit.font(800, true)
	wv.spacing_glyph = 14
	_word.add_theme_font_override("font", wv)
	_word.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_word)
	col.add_child(Kit.spacer(0, 6))
	_tag = Kit.label("Your games, one place", 17, 500, Color(1, 1, 1, 0.6))
	_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_tag)

	var bottom := Kit.vbox(12)
	bottom.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	bottom.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom.offset_bottom = -64
	add_child(bottom)
	_status = Kit.label("Starting up", 14, 500, Color(1, 1, 1, 0.55))
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bottom.add_child(_status)
	var bar_holder := CenterContainer.new()
	bottom.add_child(bar_holder)
	var bar := ColorRect.new()
	bar.custom_minimum_size = Vector2(280, 3)
	_bar_mat = ShaderMaterial.new()
	_bar_mat.shader = BAR
	_bar_mat.set_shader_parameter("rect_size", Vector2(280, 3))
	_bar_mat.set_shader_parameter("color_a", App.DEFAULT_ACCENT)
	_bar_mat.set_shader_parameter("color_b", App.accent_pair(App.DEFAULT_ACCENT))
	bar.material = _bar_mat
	bar_holder.add_child(bar)

	var version := Kit.label("v" + App.version, 12, 500, Color(1, 1, 1, 0.3))
	version.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	version.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	version.grow_vertical = Control.GROW_DIRECTION_BEGIN
	version.offset_right = -24
	version.offset_bottom = -20
	add_child(version)

	_intro()


func _intro() -> void:
	_logo.scale = Vector2.ONE * 0.55
	_logo.modulate.a = 0.0
	_ring.modulate.a = 0.0
	_word.modulate.a = 0.0
	_tag.modulate.a = 0.0
	var t := create_tween().set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(_logo, "scale", Vector2.ONE, 0.8)
	t.tween_property(_logo, "modulate:a", 1.0, 0.4)
	t.tween_property(_ring, "modulate:a", 1.0, 0.6).set_delay(0.25)
	t.tween_property(_word, "modulate:a", 1.0, 0.6).set_delay(0.3).set_trans(Tween.TRANS_SINE)
	t.tween_property(_tag, "modulate:a", 1.0, 0.6).set_delay(0.45).set_trans(Tween.TRANS_SINE)


func _process(delta: float) -> void:
	_shown = lerpf(_shown, _progress, 1.0 - exp(-delta * 6.0))
	_bar_mat.set_shader_parameter("progress", _shown)


func _step(text: String, progress: float) -> void:
	_status.text = text
	_progress = progress


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
	var warm := Library.recent().slice(0, 14)
	for e in warm:
		Art.get_art(str(e["id"]), &"cover")
	var sel := str(Settings.get_value("last_selected"))
	if sel == "" and not warm.is_empty():
		sel = str(warm[0]["id"])
	if sel != "":
		Art.get_art(sel, &"hero")
		Art.get_art(sel, &"logo")
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
		await get_tree().create_timer(0.25).timeout
	_outro()


func _outro() -> void:
	set_process(false)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t := create_tween().set_parallel(true).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(_logo, "scale", Vector2.ONE * 1.18, 0.6)
	t.tween_property(self, "modulate:a", 0.0, 0.55).set_delay(0.08)
	t.chain().tween_callback(func() -> void:
		finished.emit()
		queue_free()
	)
	await get_tree().create_timer(0.12).timeout
	finished_early.emit()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_skip = true


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		_skip = true
