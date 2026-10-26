class_name LaunchOverlay
extends Control
## The moment a game starts: its art blurred into a calm backdrop, the logo
## (or name) crisp in front, and a small water orb that slowly fills while the
## game loads. Oazy steps aside as soon as the game's window takes over, says
## so gently when a launcher is slow, and offers a way out when it fails.

const BACKDROP := preload("res://shaders/launch_backdrop.gdshader")
## Seconds before the status admits the game is taking a while.
const SLOW_AFTER := 9.0
## Seconds before Oazy stops waiting and gets out of the way.
const GIVE_UP_AFTER := 45.0
## Without the companion Oazy can't see the game's window, so the screen
## leaves after a short, fixed beat instead.
const BLIND_HOLD := 2.4
## Width the art is blurred down to (then smoothly scaled back up).
const BLUR_W := 112
const LOGO_BOX := Vector2(620, 230)

## Blurred backdrops by entry, so launching the same game again is instant.
static var _blurred := {}

signal finished

var entry_id := ""
## Opens the entry's details when a launch fails.
var on_edit := Callable()
var _entry := {}
var _backdrop: TextureRect
var _stage: Control
var _title_slot: Control
var _title_holder: Control
var _logo: TextureRect
var _name: Label
var _status_box: VBoxContainer
var _orb: UpdateOrb
var _text_box: VBoxContainer
var _status: Label
var _detail: Label
var _actions: VBoxContainer
var _drift: Tween
var _started := false
var _watching := false
var _slow := false
var _failed := false
var _done := false
var _elapsed := 0.0
var _start_fg := 0
var _start_windows := {}


func setup(id: String) -> LaunchOverlay:
	entry_id = id
	return self


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_to_group("modal")
	_entry = Library.get_entry(entry_id)
	_start_fg = Host.foreground
	for w in Host.windows:
		_start_windows[int(w["hwnd"])] = true

	var base := ColorRect.new()
	base.color = Color(0.02, 0.035, 0.05)
	base.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(base)

	_backdrop = TextureRect.new()
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_backdrop.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bm := ShaderMaterial.new()
	bm.shader = BACKDROP
	_backdrop.material = bm
	_backdrop.modulate.a = 0.0
	_backdrop.resized.connect(func() -> void: _backdrop.pivot_offset = _backdrop.size / 2.0)
	add_child(_backdrop)

	_stage = Control.new()
	_stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.resized.connect(func() -> void: _stage.pivot_offset = _stage.size / 2.0)
	add_child(_stage)
	var col := Kit.vbox(0)
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(col)

	col.add_child(_vgap(1.0))
	# A plain slot, so the title can rise into place without the box layout
	# snapping it back.
	_title_slot = Control.new()
	_title_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_title_slot)
	_title_holder = CenterContainer.new()
	_title_holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_title_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_holder.minimum_size_changed.connect(func() -> void: _title_slot.custom_minimum_size = _title_holder.get_combined_minimum_size())
	_title_slot.add_child(_title_holder)
	_logo = TextureRect.new()
	_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_logo.visible = false
	_title_holder.add_child(_logo)
	_name = Kit.label(str(_entry.get("name", "")), 68, 600, Color.WHITE, true)
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_name.custom_minimum_size = Vector2(1100, 0)
	_title_holder.add_child(_name)
	col.add_child(_vgap(0.8))

	_status_box = Kit.vbox(0)
	# Room for the buttons a failed launch adds, so nothing above them moves.
	_status_box.custom_minimum_size.y = 196
	_status_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_status_box)
	var orb_holder := CenterContainer.new()
	orb_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_box.add_child(orb_holder)
	_orb = UpdateOrb.new(60, 0.86)
	_orb.mat.set_shader_parameter("ripples", 0.0)
	_orb.mat.set_shader_parameter("waves", 0.7)
	_orb.mat.set_shader_parameter("swirl", -0.3)
	_orb.snap(0.1)
	orb_holder.add_child(_orb)
	_status_box.add_child(Kit.spacer(0, 16))
	_text_box = Kit.vbox(4)
	_text_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_box.add_child(_text_box)
	_status = Kit.label("Starting", 17, 500, App.TEXT)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_text_box.add_child(_status)
	_detail = Kit.label(_store(), 14, 500, Color(1, 1, 1, 0.5))
	_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail.visible = _detail.text != ""
	_text_box.add_child(_detail)
	_actions = Kit.vbox(0)
	_actions.visible = false
	_status_box.add_child(_actions)
	col.add_child(Kit.spacer(0, 40))
	_title_slot.custom_minimum_size = _title_holder.get_combined_minimum_size()

	Art.art_ready.connect(_on_art_ready)
	_show_logo(Art.get_art(entry_id, &"logo"), false)
	_set_backdrop(_source_art(), false)
	_intro()


