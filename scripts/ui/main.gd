extends Control
## Root of the app: builds the interface, owns navigation, the borderless
## window, context menus, launching and every overlay.

const PAGE_ORDER := [&"home", &"library", &"settings"]
const GRIP := 6.0

var backdrop: Backdrop
var top_bar: TopBar
var home: HomePage
var library_page: LibraryPage
var settings_page: SettingsPage
var current_page: StringName = &"home"
var toasts: Toasts
var overlay_layer: Control
var loaded := false

var _pages := {}
var _page_host: Control
var _menu: PopupMenu
var _menu_id := ""
var _grips: Array[Control] = []
var _launching := false
var _page_tween: Tween


func _ready() -> void:
	get_tree().root.theme = Kit.build_theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_setup_window()

	backdrop = Backdrop.new()
	add_child(backdrop)

	_page_host = Control.new()
	_page_host.set_anchors_preset(Control.PRESET_FULL_RECT)
	_page_host.offset_top = TopBar.HEIGHT
	_page_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_page_host)
	home = HomePage.new()
	home.main = self
	library_page = LibraryPage.new()
	library_page.main = self
	settings_page = SettingsPage.new()
	settings_page.main = self
	_pages = {&"home": home, &"library": library_page, &"settings": settings_page}
	for key in PAGE_ORDER:
		var p: Control = _pages[key]
		_page_host.add_child(p)
		p.visible = key == &"home"

	top_bar = TopBar.new()
	add_child(top_bar)
	top_bar.tab_selected.connect(go)
	top_bar.settings_pressed.connect(func() -> void: go(&"home" if current_page == &"settings" else &"settings"))
	top_bar.update_pressed.connect(show_update)

	overlay_layer = Control.new()
	overlay_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay_layer)

	toasts = Toasts.new()
	add_child(toasts)

	_menu = PopupMenu.new()
	_menu.id_pressed.connect(_on_menu)
	add_child(_menu)

	_add_resize_grips()

	App.toast_requested.connect(func(text: String, kind: StringName) -> void: toasts.show_toast(text, kind))
	Library.import_finished.connect(_on_import_finished)
	Updater.state_changed.connect(_on_update_state)
	get_window().files_dropped.connect(_on_files_dropped)
	get_window().size_changed.connect(_sync_grips)

	var loading := LoadingScreen.new()
	add_child(loading)
	loading.finished_early.connect(_on_loaded)
	loading.run()


# --- Window ----------------------------------------------------------------------

func _setup_window() -> void:
	var w := get_window()
	w.min_size = Vector2i(1080, 640)
	if App.smoke_test:
		return
	var screen := w.current_screen
	var usable := DisplayServer.screen_get_usable_rect(screen)
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
	if Settings.get_value("start_fullscreen"):
		w.mode = Window.MODE_FULLSCREEN


func toggle_fullscreen() -> void:
	var w := get_window()
	w.mode = Window.MODE_WINDOWED if w.mode == Window.MODE_FULLSCREEN else Window.MODE_FULLSCREEN
	_sync_grips()


func _add_resize_grips() -> void:
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
	if not DisplayServer.has_method("window_start_resize"):
		return
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
	_sync_grips()


func _sync_grips() -> void:
	var windowed := get_window().mode == Window.MODE_WINDOWED
	for g in _grips:
		g.visible = windowed


func _exit_tree() -> void:
	var w := get_window()
	if w and w.mode == Window.MODE_WINDOWED and not App.smoke_test:
		Settings.set_value("window_rect", [w.position.x, w.position.y, w.size.x, w.size.y])
	Settings.save()


# --- Navigation ----------------------------------------------------------------------

func go(page: StringName) -> void:
	if page == current_page or not _pages.has(page):
		return
	var old: Control = _pages[current_page]
	var fresh: Control = _pages[page]
	var dir := signf(PAGE_ORDER.find(page) - PAGE_ORDER.find(current_page))
	current_page = page
	top_bar.select(page)
	Sfx.play(&"move", 0.9)
	if _page_tween and _page_tween.is_valid():
		_page_tween.kill()
	for p in _pages.values():
		if p != old and p != fresh:
			p.visible = false
	fresh.visible = true
	fresh.modulate.a = 0.0
	fresh.position.x = 48.0 * dir
	old.position.x = 0.0
	_page_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	_page_tween.tween_property(old, "modulate:a", 0.0, 0.18)
	_page_tween.tween_property(old, "position:x", -32.0 * dir, 0.3)
	_page_tween.tween_property(fresh, "modulate:a", 1.0, 0.4).set_delay(0.06)
	_page_tween.tween_property(fresh, "position:x", 0.0, 0.5).set_delay(0.06)
	_page_tween.chain().tween_callback(func() -> void:
		old.visible = false
		old.position.x = 0.0
	)
	get_viewport().gui_release_focus()
	if fresh.has_method("on_shown"):
		fresh.on_shown()
	if page == &"home":
		home._apply_hero()
	else:
		backdrop.set_hero(null)


func focus_entry(id: String) -> void:
	go(&"home")
	home.select_id(id)


func modal_open() -> bool:
	return not get_tree().get_nodes_in_group("modal").is_empty()


# --- Actions -------------------------------------------------------------------------

func launch(id: String) -> void:
	if _launching or not Library.has_entry(id):
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
	var d := EditDialog.new()
	d.prefill = prefill.duplicate()
	d.on_saved = func(id: String) -> void: focus_entry(id)
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
		Library.remove_entry(id)
		Art.forget(id)
		App.toast("Removed %s" % e["name"])
	overlay_layer.add_child(d)


