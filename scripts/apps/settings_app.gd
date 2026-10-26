class_name SettingsApp
extends Control
## The Settings window, grouped into calm cards.

const COLUMN := 760.0

var main: Node
var _col: VBoxContainer
var _update_status: Label
var _update_btn: FxButton
var _update_icon: TextureRect
var _scan_btn: FxButton
var _swatches: Array[Button] = []
var _effects := {}
var _lights := {}
var _hotkey_status: Label
var _pointer_status: Label
var _pointer_cards: Array[PointerCard] = []
var _first_row := true


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	add_child(scroll)
	var center := Kit.hbox(0)
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	center.add_child(Kit.spacer(0, 0, true))
	_col = Kit.vbox(14)
	_col.custom_minimum_size.x = COLUMN
	center.add_child(_col)
	center.add_child(Kit.spacer(0, 0, true))
	resized.connect(func() -> void: _col.custom_minimum_size.x = clampf(size.x - 72.0, 420.0, COLUMN))

	_col.add_child(Kit.spacer(0, 18))
	_col.add_child(Kit.label("Settings", 34, 800, Color.WHITE, true))
	_col.add_child(Kit.spacer(0, 2))

	_build_updates()

	var you := _section("Your Oazy", "user")
	_name_row(you)
	if App.is_windows() or Shell.native:
		_toggle_row(you, "Use Oazy as your desktop", "Apps open on Oazy's desktop, under Oazy's taskbar, so you never leave Oazy. Applies the next time Oazy starts.", "shell_mode", func(_on: bool) -> void:
			App.toast("Restart Oazy to switch")
		)
	if Shell.native:
		_toggle_row(you, "Hide the Windows taskbar", "Oazy's taskbar takes its place while Oazy is running.", "hide_windows_taskbar")
		_toggle_row(you, "Oazy's Alt + Tab", "Alt + Tab shows every open window as a live preview on Oazy's glass. Off brings back Windows' own.", "alt_tab")
		_toggle_row(you, "Match app title bars to Oazy", "Gives other apps' title bars and borders Oazy's colours (Windows 11).", "theme_app_windows")
	else:
		_toggle_row(you, "Open in fullscreen", "Oazy covers the whole screen like a real desktop. F11 switches any time.", "shell_fullscreen", func(on: bool) -> void: main.apply_window_mode(on))
	if App.is_windows():
		_toggle_row(you, "Open web links in Oazy Browser", "Web searches and addresses from Start open in Oazy's own browser instead of your default one.", "browser_links")
	_toggle_row(you, "Start with Windows", "Sign in and land straight on your Oazy desktop.", "launch_at_startup", func(on: bool) -> void: main.set_autostart(on))
	var hk := _row(you, "Open Start from anywhere" if Shell.native else "Come back home from anywhere", "Press Ctrl + Alt + O in any app to open Start." if Shell.native else "Press Ctrl + Alt + O in any app to bring Oazy to the front.")
	_hotkey_status = Kit.label("", 14, 600, App.TEXT_DIM)
	_hotkey_status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hk.add_child(_hotkey_status)
	_toggle_row(you, "Minimise Oazy when a game starts", "Off keeps your desktop right behind the game.", "minimize_for_games")

	var look := _section("Appearance", "palette")
	_swatch_row(look)
	_light_row(look)
	_effects_row(look)
	_pointer_rows(look)
	_custom_icons_rows(look)
	_toggle_row(look, "Interface sounds", "Soft clicks and chimes as you move around.", "ui_sounds")
	_slider_row(look, "Sound volume", "volume")

	var library := _section("Library and taskbar", "grid")
	_scan_btn = _button_row(library, "Find installed games", "Imports Steam, Epic Games and GOG games. Already added ones are skipped.", "Scan now", "sparkles", func() -> void: main.scan_stores())
	_button_row(library, "Add a game or app", "Any .exe, shortcut, Steam link or web address.", "Add", "plus", func() -> void: main.open_add({}))
	_button_row(library, "Refresh artwork", "Forget downloaded covers and fetch them again.", "Refresh", "refresh", func() -> void:
		Art.clear_downloads()
		App.toast("Artwork refreshed", &"success")
	)
	_button_row(library, "Reset taskbar", "Go back to the suggested pinned apps.", "Reset", "pin", func() -> void:
		Catalog.reset_pins()
		App.toast("Taskbar reset", &"success")
	)

	var about := _section("About", "info")
	_button_row(about, "Data folder", "Your library, settings and downloaded artwork live here.", "Open", "folder", func() -> void: OS.shell_open(App.data_dir()))
	var credits := Kit.label("Oazy %s  ·  Made with Godot  ·  Inter & Outfit typefaces (SIL OFL)" % App.version, 13, 500, App.TEXT_MUTE)
	credits.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_col.add_child(Kit.spacer(0, 8))
	_col.add_child(credits)
	_col.add_child(Kit.spacer(0, 60))

	Updater.state_changed.connect(func(_s: StringName) -> void: _sync_update())
	Library.import_finished.connect(func(_a: int, _f: int) -> void: _sync_scan())
	Host.status_changed.connect(func(_ok: bool) -> void: _sync_hotkey())
	Cursors.applied.connect(func(_id: String, _wide: bool) -> void: _sync_pointer())
	_sync_update()
	_sync_hotkey()
	_sync_pointer()


