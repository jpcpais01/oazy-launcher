extends Node
## Headless smoke test, run with: OazyLauncher.exe --headless -- --smoke-test
## Exercises the pure logic, then drives the real UI through its main flows.
## Prints SMOKE: PASS / SMOKE: FAIL and exits with 0 / 1.

var _failures := PackedStringArray()
var _checks := 0


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	_logic_tests()
	await _ui_tests()
	_finish()


func check(cond: bool, what: String) -> void:
	_checks += 1
	if not cond:
		_failures.append(what)
		printerr("  FAILED: ", what)


func _logic_tests() -> void:
	# Versions.
	check(Semver.compare("1.0.10", "1.0.9") == 1, "semver: 1.0.10 > 1.0.9")
	check(Semver.compare("v2.0.0", "1.99.99") == 1, "semver: major wins")
	check(Semver.compare("1.0.3", "1.0.3") == 0, "semver: equal")
	check(Semver.is_newer("1.0.1", "0.0.0-dev"), "semver: dev builds are older")
	check(not Semver.is_newer("1.0.0", "1.0.0"), "semver: same is not newer")

	# Steam KeyValues.
	var vdf := Vdf.parse("\"libraryfolders\"\n{\n\t\"0\"\n\t{\n\t\t\"path\"\t\t\"D:\\\\SteamLibrary\"\n\t\t\"apps\" { \"570\" \"123\" }\n\t}\n}\n")
	var folders: Dictionary = vdf.get("libraryfolders", {})
	check(folders.has("0") and str(folders["0"].get("path", "")) == "D:\\SteamLibrary", "vdf: library path with escaped backslash")
	var acf := Vdf.parse("\"AppState\" { \"appid\" \"1245620\" \"name\" \"ELDEN RING\" \"installdir\" \"ELDEN RING\" }")
	check(str(Vdf.get_key(acf.get("AppState", {}), "APPID", "")) == "1245620", "vdf: case-insensitive lookup")
	check(Library.is_steam_tool("228980", "Steamworks Common Redistributables"), "steam: skips redistributables")
	check(not Library.is_steam_tool("1245620", "ELDEN RING"), "steam: keeps games")

	# Epic manifest.
	var epic := Library.epic_entry({
		"DisplayName": "Fortnite", "AppName": "Fortnite", "MainGameAppName": "Fortnite",
		"CatalogNamespace": "fn", "CatalogItemId": "4fe7", "InstallLocation": "C:\\Epic\\Fortnite",
		"LaunchExecutable": "FortniteGame/Binaries/Win64/FortniteLauncher.exe", "AppCategories": ["public", "games"],
	})
	check(str(epic.get("epic_uri", "")) == "com.epicgames.launcher://apps/fn%3A4fe7%3AFortnite?action=launch&silent=true", "epic: launch uri")
	check(epic.get("kind") == "game", "epic: categorised as game")
	check(Library.epic_entry({"AppName": "DLC1", "MainGameAppName": "Base"}).is_empty(), "epic: skips DLC")

	# GOG registry.
	var gog := Library.parse_gog_registry("HKEY_LOCAL_MACHINE\\SOFTWARE\\WOW6432Node\\GOG.com\\Games\\1207658924\r\n    gameName    REG_SZ    The Witcher 3\r\n    exe    REG_SZ    C:\\GOG\\Witcher3\\bin\\x64\\witcher3.exe\r\n\r\nHKEY_LOCAL_MACHINE\\SOFTWARE\\WOW6432Node\\GOG.com\\Games\\2\r\n    gameName    REG_SZ    Broken\r\n")
	check(gog.size() == 1 and gog[0]["name"] == "The Witcher 3", "gog: parses registry dump")

	# Launch argument parsing and formatting.
	var args := Library.split_args("-windowed \"-name=Big Boss\" -fps 144")
	check(args.size() == 4 and args[1] == "-name=Big Boss", "args: quoted arguments")
	check(Fmt.playtime(3 * 3600 + 25 * 60) == "3h 25m played", "fmt: playtime")
	check(Fmt.ago(1000, 1000 + 86400 + 10) == "Yesterday", "fmt: yesterday")
	check(Fmt.initials("The Witcher 3: Wild Hunt") == "TW", "fmt: initials")
	check(Fmt.pretty_name("C:/Games/hollow_knight.exe") == "Hollow Knight", "fmt: pretty name")
	check(Library.infer_from_path("https://www.figma.com/files")["kind"] == "app", "infer: urls are apps")

	# Markdown -> BBCode.
	var bb := Markdown.to_bbcode("## New\n- **Bold** move and [link](https://example.com)\n- `code`")
	check(bb.contains("[b]Bold[/b]") and bb.contains("[url=https://example.com]link[/url]") and bb.contains("[code]code[/code]"), "markdown: inline formatting")

	# Updater payload parsing (newest first, drafts/prereleases/no-asset skipped).
	Updater.apply_releases([
		{"tag_name": "v1.0.12", "body": "- Old", "assets": [{"name": "OazyLauncher.exe", "size": 10, "browser_download_url": "https://x/12"}]},
		{"tag_name": "v1.0.15", "body": "- Newest", "published_at": "2026-10-25T10:00:00Z", "assets": [{"name": "OazyLauncher.exe", "size": 99, "digest": "sha256:ab", "browser_download_url": "https://x/15"}]},
		{"tag_name": "v1.0.16", "prerelease": true, "assets": [{"name": "OazyLauncher.exe"}]},
		{"tag_name": "v1.0.14", "body": null, "assets": [{"name": "OazyLauncher.exe", "size": 50, "browser_download_url": "https://x/14"}]},
		{"tag_name": "v1.0.17", "assets": []},
	], "1.0.12")
	check(Updater.latest.get("version") == "1.0.15", "updater: picks newest stable with an exe")
	check(Updater.newer.size() == 2, "updater: counts releases newer than installed")
	check(Updater.combined_notes().contains("Behind-the-scenes"), "updater: fills in empty notes")
	check(Updater.verify_file("res://project.godot", 0, "") != "", "updater: rejects non-exe downloads")
	Updater.apply_releases([], App.version)

	# Artwork lookups: name matching and store payload parsing.
	check(Art.norm_title("MARVEL RIVALS™") == Art.norm_title("Marvel Rivals"), "art: titles normalise")
	check(Art.match_steam_search({"items": [{"name": "Marvel Rivals Soundtrack", "id": 1}, {"name": "Marvel Rivals", "id": 2767030}]}, "Marvel Rivals™") == "2767030", "art: steam search exact match")
	check(Art.match_steam_search({"items": [{"name": "Fortnite Fan Game", "id": 9}]}, "Fortnite") == "", "art: steam search rejects near misses")
	var ep := Art.epic_ids({"epic_app": "Fortnite", "epic_uri": "com.epicgames.launcher://apps/fn%3A4fe75bbc5a674f4f9b356b5c90567da5%3AFortnite?action=launch&silent=true"})
	check(ep.get("item") == "4fe75bbc5a674f4f9b356b5c90567da5" and ep.get("app") == "Fortnite", "art: epic ids from launch uri")
	var cat_json := JSON.stringify([{"id": "abc", "title": "Fortnite", "keyImages": [{"type": "DieselGameBoxTall", "url": "https://cdn1.epicgames.com/tall.jpg"}]}])
	var cat := Art.parse_epic_catalog(Marshalls.raw_to_base64(cat_json.to_utf8_buffer()))
	check(cat["by_id"].has("abc") and cat["by_title"]["fortnite"]["DieselGameBoxTall"].ends_with("tall.jpg"), "art: epic catalog cache parses")
	var gdb := Art.gamesdb_images({"game": {"vertical_cover": {"url_format": "https://images.gog.com/x{formatter}.{ext}"}, "logo": {"url_format": "https://images.gog.com/l{formatter}.{ext}"}}})
	check(gdb.get(&"cover") == "https://images.gog.com/x.jpg" and gdb.get(&"logo") == "https://images.gog.com/l.png", "art: gamesdb images")
	check(Art.match_wiki({"query": {"pages": [{"title": "Fortnite Battle Royale", "index": 1, "thumbnail": {"source": "a"}}, {"title": "Fortnite (video game)", "index": 2, "thumbnail": {"source": "b"}}]}}, "Fortnite") == "b", "art: wikipedia picks the matching page")

	# Library CRUD (smoke runs use a throwaway file).
	var id := Library.add_entry({"name": "Smoke Game", "path": "C:/Games/smoke.exe"})
	check(Library.has_entry(id), "library: add")
	Library.update_entry(id, {"playtime": 7200})
	check(int(Library.get_entry(id)["playtime"]) == 7200, "library: update")
	check(Library.toggle_favorite(id), "library: favourite")
	check(Library.query("favorites", "", "recent").size() == 1, "library: favourites filter")
	check(Library.query("all", "smoke", "name").size() == 1, "library: search")
	Library.add_entry({"name": "Some App", "path": "C:/Apps/app.exe", "kind": "app", "last_played": 5})
	check(Library.recent()[0]["name"] == "Some App", "library: recent ordering")
	Library.save_now()
	Library.load_library()
	check(Library.entries.size() == 2, "library: save and reload")

	# Shell: search ranking, Start clutter, window grouping and the sky.
	check(Catalog.match_score("Visual Studio Code", "visual studio code") == 100, "catalog: exact match")
	check(Catalog.match_score("Google Chrome", "goo") == 80, "catalog: prefix match")
	check(Catalog.match_score("Google Chrome", "chr") == 60, "catalog: word match")
	check(Catalog.match_score("Visual Studio Code", "vsc") == 50, "catalog: initials match")
	check(Catalog.match_score("Spotify", "zzz") == 0, "catalog: no match")
	check(Catalog.is_clutter("Uninstall Steam", "x") and Catalog.is_clutter("Steam Support", "https://help.steampowered.com"), "catalog: hides uninstallers and links")
	check(not Catalog.is_clutter("Steam", "C:/Program Files (x86)/Steam/steam.exe"), "catalog: keeps real apps")
	Catalog.set_mock_apps(_mock_apps())
	check(not Catalog.find_app("Chrome").is_empty(), "catalog: apps load")
	check(Catalog.find_app_by_name("Uninstall Discord").is_empty(), "catalog: clutter filtered on load")
	check(Catalog.ref_for_window({"exe": "C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe", "aumid": "Chrome"}) == "app:Chrome", "catalog: window matched by app id")
	check(Catalog.ref_for_window({"exe": "C:\\Apps\\app.exe"}).begins_with("lib:"), "catalog: window matched to a library entry")
	check(Catalog.ref_for_window({"exe": "C:\\Tools\\mystery.exe", "hwnd": 5}) == "win:C:/Tools/mystery.exe", "catalog: unknown windows group by exe")
	check(Catalog.window_group_name({"title": "Inbox - Mail"}) == "Mail", "catalog: group name from title")
	check(Catalog.search("chro").size() > 0 and Catalog.search("chro")[0]["name"] == "Google Chrome", "catalog: search finds apps")
	check(Catalog.search("smoke").size() > 0, "catalog: search finds library entries")
	check(Catalog.is_pinned("app:Chrome"), "catalog: default pins")
	Catalog.set_pinned("app:Spotify", false)
	check(not Catalog.is_pinned("app:Spotify"), "catalog: unpin")
	Catalog.move_pin("app:Chrome", 2)
	check(Catalog.pins().find("app:Chrome") == 2, "catalog: move pin")
	Catalog.reset_pins()
	check(Catalog.pins().slice(0, 2) == ["oazy:library", "app:Chrome"], "catalog: reset pins")
	check(Catalog.item("oazy:library")["name"] == "Library", "catalog: Oazy apps")
	check(Wallpaper.palette_for("night", 12.0) == Wallpaper.PALETTES["night"], "wallpaper: fixed light")
	check(Wallpaper.palette_for("auto", 3.0).size() == Wallpaper.PARAMS.size(), "wallpaper: auto light blends")
	check(App.user_name() == "" or App.user_name().length() > 1, "app: user name")

	# Start's quick answers: sums, addresses, paths and commands.
	check(QuickAnswers.calc("12*4") == "48", "quick: multiply")
	check(QuickAnswers.calc("7/2") == "3.5", "quick: real division")
	check(QuickAnswers.calc("2^10") == "1024", "quick: powers")
	check(QuickAnswers.calc("(1+2) × 3") == "9", "quick: brackets and ×")
	check(QuickAnswers.calc("2,5 * 4") == "10", "quick: decimal comma")
	check(QuickAnswers.calc("sqrt(16)") == "4", "quick: functions")
	check(QuickAnswers.calc("pow(2, 3)") == "8", "quick: function arguments")
	check(QuickAnswers.calc("1/0") == "", "quick: no infinity")
	check(QuickAnswers.calc("chrome") == "" and QuickAnswers.calc("42") == "" and QuickAnswers.calc("OS.kill(1)") == "", "quick: not sums")
	check(QuickAnswers.as_url("github.com") == "https://github.com", "quick: bare domains")
	check(QuickAnswers.as_url("localhost:3000/app") == "http://localhost:3000/app", "quick: localhost")
	check(QuickAnswers.as_url("game.exe") == "" and QuickAnswers.as_url("1.5") == "" and QuickAnswers.as_url("visual studio") == "", "quick: not urls")
	check(QuickAnswers.as_path(OS.get_user_data_dir()) != "" and QuickAnswers.as_path("C:/Nope/Nothing") == "", "quick: paths that exist")
	check(QuickAnswers.commands("lock")[0]["ref"] == "cmd:lock" and int(QuickAnswers.commands("lock")[0]["score"]) >= 90, "quick: exact commands")
	check(QuickAnswers.commands("wifi")[0]["ref"] == "cmd:wifi", "quick: commands by keyword")
	check(QuickAnswers.commands("zzzz").is_empty(), "quick: no command")
	Settings.set_value("recent_apps", ["app:" + str(Catalog.find_app_by_name("Steam")["id"])])
	check(Catalog.search("s")[0]["name"] == "Steam", "catalog: recently opened ranks first")
	Settings.set_value("recent_apps", [])

	# Favourites: anything you can open, in the order you added them.
	var lib_ref := "lib:" + str(Library.entries[0]["id"])
	Catalog.set_favorite(lib_ref, false)
	Catalog.set_favorite("app:Chrome", true)
	Catalog.set_favorite(lib_ref, true)
	check(Catalog.is_favorite("app:Chrome") and Catalog.is_favorite(lib_ref), "favourites: add")
	check(bool(Library.get_entry(lib_ref.substr(4))["favorite"]), "favourites: library entries keep the heart")
	check(Catalog.favorites().slice(0, 2) == ["app:Chrome", lib_ref], "favourites: in the order added")
	check(Catalog.toggle_favorite("app:Chrome") == false and not Catalog.favorites().has("app:Chrome"), "favourites: remove")
	check(not Catalog.can_favorite("web:x") and Catalog.can_favorite("oazy:settings"), "favourites: only things you can open")
	Library.toggle_favorite(lib_ref.substr(4))
	check(not Catalog.is_favorite(lib_ref) and not Catalog.favorites().has(lib_ref), "favourites: follow the library's heart")
	Catalog.set_favorite("app:Chrome", true)

	# Shell mode: a layer's window is cut to the union of what it shows.
	check(not Shell.native, "shell: one window in tests")
	var poly := Shell.union_polygon([Rect2(0, 0, 10, 10), Rect2(50, 50, 10, 10)] as Array[Rect2], 2.0)
	check(poly.size() == 13 and poly[1] == Vector2(0, 0) and poly[8] == Vector2(120, 100), "shell: shape of separate parts")
	check(Shell.union_polygon([Rect2(0, 0, 10, 10), Rect2(5, 5, 10, 10)] as Array[Rect2], 1.0).size() == 7, "shell: overlapping parts merge")
	check(Shell.union_polygon([] as Array[Rect2], 1.0).is_empty(), "shell: nothing to show")


