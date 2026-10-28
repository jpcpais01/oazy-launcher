extends Node
## CI visual check: run with a real renderer, e.g.
##   xvfb-run godot --path . --resolution 2560x1440 -- --screenshots=/tmp/shots
## Seeds a sample library (real Steam app ids, so artwork downloads), walks the
## main screens and saves a PNG of each.

const STEAM_SAMPLES := [
	["ELDEN RING", "1245620", 61],
	["Marvel Rivals", "2767030", 23],
	["Cyberpunk 2077", "1091500", 88],
	["Baldur's Gate 3", "1086940", 140],
	["Hades II", "1145350", 12],
	["Counter-Strike 2", "730", 410],
]

var dir := ""


func _ready() -> void:
	dir = App.screenshot_dir
	DirAccess.make_dir_recursive_absolute(dir)
	var now := int(Time.get_unix_time_from_system())
	var i := 0
	for s in STEAM_SAMPLES:
		Library.add_entry({
			"name": s[0], "source": "steam", "kind": "game", "steam_appid": s[1],
			"playtime": int(s[2]) * 3600 + 1260, "launches": 10 + i,
			"last_played": now - i * 86400 * 2 - 3600, "favorite": i == 0,
		})
		i += 1
	Library.add_entry({"name": "Hollow Knight", "path": "C:/Games/Hollow Knight/hollow_knight.exe", "playtime": 41 * 3600, "last_played": now - 86400 * 30})
	Library.add_entry({"name": "Claude Code", "kind": "app", "path": "C:/Windows/System32/cmd.exe", "args": "/k claude", "launches": 40, "last_played": now - 600})
	Catalog.set_mock_apps([
		{"name": "Google Chrome", "id": "Chrome"},
		{"name": "File Explorer", "id": "Microsoft.Windows.Explorer"},
		{"name": "Discord", "id": "com.squirrel.Discord.Discord"},
		{"name": "Spotify", "id": "SpotifyAB.SpotifyMusic_zpdnekdrzrea0!Spotify"},
		{"name": "Steam", "id": "C:/Program Files (x86)/Steam/steam.exe"},
		{"name": "Visual Studio Code", "id": "Microsoft.VisualStudioCode"},
		{"name": "Terminal", "id": "Microsoft.WindowsTerminal_8wekyb3d8bbwe!App"},
		{"name": "Notepad", "id": "Microsoft.WindowsNotepad_8wekyb3d8bbwe!App"},
		{"name": "Calculator", "id": "Microsoft.WindowsCalculator_8wekyb3d8bbwe!App"},
		{"name": "Paint", "id": "Microsoft.Paint_8wekyb3d8bbwe!App"},
		{"name": "OBS Studio", "id": "C:/Program Files/obs-studio/bin/64bit/obs64.exe"},
		{"name": "Figma", "id": "com.squirrel.figma.Figma"},
		{"name": "Photos", "id": "Microsoft.Windows.Photos_8wekyb3d8bbwe!App"},
		{"name": "Microsoft Edge", "id": "MSEdge"},
		{"name": "Claude", "id": "C:/Users/joao/AppData/Local/AnthropicClaude/claude.exe"},
		{"name": "WhatsApp", "id": "5319275A.WhatsAppDesktop_cv1g1gvanyjgm!App"},
	])
	# Flow as João has it: a Library card with its own art.
	Library.update_entry(Catalog.add_to_library("oazy:flow"), {"launches": 30, "last_played": now - 1800})
	Catalog.set_favorite("app:Chrome", true)
	Catalog.set_favorite("lib:" + str(Library.entries[0]["id"]), true)
	for e in Library.entries:
		if str(e["name"]) == "Claude Code":
			Catalog.set_favorite("lib:" + str(e["id"]), true)
	Catalog.set_favorite("app:SpotifyAB.SpotifyMusic_zpdnekdrzrea0!Spotify", true)
	for r in ["app:5319275A.WhatsAppDesktop_cv1g1gvanyjgm!App", "app:com.squirrel.Discord.Discord", "app:Microsoft.Windows.Explorer", "oazy:browser"]:
		Catalog.set_favorite(r, true)
	for r in ["app:Microsoft.WindowsTerminal_8wekyb3d8bbwe!App", "app:com.squirrel.figma.Figma", "app:Microsoft.VisualStudioCode", "app:com.squirrel.Discord.Discord"]:
		Catalog.note_recent(r)
	await _wait(0.2)
	await shot("00-loading")
	var main := get_tree().current_scene
	var waited := 0.0
	while not main.loaded and waited < 8.0:
		await _wait(0.2)
		waited += 0.2
	if OS.get_environment("OAZY_SHOTS_ONLY") == "assistant":
		# Dev runs: just the Claude popup.
		Account.set_mock({"name": "João Pais", "email": "joao.pais@gmail.com"}, null)
		await _wait(1.5)
		await _assistant(main)
		get_tree().quit()
		return
	# Give artwork a moment to arrive from Steam.
	waited = 0.0
	while waited < 15.0:
		var done := true
		for e in Library.entries:
			if str(e["source"]) == "steam" and not Art.is_resolved(str(e["id"]), &"cover"):
				done = false
		if done:
			break
		await _wait(0.25)
		waited += 0.25
	await _wait_for_hero(str(Library.recent()[0]["id"]))
	main.desktop.refresh()
	Settings.set_value("cpu_temp", true)
	main.desktop.show_mock_stats(0.23, 0.58, {"cpu_mhz": 4712.0, "cpu_temp": 58.0, "gpu_name": "NVIDIA GeForce RTX 4070", "gpu_mhz": 2475.0, "gpu_temp": 61.0, "gpu_load": 34.0, "mem_total": 34359738368.0, "hz": 165})
	Host.set_mock_windows([
		{"hwnd": 101, "title": "Oazy – Google Chrome", "exe": "C:/Program Files/Google/Chrome/Application/chrome.exe", "aumid": "Chrome", "name": "Google Chrome"},
		{"hwnd": 102, "title": "Claude Code", "exe": "C:/Windows/System32/cmd.exe", "name": "Windows Command Processor"},
		{"hwnd": 103, "title": "#general - Discord", "exe": "C:/Users/joao/AppData/Local/Discord/app-1.0/Discord.exe", "aumid": "com.squirrel.Discord.Discord", "name": "Discord"},
	], 0)
	var ws: GDScript = load("res://tests/weather_sample.gd")
	Weather.set_mock(ws.place(), ws.forecast())
	Network.set_mock({"ok": true, "wifi": true, "radio": true, "state": "connected", "internet": true,
		"current": {"id": "4f617a79", "ssid": "Oazy Home", "signal": 92, "mbps": 1201, "ghz": "5"},
		"ethernet": [{"name": "Ethernet", "device": "Intel(R) Ethernet I225-V", "up": true, "mbps": 1000}],
		"networks": [
			{"id": "4f617a79", "ssid": "Oazy Home", "signal": 92, "secure": true, "auth": "wpa2", "known": true, "connected": true, "connectable": true},
			{"id": "4c6162", "ssid": "Lab 5G", "signal": 74, "secure": true, "auth": "wpa3", "known": false, "connected": false, "connectable": true},
			{"id": "436166", "ssid": "Café Lisboa Guest", "signal": 51, "secure": false, "auth": "open", "known": false, "connected": false, "connectable": true},
			{"id": "4e4f53", "ssid": "NOS-8A21", "signal": 38, "secure": true, "auth": "wpa2", "known": true, "connected": false, "connectable": true},
			{"id": "4d454f", "ssid": "MEO-Office", "signal": 22, "secure": true, "auth": "enterprise", "known": false, "connected": false, "connectable": true},
		]})
	await _wait(2.5)
	if OS.get_environment("OAZY_SHOTS_ONLY") == "tasks":
		await _tasks_shots(main)
		get_tree().quit()
		return
	if OS.get_environment("OAZY_SHOTS_ONLY") == "music":
		await _music(main)
		get_tree().quit()
		return
	if OS.get_environment("OAZY_SHOTS_ONLY") == "switcher":
		await _switcher_shots(main)
		get_tree().quit()
		return
	await shot("01-desktop")
	for size_id in ["small", "large"]:
		Settings.set_value("fav_icon_size", size_id)
		await _wait(0.6)
		await shot("01f-desktop-favs-" + size_id)
	Settings.set_value("fav_icon_size", "medium")
	# Each wallpaper: on the desktop, then on its own.
	for id in Wallpaper.STYLES:
		Settings.set_value("wallpaper", id)
		await _wait(1.3)
		if id != "oasis":
			await shot("01w-desktop-" + id)
		var shown := []
		for c in main.get_children():
			if c is CanvasItem and c != main.wallpaper and (c as CanvasItem).visible:
				(c as CanvasItem).visible = false
				shown.append(c)
		await _wait(0.2)
		await shot("01x-wallpaper-" + id)
		for c in shown:
			(c as CanvasItem).visible = true
	Settings.set_value("wallpaper", "oasis")
	await _wait(1.3)
	await _music(main)
	await _below(main)
	main.weather.open(main.taskbar._weather_btn)
	await _wait(0.9)
	await shot("01b-weather")
	main.weather.close()
	await _wait(0.3)
	main.network.open(main.taskbar._net)
	await _wait(0.9)
	await shot("01c-network")
	main.network._toggle_row("4c6162")
	await _wait(0.6)
	await shot("01d-network-key")
	main.network.close()
	await _wait(0.3)
	await _tasks_shots(main)
	Account.set_mock({"name": "João Pais", "email": "joao.pais@gmail.com"}, _mock_photo(Color("2b6f8f"), Color("f2b27a")))
	main.start.open()
	await _wait(0.9)
	await shot("02-start")
	main.start.open("c")
	await _wait(0.6)
	await shot("03-search")
	main.start.close()
	await _wait(0.5)
	await _assistant(main)
	# Signing in: the picker with the accounts Chrome knows.
	Account.set_mock({})
	Account.set_mock_chrome([
		{"name": "João Pais", "email": "joao.pais@gmail.com", "from": "Chrome", "texture": _mock_photo(Color("2b6f8f"), Color("f2b27a"))},
		{"name": "João Pais", "email": "joao@studio.pt", "from": "Chrome · Work", "texture": _mock_photo(Color("5b3f8f"), Color("9fd6c8"))},
		{"name": "", "email": "oazy.tests@gmail.com", "from": "Chrome · Testing"},
	])
	main.show_account_picker()
	await _wait(1.0)
	await shot("02c-account-picker")
	for m in main.overlay_layer.get_children():
		if m is AccountPicker:
			(m as AccountPicker).close()
	Account.set_mock({"name": "João Pais", "email": "joao.pais@gmail.com"}, _mock_photo(Color("2b6f8f"), Color("f2b27a")))
	await _wait(0.5)
	var lib: ShellWindow = main.open_app(&"library")
	await _wait(1.5)
	await shot("04-library")
	main.focus_entry(str(Library.recent()[1]["id"]))
	await _wait_for_hero(str(Library.recent()[1]["id"]))
	await _wait(1.2)
	await shot("05-game")
	var settings: ShellWindow = main.open_app(&"settings")
	await _wait(1.2)
	await _wait(0.3)
	await shot("06-settings")
	(settings.body.get_child(0) as SettingsApp).open_page("personalise")
	await _wait(0.5)
	var icons := settings.find_child("CustomIcons", true, false) as Control
	var scroller := settings.find_child("*ScrollContainer*", true, false) as ScrollContainer
	if icons and scroller:
		scroller.scroll_vertical = int(icons.global_position.y - scroller.global_position.y) - 160
		await _wait(0.4)
		await shot("06b-settings-icons")
		scroller.scroll_vertical = 0
	var walls := settings.find_child("Wallpapers", true, false) as Control
	if walls and scroller:
		var content := scroller.get_child(0) as Control
		scroller.scroll_vertical = int((content.get_global_transform().affine_inverse() * walls.global_position).y) - 200
		await _wait(0.4)
		await shot("06d-settings-wallpapers")
		scroller.scroll_vertical = 0
	var pointers := settings.find_child("Pointers", true, false) as Control
	if pointers:
		var sc := pointers.get_parent()
		while sc and not sc is ScrollContainer:
			sc = sc.get_parent()
		if sc:
			var content := (sc as ScrollContainer).get_child(0) as Control
			var y := (content.get_global_transform().affine_inverse() * pointers.global_position).y
			(sc as ScrollContainer).scroll_vertical = int(y) - 260
		await _wait(0.4)
		await shot("06c-settings-pointers")
		if sc:
			(sc as ScrollContainer).scroll_vertical = 0
	var st := settings.body.get_child(0) as SettingsApp
	if st:
		for spec in [["desktop", "06d-settings-desktop"], ["network", "06e-settings-network"], ["updates", "06f-settings-updates"]]:
			st.open_page(spec[0])
			await _wait(0.5)
			await shot(spec[1])
		st.search("sound")
		await _wait(0.5)
		await shot("06g-settings-search")
		st.open_page("personalise")
	var work: Rect2 = main.layer.work_rect()
	lib.set_rect(Rect2(work.position + Vector2(40, 30), Vector2(work.size.x * 0.56, work.size.y * 0.8)))
	settings.set_rect(Rect2(work.position + Vector2(work.size.x * 0.48, work.size.y * 0.12), Vector2(work.size.x * 0.48, work.size.y * 0.84)))
	var chrome: TaskbarButton = main.taskbar.button_for("app:Chrome")
	if chrome:
		main.preview.show_for(chrome)
	await _wait(1.0)
	await shot("07-windows")
	main.preview.hide_preview()
	# Stand-in window pictures (no real windows here): the screen as it is now.
	var pic := ImageTexture.create_from_image(get_viewport().get_texture().get_image())
	for w in Host.windows:
		Host.captures[int(w["hwnd"])] = pic
	main.switcher.handle_key("open")
	await _wait(0.8)
	await shot("07b-switcher")
	main.switcher.step(1)
	await _wait(0.5)
	await shot("07b2-switcher-picture")
	main.switcher.handle_key("cancel")
	await _wait(0.3)
	# A maximised app: the taskbar melts into a full-width shelf.
	var before: Array = Host.windows.duplicate(true)
	var maxed: Array = Host.windows.duplicate(true)
	maxed[0]["max"] = true
	lib.minimize()
	settings.minimize()
	Host.set_mock_windows(maxed, int(maxed[0]["hwnd"]))
	await _wait(1.0)
	await shot("07c-docked")
	Host.set_mock_windows(before, 0)
	lib.unminimize()
	settings.unminimize()
	await _wait(0.6)
	main.open_add({})
	await _wait(0.9)
	await shot("08-add")
	_close_modals()
	await _wait(0.5)
	main.find_apps()
	await _wait(0.6)
	var finder: FindAppsDialog = main.overlay_layer.get_children().filter(func(c: Node) -> bool: return c is FindAppsDialog)[0]
	for r in finder._rows.slice(0, 3):
		finder._toggle(r)
	await _wait(0.5)
	await shot("08b-find-apps")
	finder._add_picked()
	Catalog.add_to_library("app:Microsoft.WindowsNotepad_8wekyb3d8bbwe!App")
	await _wait(0.5)
	var lib_app: LibraryApp = lib.body.get_child(0)
	main.focus_shell_window(lib)
	lib_app.set_filter("apps")
	await _wait(1.2)
	await shot("08c-library-apps")
	lib_app.set_filter("all")
	main.show_ref_menu("app:Microsoft.Paint_8wekyb3d8bbwe!App", Vector2(900, 500))
	await _wait(0.5)
	await shot("08d-app-menu")
	main._menu.hide()
	await _wait(0.3)
	Updater.apply_releases([
		{"tag_name": "v2.0.0", "published_at": "2026-10-25T10:00:00Z", "body": "### Oazy is your desktop now\n- **A real taskbar** with everything that's open.\n- Glass windows you can snap, resize and minimise.\n- Start opens any app, game, folder or website.", "assets": [{"name": "OazyLauncher.exe", "size": 97000000, "browser_download_url": "https://x"}]},
		{"tag_name": "v1.0.8", "published_at": "2026-10-20T10:00:00Z", "body": "### Controller support\n- Shoulder buttons switch pages.", "assets": [{"name": "OazyLauncher.exe", "size": 96000000, "browser_download_url": "https://x"}]},
	], "1.0.3")
	Updater.state = &"available"
	Updater.state_changed.emit(&"available")
	await _wait(2.0)
	await shot("09a-update-pill")
	main.show_update()
	await _wait(1.0)
	await shot("09-update")
	Updater.state = &"downloading"
	Updater.state_changed.emit(&"downloading")
	for k in 8:
		Updater.progress.emit(int(97000000 * 0.06 * (k + 1)), 97000000, 14200000.0)
		await _wait(0.12)
	await _wait(0.8)
	await shot("10-download")
	Updater.state = &"ready"
	Updater.state_changed.emit(&"ready")
	await _wait(0.5)
	await shot("10b-ready")
	Updater.state = &"installing"
	Updater.state_changed.emit(&"installing")
	await _wait(1.6)
	await shot("10c-restarting")
	Updater.state = &"available"
	_close_modals()
	await _wait(0.5)
	var welcome := UpdateWelcome.new()
	welcome.version = "2.1.40"
	welcome.from_version = "2.1.31"
	welcome.markdown = Updater.combined_notes()
	welcome.show_all = main.show_patch_notes
	main.overlay_layer.add_child(welcome)
	await _wait(1.8)
	await shot("10d-welcome")
	_close_modals()
	await _wait(0.5)
	# Downloading in the background: the pill, closed and hovered.
	Updater.state = &"downloading"
	Updater.state_changed.emit(&"downloading")
	main.update_pill._news_left = 0.0
	main.update_pill._refresh_open()
	Updater.progress.emit(int(97000000 * 0.42), 97000000, 14200000.0)
	await _wait(1.4)
	await shot("10e-pill-downloading")
	main.update_pill._set_hover(true)
	await _wait(0.8)
	await shot("10f-pill-open")
	main.update_pill._hovered = false
	Updater.state = &"idle"
	Updater.state_changed.emit(&"idle")
	await _wait(0.5)
	# The launch screen: starting, a slow launcher, and a launch that failed.
	var game_id := str(Library.entries[0]["id"])
	main.launch(game_id)
	await _wait(1.6)
	await shot("11-launch")
	await _wait(2.0)
	var slow := LaunchOverlay.new().setup(game_id)
	main.overlay_layer.add_child(slow)
	slow._started = true
	slow._elapsed = 11.0
	await _wait(0.8)
	slow.show_slow()
	await _wait(0.8)
	await shot("11b-launch-slow")
	slow.fail()
	await _wait(1.0)
	await shot("11c-launch-failed")
	_close_modals()
	await _wait(0.5)
	var cleaner_win: ShellWindow = main.open_app(&"cleaner")
	var cleaner: CleanerApp = cleaner_win.body.get_child(0)
	await _wait(0.8)
	await shot("12-cleaner-scan")
	while Cleaner.busy():
		await _wait(0.2)
	await _wait(1.6)
	await shot("13-cleaner")
	cleaner._go("startup")
	Cleaner.want_startup(Cleaner.scan["startup"][0], false)
	await _wait(0.8)
	await shot("14-cleaner-startup")
	cleaner._go("privacy")
	await _wait(0.8)
	await shot("15-cleaner-privacy")
	Cleaner.apply_picks()
	await _wait(0.6)
	await shot("16-cleaner-applying")
	while Cleaner.busy():
		await _wait(0.2)
	await _wait(1.6)
	await shot("17-cleaner-done")
	print("SCREENSHOTS: DONE")
	get_tree().quit(0)