func on_shown() -> void:
	_sync_update()
	_sync_scan()
	_sync_hotkey()


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


# --- Sections -------------------------------------------------------------------

func _build_updates() -> void:
	var card := PanelContainer.new()
	var s := Kit.box(Color(1, 1, 1, 0.055), 22, Color(1, 1, 1, 0.08), 1, 26, 22)
	card.add_theme_stylebox_override("panel", s)
	_col.add_child(card)
	var row := Kit.hbox(20)
	card.add_child(row)
	row.add_child(OazyMark.icon(64))
	var text := Kit.vbox(4)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(text)
	text.add_child(Kit.label("Oazy %s" % App.version, 22, 700, Color.WHITE, true))
	var status_row := Kit.hbox(8)
	text.add_child(status_row)
	_update_icon = Kit.icon_rect("check", 16, App.SUCCESS)
	_update_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	status_row.add_child(_update_icon)
	_update_status = Kit.label("", 15, 500, App.TEXT_DIM)
	_update_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_update_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	status_row.add_child(_update_status)
	var notes := FxButton.make("Patch notes", "sparkles", FxButton.Style.GHOST, 46)
	notes.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	notes.pressed.connect(func() -> void: main.show_patch_notes())
	row.add_child(notes)
	_update_btn = FxButton.make("Check for updates", "refresh", FxButton.Style.PRIMARY, 46)
	_update_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_update_btn.pressed.connect(_on_update_button)
	row.add_child(_update_btn)
	var opts := _section("", "")
	_toggle_row(opts, "Check for updates automatically", "Oazy checks GitHub quietly in the background.", "auto_check_updates")


func _section(title: String, icon_name: String) -> VBoxContainer:
	if title != "":
		var head := Kit.hbox(10)
		head.add_child(Kit.icon_rect(icon_name, 18, App.TEXT_DIM))
		head.add_child(Kit.label(title.to_upper(), 13, 700, App.TEXT_DIM))
		_col.add_child(Kit.spacer(0, 12))
		_col.add_child(head)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", Kit.box(Color(1, 1, 1, 0.045), 20, Color(1, 1, 1, 0.07), 1, 24, 8))
	_col.add_child(card)
	var list := Kit.vbox(0)
	card.add_child(list)
	_first_row = true
	return list


func _row(list: VBoxContainer, title: String, desc: String) -> HBoxContainer:
	if list.get_child_count() > 0:
		var line := ColorRect.new()
		line.color = Color(1, 1, 1, 0.06)
		line.custom_minimum_size.y = 1
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		list.add_child(line)
	var row := Kit.hbox(18)
	row.custom_minimum_size.y = 74
	list.add_child(row)
	var text := Kit.vbox(3)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(text)
	text.add_child(Kit.label(title, 17, 600, App.TEXT))
	if desc != "":
		var d := Kit.label(desc, 14, 500, App.TEXT_MUTE)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.add_child(d)
	return row


func _toggle_row(list: VBoxContainer, title: String, desc: String, key: String, extra: Callable = Callable()) -> ToggleSwitch:
	var row := _row(list, title, desc)
	var sw := ToggleSwitch.new()
	if key != "":
		sw.set_on(bool(Settings.get_value(key)))
	sw.toggled.connect(func(on: bool) -> void:
		if key != "":
			Settings.set_value(key, on)
		if extra.is_valid():
			extra.call(on)
	)
	row.add_child(sw)
	return sw


## Oazy's own icons for common apps: All / None, then one chip per app.
func _custom_icons_rows(list: VBoxContainer) -> void:
	var row := _row(list, "Oazy app icons", "Swap the stock icons of everyday apps for Oazy-style ones on the taskbar and in Start.")
	var chips: Array[Button] = []
	var sync := func() -> void:
		var on: Array = Settings.get_value("custom_icons")
		for c in chips:
			c.set_pressed_no_signal(on.has(str(c.get_meta("key"))))
	for pair in [["All", true], ["None", false]]:
		var b := FxButton.make(str(pair[0]), "", FxButton.Style.GHOST, 38)
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


