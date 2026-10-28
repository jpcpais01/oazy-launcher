class_name SettingsApp
extends Control
## The Settings window: a sidebar of sections, each a page of calm cards, and a
## search that looks through every setting at once.

const SIDEBAR := 248.0
const SIDEBAR_COMPACT := 76.0
const COLUMN := 760.0
const PAGES := [
	["account", "Account", "user", "Your Google account: your Oazy profile, and one sign-in for Oazy Browser, Flow and your other web apps."],
	["personalise", "Personalise", "palette", "Colours, wallpaper, pointer, icons and sounds."],
	["desktop", "Desktop & taskbar", "desktop", "How Oazy sits on your PC, its shortcuts and the desktop's cards."],
	["apps", "Apps & library", "grid", "Your games and apps, where they come from and how they launch."],
	["browser", "Browser & files", "globe", "Oazy's own browser, terminal and file explorer, and what opens in them."],
	["network", "Network", "wifi", "Wi-Fi, cable and the internet."],
	["performance", "Performance", "bolt", "Effects, frame rate and keeping Windows tidy."],
	["updates", "Updates", "download", "New versions of Oazy, straight from GitHub."],
	["about", "About", "info", "Oazy, your data and the people behind the parts."],
]

var main: Node
var _page := "account"
var _query := ""
var _compact := false
var _nav := {}
var _pages := {}
var _rows: Array[Dictionary] = []
var _toggles := {}
var _sidebar: MarginContainer
var _search: LineEdit
var _search_box: PanelContainer
var _scroll: ScrollContainer
var _pages_box: VBoxContainer
var _empty: VBoxContainer
var _empty_label: Label
var _foot_status: Label
var _foot_dot: Panel
var _foot_text: VBoxContainer
var _update_status: Label
var _update_btn: FxButton
var _update_icon: TextureRect
var _recheck_btn: FxButton
var _scan_btn: FxButton
var _swatches: Array[Button] = []
var _effects := {}
var _lights := {}
var _music_sources := {}
var _units := {}
var _fav_sizes := {}
var _hotkey_status: Label
var _pointer_status: Label
var _pointer_cards: Array[PointerCard] = []
var _net_tile: PanelContainer
var _net_icon: TextureRect
var _net_title: Label
var _net_sub: Label
var _net_radio: ToggleSwitch
var _net_choose: FxButton
var _fade: Tween
var _acct_avatar: Avatar
var _acct_name: Label
var _acct_mail: Label
var _acct_in: FxButton
var _acct_switch: FxButton
var _acct_out: FxButton


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

	_scroll = ScrollContainer.new()
	_scroll.name = "ScrollContainer"
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	root.add_child(_scroll)
	var center := Kit.hbox(0)
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(center)
	center.add_child(Kit.spacer(0, 0, true))
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_top", 26)
	pad.add_theme_constant_override("margin_bottom", 48)
	center.add_child(pad)
	center.add_child(Kit.spacer(0, 0, true))
	_pages_box = Kit.vbox(0)
	_pages_box.custom_minimum_size.x = COLUMN
	pad.add_child(_pages_box)

	_build_account()
	_build_personalise()
	_build_desktop()
	_build_apps()
	_build_browser()
	_build_network()
	_build_performance()
	_build_updates()
	_build_about()
	_build_empty()

	resized.connect(_on_resized)
	Settings.changed.connect(_on_setting)
	Updater.state_changed.connect(func(_s: StringName) -> void: _sync_update())
	Library.import_finished.connect(func(_a: int, _f: int) -> void: _sync_scan())
	Host.status_changed.connect(func(_ok: bool) -> void: _sync_hotkey())
	Cursors.applied.connect(func(_id: String, _wide: bool) -> void: _sync_pointer())
	Network.changed.connect(_sync_network)
	Account.changed.connect(_sync_account)
	Account.busy_changed.connect(func(_b: bool) -> void: _sync_account())
	_sync_account()
	_sync_update()
	_sync_hotkey()
	_sync_pointer()
	_sync_network()
	_show()


func on_shown() -> void:
	_sync_update()
	_sync_scan()
	_sync_hotkey()
	_sync_network()


## Opens a section by id (see PAGES), leaving any search.
func open_page(id: String) -> void:
	if not _pages.has(id):
		return
	_page = id
	if _query != "":
		_search.text = ""
		_query = ""
	_show()


## Filters every section down to the settings that match `text`.
func search(text: String) -> void:
	if _search.text != text:
		_search.text = text
	_query = text.strip_edges().to_lower()
	_show()


func _on_resized() -> void:
	var compact := size.x < 860.0
	if compact != _compact:
		_compact = compact
		_sync_compact()
	var room := size.x - (SIDEBAR_COMPACT if _compact else SIDEBAR) - 1.0
	_pages_box.custom_minimum_size.x = clampf(room - 80.0, 380.0, COLUMN)


func _on_setting(key: String, value: Variant) -> void:
	if _toggles.has(key) and value is bool:
		for sw in _toggles[key]:
			if (sw as ToggleSwitch).button_pressed != value:
				(sw as ToggleSwitch).set_on(value)
	match key:
		"weather_unit":
			_sync_units()
		"wallpaper_light":
			_sync_lights()
		"music_source":
			_select(_music_sources, str(value))
		"effects":
			_sync_effects()
		"accent":
			_sync_swatches()
		"fav_icon_size":
			_select(_fav_sizes, str(value))


# --- Sidebar ---------------------------------------------------------------------------

