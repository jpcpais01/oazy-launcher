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

	# Claude's replies in the orb popup.
	var md := ChatMarkdown.blocks("Hi **there**\n\n- one\n- two\n\n```py\nprint(1)\n```\nafter")
	check(md.size() == 3 and md[0]["t"] == "text" and md[1]["t"] == "code" and md[2]["t"] == "text", "chat markdown: text, code, text")
	check(str(md[0]["bb"]).contains("[b]there[/b]") and str(md[0]["bb"]).contains("[ul"), "chat markdown: bold and list")
	check(str(md[1]["lang"]) == "py" and str(md[1]["code"]) == "print(1)", "chat markdown: fenced code")
	var open_fence := ChatMarkdown.blocks("Look:\n```\nhalf")
	check(open_fence.size() == 2 and str(open_fence[1]["code"]) == "half", "chat markdown: code still streaming")
	check(ClaudeMood.found("[[mood:happy]] Hi! [[mood:Proud]] [[mood:nope]]") == PackedStringArray(["happy", "proud"]), "claude mood: tags read")
	check(ClaudeMood.strip("[[mood:happy]] Hi there") == "Hi there" and ClaudeMood.strip("[[mo") == "" and ClaudeMood.strip("Hi [[mood:ca") == "Hi ", "claude mood: tags hidden, even half arrived")
	check(ChatMarkdown.blocks("[[mood:calm]]\nHello").size() == 1 and not str(ChatMarkdown.blocks("[[mood:calm]]\nHello")[0]["bb"]).contains("mood"), "claude mood: never drawn")
	check(ClaudeMood.hearing("thanks so much!") == "happy" and ClaudeMood.hearing("why is it slow?") == "curious", "claude mood: reacts to what you write")
	check(ClaudeCli._quote("C:/Program Files/x") == "\"C:/Program Files/x\"" and ClaudeCli._quote("-p") == "-p", "claude cli: argument quoting")

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
	check(Art.brand_art("WhatsApp Beta", &"cover").ends_with("whatsapp_cover.webp.bin") and Art.brand_art("Discord PTB", &"hero").ends_with("discord_hero.webp.bin") and Art.brand_art("Microsoft Teams", &"cover") != "" and Art.brand_art("Teams", &"logo") != "" and Art.brand_art("ArcGIS Earth", &"hero") != "" and Art.brand_art("Hyperliquid", &"logo") != "", "art: built-in art for app editions, Teams, ArcGIS Earth and Hyperliquid")

	check(Art.share_image("<head><meta property=\"og:image\" content=\"https://cdn.x/og.jpg\"></head>", "https://x.com") == "https://cdn.x/og.jpg", "art: share image from og:image")
	check(Art.share_image("<meta content='/img/s.png' name='twitter:image'>", "https://x.com/app") == "https://x.com/img/s.png", "art: share image, relative and reversed attributes")
	var wide := Image.create(1200, 630, false, Image.FORMAT_RGBA8)
	wide.fill(Color(0.3, 0.4, 0.9))
	var poster := Art.poster_from_wide(wide)
	check(poster != null and poster.get_size() == Vector2i(600, 900), "art: wide share image becomes a poster")

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
	Catalog.move_favorite(lib_ref, 0)
	check(Catalog.favorites().slice(0, 2) == [lib_ref, "app:Chrome"], "favourites: drag to reorder")
	Catalog.move_favorite(lib_ref, 1)
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
	check(Catalog.item(game_ref)["icon_key"] == "C:\\Games\\smoke.exe", "icons: a game uses its own exe's icon")
	check(Catalog.entry_icon_key({"name": "Smoke Game", "path": "steam://rungameid/1"}) == "shell:AppsFolder\\C:/Games/Smoke Launcher.exe", "icons: a game without an exe uses its Start shortcut's icon")
	check(Catalog.entry_icon_key({"name": "Nothing", "path": "https://example.com"}) == "", "icons: links fall back to the cover")
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
	var both := Shell.union_polygon([Rect2(0, 0, 10, 10), Rect2(5, 5, 10, 10)] as Array[Rect2], 1.0)
	check(Geometry2D.is_point_in_polygon(Vector2(7, 7), both) and Geometry2D.is_point_in_polygon(Vector2(2, 2), both)
		and Geometry2D.is_point_in_polygon(Vector2(13, 13), both) and Geometry2D.is_point_in_polygon(Vector2(12, 7), both),
		"shell: overlapping parts join without holes")
	check(not Geometry2D.is_point_in_polygon(Vector2(2, 13), both) and not Geometry2D.is_point_in_polygon(Vector2(13, 2), both),
		"shell: nothing between overlapping parts takes clicks")
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

	# The trading desk: Hyperliquid answers, read without the network.
	var hm := {}
	var hc := {}
	check(Hyperliquid.parse_meta_and_ctxs([{"universe": [{"name": "BTC", "szDecimals": 5, "maxLeverage": 40}, {"name": "kPEPE", "szDecimals": 0, "maxLeverage": 10}]},
		[{"markPx": "111842.0", "prevDayPx": "110000.0", "dayNtlVlm": "2100000000.0", "openInterest": "30000.5", "funding": "0.0000125", "oraclePx": "111850.0", "midPx": "111841.5"},
		{"markPx": "0.012345", "prevDayPx": "0.0125", "dayNtlVlm": "1.0", "openInterest": "1.0", "funding": "-0.0001", "oraclePx": "0.0123", "midPx": null}]], hm, hc)
		and int(hm["BTC"]["sz"]) == 5 and is_equal_approx(float(hc["BTC"]["prev"]), 110000.0) and hc.has("kPEPE"), "hyperliquid: meta and 24h stats")
	var hb := Hyperliquid.parse_book({"coin": "BTC", "time": 1, "levels": [[{"px": "100.5", "sz": "2.0", "n": 3}, {"px": "100.0", "sz": "1.0", "n": 1}], [{"px": "101.0", "sz": "0.5", "n": 2}]]})
	check((hb["bids"] as Array).size() == 2 and is_equal_approx(float(hb["asks"][0][0]), 101.0), "hyperliquid: order book levels")
	var hcan := Hyperliquid.parse_candles([{"t": 7200000, "T": 10799999, "s": "BTC", "i": "1h", "o": "2", "c": "3", "h": "4", "l": "1", "v": "10", "n": 5}, {"t": 3600000, "o": "1", "c": "2", "h": "2", "l": "1", "v": "5"}])
	check(hcan.size() == 2 and int(hcan[0][0]) == 3600 and is_equal_approx(float(hcan[1][4]), 3.0), "hyperliquid: candles, oldest first")
	var hacct := Hyperliquid.parse_account({"marginSummary": {"accountValue": "1000.0", "totalNtlPos": "500.0", "totalRawUsd": "500.0", "totalMarginUsed": "50.0"}, "withdrawable": "900.0",
		"assetPositions": [{"type": "oneWay", "position": {"coin": "ETH", "szi": "-2.0", "entryPx": "4000.0", "positionValue": "7800.0", "unrealizedPnl": "200.0", "returnOnEquity": "0.25", "liquidationPx": "4500.0", "leverage": {"type": "isolated", "value": 10}, "marginUsed": "800.0"}}]})
	check(hacct.get("positions", []).size() == 1 and float(hacct["positions"][0]["szi"]) == -2.0 and not bool(hacct["positions"][0]["cross"]) and int(hacct["positions"][0]["lev"]) == 10, "hyperliquid: account and positions")
	check(Hyperliquid.is_address("0x" + "a1".repeat(20)) and not Hyperliquid.is_address("0x" + "a1".repeat(32)) and not Hyperliquid.is_address("hello"), "hyperliquid: addresses, never keys")
	check(Hyperliquid.fmt_px(111842.0) == "111,842" and Hyperliquid.fmt_px(3950.55) == "3,950.6" and Hyperliquid.fmt_px(0.012345) == "0.012345" and Hyperliquid.fmt_usd(-12.5, true) == "−$12.50", "hyperliquid: price formatting")
	# Builder exchanges (HIP-3): prefixed names and their own asset numbers.
	check(Hyperliquid.parse_dexes([null, {"name": "xyz", "fullName": "XYZ"}, {"name": "flx"}]) == ["", "xyz", "flx"], "hyperliquid: builder exchanges")
	check(Hyperliquid.parse_meta_and_ctxs([{"universe": [{"name": "DRAM", "szDecimals": 2, "maxLeverage": 10, "onlyIsolated": true}, {"name": "xyz:XYZ100", "szDecimals": 3, "maxLeverage": 20}]},
		[{"markPx": "1.0"}, {"markPx": "25000.0"}]], hm, hc, "xyz", 1) and int(hm["xyz:DRAM"]["asset"]) == 110000 and int(hm["xyz:XYZ100"]["asset"]) == 110001 and bool(hm["xyz:DRAM"]["isolated"]) and int(hm["BTC"]["asset"]) == 0, "hyperliquid: builder asset numbers")
	check(Hyperliquid.display("xyz:XYZ100") == "XYZ100" and Hyperliquid.dex_of("xyz:XYZ100") == "xyz" and Hyperliquid.dex_of("BTC") == "", "hyperliquid: builder coin names")
	var hlp := Hyperliquid.new()
	hlp.meta = hm
	check(Array(hlp.parse_coins("btc, xyz100 dram, kpepe")) == ["BTC", "xyz:XYZ100", "xyz:DRAM", "kPEPE"], "hyperliquid: typed names find builder markets")
	hlp.free()
	var hacct2 := Hyperliquid.merge_accounts(hacct, Hyperliquid.parse_account({"marginSummary": {"accountValue": "50.0", "totalNtlPos": "0", "totalMarginUsed": "5"}, "withdrawable": "10",
		"assetPositions": [{"position": {"coin": "XYZ100", "szi": "1", "entryPx": "25000", "positionValue": "25000", "unrealizedPnl": "0", "leverage": {"type": "isolated", "value": 5}, "marginUsed": "5000"}}]}, "xyz"))
	check(is_equal_approx(float(hacct2["value"]), 1050.0) and (hacct2["positions"] as Array).any(func(p: Dictionary) -> bool: return p["coin"] == "xyz:XYZ100"), "hyperliquid: accounts across exchanges add up")
	# Orders: the exact bytes Hyperliquid's own SDK signs, and its number format.
	var act := HlExchange.order_action({"asset": 110003, "buy": true, "px": 81250.0, "sz": 0.0123, "reduce": false, "tif": "Gtc"})
	check(MsgPack.pack(act).hex_encode() == "83a474797065a56f72646572a66f72646572739186a161ce0001adb3a162c3a170a53831323530a173a6302e30313233a172c2a17481a56c696d697481a3746966a3477463a867726f7570696e67a26e61", "trading: order packs like the SDK")
	check(MsgPack.pack({"type": "cancel", "cancels": [{"a": 5, "o": 123456789012}]}).hex_encode() == "82a474797065a663616e63656ca763616e63656c739182a16105a16fcf0000001cbe991a14", "trading: cancel packs like the SDK")
	# Take profit / stop loss: trigger orders, packed like the SDK.
	var tp_act := HlExchange.orders_action([{"asset": 0, "buy": false, "px": 100000.0, "sz": 0.001, "reduce": true, "trigger": 110000.0, "tpsl": "tp"}], "positionTpsl")
	check(MsgPack.pack(tp_act).hex_encode() == "83a474797065a56f72646572a66f72646572739186a16100a162c2a170a6313030303030a173a5302e303031a172c3a17481a77472696767657283a869734d61726b6574c3a9747269676765725078a6313130303030a47470736ca27470a867726f7570696e67ac706f736974696f6e5470736c", "trading: take profit packs like the SDK")
	var sl_o := HlExchange.tpsl_order(3, true, 0.5, 2000.0, "sl", 4)
	check(not bool(sl_o["buy"]) and bool(sl_o["reduce"]) and is_equal_approx(float(sl_o["px"]), 1800.0) and is_equal_approx(float(sl_o["trigger"]), 2000.0), "trading: a long's stop loss sells, reduce-only, with room to fill")
	check(HlExchange.tpsl_problem(true, 100.0, 110.0, 95.0) == "" and HlExchange.tpsl_problem(true, 100.0, 90.0, 0.0) != "" and HlExchange.tpsl_problem(false, 100.0, 90.0, 105.0) == "" and HlExchange.tpsl_problem(false, 100.0, 0.0, 95.0) != "", "trading: TP / SL must sit on the right side of the price")
	check(Hyperliquid.tpsl_of("Take Profit Market") == "tp" and Hyperliquid.tpsl_of("Stop Market") == "sl" and Hyperliquid.tpsl_of("Limit") == "", "hyperliquid: TP / SL orders recognised")
	var ut := func(y: int, mo: int, d: int, h: int, mi: int = 0) -> int:
		return Time.get_unix_time_from_datetime_dict({"year": y, "month": mo, "day": d, "hour": h, "minute": mi, "second": 0})
	check(Hyperliquid.ny_offset(ut.call(2026, 10, 29, 14)) == -4 * 3600 and Hyperliquid.ny_offset(ut.call(2026, 11, 2, 14)) == -5 * 3600
		and Hyperliquid.ny_offset(ut.call(2026, 3, 8, 6, 59)) == -5 * 3600 and Hyperliquid.ny_offset(ut.call(2026, 3, 8, 7)) == -4 * 3600, "hyperliquid: New York summer time")
	check(Hyperliquid.session_open(ut.call(2026, 10, 29, 14)) == ut.call(2026, 10, 29, 13, 30)
		and Hyperliquid.session_open(ut.call(2026, 10, 29, 13, 29)) == ut.call(2026, 10, 28, 13, 30)
		and Hyperliquid.session_open(ut.call(2026, 10, 31, 12)) == ut.call(2026, 10, 30, 13, 30)
		and Hyperliquid.session_open(ut.call(2026, 11, 2, 14)) == ut.call(2026, 10, 30, 13, 30)
		and Hyperliquid.session_open(ut.call(2026, 11, 2, 15)) == ut.call(2026, 11, 2, 14, 30), "hyperliquid: today starts at the 9:30 New York open")
	check(Hyperliquid.session_close_before(ut.call(2026, 10, 29, 13, 30)) == ut.call(2026, 10, 28, 20)
		and Hyperliquid.session_close_before(ut.call(2026, 11, 2, 14, 30)) == ut.call(2026, 10, 30, 20), "hyperliquid: last trading day's 4pm close")
	check(Hyperliquid.has_session("xyz:TSLA") and not Hyperliquid.has_session("BTC"), "hyperliquid: Today only for stocks and ETFs")
	var ico := CoinIcons.decode('<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32"><circle cx="16" cy="16" r="16" fill="#f7931a"/></svg>'.to_utf8_buffer(), true)
	check(ico != null and ico.get_width() == CoinIcons.SIZE and ico.get_pixel(CoinIcons.SIZE / 2, CoinIcons.SIZE / 2).a > 0.9 and ico.get_pixel(1, 1).a < 0.05
		and CoinIcons.decode("<!doctype html><html></html>".to_utf8_buffer(), true) == null, "coin icons: logos decode round, web pages don't")
	check(CoinIcons.urls("xyz:TSLA")[0].ends_with("/coins/xyz:TSLA.svg") and CoinIcons.urls("kPEPE")[1].ends_with("/color/pepe.svg"), "coin icons: where logos come from")
	var tord := Hyperliquid.parse_orders([{"coin": "BTC", "side": "A", "limitPx": "99000", "sz": "0.1", "oid": 9, "timestamp": 1, "orderType": "Stop Market", "isTrigger": true, "triggerPx": "100000", "reduceOnly": true, "isPositionTpsl": true}])
	check(tord.size() == 1 and str(tord[0]["tpsl"]) == "sl" and is_equal_approx(float(tord[0]["trigger"]), 100000.0) and bool(tord[0]["position"]), "hyperliquid: trigger orders keep their trigger price")
	# Your money: spot balances valued in dollars; unified accounts count them as the account.
	var spx := Hyperliquid.parse_spot_prices([{"tokens": [{"name": "USDC", "index": 0}, {"name": "HYPE", "index": 150}, {"name": "USDT0", "index": 268}],
		"universe": [{"name": "@107", "tokens": [150, 0], "index": 107}]}, [{"coin": "@107", "markPx": "40.0", "midPx": "40.5"}]])
	check(is_equal_approx(float(spx["HYPE"]), 40.5) and is_equal_approx(float(spx["USDC"]), 1.0) and is_equal_approx(float(spx["USDT0"]), 1.0), "hyperliquid: spot prices in dollars")
	var sbal := Hyperliquid.parse_spot_balances({"balances": [{"coin": "USDC", "token": 0, "total": "5000.0", "hold": "800.0", "entryNtl": "0.0"}, {"coin": "HYPE", "token": 150, "total": "10.0", "hold": "0.0", "entryNtl": "300.0"}, {"coin": "PURR", "total": "0.0", "hold": "0.0"}]})
	check(sbal.size() == 2, "hyperliquid: spot balances, empty ones skipped")
	var uni := Hyperliquid.compose_account(hacct, sbal, spx, true)
	check(is_equal_approx(float(uni["value"]), 5000.0 + 405.0 + 200.0) and is_equal_approx(float(uni["withdrawable"]), 4200.0) and is_equal_approx(float(uni["margin"]), 800.0), "hyperliquid: a unified account is its spot money plus open P&L")
	var std := Hyperliquid.compose_account(hacct, sbal, spx, false)
	check(is_equal_approx(float(std["value"]), 1000.0 + 5405.0) and is_equal_approx(float(std["withdrawable"]), 900.0 + 4200.0), "hyperliquid: a standard account adds perps and spot")
	check(Hyperliquid.unified("unifiedAccount") and Hyperliquid.unified("portfolioMargin") and not Hyperliquid.unified("disabled"), "hyperliquid: account modes")
	check(HlExchange.wire(81250.0) == "81250" and HlExchange.wire(0.0123) == "0.0123" and HlExchange.wire(100.0) == "100" and HlExchange.wire(-0.0) == "0", "trading: number format")
	check(is_equal_approx(HlExchange.round_px(81253.7, 5), 81254.0) and is_equal_approx(HlExchange.round_px(3951.437, 4), 3951.4) and is_equal_approx(HlExchange.round_px(0.0123456, 0), 0.012346) and is_equal_approx(HlExchange.round_sz(0.01239, 4), 0.0123), "trading: prices and sizes round the exchange's way")
	check(HlExchange.parse_response({"status": "ok", "response": {"type": "order", "data": {"statuses": [{"filled": {"totalSz": "0.02", "avgPx": "1891.4", "oid": 77}}]}}}).get("filled") == 0.02
		and not HlExchange.parse_response({"status": "ok", "response": {"type": "order", "data": {"statuses": [{"error": "Insufficient margin"}]}}})["ok"]
		and not HlExchange.parse_response({"status": "err", "response": "User or API Wallet does not exist."})["ok"], "trading: reads the exchange's answers")
	var hx := HlExchange.new(null)
	check(not bool((await hx.send(act)).get("ok", true)), "trading: nothing is sent while disarmed")
	hx.free()
	# Claude attachments: pictures inline (shrunk), files by path at the end.
	var big := Image.create(3200, 1800, false, Image.FORMAT_RGB8)
	big.fill(Color(0.2, 0.5, 0.7))
	var pic := ClaudeAttach.from_image(big)
	check(pic["kind"] == "image" and maxi(pic["image"].get_width(), pic["image"].get_height()) == ClaudeAttach.MAX_SIDE and Marshalls.base64_to_raw(pic["data"]).size() <= ClaudeAttach.MAX_RAW, "claude attach: big pictures shrink for the API")
	var sent: Variant = ClaudeAttach.content("what's this?", [pic, {"kind": "file", "name": "a b.pdf", "path": "/home/x/a b.pdf"}])
	check(sent is Array and sent[0]["type"] == "image" and sent[1]["type"] == "text" and str(sent[1]["text"]).ends_with(ClaudeAttach.FILE_PREFIX + ClaudeAttach._native("/home/x/a b.pdf") + "]"), "claude attach: picture blocks, then text naming the files")
	check(ClaudeAttach.content("hi", []) == "hi" and ClaudeAttach.images_in(sent).size() == 1, "claude attach: plain text stays a string; pictures read back")
	var split := ClaudeAttach.split("look\n\n[Attached file: C:\\a\\b.pdf]\n[Attached file: C:\\c d.txt]")
	check(split[0] == "look" and split[1].size() == 2 and split[1][1] == "C:\\c d.txt", "claude attach: file lines split back off")
	check(ClaudeHistory.user_text({"message": {"content": [{"type": "text", "text": "hey\n\n[Attached file: /x/y.txt]"}]}}) == "hey", "claude attach: past chats show the words, not the file lines")

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
	check(not desk.trade.visible and not desk.trade._active, "desktop: trading desk parked on the second screen")
	desk.page(1)
	await _wait(1.5)
	check(desk.trade.visible and desk.trade._active and not desk.below.visible and not desk.below._active and is_equal_approx(desk.trade.position.y, 0.0), "desktop: on to the trading desk, second screen parked")
	check(desk.trade.hl.focused, "desktop: the desk streams only while it's in view")
	desk.page(-1)
	await _wait(1.5)
	check(desk.below.visible and not desk.trade.visible and not desk.trade.hl.focused, "desktop: back to the second screen, desk stops streaming")
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
		var opened := Host.windows.duplicate(true)
		opened.append({"hwnd": 104, "title": "Fresh", "exe": "C:/Tools/fresh.exe"})
		Host.set_mock_windows(opened, 101)
		bar.rebuild()
		check(bar._order[0] == mystery and bar._order.back().ref == "win:C:/Tools/fresh.exe", "taskbar: a newly opened app joins the right end")
		opened.pop_back()
		Host.set_mock_windows(opened, 101)
		bar.rebuild()
		Settings.set_value("taskbar_order", [])
		bar.rebuild()
	if chrome:
		main.preview.show_for(chrome)
		await _wait(0.3)
		check(main.preview.is_showing(), "taskbar: hover preview opens")
		main.preview.hide_preview()
	await _tasks_tests(main)
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

	# A fullscreen game or video hides the taskbar, and it comes back by
	# itself once there isn't one (worked out again every second).
	var was_available := Host.available
	Host.available = true
	Host.fullscreen_app = true
	main._sync_layers()
	check(not main.taskbar.is_visible_in_tree(), "taskbar: steps aside for a fullscreen app")
	Host.fullscreen_app = false
	main._heal()
	check(main.taskbar.is_visible_in_tree(), "taskbar: back once nothing is fullscreen")
	Host.available = was_available

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
	var favs := main.desktop.get("_favs") as ReorderGrid
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

	# The orb's Claude popup (no claude here: events are fed in).
	var ai: AssistantPanel = main.assistant
	ai.mock = true
	main.taskbar.start_pressed.emit()
	await _wait(0.4)
	check(ai.is_open and not main.start.is_open, "assistant: the orb opens Claude, not Start")
	check(main.get_viewport_rect().grow(1.0).encloses(ai.get_global_rect()) and ai.get_global_rect().end.y <= main.taskbar.get_global_rect().position.y + 1.0, "assistant: fits above the taskbar")
	ai.submit("hello")
	check(ai.running and main.taskbar.orb.busy, "assistant: sending stirs the orb")
	ai.handle_message({"type": "stream_event", "event": {"type": "content_block_start", "index": 0, "content_block": {"type": "text"}}})
	ai.handle_message({"type": "stream_event", "event": {"type": "content_block_delta", "index": 0, "delta": {"type": "text_delta", "text": "Hi **João**"}}})
	ai.handle_message({"type": "stream_event", "event": {"type": "content_block_stop", "index": 0}})
	ai.handle_message({"type": "control_request", "request_id": "r1", "request": {"subtype": "can_use_tool", "tool_name": "Write", "input": {"file_path": "/tmp/x.txt"}}})
	check(ai._asks.size() == 1, "assistant: asks before writing")
	ai._answer("r1", false)
	Settings.set_value("claude_auto_allow", true)
	ai.handle_message({"type": "control_request", "request_id": "r2", "request": {"subtype": "can_use_tool", "tool_name": "Write", "input": {"file_path": "/tmp/x.txt"}}})
	check(ai._asks.is_empty() and ai._mode.text == "Allow all", "assistant: Allow all lets it through without a card")
	Settings.set_value("claude_auto_allow", false)
	check(ai._mode.text == "Ask first", "assistant: back to asking first")
	ai.handle_message({"type": "result", "subtype": "success"})
	check(not ai.running and ai._asks.is_empty() and not main.taskbar.orb.busy, "assistant: reply done")
	ai.handle_message({"type": "stream_event", "event": {"type": "content_block_start", "index": 0, "content_block": {"type": "text"}}})
	ai.handle_message({"type": "stream_event", "event": {"type": "content_block_delta", "index": 0, "delta": {"type": "text_delta", "text": "[[mood:excited]] Done!"}}})
	check(ai._blob._mood == "excited" and ai._blob.is_processing(), "assistant: the avatar takes Claude's mood and lives while open")
	main.taskbar.start_alt_pressed.emit()
	await _wait(0.3)
	check(main.start.is_open and not ai.is_open, "assistant: right-clicking the orb opens Start instead")
	main.start.close()
	await _wait(0.2)
	# Alt+Tab: the conversation is there to come back to.
	main.switcher.handle_key("open")
	var at := -1
	for i in main.switcher._entries.size():
		if main.switcher._entries[i].has("assistant"):
			at = i
	check(at >= 0 and str(main.switcher._entries[at]["title"]) == "hello", "assistant: in Alt+Tab with its conversation")
	main.switcher.selected = maxi(at, 0)
	main.switcher.commit()
	await _wait(0.3)
	check(ai.is_open, "assistant: Alt+Tab brings it back")
	main.switcher.handle_key("open")
	check(main.switcher._entries[0].has("assistant"), "assistant: first in Alt+Tab while it's open")
	main.switcher.handle_key("cancel")
	await _wait(0.3)
	# Past chats, from a Claude Code history made up here.
	var conf := ProjectSettings.globalize_path("user://smoke_claude")
	var was_conf := OS.get_environment("CLAUDE_CONFIG_DIR")
	OS.set_environment("CLAUDE_CONFIG_DIR", conf)
	var pdir := ClaudeHistory.project_dir(ClaudeCli.home())
	DirAccess.make_dir_recursive_absolute(pdir)
	var tf := FileAccess.open(pdir.path_join("abc-123.jsonl"), FileAccess.WRITE)
	tf.store_line(JSON.stringify({"type": "user", "cwd": ClaudeCli.home(), "message": {"role": "user", "content": "Plan my week"}}))
	tf.store_line(JSON.stringify({"type": "assistant", "message": {"id": "m1", "role": "assistant", "content": [{"type": "tool_use", "id": "t1", "name": "Read", "input": {"file_path": "/x/notes.md"}}]}}))
	tf.store_line(JSON.stringify({"type": "user", "message": {"role": "user", "content": [{"type": "tool_result", "tool_use_id": "t1", "content": "ok"}]}}))
	tf.store_line(JSON.stringify({"type": "assistant", "message": {"id": "m2", "role": "assistant", "content": [{"type": "text", "text": "Here's a **plan**."}]}}))
	tf.store_line(JSON.stringify({"type": "ai-title", "aiTitle": "Weekly plan"}))
	tf.close()
	var past := ClaudeHistory.recent(ClaudeCli.home())
	check(past.size() == 1 and str(past[0]["title"]) == "Weekly plan" and str(past[0]["id"]) == "abc-123", "assistant: reads past chats")
	ai.mock = true
	ai.show_history()
	check(ai._history.visible and ai._history_list.get_child_count() == 1, "assistant: past chats list")
	ai.load_chat(past[0])
	check(not ai._history.visible and ai._cli.session == "abc-123" and ai.title() == "Plan my week" and ai._tools.size() == 1, "assistant: a past chat opens where it left off")
	OS.set_environment("CLAUDE_CONFIG_DIR", was_conf)
	DirAccess.remove_absolute(pdir.path_join("abc-123.jsonl"))
	ai.close()
	ai.new_chat()
	check(not ai._has_conversation(), "assistant: new chat clears it")
	ai.mock = false
	await _wait(0.3)

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
	var was_state := Updater.state
	Updater.state = &"available"
	Updater.state_changed.emit(&"available")
	await _wait(0.6)
	check(main.update_pill._card.visible and main.update_pill._open, "update pill: slides in, open with the news")
	check(main.update_pill.shell_shape().size() == 1, "update pill: its layer keeps it on screen")
	Updater.state = &"downloading"
	Updater.state_changed.emit(&"downloading")
	Updater.progress.emit(500, 1000, 100.0)
	await _wait(0.3)
	check(main.update_pill._sub.text.contains("/s"), "update pill: shows download speed")
	Updater.state = &"checking"
	Updater.state_changed.emit(&"checking")
	Updater.state = &"error"
	Updater.state_changed.emit(&"error")
	check(main.update_pill._want_in, "update pill: a failed download stays to retry")
	Updater.state = &"idle"
	Updater.state_changed.emit(&"idle")
	Updater.state = &"error"
	Updater.state_changed.emit(&"error")
	check(not main.update_pill._want_in, "update pill: a failed background check isn't news")
	Updater.state = was_state
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
	await _wallet_test()
	await _capture_test()
	await _procs_test()
	await _media_test()
	check(Host.available, "host: still running after the checks")


