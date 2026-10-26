class_name TasksFlyout
extends Flyout
## Oazy's task manager: a glass card that rises from its own taskbar button,
## with a tail pointing down at it. Everything running, one row per app (its
## windows and every process it started), CPU and memory for each and for the
## PC, and a clear End button. Background programs and Windows' own sit in
## folding sections; what Windows can't live without has no End at all.
## Polls only while open.

const REF := "oazy:tasks"
const TAIL := 13.0
## From the tail's tip down to the top of the button it points at.
const GAP := 7.0
## The list grows with what it shows, up to this, then scrolls.
const LIST_MAX := 420.0
const LIST_MIN := 160.0
const POLL := 1.5
const HISTORY := 48
const COL_CPU := 54.0
const COL_MEM := 70.0
const COL_ACT := 64.0
## A confirm or "needs admin" state on a row lasts this long.
const HOLD_MS := 5000
const SECTIONS := [["apps", "Apps"], ["background", "Background"], ["system", "Windows"]]

var main: Node
var _timer: Timer
var _data: Dictionary = {}
var _cpu_hist: Array = []
var _mem_hist: Array = []
var _sort := "cpu"
var _query := ""
var _folded := {"background": true, "system": true}
var _rows := {}
var _sections := {}
## Group key -> until (msec): End was pressed once and asks again.
var _confirm := {}
## Group key -> {until, pids}: Windows said no; End asks for admin rights.
var _denied := {}
## Group key -> since (msec): ending, greyed until it's gone.
var _ending := {}
var _expanded := ""
var _polling := false
var _last_poll := 0
var _mock_t := 0.0

var _count: Label
var _cpu_val: Label
var _cpu_sub: Label
var _cpu_spark: Sparkline
var _mem_val: Label
var _mem_sub: Label
var _mem_spark: Sparkline
var _search: LineEdit
var _heads := {}
var _scroll: ScrollContainer
var _list: VBoxContainer
var _empty: Label


func _init() -> void:
	width = 460.0


func _build() -> void:
	_glass.offset_bottom = TAIL
	var head := Kit.hbox(8)
	content.add_child(head)
	var title := Kit.label("Task manager", 15, 700, App.TEXT)
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(title)
	_count = Kit.label("", 12, 500, App.TEXT_MUTE)
	_count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_count)
	var startup := _chip("Startup apps", "rocket")
	startup.tooltip_text = "What starts when you sign in (in Cleaner)"
	startup.pressed.connect(_open_startup)
	head.add_child(startup)

	var meters := Kit.hbox(10)
	content.add_child(meters)
	var cpu := _meter("cpu", "CPU")
	meters.add_child(cpu[0])
	_cpu_val = cpu[1]
	_cpu_sub = cpu[2]
	_cpu_spark = cpu[3]
	_cpu_spark.ceil_v = 0.25
	var mem := _meter("memory", "Memory")
	meters.add_child(mem[0])
	_mem_val = mem[1]
	_mem_sub = mem[2]
	_mem_spark = mem[3]
	_mem_spark.ceil_v = 1.0

	var find := PanelContainer.new()
	find.add_theme_stylebox_override("panel", Kit.box(Color(1, 1, 1, 0.06), 999, Color(1, 1, 1, 0.08), 1, 12, 0))
	content.add_child(find)
	var find_row := Kit.hbox(8)
	find.add_child(find_row)
	var glass_icon := Kit.icon_rect("search", 15, Color(1, 1, 1, 0.55))
	glass_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	find_row.add_child(glass_icon)
	_search = LineEdit.new()
	_search.placeholder_text = "Find an app or process"
	_search.clear_button_enabled = true
	_search.custom_minimum_size.y = 34
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.add_theme_font_size_override("font_size", 13)
	for s in ["normal", "focus", "read_only"]:
		_search.add_theme_stylebox_override(s, Kit.empty())
	_search.text_changed.connect(func(t: String) -> void:
		_query = t.strip_edges().to_lower()
		_render()
	)
	find_row.add_child(_search)

	# Column heads double as the sort: CPU, memory or name.
	var cols := Kit.hbox(0)
	cols.add_theme_constant_override("separation", 0)
	content.add_child(cols)
	cols.add_child(Kit.spacer(6))
	var name_head := _col_head("Name", "name", HORIZONTAL_ALIGNMENT_LEFT)
	name_head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(name_head)
	var cpu_head := _col_head("CPU", "cpu", HORIZONTAL_ALIGNMENT_RIGHT)
	cpu_head.custom_minimum_size.x = COL_CPU
	cols.add_child(cpu_head)
	var mem_head := _col_head("Memory", "mem", HORIZONTAL_ALIGNMENT_RIGHT)
	mem_head.custom_minimum_size.x = COL_MEM + 6.0
	cols.add_child(mem_head)
	cols.add_child(Kit.spacer(COL_ACT + 12.0))
	_sync_heads()

	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# No bar: it would push the numbers out from under their column heads.
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_scroll.custom_minimum_size.y = LIST_MIN
	content.add_child(_scroll)
	_list = Kit.vbox(2)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_list)
	_list.minimum_size_changed.connect(func() -> void:
		_scroll.custom_minimum_size.y = clampf(_list.get_combined_minimum_size().y, LIST_MIN, LIST_MAX)
	)
	for spec in SECTIONS:
		_list.add_child(_section(spec[0], spec[1]))
	_empty = Kit.label("Nothing matches", 13, 500, App.TEXT_MUTE)
	_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty.custom_minimum_size.y = 80
	_empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_empty.visible = false
	_list.add_child(_empty)

	var foot := Kit.hbox(8)
	content.add_child(foot)
	var hint := Kit.label("Click a row for more", 12, 500, App.TEXT_MUTE)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	foot.add_child(hint)
	var full := _chip("Windows Task Manager", "external")
	full.tooltip_text = "Services, performance graphs and the rest"
	full.pressed.connect(func() -> void:
		close()
		if App.is_windows():
			OS.create_process("taskmgr.exe", [])
	)
	foot.add_child(full)

	_timer = Timer.new()
	_timer.wait_time = POLL
	_timer.timeout.connect(_poll)
	add_child(_timer)
	Host.windows_changed.connect(func() -> void:
		# Opened and closed windows show at once (a title changing doesn't need to).
		if is_open and not _data.is_empty() and Time.get_ticks_msec() - _last_poll > 600:
			_poll()
	)


