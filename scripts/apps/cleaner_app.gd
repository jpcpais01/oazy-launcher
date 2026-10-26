class_name CleanerApp
extends Control
## The Cleaner window: looks the PC over, shows what's worth changing, applies
## only what you pick and keeps every change ready to undo (see Cleaner).

const ORB := preload("res://shaders/cleaner_orb.gdshader")
const SIDEBAR := 236.0
const PAGES := [
	["overview", "Overview", "sparkles"],
	["apps", "Bloatware", "apps"],
	["startup", "Startup apps", "rocket"],
	["junk", "Junk files", "broom"],
	["perf", "Performance", "bolt"],
	["privacy", "Privacy", "eye_off"],
	["history", "History", "undo"],
]
const TINTS := {
	"apps": Color("ff8a9e"), "startup": Color("ffbf5e"), "junk": Color("7cc7ff"),
	"perf": Color("4fe0a5"), "privacy": Color("b597ff"), "history": Color("9aa6bd"),
}
const HEADINGS := {
	"apps": ["Bloatware", "Apps that came with Windows or snuck in later. Removing one only takes it off your account, and Undo brings it back."],
	"startup": ["Startup apps", "Everything that starts when you sign in. Turning one off doesn't remove it, it just waits until you open it."],
	"junk": ["Junk files", "Leftovers that are safe to clear. Files used in the last day are always kept."],
	"perf": ["Performance", "Settings that make Windows faster and smoother, especially in games."],
	"privacy": ["Privacy", "Settings that stop Windows sharing your data and showing you ads."],
	"history": ["History", "Every cleanup Oazy has made on this PC. Undo puts things back exactly as they were."],
}

var main: Node
var _page := "overview"
var _nav := {}
var _scroll: ScrollContainer
var _page_box: VBoxContainer
var _bar: PanelContainer
var _bar_title: Label
var _bar_sub: Label
var _bar_apply: FxButton
var _bar_restore: ToggleSwitch
var _phase_label: Label
var _syncs: Array[Callable] = []
var _result: Dictionary = {}
var _result_undo: Array = []
var _width := 900.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var root := Kit.hbox(0)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	root.add_child(_build_sidebar())
	var line := ColorRect.new()
	line.color = Color(1, 1, 1, 0.06)
	line.custom_minimum_size.x = 1
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(line)

	var content := Kit.vbox(0)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(content)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(_scroll)
	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right"]:
		pad.add_theme_constant_override("margin_" + side, 40)
	pad.add_theme_constant_override("margin_top", 26)
	pad.add_theme_constant_override("margin_bottom", 30)
	_scroll.add_child(pad)
	_page_box = Kit.vbox(16)
	_page_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_child(_page_box)
	content.add_child(_build_bar())

	resized.connect(func() -> void:
		# Overview's tiles go from three columns to two on narrow windows.
		var w := size.x - SIDEBAR - 81.0
		var changed := (w < 760.0) != (_width < 760.0)
		_width = w
		if changed and _page == "overview":
			_render()
	)
	Cleaner.state_changed.connect(_on_state)
	Cleaner.scanned.connect(func() -> void:
		if _page not in ["busy", "result"]:
			_render()
		_sync_all()
	)
	Cleaner.selection_changed.connect(_sync_all)
	Cleaner.applied.connect(func(run: Dictionary) -> void:
		if run.get("ok", false):
			_result = run
			_result_undo = []
			_page = "result"
		elif _page == "busy":
			_page = "overview"
		_render()
	)
	Cleaner.undone.connect(func(run: Dictionary, results: Array) -> void:
		_result = run
		_result_undo = results
		_page = "result"
		_render()
	)
	_width = 900.0
	if Cleaner.busy() and Cleaner.state != &"scanning":
		_page = "busy"
	_render()
	# Looking is harmless, so the first open starts right away.
	if not Cleaner.has_scan() and not Cleaner.busy() and (not App.smoke_test or App.screenshot_dir != ""):
		Cleaner.start_scan()


func on_shown() -> void:
	_sync_all()


# --- Sidebar ---------------------------------------------------------------------------

func _build_sidebar() -> Control:
	var m := MarginContainer.new()
	m.custom_minimum_size.x = SIDEBAR
	for side in ["left", "right"]:
		m.add_theme_constant_override("margin_" + side, 14)
	m.add_theme_constant_override("margin_top", 18)
	m.add_theme_constant_override("margin_bottom", 18)
	var col := Kit.vbox(4)
	m.add_child(col)
	for spec in PAGES:
		if spec[0] == "history":
			col.add_child(Kit.spacer(0, 10))
		col.add_child(_nav_button(spec[0], spec[1], spec[2]))
	col.add_child(Kit.spacer(0, 0, true))
	col.get_child(col.get_child_count() - 1).size_flags_vertical = Control.SIZE_EXPAND_FILL
	# A promise, always in view.
	var promise := PanelContainer.new()
	promise.add_theme_stylebox_override("panel", Kit.box(Color(1, 1, 1, 0.04), 16, Color(1, 1, 1, 0.06), 1, 14, 14))
	col.add_child(promise)
	var pv := Kit.vbox(6)
	promise.add_child(pv)
	var ph := Kit.hbox(8)
	pv.add_child(ph)
	ph.add_child(Kit.icon_rect("shield", 16, App.SUCCESS))
	ph.add_child(Kit.label("Safe by design", 14, 700, App.TEXT))
	var pt := Kit.label("Nothing changes until you press Apply. Defender, Windows Update and drivers are never touched, and every change can be undone.", 12, 500, App.TEXT_MUTE)
	pt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pv.add_child(pt)
	return m


