extends Control
## Root of Oazy, a desktop shell: wallpaper, desktop widgets, Oazy's own
## windows, the taskbar, Start and every overlay. Also owns the window mode,
## launching, context menus and keyboard shortcuts.
##
## The main window is the desktop itself; everything above it lives in layers
## (see Shell), which are separate OS windows when Oazy is your desktop.

const GRIP := 6.0
const APP_TITLES := {&"library": "Library", &"settings": "Settings", &"cleaner": "Cleaner"}
const APP_SIZES := {&"library": Vector2(1260, 780), &"settings": Vector2(1120, 820), &"cleaner": Vector2(1180, 800)}

## The update version a toast already announced.
var _announced_update := ""
var wallpaper: Wallpaper
var desktop: Desktop
var layer: WindowLayer
var taskbar: Taskbar
var start: StartPanel
var preview: TaskPreview
var switcher: Switcher
var overlay_layer: Control
var toasts: Toasts
var loaded := false

var _chrome: Control
var _max_btn: FxButton
var _menu: PopupMenu
var _menu_ref := ""
var _desk_menu: PopupMenu
var _grips: Array[Control] = []
var _launching := false
var _peeked: Array[ShellWindow] = []
var _fg_at_start := 0
var _menus: Control
var quick: QuickSettings
var calendar: CalendarFlyout
var weather: WeatherFlyout
var network: NetworkFlyout


func _ready() -> void:
	get_tree().root.theme = Kit.build_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	App.set_accent(Color(str(Settings.get_value("accent"))))
	Shell.setup(self, Shell.wanted(), Taskbar.RESERVE)
	_setup_window()
	Shell.sync_metrics()

	wallpaper = Wallpaper.new()
	add_child(wallpaper)
	desktop = Desktop.new()
	desktop.main = self
	add_child(desktop)
	layer = WindowLayer.new()
	layer.main = self
	layer.reserved_bottom = Taskbar.RESERVE + 4.0
	Shell.layer("apps", {"focus": true, "work": true}).add_child(layer)
	preview = TaskPreview.new()
	preview.main = self
	taskbar = Taskbar.new()
	taskbar.main = self
	taskbar.layer = layer
	taskbar.preview = preview
	var bar := Shell.layer("bar", {"top": true})
	bar.add_child(taskbar)
	bar.add_child(preview)
	start = StartPanel.new()
	start.main = self
	var start_layer := Shell.layer("start", {"top": true, "focus": true, "work": true})
	start_layer.add_child(start)
	quick = QuickSettings.new()
	start_layer.add_child(quick)
	calendar = CalendarFlyout.new()
	start_layer.add_child(calendar)
	taskbar.attach_flyouts(quick, calendar)
	weather = WeatherFlyout.new()
	start_layer.add_child(weather)
	taskbar.attach_weather(weather)
	network = NetworkFlyout.new()
	start_layer.add_child(network)
	taskbar.attach_network(network)
	taskbar.start_pressed.connect(start.toggle)
	taskbar.search_pressed.connect(func() -> void: start.open())
	start.visibility_changed_to.connect(func(o: bool) -> void:
		taskbar.orb.open = o
		if o:
			_fg_at_start = Host.foreground
		desktop.dim(o)
		if o:
			preview.hide_preview()
			quick.close()
			calendar.close()
			weather.close()
			network.close()
	)

	_menus = Shell.layer("overlay", {"top": true, "focus": true, "work": true})
	overlay_layer = OverlayLayer.new()
	_menus.add_child(overlay_layer)
	toasts = Toasts.new()
	Shell.layer("toasts", {"top": true}).add_child(toasts)
	switcher = Switcher.new()
	switcher.main = self
	Shell.layer("switcher", {"top": true}).add_child(switcher)

	# Menus share the dialog layer so they open above other apps too.
	_menu = PopupMenu.new()
	_menu.id_pressed.connect(_on_menu)
	_menus.add_child(_menu)
	_desk_menu = PopupMenu.new()
	_desk_menu.id_pressed.connect(_on_desk_menu)
	_menus.add_child(_desk_menu)

	if not Shell.native:
		_build_window_chrome()
		_add_resize_grips()
	else:
		# The taskbar slides in once Oazy has loaded.
		Shell.set_layer_visible("bar", false)

	App.toast_requested.connect(func(text: String, kind: StringName) -> void: toasts.show_toast(text, kind))
	App.open_page.connect(func(page: StringName) -> void: open_app(page))
	App.launch_requested.connect(launch)
	Library.import_finished.connect(_on_import_finished)
	Updater.state_changed.connect(_on_update_state)
	Host.hotkey.connect(_on_hotkey)
	Host.desktop_hotkey.connect(show_desktop)
	Host.switch_key.connect(switcher.handle_key)
	Host.status_changed.connect(_on_host_status)
	Browser.runtime_missing.connect(_on_browser_runtime_missing)
	Host.fullscreen_changed.connect(_on_fullscreen_app)
	Settings.changed.connect(_on_setting)
	get_window().files_dropped.connect(_on_files_dropped)
	get_window().size_changed.connect(_sync_window_ui)
	get_window().size_changed.connect(Shell.sync_metrics)
	if Shell.native:
		get_tree().auto_accept_quit = false
		# Start closes when you go anywhere else, even if Windows never let
		# it take focus in the first place.
		get_window().focus_entered.connect(_close_start_elsewhere)
		Shell.surface_of(layer).focus_entered.connect(_close_start_elsewhere)
		Host.windows_changed.connect(func() -> void:
			# Only when you actually switched to another app since Start
			# opened, not on any window event while Windows is still
			# handing focus over.
			if not Host.self_foreground and Host.foreground != _fg_at_start:
				_close_start_elsewhere()
		)
	get_window().focus_entered.connect(func() -> void:
		if not Host.available:
			Host.self_foreground = true
		taskbar.queue_rebuild()
		if loaded:
			Shell.precreate_layers()
	)

	if not App.smoke_test or App.is_windows():
		Host.start()
	if App.is_windows() and not App.smoke_test and not Settings.get_value("claude_checked"):
		WorkerThreadPool.add_task(func() -> void: _add_claude_code.call_deferred(Library.detect_claude_code()), false, "Find Claude Code")

	var loading := LoadingScreen.new()
	add_child(loading)
	loading.finished_early.connect(_on_loaded)
	loading.run()


