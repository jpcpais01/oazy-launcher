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


func _ui_tests() -> void:
	var main := get_tree().current_scene
	check(main != null and main.has_method("go"), "ui: main scene loaded")
	if main == null:
		return
	var waited := 0.0
	while not main.loaded and waited < 5.0:
		await _wait(0.1)
		waited += 0.1
	check(main.loaded, "ui: loading screen finished")
	main.go(&"library")
	await _wait(0.60)
	check(main.current_page == &"library", "ui: library page")
	check(main.library_page._cards.size() == Library.entries.size(), "ui: library shows every entry")
	main.go(&"settings")
	await _wait(0.30)
	main.go(&"home")
	await _wait(0.30)
	check(main.home.current_id() != "", "ui: home has a selection")
	main.home.move(1)
	main.home.move(-1)
	var first_id := str(Library.recent()[0]["id"])
	main.open_edit(first_id)
	main.open_add({"name": "Dropped", "path": "C:/x.exe"})
	main.show_entry_menu(first_id, Vector2(200, 200))
	await _wait(0.30)
	check(main.modal_open(), "ui: dialogs open")
	main._menu.hide()
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
	check(Icons.tex("play", 24) != null, "ui: icons render")


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