func _nav_button(id: String, title: String, glyph: String) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size.y = 44
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for s in ["normal", "pressed", "disabled", "focus"]:
		b.add_theme_stylebox_override(s, Kit.empty())
	b.add_theme_stylebox_override("hover", Kit.box(Color(1, 1, 1, 0.05), 12))
	var row := Kit.hbox(12)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 12
	row.offset_right = -10
	b.add_child(row)
	var tint: Color = TINTS.get(id, App.accent)
	var ic := Kit.icon_rect(glyph, 18, tint if id != "overview" else App.accent)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(ic)
	var l := Kit.label(title, 15, 600, App.TEXT_DIM)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var badge := Kit.label("", 12, 700, App.TEXT_MUTE)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.custom_minimum_size = Vector2(26, 22)
	row.add_child(badge)
	b.pressed.connect(func() -> void:
		Sfx.play(&"select")
		_go(id)
	)
	_nav[id] = {"button": b, "label": l, "badge": badge}
	return b


func _sync_nav() -> void:
	var page := _page
	if page == "busy" or page == "result":
		page = "history" if not _result_undo.is_empty() else ""
	for id in _nav.keys():
		var n: Dictionary = _nav[id]
		var on: bool = id == page
		var b: Button = n["button"]
		b.add_theme_stylebox_override("normal", Kit.box(Color(1, 1, 1, 0.085), 12, Color(1, 1, 1, 0.08), 1) if on else Kit.empty())
		var l: Label = n["label"]
		l.add_theme_color_override("font_color", Color.WHITE if on else App.TEXT_DIM)
		var badge: Label = n["badge"]
		var picked := Cleaner.picks_in(id) if id not in ["overview", "history"] else 0
		if picked > 0:
			badge.text = str(picked)
			badge.add_theme_color_override("font_color", Color(0.02, 0.06, 0.08))
			badge.add_theme_stylebox_override("normal", Kit.box(App.accent, 11, Color(0, 0, 0, 0), 1, 7, 1))
		else:
			badge.text = _count_text(id)
			badge.add_theme_color_override("font_color", App.TEXT_MUTE)
			badge.add_theme_stylebox_override("normal", Kit.empty())


func _count_text(id: String) -> String:
	if not Cleaner.has_scan():
		return ""
	match id:
		"apps":
			return str(Cleaner.scan.get("apps", []).size())
		"startup":
			return str(_startup_on())
		"junk":
			return _short_bytes(_junk_total())
		"perf", "privacy":
			var left := _tweaks_left(id)
			return str(left) if left > 0 else ""
		"history":
			return str(Cleaner.history.size()) if not Cleaner.history.is_empty() else ""
	return ""


# --- Action bar ---------------------------------------------------------------------------

func _build_bar() -> Control:
	var m := MarginContainer.new()
	for side in ["left", "right", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 18)
	m.add_theme_constant_override("margin_top", 0)
	_bar = PanelContainer.new()
	var s := Kit.box(Color(1, 1, 1, 0.07), 20, Color(1, 1, 1, 0.1), 1, 20, 14)
	Kit.shadowed(s, Color(0, 0, 0, 0.28), 20, Vector2(0, 8))
	_bar.add_theme_stylebox_override("panel", s)
	m.add_child(_bar)
	var row := Kit.hbox(16)
	_bar.add_child(row)
	var text := Kit.vbox(2)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(text)
	_bar_title = Kit.label("", 16, 700, Color.WHITE)
	text.add_child(_bar_title)
	_bar_sub = Kit.label("", 13, 500, App.TEXT_MUTE)
	_bar_sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	text.add_child(_bar_sub)
	var rp := Kit.hbox(10)
	rp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(rp)
	var rl := Kit.label("Restore point first", 13, 600, App.TEXT_DIM)
	rl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rp.add_child(rl)
	_bar_restore = ToggleSwitch.new()
	_bar_restore.tooltip_text = "A Windows restore point is a second safety net on top of Oazy's own undo."
	_bar_restore.set_on(Cleaner.restore_point)
	_bar_restore.toggled.connect(func(on: bool) -> void:
		Cleaner.restore_point = on
		_sync_bar()
	)
	rp.add_child(_bar_restore)
	_bar_apply = FxButton.make("Apply", "check", FxButton.Style.PRIMARY, 46)
	_bar_apply.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_bar_apply.pressed.connect(func() -> void: Cleaner.apply_picks())
	row.add_child(_bar_apply)
	return m


func _sync_bar() -> void:
	var show := Cleaner.has_scan() and _page not in ["busy", "result", "history"]
	_bar.get_parent().visible = show
	if not show:
		return
	var n := Cleaner.picks.size()
	var free := Cleaner.bytes_picked()
	if n == 0:
		_bar_title.text = "Pick what to change"
		_bar_sub.text = "Recommended picks are ticked for you. Tap any row to change it."
	else:
		_bar_title.text = "%d change%s picked" % [n, "" if n == 1 else "s"]
		var parts := PackedStringArray()
		if free > 0:
			parts.append("Frees %s" % Fmt.bytes(free))
		if Cleaner.needs_admin():
			parts.append("Windows asks once")
		parts.append("Undo any time")
		_bar_sub.text = "  ·  ".join(parts)
	_bar_apply.text = "Apply" if n == 0 else "Apply %d" % n
	_bar_apply.disabled = n == 0 or Cleaner.busy()


func _sync_all() -> void:
	for s in _syncs:
		if s.is_valid():
			s.call()
	_sync_nav()
	_sync_bar()


func _on_state() -> void:
	if Cleaner.state in [&"applying", &"undoing"]:
		if _page != "busy":
			_page = "busy"
			_render()
		elif _phase_label:
			_phase_label.text = Cleaner.phase
	elif Cleaner.state == &"scanning" and _page == "overview":
		_render()
	_sync_bar()