func _build_sidebar() -> Control:
	_sidebar = MarginContainer.new()
	_sidebar.custom_minimum_size.x = SIDEBAR
	for side in ["left", "right"]:
		_sidebar.add_theme_constant_override("margin_" + side, 14)
	_sidebar.add_theme_constant_override("margin_top", 18)
	_sidebar.add_theme_constant_override("margin_bottom", 16)
	var col := Kit.vbox(4)
	_sidebar.add_child(col)

	_search_box = PanelContainer.new()
	_search_box.add_theme_stylebox_override("panel", Kit.box(Color(1, 1, 1, 0.045), 12, Color(1, 1, 1, 0.07), 1, 12, 0))
	col.add_child(_search_box)
	var srow := Kit.hbox(8)
	_search_box.add_child(srow)
	var sic := Kit.icon_rect("search", 16, App.TEXT_MUTE)
	sic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	srow.add_child(sic)
	_search = LineEdit.new()
	_search.name = "Search"
	_search.placeholder_text = "Find a setting"
	_search.clear_button_enabled = true
	_search.custom_minimum_size.y = 40
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.add_theme_font_size_override("font_size", 14)
	for s in ["normal", "focus", "read_only"]:
		_search.add_theme_stylebox_override(s, Kit.empty())
	_search.text_changed.connect(search)
	_search.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE and _search.text != "":
			search("")
			_search.accept_event()
	)
	srow.add_child(_search)
	col.add_child(Kit.spacer(0, 10))

	for spec in PAGES:
		if spec[0] == "updates":
			col.add_child(Kit.spacer(0, 10))
		col.add_child(_nav_button(spec[0], spec[1], spec[2]))
	var grow := Kit.spacer(0, 0)
	grow.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(grow)

	# Which Oazy this is and whether a newer one is waiting, always in view.
	var foot := Button.new()
	foot.focus_mode = Control.FOCUS_NONE
	foot.custom_minimum_size.y = 58
	foot.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	foot.add_theme_stylebox_override("normal", Kit.box(Color(1, 1, 1, 0.035), 14, Color(1, 1, 1, 0.06), 1))
	foot.add_theme_stylebox_override("hover", Kit.box(Color(1, 1, 1, 0.06), 14, Color(1, 1, 1, 0.1), 1))
	foot.add_theme_stylebox_override("pressed", Kit.box(Color(1, 1, 1, 0.06), 14, Color(1, 1, 1, 0.1), 1))
	foot.add_theme_stylebox_override("focus", Kit.empty())
	foot.pressed.connect(func() -> void:
		Sfx.play(&"select")
		open_page("updates")
	)
	col.add_child(foot)
	var frow := Kit.hbox(10)
	frow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frow.offset_left = 10
	frow.offset_right = -10
	frow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	foot.add_child(frow)
	var orb := UpdateOrb.icon(34)
	orb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	orb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	frow.add_child(orb)
	_foot_text = Kit.vbox(1)
	_foot_text.alignment = BoxContainer.ALIGNMENT_CENTER
	_foot_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_foot_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frow.add_child(_foot_text)
	_foot_text.add_child(Kit.label("Oazy %s" % App.version, 14, 600, App.TEXT))
	var srow2 := Kit.hbox(6)
	srow2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_foot_text.add_child(srow2)
	_foot_dot = Panel.new()
	_foot_dot.custom_minimum_size = Vector2(6, 6)
	_foot_dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_foot_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	srow2.add_child(_foot_dot)
	_foot_status = Kit.label("", 12, 500, App.TEXT_MUTE)
	_foot_status.clip_text = true
	_foot_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_foot_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	srow2.add_child(_foot_status)
	return _sidebar


func _nav_button(id: String, title: String, glyph: String) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size.y = 42
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.tooltip_text = title
	for s in ["normal", "pressed", "disabled", "focus"]:
		b.add_theme_stylebox_override(s, Kit.empty())
	b.add_theme_stylebox_override("hover", Kit.box(Color(1, 1, 1, 0.05), 12))
	var row := Kit.hbox(12)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 13
	row.offset_right = -10
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(row)
	var ic := Kit.icon_rect(glyph, 18, App.TEXT_DIM)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(ic)
	var l := Kit.label(title, 15, 600, App.TEXT_DIM)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(l)
	# A small accent dot, for news worth a look (a waiting update).
	var dot := Panel.new()
	dot.custom_minimum_size = Vector2(7, 7)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dot.add_theme_stylebox_override("panel", Kit.box(App.accent, 99))
	dot.visible = false
	row.add_child(dot)
	b.pressed.connect(func() -> void:
		Sfx.play(&"select")
		open_page(id)
	)
	_nav[id] = {"button": b, "icon": ic, "glyph": glyph, "label": l, "dot": dot}
	return b


func _sync_nav() -> void:
	for id in _nav.keys():
		var n: Dictionary = _nav[id]
		var on: bool = _query == "" and id == _page
		var b: Button = n["button"]
		b.add_theme_stylebox_override("normal", Kit.box(Color(1, 1, 1, 0.085), 12, Color(1, 1, 1, 0.08), 1) if on else Kit.empty())
		(n["label"] as Label).add_theme_color_override("font_color", Color.WHITE if on else App.TEXT_DIM)
		(n["icon"] as TextureRect).texture = Icons.tex(str(n["glyph"]), 18, App.accent if on else App.TEXT_DIM)


func _sync_compact() -> void:
	_sidebar.custom_minimum_size.x = SIDEBAR_COMPACT if _compact else SIDEBAR
	_search_box.visible = not _compact
	_foot_text.visible = not _compact
	for id in _nav.keys():
		(_nav[id]["label"] as Label).visible = not _compact
	if _compact and _query != "":
		search("")


# --- Pages and search ------------------------------------------------------------------

func _show() -> void:
	var searching := _query != ""
	var hits := 0
	for r in _rows:
		r["hit"] = not searching or str(r["text"]).contains(_query)
	for id in _pages.keys():
		var p: Dictionary = _pages[id]
		var page_hits := 0
		for g in p["groups"]:
			page_hits += _filter_group(g)
		hits += page_hits
		(p["node"] as Control).visible = page_hits > 0 if searching else id == _page
		(p["title"] as Control).visible = not searching
		(p["sub"] as Control).visible = not searching
		(p["crumb"] as Control).visible = searching
	_empty.visible = searching and hits == 0
	_empty_label.text = "Nothing matches “%s”" % _search.text.strip_edges()
	_sync_nav()
	_scroll.scroll_vertical = 0
	if _fade and _fade.is_valid():
		_fade.kill()
	_pages_box.modulate.a = 0.0
	_fade = Kit.ease_tween(_pages_box, Tween.TRANS_QUART)
	_fade.tween_property(_pages_box, "modulate:a", 1.0, 0.18)


