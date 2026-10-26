extends Node
## Persistent user preferences (user://settings.cfg).

signal changed(key: String, value: Variant)

const PATH := "user://settings.cfg"
const DEFAULTS := {
	"minimize_for_games": false,
	"launch_at_startup": false,
	"shell_fullscreen": true,
	"shell_mode": true,
	"hide_windows_taskbar": true,
	"theme_app_windows": true,
	"alt_tab": true,
	"cpu_temp": false,
	"favorites": [],
	"fav_icon_size": "medium",
	"custom_icons": ["explorer", "terminal", "claude", "whatsapp"],
	## Default custom icons already offered, so new defaults reach old installs once.
	"custom_icons_offered": [],
	"auto_check_updates": true,
	"ui_sounds": true,
	"volume": 0.6,
	"effects": "high",
	"accent": "38d6c4",
	"wallpaper": "oasis",
	"wallpaper_light": "auto",
	"user_name": "",
	"pins": [],
	"pins_initialized": false,
	## The order the taskbar was dragged into (refs; missing ones keep their spot).
	"taskbar_order": [],
	"recent_apps": [],
	"window_rect": [],
	"last_seen_version": "",
	"pending_update_version": "",
	"pending_update_notes": "",
	"pending_update_from": "",
	"steam_root": "",
	"first_scan_done": false,
	"claude_checked": false,
	"seen_shell_intro": false,
	"weather_unit": "auto",
	"browser_links": true,
	"browser_pinned": false,
	"terminal_oazy": true,
	"terminal_pinned": false,
	"flow_pinned": false,
	"claude_app_pinned": false,
	"files_oazy": true,
	"cleaner_watch": true,
	"pointer": "oazy",
	"removed_imports": [],
}

var _values := {}
var _dirty := false
var _save_timer: Timer


func _ready() -> void:
	_values = DEFAULTS.duplicate(true)
	var cfg := ConfigFile.new()
	if not App.smoke_test and cfg.load(PATH) == OK and cfg.has_section("settings"):
		for key in cfg.get_section_keys("settings"):
			_values[key] = cfg.get_value("settings", key)
	_offer_new_icons()
	_save_timer = Timer.new()
	_save_timer.one_shot = true
	_save_timer.wait_time = 0.6
	_save_timer.timeout.connect(save)
	add_child(_save_timer)


## Turns on custom icons that became defaults after this install picked its set.
func _offer_new_icons() -> void:
	var on: Array = (_values["custom_icons"] as Array).duplicate()
	var offered: Array = (_values["custom_icons_offered"] as Array).duplicate()
	var changed_any := false
	for key in DEFAULTS["custom_icons"]:
		if not offered.has(key):
			offered.append(key)
			if not on.has(key):
				on.append(key)
			changed_any = true
	if changed_any:
		_values["custom_icons"] = on
		_values["custom_icons_offered"] = offered
		_dirty = true


func get_value(key: String) -> Variant:
	return _values.get(key, DEFAULTS.get(key))


func set_value(key: String, value: Variant) -> void:
	if _values.get(key) == value:
		return
	_values[key] = value
	_dirty = true
	if is_inside_tree():
		_save_timer.start()
	changed.emit(key, value)


func save() -> void:
	if not _dirty or App.smoke_test:
		return
	var cfg := ConfigFile.new()
	for key in _values.keys():
		cfg.set_value("settings", key, _values[key])
	if cfg.save(PATH) == OK:
		_dirty = false


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		save()