# --- Pages ---------------------------------------------------------------------------------

func _go(id: String) -> void:
	if _page == "busy":
		return
	_page = id
	_scroll.scroll_vertical = 0
	_render()


func _render() -> void:
	_syncs.clear()
	_phase_label = null
	for c in _page_box.get_children():
		c.queue_free()
	match _page:
		"overview":
			_render_overview()
		"busy":
			_render_busy()
		"result":
			_render_result()
		"history":
			_render_history()
		"apps":
			_render_apps()
		"startup":
			_render_startup()
		"junk":
			_render_junk()
		"perf", "privacy":
			_render_tweaks(_page)
	_page_box.modulate.a = 0.0
	Kit.ease_tween(_page_box).tween_property(_page_box, "modulate:a", 1.0, 0.3)
	_sync_all()


func _orb(px: float, level: float, scanning: bool, calm: bool = false) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(px, px)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var rect := ColorRect.new()
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = ORB
	mat.set_shader_parameter("color_a", App.accent)
	mat.set_shader_parameter("color_b", App.accent_pair(App.accent))
	mat.set_shader_parameter("scanning", 1.0 if scanning else 0.0)
	mat.set_shader_parameter("calm", 1.0 if calm or Settings.get_value("effects") == "eco" else 0.0)
	mat.set_shader_parameter("level", 0.0)
	rect.material = mat
	holder.add_child(rect)
	# The water rises to its level.
	var t := holder.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_method(func(v: float) -> void: mat.set_shader_parameter("level", v), 0.0, level, 1.4)
	return holder


func _render_overview() -> void:
	var scanning := Cleaner.state == &"scanning"
	var has := Cleaner.has_scan()
	var hero := Kit.hbox(34)
	_page_box.add_child(hero)
	var level := 0.5 if not has else Cleaner.health() / 100.0
	hero.add_child(_orb(236.0, level, scanning or not has))
	var text := Kit.vbox(10)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	hero.add_child(text)
	var eyebrow := "YOUR PC"
	var title := ""
	var sub := ""
	var todo := _todo()
	if scanning:
		eyebrow = "SCANNING"
		title = "Looking around…"
		sub = "Checking apps, startup, files and settings. Looking never changes anything."
	elif not has:
		title = "Let's tidy up Windows"
		sub = "Oazy finds apps you never asked for, startup apps that slow you down, junk files and settings that share your data. Nothing changes until you say so."
	elif todo == 0:
		eyebrow = "HEALTH %d" % int(Cleaner.health())
		title = "Your PC is in great shape"
		sub = "Everything Oazy recommends is done. There's still more you can pick in each section."
	else:
		eyebrow = "HEALTH %d" % int(Cleaner.health())
		title = "%d thing%s worth tidying" % [todo, "" if todo == 1 else "s"]
		var parts := PackedStringArray()
		var apps := _rec_apps()
		if apps > 0:
			parts.append("%d app%s you didn't ask for" % [apps, "" if apps == 1 else "s"])
		var j := _junk_total()
		if j > 0:
			parts.append("%s of junk" % Fmt.bytes(j))
		var tw := _tweaks_left("perf", true) + _tweaks_left("privacy", true)
		if tw > 0:
			parts.append("%d setting%s to fix" % [tw, "" if tw == 1 else "s"])
		var st := _startup_hinted()
		if st > 0:
			parts.append("%d startup app%s that can wait" % [st, "" if st == 1 else "s"])
		sub = _sentence(parts) + "."
	text.add_child(Kit.label(eyebrow, 13, 700, App.accent))
	var tl := Kit.label(title, 40, 800, Color.WHITE, true)
	tl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_child(tl)
	var sl := Kit.label(sub, 16, 500, App.TEXT_DIM)
	sl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_child(sl)
	if not scanning:
		var buttons := Kit.hbox(10)
		text.add_child(Kit.spacer(0, 4))
		text.add_child(buttons)
		if not has:
			var go := FxButton.make("Scan my PC", "search", FxButton.Style.PRIMARY, 48)
			go.pressed.connect(func() -> void: Cleaner.start_scan())
			buttons.add_child(go)
		else:
			if todo > 0:
				var review := FxButton.make("Review picks", "chevron_right", FxButton.Style.PRIMARY, 46)
				review.pressed.connect(func() -> void: _go(_first_with_picks()))
				buttons.add_child(review)
			var again := FxButton.make("Scan again", "refresh", FxButton.Style.GHOST, 46)
			again.pressed.connect(func() -> void: Cleaner.start_scan())
			buttons.add_child(again)

	if not Cleaner.came_back.is_empty():
		var warn := PanelContainer.new()
		warn.add_theme_stylebox_override("panel", Kit.box(Color(App.WARNING, 0.1), 18, Color(App.WARNING, 0.3), 1, 20, 14))
		_page_box.add_child(warn)
		var wr := Kit.hbox(12)
		warn.add_child(wr)
		wr.add_child(Kit.icon_rect("alert", 18, App.WARNING))
		var names := Cleaner.came_back.slice(0, 4)
		var more := Cleaner.came_back.size() - names.size()
		var wl := Kit.label("Windows brought back %s%s. They're picked again below." % [_sentence(PackedStringArray(names)), " and %d more" % more if more > 0 else ""], 14, 600, App.TEXT)
		wl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		wl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		wr.add_child(wl)

	_page_box.add_child(Kit.spacer(0, 6))
	var grid := GridContainer.new()
	grid.columns = 3 if _width >= 760.0 else 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	_page_box.add_child(grid)
	for spec in PAGES:
		if spec[0] != "overview":
			grid.add_child(_tile(spec[0], spec[1], spec[2]))

	_page_box.add_child(Kit.spacer(0, 4))
	var watch := PanelContainer.new()
	watch.add_theme_stylebox_override("panel", Kit.box(Color(1, 1, 1, 0.04), 18, Color(1, 1, 1, 0.06), 1, 20, 14))
	_page_box.add_child(watch)
	var wrow := Kit.hbox(14)
	watch.add_child(wrow)
	var wic := _glyph_tile("shield", App.SUCCESS, 40)
	wrow.add_child(wic)
	var wt := Kit.vbox(2)
	wt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wt.alignment = BoxContainer.ALIGNMENT_CENTER
	wrow.add_child(wt)
	wt.add_child(Kit.label("Keep watch", 16, 600, App.TEXT))
	var wd := Kit.label("A couple of minutes after Oazy starts, it quietly checks whether Windows brought anything back, and tells you.", 13, 500, App.TEXT_MUTE)
	wd.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	wt.add_child(wd)
	var sw := ToggleSwitch.new()
	sw.set_on(bool(Settings.get_value("cleaner_watch")))
	sw.toggled.connect(func(on: bool) -> void: Settings.set_value("cleaner_watch", on))
	wrow.add_child(sw)