## Shows the rows of a group that match the search (and whatever extra each
## row carries below it, like the pointer cards), with hairlines between them.
## Returns how many rows show.
func _filter_group(g: Dictionary) -> int:
	var list: VBoxContainer = g["list"]
	var shown := 0
	var current := true
	for child in list.get_children():
		if child.has_meta("row"):
			var r: Dictionary = _rows[int(child.get_meta("row"))]
			current = r["hit"] and r["available"]
			(child as Control).visible = current
			if current:
				(child.get_node("Line") as Control).visible = shown > 0
				shown += 1
		elif child is Control:
			(child as Control).visible = current
	(g["box"] as Control).visible = shown > 0
	return shown


func _build_empty() -> void:
	_empty = Kit.vbox(10)
	_empty.alignment = BoxContainer.ALIGNMENT_CENTER
	_empty.custom_minimum_size.y = 360
	_pages_box.add_child(_empty)
	var ic := Kit.icon_rect("search", 34, App.TEXT_MUTE)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_empty.add_child(ic)
	_empty_label = Kit.label("", 18, 600, App.TEXT_DIM)
	_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty.add_child(_empty_label)
	var hint := Kit.label("Try a word like colour, taskbar, sound or update.", 14, 500, App.TEXT_MUTE)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty.add_child(hint)
	_empty.visible = false


func _page_node(id: String) -> VBoxContainer:
	var spec: Array = []
	for s in PAGES:
		if s[0] == id:
			spec = s
	var page := Kit.vbox(0)
	page.name = "Page_" + id
	_pages_box.add_child(page)
	var title := Kit.label(spec[1], 28, 700, Color.WHITE, true)
	page.add_child(title)
	var sub := Kit.label(spec[3], 14, 500, App.TEXT_MUTE)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(sub)
	# In search results each section is named by a small heading instead.
	var crumb := Kit.hbox(8)
	var cic := Kit.icon_rect(spec[2], 15, App.TEXT_DIM)
	cic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	crumb.add_child(cic)
	crumb.add_child(Kit.label(spec[1], 15, 600, App.TEXT_DIM))
	page.add_child(crumb)
	_pages[id] = {"node": page, "title": title, "sub": sub, "crumb": crumb, "groups": []}
	page.add_child(Kit.spacer(0, 6))
	return page


## A card of rows under a small heading, on page `id`.
func _group(id: String, title: String) -> VBoxContainer:
	var page: VBoxContainer = _pages[id]["node"]
	var box := Kit.vbox(8)
	page.add_child(box)
	box.add_child(Kit.spacer(0, 10))
	if title != "":
		var head := Kit.label(title.to_upper(), 12, 600, App.TEXT_DIM)
		var m := MarginContainer.new()
		m.add_theme_constant_override("margin_left", 4)
		m.add_child(head)
		box.add_child(m)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", Kit.box(Color(1, 1, 1, 0.035), 16, Color(1, 1, 1, 0.06), 1, 24, 6))
	box.add_child(card)
	var list := Kit.vbox(0)
	card.add_child(list)
	(_pages[id]["groups"] as Array).append({"box": box, "list": list})
	return list


## A setting: title and description on the left, its control added to the
## returned row on the right. `keys` are extra words search should find it by.
## Anything added to `list` after a row belongs to it (and hides with it).
func _row(list: VBoxContainer, title: String, desc: String, keys: String = "", available: bool = true) -> HBoxContainer:
	var wrap := Kit.vbox(0)
	wrap.set_meta("row", _rows.size())
	_rows.append({"text": ("%s %s %s" % [title, desc, keys]).to_lower(), "hit": true, "available": available})
	list.add_child(wrap)
	var line := ColorRect.new()
	line.name = "Line"
	line.color = Color(1, 1, 1, 0.06)
	line.custom_minimum_size.y = 1
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(line)
	var row := Kit.hbox(18)
	row.custom_minimum_size.y = 72
	wrap.add_child(row)
	var text := Kit.vbox(3)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(text)
	text.add_child(Kit.label(title, 16, 500, App.TEXT))
	if desc != "":
		var d := Kit.label(desc, 13, 500, App.TEXT_MUTE)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.add_child(d)
	return row


func _toggle_row(list: VBoxContainer, title: String, desc: String, key: String, extra: Callable = Callable(), keys: String = "", available: bool = true) -> ToggleSwitch:
	var row := _row(list, title, desc, keys, available)
	var sw := ToggleSwitch.new()
	if key != "":
		sw.set_on(bool(Settings.get_value(key)))
		if not _toggles.has(key):
			_toggles[key] = []
		(_toggles[key] as Array).append(sw)
	sw.toggled.connect(func(on: bool) -> void:
		if key != "":
			Settings.set_value(key, on)
		if extra.is_valid():
			extra.call(on)
	)
	row.add_child(sw)
	return sw


func _button_row(list: VBoxContainer, title: String, desc: String, label_text: String, icon_name: String, cb: Callable, keys: String = "", available: bool = true) -> FxButton:
	var row := _row(list, title, desc, keys, available)
	var b := FxButton.make(label_text, icon_name, FxButton.Style.GHOST, 40)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(cb)
	row.add_child(b)
	return b


## A row of chips, one per [value, label]; `pick` gets the chosen value.
func _chips_row(list: VBoxContainer, title: String, desc: String, specs: Array, store: Dictionary, pick: Callable, keys: String = "") -> void:
	var row := _row(list, title, desc, keys)
	var box := Kit.hbox(6)
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(box)
	for spec in specs:
		var b := FxButton.make(spec[1], "", FxButton.Style.CHIP, 34)
		b.add_theme_font_size_override("font_size", 13)
		var value: String = spec[0]
		b.pressed.connect(func() -> void: pick.call(value))
		box.add_child(b)
		store[value] = b