## The desktop's second screen: live markets and news when this machine can
## reach them (CI can), otherwise a made-up but realistic sample.
## The music wallpaper on two very different songs.
func _music(main: Node) -> void:
	Music.set_on(true)
	Music.set_mock_media({"has": true, "app": "Chrome", "title": "Celestial Echoes", "artist": "Aura of Sound", "playing": true,
		"can_seek": true, "can_next": true, "can_prev": true, "dur": 252.0, "pos": 165.0})
	var songs := {
		# Bright, quick, major: warm.
		"joy": [[880, 940, 820, 610, 540, 600, 520, 470, 430, 380, 330, 300, 260, 210, 160, 110], 0.75, 0.8, 0, 1.0, 0.62],
		# Slow, dark, minor: deep blue.
		"blue": [[620, 700, 560, 380, 420, 380, 300, 240, 190, 150, 110, 80, 60, 40, 30, 20], -0.65, 0.2, 9, -1.0, 0.3],
		# Hard, noisy, minor and loud: violet.
		"tense": [[999, 960, 900, 700, 640, 660, 600, 560, 520, 500, 480, 440, 400, 360, 320, 260], -0.6, 0.95, 4, -0.8, 0.55],
	}
	for id in songs:
		var song: Array = songs[id]
		Music.key = int(song[3])
		Music.set_mock({"b": song[0], "db": -16.0, "o": 0.6, "k": 0.0, "bpm": 120.0, "bc": 0.8, "ph": 0.1,
			"c": float(song[5]), "f": 0.15, "r": 3.0, "m": float(song[4]), "key": int(song[3]), "kc": 0.8}, float(song[1]), float(song[2]))
		await _wait(1.6)
		await shot("01m-desktop-music-" + id)
	# Clicking the desktop: just the music and the taskbar.
	main.set_clean_view(true)
	await _wait(1.0)
	await shot("01m-desktop-music-clean")
	main.set_clean_view(false)
	await _wait(0.8)
	var shown := []
	for c in main.get_children():
		if c is CanvasItem and c != main.wallpaper and (c as CanvasItem).visible:
			(c as CanvasItem).visible = false
			shown.append(c)
	await _wait(0.2)
	await shot("01x-wallpaper-music")
	for c in shown:
		(c as CanvasItem).visible = true
	Music.set_mock_media({})
	Music.set_mock({})
	Music.set_on(false)
	await _wait(1.6)