func _on_open() -> void:
	_expanded = ""
	_confirm.clear()
	_poll()
	# The companion measures CPU between two looks: the second one, soon after
	# the first, gives a fresh reading instead of an average since last time.
	get_tree().create_timer(0.4).timeout.connect(func() -> void:
		if is_open:
			_poll()
	)
	_timer.start()


func close() -> void:
	super.close()
	if _timer:
		_timer.stop()
	if _search and _search.has_focus():
		_search.release_focus()


# --- Placement: centred over the button, the tail on it --------------------------------

func _place() -> void:
	var vp := Shell.view_size()
	var r := anchor.get_global_rect() if anchor and is_instance_valid(anchor) else Rect2(Vector2(vp.x * 0.5, vp.y - Taskbar.RESERVE + 6.0), Vector2.ZERO)
	var cx := r.get_center().x
	var x := clampf(cx - size.x * 0.5, 10.0, vp.x - size.x - 10.0)
	position = Vector2(x, r.position.y - GAP - TAIL - size.y)
	_glass.set_tail(clampf(cx - x, 34.0, size.x - 34.0), TAIL, 14.0)


func _pivot() -> Vector2:
	var cx := size.x * 0.5
	if anchor and is_instance_valid(anchor):
		cx = clampf(anchor.get_global_rect().get_center().x - position.x, 0.0, size.x)
	return Vector2(cx, size.y + TAIL)


# --- Data -----------------------------------------------------------------------------

func _poll() -> void:
	if not is_open or _polling:
		return
	_last_poll = Time.get_ticks_msec()
	if Host.available and not Host.mocked:
		_polling = true
		Host.procs(func(d: Dictionary) -> void:
			_polling = false
			if d.get("ok", false) and is_open:
				_apply(d, Host.windows)
		)
	else:
		_mock_t += POLL
		var m := TaskList.mock(Host.windows, _mock_t)
		_apply(m["snap"], m["windows"])