static func _select(store: Dictionary, value: String) -> void:
	for key in store.keys():
		(store[key] as FxButton).selected = key == value


# --- Account ------------------------------------------------------------------------------

func _build_account() -> void:
	_page_node("account")
	var you := _group("account", "")
	var row := _row(you, "", "", "google profile photo picture sign in log in login out email chrome name")
	row.custom_minimum_size.y = 104
	var text := row.get_child(0) as VBoxContainer
	_acct_name = text.get_child(0) as Label
	_acct_name.add_theme_font_override("font", Kit.font(700, true))
	_acct_name.add_theme_font_size_override("font_size", 20)
	_acct_name.clip_text = true
	_acct_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_acct_mail = Kit.label("", 14, 500, App.TEXT_DIM)
	_acct_mail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_child(_acct_mail)
	_acct_avatar = Avatar.new(64)
	_acct_avatar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_acct_avatar)
	row.move_child(_acct_avatar, 0)
	var buttons := Kit.hbox(8)
	buttons.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(buttons)
	_acct_in = FxButton.make("Sign in with Google", "user", FxButton.Style.PRIMARY, 42)
	_acct_in.pressed.connect(func() -> void: main.show_account_picker())
	buttons.add_child(_acct_in)
	_acct_switch = FxButton.make("Switch", "refresh", FxButton.Style.GHOST, 40)
	_acct_switch.pressed.connect(func() -> void: main.show_account_picker())
	buttons.add_child(_acct_switch)
	_acct_out = FxButton.make("Sign out", "", FxButton.Style.GHOST, 40)
	_acct_out.pressed.connect(func() -> void: main.confirm_sign_out())
	buttons.add_child(_acct_out)

	var web := _group("account", "Across Oazy")
	_row(web, "One sign-in for the web", "Oazy Browser, Flow and your other web apps share one sign-in: sign in to Google once and they all are. Sites that sign you in with a popup open it in a small Oazy window.", "browser flow apps cookies session shared popup")
	_button_row(web, "Google Account", "Your Google settings, privacy and security, in Oazy Browser.", "Open", "external", func() -> void: Account.manage(), "manage privacy security password")
	_row(web, "Chrome", "Picking an account from Chrome fills in your email. Chrome keeps its own sign-in (it's locked to Chrome), so Google asks for your password or passkey once here.", "chrome profile accounts import")


func _sync_account() -> void:
	if _acct_name == null:
		return
	var on := Account.signed_in()
	var name := Account.display_name()
	_acct_name.text = Account.full_name if Account.full_name != "" else (name if name != "" else "Not signed in")
	_acct_mail.text = Account.email if on else ("Waiting for you to finish signing in on Google's page…" if Account.busy else "Sign in with Google to bring your name and photo to Oazy, and sign in to its browser and apps in one go.")
	_acct_avatar.set_person(name if name != "" else "?", Account.photo)
	_acct_in.visible = not on
	_acct_in.text = "Finish signing in" if Account.busy else "Sign in with Google"
	_acct_switch.visible = on
	_acct_out.visible = on


# --- Personalise -------------------------------------------------------------------------

func _build_personalise() -> void:
	_page_node("personalise")
	var look := _group("personalise", "Colour and wallpaper")
	_swatch_row(look)
	_wallpaper_rows(look)
	_light_row(look)
	_toggle_row(look, "Music wallpaper", "Lights the desktop with what's playing: it moves with the beat, and its colours follow the song's mood. Also on the taskbar.", "music_wallpaper", Callable(), "visualiser visualizer audio sound song spectrum beat")
	_chips_row(look, "Music listens to", "Chrome alone, so YouTube Music works even minimised and nothing else joins in (everything while Chrome is closed), or all sound.",
		[["chrome", "Chrome"], ["all", "All sound"]], _music_sources,
		func(v: String) -> void: Settings.set_value("music_source", v), "visualiser visualizer audio youtube chrome sound")
	_select(_music_sources, str(Settings.get_value("music_source")))

	var you := _group("personalise", "Pointer and icons")
	_pointer_rows(you)
	_custom_icons_rows(you)
	_chips_row(you, "Favourite icon size", "How big your favourites are on the desktop.", [["small", "Small"], ["medium", "Medium"], ["large", "Large"]], _fav_sizes,
		func(v: String) -> void: Settings.set_value("fav_icon_size", v), "favourites favorites desktop icons big small large")
	_select(_fav_sizes, str(Settings.get_value("fav_icon_size")))

	var sound := _group("personalise", "Sound")
	_toggle_row(sound, "Interface sounds", "Soft clicks and chimes as you move around.", "ui_sounds", Callable(), "audio sfx click chime mute")
	_slider_row(sound, "Sound volume", "How loud Oazy's own sounds are.", "volume", "audio loud quiet")

	var greet := _group("personalise", "Greeting")
	_name_row(greet)


func _swatch_row(list: VBoxContainer) -> void:
	var row := _row(list, "Accent colour", "Tints the Start orb, highlights and a soft glow in the wallpaper.", "color theme tint highlight")
	var box := Kit.hbox(10)
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(box)
	for c in App.ACCENT_SWATCHES:
		var col: Color = c
		var b := Button.new()
		b.custom_minimum_size = Vector2(28, 28)
		b.focus_mode = Control.FOCUS_ALL
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.tooltip_text = "#" + col.to_html(false)
		b.set_meta("color", col)
		b.pressed.connect(func() -> void:
			Sfx.play(&"toggle")
			Settings.set_value("accent", col.to_html(false))
			App.set_accent(col)
			_sync_swatches()
			_sync_nav()
		)
		box.add_child(b)
		_swatches.append(b)
	_sync_swatches()


