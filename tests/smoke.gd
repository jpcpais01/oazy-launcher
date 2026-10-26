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

	# Store discovery from the installed-programs list and Xbox games.
	var reg := "\r\nHKEY_LOCAL_MACHINE\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\Riot Game valorant.live\r\n    DisplayName    REG_SZ    VALORANT\r\n    UninstallString    REG_SZ    \"C:\\Riot Games\\Riot Client\\RiotClientServices.exe\" --uninstall-product=valorant --uninstall-patchline=live\r\n\r\nHKEY_LOCAL_MACHINE\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\Uplay Install 5059\r\n    DisplayName    REG_SZ    Rainbow Six Siege\r\n\r\nHKEY_LOCAL_MACHINE\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\Overwatch\r\n    DisplayName    REG_SZ    Overwatch\r\n    DisplayIcon    REG_SZ    \"C:\\Program Files (x86)\\Overwatch\\Overwatch Launcher.exe\"\r\n    UninstallString    REG_SZ    \"C:\\ProgramData\\Battle.net\\Agent\\Blizzard Uninstaller.exe\" --lang=enUS --uid=prometheus\r\n\r\nHKEY_LOCAL_MACHINE\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\Riot Client\r\n    DisplayName    REG_SZ    Riot Client\r\n    UninstallString    REG_SZ    \"C:\\Riot Games\\Riot Client\\RiotClientServices.exe\" --uninstall-product=riot_client\r\n\r\nHKEY_LOCAL_MACHINE\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\7-Zip\r\n    DisplayName    REG_SZ    7-Zip\r\n    SystemComponent    REG_DWORD    0x0\r\n"
	var blocks := Library.parse_reg_blocks(reg, Library.UNINSTALL_VALUES)
	check(blocks.size() == 5 and blocks[1]["_key"] == "Uplay Install 5059", "discovery: reads registry blocks")
	var stores := Library.scan_uninstall_entries(blocks)
	check(stores.size() == 3, "discovery: keeps games, skips launchers and other programs")
	check(stores[0]["source"] == "riot" and stores[0]["path"] == "C:/Riot Games/Riot Client/RiotClientServices.exe" and stores[0]["args"] == "--launch-product=valorant --launch-patchline=live", "discovery: riot games launch through the client")
	check(stores[1]["path"] == "uplay://launch/5059/0", "discovery: ubisoft launch link")
	check(stores[2]["source"] == "battlenet" and stores[2]["path"].ends_with("Overwatch Launcher.exe"), "discovery: battle.net game exe")
	var xb := Library.xbox_item("<Game><Identity Name=\"Microsoft.Forza5\" Version=\"1\"/><ExecutableList><Executable Name=\"ForzaHorizon5.exe\" Id=\"Game\"/></ExecutableList><ShellVisuals DefaultDisplayName=\"Forza Horizon 5\"/></Game>", "D:/XboxGames/Forza Horizon 5/Content")
	check(xb.get("name") == "Forza Horizon 5" and xb.get("path") == "D:/XboxGames/Forza Horizon 5/Content/ForzaHorizon5.exe" and xb.get("xbox_package") == "Microsoft.Forza5", "discovery: xbox game config")
	var genshin := Library.uninstall_item({"_key": "Genshin Impact", "DisplayName": "Genshin Impact", "Publisher": "COGNOSPHERE PTE. LTD.", "DisplayIcon": "C:\\Games\\Genshin Impact\\GenshinImpact.exe"})
	check(genshin.get("source") == "custom" and str(genshin.get("path")).ends_with("GenshinImpact.exe"), "discovery: standalone game from a game publisher")
	check(Library.uninstall_item({"_key": "HoYoPlay", "DisplayName": "HoYoPlay Launcher", "Publisher": "COGNOSPHERE", "DisplayIcon": "C:\\x\\launcher.exe"}).is_empty(), "discovery: publisher launchers are not games")
	check(Library.uninstall_item({"_key": "Notepad++", "DisplayName": "Notepad++", "Publisher": "Notepad++ Team", "DisplayIcon": "C:\\Program Files\\Notepad++\\notepad++.exe"}).is_empty(), "discovery: ordinary programs are not games")
	check(Art.gamesdb_ref({"source": "riot", "args": "--launch-product=league_of_legends --launch-patchline=live"}) == "riot/league_of_legends", "art: riot games use galaxy's riot ids")
	check(Art.gamesdb_ref({"source": "ubisoft", "path": "uplay://launch/635/0"}) == "uplay/635", "art: ubisoft games use galaxy's uplay ids")
	# Your own games: Godot exports and art dropped next to the exe.
	var gd_dir := "user://smoke/own_games/My Game"
	DirAccess.make_dir_recursive_absolute(gd_dir)
	var gd_exe := FileAccess.open(gd_dir.path_join("my_game.exe"), FileAccess.WRITE)
	var junk := PackedByteArray()
	junk.resize(1024)
	gd_exe.store_buffer(junk)
	gd_exe.store_buffer("GDPC".to_ascii_buffer())
	gd_exe.close()
	check(Library.is_godot_exe(gd_dir.path_join("my_game.exe")), "own games: godot export recognised")
	var own := Library.scan_game_folders([{"path": "user://smoke/own_games", "any": false}])
	check(own.size() == 1 and own[0]["name"] == "My Game" and own[0]["kind"] == "game", "own games: found in a folder")
	gd_dir = ProjectSettings.globalize_path(gd_dir)
	for art_file in ["My_Game_banner.png", "cover.jpg", "other_logo.png"]:
		var af := FileAccess.open(gd_dir.path_join(art_file), FileAccess.WRITE)
		af.store_string("x")
		af.close()
	check(Art.sidecar_art(gd_dir.path_join("my_game.exe"), &"hero").has(gd_dir.path_join("My_Game_banner.png")), "own games: <name>_banner.png next to the exe is art")
	check(Art.sidecar_art(gd_dir.path_join("my_game.exe"), &"cover").has(gd_dir.path_join("cover.jpg")), "own games: plain cover.jpg is art")
	check(Art.sidecar_art(gd_dir.path_join("my_game.exe"), &"logo").is_empty(), "own games: another game's logo is ignored")

	check(Art.brand_art("Claude Code", &"hero").ends_with("claudecode_hero.webp.bin") and Art.brand_art("Visual Studio Code", &"cover") != "" and Art.brand_art("Discord", &"logo") != "", "art: built-in app art by name")
	check(Art.decode(FileAccess.get_file_as_bytes(Art.brand_art("Higgsfield", &"cover"))) != null, "art: built-in app art decodes")
	check(Art.brand_art("Some Random Game", &"cover") == "", "art: no built-in art for unknown names")

	var deduped := Library.dedupe_found([{"name": "Apex Legends", "kind": "game", "source": "ea", "path": "a"}, {"name": "Apex Legends™", "kind": "game", "source": "steam", "path": "b"}])
	check(deduped.size() == 1 and deduped[0]["source"] == "steam", "discovery: one tile per game, best store wins")
	check(not Catalog.is_clutter("Debugger Pro", "x") and Catalog.is_clutter("Game Setup", "x") and Catalog.is_clutter("Thing", "C:/Thing/unins000.exe"), "catalog: clutter matches whole words and helper exes")

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
	check(Catalog.ref_for_window({"exe": "C:\\Windows\\explorer.exe", "name": "Windows Explorer"}) == "app:Microsoft.Windows.Explorer", "catalog: folder windows group with File Explorer")
	check(Catalog.ref_for_window({"exe": "C:\\Program Files\\WindowsApps\\5319275A.WhatsAppDesktop_2.2540.6.0_x64__cv1g1gvanyjgm\\WhatsApp.Root.exe", "name": "WhatsApp.Root"}) == "app:5319275A.WhatsAppDesktop_cv1g1gvanyjgm!App", "catalog: Store app windows group with their app")
	check(Catalog.ref_for_window({"exe": "D:\\Apps\\WhatsApp.Root.exe"}) == "app:5319275A.WhatsAppDesktop_cv1g1gvanyjgm!App", "catalog: window matched by its file name's first word")
	check(Catalog.window_group_name({"title": "Inbox - Mail"}) == "Mail", "catalog: group name from title")
	check(Catalog.search("chro").size() > 0 and Catalog.search("chro")[0]["name"] == "Google Chrome", "catalog: search finds apps")
	check(Catalog.search("smoke").size() > 0, "catalog: search finds library entries")
	check(Catalog.is_pinned("app:Chrome"), "catalog: default pins")
	Catalog.set_pinned("app:Spotify", false)
	check(not Catalog.is_pinned("app:Spotify"), "catalog: unpin")
	Catalog.move_pin("app:Chrome", 2)
	check(Catalog.pins().find("app:Chrome") == 2, "catalog: move pin")
	Catalog.reset_pins()
	check(Catalog.pins().slice(0, 3) == ["oazy:library", "oazy:browser", "app:Chrome"], "catalog: reset pins")
	check(Catalog.item("oazy:library")["name"] == "Library", "catalog: Oazy apps")

	# Installed apps joining the library take their pin and windows with them.
	check(Catalog.can_add_to_library("app:Chrome"), "library apps: installed app can be added")
	var before := FindAppsDialog.candidates().size()
	var chrome := Catalog.add_to_library("app:Chrome")
	check(chrome != "" and Library.get_entry(chrome)["kind"] == "app", "library apps: added as an app")
	check(Catalog.add_to_library("app:Chrome") == chrome and not Catalog.can_add_to_library("app:Chrome"), "library apps: added once")
	check(Catalog.is_pinned("lib:" + chrome) and Settings.get_value("pins").has("lib:" + chrome) and not Settings.get_value("pins").has("app:Chrome"), "library apps: pin moves to the entry")
	check(Catalog.canonical("app:Chrome") == "lib:" + chrome and Catalog.is_pinned("app:Chrome"), "one ref: the Start app is its library entry")
	check(Catalog.ref_for_window({"exe": "C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe", "aumid": "Chrome"}) == "lib:" + chrome, "library apps: windows group with the entry")
	check(FindAppsDialog.candidates().size() == before - 1, "library apps: Find apps skips what's in the library")
	check(not Catalog.all_items().any(func(it: Dictionary) -> bool: return it["ref"] == "app:Chrome"), "library apps: no duplicate in All apps")
	Catalog.remove_from_library(chrome)
	check(Catalog.is_pinned("app:Chrome") and Catalog.can_add_to_library("app:Chrome"), "library apps: pin goes back on removal")

	# Oazy Browser: an Oazy app whose windows are real ones.
	check(Catalog.item(Browser.REF)["name"] == "Browser" and Catalog.item(Browser.REF)["kind"] == "oazy", "browser: in the catalog")
	check(Catalog.ref_for_window({"exe": "C:\\Users\\me\\AppData\\Roaming\\OazyLauncher\\browser\\app-1234abcd\\OazyBrowser.exe"}) == Browser.REF, "browser: windows group under the browser")
	check(Catalog.ref_for_window({"exe": "C:\\Games\\OazyBrowser.exe"}) != Browser.REF, "browser: only our own build")
	check(Catalog.search("brow").size() > 0 and Catalog.search("brow")[0]["ref"] == Browser.REF, "browser: found from Start")
	# On Windows Flow has already joined the Library by itself; start from the bare app.
	if Catalog.library_entry_for_oazy("oazy:flow") != "":
		check(App.is_windows(), "flow: joins the Library by itself only on Windows")
		Catalog.remove_from_library(Catalog.library_entry_for_oazy("oazy:flow"))
	check(Catalog.item("oazy:flow")["name"] == "Flow" and Catalog.is_own_window_app("oazy:flow"), "flow: a web app of the browser")
	check(Catalog.ref_for_window({"exe": "C:\\Users\\me\\AppData\\Roaming\\OazyLauncher\\browser\\app-1234abcd\\OazyBrowser.exe", "title": "Flow"}) == "oazy:flow", "flow: its window groups under Flow")
	check(Catalog.ref_for_window({"exe": "C:\\Users\\me\\AppData\\Roaming\\OazyLauncher\\browser\\app-1234abcd\\OazyBrowser.exe", "title": "Flow - Oazy Browser"}) == Browser.REF, "flow: a browser tab about Flow stays the browser's")
	check(Catalog.search("flow").size() > 0 and Catalog.search("flow")[0]["ref"] == "oazy:flow", "flow: found from Start")
	check(Art.brand_art("Flow", &"cover") != "" and Art.brand_art("Flow", &"hero") != "" and Art.brand_art("Flow", &"logo") != "", "flow: has its own art")
	check(Catalog.can_add_to_library("oazy:flow"), "flow: can join the Library")
	var flow_id := Catalog.add_to_library("oazy:flow")
	check(flow_id != "" and Catalog.canonical("oazy:flow") == "lib:" + flow_id, "flow: is its library card everywhere")
	check(Catalog.item("lib:" + flow_id)["oazy"] == "oazy:flow" and Catalog.item("lib:" + flow_id)["kind"] == "libapp", "flow: its card keeps Flow's icon")
	check(Catalog.ref_for_window({"exe": "C:\\Users\\me\\AppData\\Roaming\\OazyLauncher\\browser\\app-1234abcd\\OazyBrowser.exe", "title": "Flow"}) == "lib:" + flow_id, "flow: its window groups under its card")
	var oazy_claude := Catalog.add_to_library("oazy:claude")
	check(Catalog.library_entry_named("Claude") != oazy_claude, "library apps: Oazy's Claude isn't taken for the Claude app")
	Catalog.remove_from_library(oazy_claude)
	Catalog.remove_from_library(flow_id)
	check(Catalog.canonical("oazy:flow") == "oazy:flow", "flow: leaves the Library cleanly")
	for f in Browser.FILES:
		check(FileAccess.file_exists(Browser.SRC.path_join(f)), "browser: packaged " + f)

	# Account: Google photo sizes, and who Oazy greets.
	check(Account.big_photo("https://lh3.googleusercontent.com/a/ACg8x=s96-c") == "https://lh3.googleusercontent.com/a/ACg8x=s256-c", "account: photo asked for bigger")
	check(Account.big_photo("https://lh3.googleusercontent.com/a/ACg8x") == "https://lh3.googleusercontent.com/a/ACg8x=s256-c", "account: photo without a size gets one")
	check(Account.big_photo("https://lh3.googleusercontent.com/-a/AAAA/s64-c/photo.jpg") == "https://lh3.googleusercontent.com/-a/AAAA/s256-c/photo.jpg", "account: old-style photo url resized")
	check(Account.big_photo("file:///x.png") == "", "account: only web photos")
	check(not Account.signed_in(), "account: nobody signed in during the smoke test")
	Account.set_mock({"name": "Ana Sousa", "email": "ana@example.com"})
	check(Account.signed_in() and Account.display_name() == "Ana Sousa" and Account.first_name() == "Ana", "account: Google name in Start and the greeting")
	Settings.set_value("user_name", "Nina")
	check(Account.first_name() == "Nina" and Account.display_name() == "Ana Sousa", "account: your own greeting name wins over Google's")
	Settings.set_value("user_name", "")
	Account.set_mock({})
	check(not Account.signed_in(), "account: mock signed out")
	if App.is_windows():
		var built := Browser.build()
		check(built.has("exe"), "browser: compiles on Windows (%s)" % str(built.get("error", "ok")))

	# Oazy Terminal: shells on pseudoconsoles, in an Oazy window of its own.
	check(Catalog.item(Terminal.REF)["kind"] == "oazy", "terminal: in the catalog")
	check(Catalog.ref_for_window({"exe": "C:\\Users\\me\\AppData\\Roaming\\OazyLauncher\\terminal\\app-1234abcd\\OazyTerminal.exe", "title": "PowerShell - Oazy Terminal"}) == Terminal.REF, "terminal: windows group under the terminal")
	check(Catalog.pins().has(Terminal.REF), "terminal: pinned")
	check(Terminal.profile_for({"ref": "app:Microsoft.WindowsTerminal_8wekyb3d8bbwe!App", "name": "Terminal"}) == "", "terminal: takes over Windows Terminal")
	check(Terminal.profile_for({"ref": "app:{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\\cmd.exe", "name": "Command Prompt"}) == "cmd", "terminal: Command Prompt opens as cmd")
	check(Terminal.profile_for({"ref": "app:{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\\WindowsPowerShell\\v1.0\\powershell.exe", "name": "Windows PowerShell"}) == "powershell", "terminal: PowerShell opens as powershell")
	check(Terminal.profile_for({"ref": "app:{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\\WindowsPowerShell\\v1.0\\powershell_ise.exe", "name": "Windows PowerShell ISE"}) == "-", "terminal: leaves the ISE alone")
	check(Terminal.profile_for({"ref": "app:Chrome", "name": "Google Chrome"}) == "-", "terminal: leaves other apps alone")
	check(Terminal.runs_shell("C:/Windows/System32/cmd.exe") and not Terminal.runs_shell("C:/Games/game.exe"), "terminal: shell library entries")
	var term_files := Terminal.files()
	for f in term_files:
		check(FileAccess.file_exists(str(term_files[f])), "terminal: packaged " + str(f))
	if App.is_windows():
		var built_term := Terminal.build()
		check(built_term.has("exe"), "terminal: compiles on Windows (%s)" % str(built_term.get("error", "ok")))
	# Oazy Files: folders in an Oazy window, standing in for File Explorer.
	check(Catalog.item(Files.REF)["kind"] == "oazy", "files: in the catalog")
	check(Catalog.is_own_window_app(Files.REF), "files: its own window")
	var fe_ref := Catalog.ref_for_window({"exe": "C:\\Users\\me\\AppData\\Roaming\\OazyLauncher\\files\\app-1234abcd\\OazyFiles.exe", "title": "Downloads - Oazy Files"})
	check(fe_ref == Files.REF or fe_ref.begins_with("app:"), "files: windows group under Files or File Explorer")
	check(Files.is_explorer({"ref": "app:Microsoft.Windows.Explorer", "name": "File Explorer"}), "files: takes over File Explorer")
	check(not Files.is_explorer({"ref": "app:Chrome", "name": "Google Chrome"}), "files: leaves other apps alone")
	check(Settings.get_value("files_oazy") == true, "files: on by default")
	var files_files := Files.files()
	for f in files_files:
		check(FileAccess.file_exists(str(files_files[f])), "files: packaged " + str(f))
	if App.is_windows():
		var built_files := Files.build()
		check(built_files.has("exe"), "files: compiles on Windows (%s)" % str(built_files.get("error", "ok")))
	# Oazy Claude: Claude Code in an Oazy window.
	check(Catalog.item(ClaudeApp.REF)["kind"] == "oazy" and Catalog.is_own_window_app(ClaudeApp.REF), "claude: in the catalog, its own window")
	check(Catalog.ref_for_window({"exe": "C:\\Users\\me\\AppData\\Roaming\\OazyLauncher\\claude\\app-1234abcd\\OazyClaude.exe", "title": "Claude - Fix the build"}) == ClaudeApp.REF, "claude: windows group under it")
	check(Catalog.search("claude").any(func(it: Dictionary) -> bool: return it["ref"] == ClaudeApp.REF), "claude: found from Start")
	if App.is_windows():
		check(Catalog.pins().has(ClaudeApp.REF), "claude: pinned")
	var claude_files := ClaudeApp.files()
	for f in claude_files:
		check(FileAccess.file_exists(str(claude_files[f])), "claude: packaged " + str(f))
	if App.is_windows():
		var built_claude := ClaudeApp.build()
		check(built_claude.has("exe"), "claude: compiles on Windows (%s)" % str(built_claude.get("error", "ok")))
	check(Wallpaper.palette_for("night", 12.0) == Wallpaper.PALETTES["night"], "wallpaper: fixed light")
	check(Wallpaper.palette_for("auto", 3.0).size() == Wallpaper.PARAMS.size(), "wallpaper: auto light blends")
	check(Wallpaper.style_index("tide") == 2 and Wallpaper.style_index("gone") == 0, "wallpaper: styles, unknown falls back to Oasis")
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

	# One thing, one ref: a game's Start shortcut, or its window, is the game.
	Catalog.set_mock_apps(_mock_apps() + [{"name": "Smoke Game™", "id": "C:/Games/Smoke Launcher.exe"}])
	var game_ref := "lib:" + str(Library.entries[0]["id"])
	check(Catalog.canonical("app:C:/Games/Smoke Launcher.exe") == game_ref, "one ref: a game's Start shortcut is the game")
	check(Catalog.canonical("win:C:/Games/smoke.exe") == game_ref and Catalog.ref_for_window({"exe": "C:\\Games\\smoke.exe"}) == game_ref, "one ref: a game's window is the game")
	check(not Catalog.all_items().any(func(it: Dictionary) -> bool: return it["ref"] == "app:C:/Games/Smoke Launcher.exe"), "one ref: no Start duplicate of a game")
	Catalog.set_favorite(game_ref, false)
	Settings.set_value("favorites", ["app:C:/Games/Smoke Launcher.exe", "app:Chrome"])
	Catalog._tidy()
	check(Settings.get_value("favorites") == [game_ref, "app:Chrome"] and bool(Library.get_entry(game_ref.substr(4))["favorite"]), "one ref: an old Start-shortcut favourite becomes the game's heart")
	Catalog.set_favorite("win:C:/Games/smoke.exe", true)
	check(Catalog.favorites().count(game_ref) == 1 and Catalog.is_favorite("app:C:/Games/Smoke Launcher.exe"), "one ref: favourited anywhere, one favourite")
	Catalog.set_mock_apps(_mock_apps())

	# Weather: codes, units and reading the forecast offline.
	check(Weather.kind_for(0) == "clear" and Weather.kind_for(2) == "partly" and Weather.kind_for(63) == "rain" and Weather.kind_for(81) == "rain", "weather: codes to icons")
	check(Weather.kind_for(73) == "snow" and Weather.kind_for(96) == "storm" and Weather.kind_for(45) == "fog", "weather: more codes")
	var ws: GDScript = load("res://tests/weather_sample.gd")
	Weather.set_mock(ws.place(), ws.forecast())
	check(Weather.temp(18.4) == "18°" and not Weather.fahrenheit(), "weather: celsius in Portugal")
	Settings.set_value("weather_unit", "f")
	check(Weather.temp(20.0) == "68°" and Weather.wind(16.09) == "10 mph", "weather: fahrenheit")
	Settings.set_value("weather_unit", "auto")
	check(int(Weather.current()["humidity"]) == 64, "weather: current conditions")
	check(Weather.hours(7, 2).size() == 7 and Weather.days().size() >= 6, "weather: hours and days ahead")
	Weather.updated -= 3 * 3600
	var old := Weather.current()
	check(not old.is_empty() and int(old["humidity"]) == -1, "weather: old data falls back to the hourly forecast")
	Weather.updated += 3 * 3600
	check(WeatherIcons.tex("storm", false, 32).get_width() == 32, "weather: icons render")

	# Shell mode: a layer's window is cut to the union of what it shows.
	check(not Shell.native, "shell: one window in tests")
	var poly := Shell.union_polygon([Rect2(0, 0, 10, 10), Rect2(50, 50, 10, 10)] as Array[Rect2], 2.0)
	check(poly.size() == 13 and poly[1] == Vector2(0, 0) and poly[8] == Vector2(120, 100), "shell: shape of separate parts")
	check(Shell.union_polygon([Rect2(0, 0, 10, 10), Rect2(5, 5, 10, 10)] as Array[Rect2], 1.0).size() == 7, "shell: overlapping parts merge")
	check(Shell.union_polygon([] as Array[Rect2], 1.0).is_empty(), "shell: nothing to show")
	check(AppIcon.custom_look({"ref": "app:Microsoft.Windows.Explorer", "name": "File Explorer"})[0] == "folder", "icons: File Explorer gets Oazy's folder")
	check(AppIcon.custom_look({"ref": "win:C:/Windows/explorer.exe", "name": "Windows Explorer"})[0] == "folder", "icons: Explorer windows too")
	check(AppIcon.custom_look({"ref": "app:Microsoft.WindowsTerminal_8wekyb3d8bbwe!App", "name": "Terminal"})[0] == "terminal", "icons: Terminal gets Oazy's terminal")
	check(AppIcon.custom_look({"ref": "lib:x", "name": "Claude Code", "icon_key": "C:\\Windows\\System32\\cmd.exe"})[0] == "claude_code", "icons: Claude Code gets Claude's, not the terminal's")
	check(AppIcon.custom_look({"ref": "win:C:/Users/j/AppData/Local/AnthropicClaude/app-1.0/claude.exe", "name": "Claude"})[0] == "claude", "icons: the Claude app")
	check(AppIcon.custom_look({"ref": "app:5319275A.WhatsAppDesktop_cv1g1gvanyjgm!App", "name": "WhatsApp"})[0] == "whatsapp", "icons: WhatsApp")
	check((Settings.get_value("custom_icons_offered") as Array).has("whatsapp"), "icons: new defaults are offered once")
	check(AppIcon.custom_look({"ref": "app:Chrome", "name": "Google Chrome"}).is_empty(), "icons: other apps keep their icons")

	# Mouse pointers: ten complete themes, unpacked into real Windows cursors.
	check(Cursors.theme_ids().size() == 10, "pointers: ten themes")
	check(Cursors.selected() == "oazy", "pointers: Oazy's own by default")
	var missing := PackedStringArray()
	for theme in Cursors.theme_ids():
		for glyph in CursorSets.GLYPHS:
			if Cursors.preview(theme, glyph) == null:
				missing.append("%s/%s" % [theme, glyph])
	check(missing.is_empty(), "pointers: every glyph has a preview %s" % str(missing))
	var dir := Cursors._prepare("lagoon")
	var files := DirAccess.get_files_at(dir) if dir != "" else PackedStringArray()
	check(files.has("arrow.cur") and files.has("hand.cur") and files.has("busy.ani") and files.has("working.ani") and files.size() == CursorSets.GLYPHS.size() + 1, "pointers: theme unpacks to a full set (%s)" % str(files))
	if files.has("busy.ani"):
		var ani := FileAccess.get_file_as_bytes(dir.path_join("busy.ani"))
		check(ani.slice(0, 4).get_string_from_ascii() == "RIFF" and ani.slice(8, 12).get_string_from_ascii() == "ACON" and ani.decode_u32(4) == ani.size() - 8, "pointers: busy spinner is a valid animated cursor")
		var cur := FileAccess.get_file_as_bytes(dir.path_join("arrow.cur"))
		check(cur.decode_u16(2) == 2 and cur.decode_u16(4) == CursorSets.SIZES.size(), "pointers: arrow has every size")


	# The desktop's second screen: market quotes and headlines.
	var chart := {"chart": {"result": [{"meta": {"symbol": "AAPL", "regularMarketPrice": 258.1, "chartPreviousClose": 250.0, "currency": "USD", "shortName": "Apple Inc."},
		"timestamp": [1, 2, 3], "indicators": {"quote": [{"close": [251.0, null, 258.1]}]}}], "error": null}}
	var q := Markets.parse_chart(chart)
	check(q.get("symbol") == "AAPL" and is_equal_approx(float(q.get("prev", 0)), 250.0) and (q.get("points", []) as Array).size() == 2, "markets: parses a chart, skipping gaps")
	check(Markets.parse_chart({"chart": {"result": null, "error": {"code": "Not Found"}}}).is_empty(), "markets: unknown symbol is empty")
	check(Array(Markets.parse_symbols("aapl, ^gspc  btc-usd;AAPL")) == ["AAPL", "^GSPC", "BTC-USD"], "markets: symbols from typed text")
	check(Markets.format_price(6712.4, "USD") == "$6,712.40" and Markets.format_price(111842.0, "USD") == "$111,842" and Markets.format_price(0.5) == "0.5000" and Markets.format_price(9.999) == "10.00", "markets: price formatting")
	var rss := "<?xml version=\"1.0\"?><rss><channel><title>Top stories</title><item><title>Big news about something important - Reuters</title><link>https://news.example/a</link><pubDate>Sun, 26 Oct 2026 10:00:00 GMT</pubDate><source url=\"https://reuters.com\">Reuters</source></item><item><title><![CDATA[Older &amp; smaller story here]]></title><link>https://news.example/b</link><pubDate>Sun, 26 Oct 2026 11:00:00 +0200</pubDate></item></channel></rss>"
	var items := News.parse_rss(rss.to_utf8_buffer())
	check(items.size() == 2 and items[0]["title"] == "Big news about something important" and items[0]["source"] == "Reuters", "news: Google-style title and source")
	check(items.size() == 2 and int(items[0]["at"]) > int(items[1]["at"]), "news: newest first, time zones applied")
	check(News.parse_date("Sun, 26 Oct 2026 10:00:00 GMT") == Time.get_unix_time_from_datetime_string("2026-10-26T10:00:00"), "news: RFC 822 dates")

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
		{"name": "WhatsApp", "id": "5319275A.WhatsAppDesktop_cv1g1gvanyjgm!App"},
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

	# Scrolling down to the second screen and back.
	var desk: Desktop = main.desktop
	check(not desk.below.visible, "desktop: second screen parked until scrolled to")
	desk.page(1)
	await _wait(1.5)
	check(desk.below.visible and not desk._top.visible and is_equal_approx(desk.below.position.y, 0.0), "desktop: glides to the second screen and parks the first")
	check(desk.below._cards.get_child_count() == mini(DesktopBelow.CARDS, DesktopBelow.top_refs().size()), "desktop: second screen has its covers")
	desk.page(-1)
	await _wait(1.5)
	check(desk._top.visible and not desk.below.visible and desk._top.position.y == 0.0, "desktop: glides back up")

	# Real-window plumbing (Windows only), otherwise mock windows.
	if App.is_windows():
		await _host_tests()
		Catalog.set_mock_apps(_mock_apps())
	Host.set_mock_windows([
		{"hwnd": 101, "title": "New Tab - Google Chrome", "exe": "C:/Program Files/Google/Chrome/Application/chrome.exe", "aumid": "Chrome", "name": "Google Chrome"},
		{"hwnd": 102, "title": "Docs - Google Chrome", "exe": "C:/Program Files/Google/Chrome/Application/chrome.exe", "aumid": "Chrome", "name": "Google Chrome"},
		{"hwnd": 103, "title": "Mystery", "exe": "C:/Tools/mystery.exe"},
	], 101)
	# Both bottom corners of the screen are click targets, and the orb keeps its own.
	var vp := main.get_viewport().get_visible_rect().size
	var tb: Taskbar = main.taskbar
	var corner_l := tb._start_hit.get_global_rect()
	var corner_r := tb._desk_hit.get_global_rect()
	check(corner_l.has_point(Vector2(0.5, vp.y - 0.5)), "taskbar: bottom-left corner opens Start")
	check(corner_r.has_point(Vector2(vp.x - 0.5, vp.y - 0.5)), "taskbar: bottom-right corner shows the desktop")
	var orb_c := tb.orb.get_global_rect().get_center()
	check(not tb._start_hit._has_point(orb_c - corner_l.position), "taskbar: the orb keeps its own clicks")
	main.taskbar.rebuild()
	var chrome: TaskbarButton = main.taskbar.button_for("app:Chrome")
	check(chrome != null and chrome.window_count() == 2, "taskbar: groups windows under their pin")
	check(chrome != null and chrome.active, "taskbar: foreground window is active")
	check(main.taskbar.button_for("win:C:/Tools/mystery.exe") != null, "taskbar: unpinned windows get a button")
	var mystery: TaskbarButton = main.taskbar.button_for("win:C:/Tools/mystery.exe")
	if mystery:
		var bar: Taskbar = main.taskbar
		bar._on_drag_started(mystery)
		mystery.position.x = bar._slot_x(0)
		bar._order.erase(mystery)
		bar._order.insert(bar._drag_slot(), mystery)
		bar._on_drag_ended(mystery)
		check(bar._order[0] == mystery and str(Settings.get_value("taskbar_order")[0]) == mystery.ref, "taskbar: dragging reorders and saves")
		bar.rebuild()
		check(bar._order[0] == mystery, "taskbar: dragged order survives a rebuild")
		Settings.set_value("taskbar_order", [])
		bar.rebuild()
	if chrome:
		main.preview.show_for(chrome)
		await _wait(0.3)
		check(main.preview.is_showing(), "taskbar: hover preview opens")
		main.preview.hide_preview()
	main.switcher.handle_key("open")
	check(main.switcher.is_open and main.switcher.selected == 1, "switcher: Alt+Tab picks the previous window")
	await _wait(0.4)
	check(main.switcher.is_showing(), "switcher: shows after a moment")
	check(App.switcher_open, "switcher: runs at full frame rate while open")
	main.switcher.handle_key("next")
	main.switcher.handle_key("next")
	check(main.switcher.selected == 0, "switcher: Tab wraps around")
	main.switcher.handle_key("prev")
	check(main.switcher.selected == 2, "switcher: Shift+Tab goes back")
	main.switcher.handle_key("done")
	check(not main.switcher.is_open, "switcher: letting go of Alt switches")
	main.switcher.handle_key("open_back")
	main.switcher.handle_key("cancel")
	await _wait(0.3)
	check(not main.switcher.is_open and not main.switcher.is_showing(), "switcher: Esc backs out")
	check(not App.switcher_open, "switcher: frame rate goes back to normal after")
	Host.set_mock_windows([])
	main.taskbar.rebuild()
	check(main.taskbar.button_for("win:C:/Tools/mystery.exe") == null, "taskbar: closed windows disappear")

	# The pointer moving where no Oazy window hears it lets go of hover.
	App._unheard_at = Time.get_ticks_msec() - 200
	App._unheard_frames = 5
	await _wait(0.1)
	check(App.pointer_away, "hover: pointer moving elsewhere lets go of hover")
	var ev := InputEventMouseMotion.new()
	ev.position = Vector2(5, 5)
	App._on_window_input(ev)
	await _wait(0.1)
	check(not App.pointer_away, "hover: back as soon as an Oazy window hears the pointer")

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
	var st := settings.body.get_child(0) as SettingsApp
	for spec in SettingsApp.PAGES:
		st.open_page(spec[0])
		check(st.page_visible(spec[0]) and st.visible_rows() > 0, "settings: %s page shows its settings" % spec[0])
	st.open_page("desktop")
	st.search("taskbar")
	check(st.visible_rows() >= 2 and st.page_visible("desktop"), "settings: search finds taskbar settings")
	st.search("zzqx")
	check(st.visible_rows() == 0, "settings: search with no match shows nothing")
	st.search("")
	check(st.page_visible("desktop") and not st.page_visible("personalise"), "settings: clearing search goes back to the page")
	st.open_page("personalise")
	var favs := main.desktop.get("_favs") as GridContainer
	for size_id in ["large", "small", "medium"]:
		Settings.set_value("fav_icon_size", size_id)
		await _wait(0.1)
		var tile := favs.get_child(0) as Control
		check(tile.custom_minimum_size == Desktop.FAV_SIZES[size_id]["tile"] and favs.position.x >= 0.0, "desktop: %s favourite icons" % size_id)
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

	# Cleaner: scan, pick, apply and undo, against the mock PC.
	var safe := true
	for e in Cleaner.catalog.get("apps", []):
		for pat in Cleaner.catalog.get("protected", []):
			if str(e["id"]).matchn(str(pat)):
				safe = false
	for t in Cleaner.catalog.get("tweaks", []):
		for op in t["ops"]:
			var path := str(op.get("path", ""))
			if path.contains("Defender") or path.contains("WindowsUpdate") or path.contains("\\Services\\") or (op["t"] == "service" and op["name"] != "DiagTrack"):
				safe = false
	check(safe and "Microsoft.WindowsStore" in Cleaner.catalog["protected"], "cleaner: catalog never touches protected parts of Windows")
	var cl: ShellWindow = main.open_app(&"cleaner")
	await _wait(0.4)
	check(cl != null and cl.body.get_child(0) is CleanerApp, "cleaner: opens")
	var cleaner: CleanerApp = cl.body.get_child(0)
	Cleaner.start_scan()
	await _cleaner_idle()
	check(Cleaner.has_scan() and Cleaner.scan["apps"].size() > 0, "cleaner: scan finds bloat")
	check(Cleaner.is_picked("app:Microsoft.BingNews") and not Cleaner.is_picked("app:SpotifyAB.SpotifyMusic"), "cleaner: only recommended picks are ticked")
	check(not Cleaner.is_picked("tweak:game_mode") and Cleaner.is_picked("tweak:ads"), "cleaner: done settings aren't picked")
	check(Cleaner.picks_in("startup") == 0, "cleaner: startup apps are left alone until you choose")
	for page in ["apps", "startup", "junk", "perf", "privacy", "history", "overview"]:
		cleaner._go(page)
		await _wait(0.1)
	var steam: Dictionary = Cleaner.scan["startup"][0]
	Cleaner.want_startup(steam, false)
	check(Cleaner.picks.get(Cleaner.startup_key(steam)) == false and not Cleaner.startup_wanted(steam), "cleaner: startup switch")
	check(Cleaner.needs_admin(), "cleaner: a restore point asks Windows once")
	Cleaner.apply_picks()
	await _cleaner_idle()
	check(Cleaner.history.size() == 1 and cleaner._page == "result", "cleaner: apply keeps a record")
	var still := false
	for a in Cleaner.scan["apps"]:
		if a["pkg"] == "Microsoft.BingNews":
			still = true
	check(not still and Cleaner.picks.is_empty(), "cleaner: applied picks are done")
	Cleaner.undo_run(str(Cleaner.history[0]["id"]))
	await _cleaner_idle()
	check(Cleaner.history[0].get("undone", false), "cleaner: undo")
	cl.close()
	await _wait(0.4)

	# Start.
	main.start.open()
	await _wait(0.4)
	check(main.start.is_open, "start: opens")
	check(main.get_viewport_rect().grow(1.0).encloses(main.start.get_global_rect()), "start: fits on screen")
	check(main.start.get_global_rect().end.y <= main.taskbar.get_global_rect().position.y + 1.0, "start: sits above the taskbar")
	check(main.desktop.modulate.a < 0.01 and main.desktop.scale.x < 1.0, "desktop: fades and eases back behind Start")
	check(main.desktop._hero_glass._shadow.modulate.a < 0.01, "desktop: the hero card's shadow fades with it")
	var inner: Rect2 = main.start._root.get_global_rect()
	check(main.start.get_global_rect().grow(1.0).encloses(inner), "start: content stays inside the glass")
	var sr: Rect2 = main.start._glass.shadow_rect()
	check(sr.encloses(main.start.get_global_rect()) and sr.end.y - main.start.get_global_rect().end.y > sr.position.y - main.start.get_global_rect().position.y - 0.01, "start: layer shape covers the shadow, more below than above")
	main.start.open("chro")
	await _wait(0.3)
	check(main.start._rows.size() > 1, "start: search shows results")
	var first_row: Control = main.start._rows[0]
	var row_count: int = main.start._result_list.get_child_count()
	main.start._search.text = "steam"
	main.start._on_text("steam")
	check(main.start._result_list.get_child_count() == row_count and main.start._result_list.get_child(0) == first_row, "start: search reuses its rows")
	check(str(main.start._rows[0].get_meta("ref")) != "", "start: reused rows point at the new results")
	var tiles: Array = main.start._pinned.get_children()
	main.start.close()
	await _wait(0.5)
	check(is_equal_approx(main.desktop.modulate.a, 1.0) and main.desktop.scale.is_equal_approx(Vector2.ONE), "desktop: settles back fully when Start closes")
	main.start.open()
	await _wait(0.1)
	check(main.start._pinned.get_children() == tiles, "start: reopening keeps its tiles")
	main.start._show_view(main.start._all)
	await _wait(0.2)
	var all_scroll: ScrollContainer = main.start._all_list.get_parent()
	check(all_scroll.has_meta("smooth_scroll"), "scroll: Start's lists scroll smoothly")
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	wheel.factor = 1.0
	all_scroll.gui_input.emit(wheel)
	await _wait(0.05)
	var mid: float = all_scroll.get_v_scroll_bar().value
	await _wait(0.6)
	var end: float = all_scroll.get_v_scroll_bar().value
	check(end > 0.0 and mid < end, "scroll: the wheel glides instead of jumping (%.0f -> %.0f)" % [mid, end])
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
	check(main.desktop._hero_id != "" and main.desktop._hero_glass.visible, "desktop: the game card shows a game")
	var tile: Control = null
	if not Library.entries.is_empty():
		tile = main.desktop._recent_tile(str(Library.entries[0]["id"]))
		main.desktop._recent.add_child(tile)
		# A quick pass over a card: the "in" animation must not outlive the "out".
		tile.mouse_entered.emit()
		await get_tree().process_frame
		tile.mouse_exited.emit()
		await _wait(0.45)
		var cover: CoverArt = tile.get_child(0)
		var want := 0.85 if str(tile.get_meta("id")) == main.desktop._hero_id else 0.0
		check(absf(cover.focus_amount - want) < 0.01 and tile.scale.is_equal_approx(Vector2.ONE), "desktop: a quick pass over a recent card leaves it unlit")
		tile.queue_free()
	else:
		check(false, "desktop: test library has a game")
	Catalog.favorites_changed.emit()
	check(main.desktop._favs.get_child_count() == mini(Catalog.favorites().size(), Desktop.FAV_MAX) or (Catalog.favorites().is_empty() and main.desktop._favs.get_child_count() == 1), "desktop: favourites show")
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
	Host.request(["wifi", "1"], func(d: Dictionary) -> void: got["wifi"] = d)
	waited = 0.0
	while got.size() < 5 and waited < 30.0:
		await _wait(0.2)
		waited += 0.2
	check(got.has("windows") and got["windows"].get("ok", false), "host: lists windows")
	check(got.has("apps") and got["apps"].get("apps", []).size() > 0, "host: lists installed apps")
	check(got.has("stats") and got["stats"].has("cpu"), "host: system stats")
	check(got.has("icon") and FileAccess.file_exists("user://smoke/explorer.png"), "host: renders icons (%s)" % str(got.get("icon", {}).get("error", "no reply")))
	# CI machines have no Wi-Fi adapter, but the answer (and the cable list) must still come back.
	check(got.has("wifi") and got["wifi"].get("ok", false) and got["wifi"].has("ethernet"), "host: network status (%s)" % str(got.get("wifi", {})))
	await _capture_test()
	check(Host.available, "host: still running after the checks")