func _tile(id: String, title: String, glyph: String) -> Control:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_ALL
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size.y = 150
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var tint: Color = TINTS[id]
	b.add_theme_stylebox_override("normal", Kit.box(Color(1, 1, 1, 0.045), 20, Color(1, 1, 1, 0.07), 1))
	b.add_theme_stylebox_override("hover", Kit.box(Color(tint, 0.09), 20, Color(tint, 0.35), 1))
	b.add_theme_stylebox_override("pressed", Kit.box(Color(tint, 0.14), 20, Color(tint, 0.45), 1))
	b.add_theme_stylebox_override("focus", Kit.box(Color(0, 0, 0, 0), 20, Color(1, 1, 1, 0.8), 2))
	b.disabled = not Cleaner.has_scan() and id != "history"
	b.pressed.connect(func() -> void:
		Sfx.play(&"select")
		_go(id)
	)
	var col := Kit.vbox(4)
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 20
	col.offset_top = 18
	col.offset_right = -18
	col.offset_bottom = -16
	b.add_child(col)
	var top := Kit.hbox(8)
	col.add_child(top)
	top.add_child(_glyph_tile(glyph, tint, 38))
	top.add_child(Kit.spacer(0, 0, true))
	var picked := Cleaner.picks_in(id)
	if picked > 0:
		var chip := Kit.label("%d picked" % picked, 12, 700, tint)
		chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		chip.add_theme_stylebox_override("normal", Kit.box(Color(tint, 0.14), 10, Color(0, 0, 0, 0), 1, 8, 2))
		top.add_child(chip)
	col.add_child(Kit.spacer(0, 0, true))
	col.get_child(col.get_child_count() - 1).size_flags_vertical = Control.SIZE_EXPAND_FILL
	var big := "—"
	var cap := ""
	if Cleaner.has_scan() or id == "history":
		match id:
			"apps":
				var n: int = Cleaner.scan.get("apps", []).size()
				big = str(n)
				cap = "apps you didn't ask for" if n != 1 else "app you didn't ask for"
			"startup":
				big = str(_startup_on())
				cap = "start with Windows"
			"junk":
				big = Fmt.bytes(_junk_total())
				cap = "of junk files"
			"perf", "privacy":
				var left := _tweaks_left(id)
				big = str(left)
				cap = ("speed-up" if id == "perf" else "privacy fix") + ("" if left == 1 else "s") + " to make"
				if left == 0:
					big = "All set"
					cap = "nothing left to change"
			"history":
				big = str(Cleaner.history.size())
				cap = "cleanups you can undo" if Cleaner.history.size() != 1 else "cleanup you can undo"
	var bl := Kit.label(big, 28, 800, Color.WHITE, true)
	col.add_child(bl)
	var row := Kit.hbox(6)
	col.add_child(row)
	var tl := Kit.label(title, 14, 700, App.TEXT_DIM)
	row.add_child(tl)
	if cap != "":
		var cl := Kit.label("·  " + cap, 13, 500, App.TEXT_MUTE)
		cl.clip_text = true
		cl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		cl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(cl)
	return b


func _render_busy() -> void:
	var undoing := Cleaner.state == &"undoing"
	_page_box.add_child(Kit.spacer(0, 40))
	var center := Kit.vbox(14)
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	_page_box.add_child(center)
	var orb_row := Kit.hbox(0)
	orb_row.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(orb_row)
	orb_row.add_child(_orb(260.0, 0.55, true))
	var t := Kit.label("Putting things back" if undoing else "Applying your picks", 34, 800, Color.WHITE, true)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(t)
	_phase_label = Kit.label(Cleaner.phase, 16, 500, App.TEXT_DIM)
	_phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(_phase_label)
	var hint := Kit.label("You can keep using your PC while this runs.", 13, 500, App.TEXT_MUTE)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(hint)