func _apply(snap: Dictionary, windows: Array) -> void:
	_data = TaskList.build(snap, windows)
	var cpu := maxf(float(_data["cpu"]), 0.0)
	var total := float(_data["mem_total"])
	var used := float(_data["mem_used"])
	_push(_cpu_hist, cpu)
	_push(_mem_hist, used / total if total > 0.0 else 0.0)
	_cpu_val.text = _pct(cpu)
	_cpu_sub.text = "%d cores" % int(snap.get("cores", 0)) if int(snap.get("cores", 0)) > 0 else ""
	_mem_val.text = _gb(used)
	_mem_sub.text = "of %s" % _gb(total, true) if total > 0.0 else ""
	_cpu_spark.set_data(_cpu_hist, NAN, App.accent)
	_mem_spark.set_data(_mem_hist, NAN, Color("8fb8ff"))
	var apps: int = _data["apps"].size()
	_count.text = "%d %s · %d processes" % [apps, "app" if apps == 1 else "apps", int(_data["count"])]
	var now := Time.get_ticks_msec()
	for k in _confirm.keys():
		if now > int(_confirm[k]):
			_confirm.erase(k)
	for k in _denied.keys():
		if now > int(_denied[k]["until"]):
			_denied.erase(k)
	for k in _ending.keys():
		if now - int(_ending[k]) > 4000:
			_ending.erase(k)
	_render()


static func _push(hist: Array, v: float) -> void:
	hist.append(v)
	while hist.size() > HISTORY:
		hist.pop_front()
	# A flat start until there's history, so the line begins at once.
	while hist.size() < 2:
		hist.push_front(v)


func _render() -> void:
	if _data.is_empty():
		return
	var shown := 0
	var keep := {}
	for spec in SECTIONS:
		var id: String = spec[0]
		var sec: Dictionary = _sections[id]
		var list: Array = _data[id].filter(_matches)
		list.sort_custom(_sorter)
		var cpu := 0.0
		var mem := 0.0
		for g in list:
			cpu += float(g["cpu"])
			mem += float(g["mem"])
		sec["box"].visible = not list.is_empty()
		sec["count"].text = str(list.size())
		sec["totals"].text = "%s · %s" % [_pct(cpu), _mb(mem)] if id != "apps" else ""
		var folded: bool = _folded.get(id, false) and _query == ""
		if sec.has("chevron"):
			sec["chevron"].rotation_degrees = -90.0 if folded else 0.0
		sec["body"].visible = not folded
		shown += list.size()
		if folded:
			continue
		var i := 0
		for g in list:
			var key: String = g["key"]
			keep[key] = true
			var row: TaskRow = _rows.get(key)
			if row == null:
				row = TaskRow.new(self)
				_rows[key] = row
			if row.get_parent() != sec["body"]:
				if row.get_parent():
					row.get_parent().remove_child(row)
				sec["body"].add_child(row)
			sec["body"].move_child(row, i)
			row.show_group(g)
			i += 1
	for key in _rows.keys():
		if not keep.has(key):
			_rows[key].queue_free()
			_rows.erase(key)
	_empty.visible = shown == 0


func _matches(g: Dictionary) -> bool:
	if _query == "":
		return true
	return str(g["name"]).to_lower().contains(_query) or str(g["exe"]).get_file().to_lower().contains(_query)


func _sorter(a: Dictionary, b: Dictionary) -> bool:
	match _sort:
		"mem":
			if not is_equal_approx(float(a["mem"]), float(b["mem"])):
				return float(a["mem"]) > float(b["mem"])
		"cpu":
			# Within a tenth of a percent counts as the same, so rows don't swap
			# places on every reading.
			if absf(float(a["cpu"]) - float(b["cpu"])) > 0.001:
				return float(a["cpu"]) > float(b["cpu"])
			if not is_equal_approx(float(a["mem"]), float(b["mem"])):
				return float(a["mem"]) > float(b["mem"])
	return str(a["name"]).naturalnocasecmp_to(str(b["name"])) < 0


# --- Actions ----------------------------------------------------------------------------