func _mock_apps() -> Array:
	return [
		{"name": "Google Chrome", "id": "Chrome"},
		{"name": "File Explorer", "id": "Microsoft.Windows.Explorer"},
		{"name": "Discord", "id": "com.squirrel.Discord.Discord"},
		{"name": "Uninstall Discord", "id": "C:/Discord/Update.exe"},
		{"name": "Spotify", "id": "SpotifyAB.SpotifyMusic_zpdnekdrzrea0!Spotify"},
		{"name": "Steam", "id": "C:/Program Files (x86)/Steam/steam.exe"},
		{"name": "Visual Studio Code", "id": "Microsoft.VisualStudioCode"},
		{"name": "Terminal", "id": "Microsoft.WindowsTerminal_8wekyb3d8bbwe!App"},
	]


func _ui_tests() -> void:
	var main := get_tree().current_scene
	check(main != null and main.has_method("open_app"), "ui: main scene loaded")
	if main == null:
		return
	var waited := 0.0
	while not main.loaded and waited < 5.0:
		await _wait(0.1)
		waited += 0.1
	check(main.loaded, "ui: loading screen finished")
	await _wait(0.5)
	_layout_checks(main, "desktop")

	# Real-window plumbing (Windows only), otherwise mock windows.
	if App.is_windows():
		await _host_tests()
		Catalog.set_mock_apps(_mock_apps())
	Host.set_mock_windows([
		{"hwnd": 101, "title": "New Tab - Google Chrome", "exe": "C:/Program Files/Google/Chrome/Application/chrome.exe", "aumid": "Chrome", "name": "Google Chrome"},
		{"hwnd": 102, "title": "Docs - Google Chrome", "exe": "C:/Program Files/Google/Chrome/Application/chrome.exe", "aumid": "Chrome", "name": "Google Chrome"},
		{"hwnd": 103, "title": "Mystery", "exe": "C:/Tools/mystery.exe"},
	], 101)
	main.taskbar.rebuild()
	var chrome: TaskbarButton = main.taskbar.button_for("app:Chrome")
	check(chrome != null and chrome.window_count() == 2, "taskbar: groups windows under their pin")
	check(chrome != null and chrome.active, "taskbar: foreground window is active")
	check(main.taskbar.button_for("win:C:/Tools/mystery.exe") != null, "taskbar: unpinned windows get a button")
	if chrome:
		main.preview.show_for(chrome)
		await _wait(0.3)
		check(main.preview.is_showing(), "taskbar: hover preview opens")
		main.preview.hide_preview()
	Host.set_mock_windows([])
	main.taskbar.rebuild()
	check(main.taskbar.button_for("win:C:/Tools/mystery.exe") == null, "taskbar: closed windows disappear")

	# Oazy's own windows.
	var lib: ShellWindow = main.open_app(&"library")
	await _wait(0.6)
	check(lib != null and main.layer.find("oazy:library") == lib, "windows: library opens")
	check(lib != null and lib.active, "windows: new window is active")
	var lib_app: LibraryApp = lib.body.get_child(0)
	check(lib_app.card_count() == Library.entries.size(), "windows: library shows every entry")
	check(main.open_app(&"library") == lib, "windows: reopening focuses the same window")
	var settings: ShellWindow = main.open_app(&"settings")
	await _wait(0.5)
	check(settings.active and not lib.active, "windows: focus moves to the newest")
	check(main.taskbar.button_for("oazy:settings") != null and main.taskbar.button_for("oazy:settings").window_count() == 1, "windows: shell windows on the taskbar")
	_window_checks(main, lib, "library")
	_window_checks(main, settings, "settings")
	settings.toggle_maximize()
	await _wait(0.5)
	check(settings.maximized and main.layer.work_rect().grow(1.0).encloses(settings.get_rect()), "windows: maximise fills the work area")
	settings.toggle_maximize()
	await _wait(0.5)
	check(not settings.maximized, "windows: restore")
	settings.minimize()
	await _wait(0.5)
	check(settings.minimized and not settings.visible, "windows: minimise")
	main.toggle_shell_window(settings)
	await _wait(0.5)
	check(not settings.minimized and settings.visible and settings.active, "windows: taskbar brings it back")
	main.focus_entry(str(Library.recent()[0]["id"]))
	await _wait(0.6)
	main.show_desktop()
	await _wait(0.5)
	check(lib.minimized and settings.minimized, "windows: show desktop minimises all")
	main.show_desktop()
	await _wait(0.5)
	check(not lib.minimized, "windows: show desktop again restores")
	settings.close()
	await _wait(0.5)
	check(main.layer.find("oazy:settings") == null, "windows: close")

	# Start.
	main.start.open()
	await _wait(0.4)
	check(main.start.is_open, "start: opens")
	check(main.get_viewport_rect().grow(1.0).encloses(main.start.get_global_rect()), "start: fits on screen")
	check(main.start.get_global_rect().end.y <= main.taskbar.get_global_rect().position.y + 1.0, "start: sits above the taskbar")
	var inner: Rect2 = main.start._root.get_global_rect()
	check(main.start.get_global_rect().grow(1.0).encloses(inner), "start: content stays inside the glass")
	var sr: Rect2 = main.start._glass.shadow_rect()
	check(sr.encloses(main.start.get_global_rect()) and sr.end.y - main.start.get_global_rect().end.y > sr.position.y - main.start.get_global_rect().position.y - 0.01, "start: layer shape covers the shadow, more below than above")
	main.start.open("chro")
	await _wait(0.3)
	check(main.start._rows.size() > 1, "start: search shows results")
	main.start.close()
	await _wait(0.4)
	check(not main.start.is_open, "start: closes")

	# Dialogs, launching and overlays.
	var first_id := str(Library.recent()[0]["id"])
	main.open_edit(first_id)
	main.open_add({"name": "Dropped", "path": "C:/x.exe"})
	main.show_entry_menu(first_id, Vector2(200, 200))
	await _wait(0.30)
	check(main.modal_open(), "ui: dialogs open")
	check(_menu_has(main._menu, "favourites"), "favourites: in the library menu")
	main._menu.hide()
	main.show_ref_menu("app:Chrome", Vector2(200, 200))
	check(_menu_has(main._menu, "Remove from favourites"), "favourites: in app menus")
	main._menu.hide()
	main.taskbar._on_context(main.taskbar.button_for("app:Chrome"), Vector2(400, 800))
	check(_menu_has(main.taskbar._menu, "favourites"), "favourites: in the taskbar menu")
	main.taskbar._menu.hide()
	main.start.open()
	await _wait(0.3)
	check(main.start._favs.visible and main.start._favs.get_child_count() > 0, "favourites: at the top of Start")
	check(main.start.get_global_rect().end.y <= main.taskbar.get_global_rect().position.y + 1.0, "favourites: Start still fits")
	main.start._show_menu("app:Chrome", Vector2(300, 300))
	check(_menu_has(main.start._menu, "favourites"), "favourites: in Start's menu")
	main.start._menu.hide()
	main.start.close()
	check(main.desktop._favs_glass.visible and main.desktop._favs.get_child_count() > 0, "favourites: on the desktop")
	for m in get_tree().get_nodes_in_group("modal"):
		m.close()
	await _wait(0.60)
	check(not main.modal_open(), "ui: dialogs close")
	main.launch(first_id)
	await _wait(0.30)
	Updater.apply_releases([{"tag_name": "v99.0.0", "body": "- Big", "assets": [{"name": "OazyLauncher.exe", "size": 1, "browser_download_url": "https://x"}]}], App.version)
	main.show_update()
	main.show_patch_notes()
	main.toasts.show_toast("Smoke toast", &"success")
	await _wait(0.90)
	check(Icons.tex("play", 24) != null and Icons.tex("leaf", 24) != null, "ui: icons render")
	for m in get_tree().get_nodes_in_group("modal"):
		if m.has_method("close"):
			m.close()
	await _wait(0.6)
	_layout_checks(main, "end")