func _render_result() -> void:
	var undo: bool = not _result_undo.is_empty() or (_result.get("undone", false) and _result.has("undo_results"))
	var entries: Array = _result_undo if undo else _result.get("entries", [])
	var good := 0
	var bad := 0
	for e in entries:
		if e.get("ok", false):
			good += 1
		else:
			bad += 1
	var hero := Kit.hbox(30)
	_page_box.add_child(hero)
	hero.add_child(_orb(180.0, 1.0 if bad == 0 else 0.8, false, true))
	var text := Kit.vbox(8)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	hero.add_child(text)
	var eyebrow := Kit.label(Fmt.ago(int(_result.get("time", 0))).to_upper(), 13, 700, App.accent)
	text.add_child(eyebrow)
	var title := ""
	if undo:
		title = "Put back" if bad == 0 else "Mostly put back"
	else:
		title = "All done" if bad == 0 else "Done, %d skipped" % bad
	text.add_child(Kit.label(title, 40, 800, Color.WHITE, true))
	var parts := PackedStringArray()
	parts.append("%d change%s %s" % [good, "" if good == 1 else "s", "undone" if undo else "made"])
	var freed := int(_result.get("freed", 0))
	if not undo and freed > 0:
		parts.append("%s freed" % Fmt.bytes(freed))
	var sub := Kit.label("  ·  ".join(parts), 16, 500, App.TEXT_DIM)
	text.add_child(sub)
	var restore: Dictionary = _result.get("restore", {})
	if not undo and restore.get("tried", false):
		var rr := Kit.hbox(8)
		text.add_child(rr)
		rr.add_child(Kit.icon_rect("shield" if restore.get("ok", false) else "info", 15, App.SUCCESS if restore.get("ok", false) else App.WARNING))
		var rl := Kit.label("Windows restore point made first" if restore.get("ok", false) else str(restore.get("msg", "")), 13, 600, App.TEXT_MUTE)
		rl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rr.add_child(rl)
	var buttons := Kit.hbox(10)
	text.add_child(Kit.spacer(0, 4))
	text.add_child(buttons)
	var done := FxButton.make("Done", "check", FxButton.Style.PRIMARY, 46)
	done.pressed.connect(func() -> void: _go("overview"))
	buttons.add_child(done)
	var run_id := str(_result.get("id", ""))
	var live := Cleaner.run_by_id(run_id)
	if not undo and not live.is_empty() and not live.get("undone", false) and Cleaner.undoable(live) > 0:
		var ub := FxButton.make("Undo these changes", "undo", FxButton.Style.GHOST, 46)
		ub.pressed.connect(func() -> void: Cleaner.undo_run(run_id))
		buttons.add_child(ub)

	_page_box.add_child(Kit.spacer(0, 8))
	var list := _card()
	for e in entries:
		_result_row(list, e, undo)
	if entries.is_empty():
		_empty(list, "Nothing needed changing.")


func _result_row(list: VBoxContainer, e: Dictionary, undo: bool) -> void:
	var ok: bool = e.get("ok", false)
	var row := _plain_row(list)
	var ic := Kit.icon_rect("check" if ok else "alert", 18, App.SUCCESS if ok else App.WARNING)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(ic)
	var text := Kit.vbox(2)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(text)
	text.add_child(Kit.label(str(e.get("label", "")), 15, 600, App.TEXT))
	var msg := str(e.get("msg", ""))
	if not undo and ok:
		match str(e.get("kind", "")):
			"app":
				msg = "Removed"
			"tweak":
				msg = "Changed"
			"startup":
				msg = "Startup changed"
			"junk":
				msg = "%s freed · can't be undone" % Fmt.bytes(int(e.get("freed", 0)))
	elif undo and ok:
		msg = "Back as it was"
	if msg != "":
		var ml := Kit.label(msg, 13, 500, App.TEXT_MUTE)
		ml.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.add_child(ml)
	var store := str(e.get("store", ""))
	if store != "":
		var sb := FxButton.make("Microsoft Store", "external", FxButton.Style.GHOST, 38)
		sb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		sb.pressed.connect(func() -> void: OS.shell_open(store))
		row.add_child(sb)


func _render_history() -> void:
	_heading("history")
	var list := _card()
	if Cleaner.history.is_empty():
		_empty(list, "Nothing yet. Everything you change shows up here, ready to undo.")
		return
	for run in Cleaner.history:
		var r: Dictionary = run
		var row := _plain_row(list, true)
		row.get_parent().pressed.connect(func() -> void:
			_result = r
			_result_undo = r.get("undo_results", []) if r.get("undone", false) else []
			_page = "result"
			_render()
		)
		row.add_child(_glyph_tile("clock", TINTS["history"], 40))
		var text := Kit.vbox(2)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_child(text)
		var n: int = r.get("entries", []).size()
		text.add_child(Kit.label("%s  ·  %d change%s" % [Fmt.ago(int(r.get("time", 0))), n, "" if n == 1 else "s"], 16, 600, App.TEXT))
		var parts := PackedStringArray()
		var names := PackedStringArray()
		for e in r.get("entries", []):
			if names.size() < 3:
				names.append(str(e.get("label", "")))
		parts.append(", ".join(names) + ("…" if n > 3 else ""))
		if int(r.get("freed", 0)) > 0:
			parts.append("%s freed" % Fmt.bytes(int(r["freed"])))
		var dl := Kit.label("  ·  ".join(parts), 13, 500, App.TEXT_MUTE)
		dl.clip_text = true
		dl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		text.add_child(dl)
		if r.get("undone", false):
			row.add_child(_chip("Undone", App.TEXT_MUTE))
		elif Cleaner.undoable(r) == 0:
			row.add_child(_chip("Nothing to undo", App.TEXT_MUTE))
		else:
			var ub := FxButton.make("Undo", "undo", FxButton.Style.GHOST, 38)
			ub.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			ub.disabled = Cleaner.busy()
			ub.pressed.connect(func() -> void: Cleaner.undo_run(str(r["id"])))
			row.add_child(ub)