## The art is ready and the launch went out: wait for the game's window.
func success() -> void:
	if _done:
		return
	_started = true
	_elapsed = 0.0
	if Host.available and not Host.mocked:
		_watching = true
		Host.windows_changed.connect(_check_game)
		Host.fullscreen_changed.connect(func(_on: bool) -> void: _check_game())
		_check_game()
	else:
		var t := create_tween()
		t.tween_interval(BLIND_HOLD)
		t.tween_callback(hand_off)


func fail() -> void:
	if _done:
		return
	_failed = true
	_watching = false
	_orb.set_look({"error": 1.0, "swirl": 0.0, "waves": 0.25}, 0.5)
	_orb.target = 0.5
	var store := _store()
	_swap_text("Couldn't start the game",
		("%s didn't open it. Its details may need a look." % store) if store != "" else "Its file or launch options may need a look.")
	var row := Kit.hbox(10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var edit := FxButton.make("Edit details", "edit", FxButton.Style.GHOST, 42)
	edit.pressed.connect(func() -> void:
		dismiss()
		if on_edit.is_valid():
			on_edit.call(entry_id)
	)
	var close := FxButton.make("Close", "", FxButton.Style.GHOST, 42)
	close.custom_minimum_size.x = 104
	close.pressed.connect(dismiss)
	row.add_child(edit)
	row.add_child(close)
	_actions.add_child(Kit.spacer(0, 24))
	_actions.add_child(row)
	_actions.visible = true
	_actions.modulate.a = 0.0
	create_tween().tween_property(_actions, "modulate:a", 1.0, 0.35).set_delay(0.15)
	edit.grab_focus.call_deferred()


## The game is on screen (or close enough): fill the orb, let the art and
## logo drift forward and fade, revealing the game underneath.
func hand_off() -> void:
	if _done:
		return
	_done = true
	_watching = false
	remove_from_group("modal")
	_orb.target = 1.0
	if Settings.get_value("minimize_for_games") and not App.smoke_test:
		get_window().mode = Window.MODE_MINIMIZED
	if _drift and _drift.is_valid():
		_drift.kill()
	var t := create_tween().set_parallel(true).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	t.tween_property(_stage, "scale", Vector2.ONE * 1.035, 0.5)
	t.tween_property(_status_box, "modulate:a", 0.0, 0.2)
	t.tween_property(_backdrop, "scale", _backdrop.scale * 1.03, 0.5)
	t.tween_property(self, "modulate:a", 0.0, 0.42).set_delay(0.08).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.chain().tween_callback(_finish)


## Leave without waiting for the game (Esc, a click, Close, or giving up).
func dismiss() -> void:
	if _done:
		return
	_done = true
	_watching = false
	remove_from_group("modal")
	var t := create_tween().set_parallel(true).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	t.tween_property(_stage, "scale", Vector2.ONE * 0.985, 0.32)
	t.tween_property(self, "modulate:a", 0.0, 0.3)
	t.chain().tween_callback(_finish)


func _finish() -> void:
	finished.emit()
	queue_free()


func _process(delta: float) -> void:
	if not _started or _done or _failed:
		return
	_elapsed += delta
	# No real progress to read, so the water rises fast, then ever more slowly.
	_orb.target = 0.16 + 0.72 * (1.0 - exp(-_elapsed / 6.0))
	if _watching and not _slow and _elapsed > SLOW_AFTER:
		show_slow()
	if _watching and _elapsed > GIVE_UP_AFTER:
		App.toast("%s is still starting" % str(_entry.get("name", "Your game")))
		dismiss()


## The launcher is taking its time: say so, and how to get back to work.
func show_slow() -> void:
	_slow = true
	var store := _store()
	_swap_text("Still starting", ("%s can take a moment. " % store if store != "" else "") + "Press Esc to wait on your desktop.")


## Steps aside as soon as anything but Oazy takes the screen: the game, or a
## launcher dialog that would otherwise sit hidden under this layer.
func _check_game() -> void:
	if not _watching or _done:
		return
	if Host.fullscreen_app or (not Host.self_foreground and Host.foreground != 0 and Host.foreground != _start_fg):
		hand_off()
		return
	# A game Oazy started itself may show its window before it takes focus.
	var image := Library.session_image(entry_id)
	if image == "":
		return
	for w in Host.windows:
		if not _start_windows.has(int(w["hwnd"])) and str(w["exe"]).replace("\\", "/").get_file().to_lower() == image:
			hand_off()
			return


func _intro() -> void:
	modulate.a = 0.0
	_backdrop.scale = Vector2.ONE * 1.08
	_title_holder.modulate.a = 0.0
	_rise(18.0)
	_status_box.modulate.a = 0.0
	var t := create_tween().set_parallel(true).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	t.tween_property(self, "modulate:a", 1.0, 0.3).set_trans(Tween.TRANS_QUART)
	t.tween_property(_backdrop, "scale", Vector2.ONE * 1.015, 1.4)
	t.tween_property(_title_holder, "modulate:a", 1.0, 0.55).set_delay(0.12).set_trans(Tween.TRANS_SINE)
	t.tween_property(_status_box, "modulate:a", 1.0, 0.5).set_delay(0.32).set_trans(Tween.TRANS_SINE)
	t.tween_method(_rise, 18.0, 0.0, 0.8).set_delay(0.12)
	t.chain().tween_callback(_start_drift)


## Moves the title down by `y` without touching its anchors.
func _rise(y: float) -> void:
	_title_holder.offset_top = y
	_title_holder.offset_bottom = y


## A slow push-in on the art while we wait, so the screen never feels frozen.
func _start_drift() -> void:
	if _done:
		return
	_drift = create_tween().set_loops()
	_drift.tween_property(_backdrop, "scale", Vector2.ONE * 1.05, 14.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_drift.tween_property(_backdrop, "scale", Vector2.ONE * 1.015, 14.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## The store or launcher the game comes from ("Steam"), or "" for a game
## added by hand.
func _store() -> String:
	var src := Library.source_label(_entry)
	return "" if src in ["Game", "App"] else src


func _swap_text(status: String, detail: String) -> void:
	var t := create_tween().set_trans(Tween.TRANS_SINE)
	t.tween_property(_text_box, "modulate:a", 0.0, 0.18)
	t.tween_callback(func() -> void:
		_status.text = status
		_detail.text = detail
		_detail.visible = detail != ""
	)
	t.tween_property(_text_box, "modulate:a", 1.0, 0.32)


func _source_art() -> Texture2D:
	var tex := Art.get_art(entry_id, &"hero")
	if tex == null and Art.is_resolved(entry_id, &"hero"):
		tex = Art.get_art(entry_id, &"cover")
	return tex


func _on_art_ready(id: String, kind: StringName) -> void:
	if id != entry_id or _done:
		return
	if kind == &"logo":
		_show_logo(Art.get_art(entry_id, &"logo"), true)
	elif kind == &"hero" or kind == &"cover":
		if _backdrop.texture == null:
			_set_backdrop(_source_art(), true)


func _set_backdrop(tex: Texture2D, fade: bool) -> void:
	if tex == null:
		# Nothing yet: a soft field in the game's own colours.
		var cols := Kit.cover_colors(str(_entry.get("name", "")), str(_entry.get("accent", "")))
		var g := Gradient.new()
		g.set_color(0, cols[0].darkened(0.2))
		g.set_color(1, cols[1].darkened(0.45))
		var gt := GradientTexture2D.new()
		gt.gradient = g
		gt.fill = GradientTexture2D.FILL_RADIAL
		gt.fill_from = Vector2(0.5, 0.35)
		gt.fill_to = Vector2(1.1, 1.1)
		gt.width = 256
		gt.height = 144
		_backdrop.texture = gt
		_backdrop.modulate.a = 1.0
		return
	if not _blurred.has(entry_id):
		_blurred[entry_id] = _blur(tex)
	_backdrop.texture = _blurred[entry_id]
	if fade:
		_backdrop.modulate.a = 0.0
		create_tween().tween_property(_backdrop, "modulate:a", 1.0, 0.8).set_trans(Tween.TRANS_SINE)
	else:
		_backdrop.modulate.a = 1.0


## A cheap, smooth blur: average down by halves, then scale back up with a
## cubic filter. Done once per game; the GPU just stretches the result.
static func _blur(tex: Texture2D) -> Texture2D:
	var img := tex.get_image()
	if img == null or img.is_empty():
		return tex
	img = img.duplicate()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGB8)
	while img.get_width() > BLUR_W * 2:
		img.shrink_x2()
	img.resize(BLUR_W, maxi(1, roundi(float(BLUR_W) * img.get_height() / img.get_width())), Image.INTERPOLATE_BILINEAR)
	img.resize(BLUR_W * 6, img.get_height() * 6, Image.INTERPOLATE_CUBIC)
	return ImageTexture.create_from_image(img)


func _show_logo(tex: Texture2D, fade: bool) -> void:
	if tex == null or _logo.visible:
		return
	var sz := tex.get_size()
	var k := minf(LOGO_BOX.x / sz.x, LOGO_BOX.y / sz.y)
	_logo.texture = tex
	_logo.custom_minimum_size = (sz * k).round()
	_logo.visible = true
	if not fade:
		_name.visible = false
		return
	_logo.modulate.a = 0.0
	var t := create_tween().set_trans(Tween.TRANS_SINE)
	t.tween_property(_name, "modulate:a", 0.0, 0.2)
	t.tween_callback(func() -> void: _name.visible = false)
	t.tween_property(_logo, "modulate:a", 1.0, 0.45)


static func _vgap(ratio: float) -> Control:
	var c := Kit.spacer()
	c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	c.size_flags_stretch_ratio = ratio
	return c


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		dismiss()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		dismiss()
		get_viewport().set_input_as_handled()


func close() -> void:
	dismiss()