## End pressed on a row: ask first where work could be lost, ask Windows for
## admin rights where it said no, otherwise end it now.
func end_group(g: Dictionary) -> void:
	var key: String = g["key"]
	if g["protected"] or _ending.has(key):
		return
	if _denied.has(key):
		_end_as_admin(g, _denied[key]["pids"])
		_denied.erase(key)
		_render()
		return
	var asks: bool = g["risky"] or g["section"] == "system"
	if asks and not _confirm.has(key):
		_confirm[key] = Time.get_ticks_msec() + HOLD_MS
		Sfx.play(&"move")
		_render()
		_expire_later()
		return
	_confirm.erase(key)
	_ending[key] = Time.get_ticks_msec()
	Sfx.play(&"select")
	if g["close_only"]:
		for w in g["windows"]:
			Host.close_window(int(w["hwnd"]))
		_render()
		return
	if not Host.available or Host.mocked:
		_render()
		return
	Host.kill(g["pids"], func(d: Dictionary) -> void:
		var denied: Array = d.get("denied", [])
		if not denied.is_empty() and int(d.get("ended", 0)) == 0:
			_ending.erase(key)
			_denied[key] = {"until": Time.get_ticks_msec() + HOLD_MS * 2, "pids": denied}
			_expire_later()
		elif not d.get("ok", false) and d.has("error"):
			_ending.erase(key)
			App.toast("Couldn't end %s" % g["name"], &"error")
		_poll()
	)
	_render()


func _expire_later() -> void:
	get_tree().create_timer(HOLD_MS / 1000.0 + 0.1).timeout.connect(func() -> void:
		if is_open and not _data.is_empty():
			var now := Time.get_ticks_msec()
			for k in _confirm.keys():
				if now > int(_confirm[k]):
					_confirm.erase(k)
			_render()
	)


## Windows' own taskkill, run as admin: Windows asks first (UAC).
func _end_as_admin(g: Dictionary, pids: Array) -> void:
	if not App.is_windows():
		return
	var args := PackedStringArray(["/F", "/T"])
	for p in pids:
		args.append("/PID")
		args.append(str(int(p)))
	var cmd := "Start-Process taskkill -Verb RunAs -WindowStyle Hidden -ArgumentList '%s'" % " ".join(args)
	OS.create_process("powershell.exe", ["-NoProfile", "-WindowStyle", "Hidden", "-Command", cmd])
	_ending[g["key"]] = Time.get_ticks_msec()
	get_tree().create_timer(2.0).timeout.connect(_poll)


func switch_to(g: Dictionary) -> void:
	if g["windows"].is_empty():
		return
	close()
	Host.focus(int(g["windows"][0]["hwnd"]))


func show_file(g: Dictionary) -> void:
	var exe: String = g["exe"]
	if exe != "":
		OS.shell_show_in_file_manager(exe.replace("/", "\\") if App.is_windows() else exe)


## What is this? A web search for the program's file name.
func look_up(g: Dictionary) -> void:
	var file: String = str(g["exe"]).get_file()
	if file == "":
		file = str(g["name"])
	var url := "https://www.google.com/search?q=" + ("what is " + file).uri_encode()
	close()
	if App.is_windows():
		Browser.open(url)
	else:
		OS.shell_open(url)


func toggle_details(key: String) -> void:
	_expanded = "" if _expanded == key else key
	_render()


func state_of(key: String) -> StringName:
	if _ending.has(key):
		return &"ending"
	if _denied.has(key):
		return &"denied"
	if _confirm.has(key):
		return &"confirm"
	return &""


func is_expanded(key: String) -> bool:
	return _expanded == key


func _open_startup() -> void:
	close()
	var win: ShellWindow = main.open_app(&"cleaner") if main else null
	if win and win.body.get_child_count() > 0:
		var cl: CleanerApp = win.body.get_child(0)
		cl._go("startup")


# --- Building bits ----------------------------------------------------------------------

func _meter(glyph: String, title: String) -> Array:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", Kit.box(Color(1, 1, 1, 0.04), 16, Color(1, 1, 1, 0.07), 1, 12, 10))
	var col := Kit.vbox(4)
	card.add_child(col)
	var top := Kit.hbox(6)
	col.add_child(top)
	var ic := Kit.icon_rect(glyph, 14, Color(1, 1, 1, 0.55))
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(ic)
	var name := Kit.label(title, 12, 600, App.TEXT_DIM)
	name.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(name)
	var sub := Kit.label("", 11, 500, App.TEXT_MUTE)
	sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	sub.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(sub)
	var val := Kit.label("–", 20, 700, App.TEXT)
	col.add_child(val)
	var spark := Sparkline.new()
	spark.custom_minimum_size.y = 30
	spark.floor_v = 0.0
	spark.width = 1.4
	spark.smooth = 0
	col.add_child(spark)
	return [card, val, sub, spark]