func _sync_swatches() -> void:
	var chosen := Color(str(Settings.get_value("accent")))
	for b in _swatches:
		var col: Color = b.get_meta("color")
		var on := col.is_equal_approx(chosen)
		var n := Kit.box(col, 999, Color(1, 1, 1, 0.95) if on else Color(1, 1, 1, 0.12), 3 if on else 1)
		var h := Kit.box(col.lightened(0.12), 999, Color(1, 1, 1, 0.6), 2)
		b.add_theme_stylebox_override("normal", n)
		b.add_theme_stylebox_override("hover", h)
		b.add_theme_stylebox_override("pressed", n)
		b.add_theme_stylebox_override("focus", Kit.box(Color(0, 0, 0, 0), 999, Color(1, 1, 1, 0.9), 2))


## Wallpaper styles, as live preview cards.
func _wallpaper_rows(list: VBoxContainer) -> void:
	_row(list, "Wallpaper", "Calm, slowly moving backgrounds, lit by the wallpaper light below.", "background animated style")
	var grid := GridContainer.new()
	grid.name = "Wallpapers"
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_bottom", 20)
	pad.add_child(grid)
	list.add_child(pad)
	for id in Wallpaper.STYLES:
		var card := WallpaperCard.make(id)
		card.pressed.connect(func() -> void:
			Sfx.play(&"toggle")
			Settings.set_value("wallpaper", id)
		)
		grid.add_child(card)


func _light_row(list: VBoxContainer) -> void:
	_chips_row(list, "Wallpaper light", "Auto follows the time of day, from dawn to night.",
		[["auto", "Auto"], ["dawn", "Dawn"], ["day", "Day"], ["dusk", "Dusk"], ["night", "Night"]], _lights,
		func(v: String) -> void: Settings.set_value("wallpaper_light", v), "background time day night dawn dusk")
	_sync_lights()


func _sync_lights() -> void:
	_select(_lights, str(Settings.get_value("wallpaper_light")))


## Mouse pointer themes: Off plus every theme, as preview cards.
func _pointer_rows(list: VBoxContainer) -> void:
	var desc := "Oazy's pointers follow you into every app while Oazy is running. Off keeps Windows' own." if App.is_windows() else "Oazy's own pointers, from the arrow to the busy spinner."
	var row := _row(list, "Mouse pointer", desc, "cursor arrow theme")
	_pointer_status = Kit.label("", 14, 600, App.TEXT_DIM)
	_pointer_status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_pointer_status)
	var grid := GridContainer.new()
	grid.name = "Pointers"
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_bottom", 20)
	pad.add_child(grid)
	list.add_child(pad)
	var ids: Array[String] = [Cursors.OFF]
	ids.append_array(Cursors.theme_ids())
	for id in ids:
		var card := PointerCard.make(id)
		card.pressed.connect(func() -> void:
			Sfx.play(&"toggle")
			Settings.set_value("pointer", id)
			_sync_pointer()
		)
		grid.add_child(card)
		_pointer_cards.append(card)


func _sync_pointer() -> void:
	if _pointer_status == null:
		return
	var id := Cursors.selected()
	for c in _pointer_cards:
		c.chosen = c.theme_id == id
	if id == Cursors.OFF:
		_pointer_status.text = "Windows default" if App.is_windows() else "Off"
		_pointer_status.add_theme_color_override("font_color", App.TEXT_MUTE)
	elif Cursors.system_wide:
		_pointer_status.text = "In every app"
		_pointer_status.add_theme_color_override("font_color", App.SUCCESS)
	else:
		_pointer_status.text = "In Oazy"
		_pointer_status.add_theme_color_override("font_color", App.TEXT_DIM)


## Oazy's own icons for common apps: All / None, then one chip per app.
func _custom_icons_rows(list: VBoxContainer) -> void:
	var row := _row(list, "Oazy app icons", "Swap the stock icons of everyday apps for Oazy-style ones on the taskbar and in Start.", "icon pack explorer terminal claude whatsapp")
	var chips: Array[Button] = []
	var sync := func() -> void:
		var on: Array = Settings.get_value("custom_icons")
		for c in chips:
			c.set_pressed_no_signal(on.has(str(c.get_meta("key"))))
	for pair in [["All", true], ["None", false]]:
		var b := FxButton.make(str(pair[0]), "", FxButton.Style.GHOST, 36)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var all: bool = pair[1]
		b.pressed.connect(func() -> void:
			Settings.set_value("custom_icons", AppIcon.CUSTOM.keys() if all else [])
			sync.call()
		)
		row.add_child(b)
	var grid := GridContainer.new()
	grid.name = "CustomIcons"
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_bottom", 18)
	pad.add_child(grid)
	list.add_child(pad)
	for key in AppIcon.CUSTOM:
		var c: Dictionary = AppIcon.CUSTOM[key]
		var chip := Button.new()
		chip.toggle_mode = true
		chip.set_meta("key", key)
		chip.custom_minimum_size = Vector2(0, 48)
		chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		chip.focus_mode = Control.FOCUS_NONE
		chip.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		chip.add_theme_stylebox_override("normal", Kit.box(Color(1, 1, 1, 0.03), 14, Color(1, 1, 1, 0.06), 1))
		chip.add_theme_stylebox_override("hover", Kit.box(Color(1, 1, 1, 0.07), 14, Color(1, 1, 1, 0.12), 1))
		chip.add_theme_stylebox_override("pressed", Kit.box(Color(App.accent, 0.16), 14, Color(App.accent, 0.55), 1))
		chip.add_theme_stylebox_override("hover_pressed", Kit.box(Color(App.accent, 0.22), 14, Color(App.accent, 0.7), 1))
		var inner := Kit.hbox(10)
		inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		inner.offset_left = 8
		inner.offset_right = -8
		inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.add_child(inner)
		var ic := AppIcon.new()
		ic.custom_minimum_size = Vector2(30, 30)
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		ic.set_item({"name": c["name"], "kind": "app", "custom": key})
		inner.add_child(ic)
		var l := Kit.label(str(c["name"]), 14, 500, App.TEXT)
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.clip_text = true
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		inner.add_child(l)
		chip.toggled.connect(func(on: bool) -> void:
			var now: Array = (Settings.get_value("custom_icons") as Array).duplicate()
			if on and not now.has(key):
				now.append(key)
			elif not on:
				now.erase(key)
			Settings.set_value("custom_icons", now)
		)
		grid.add_child(chip)
		chips.append(chip)
	sync.call()