func scan_stores() -> void:
	if Library.importing:
		return
	if not App.is_windows():
		App.toast("Scanning for games works on Windows", &"info")
		return
	Library.import_stores()
	App.toast("Looking for Steam, Epic Games and GOG games…")


func show_update() -> void:
	for c in overlay_layer.get_children():
		if c is UpdateOverlay:
			return
	if Updater.latest.is_empty():
		Updater.check()
		App.toast("Checking for updates…")
		return
	overlay_layer.add_child(UpdateOverlay.new())


func show_patch_notes() -> void:
	var d := NotesDialog.new()
	d.title = "Patch notes"
	d.subtitle = "Everything that changed, version by version."
	d.history = true
	overlay_layer.add_child(d)


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


# --- Context menu --------------------------------------------------------------------

func show_entry_menu(id: String, at: Vector2) -> void:
	var e := Library.get_entry(id)
	if e.is_empty():
		return
	_menu_id = id
	_menu.clear()
	var is_game: bool = e["kind"] == "game"
	_menu.add_icon_item(Icons.tex("play", 18), "Play" if is_game else "Open", 0)
	_menu.add_icon_item(Icons.tex("heart_fill" if e["favorite"] else "heart", 18), "Remove from favourites" if e["favorite"] else "Add to favourites", 1)
	_menu.add_separator()
	_menu.add_icon_item(Icons.tex("edit", 18), "Edit details", 2)
	var path := str(e["path"])
	if path != "" and not path.contains("://") and (FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path)):
		_menu.add_icon_item(Icons.tex("folder", 18), "Show in folder", 3)
	_menu.add_separator()
	_menu.add_icon_item(Icons.tex("trash", 18, App.DANGER.lightened(0.2)), "Remove from library", 4)
	_menu.reset_size()
	var pos := Vector2i(at)
	var vp := get_viewport_rect().size
	pos.x = mini(pos.x, int(vp.x) - _menu.size.x - 8)
	pos.y = mini(pos.y, int(vp.y) - _menu.size.y - 8)
	_menu.position = pos
	_menu.popup()
	Sfx.play(&"open")


func _on_menu(item: int) -> void:
	var id := _menu_id
	var e := Library.get_entry(id)
	if e.is_empty():
		return
	match item:
		0:
			launch(id)
		1:
			Library.toggle_favorite(id)
		2:
			open_edit(id)
		3:
			OS.shell_show_in_file_manager(str(e["path"]))
		4:
			confirm_remove(id)


# --- Events ----------------------------------------------------------------------------

func _on_loaded() -> void:
	loaded = true
	home.intro()
	Sfx.play(&"open", 0.8)
	_post_update_welcome()


func _post_update_welcome() -> void:
	var pending := str(Settings.get_value("pending_update_version"))
	var last := str(Settings.get_value("last_seen_version"))
	if pending != "" and Semver.compare(pending, App.version) == 0:
		var d := NotesDialog.new()
		d.title = "Welcome to Oazy %s" % App.version
		d.subtitle = "The update went smoothly. Here's what's new."
		d.markdown = str(Settings.get_value("pending_update_notes"))
		overlay_layer.add_child(d)
		Settings.set_value("pending_update_version", "")
		Settings.set_value("pending_update_notes", "")
	elif last != "" and last != App.version:
		toasts.show_toast("Updated to Oazy %s" % App.version, &"update", show_patch_notes)
	Settings.set_value("last_seen_version", App.version)


func _on_import_finished(added: int, found: int) -> void:
	if added > 0:
		App.toast("Added %d %s to your library" % [added, "game" if added == 1 else "games"], &"success")
	elif found > 0:
		App.toast("Everything is already in your library")
	elif loaded:
		App.toast("No Steam, Epic or GOG games found. Add yours with + Add.")


func _on_update_state(state: StringName) -> void:
	if state == &"available" and loaded:
		toasts.show_toast("Oazy %s is available. See what's new" % Updater.latest.get("version", ""), &"update", show_update)


func _on_files_dropped(files: PackedStringArray) -> void:
	if files.is_empty() or modal_open():
		return
	var path := files[0].replace("\\", "/")
	if DirAccess.dir_exists_absolute(path):
		App.toast("Drop a program or shortcut, not a folder", &"error")
		return
	open_add(Library.infer_from_path(path))


# --- Input -----------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var k: InputEventKey = event
		if k.keycode == KEY_F11 or (k.keycode == KEY_ENTER and k.alt_pressed):
			toggle_fullscreen()
		elif modal_open():
			return
		elif k.keycode == KEY_TAB and not k.ctrl_pressed:
			_cycle_page(-1 if k.shift_pressed else 1)
		elif k.keycode == KEY_F and k.ctrl_pressed:
			go(&"library")
			library_page.focus_search()
		elif k.keycode == KEY_N and k.ctrl_pressed:
			open_add({})
		elif k.keycode == KEY_COMMA and k.ctrl_pressed:
			go(&"settings")
		elif k.keycode == KEY_ESCAPE and current_page != &"home":
			Sfx.play(&"back")
			go(&"home")
		else:
			return
		get_viewport().set_input_as_handled()
	elif event is InputEventJoypadButton and event.pressed and not modal_open():
		var j: InputEventJoypadButton = event
		if j.button_index == JOY_BUTTON_LEFT_SHOULDER:
			_cycle_page(-1)
		elif j.button_index == JOY_BUTTON_RIGHT_SHOULDER:
			_cycle_page(1)
		elif j.button_index == JOY_BUTTON_B and current_page != &"home":
			go(&"home")
		else:
			return
		get_viewport().set_input_as_handled()


func _cycle_page(dir: int) -> void:
	var i := PAGE_ORDER.find(current_page)
	go(PAGE_ORDER[wrapi(i + dir, 0, PAGE_ORDER.size())])