func _below(main: Node) -> void:
	var below: DesktopBelow = main.desktop.below
	below.set_active(true)
	below.markets.refresh(true)
	below.news.refresh(true)
	var waited := 0.0
	while waited < 25.0 and (below.markets.busy or below.news.busy):
		await _wait(0.25)
		waited += 0.25
	print("  markets live: %d of %d, news live: %d" % [below.markets.quotes.size(), Markets.symbols().size(), below.news.items().size()], "  (", below.markets.last_error, " / ", below.news.last_error, ")")
	if below.markets.quotes.size() < Markets.symbols().size():
		below.markets.set_mock(_mock_quotes())
	if below.news.items().is_empty():
		below.news.set_mock(News.topic(), _mock_news())
	main.desktop.scroll_to(main.desktop.size.y * 0.45)
	await _wait(0.12)
	await shot("01s0-desktop-scrolling")
	main.desktop.page(1)
	await _wait(1.6)
	await shot("01s-desktop-below")
	below._open_market_edit()
	await _wait(0.3)
	await shot("01s2-desktop-markets-edit")
	below._close_market_edit()
	main.desktop.page(-1)
	await _wait(1.4)


static func _mock_quotes() -> Dictionary:
	var out := {}
	var spec := {
		"^GSPC": [6712.4, 0.62, "S&P 500"], "^IXIC": [22840.1, 0.94, "NASDAQ Composite"], "NVDA": [186.32, 1.84, "NVIDIA Corporation"],
		"AAPL": [258.11, -0.42, "Apple Inc."], "MSFT": [521.77, 0.31, "Microsoft Corporation"], "BTC-USD": [111842.0, -1.27, "Bitcoin USD"],
	}
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for sym in spec:
		var price: float = spec[sym][0]
		var pct: float = spec[sym][1]
		var prev := price / (1.0 + pct / 100.0)
		var pts := []
		var v := prev
		for i in 78:
			var drift := (price - v) / float(78 - i)
			v += drift + rng.randfn(0.0, prev * 0.0018)
			pts.append(v)
		pts[-1] = price
		out[sym] = {"symbol": sym, "name": spec[sym][2], "price": price, "prev": prev, "currency": "USD", "points": pts, "at": int(Time.get_unix_time_from_system()),
			"open_from": int(Time.get_unix_time_from_system()) - 3 * 3600, "open_to": int(Time.get_unix_time_from_system()) + 3 * 3600}
	return out