## On Windows, the helper must build, connect and answer.
func _host_tests() -> void:
	var waited := 0.0
	while not Host.available and not Host.failed and waited < 30.0:
		await _wait(0.2)
		waited += 0.2
	check(Host.available, "host: connects (%s)" % Host.fail_reason)
	if not Host.available:
		return
	var got := {}
	Host.request(["windows"], func(d: Dictionary) -> void: got["windows"] = d)
	Host.request(["apps"], func(d: Dictionary) -> void: got["apps"] = d)
	Host.request(["stats"], func(d: Dictionary) -> void: got["stats"] = d)
	Host.render_icon("C:/Windows/explorer.exe", 64, ProjectSettings.globalize_path("user://smoke/explorer.png"), func(d: Dictionary) -> void: got["icon"] = d)
	waited = 0.0
	while got.size() < 4 and waited < 30.0:
		await _wait(0.2)
		waited += 0.2
	check(got.has("windows") and got["windows"].get("ok", false), "host: lists windows")
	check(got.has("apps") and got["apps"].get("apps", []).size() > 0, "host: lists installed apps")
	check(got.has("stats") and got["stats"].has("cpu"), "host: system stats")
	check(got.has("icon") and FileAccess.file_exists("user://smoke/explorer.png"), "host: renders icons (%s)" % str(got.get("icon", {}).get("error", "no reply")))
	check(Host.available, "host: still running after the checks")


