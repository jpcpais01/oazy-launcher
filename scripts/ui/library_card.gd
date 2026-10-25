class_name LibraryCard
extends Control
## Portrait card in the Library grid. Lifts, glows and sweeps on hover/focus,
## and reveals a quick-play button.

signal open(id: String)
signal play(id: String)
signal context(id: String, at: Vector2)

const W := 192.0
const H := 288.0

var entry_id := ""
var cover: CoverArt
var _holder: Control
var _name: Label
var _meta: Label
var _play_btn: FxButton
var _hot := false
var _tween: Tween


func setup(id: String) -> LibraryCard:
	entry_id = id
	return self


func _ready() -> void:
	custom_minimum_size = Vector2(W, H + 58)
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	_holder = Control.new()
	_holder.position = Vector2.ZERO
	_holder.size = Vector2(W, H)
	_holder.pivot_offset = Vector2(W, H) / 2.0
	_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_holder)
	cover = CoverArt.new()
	cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_holder.add_child(cover)
	cover.setup(entry_id, 16.0)

	_play_btn = FxButton.icon_only("play", "Play", 20, 46)
	_play_btn.variant = FxButton.Style.PRIMARY
	_play_btn._apply_style()
	_play_btn.position = Vector2(W - 58, H - 58)
	_play_btn.size = Vector2(46, 46)
	_play_btn.modulate.a = 0.0
	_play_btn.focus_mode = Control.FOCUS_NONE
	_play_btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_play_btn.pressed.connect(func() -> void: play.emit(entry_id))
	_holder.add_child(_play_btn)

	_name = Kit.label("", 15, 600, App.TEXT)
	_name.position = Vector2(2, H + 12)
	_name.size = Vector2(W - 4, 20)
	_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_name.clip_text = true
	add_child(_name)
	_meta = Kit.label("", 13, 500, App.TEXT_MUTE)
	_meta.position = Vector2(2, H + 34)
	_meta.size = Vector2(W - 4, 18)
	_meta.clip_text = true
	_meta.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	add_child(_meta)

	mouse_entered.connect(_set_hot.bind(true))
	mouse_exited.connect(func() -> void: _set_hot(has_focus()))
	focus_entered.connect(func() -> void:
		_set_hot(true)
		Sfx.play(&"move")
	)
	focus_exited.connect(func() -> void: _set_hot(_is_mouse_inside()))
	Library.entry_changed.connect(func(id: String) -> void:
		if id == entry_id:
			_refresh_text()
	)
	_refresh_text()
	cover.set_dim(0.08)


func _refresh_text() -> void:
	var e := Library.get_entry(entry_id)
	if e.is_empty():
		return
	_name.text = str(e["name"])
	var bits := PackedStringArray([Library.source_label(e)])
	if int(e["playtime"]) >= 60:
		bits.append(Fmt.playtime(int(e["playtime"])).replace(" played", ""))
	elif int(e["last_played"]) > 0:
		bits.append(Fmt.ago(int(e["last_played"])))
	if e["favorite"]:
		bits.append("♥")
	_meta.text = "  ·  ".join(bits)


func _is_mouse_inside() -> bool:
	return Rect2(Vector2.ZERO, size).has_point(get_local_mouse_position())


func _set_hot(on: bool) -> void:
	if on == _hot:
		return
	_hot = on
	if on:
		cover.sweep()
		if not has_focus():
			Sfx.play(&"move", 1.15)
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_holder, "position:y", -8.0 if on else 0.0, 0.4)
	_tween.tween_property(_holder, "scale", Vector2.ONE * (1.035 if on else 1.0), 0.4)
	_tween.tween_property(cover, "focus_amount", 1.0 if on else 0.0, 0.3)
	_tween.tween_property(_play_btn, "modulate:a", 1.0 if on else 0.0, 0.25)
	_tween.tween_property(_name, "modulate", Color.WHITE if on else Color(1, 1, 1, 0.92), 0.25)
	_play_btn.mouse_filter = Control.MOUSE_FILTER_STOP if on else Control.MOUSE_FILTER_IGNORE
	cover.set_dim(0.0 if on else 0.08)


func intro(delay: float) -> void:
	modulate.a = 0.0
	_holder.position.y = 26.0
	var t := create_tween().set_parallel(true).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	t.tween_property(self, "modulate:a", 1.0, 0.45).set_delay(delay)
	t.tween_property(_holder, "position:y", 0.0, 0.65).set_delay(delay)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			open.emit(entry_id)
			accept_event()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			context.emit(entry_id, get_global_mouse_position())
			accept_event()
	elif event.is_action_pressed("ui_accept"):
		play.emit(entry_id)
		accept_event()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_MENU:
		context.emit(entry_id, global_position + Vector2(W / 2.0, H / 2.0))
		accept_event()