static func _mock_news() -> Array:
	var now := int(Time.get_unix_time_from_system())
	var list := [
		["Central banks signal a slower path for rate cuts as inflation cools unevenly", "Reuters", 18],
		["Lisbon unveils plan to plant 20,000 trees along the riverfront by 2030", "The Guardian", 42],
		["Chipmakers rally after record quarter for AI data-centre demand", "Bloomberg", 65],
		["Scientists map the deepest coral reef yet found in the Atlantic", "BBC News", 96],
		["The best games of the year so far, from indie gems to blockbusters", "The Verge", 140],
		["European rail operators agree on single ticket for cross-border trips", "Financial Times", 190],
		["New battery chemistry promises faster charging for budget electric cars", "Wired", 260],
		["Champions League: late winner keeps the group wide open", "ESPN", 320],
	]
	var out := []
	for it in list:
		out.append({"title": it[0], "source": it[1], "link": "https://example.com", "at": now - int(it[2]) * 60})
	return out


## The Start orb's Claude popup: empty, mid-conversation and asking. With
## OAZY_SHOTS_LIVE=1 (a dev run on a PC with Claude Code signed in) it talks
## to the real claude instead.
func _assistant(main: Node) -> void:
	var a: AssistantPanel = main.assistant
	var live := OS.get_environment("OAZY_SHOTS_LIVE") == "1"
	a.mock = not live
	a.open()
	await _wait(0.9)
	await shot("02d-assistant")
	Settings.set_value("claude_auto_allow", true)
	await _wait(0.3)
	await shot("02d2-assistant-allow-all")
	Settings.set_value("claude_auto_allow", false)
	if live:
		a.submit("In two short sentences: what is in my home folder?")
		var waited := 0.0
		while a.running and waited < 90.0:
			await _wait(0.5)
			waited += 0.5
			if waited == 3.0:
				await shot("02e-assistant-live-working")
		await _wait(0.6)
		await shot("02e-assistant-live")
		a.submit("Create a file called oazy-hello.txt in my home folder with the word hi in it.")
		waited = 0.0
		while a.running and a._asks.is_empty() and waited < 90.0:
			await _wait(0.5)
			waited += 0.5
		await _wait(0.6)
		await shot("02f-assistant-live-ask")
		for id in a._asks.keys():
			a._answer(str(id), false)
		waited = 0.0
		while a.running and waited < 60.0:
			await _wait(0.5)
			waited += 0.5
		await _wait(0.4)
		await shot("02g-assistant-live-denied")
		a.new_chat()
		a.close()
		await _wait(0.4)
		return
	a.submit("What's taking up the most space in my Downloads folder?")
	a.handle_message({"type": "stream_event", "event": {"type": "message_start", "message": {"id": "m1"}}})
	a.handle_message({"type": "stream_event", "event": {"type": "content_block_start", "index": 0, "content_block": {"type": "tool_use", "id": "t1", "name": "Bash"}}})
	a.handle_message({"type": "stream_event", "event": {"type": "content_block_delta", "index": 0, "delta": {"type": "input_json_delta", "partial_json": "{\"command\": \"du -sh ~/Downloads/*\", \"description\": \"Measure what's in Downloads\"}"}}})
	a.handle_message({"type": "stream_event", "event": {"type": "content_block_stop", "index": 0}})
	await _wait(0.5)
	await shot("02e-assistant-working")
	a.handle_message({"type": "user", "message": {"content": [{"type": "tool_result", "tool_use_id": "t1", "content": "ok"}]}})
	a.handle_message({"type": "stream_event", "event": {"type": "message_start", "message": {"id": "m2"}}})
	a.handle_message({"type": "stream_event", "event": {"type": "content_block_start", "index": 0, "content_block": {"type": "text"}}})
	var reply := "Your **Downloads** folder is using about **18.4 GB**, and most of it is three big installers:\n\n| File | Size |\n|---|---|\n| `Cyberpunk2077_setup.exe` | 9.1 GB |\n| `DaVinci_Resolve_19.zip` | 3.4 GB |\n| `Win11_23H2.iso` | 2.9 GB |\n\nThe rest is small stuff: PDFs, screenshots and a few zips from this month.\n\nWant me to move the installers you've already used into a folder called **Old installers**, so you can check before deleting anything?"
	a.handle_message({"type": "stream_event", "event": {"type": "content_block_delta", "index": 0, "delta": {"type": "text_delta", "text": reply}}})
	a.handle_message({"type": "stream_event", "event": {"type": "content_block_stop", "index": 0}})
	a.handle_message({"type": "result", "subtype": "success"})
	await _wait(0.6)
	await shot("02f-assistant-reply")
	a.submit("Yes please")
	a.handle_message({"type": "stream_event", "event": {"type": "message_start", "message": {"id": "m3"}}})
	a.handle_message({"type": "assistant", "message": {"id": "m3", "content": [{"type": "tool_use", "id": "t2", "name": "PowerShell", "input": {"command": "New-Item -ItemType Directory \"$HOME\\Downloads\\Old installers\"\nMove-Item \"$HOME\\Downloads\\Cyberpunk2077_setup.exe\", \"$HOME\\Downloads\\Win11_23H2.iso\" \"$HOME\\Downloads\\Old installers\"", "description": "Move the used installers into Old installers"}}]}})
	a.handle_message({"type": "control_request", "request_id": "r1", "request": {"subtype": "can_use_tool", "tool_name": "PowerShell", "tool_use_id": "t2", "input": {"command": "New-Item -ItemType Directory \"$HOME\\Downloads\\Old installers\"\nMove-Item \"$HOME\\Downloads\\Cyberpunk2077_setup.exe\", \"$HOME\\Downloads\\Win11_23H2.iso\" \"$HOME\\Downloads\\Old installers\"", "description": "Move the used installers into Old installers"}}})
	await _wait(0.6)
	await shot("02g-assistant-ask")
	a._answer("r1", true)
	a.handle_message({"type": "user", "message": {"content": [{"type": "tool_result", "tool_use_id": "t2", "content": "ok"}]}})
	a.handle_message({"type": "assistant", "message": {"id": "m4", "content": [{"type": "text", "text": "Done. Both installers are in **Downloads/Old installers** now."}]}})
	a.handle_message({"type": "result", "subtype": "success"})
	await _wait(0.4)
	a.close()
	await _wait(0.4)
	# Alt+Tab: the conversation waits there like a window.
	main.switcher.handle_key("open")
	for i in main.switcher._entries.size():
		if main.switcher._entries[i].has("assistant"):
			main.switcher.selected = i
	main.switcher._select(main.switcher.selected, false)
	await _wait(0.8)
	await shot("02h-assistant-alt-tab")
	main.switcher.handle_key("cancel")
	await _wait(0.4)
	a.new_chat()
	# Past chats, from a made-up Claude Code history.
	var was_conf := OS.get_environment("CLAUDE_CONFIG_DIR")
	OS.set_environment("CLAUDE_CONFIG_DIR", ProjectSettings.globalize_path("user://shots_claude"))
	var dir := ClaudeHistory.project_dir(ClaudeCli.home())
	DirAccess.make_dir_recursive_absolute(dir)
	var chats := [
		["Free up space in Downloads", "What's taking up the most space in my Downloads folder?", 0],
		["Birthday message for Rita", "Help me write a birthday message to Rita", 3600 * 5],
		["Explain how VPNs work", "Explain this to me simply: how does a VPN work?", 86400 + 3600],
		["Rename holiday photos by date", "Rename the photos in Pictures/Algarve by the date they were taken", 86400 * 3],
		["What I worked on this week", "What did I work on this week?", 86400 * 6],
	]
	var now := int(Time.get_unix_time_from_system())
	for i in chats.size():
		var path := dir.path_join("shot-%d.jsonl" % i)
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_line(JSON.stringify({"type": "user", "cwd": ClaudeCli.home(), "message": {"role": "user", "content": chats[i][1]}}))
		f.store_line(JSON.stringify({"type": "assistant", "message": {"id": "h%d" % i, "role": "assistant", "content": [{"type": "text", "text": "Sure, here's a short summary."}]}}))
		f.store_line(JSON.stringify({"type": "ai-title", "aiTitle": chats[i][0]}))
		f.close()
		# Older chats, older files.
		OS.execute("touch", PackedStringArray(["-d", "@%d" % (now - int(chats[i][2])), path]))
	a.open()
	await _wait(0.5)
	a.show_history()
	await _wait(0.6)
	await shot("02i-assistant-past-chats")
	var past := ClaudeHistory.recent(ClaudeCli.home())
	if past.size() > 1:
		a.load_chat(past[1])
	await _wait(0.6)
	await shot("02j-assistant-past-chat-open")
	OS.set_environment("CLAUDE_CONFIG_DIR", was_conf)
	a.close()
	await _wait(0.4)
	a.new_chat()
	a.mock = false