func _chip(text: String, glyph: String) -> Button:
	var b := Button.new()
	b.text = text
	b.icon = Icons.tex(glyph, 14, Color(1, 1, 1, 0.75))
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.custom_minimum_size.y = 28
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.add_theme_font_override("font", Kit.font(600))
	b.add_theme_font_size_override("font_size", 12)
	b.add_theme_color_override("font_color", App.TEXT_DIM)
	b.add_theme_color_override("font_hover_color", App.TEXT)
	b.add_theme_constant_override("h_separation", 6)
	b.add_theme_stylebox_override("normal", Kit.box(Color(1, 1, 1, 0.05), 999, Color(1, 1, 1, 0.07), 1, 10, 0))
	b.add_theme_stylebox_override("hover", Kit.box(Color(1, 1, 1, 0.1), 999, Color(1, 1, 1, 0.13), 1, 10, 0))
	b.add_theme_stylebox_override("pressed", Kit.box(Color(1, 1, 1, 0.14), 999, Color(1, 1, 1, 0.16), 1, 10, 0))
	return b


func _col_head(text: String, sort_id: String, align: HorizontalAlignment) -> Button:
	var b := Button.new()
	b.flat = true
	b.text = text
	b.alignment = align
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.tooltip_text = "Sort by " + text.to_lower()
	b.add_theme_font_override("font", Kit.font(600))
	b.add_theme_font_size_override("font_size", 11)
	for st in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		b.add_theme_stylebox_override(st, Kit.empty())
	b.pressed.connect(func() -> void:
		_sort = sort_id
		Sfx.play(&"move")
		_sync_heads()
		_render()
	)
	_heads[sort_id] = b
	return b


func _sync_heads() -> void:
	for id in _heads:
		var b: Button = _heads[id]
		var on: bool = id == _sort
		var c := App.TEXT if on else App.TEXT_MUTE
		b.add_theme_color_override("font_color", c)
		b.add_theme_color_override("font_hover_color", App.TEXT)
		b.add_theme_color_override("font_pressed_color", App.TEXT)


func _section(id: String, title: String) -> Control:
	var box := Kit.vbox(2)
	var head := Button.new()
	head.flat = true
	head.focus_mode = Control.FOCUS_NONE
	head.custom_minimum_size.y = 30
	for st in ["normal", "pressed", "focus"]:
		head.add_theme_stylebox_override(st, Kit.empty())
	head.add_theme_stylebox_override("hover", Kit.box(Color(1, 1, 1, 0.04), 10))
	head.add_theme_stylebox_override("hover_pressed", Kit.box(Color(1, 1, 1, 0.04), 10))
	box.add_child(head)
	var row := Kit.hbox(6)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 6
	row.offset_right = -COL_ACT - 12.0
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(row)
	var sec := {"box": box}
	if id != "apps":
		head.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var chev := Kit.icon_rect("chevron_down", 14, Color(1, 1, 1, 0.55))
		chev.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		chev.custom_minimum_size = Vector2(14, 14)
		chev.pivot_offset = Vector2(7, 7)
		row.add_child(chev)
		sec["chevron"] = chev
		head.pressed.connect(func() -> void:
			_folded[id] = not _folded.get(id, false)
			Sfx.play(&"move")
			_render()
		)
	else:
		head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var name := Kit.label(title, 12, 700, App.TEXT_DIM)
	name.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(name)
	var count := Kit.label("", 12, 600, App.TEXT_MUTE)
	count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(count)
	var totals := Kit.label("", 11, 500, App.TEXT_MUTE)
	totals.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(totals)
	var body := Kit.vbox(2)
	box.add_child(body)
	sec["count"] = count
	sec["totals"] = totals
	sec["body"] = body
	_sections[id] = sec
	return box


static func _pct(v: float) -> String:
	var p := maxf(v, 0.0) * 100.0
	if p >= 9.95:
		return "%d%%" % int(roundf(p))
	if p < 0.05:
		return "0%"
	return "%.1f%%" % p


static func _mb(bytes: float) -> String:
	if bytes >= 1073741824.0:
		return "%.1f GB" % (bytes / 1073741824.0)
	return "%d MB" % int(roundf(bytes / 1048576.0))