func _slider_row(list: VBoxContainer, title: String, desc: String, key: String, keys: String = "") -> void:
	var row := _row(list, title, desc, keys)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.value = float(Settings.get_value(key))
	slider.custom_minimum_size = Vector2(220, 24)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.value_changed.connect(func(v: float) -> void: Settings.set_value(key, v))
	slider.drag_ended.connect(func(_c: bool) -> void: Sfx.play(&"select"))
	row.add_child(slider)


func _name_row(list: VBoxContainer) -> void:
	var row := _row(list, "Your name", "Used for the greeting on your desktop. Empty uses your Google first name, or your Windows name.", "user greeting hello")
	var edit := LineEdit.new()
	edit.placeholder_text = App.user_name() if App.user_name() != "" else "Your name"
	edit.text = str(Settings.get_value("user_name"))
	edit.custom_minimum_size = Vector2(220, 40)
	edit.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	edit.text_changed.connect(func(t: String) -> void: Settings.set_value("user_name", t.strip_edges()))
	row.add_child(edit)


# --- Desktop & taskbar ---------------------------------------------------------------------

func _build_desktop() -> void:
	_page_node("desktop")
	var shell := _group("desktop", "Oazy on your PC")
	_toggle_row(shell, "Use Oazy as your desktop", "Apps open on Oazy's desktop, under Oazy's taskbar, so you never leave Oazy. Applies the next time Oazy starts.", "shell_mode", func(_on: bool) -> void:
		App.toast("Restart Oazy to switch")
	, "shell mode replace explorer", App.is_windows() or Shell.native)
	_toggle_row(shell, "Hide the Windows taskbar", "Oazy's taskbar takes its place while Oazy is running.", "hide_windows_taskbar", Callable(), "explorer", Shell.native)
	_toggle_row(shell, "Tint app window borders", "Gives other apps' window borders Oazy's accent colour (Windows 11).", "theme_app_windows", Callable(), "theme window border title bar colour", Shell.native)
	_toggle_row(shell, "Open in fullscreen", "Oazy covers the whole screen like a real desktop. F11 switches any time.", "shell_fullscreen", func(on: bool) -> void: main.apply_window_mode(on), "window f11", not Shell.native)
	_toggle_row(shell, "Start with Windows", "Sign in and land straight on your Oazy desktop.", "launch_at_startup", func(on: bool) -> void: main.set_autostart(on), "startup boot login autostart")

	var keys := _group("desktop", "Shortcuts")
	var hk := _row(keys, "Open Start from anywhere" if Shell.native else "Come back home from anywhere", "Press Ctrl + Alt + O in any app to open Start." if Shell.native else "Press Ctrl + Alt + O in any app to bring Oazy to the front.", "hotkey keyboard ctrl alt")
	_hotkey_status = Kit.label("", 14, 600, App.TEXT_DIM)
	_hotkey_status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hk.add_child(_hotkey_status)
	_toggle_row(keys, "Oazy's Alt + Tab", "Alt + Tab shows every open window as a live preview on Oazy's glass. Off brings back Windows' own.", "alt_tab", Callable(), "switcher alt tab windows keyboard", Shell.native)
	_button_row(keys, "Keyboard shortcuts", "Every key Oazy listens for, on one sheet.", "Show", "keyboard", func() -> void: main.show_shortcuts(), "hotkeys keys")

	var desk := _group("desktop", "Desktop cards")
	_toggle_row(desk, "Show CPU temperature", "On the desktop's This PC card. Comes from HWiNFO or LibreHardwareMonitor while one is running, otherwise from your motherboard's sensor (less exact).", "cpu_temp", Callable(), "sensor heat hwinfo")
	_chips_row(desk, "Weather units", "Auto picks what's usual where you are.", [["auto", "Auto"], ["c", "°C"], ["f", "°F"]], _units, func(v: String) -> void:
		Settings.set_value("weather_unit", v)
		Weather.changed.emit()
	, "celsius fahrenheit temperature forecast")
	_sync_units()

	var bar := _group("desktop", "Taskbar")
	_button_row(bar, "Reset taskbar", "Go back to the suggested pinned apps.", "Reset", "pin", func() -> void:
		Catalog.reset_pins()
		App.toast("Taskbar reset", &"success")
	, "pins pinned apps")


func _sync_units() -> void:
	_select(_units, str(Settings.get_value("weather_unit")))


func _sync_hotkey() -> void:
	if _hotkey_status == null:
		return
	if Host.available and Host.hotkey_ok:
		_hotkey_status.text = "On"
		_hotkey_status.add_theme_color_override("font_color", App.SUCCESS)
	elif Host.available:
		_hotkey_status.text = "Taken by another app"
		_hotkey_status.add_theme_color_override("font_color", App.WARNING)
	else:
		_hotkey_status.text = "Windows only" if not App.is_windows() else "Starting…"
		_hotkey_status.add_theme_color_override("font_color", App.TEXT_MUTE)


# --- Apps & library ----------------------------------------------------------------------

func _build_apps() -> void:
	_page_node("apps")
	var lib := _group("apps", "Library")
	_scan_btn = _button_row(lib, "Find installed games", "Imports Steam, Epic Games and GOG games. Already added ones are skipped.", "Scan now", "sparkles", func() -> void: main.scan_stores(), "steam epic gog import scan")
	_button_row(lib, "Add a game or app", "Any .exe, shortcut, Steam link or web address.", "Add", "plus", func() -> void: main.open_add({}), "new program shortcut exe")
	_button_row(lib, "Refresh artwork", "Forget downloaded covers and fetch them again.", "Refresh", "refresh", func() -> void:
		Art.clear_downloads()
		App.toast("Artwork refreshed", &"success")
	, "covers images art pictures")
	_button_row(lib, "Open Library", "Every game and app you've added, with its artwork.", "Open", "grid", func() -> void: main.open_app(&"library"), "games")

	var play := _group("apps", "While you play")
	_toggle_row(play, "Minimise Oazy when a game starts", "Off keeps your desktop right behind the game.", "minimize_for_games", Callable(), "launch gaming hide")