func _render_apps() -> void:
	_heading("apps", true)
	var keep: Array = []
	for t in Cleaner.scan.get("tweaks", []):
		if t["group"] == "apps":
			keep.append(t)
	if not keep.is_empty():
		_section_label("KEEP IT THAT WAY")
		var kl := _card()
		for t in keep:
			_tweak_row(kl, t)
	var apps: Array = Cleaner.scan.get("apps", []).duplicate()
	apps.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["rec"] != b["rec"]:
			return a["rec"]
		return str(a["name"]).naturalnocasecmp_to(str(b["name"])) < 0
	)
	_section_label("FOUND ON THIS PC")
	var list := _card()
	if apps.is_empty():
		_empty(list, "No bloatware found. Nice and clean.")
	for a in apps:
		var app: Dictionary = a
		var key := "app:" + str(app["pkg"])
		var chips: Array = []
		if app["rec"]:
			chips.append(["Recommended", App.accent])
		var icon := AppIcon.new()
		icon.custom_minimum_size = Vector2(40, 40)
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		icon.set_item({"kind": "app", "name": app["name"], "icon_key": ("shell:AppsFolder\\" + str(app["aumid"])) if str(app["aumid"]) != "" else ""})
		_pick_row(list, key, icon, str(app["name"]), str(app["desc"]), chips, "")


func _render_startup() -> void:
	_heading("startup")
	var rows: Array = Cleaner.scan.get("startup", []).duplicate()
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["protected"] != b["protected"]:
			return not a["protected"]
		if (str(a["hint"]) != "") != (str(b["hint"]) != ""):
			return str(a["hint"]) != ""
		return str(a["name"]).naturalnocasecmp_to(str(b["name"])) < 0
	)
	var list := _card()
	if rows.is_empty():
		_empty(list, "Nothing starts with Windows. Sign-in is as quick as it gets.")
	for s in rows:
		_startup_row(list, s)


func _render_junk() -> void:
	_heading("junk", true)
	var list := _card()
	for j in Cleaner.scan.get("junk", []):
		var item: Dictionary = j
		var size := int(item["size"])
		var busy := str(item.get("busy", ""))
		var meta := Fmt.bytes(size) if size >= 0 else "Measured when cleaned"
		var desc := str(item["desc"])
		var chips: Array = []
		if item["rec"]:
			chips.append(["Recommended", App.accent])
		if item.get("admin", false):
			chips.append(["Admin", App.TEXT_DIM])
		var off := size == 0 or busy != ""
		if busy != "":
			desc = "Close %s to clean this. " % busy.capitalize() + desc
			meta = Fmt.bytes(size) if size > 0 else ""
		elif size == 0:
			meta = "Already clean"
		_pick_row(list, "junk:" + str(item["id"]), _glyph_tile(str(item["icon"]), TINTS["junk"], 40), str(item["name"]), desc, chips, meta, off)


func _render_tweaks(group: String) -> void:
	_heading(group, true)
	var list := _card()
	var rows: Array = []
	for t in Cleaner.scan.get("tweaks", []):
		if t["group"] == group:
			rows.append(t)
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["done"] != b["done"]:
			return not a["done"]
		return a["rec"] and not b["rec"]
	)
	for t in rows:
		_tweak_row(list, t)


func _tweak_row(list: VBoxContainer, t: Dictionary) -> void:
	var chips: Array = []
	if t["done"]:
		chips.append(["Already on", App.SUCCESS])
	else:
		if t["rec"]:
			chips.append(["Recommended", App.accent])
		if t.get("admin", false):
			chips.append(["Admin", App.TEXT_DIM])
	var tint: Color = TINTS.get(str(t["group"]), App.accent)
	_pick_row(list, "tweak:" + str(t["id"]), _glyph_tile(str(t["icon"]), tint, 40), str(t["name"]), str(t["desc"]), chips, "", t["done"])


# --- Building blocks --------------------------------------------------------------------------

func _heading(id: String, picks: bool = false) -> void:
	var h: Array = HEADINGS[id]
	var row := Kit.hbox(16)
	_page_box.add_child(row)
	var text := Kit.vbox(6)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)
	var top := Kit.hbox(12)
	text.add_child(top)
	top.add_child(_glyph_tile(_glyph_of(id), TINTS[id], 40))
	var tl := Kit.label(h[0], 30, 800, Color.WHITE, true)
	tl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(tl)
	var d := Kit.label(h[1], 15, 500, App.TEXT_DIM)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_child(d)
	if picks and Cleaner.has_scan():
		var chips := Kit.hbox(8)
		chips.size_flags_vertical = Control.SIZE_SHRINK_END
		row.add_child(chips)
		var rec := FxButton.make("Recommended", "sparkles", FxButton.Style.CHIP, 36)
		rec.add_theme_font_size_override("font_size", 13)
		rec.pressed.connect(func() -> void: _pick_group(id, true))
		chips.add_child(rec)
		var none := FxButton.make("None", "", FxButton.Style.CHIP, 36)
		none.add_theme_font_size_override("font_size", 13)
		none.pressed.connect(func() -> void: _pick_group(id, false))
		chips.add_child(none)
	_page_box.add_child(Kit.spacer(0, 2))


func _glyph_of(id: String) -> String:
	for spec in PAGES:
		if spec[0] == id:
			return spec[2]
	return "dot"


## Ticks a section's recommended picks (or clears the section).
func _pick_group(id: String, rec: bool) -> void:
	var keys: Array[String] = []
	var wanted := {}
	if id == "apps":
		for a in Cleaner.scan.get("apps", []):
			keys.append("app:" + str(a["pkg"]))
			wanted["app:" + str(a["pkg"])] = a["rec"]
	if id == "junk":
		for j in Cleaner.scan.get("junk", []):
			keys.append("junk:" + str(j["id"]))
			wanted["junk:" + str(j["id"])] = j["rec"] and int(j["size"]) != 0 and str(j.get("busy", "")) == ""
	for t in Cleaner.scan.get("tweaks", []):
		if t["group"] == id or (id == "apps" and t["group"] == "apps"):
			keys.append("tweak:" + str(t["id"]))
			wanted["tweak:" + str(t["id"])] = t["rec"] and not t["done"]
	for k in keys:
		if rec and wanted[k]:
			Cleaner.picks[k] = true
		else:
			Cleaner.picks.erase(k)
	Cleaner.selection_changed.emit()