static func _gb(bytes: float, whole: bool = false) -> String:
	var g := bytes / 1073741824.0
	return ("%d GB" % int(roundf(g))) if whole else ("%.1f GB" % g)


## One app or program: icon, name, CPU, memory and End. Clicking it unfolds a
## strip of extras (switch to it, its file, what is it).
class TaskRow extends VBoxContainer:
	var owner_flyout: TasksFlyout
	var group: Dictionary = {}
	var _btn: Button
	var _icon: AppIcon
	var _name: Label
	var _sub: Label
	var _cpu: Label
	var _mem: Label
	var _end: Button
	var _shield: TextureRect
	var _details: HBoxContainer
	var _ref := ""
	var _detail_sig := ""

	func _init(f: TasksFlyout) -> void:
		owner_flyout = f
		add_theme_constant_override("separation", 0)
		_btn = Button.new()
		_btn.focus_mode = Control.FOCUS_NONE
		_btn.custom_minimum_size.y = 46
		_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		_btn.add_theme_stylebox_override("normal", Kit.empty())
		_btn.add_theme_stylebox_override("focus", Kit.empty())
		_btn.add_theme_stylebox_override("hover", Kit.box(Color(1, 1, 1, 0.055), 12))
		_btn.add_theme_stylebox_override("pressed", Kit.box(Color(1, 1, 1, 0.08), 12))
		_btn.add_theme_stylebox_override("hover_pressed", Kit.box(Color(1, 1, 1, 0.08), 12))
		_btn.pressed.connect(func() -> void: owner_flyout.toggle_details(str(group.get("key", ""))))
		_btn.gui_input.connect(func(e: InputEvent) -> void:
			if e is InputEventMouseButton and e.pressed and e.double_click and e.button_index == MOUSE_BUTTON_LEFT:
				owner_flyout.switch_to(group)
		)
		add_child(_btn)
		var row := Kit.hbox(10)
		row.add_theme_constant_override("separation", 0)
		row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		row.offset_left = 6
		row.offset_right = -6
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_btn.add_child(row)
		_icon = AppIcon.new()
		_icon.custom_minimum_size = Vector2(28, 28)
		_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(_icon)
		row.add_child(Kit.spacer(10))
		var text := Kit.vbox(0)
		text.alignment = BoxContainer.ALIGNMENT_CENTER
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(text)
		_name = _clip(Kit.label("", 13, 600, App.TEXT))
		text.add_child(_name)
		_sub = _clip(Kit.label("", 11, 500, App.TEXT_MUTE))
		text.add_child(_sub)
		_cpu = Kit.label("", 13, 600, App.TEXT_DIM)
		_cpu.custom_minimum_size.x = TasksFlyout.COL_CPU
		_cpu.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_cpu.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_cpu.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(_cpu)
		_mem = Kit.label("", 13, 500, App.TEXT_DIM)
		_mem.custom_minimum_size.x = TasksFlyout.COL_MEM
		_mem.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_mem.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_mem.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(_mem)
		row.add_child(Kit.spacer(12))
		var act := Control.new()
		act.custom_minimum_size = Vector2(TasksFlyout.COL_ACT, 28)
		act.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		act.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(act)
		_end = Button.new()
		_end.focus_mode = Control.FOCUS_NONE
		_end.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		_end.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_end.add_theme_font_override("font", Kit.font(600))
		_end.add_theme_font_size_override("font_size", 12)
		_end.pressed.connect(func() -> void: owner_flyout.end_group(group))
		act.add_child(_end)
		_shield = Kit.icon_rect("shield", 15, Color(1, 1, 1, 0.3))
		_shield.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_shield.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		_shield.mouse_filter = Control.MOUSE_FILTER_PASS
		_shield.tooltip_text = "Windows needs this to run"
		act.add_child(_shield)
		_details = Kit.hbox(6)
		_details.visible = false
		add_child(_details)

	static func _clip(l: Label) -> Label:
		l.clip_text = true
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return l

	func show_group(g: Dictionary) -> void:
		group = g
		var ref: String = g["ref"] + "|" + str(g["name"])
		if ref != _ref:
			_ref = ref
			_icon.set_item(g["item"])
		_name.text = str(g["name"])
		var state := owner_flyout.state_of(str(g["key"]))
		var cpu := float(g["cpu"])
		_cpu.text = TasksFlyout._pct(cpu)
		_cpu.add_theme_color_override("font_color", App.WARNING if cpu >= 0.25 else (App.TEXT if cpu >= 0.05 else App.TEXT_DIM))
		_mem.text = TasksFlyout._mb(float(g["mem"]))
		var mem := float(g["mem"])
		_mem.add_theme_color_override("font_color", App.WARNING if mem >= 4294967296.0 else (App.TEXT if mem >= 1073741824.0 else App.TEXT_DIM))
		match state:
			&"confirm":
				_sub.text = "Unsaved work may be lost" if g["section"] == "apps" else "Windows may need this. End anyway?"
				_sub.add_theme_color_override("font_color", App.WARNING)
			&"denied":
				_sub.text = "Windows needs admin rights to end this"
				_sub.add_theme_color_override("font_color", App.WARNING)
			_:
				_sub.text = str(g["sub"])
				_sub.add_theme_color_override("font_color", App.TEXT_MUTE)
		_sub.visible = _sub.text != ""
		_shield.visible = g["protected"]
		_end.visible = not g["protected"]
		_style_end(state, g["close_only"])
		modulate.a = 0.45 if state == &"ending" else 1.0
		_sync_details(owner_flyout.is_expanded(str(g["key"])))

	func _style_end(state: StringName, close_only: bool) -> void:
		var red := App.DANGER
		var text := "Close" if close_only else "End"
		var bg := Color(1, 1, 1, 0.05)
		var edge := Color(1, 1, 1, 0.08)
		var hover := Color(red, 0.2)
		var hover_edge := Color(red, 0.45)
		var fg := App.TEXT_DIM
		match state:
			&"confirm":
				text = "Sure?"
				bg = Color(red, 0.85)
				edge = Color(red.lightened(0.2), 0.9)
				hover = Color(red.lightened(0.08), 0.95)
				hover_edge = edge
				fg = Color.WHITE
			&"denied":
				text = "Admin"
				bg = Color(App.WARNING, 0.18)
				edge = Color(App.WARNING, 0.4)
				hover = Color(App.WARNING, 0.28)
				hover_edge = Color(App.WARNING, 0.6)
				fg = App.TEXT
			&"ending":
				text = "…"
		_end.text = text
		_end.disabled = state == &"ending"
		_end.tooltip_text = {
			&"confirm": "Click again to end it",
			&"denied": "Ask Windows for admin rights and end it",
		}.get(state, "Close its windows" if close_only else "End task")
		_end.add_theme_stylebox_override("normal", Kit.box(bg, 999, edge, 1))
		_end.add_theme_stylebox_override("hover", Kit.box(hover, 999, hover_edge, 1))
		_end.add_theme_stylebox_override("pressed", Kit.box(Color(red, 0.4), 999, hover_edge, 1))
		_end.add_theme_stylebox_override("disabled", Kit.box(Color(1, 1, 1, 0.03), 999, Color(1, 1, 1, 0.05), 1))
		_end.add_theme_stylebox_override("focus", Kit.empty())
		_end.add_theme_color_override("font_color", fg)
		_end.add_theme_color_override("font_hover_color", Color.WHITE)
		_end.add_theme_color_override("font_pressed_color", Color.WHITE)
		_end.add_theme_color_override("font_disabled_color", App.TEXT_MUTE)

	func _sync_details(open: bool) -> void:
		var sig := "%s|%d|%s" % [group["key"], group["windows"].size(), group["exe"]] if open else ""
		_details.visible = open
		if sig == _detail_sig:
			return
		_detail_sig = sig
		for c in _details.get_children():
			c.queue_free()
		if not open:
			return
		_details.add_child(Kit.spacer(44))
		if not group["windows"].is_empty():
			var go := owner_flyout._chip("Switch to", "window")
			go.pressed.connect(func() -> void: owner_flyout.switch_to(group))
			_details.add_child(go)
		if str(group["exe"]) != "":
			var file := owner_flyout._chip("File location", "folder")
			file.tooltip_text = str(group["exe"]).replace("/", "\\")
			file.pressed.connect(func() -> void: owner_flyout.show_file(group))
			_details.add_child(file)
		if group["section"] != "apps":
			var what := owner_flyout._chip("What is this?", "search")
			what.pressed.connect(func() -> void: owner_flyout.look_up(group))
			_details.add_child(what)
		_details.add_child(Kit.spacer(0, 36))
