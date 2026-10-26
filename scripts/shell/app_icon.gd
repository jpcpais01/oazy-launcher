class_name AppIcon
extends Control
## The icon for anything in the Catalog: the app's real icon, a game's cover,
## or a soft plate with a glyph or initial when there is no artwork yet.

const PLATE := preload("res://shaders/plate.gdshader")

var item: Dictionary = {}
var _plate: ColorRect
var _plate_mat: ShaderMaterial
var _tex: TextureRect
var _glyph: TextureRect
var _letter: Label
var _cover: CoverArt
var _key := ""


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plate_mat = ShaderMaterial.new()
	_plate_mat.shader = PLATE
	_plate = ColorRect.new()
	_plate.color = Color.WHITE
	_plate.material = _plate_mat
	_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plate.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_plate)
	_tex = TextureRect.new()
	_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_tex)
	_glyph = TextureRect.new()
	_glyph.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_glyph.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	_glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glyph.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_glyph)
	_letter = Kit.label("", 18, 700, Color.WHITE, true)
	_letter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_letter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_letter.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_letter.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.25))
	_letter.add_theme_constant_override("shadow_offset_y", 1)
	add_child(_letter)


func _ready() -> void:
	resized.connect(_sync)
	Catalog.icon_ready.connect(func(key: String) -> void:
		if key == _key:
			refresh()
	)
	App.accent_changed.connect(func(_c: Color) -> void:
		if str(item.get("kind", "")) == "oazy":
			refresh()
	)
	Settings.changed.connect(func(key: String, _v: Variant) -> void:
		if key == "custom_icons":
			refresh()
	)
	_sync()
	refresh()


func set_item(it: Dictionary) -> AppIcon:
	item = it
	if is_inside_tree():
		refresh()
	return self


func refresh() -> void:
	_tex.visible = false
	_glyph.visible = false
	_letter.visible = false
	_plate.visible = false
	if _cover:
		_cover.visible = false
	var kind := str(item.get("kind", ""))
	var name := str(item.get("name", "?"))
	_key = str(item.get("icon_key", ""))
	if kind == "game":
		if _cover == null:
			_cover = CoverArt.new()
			_cover.glow_enabled = false
			_cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			add_child(_cover)
		_cover.visible = true
		_cover.setup(str(item.get("entry_id", "")), _radius())
		return
	if kind == "oazy":
		_show_plate(App.accent.lightened(0.05), App.accent.darkened(0.4))
		_show_glyph(str(item.get("glyph", "grid")))
		return
	var own := custom_look(item)
	if not own.is_empty():
		_show_plate(own[1], own[2])
		_show_glyph(own[0])
		return
	var tex := Catalog.icon(_key) if _key != "" else null
	if tex != null:
		_tex.texture = tex
		_tex.visible = true
		return
	var lower := name.to_lower()
	if lower.contains("claude"):
		_show_plate(Color("e9a37e"), Color("b8573b"))
		_show_glyph("terminal")
		return
	var h := absi(name.hash())
	var base := float(h % 360) / 360.0
	_show_plate(Color.from_hsv(base, 0.34, 0.74), Color.from_hsv(fposmod(base + 0.06, 1.0), 0.46, 0.44))
	_letter.text = Fmt.initials(name).substr(0, 1) if name != "" else "?"
	_letter.visible = true