func _card() -> VBoxContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", Kit.box(Color(1, 1, 1, 0.04), 20, Color(1, 1, 1, 0.07), 1, 8, 6))
	_page_box.add_child(card)
	var list := Kit.vbox(0)
	card.add_child(list)
	return list


func _section_label(text: String) -> void:
	_page_box.add_child(Kit.spacer(0, 2))
	_page_box.add_child(Kit.label(text, 12, 700, App.TEXT_MUTE))


func _empty(list: VBoxContainer, text: String) -> void:
	var l := Kit.label(text, 15, 500, App.TEXT_MUTE)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.custom_minimum_size.y = 90
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	list.add_child(l)


func _divider(list: VBoxContainer) -> void:
	if list.get_child_count() == 0:
		return
	var line := ColorRect.new()
	line.color = Color(1, 1, 1, 0.055)
	line.custom_minimum_size.y = 1
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 16)
	m.add_theme_constant_override("margin_right", 16)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(line)
	list.add_child(m)


## A row inside a list card; with `clickable` it sits on a flat button.
func _plain_row(list: VBoxContainer, clickable: bool = false) -> HBoxContainer:
	_divider(list)
	var row := Kit.hbox(14)
	if clickable:
		var b := _row_button()
		list.add_child(b)
		_fill(b, row)
	else:
		var m := MarginContainer.new()
		m.add_theme_constant_override("margin_left", 16)
		m.add_theme_constant_override("margin_right", 16)
		m.add_theme_constant_override("margin_top", 12)
		m.add_theme_constant_override("margin_bottom", 12)
		m.mouse_filter = Control.MOUSE_FILTER_IGNORE
		list.add_child(m)
		m.add_child(row)
	return row


func _row_button() -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_ALL
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.custom_minimum_size.y = 72
	b.add_theme_stylebox_override("normal", Kit.empty())
	b.add_theme_stylebox_override("disabled", Kit.empty())
	b.add_theme_stylebox_override("hover", Kit.box(Color(1, 1, 1, 0.045), 14))
	b.add_theme_stylebox_override("pressed", Kit.box(Color(1, 1, 1, 0.07), 14))
	b.add_theme_stylebox_override("focus", Kit.box(Color(0, 0, 0, 0), 14, Color(1, 1, 1, 0.7), 2))
	return b


## Puts `row` inside button `b` and keeps the button as tall as the row.
func _fill(b: Button, row: HBoxContainer) -> void:
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 16
	row.offset_right = -16
	row.offset_top = 12
	row.offset_bottom = -12
	b.add_child(row)
	row.minimum_size_changed.connect(func() -> void: b.custom_minimum_size.y = maxf(72.0, row.get_combined_minimum_size().y + 24.0))
	b.custom_minimum_size.y = maxf(72.0, row.get_combined_minimum_size().y + 24.0)


## A row you tick: check circle, icon, text, chips and an optional size.
func _pick_row(list: VBoxContainer, key: String, icon: Control, title: String, desc: String, chips: Array, meta: String, off: bool = false) -> void:
	_divider(list)
	var b := _row_button()
	b.disabled = off
	b.mouse_default_cursor_shape = Control.CURSOR_ARROW if off else Control.CURSOR_POINTING_HAND
	list.add_child(b)
	var row := Kit.hbox(14)
	var check := Check.new()
	check.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	check.done = off and chips.size() > 0 and chips[0][0] == "Already on"
	row.add_child(check)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if off:
		icon.modulate.a = 0.55
	row.add_child(icon)
	var text := Kit.vbox(3)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(text)
	var tr := Kit.hbox(8)
	text.add_child(tr)
	tr.add_child(Kit.label(title, 16, 600, App.TEXT if not off else App.TEXT_DIM))
	for c in chips:
		tr.add_child(_chip(c[0], c[1]))
	if desc != "":
		var d := Kit.label(desc, 13, 500, App.TEXT_MUTE)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.add_child(d)
	if meta != "":
		var ml := Kit.label(meta, 14, 700, App.TEXT_DIM)
		ml.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(ml)
	_fill(b, row)
	if off:
		return
	b.pressed.connect(func() -> void:
		Sfx.play(&"toggle", 1.1 if not Cleaner.is_picked(key) else 0.9)
		Cleaner.set_pick(key, not Cleaner.is_picked(key))
	)
	var sync := func() -> void:
		var on := Cleaner.is_picked(key)
		check.set_on(on)
		b.add_theme_stylebox_override("normal", Kit.box(Color(App.accent, 0.06), 14) if on else Kit.empty())
	sync.call()
	_syncs.append(sync)