## The trading key's maths on real Windows: the companion signs a known order
## exactly as Hyperliquid's own SDK does, and a key survives DPAPI.
func _wallet_test() -> void:
	var got := {}
	var file := ProjectSettings.globalize_path("user://smoke/hl.key")
	Host.request(["hl_selftest"], func(d: Dictionary) -> void: got["self"] = d)
	Host.request(["hl_key_new", file], func(d: Dictionary) -> void: got["new"] = d)
	var waited := 0.0
	while got.size() < 2 and waited < 20.0:
		await _wait(0.1)
		waited += 0.1
	var st: Dictionary = got.get("self", {})
	check(st.get("r", "") == "0xacfedf1f197cb8b7bef9a6cb49d49d2036441087b76cd10b5ac1d75c48a4fbe4" and st.get("s", "") == "0x1bfb69547cf486b0ba3b1618edd95be99a57827b579df05c1253ba590179092"
		and int(st.get("v", 0)) == 27 and st.get("address", "") == "0x2c7536e3605d9c16a7a3d7b1898e529396a65c23", "host: signs Hyperliquid orders like the SDK (%s)" % str(st))
	var made := str(got.get("new", {}).get("address", ""))
	check(Hyperliquid.is_address(made), "host: makes a trading key (%s)" % str(got.get("new", {})))
	Host.request(["hl_key_address", file], func(d: Dictionary) -> void: got["addr"] = d)
	Host.request(["hl_sign", file, "80", "1", "1"], func(d: Dictionary) -> void: got["sign"] = d)
	Host.request(["hl_key_forget", file], func(d: Dictionary) -> void: got["forget"] = d)
	Host.request(["hl_key_address", file], func(d: Dictionary) -> void: got["gone"] = d)
	waited = 0.0
	while got.size() < 6 and waited < 20.0:
		await _wait(0.1)
		waited += 0.1
	check(str(got.get("addr", {}).get("address", "")) == made and str(got.get("sign", {}).get("address", "")) == made, "host: the key comes back from DPAPI and signs")
	check(str(got.get("gone", {}).get("address", "x")) == "" and not FileAccess.file_exists("user://smoke/hl.key"), "host: the key can be removed")