# --- Window mode -------------------------------------------------------------------------

func _setup_window() -> void:
	var w := get_window()
	w.min_size = Vector2i(1100, 680)
	if Shell.native:
		# The desktop: the whole primary screen, under every other window.
		var scr := DisplayServer.get_primary_screen()
		w.mode = Window.MODE_WINDOWED
		w.borderless = true
		w.current_screen = scr
		w.position = DisplayServer.screen_get_position(scr)
		w.size = DisplayServer.screen_get_size(scr)
		return
	if App.smoke_test:
		return
	var usable := DisplayServer.screen_get_usable_rect(w.current_screen)
	var saved: Variant = Settings.get_value("window_rect")
	if saved is Array and saved.size() == 4:
		var r := Rect2i(int(saved[0]), int(saved[1]), int(saved[2]), int(saved[3]))
		if usable.grow(40).encloses(r) and r.size.x >= w.min_size.x:
			w.size = r.size
			w.position = r.position
	elif w.size.x > usable.size.x * 0.92 or w.size.y > usable.size.y * 0.92:
		var h := int(usable.size.y * 0.86)
		var size_fit := Vector2i(mini(int(h * 16.0 / 9.0), int(usable.size.x * 0.92)), h)
		w.size = size_fit
		w.position = usable.position + (usable.size - size_fit) / 2
	if Settings.get_value("shell_fullscreen"):
		w.mode = Window.MODE_FULLSCREEN


func apply_window_mode(fullscreen: bool) -> void:
	if App.smoke_test or Shell.native:
		return
	var w := get_window()
	if fullscreen:
		if w.mode == Window.MODE_WINDOWED:
			Settings.set_value("window_rect", [w.position.x, w.position.y, w.size.x, w.size.y])
		w.mode = Window.MODE_FULLSCREEN
	else:
		w.mode = Window.MODE_WINDOWED
	_sync_window_ui()


func toggle_fullscreen() -> void:
	if Shell.native:
		return
	var full := get_window().mode != Window.MODE_FULLSCREEN
	Settings.set_value("shell_fullscreen", full)
	apply_window_mode(full)