func _wait_for_hero(id: String) -> void:
	var waited := 0.0
	while waited < 6.0 and not Art.is_resolved(id, &"hero"):
		await _wait(0.25)
		waited += 0.25


func _close_modals() -> void:
	for m in get_tree().get_nodes_in_group("modal"):
		if m.has_method("close"):
			m.close()


## The task manager over its taskbar button: apps, then Background unfolded
## with a row asking before it ends something.
func _tasks_shots(main: Node) -> void:
	var tf: TasksFlyout = main.tasks
	main.open_tasks()
	await _wait(3.4)
	await shot("01t-tasks")
	tf._folded["background"] = false
	var chrome: Dictionary = tf._data["apps"][0]
	for g in tf._data["apps"]:
		if g["ref"] == "app:Chrome":
			chrome = g
	tf.toggle_details(chrome["key"])
	var sys: Array = tf._data["system"]
	for g in tf._data["apps"]:
		if str(g["name"]).contains("Claude"):
			tf._confirm[g["key"]] = Time.get_ticks_msec() + 60000
	await _wait(1.6)
	await shot("01u-tasks-more")
	tf._folded["background"] = true
	tf._confirm.clear()
	tf.toggle_details(chrome["key"])
	tf.close()
	await _wait(0.3)


## A stand-in profile photo: a soft sky with a figure, like a portrait.
func _mock_photo(sky: Color, glow: Color) -> Texture2D:
	var n := 192
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var u := Vector2(x, y) / float(n)
			var c := sky.lerp(glow, clampf(u.y * 1.1 - 0.1, 0.0, 1.0))
			var head := (u - Vector2(0.5, 0.42)).length() < 0.17
			var body := (u - Vector2(0.5, 1.02)).length() < 0.38
			if head or body:
				c = c.darkened(0.55)
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)


