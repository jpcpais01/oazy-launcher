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
	Library.add_entry({"name": "Discord", "path": "C:/Apps/Discord.exe", "kind": "app", "launches": 3})
	await _wait(0.7)
	await shot("00-loading")
	var main := get_tree().current_scene
	var waited := 0.0
	while not main.loaded and waited < 8.0:
		await _wait(0.2)
		waited += 0.2
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
	main.home.select_id(str(Library.recent()[0]["id"]))
	await _wait(2.5)
	await shot("01-home")
	main.home.move(2)
	await _wait(2.0)
	await shot("02-home-browse")
	main.go(&"library")
	await _wait(1.5)
	await shot("03-library")
	main.go(&"settings")
	await _wait(1.2)
	await shot("04-settings")
	main.go(&"home")
	await _wait(0.8)
	main.open_add({})
	await _wait(0.9)
	await shot("05-add")
	_close_modals()
	await _wait(0.5)
	Updater.apply_releases([
		{"tag_name": "v1.0.9", "published_at": "2026-10-25T10:00:00Z", "body": "### Faster everything\n- **Instant search** in the library.\n- New *Eco* mode for laptops.\n- Fixed artwork for newer Steam games.", "assets": [{"name": "OazyLauncher.exe", "size": 97000000, "browser_download_url": "https://x"}]},
		{"tag_name": "v1.0.8", "published_at": "2026-10-20T10:00:00Z", "body": "### Controller support\n- Shoulder buttons switch pages.", "assets": [{"name": "OazyLauncher.exe", "size": 96000000, "browser_download_url": "https://x"}]},
	], "1.0.2")
	Updater.state = &"available"
	main.show_update()
	await _wait(1.0)
	await shot("06-update")
	Updater.state = &"downloading"
	Updater.state_changed.emit(&"downloading")
	for k in 8:
		Updater.progress.emit(int(97000000 * 0.06 * (k + 1)), 97000000, 14200000.0)
		await _wait(0.12)
	await _wait(0.8)
	await shot("07-download")
	Updater.state = &"available"
	_close_modals()
	await _wait(0.5)
	main.launch(str(Library.recent()[0]["id"]))
	await _wait(1.4)
	await shot("08-launch")
	print("SCREENSHOTS: DONE")
	get_tree().quit(0)


func _close_modals() -> void:
	for m in get_tree().get_nodes_in_group("modal"):
		if m.has_method("close"):
			m.close()


func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := dir.path_join(name + ".png")
	img.save_png(path)
	print("  saved ", path, " ", img.get_size())


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