func _build_window_chrome() -> void:
	# Only shown when Oazy runs in a window: a drag strip and the usual buttons.
	_chrome = Control.new()
	_chrome.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_chrome.offset_bottom = 34
	_chrome.mouse_filter = Control.MOUSE_FILTER_STOP
	_chrome.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			if e.double_click:
				toggle_fullscreen()
			elif DisplayServer.has_method("window_start_drag"):
				DisplayServer.call("window_start_drag")
	)
	add_child(_chrome)
	var row := Kit.hbox(2)
	row.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	row.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	row.offset_right = -8
	row.offset_top = 4
	_chrome.add_child(row)
	var min_btn := FxButton.icon_only("minimize", "Minimise", 16, 28)
	min_btn.pressed.connect(func() -> void: get_window().mode = Window.MODE_MINIMIZED)
	_max_btn = FxButton.icon_only("maximize", "Fullscreen", 14, 28)
	_max_btn.pressed.connect(toggle_fullscreen)
	var close_btn := FxButton.icon_only("close", "Close Oazy", 16, 28)
	close_btn.add_theme_stylebox_override("hover", Kit.box(Color(1.0, 0.36, 0.42, 0.9), 999))
	close_btn.pressed.connect(quit)
	for b in [min_btn, _max_btn, close_btn]:
		b.focus_mode = Control.FOCUS_NONE
		b.hover_scale = 1.0
		row.add_child(b)


func _add_resize_grips() -> void:
	if not DisplayServer.has_method("window_start_resize"):
		return
	# Edge index matches DisplayServer.WindowResizeEdge.
	var specs := [
		[0, Control.PRESET_TOP_LEFT, Control.CURSOR_FDIAGSIZE, Vector2(GRIP * 2, GRIP * 2)],
		[1, Control.PRESET_TOP_WIDE, Control.CURSOR_VSIZE, Vector2(0, GRIP)],
		[2, Control.PRESET_TOP_RIGHT, Control.CURSOR_BDIAGSIZE, Vector2(GRIP * 2, GRIP * 2)],
		[3, Control.PRESET_LEFT_WIDE, Control.CURSOR_HSIZE, Vector2(GRIP, 0)],
		[4, Control.PRESET_RIGHT_WIDE, Control.CURSOR_HSIZE, Vector2(GRIP, 0)],
		[5, Control.PRESET_BOTTOM_LEFT, Control.CURSOR_BDIAGSIZE, Vector2(GRIP * 2, GRIP * 2)],
		[6, Control.PRESET_BOTTOM_WIDE, Control.CURSOR_VSIZE, Vector2(0, GRIP)],
		[7, Control.PRESET_BOTTOM_RIGHT, Control.CURSOR_FDIAGSIZE, Vector2(GRIP * 2, GRIP * 2)],
	]
	for s in specs:
		var g := Control.new()
		g.mouse_default_cursor_shape = s[2]
		g.mouse_filter = Control.MOUSE_FILTER_STOP
		g.custom_minimum_size = s[3]
		g.set_anchors_and_offsets_preset(s[1], Control.PRESET_MODE_MINSIZE)
		var edge: int = s[0]
		g.gui_input.connect(func(e: InputEvent) -> void:
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				DisplayServer.call("window_start_resize", edge)
		)
		add_child(g)
		_grips.append(g)
	_sync_window_ui()


func _sync_window_ui() -> void:
	var windowed := get_window().mode == Window.MODE_WINDOWED and not App.smoke_test and not Shell.native
	for g in _grips:
		g.visible = windowed
	if _chrome:
		_chrome.visible = windowed


func _exit_tree() -> void:
	var w := get_window()
	if w and w.mode == Window.MODE_WINDOWED and not App.smoke_test and not Shell.native:
		Settings.set_value("window_rect", [w.position.x, w.position.y, w.size.x, w.size.y])
	Settings.save()


func quit() -> void:
	Settings.save()
	Host.shutdown()
	get_tree().quit()


# --- Oazy's own apps -------------------------------------------------------------------------

func open_app(name: StringName) -> ShellWindow:
	if not APP_TITLES.has(name):
		return null
	start.close()
	var ref := "oazy:" + String(name)
	var existing := layer.find(ref)
	if existing:
		focus_shell_window(existing)
		return existing
	var win := ShellWindow.new().setup(ref, APP_TITLES[name])
	layer.open_window(win, APP_SIZES[name])
	var content: Control
	match name:
		&"library":
			var lib := LibraryApp.new()
			lib.main = self
			content = lib
		&"settings":
			var st := SettingsApp.new()
			st.main = self
			content = st
		&"cleaner":
			var cl := CleanerApp.new()
			cl.main = self
			content = cl
	win.body.add_child(content)
	_bring_windows_forward()
	return win