func _startup_row(list: VBoxContainer, s: Dictionary) -> void:
	_divider(list)
	var locked: bool = s["protected"]
	var b := _row_button()
	b.disabled = locked
	b.mouse_default_cursor_shape = Control.CURSOR_ARROW if locked else Control.CURSOR_POINTING_HAND
	list.add_child(b)
	var row := Kit.hbox(14)
	var icon := AppIcon.new()
	icon.custom_minimum_size = Vector2(40, 40)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.set_item({"kind": "app", "name": s["name"], "icon_key": str(s.get("exe", "")).replace("/", "\\")})
	row.add_child(icon)
	var text := Kit.vbox(3)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(text)
	var tr := Kit.hbox(8)
	text.add_child(tr)
	tr.add_child(Kit.label(str(s["name"]), 16, 600, App.TEXT if not locked else App.TEXT_DIM))
	var change := _chip("", App.accent)
	change.visible = false
	tr.add_child(change)
	if s.get("admin", false) and not locked:
		tr.add_child(_chip("Admin", App.TEXT_DIM))
	var pub := str(s.get("publisher", ""))
	var hint := str(s.get("hint", ""))
	var desc := pub
	if locked:
		desc = "Windows needs this one" + ("  ·  " + pub if pub != "" else "")
	if desc != "":
		text.add_child(Kit.label(desc, 13, 500, App.TEXT_MUTE))
	if hint != "" and not locked:
		var hl := Kit.label(hint, 13, 600, Color(TINTS["startup"], 0.9))
		hl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.add_child(hl)
	if locked:
		var lk := Kit.icon_rect("lock", 18, App.TEXT_MUTE)
		lk.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(lk)
		_fill(b, row)
		return
	var sw := ToggleSwitch.new()
	sw.focus_mode = Control.FOCUS_NONE
	sw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(sw)
	_fill(b, row)
	b.pressed.connect(func() -> void: Cleaner.want_startup(s, not Cleaner.startup_wanted(s)))
	var sync := func() -> void:
		var want := Cleaner.startup_wanted(s)
		if sw.button_pressed != want:
			sw.set_pressed_no_signal(want)
			sw._on_toggled(want)
		var changed := want != bool(s["enabled"])
		change.visible = changed
		change.text = "Turns on" if want else "Turns off"
		b.add_theme_stylebox_override("normal", Kit.box(Color(App.accent, 0.06), 14) if changed else Kit.empty())
	sw.set_on(Cleaner.startup_wanted(s))
	sync.call()
	_syncs.append(sync)


func _chip(text: String, color: Color) -> Label:
	var l := Kit.label(text, 11, 700, color)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	l.add_theme_stylebox_override("normal", Kit.box(Color(color, 0.13), 9, Color(0, 0, 0, 0), 1, 7, 1))
	return l


func _glyph_tile(glyph: String, tint: Color, px: float) -> Control:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(px, px)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var s := Kit.box(Color(tint, 0.16), int(px * 0.32), Color(tint, 0.28), 1)
	p.add_theme_stylebox_override("panel", s)
	var ic := Kit.icon_rect(glyph, int(px * 0.5), tint.lightened(0.15))
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.add_child(ic)
	return p


# --- Numbers ----------------------------------------------------------------------------------

func _todo() -> int:
	return _rec_apps() + _tweaks_left("perf", true) + _tweaks_left("privacy", true) + _tweaks_left("apps", true) + _startup_hinted() + (1 if _junk_total() > 100 * 1048576 else 0)


func _rec_apps() -> int:
	var n := 0
	for a in Cleaner.scan.get("apps", []):
		if a["rec"]:
			n += 1
	return n


func _tweaks_left(group: String, rec_only: bool = false) -> int:
	var n := 0
	for t in Cleaner.scan.get("tweaks", []):
		if t["group"] == group and not t["done"] and (t["rec"] or not rec_only):
			n += 1
	return n


func _startup_on() -> int:
	var n := 0
	for s in Cleaner.scan.get("startup", []):
		if s["enabled"]:
			n += 1
	return n


func _startup_hinted() -> int:
	var n := 0
	for s in Cleaner.scan.get("startup", []):
		if s["enabled"] and not s["protected"] and str(s["hint"]) != "":
			n += 1
	return n


func _junk_total() -> int:
	var n := 0
	for j in Cleaner.scan.get("junk", []):
		n += maxi(0, int(j["size"]))
	return n


func _first_with_picks() -> String:
	for id in ["apps", "startup", "junk", "perf", "privacy"]:
		if Cleaner.picks_in(id) > 0:
			return id
	return "apps"


static func _short_bytes(n: int) -> String:
	if n <= 0:
		return ""
	if n < 1073741824:
		return "%d MB" % maxi(1, n / 1048576)
	return "%.1f GB" % (n / 1073741824.0)


static func _sentence(parts: PackedStringArray) -> String:
	if parts.size() <= 1:
		return "".join(parts)
	return ", ".join(parts.slice(0, parts.size() - 1)) + " and " + parts[parts.size() - 1]


## The round tick on pickable rows; `done` shows a calm green check instead.
class Check extends Control:
	var done := false
	var _t := 0.0
	var _tween: Tween

	func _init() -> void:
		custom_minimum_size = Vector2(26, 26)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_on(on: bool) -> void:
		var target := 1.0 if on else 0.0
		if is_equal_approx(target, _t):
			return
		if _tween and _tween.is_valid():
			_tween.kill()
		if not is_inside_tree():
			_t = target
			queue_redraw()
			return
		_tween = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_tween.tween_method(func(v: float) -> void:
			_t = v
			queue_redraw()
		, _t, target, 0.26)

	func _draw() -> void:
		var c := size / 2.0
		var r := 11.0
		if done:
			draw_circle(c, r, Color(App.SUCCESS, 0.16))
			_tick(c, Color(App.SUCCESS, 0.95), 1.0)
			return
		draw_arc(c, r - 0.75, 0.0, TAU, 40, Color(1, 1, 1, lerpf(0.28, 0.0, clampf(_t, 0.0, 1.0))), 1.5, true)
		if _t > 0.01:
			draw_circle(c, r * clampf(_t, 0.0, 1.15), App.accent)
			_tick(c, Color(0.02, 0.07, 0.09, clampf(_t, 0.0, 1.0)), clampf(_t, 0.0, 1.0))

	func _tick(c: Vector2, col: Color, k: float) -> void:
		var pts := PackedVector2Array([c + Vector2(-4.6, 0.2) * k, c + Vector2(-1.4, 3.4) * k, c + Vector2(4.8, -3.4) * k])
		draw_polyline(pts, col, 2.2, true)