func _window_checks(main: Node, win: ShellWindow, where: String) -> void:
	var work: Rect2 = main.layer.work_rect().grow(1.0)
	check(work.encloses(win.get_global_rect()), "layout(%s): window inside the work area" % where)
	check(win.size.x >= ShellWindow.MIN_SIZE.x and win.size.y >= ShellWindow.MIN_SIZE.y, "layout(%s): window has a usable size" % where)
	check(win.body.size.x > win.size.x * 0.9 and win.body.size.y > win.size.y * 0.7, "layout(%s): window content fills it" % where)


## Catches the class of bug where a panel is anchored but never sized.
func _layout_checks(main: Node, where: String) -> void:
	var vp: Vector2 = main.get_viewport_rect().size
	var screen := Rect2(Vector2.ZERO, vp).grow(1.0)
	check(vp.x > 100.0 and vp.y > 100.0, "layout(%s): viewport has a size" % where)
	check(main.size.distance_to(vp) < 1.0, "layout(%s): main fills the window" % where)
	check(main.wallpaper.size.distance_to(vp) < 1.0, "layout(%s): wallpaper fills the window" % where)
	var bar: Rect2 = main.taskbar.get_global_rect()
	check(screen.encloses(bar) and bar.size.x > vp.x * 0.9 and bar.size.y >= 60.0, "layout(%s): taskbar spans the bottom" % where)
	check(bar.end.y > vp.y - 20.0, "layout(%s): taskbar at the bottom" % where)
	check(screen.encloses(main.taskbar.orb.get_global_rect()), "layout(%s): Start orb on screen" % where)
	check(main.layer.work_rect().end.y <= bar.position.y + 1.0, "layout(%s): windows stay above the taskbar" % where)
	check(main.desktop.size.distance_to(vp) < 1.0, "layout(%s): desktop fills the window" % where)


func _menu_has(menu: PopupMenu, text: String) -> bool:
	for i in menu.item_count:
		if menu.get_item_text(i).contains(text):
			return true
	return false


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _finish() -> void:
	print("SMOKE: %d checks, %d failed" % [_checks, _failures.size()])
	if _failures.is_empty():
		print("SMOKE: PASS")
		get_tree().quit(0)
	else:
		print("SMOKE: FAIL\n  - " + "\n  - ".join(_failures))
		get_tree().quit(1)