func focus_shell_window(win: ShellWindow) -> void:
	_bring_windows_forward()
	layer.activate(win)


func toggle_shell_window(win: ShellWindow) -> void:
	if win.minimized:
		focus_shell_window(win)
	elif win.active and windows_in_front():
		win.minimize()
	else:
		focus_shell_window(win)


func _close_start_elsewhere() -> void:
	var s := Shell.surface_of(start)
	if start.is_open and s and not s.just_shown(400) and not s.has_focus():
		start.close()


## Oazy's own windows are what you're using right now.
func windows_in_front() -> bool:
	var s := Shell.surface_of(layer)
	if s:
		return s.has_focus()
	return Host.self_foreground


func _bring_windows_forward() -> void:
	if Shell.native:
		Shell.focus(layer)
	elif not Host.self_foreground:
		Host.go_home()


func focus_entry(id: String) -> void:
	var win := open_app(&"library")
	if win and win.body.get_child_count() > 0:
		var app: LibraryApp = win.body.get_child(0)
		app.show_entry(id)


func show_desktop() -> void:
	start.close()
	if Shell.native:
		# Every window steps aside (Oazy's and other apps'), and the next
		# click brings them back.
		var open: Array[ShellWindow] = []
		for w in layer.windows():
			if not w.minimized:
				open.append(w)
		if not open.is_empty():
			_peeked = open
			for w in open:
				w.minimize()
		else:
			for w in _peeked:
				if is_instance_valid(w):
					w.unminimize()
			_peeked.clear()
		Host.show_desktop()
		return
	var any_open := false
	for w in layer.windows():
		if not w.minimized:
			any_open = true
	if any_open:
		layer.minimize_all()
	else:
		for w in layer.windows():
			w.unminimize()
	if not Host.self_foreground:
		Host.go_home()


func modal_open() -> bool:
	return not get_tree().get_nodes_in_group("modal").is_empty()


# --- Actions -------------------------------------------------------------------------------

func launch(id: String) -> void:
	if _launching or not Library.has_entry(id):
		return
	start.close()
	var e := Library.get_entry(id)
	if e["kind"] != "game":
		var ok := Library.launch(id) if not App.smoke_test else true
		var btn := taskbar.button_for("lib:" + id)
		if ok and btn and btn.window_count() == 0:
			btn.start_launching()
		Sfx.play(&"select")
		return
	_launching = true
	var overlay := LaunchOverlay.new().setup(id)
	overlay_layer.add_child(overlay)
	overlay.finished.connect(func() -> void: _launching = false)
	Sfx.play(&"launch")
	await get_tree().create_timer(0.5).timeout
	var ok := Library.launch(id) if not App.smoke_test else true
	if is_instance_valid(overlay):
		if ok:
			overlay.success()
		else:
			overlay.fail()


func open_add(prefill: Dictionary) -> void:
	start.close()
	var d := EditDialog.new()
	d.prefill = prefill.duplicate()
	overlay_layer.add_child(d)


func open_edit(id: String) -> void:
	var d := EditDialog.new()
	d.entry_id = id
	overlay_layer.add_child(d)


func confirm_remove(id: String) -> void:
	var e := Library.get_entry(id)
	if e.is_empty():
		return
	var d := ConfirmDialog.new()
	d.title = "Remove %s?" % e["name"]
	d.message = "It disappears from Oazy only. Nothing is uninstalled or deleted from your PC."
	d.confirm_text = "Remove"
	d.danger = true
	d.on_confirm = func() -> void:
		Catalog.remove_from_library(id)
		Art.forget(id)
		App.toast("Removed %s" % e["name"])
	overlay_layer.add_child(d)


func confirm_power(kind: String) -> void:
	var d := ConfirmDialog.new()
	d.title = "Restart your PC?" if kind == "restart" else "Shut down your PC?"
	d.message = "Save anything you're working on first. Open apps will be closed."
	d.confirm_text = "Restart" if kind == "restart" else "Shut down"
	d.danger = true
	d.on_confirm = func() -> void:
		if App.is_windows() and not App.smoke_test:
			OS.create_process("shutdown", ["/r" if kind == "restart" else "/s", "/t", "0"])
	overlay_layer.add_child(d)


func scan_stores() -> void:
	if Library.importing:
		return
	if not App.is_windows():
		App.toast("Scanning for games works on Windows", &"info")
		return
	Library.import_stores()
	App.toast("Looking for Steam, Epic Games and GOG games…")


