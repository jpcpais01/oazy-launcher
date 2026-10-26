class_name LibraryCard
extends Control
## Portrait card in the Library grid. Lifts a touch and takes a hairline ring
## on hover/focus, and reveals a quick-play button.

signal open(id: String)
signal play(id: String)
signal context(id: String, at: Vector2)

const W := 192.0
const H := 288.0

var entry_id := ""
var card_w := W
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
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	_holder = Control.new()
	_holder.position = Vector2.ZERO
	_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_holder)
	cover = CoverArt.new()
	cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_holder.add_child(cover)
	cover.setup(entry_id, 12.0)

	_play_btn = FxButton.icon_only("play", "Play", 18, 42)
	_play_btn.variant = FxButton.Style.PRIMARY
	_play_btn._apply_style()
	# PRIMARY pads for text labels; an icon-only round button needs none, or it
	# grows into a wide pill that spills past the card's edge.
	for st in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		_play_btn.get_theme_stylebox(st).set_content_margin_all(0)
	_play_btn.size = Vector2(42, 42)
	_play_btn.modulate.a = 0.0
	_play_btn.focus_mode = Control.FOCUS_NONE
	_play_btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_play_btn.pressed.connect(func() -> void: play.emit(entry_id))
	_holder.add_child(_play_btn)

	_name = Kit.label("", 15, 500, App.TEXT)
	_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_name.clip_text = true
	add_child(_name)
	_meta = Kit.label("", 13, 500, App.TEXT_MUTE)
	_meta.clip_text = true
	_meta.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	add_child(_meta)
	_layout()

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
	cover.set_dim(0.05)


## Cards stretch a little so a row always fills the page edge to edge.
func set_card_width(w: float) -> void:
	if is_equal_approx(w, card_w):
		return
	card_w = w
	if is_node_ready():
		_layout()


func _layout() -> void:
	var h := roundf(card_w * H / W)
	custom_minimum_size = Vector2(card_w, h + 58)
	_holder.size = Vector2(card_w, h)
	_holder.pivot_offset = _holder.size / 2.0
	_play_btn.size = _play_btn.get_combined_minimum_size()
	_play_btn.position = Vector2(card_w, h) - _play_btn.size - Vector2(10, 10)
	_name.position = Vector2(2, h + 11)
	_name.size = Vector2(card_w - 4, 20)
	_meta.position = Vector2(2, h + 32)
	_meta.size = Vector2(card_w - 4, 18)


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
		if not has_focus():
			Sfx.play(&"move", 1.15)
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_holder, "position:y", -4.0 if on else 0.0, 0.22)
	_tween.tween_property(_holder, "scale", Vector2.ONE * (1.012 if on else 1.0), 0.22)
	_tween.tween_property(cover, "focus_amount", 1.0 if on else 0.0, 0.18)
	_tween.tween_property(_play_btn, "modulate:a", 1.0 if on else 0.0, 0.16)
	_tween.tween_property(_name, "modulate", Color.WHITE if on else Color(1, 1, 1, 0.92), 0.16)
	_play_btn.mouse_filter = Control.MOUSE_FILTER_STOP if on else Control.MOUSE_FILTER_IGNORE
	cover.set_dim(0.0 if on else 0.05)


func intro(delay: float) -> void:
	modulate.a = 0.0
	_holder.position.y = 10.0
	var t := create_tween().set_parallel(true).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	t.tween_property(self, "modulate:a", 1.0, 0.28).set_delay(delay)
	t.tween_property(_holder, "position:y", 0.0, 0.4).set_delay(delay)


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
		context.emit(entry_id, global_position + _holder.size / 2.0)
		accept_event()