## Opens a real Notepad and takes the picture the Alt+Tab switcher would show.
func _capture_test() -> void:
	var pid := OS.create_process("notepad.exe", [])
	check(pid > 0, "capture: notepad starts")
	if pid <= 0:
		return
	var hwnd := 0
	var waited := 0.0
	while hwnd == 0 and waited < 15.0:
		await _wait(0.5)
		waited += 0.5
		var listed := {}
		Host.request(["windows"], func(d: Dictionary) -> void: listed["d"] = d)
		while not listed.has("d"):
			await _wait(0.05)
		for w in listed["d"].get("windows", []):
			if str(w.get("exe", "")).to_lower().ends_with("notepad.exe") or str(w.get("title", "")).to_lower().contains("notepad"):
				hwnd = int(w.get("hwnd", 0))
	check(hwnd != 0, "capture: notepad's window is listed")
	if hwnd != 0:
		await _wait(1.0)
		var got := {}
		Host.capture(hwnd, Vector2i(640, 400), func(tex: ImageTexture) -> void: got["tex"] = tex)
		waited = 0.0
		while not got.has("tex") and waited < 15.0:
			await _wait(0.1)
			waited += 0.1
		var tex: ImageTexture = got.get("tex")
		check(tex != null and tex.get_width() > 32 and tex.get_height() > 32, "capture: takes a picture of a real window (not blank)")
		check(Host.captures.has(hwnd), "capture: keeps the last picture")
		Host.close_window(hwnd)
	await _wait(0.5)
	if OS.is_process_running(pid):
		OS.kill(pid)


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
	check(screen.encloses(bar) and bar.size.x > vp.x * 0.9 and bar.size.y >= 44.0, "layout(%s): taskbar spans the bottom" % where)
	check(bar.end.y > vp.y - 20.0, "layout(%s): taskbar at the bottom" % where)
	check(screen.encloses(main.taskbar.orb.get_global_rect()), "layout(%s): Start orb on screen" % where)
	check(main.layer.work_rect().end.y <= bar.position.y + 1.0, "layout(%s): windows stay above the taskbar" % where)
	check(main.desktop.size.distance_to(vp) < 1.0, "layout(%s): desktop fills the window" % where)


func _menu_has(menu: PopupMenu, text: String) -> bool:
	for i in menu.item_count:
		if menu.get_item_text(i).contains(text):
			return true
	return false


func _cleaner_idle() -> void:
	var waited := 0.0
	await _wait(0.1)
	while (Cleaner.busy() or not Cleaner.has_scan()) and waited < 10.0:
		await _wait(0.1)
		waited += 0.1


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