## Pick installed apps to bring into the library.
func find_apps() -> void:
	start.close()
	for c in overlay_layer.get_children():
		if c is FindAppsDialog:
			return
	if Host.available:
		Catalog.refresh_apps()
	overlay_layer.add_child(FindAppsDialog.new())


func show_update() -> void:
	for c in overlay_layer.get_children():
		if c is UpdateOverlay:
			return
	if Updater.latest.is_empty():
		Updater.check()
		App.toast("Checking for updates…")
		return
	overlay_layer.add_child(UpdateOverlay.new())
	# Make sure what's offered is still the newest; the screen follows along.
	if Updater.state in [&"available", &"ready"] and Time.get_unix_time_from_system() - Updater.last_checked > 120:
		Updater.check()


func show_patch_notes() -> void:
	var d := NotesDialog.new()
	d.title = "Patch notes"
	d.subtitle = "Everything that changed, version by version."
	d.history = true
	overlay_layer.add_child(d)


func show_shortcuts() -> void:
	start.close()
	overlay_layer.add_child(ShortcutsSheet.dialog())


func set_autostart(on: bool) -> void:
	if not (App.is_windows() and App.is_packaged()):
		App.toast("Start with Windows works in the installed app")
		return
	var key := "HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Run"
	var exe := OS.get_executable_path().replace("/", "\\")
	var out := []
	var code := 0
	if on:
		code = OS.execute("reg", ["add", key, "/v", "OazyLauncher", "/t", "REG_SZ", "/d", exe, "/f"], out)
	else:
		code = OS.execute("reg", ["delete", key, "/v", "OazyLauncher", "/f"], out)
	if code != 0 and on:
		App.toast("Couldn't register Oazy to start with Windows", &"error")


func _add_claude_code(fields: Dictionary) -> void:
	Settings.set_value("claude_checked", true)
	if fields.is_empty():
		return
	for e in Library.entries:
		if str(e["name"]) == "Claude Code":
			return
	var id := Library.add_entry(fields)
	Catalog.set_pinned("lib:" + id, true)


# --- Context menus -------------------------------------------------------------------------

func show_entry_menu(id: String, at: Vector2) -> void:
	show_ref_menu("lib:" + id, at)


## The right-click menu for anything you can open: a game, an app, one of
## Oazy's own. Same actions, same order, same words everywhere.
func show_ref_menu(ref: String, at: Vector2) -> void:
	ref = Catalog.canonical(ref)
	if ref.begins_with("lib:") and not Library.has_entry(ref.substr(4)):
		return
	_menu_ref = ref
	_menu.clear()
	add_ref_actions(_menu, ref)
	popup_menu(_menu, at)
	Sfx.play(&"open")


## Opens one of the shared menus at `at` (any layer's coordinates: they all
## match), kept on screen and above the taskbar.
func popup_menu(menu: PopupMenu, at: Vector2) -> void:
	menu.reset_size()
	var vp := Shell.view_size()
	if Shell.native:
		vp.y -= Shell.reserve
	var pos := Vector2i(at)
	pos.x = clampi(pos.x, 8, int(vp.x) - menu.size.x - 8)
	pos.y = clampi(pos.y, 8, int(vp.y) - menu.size.y - 8)
	menu.position = pos
	Shell.popup(menu)


func _on_menu(item: int) -> void:
	run_ref_action(_menu_ref, item)


# One set of actions for every menu (here, Start's and the taskbar's), so
# a game offers the same things wherever you right-click it. Callers can add
# their own items around them with ids below ACT_OPEN.
const ACT_OPEN := 100
const ACT_DETAILS := 101
const ACT_FAVORITE := 102
const ACT_PIN := 103
const ACT_EDIT := 104
const ACT_FOLDER := 105
const ACT_LIBRARY := 106