## The now-playing library compiles against this Windows' WinRT metadata and
## loads into the companion. (A CI machine may have no media sessions at all,
## so what it reports is only logged.)
func _media_test() -> void:
	check(Host.media_lib != "", "host: builds the now-playing library (%s)" % Host.media_error)
	if Host.media_lib == "":
		return
	await _wait(2.0)
	var got := {}
	Host.media_command("refresh", "", func(d: Dictionary) -> void: got["r"] = d)
	var waited := 0.0
	while got.is_empty() and waited < 10.0:
		await _wait(0.2)
		waited += 0.2
	check(not got.is_empty(), "host: answers now-playing commands")
	print("SMOKE: now playing: ", got.get("r", {}), " last: ", Music.media)


## The task manager's process list (NtQuerySystemInformation read by offset)
## and ending a process, on a real Windows.
func _procs_test() -> void:
	var pid := OS.create_process("ping.exe", ["-n", "60", "127.0.0.1"])
	check(pid > 0, "procs: ping starts")
	await _wait(1.0)
	var got := {}
	Host.procs(func(d: Dictionary) -> void: got["a"] = d)
	await _wait(1.2)
	Host.procs(func(d: Dictionary) -> void: got["b"] = d)
	var waited := 0.0
	while got.size() < 2 and waited < 15.0:
		await _wait(0.2)
		waited += 0.2
	var d: Dictionary = got.get("b", {})
	var mine := {}
	var me := {}
	var cpu := 0.0
	for p in d.get("procs", []):
		cpu += float(p["cpu"])
		if int(p["pid"]) == pid:
			mine = p
		if int(p["pid"]) == OS.get_process_id():
			me = p
	check(d.get("ok", false) and d.get("procs", []).size() > 20, "procs: lists processes (%d)" % d.get("procs", []).size())
	check(not mine.is_empty() and str(mine["exe"]).to_lower().ends_with("ping.exe") and int(mine["ppid"]) == OS.get_process_id(), "procs: path and parent are right (%s)" % str(mine))
	check(not me.is_empty() and int(me["mem"]) > 1048576 and int(me["s"]) == int(mine.get("s", -1)), "procs: memory and session are read (%s)" % str(me))
	check(cpu > 0.0 and cpu <= 1.01 and float(d.get("cpu", -1)) >= 0.0 and float(d.get("mem_total", 0)) > 0.0, "procs: CPU shares and totals (%.3f)" % cpu)
	var killed := {}
	Host.kill([pid, OS.get_process_id()], func(r: Dictionary) -> void: killed["r"] = r)
	waited = 0.0
	while killed.is_empty() and waited < 10.0:
		await _wait(0.2)
		waited += 0.2
	var r: Dictionary = killed.get("r", {})
	check(int(r.get("ended", 0)) == 1 and str(r.get("refused", [])).contains(str(OS.get_process_id())), "procs: ends a process, never Oazy itself (%s)" % str(r))
	await _wait(0.5)
	check(not OS.is_process_running(pid), "procs: ping is gone")


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
		# The companion keeps pictures on its own, so a window minimised later
		# still has one.
		Host.captures.erase(hwnd)
		Host.keep_pictures(true)
		waited = 0.0
		while not Host._kept.has(hwnd) and waited < 12.0:
			await _wait(0.2)
			waited += 0.2
		check(Host._kept.has(hwnd), "capture: the companion keeps a picture of open windows")
		Host.minimize(hwnd)
		await _wait(1.0)
		var kept := Host.picture_of(hwnd)
		check(kept != null and kept.get_width() > 32, "capture: a minimised window still has its kept picture")
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