# --- Browser & terminal ----------------------------------------------------------------

func _build_browser() -> void:
	_page_node("browser")
	var web := _group("browser", "Oazy Browser")
	_toggle_row(web, "Open web links in Oazy Browser", "Web searches and addresses from Start open in Oazy's own browser instead of your default one.", "browser_links", Callable(), "internet web chrome edge default url")
	_button_row(web, "Open Oazy Browser", "A new browser window.", "Open", "browser", func() -> void: Browser.open("", true), "internet web", App.is_windows())

	var term := _group("browser", "Oazy Terminal")
	_toggle_row(term, "Open terminals in Oazy Terminal", "Terminal, Command Prompt, PowerShell and Claude Code open in Oazy's own terminal, with tabs and split panes.", "terminal_oazy", Callable(), "cmd powershell shell console claude code")
	_button_row(term, "Open Oazy Terminal", "A new terminal window.", "Open", "terminal", func() -> void: Terminal.open(), "cmd powershell shell console", App.is_windows())

	var files := _group("browser", "Oazy Files")
	_toggle_row(files, "Open folders in Oazy Files", "File Explorer, Start's folders and folders you find open in Oazy's own file explorer, with tabs, previews and search. Off brings back Windows Explorer.", "files_oazy", Callable(), "explorer folder file manager")


# --- Network -------------------------------------------------------------------------------

func _build_network() -> void:
	_page_node("network")
	var now := _group("network", "")
	var row := _row(now, "Connection", "", "wifi ethernet internet online offline")
	# The connection gets a larger, glanceable line of its own.
	var text: VBoxContainer = row.get_child(0)
	text.get_child(0).queue_free()
	row.custom_minimum_size.y = 96
	_net_tile = PanelContainer.new()
	_net_tile.custom_minimum_size = Vector2(52, 52)
	_net_tile.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_net_tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_net_tile)
	row.move_child(_net_tile, 0)
	_net_icon = Kit.icon_rect("wifi", 24, Color.WHITE)
	_net_icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_net_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_net_tile.add_child(_net_icon)
	_net_title = Kit.label("", 19, 700, Color.WHITE, true)
	_net_title.clip_text = true
	_net_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	text.add_child(_net_title)
	_net_sub = Kit.label("", 13, 500, App.TEXT_MUTE)
	text.add_child(_net_sub)
	_net_choose = FxButton.make("Choose a network", "wifi", FxButton.Style.GHOST, 40)
	_net_choose.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_net_choose.pressed.connect(func() -> void:
		if main and main.taskbar:
			main.taskbar.open_network()
	)
	row.add_child(_net_choose)

	var wifi := _group("network", "Wi-Fi")
	_net_radio = _toggle_row(wifi, "Wi-Fi", "Turn the Wi-Fi radio off to save power or stay offline.", "", func(on: bool) -> void:
		Network.set_radio(on, func(d: Dictionary) -> void:
			if not bool(d.get("ok", false)):
				App.toast("Windows keeps this switch in its own settings", &"error")
				_sync_network()
		)
	, "wireless radio airplane")
	_button_row(wifi, "Windows network settings", "Proxies, VPNs, adapters and data limits.", "Open", "external", func() -> void: OS.shell_open("ms-settings:network"), "vpn proxy adapter advanced", App.is_windows())


func _sync_network() -> void:
	if _net_title == null:
		return
	var cur := Network.current()
	var wired := Network.wired()
	var icon := "wifi"
	var tint := App.accent
	if not Network.status.is_empty() and not cur.is_empty():
		_net_title.text = str(cur.get("ssid", "Wi-Fi"))
		var parts: Array[String] = ["Connected" if Network.internet() else "Connected, no internet"]
		var sp := Network.speed(int(cur.get("mbps", 0)))
		if sp != "":
			parts.append(sp)
		_net_sub.text = "  ·  ".join(parts)
	elif not wired.is_empty():
		icon = "ethernet"
		_net_title.text = "Ethernet"
		var wsp := Network.speed(int((wired[0] as Dictionary).get("mbps", 0)))
		_net_sub.text = ("Connected  ·  %s" % wsp) if wsp != "" else "Connected"
	elif Network.status.is_empty():
		_net_title.text = "Looking for networks"
		_net_sub.text = "Windows only" if not App.is_windows() else "Starting…"
		tint = App.TEXT_DIM
	else:
		_net_title.text = "Not connected"
		_net_sub.text = "Wi-Fi is off" if Network.has_wifi() and not Network.radio_on() else "Pick a network to get online"
		tint = App.TEXT_DIM
	_net_tile.add_theme_stylebox_override("panel", Kit.box(Color(tint, 0.14), 16, Color(tint, 0.26), 1))
	_net_icon.texture = Icons.tex(icon, 24, tint.lightened(0.15))
	_net_choose.visible = Network.has_wifi()
	_net_radio.set_on(Network.radio_on())
	var i := int(_net_radio.get_parent().get_parent().get_meta("row"))
	var had: bool = _rows[i]["available"]
	_rows[i]["available"] = Network.has_wifi()
	if had != _rows[i]["available"] and is_node_ready():
		_show()


# --- Performance ---------------------------------------------------------------------------

func _build_performance() -> void:
	_page_node("performance")
	var fx := _group("performance", "Effects")
	_chips_row(fx, "Visual effects", "Eco calms the animations and caps the frame rate to save power.", [["high", "Stunning"], ["eco", "Eco"]], _effects, func(v: String) -> void:
		Settings.set_value("effects", v)
		App.refresh_fps()
		GlassPanel.refresh_all(get_tree())
	, "animation fps frame rate battery power eco")
	_sync_effects()

	var clean := _group("performance", "Cleaner")
	_toggle_row(clean, "Keep watch", "A couple of minutes after Oazy starts, it quietly checks whether Windows brought anything back, and tells you.", "cleaner_watch", Callable(), "cleaner bloatware debloat")
	_button_row(clean, "Open Cleaner", "Bloatware, startup apps, junk files and privacy, all undoable.", "Open", "broom", func() -> void: main.open_app(&"cleaner"), "debloat junk startup privacy")