## Adds the shared actions for `ref` to `menu`: Play/Open, Details, favourite,
## pin, then the Library's own (Edit, Show in folder, Add to / Remove from).
## `with_open` false leaves Open to the caller (the taskbar's New window).
static func add_ref_actions(menu: PopupMenu, ref: String, with_open: bool = true) -> void:
	ref = Catalog.canonical(ref)
	var e := Library.get_entry(ref.substr(4)) if ref.begins_with("lib:") else {}
	if with_open:
		menu.add_icon_item(Icons.tex("play", 18), "Play" if str(e.get("kind", "")) == "game" else "Open", ACT_OPEN)
	if not e.is_empty():
		menu.add_icon_item(Icons.tex("info", 18), "Details", ACT_DETAILS)
	if Catalog.can_favorite(ref):
		var fav := Catalog.is_favorite(ref)
		menu.add_icon_item(Icons.tex("heart_fill" if fav else "heart", 18), "Remove from favourites" if fav else "Add to favourites", ACT_FAVORITE)
	var pinned := Catalog.is_pinned(ref)
	menu.add_icon_item(Icons.tex("unpin" if pinned else "pin", 18), "Unpin from taskbar" if pinned else "Pin to taskbar", ACT_PIN)
	if not e.is_empty():
		menu.add_separator()
		menu.add_icon_item(Icons.tex("edit", 18), "Edit details", ACT_EDIT)
		var path := str(e["path"])
		if path != "" and not path.contains("://") and (FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path)):
			menu.add_icon_item(Icons.tex("folder", 18), "Show in folder", ACT_FOLDER)
		menu.add_separator()
		menu.add_icon_item(Icons.tex("trash", 18, App.DANGER.lightened(0.2)), "Remove from Library", ACT_LIBRARY)
	elif Catalog.can_add_to_library(ref):
		menu.add_separator()
		menu.add_icon_item(Icons.tex("grid", 18), "Add to Library", ACT_LIBRARY)


## Runs one of add_ref_actions' items. False for ids that aren't one.
func run_ref_action(ref: String, act: int) -> bool:
	ref = Catalog.canonical(ref)
	var id := ref.substr(4) if ref.begins_with("lib:") else ""
	match act:
		ACT_OPEN:
			if id != "":
				launch(id)
			else:
				Catalog.launch(ref)
		ACT_DETAILS:
			focus_entry(id)
		ACT_FAVORITE:
			toggle_favorite(ref)
		ACT_PIN:
			Catalog.set_pinned(ref, not Catalog.is_pinned(ref))
		ACT_EDIT:
			open_edit(id)
		ACT_FOLDER:
			OS.shell_show_in_file_manager(str(Library.get_entry(id).get("path", "")))
		ACT_LIBRARY:
			toggle_library(ref)
		_:
			return false
	return true


func toggle_library(ref: String) -> void:
	if ref.begins_with("lib:"):
		confirm_remove(ref.substr(4))
		return
	var name := str(Catalog.item(ref).get("name", ""))
	if Catalog.add_to_library(ref) != "":
		App.toast("Added %s to your Library" % name, &"success")


func toggle_favorite(ref: String) -> void:
	var on := Catalog.toggle_favorite(ref)
	var name := str(Catalog.item(ref).get("name", ""))
	App.toast(("Added %s to favourites" if on else "Removed %s from favourites") % name, &"success" if on else &"info")


func _show_desktop_menu(at: Vector2) -> void:
	_desk_menu.clear()
	_desk_menu.add_icon_item(Icons.tex("plus", 18), "Add a game or app", 0)
	_desk_menu.add_icon_item(Icons.tex("grid", 18), "Open Library", 1)
	_desk_menu.add_separator()
	_desk_menu.add_icon_item(Icons.tex("palette", 18), "Personalise", 2)
	_desk_menu.add_icon_item(Icons.tex("keyboard", 18), "Keyboard shortcuts", 4)
	if not Shell.native:
		_desk_menu.add_icon_item(Icons.tex("desktop", 18), "Fullscreen" if get_window().mode != Window.MODE_FULLSCREEN else "Run in a window", 3)
	popup_menu(_desk_menu, at)
	Sfx.play(&"open")


func _on_desk_menu(item: int) -> void:
	match item:
		0:
			open_add({})
		1:
			open_app(&"library")
		2:
			open_app(&"settings")
		3:
			toggle_fullscreen()
		4:
			show_shortcuts()


# --- Events ----------------------------------------------------------------------------------

func _on_loaded() -> void:
	loaded = true
	Shell.set_layer_visible("bar", not Host.fullscreen_app)
	desktop.intro()
	taskbar.intro()
	Sfx.play(&"open", 0.8)
	Shell.precreate_layers()
	_post_update_welcome()
	Warmup.run(self)