## The task manager: pinned for good, a card with a tail over its button,
## one row per app, and End that asks where it should.
func _tasks_tests(main: Node) -> void:
	var bar: Taskbar = main.taskbar
	var btn: TaskbarButton = bar.button_for(TasksFlyout.REF)
	check(btn != null, "tasks: always on the taskbar")
	Catalog.set_pinned(TasksFlyout.REF, false)
	bar.rebuild()
	check(Catalog.is_pinned(TasksFlyout.REF) and bar.button_for(TasksFlyout.REF) != null, "tasks: can't be unpinned")
	main.open_tasks()
	await _wait(0.6)
	var tf: TasksFlyout = main.tasks
	check(tf.is_open and not tf._rows.is_empty(), "tasks: opens from its button with rows")
	check(btn.active, "tasks: its button is lit while open")
	var tail: float = tf._glass.mat.get_shader_parameter("tail_x")
	check(absf(tf.global_position.x + tail - btn.get_global_rect().get_center().x) < 2.0, "tasks: the tail points at its button")
	check(tf.get_global_rect().end.y < bar.get_global_rect().position.y, "tasks: sits above the taskbar")
	var chrome := {}
	for g in tf._data["apps"]:
		if g["ref"] == "app:Chrome":
			chrome = g
	check(not chrome.is_empty() and chrome["windows"].size() == 2 and chrome["pids"].size() > 2, "tasks: an app's windows and helper processes are one row")
	var by_name := {}
	for id in ["background", "system"]:
		for g in tf._data[id]:
			by_name[str(g["exe"]).get_file().to_lower() if g["exe"] != "" else str(g["name"]).to_lower()] = g
	check(by_name.has("csrss") and by_name["csrss"]["protected"], "tasks: critical processes can't be ended")
	check(by_name.has("searchhost.exe") and not by_name["searchhost.exe"]["protected"], "tasks: other Windows processes can")
	var oazy_row := false
	for g in tf._data["background"]:
		if g["key"] == "oazy":
			oazy_row = g["protected"]
	check(oazy_row, "tasks: Oazy itself is shown but protected")
	tf.end_group(by_name["searchhost.exe"])
	check(tf.state_of(by_name["searchhost.exe"]["key"]) == &"confirm", "tasks: ending a Windows process asks first")
	tf._search.text = "chrome"
	tf._search.text_changed.emit("chrome")
	check(tf._sections["apps"]["box"].visible and not tf._sections["system"]["box"].visible, "tasks: search filters rows")
	tf._search.text = ""
	tf._search.text_changed.emit("")
	tf.close()
	await _wait(0.3)
	check(not tf.is_open and tf._timer.is_stopped(), "tasks: stops polling when closed")


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