## Dev runs: just the Alt+Tab stack, with stand-in pictures of a few screens.
func _switcher_shots(main: Node) -> void:
	var pics: Array[Texture2D] = [ImageTexture.create_from_image(get_viewport().get_texture().get_image())]
	var lib: ShellWindow = main.open_app(&"library")
	await _wait(1.2)
	pics.append(ImageTexture.create_from_image(get_viewport().get_texture().get_image()))
	var settings: ShellWindow = main.open_app(&"settings")
	await _wait(1.2)
	pics.append(ImageTexture.create_from_image(get_viewport().get_texture().get_image()))
	var list: Array = Host.windows.duplicate(true)
	list.append({"hwnd": 104, "title": "Spotify Premium", "exe": "C:/Users/joao/AppData/Roaming/Spotify/Spotify.exe", "name": "Spotify", "min": true})
	list.append({"hwnd": 105, "title": "Notes.txt - Notepad", "exe": "C:/Windows/System32/notepad.exe", "name": "Notepad", "min": true})
	Host.set_mock_windows(list, 0)
	for i in Host.windows.size():
		var hw := int(Host.windows[i]["hwnd"])
		if hw != 105:
			Host.captures[hw] = pics[i % pics.size()]
	lib.minimize()
	await _wait(0.6)
	main.switcher.handle_key("open")
	await _wait(1.0)
	await shot("07b-switcher")
	main.switcher.step(1)
	await _wait(0.12)
	await shot("07b1-switcher-moving")
	await _wait(0.8)
	await shot("07b2-switcher-next")
	main.switcher.step(-1)
	main.switcher.step(-1)
	await _wait(0.12)
	await shot("07b3-switcher-back-moving")
	await _wait(0.8)
	await shot("07b4-switcher-back")
	main.switcher._select(main.switcher._entries.size() - 1)
	await _wait(0.9)
	await shot("07b5-switcher-minimised")
	main.switcher.handle_key("cancel")
	await _wait(0.4)
	var chrome: TaskbarButton = main.taskbar.button_for("app:Chrome")
	if chrome:
		main.preview.show_for(chrome)
	await _wait(0.8)
	await shot("07c-preview")


func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := dir.path_join(name + ".png")
	if Shell.native:
		# Dev runs with --shell-native: the layers are separate windows, so
		# grab the whole (composited) X screen instead.
		OS.execute("import", ["-window", "root", path])
		print("  saved ", path)
		return
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("  saved ", path, " ", img.get_size())


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