func _post_update_welcome() -> void:
	var pending := str(Settings.get_value("pending_update_version"))
	var last := str(Settings.get_value("last_seen_version"))
	if pending != "" and Semver.compare(pending, App.version) == 0:
		var d := UpdateWelcome.new()
		d.version = App.version
		d.from_version = str(Settings.get_value("pending_update_from"))
		d.markdown = str(Settings.get_value("pending_update_notes"))
		d.show_all = show_patch_notes
		overlay_layer.add_child(d)
		Settings.set_value("pending_update_version", "")
		Settings.set_value("pending_update_notes", "")
		Settings.set_value("pending_update_from", "")
	elif not Settings.get_value("seen_shell_intro") and not App.smoke_test:
		var d2 := NotesDialog.new()
		d2.title = "Welcome home"
		d2.subtitle = "Oazy is now your desktop. Here's the quick tour."
		d2.markdown = "### Your PC, one calm place\n- **Start** (the orb, bottom left) opens anything: apps, games, folders and the web. Or just start typing on the desktop.\n- **The taskbar** shows everything that's open, Chrome, Claude Code, your games, with live previews when you hover.\n- **Press Ctrl + Alt + O** in any app to open Start, and **Ctrl + Alt + D** (or the desktop button on the taskbar) to get back to your desktop.\n- **Right-click** any app or game to add it to your favourites. They live on your desktop and at the top of Start."
		overlay_layer.add_child(d2)
	elif last != "" and last != App.version:
		toasts.show_toast("Updated to Oazy %s" % App.version, &"update", show_patch_notes)
	Settings.set_value("seen_shell_intro", true)
	Settings.set_value("last_seen_version", App.version)


func _on_import_finished(added: int, found: int) -> void:
	if added > 0:
		App.toast("Added %d %s to your library" % [added, "game" if added == 1 else "games"], &"success")
	elif found > 0:
		App.toast("Everything is already in your library")
	elif loaded:
		App.toast("No Steam, Epic or GOG games found. Add yours with + Add.")


func _on_update_state(state: StringName) -> void:
	# Rechecks find the same update again; only a new version is news.
	if state == &"available" and loaded and str(Updater.latest.get("version", "")) != _announced_update:
		_announced_update = str(Updater.latest.get("version", ""))
		toasts.show_toast("Oazy %s is available. See what's new" % Updater.latest.get("version", ""), &"update", show_update)


func _on_hotkey(was_foreground: bool) -> void:
	if was_foreground or Shell.native:
		# In shell mode Oazy never left: the hotkey just opens Start.
		start.toggle()
	else:
		Sfx.play(&"open", 1.1)


func _on_host_status(ok: bool) -> void:
	if ok and Shell.native:
		_enter_shell()
		if loaded:
			Shell.precreate_layers()
	if not ok and Host.failed and loaded and App.is_windows():
		App.toast("Oazy couldn't connect to Windows, so open apps won't show on the taskbar", &"error")


## Makes Oazy the desktop: Windows' own taskbar and desktop step aside and
## maximised apps stop above Oazy's taskbar.
func _enter_shell() -> void:
	var reserve := int(round(Shell.reserve * Shell.scale))
	Host.enter_shell(Host.self_hwnd, reserve, bool(Settings.get_value("hide_windows_taskbar")))
	_theme_apps()
	Host.set_switcher(bool(Settings.get_value("alt_tab")))


func _theme_apps() -> void:
	Host.theme_apps(bool(Settings.get_value("theme_app_windows")), App.accent.darkened(0.35), Color("0e1218"), App.TEXT)


func _on_setting(key: String, _value: Variant) -> void:
	if not Shell.native or not Host.available:
		return
	match key:
		"hide_windows_taskbar":
			Host.exit_shell()
			_enter_shell()
		"theme_app_windows", "accent":
			_theme_apps()
		"alt_tab":
			Host.set_switcher(bool(Settings.get_value("alt_tab")))


func _on_fullscreen_app(on: bool) -> void:
	# A game or video took the whole screen: get out of its way.
	if on:
		start.close()
		preview.hide_preview()
	if loaded:
		Shell.set_layer_visible("bar", not on)
	Shell.set_layer_visible("toasts", not on)
	App.refresh_fps()


func _on_files_dropped(files: PackedStringArray) -> void:
	if files.is_empty() or modal_open():
		return
	var path := files[0].replace("\\", "/")
	if DirAccess.dir_exists_absolute(path):
		App.toast("Drop a program or shortcut, not a folder", &"error")
		return
	open_add(Library.infer_from_path(path))