## Oazy's own icons for common Windows apps, in place of their stock ones.
## Settings ("custom_icons") picks which are on; File Explorer and Terminal
## are by default. Each one matches app ids / paths (lowercase, "/" slashes)
## or exact display names.
const CUSTOM := {
	"explorer": {"name": "File Explorer", "glyph": "folder", "a": "f3c978", "b": "c27a35",
		"ids": ["microsoft.windows.explorer", "/explorer.exe"], "names": ["file explorer"]},
	"terminal": {"name": "Terminal", "glyph": "terminal", "a": "4a5869", "b": "161c26",
		"ids": ["windowsterminal", "/wt.exe", "/cmd.exe", "powershell", "/pwsh.exe"], "names": ["terminal", "windows terminal", "command prompt", "windows powershell", "powershell"]},
	"chrome": {"name": "Google Chrome", "glyph": "globe", "a": "7cb8f5", "b": "2d63b8",
		"ids": ["chrome"], "names": ["google chrome"]},
	"edge": {"name": "Microsoft Edge", "glyph": "compass", "a": "5fd6c0", "b": "1f6f8f",
		"ids": ["msedge", "microsoftedge"], "names": ["microsoft edge"]},
	"firefox": {"name": "Firefox", "glyph": "compass", "a": "ffab6b", "b": "c2445a",
		"ids": ["firefox"], "names": ["firefox", "mozilla firefox"]},
	"steam": {"name": "Steam", "glyph": "gamepad", "a": "6e8fb3", "b": "1b2a3d",
		"ids": ["/steam.exe", "valve.steam"], "names": ["steam"]},
	"discord": {"name": "Discord", "glyph": "chat", "a": "8e95f7", "b": "4a4fc4",
		"ids": ["discord"], "names": ["discord"]},
	"vscode": {"name": "Visual Studio Code", "glyph": "code", "a": "5aaef0", "b": "1d5c9e",
		"ids": ["visualstudiocode", "vscode", "/code.exe"], "names": ["visual studio code"]},
	"spotify": {"name": "Spotify", "glyph": "music", "a": "6fdc93", "b": "1f7a45",
		"ids": ["spotify"], "names": ["spotify"]},
	"notepad": {"name": "Notepad", "glyph": "edit", "a": "9fd3f0", "b": "3f7fa6",
		"ids": ["windowsnotepad", "/notepad.exe"], "names": ["notepad"]},
	"calculator": {"name": "Calculator", "glyph": "calculator", "a": "a9b4c4", "b": "4b5566",
		"ids": ["windowscalculator", "calculatorapp", "/calc.exe"], "names": ["calculator"]},
	"settings": {"name": "Windows Settings", "glyph": "settings", "a": "9aa7ba", "b": "3e4859",
		"ids": ["windows.immersivecontrolpanel", "ms-settings:"], "names": ["windows settings"]},
	"photos": {"name": "Photos", "glyph": "image", "a": "f59fb6", "b": "a8456e",
		"ids": ["windows.photos"], "names": ["photos"]},
	"paint": {"name": "Paint", "glyph": "palette", "a": "f6b37a", "b": "c25a4a",
		"ids": ["microsoft.paint", "/mspaint.exe"], "names": ["paint"]},
	"taskmgr": {"name": "Task Manager", "glyph": "cpu", "a": "7fd1d8", "b": "2b6d78",
		"ids": ["/taskmgr.exe"], "names": ["task manager"]},
}


## Which CUSTOM entry an app matches ("" for none). Claude keeps its own look.
static func custom_key(it: Dictionary) -> String:
	if it.has("custom"):
		return str(it["custom"])
	var name := str(it.get("name", "")).to_lower().strip_edges()
	if name.contains("claude"):
		return ""
	var id := (str(it.get("ref", "")) + "|" + str(it.get("icon_key", "")) + "|").to_lower().replace("\\", "/")
	for key in CUSTOM:
		var c: Dictionary = CUSTOM[key]
		if name in c["names"]:
			return key
		for part in c["ids"]:
			# Paths must match whole file names ("/code.exe" isn't "/vscode.exe").
			if str(part).ends_with(".exe") and not id.contains(str(part) + "|"):
				continue
			if id.contains(str(part)):
				return key
	return ""


static func custom_enabled(key: String) -> bool:
	var on: Variant = Settings.get_value("custom_icons")
	return on is Array and (on as Array).has(key)


## [glyph, top colour, bottom colour] when this app shows an Oazy icon, else [].
static func custom_look(it: Dictionary) -> Array:
	var key := custom_key(it)
	if key == "" or not CUSTOM.has(key) or (not it.has("custom") and not custom_enabled(key)):
		return []
	var c: Dictionary = CUSTOM[key]
	return [c["glyph"], Color(str(c["a"])), Color(str(c["b"]))]


func _show_plate(a: Color, b: Color) -> void:
	_plate_mat.set_shader_parameter("color_a", a)
	_plate_mat.set_shader_parameter("color_b", b)
	_plate.visible = true


func _show_glyph(name: String) -> void:
	var px := int(clampf(minf(size.x, size.y) * 0.5, 10.0, 96.0))
	_glyph.texture = Icons.tex(name, px, Color.WHITE)
	_glyph.set_meta("glyph", name)
	_glyph.visible = true


func _radius() -> float:
	return roundf(minf(size.x, size.y) * 0.26)


func _sync() -> void:
	_plate_mat.set_shader_parameter("rect_size", size)
	_plate_mat.set_shader_parameter("radius", _radius())
	_letter.add_theme_font_size_override("font_size", int(clampf(minf(size.x, size.y) * 0.46, 10.0, 80.0)))
	if _glyph.visible and _glyph.has_meta("glyph"):
		_show_glyph(str(_glyph.get_meta("glyph")))
	if _cover:
		_cover.setup(str(item.get("entry_id", "")), _radius())
