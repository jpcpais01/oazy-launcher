class_name ReorderGrid
extends Control
## A grid of same-sized tiles you can drag into a new order. Tiles snap to
## cells, the others ease aside while one is dragged, and a press only turns
## into a drag after a few pixels, so clicks work as before. Tiles with the
## meta "fixed" stay put and can't be dragged past.

signal reordered(from: int, to: int)

const DRAG_THRESHOLD := 6.0

var columns := 6:
	set(v):
		columns = maxi(v, 1)
		_relayout(true)
var cell := Vector2(96, 96)
var gap := 4.0

var _order: Array[Control] = []
var _press_tile: Control
var _press_at := Vector2.INF
var _drag: Control
var _grab := Vector2.ZERO
var _from := -1
var _dropped := false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)


## Replaces every tile; they start in their cells.
func set_tiles(tiles: Array[Control], cell_size: Vector2) -> void:
	_drag = null
	_press_tile = null
	for c in get_children():
		remove_child(c)
		c.queue_free()
	cell = cell_size
	_order = tiles.duplicate()
	for t in _order:
		add_child(t)
		t.size = cell
		t.gui_input.connect(_on_tile_input.bind(t))
	_relayout(true)


## True once, right after a drag ended, so the tile's click can skip itself.
func consume_drag() -> bool:
	var d := _dropped
	_dropped = false
	return d


func is_dragging() -> bool:
	return _drag != null


func _slot_pos(i: int) -> Vector2:
	return Vector2(i % columns, i / columns) * (cell + Vector2(gap, gap))


func _relayout(snap: bool) -> void:
	var n := _order.size()
	var cols := mini(n, columns)
	var rows := ceili(float(n) / columns)
	custom_minimum_size = Vector2(cols * cell.x + maxi(cols - 1, 0) * gap, rows * cell.y + maxi(rows - 1, 0) * gap)
	size = custom_minimum_size
	if snap:
		for i in n:
			if _order[i] != _drag:
				_order[i].position = _slot_pos(i)
	else:
		set_process(true)


func _movable() -> int:
	var last := -1
	for i in _order.size():
		if not _order[i].has_meta("fixed"):
			last = i
	return last


func _on_tile_input(e: InputEvent, tile: Control) -> void:
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed:
			_dropped = false
			_press_tile = tile
			_press_at = get_global_mouse_position()
		else:
			_press_tile = null
			if _drag == tile:
				_end_drag()
		return
	if not (e is InputEventMouseMotion) or tile != _press_tile or not (e.button_mask & MOUSE_BUTTON_MASK_LEFT):
		return
	if _drag == null:
		if tile.has_meta("fixed") or _movable() < 1 or get_global_mouse_position().distance_to(_press_at) <= DRAG_THRESHOLD:
			return
		_drag = tile
		_from = _order.find(tile)
		_grab = get_global_mouse_position() - tile.global_position
		tile.z_index = 1
		var t := Kit.hover_tween(tile).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
		t.tween_property(tile, "scale", Vector2.ONE * 1.06, 0.2)
		set_process(true)
	var p := get_global_mouse_position() - _grab - global_position
	var far := Vector2(_slot_pos(mini(_movable(), columns - 1)).x, _slot_pos(_movable()).y)
	tile.position = p.clamp(Vector2(-12, -12), far + Vector2(12, 12))
	var step := cell + Vector2(gap, gap)
	var col := clampi(int(roundf(tile.position.x / step.x)), 0, columns - 1)
	var row := maxi(int(roundf(tile.position.y / step.y)), 0)
	var slot := clampi(row * columns + col, 0, _movable())
	if _order.find(tile) != slot:
		_order.erase(tile)
		_order.insert(slot, tile)
		Sfx.play(&"move", 1.1)
	accept_event()


func _end_drag() -> void:
	var tile := _drag
	_drag = null
	_dropped = true
	tile.z_index = 0
	var t := Kit.hover_tween(tile).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	t.tween_property(tile, "scale", Vector2.ONE, 0.25)
	set_process(true)
	var to := _order.find(tile)
	if to != _from:
		reordered.emit(_from, to)


func _process(delta: float) -> void:
	if _drag and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		# The release went to another window.
		_end_drag()
	var busy := _drag != null
	var k := 1.0 - exp(-delta * 16.0)
	for i in _order.size():
		var t := _order[i]
		if t == _drag:
			continue
		var goal := _slot_pos(i)
		if t.position.distance_to(goal) < 0.4:
			t.position = goal
		else:
			t.position = t.position.lerp(goal, k)
			busy = true
	set_process(busy)