# --- Input -------------------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	# Clicking a window raises it; clicking the bare desktop deactivates them.
	# (In shell mode Oazy's windows have their own layer and handle this.)
	if Shell.native:
		return
	if event is InputEventMouseButton and event.pressed and loaded and not modal_open():
		var pos: Vector2 = event.position
		if taskbar.get_global_rect().has_point(pos) or (start.is_open and start.get_global_rect().has_point(pos)) or (preview.visible and preview.get_global_rect().has_point(pos)):
			return
		layer.press_at(pos)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT and not modal_open():
		_show_desktop_menu(event.position)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey:
		if handle_key(event):
			get_viewport().set_input_as_handled()
	elif event is InputEventJoypadButton and event.pressed and not modal_open():
		var j: InputEventJoypadButton = event
		if j.button_index == JOY_BUTTON_START or j.button_index == JOY_BUTTON_GUIDE:
			start.toggle()
		elif j.button_index == JOY_BUTTON_B and start.is_open:
			start.close()
		else:
			return
		get_viewport().set_input_as_handled()


## Oazy's keyboard shortcuts, from whichever layer has focus. True if used.
func handle_key(event: InputEvent, from: Window = null) -> bool:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return false
	var k: InputEventKey = event
	var win := layer.active_window()
	if Shell.native and start.is_open and not modal_open() and from != Shell.surface_of(start):
		start.forward_key(k)
		return true
	if k.keycode == KEY_F11 or (k.keycode == KEY_ENTER and k.alt_pressed):
		toggle_fullscreen()
	elif modal_open():
		return false
	elif k.keycode == KEY_F1 or (k.keycode == KEY_SLASH and k.ctrl_pressed):
		show_shortcuts()
	elif k.keycode == KEY_F and k.ctrl_pressed:
		start.open()
	elif k.keycode == KEY_L and k.ctrl_pressed:
		open_app(&"library")
	elif k.keycode == KEY_N and k.ctrl_pressed:
		open_add({})
	elif k.keycode == KEY_COMMA and k.ctrl_pressed:
		open_app(&"settings")
	elif k.keycode == KEY_W and k.ctrl_pressed and win:
		win.close()
	elif k.keycode == KEY_ESCAPE and win:
		win.minimize()
	elif (k.keycode == KEY_PAGEDOWN or k.keycode == KEY_PAGEUP) and get_viewport().gui_get_focus_owner() == null and (win == null or (Shell.native and not windows_in_front())):
		# Down to the desktop's second screen and back.
		desktop.page(1 if k.keycode == KEY_PAGEDOWN else -1)
	elif k.unicode > 32 and not k.ctrl_pressed and not k.alt_pressed and get_viewport().gui_get_focus_owner() == null and (win == null or (Shell.native and not windows_in_front())):
		# Type on the desktop to search, like Start.
		start.open(char(k.unicode))
	else:
		return false
	return true


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and Shell.native:
		# Alt+F4 on the desktop: ask before taking the desktop away.
		_confirm_quit()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if Shell.native and not Host.available and loaded:
			# Without the companion other apps can't make room for the taskbar,
			# so it only shows while Oazy is in use.
			Shell.set_layer_visible("bar", what == NOTIFICATION_APPLICATION_FOCUS_IN)


func _confirm_quit() -> void:
	for c in overlay_layer.get_children():
		if c is ConfirmDialog:
			return
	var d := ConfirmDialog.new()
	d.title = "Close Oazy?"
	d.message = "Your apps stay open, and the Windows taskbar and desktop come back."
	d.confirm_text = "Close Oazy"
	d.on_confirm = quit
	overlay_layer.add_child(d)


func _process(_delta: float) -> void:
	# The desktop never minimises (Win+D, Win+M).
	if Shell.native and get_window().mode == Window.MODE_MINIMIZED:
		get_window().mode = Window.MODE_WINDOWED


# --- Oazy Browser ------------------------------------------------------------------------------

func _on_browser_runtime_missing() -> void:
	var d := ConfirmDialog.new()
	d.title = "Oazy Browser needs WebView2"
	d.message = "It runs on Microsoft's Edge WebView2 Runtime, the same Chromium engine Windows 11 apps use, and this PC doesn't have it yet. It's a free, quick install from Microsoft."
	d.confirm_text = "Get WebView2"
	d.on_confirm = func() -> void:
		OS.shell_open(Browser.RUNTIME_URL)
	overlay_layer.add_child(d)