func _sync_effects() -> void:
	_select(_effects, str(Settings.get_value("effects")))


# --- Updates -------------------------------------------------------------------------------

func _build_updates() -> void:
	_page_node("updates")
	var top := _group("updates", "")
	var row := _row(top, "Oazy %s" % App.version, "", "update version check download install new")
	var text: VBoxContainer = row.get_child(0)
	text.get_child(0).queue_free()
	row.custom_minimum_size.y = 104
	var orb := UpdateOrb.icon(60)
	orb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(orb)
	row.move_child(orb, 0)
	text.add_child(Kit.label("Oazy %s" % App.version, 22, 700, Color.WHITE, true))
	var status_row := Kit.hbox(8)
	text.add_child(status_row)
	_update_icon = Kit.icon_rect("check", 16, App.SUCCESS)
	_update_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	status_row.add_child(_update_icon)
	_update_status = Kit.label("", 14, 500, App.TEXT_DIM)
	_update_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_update_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	status_row.add_child(_update_status)
	# With an update found, you can still look for an even newer one.
	_recheck_btn = FxButton.make("Check again", "refresh", FxButton.Style.GHOST, 40)
	_recheck_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_recheck_btn.pressed.connect(func() -> void: Updater.check())
	row.add_child(_recheck_btn)
	_update_btn = FxButton.make("Check for updates", "refresh", FxButton.Style.PRIMARY, 40)
	_update_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_update_btn.pressed.connect(_on_update_button)
	row.add_child(_update_btn)

	var opts := _group("updates", "Options")
	_toggle_row(opts, "Check for updates automatically", "Oazy checks GitHub quietly in the background.", "auto_check_updates", Callable(), "auto background")
	_button_row(opts, "Patch notes", "Everything that changed, version by version.", "Read", "sparkles", func() -> void: main.show_patch_notes(), "changelog whats new release notes")


func _sync_update() -> void:
	if _update_status == null:
		return
	var icon := "check"
	var color := App.SUCCESS
	var btn := "Check for updates"
	var foot := "Up to date"
	match Updater.state:
		&"checking":
			_update_status.text = "Checking for updates…"
			icon = "refresh"
			color = App.TEXT_DIM
			foot = "Checking…"
		&"current":
			_update_status.text = "You're up to date"
		&"available":
			_update_status.text = "Version %s is available" % Updater.latest.get("version", "?")
			icon = "sparkles"
			color = App.accent
			btn = "See what's new"
			foot = "Update available"
		&"downloading":
			_update_status.text = "Downloading version %s…" % Updater.latest.get("version", "?")
			icon = "download"
			color = App.accent
			btn = "Show progress"
			foot = "Downloading…"
		&"ready":
			_update_status.text = "Version %s is ready to install" % Updater.latest.get("version", "?")
			icon = "download"
			color = App.accent
			btn = "Restart to update"
			foot = "Ready to install"
		&"error":
			_update_status.text = Updater.error_text
			icon = "alert"
			color = App.WARNING
			btn = "Try again"
			foot = "Couldn't check"
		_:
			_update_status.text = "Updates come straight from GitHub"
			icon = "info"
			color = App.TEXT_DIM
			foot = "Updates from GitHub"
	_update_icon.texture = Icons.tex(icon, 16, color)
	_update_btn.text = btn
	_update_btn.disabled = Updater.state == &"checking"
	_recheck_btn.visible = Updater.state in [&"available", &"ready"]
	_foot_status.text = foot
	_foot_dot.add_theme_stylebox_override("panel", Kit.box(color, 99))
	(_nav["updates"]["dot"] as Control).visible = Updater.state in [&"available", &"downloading", &"ready"]


func _on_update_button() -> void:
	match Updater.state:
		&"available", &"downloading", &"ready":
			main.show_update()
		_:
			Updater.check()


# --- About ---------------------------------------------------------------------------------

func _build_about() -> void:
	_page_node("about")
	var hero := _group("about", "")
	var row := _row(hero, "Oazy", "", "about version credits")
	var text: VBoxContainer = row.get_child(0)
	text.get_child(0).queue_free()
	row.custom_minimum_size.y = 120
	var orb := UpdateOrb.icon(72)
	orb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(orb)
	row.move_child(orb, 0)
	text.add_child(Kit.label("Oazy", 26, 700, Color.WHITE, true))
	text.add_child(Kit.label("Version %s" % App.version, 14, 500, App.TEXT_DIM))
	var credits := Kit.label("Made with Godot  ·  Geist typeface (SIL OFL)", 13, 500, App.TEXT_MUTE)
	credits.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_child(credits)

	var data := _group("about", "Your data")
	_button_row(data, "Data folder", "Your library, settings and downloaded artwork live here.", "Open", "folder", func() -> void: Files.open_folder(App.data_dir()), "files appdata storage")


# --- Live state ----------------------------------------------------------------------------

func _sync_scan() -> void:
	if _scan_btn:
		_scan_btn.disabled = Library.importing
		_scan_btn.text = "Scanning…" if Library.importing else "Scan now"


# --- Tests -------------------------------------------------------------------------------

func page_visible(id: String) -> bool:
	return _pages.has(id) and (_pages[id]["node"] as Control).visible


## How many settings show right now (on the page, or across search results).
func visible_rows() -> int:
	var n := 0
	for id in _pages.keys():
		if not (_pages[id]["node"] as Control).visible:
			continue
		for g in _pages[id]["groups"]:
			for child in (g["list"] as VBoxContainer).get_children():
				if child.has_meta("row") and (child as Control).visible:
					n += 1
	return n