## Mouse pointer themes: Off plus every theme, as preview cards.
func _pointer_rows(list: VBoxContainer) -> void:
	var desc := "Oazy's pointers follow you into every app while Oazy is running. Off keeps Windows' own." if App.is_windows() else "Oazy's own pointers, from the arrow to the busy spinner."
	var row := _row(list, "Mouse pointer", desc)
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


func _button_row(list: VBoxContainer, title: String, desc: String, label_text: String, icon_name: String, cb: Callable) -> FxButton:
	var row := _row(list, title, desc)
	var b := FxButton.make(label_text, icon_name, FxButton.Style.GHOST, 42)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(cb)
	row.add_child(b)
	return b


func _swatch_row(list: VBoxContainer) -> void:
	var row := _row(list, "Accent colour", "Tints the Start orb, highlights and a soft glow in the wallpaper.")
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


func _light_row(list: VBoxContainer) -> void:
	var row := _row(list, "Wallpaper light", "Auto follows the time of day, from dawn to night.")
	var box := Kit.hbox(6)
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(box)
	for spec in [["auto", "Auto"], ["dawn", "Dawn"], ["day", "Day"], ["dusk", "Dusk"], ["night", "Night"]]:
		var b := FxButton.make(spec[1], "", FxButton.Style.CHIP, 34)
		b.add_theme_font_size_override("font_size", 13)
		b.pressed.connect(func() -> void:
			Settings.set_value("wallpaper_light", spec[0])
			_sync_lights()
		)
		box.add_child(b)
		_lights[spec[0]] = b
	_sync_lights()


func _sync_lights() -> void:
	for key in _lights.keys():
		var b: FxButton = _lights[key]
		b.selected = Settings.get_value("wallpaper_light") == key


func _name_row(list: VBoxContainer) -> void:
	var row := _row(list, "Your name", "Used for the greeting on your desktop.")
	var edit := LineEdit.new()
	edit.placeholder_text = App.user_name() if App.user_name() != "" else "Your name"
	edit.text = str(Settings.get_value("user_name"))
	edit.custom_minimum_size = Vector2(220, 42)
	edit.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	edit.text_changed.connect(func(t: String) -> void: Settings.set_value("user_name", t.strip_edges()))
	row.add_child(edit)


func _effects_row(list: VBoxContainer) -> void:
	var row := _row(list, "Visual effects", "Eco calms the animations and caps the frame rate to save power.")
	var box := Kit.hbox(8)
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(box)
	for spec in [["high", "Stunning"], ["eco", "Eco"]]:
		var b := FxButton.make(spec[1], "", FxButton.Style.CHIP, 38)
		b.pressed.connect(func() -> void:
			Settings.set_value("effects", spec[0])
			App.refresh_fps()
			GlassPanel.refresh_all(get_tree())
			_sync_effects()
		)
		box.add_child(b)
		_effects[spec[0]] = b
	_sync_effects()


func _sync_effects() -> void:
	for key in _effects.keys():
		var b: FxButton = _effects[key]
		b.selected = Settings.get_value("effects") == key


func _slider_row(list: VBoxContainer, title: String, key: String) -> void:
	var row := _row(list, title, "")
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


# --- Live state -----------------------------------------------------------------

func _sync_scan() -> void:
	if _scan_btn:
		_scan_btn.disabled = Library.importing
		_scan_btn.text = "Scanning…" if Library.importing else "Scan now"


func _sync_update() -> void:
	if _update_status == null:
		return
	var icon := "check"
	var color := App.SUCCESS
	var btn := "Check for updates"
	match Updater.state:
		&"checking":
			_update_status.text = "Checking for updates…"
			icon = "refresh"
			color = App.TEXT_DIM
		&"current":
			_update_status.text = "You're up to date"
		&"available":
			_update_status.text = "Version %s is available" % Updater.latest.get("version", "?")
			icon = "sparkles"
			color = App.accent
			btn = "See what's new"
		&"downloading":
			_update_status.text = "Downloading version %s…" % Updater.latest.get("version", "?")
			icon = "download"
			color = App.accent
			btn = "Show progress"
		&"ready":
			_update_status.text = "Version %s is ready to install" % Updater.latest.get("version", "?")
			icon = "download"
			color = App.accent
			btn = "Restart to update"
		&"error":
			_update_status.text = Updater.error_text
			icon = "alert"
			color = App.WARNING
			btn = "Try again"
		_:
			_update_status.text = "Updates come straight from GitHub"
			icon = "info"
			color = App.TEXT_DIM
	_update_icon.texture = Icons.tex(icon, 16, color)
	_update_btn.text = btn
	_update_btn.disabled = Updater.state == &"checking"


func _on_update_button() -> void:
	match Updater.state:
		&"available", &"downloading", &"ready":
			main.show_update()
		_:
			Updater.check()
