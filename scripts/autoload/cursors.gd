extends Node
## Oazy's mouse pointer themes (drawn by tools/make_cursors.py).
##
## On Windows the companion swaps the system cursors, so every app shows the
## theme while Oazy runs, and Windows' own come back when Oazy closes (or on
## the next start if it crashed). Until then, and on other platforms, Godot
## shows the theme in Oazy's own windows.

signal applied(theme: String, system_wide: bool)

const OFF := "off"
const DIR := "user://cursors"

## Godot cursor shape -> glyph.
const SHAPES := {
	Input.CURSOR_ARROW: "arrow",
	Input.CURSOR_IBEAM: "text",
	Input.CURSOR_POINTING_HAND: "hand",
	Input.CURSOR_CROSS: "cross",
	Input.CURSOR_WAIT: "busy",
	Input.CURSOR_BUSY: "working",
	Input.CURSOR_DRAG: "move",
	Input.CURSOR_CAN_DROP: "arrow",
	Input.CURSOR_FORBIDDEN: "no",
	Input.CURSOR_VSIZE: "ns",
	Input.CURSOR_HSIZE: "we",
	Input.CURSOR_BDIAGSIZE: "nesw",
	Input.CURSOR_FDIAGSIZE: "nwse",
	Input.CURSOR_MOVE: "move",
	Input.CURSOR_VSPLIT: "ns",
	Input.CURSOR_HSPLIT: "we",
	Input.CURSOR_HELP: "help",
}

## The theme in use right now, and whether Windows itself shows it.
var current := ""
var system_wide := false
var _godot_theme := ""
var _job := 0


func _ready() -> void:
	Settings.changed.connect(func(key: String, _v: Variant) -> void:
		if key == "pointer":
			apply()
	)
	# The companion (re)started: hand it the theme again.
	Host.status_changed.connect(func(ok: bool) -> void:
		if ok:
			apply()
		else:
			system_wide = false
			_set_godot(current)
	)
	apply.call_deferred()


static func theme_ids() -> Array[String]:
	var out: Array[String] = []
	for t in CursorSets.THEMES:
		out.append(str(t["id"]))
	return out


static func theme_info(id: String) -> Dictionary:
	for t in CursorSets.THEMES:
		if t["id"] == id:
			return t
	return {}


## 64 px picture of one glyph, for previews.
static func preview(id: String, glyph: String) -> Texture2D:
	var path := "res://assets/cursors/%s/%s.png" % [id, glyph]
	return load(path) if ResourceLoader.exists(path) else null


func selected() -> String:
	var id := str(Settings.get_value("pointer"))
	return id if id == OFF or not theme_info(id).is_empty() else "oazy"


func apply() -> void:
	var id := selected()
	_job += 1
	var job := _job
	current = id
	if not _system_possible():
		system_wide = false
		_set_godot(id)
		applied.emit(id, false)
		return
	if id == OFF:
		Host.request(["cursors_off"])
		system_wide = false
		_set_godot(OFF)
		applied.emit(id, false)
		return
	# Oazy's windows get it right away; Windows' cursors follow once the
	# files are written.
	if not system_wide:
		_set_godot(id)
	WorkerThreadPool.add_task(func() -> void:
		var dir := _prepare(id)
		_send.call_deferred(job, id, dir)
	, false, "Prepare pointers")


func _system_possible() -> bool:
	return App.is_windows() and Host.available and not App.smoke_test


func _send(job: int, id: String, dir: String) -> void:
	if job != _job:
		return
	if dir == "" or not Host.available:
		system_wide = false
		_set_godot(id)
		applied.emit(id, false)
		return
	Host.request(["cursors", ProjectSettings.globalize_path(dir).replace("/", "\\")], func(d: Dictionary) -> void:
		if job != _job:
			return
		system_wide = bool(d.get("ok", false))
		# With Windows showing the theme, Godot's windows just use the system
		# cursors too (custom ones would be a fixed size and lose the animation).
		_set_godot(OFF if system_wide else id)
		applied.emit(id, system_wide)
	)


## Shows the theme as Godot's own cursors (or Windows' standard ones for OFF).
func _set_godot(id: String) -> void:
	if id == _godot_theme:
		return
	_godot_theme = id
	var info := theme_info(id)
	var px := clampi(roundi(32.0 * _scale()), 24, 128)
	for shape in SHAPES:
		if info.is_empty():
			Input.set_custom_mouse_cursor(null, shape)
			continue
		var glyph: String = SHAPES[shape]
		var tex := preview(id, glyph)
		if tex == null:
			Input.set_custom_mouse_cursor(null, shape)
			continue
		var img := tex.get_image()
		if img.is_compressed():
			img.decompress()
		img.resize(px, px, Image.INTERPOLATE_LANCZOS)
		var hot: Vector2 = CursorSets.HOTSPOTS[info["shape"]][glyph]
		Input.set_custom_mouse_cursor(ImageTexture.create_from_image(img), shape, hot * px / CursorSets.UNIT)


func _scale() -> float:
	var dpi := DisplayServer.screen_get_dpi()
	return maxf(1.0, dpi / 96.0) if dpi > 0 else 1.0


# --- Files for Windows --------------------------------------------------------------

## Unpacks a theme's bundle into user://cursors/<id>-<hash>/ (once per
## version) and returns that folder, or "" on failure. Worker thread safe.
static func _prepare(id: String) -> String:
	var src := "res://assets/cursors/%s.bin" % id
	var data := FileAccess.get_file_as_bytes(src)
	if data.size() < 8 or data.slice(0, 4).get_string_from_ascii() != "OZC1":
		push_warning("Pointer theme %s is missing from the package" % id)
		return ""
	var tag := "%s-%s" % [id, FileAccess.get_md5(src).substr(0, 8)]
	var dir := DIR.path_join(tag)
	if FileAccess.file_exists(dir.path_join("ready")):
		return dir
	DirAccess.make_dir_recursive_absolute(dir)
	var entries := _unbundle(data)
	var info := theme_info(id)
	for name in entries:
		if str(name).ends_with(".cur") and not _write(dir.path_join(name), entries[name]):
			return ""
	for glyph in CursorSets.ANIMATED:
		var hot: Vector2 = CursorSets.HOTSPOTS[info["shape"]][glyph]
		if not _write(dir.path_join(glyph + ".ani"), _ani(glyph, entries, hot)):
			return ""
	_write(dir.path_join("ready"), "ok".to_utf8_buffer())
	# Older versions of this and other themes aren't needed any more.
	for old in DirAccess.get_directories_at(DIR):
		if old != tag and old.begins_with(id + "-"):
			var path := DIR.path_join(old)
			for f in DirAccess.get_files_at(path):
				DirAccess.remove_absolute(path.path_join(f))
			DirAccess.remove_absolute(path)
	return dir


static func _write(path: String, bytes: PackedByteArray) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_buffer(bytes)
	f.close()
	return true


static func _unbundle(data: PackedByteArray) -> Dictionary:
	var out := {}
	var count := data.decode_u32(4)
	var at := 8
	for i in count:
		var n := data.decode_u16(at)
		var name := data.slice(at + 2, at + 2 + n).get_string_from_utf8()
		at += 2 + n
		var size := data.decode_u32(at)
		out[name] = data.slice(at + 4, at + 4 + size)
		at += 4 + size
	return out


## Builds an animated cursor: each frame is the still layer with the spinner
## layer laid over it, turned a quarter at a time (only a quarter of the
## frames are stored).
static func _ani(glyph: String, entries: Dictionary, hot: Vector2) -> PackedByteArray:
	var quarter: int = CursorSets.FRAMES / 4
	var spin: Dictionary = CursorSets.SPIN[glyph]
	var center: Vector2 = spin["center"]
	var bases := {}
	var spins := {}
	for px in CursorSets.SIZES:
		bases[px] = _png(entries.get("%s/base/%d" % [glyph, px], PackedByteArray()))
		for r in quarter:
			spins["%d/%d" % [px, r]] = _png(entries.get("%s/spin/%d/%d" % [glyph, px, r], PackedByteArray()))
	var icons := PackedByteArray()
	for f in CursorSets.FRAMES:
		var pngs: Array[PackedByteArray] = []
		for px in CursorSets.SIZES:
			var frame: Image = (bases[px] as Image).duplicate()
			var sp: Image = (spins["%d/%d" % [px, f % quarter]] as Image).duplicate()
			for i in f / quarter:
				sp.rotate_90(CLOCKWISE)
			var n := sp.get_width()
			var at := Vector2i(roundi(center.x * px / CursorSets.UNIT - n / 2.0), roundi(center.y * px / CursorSets.UNIT - n / 2.0))
			frame.blend_rect(sp, Rect2i(0, 0, n, sp.get_height()), at)
			pngs.append(frame.save_png_to_buffer())
		icons.append_array(_chunk("icon", _cur(pngs, CursorSets.SIZES, hot)))
	var anih := StreamPeerBuffer.new()
	# cbSize, frames, steps, cx, cy, bit count, planes, rate (1/60 s), flags (AF_ICON)
	for v in [36, CursorSets.FRAMES, CursorSets.FRAMES, 0, 0, 32, 1, CursorSets.JIFFIES, 1]:
		anih.put_u32(v)
	var body := "ACON".to_ascii_buffer()
	body.append_array(_chunk("anih", anih.data_array))
	var list := "fram".to_ascii_buffer()
	list.append_array(icons)
	body.append_array(_chunk("LIST", list))
	var out := StreamPeerBuffer.new()
	out.put_data("RIFF".to_ascii_buffer())
	out.put_u32(body.size())
	out.put_data(body)
	return out.data_array


static func _png(bytes: PackedByteArray) -> Image:
	var img := Image.new()
	if bytes.is_empty() or img.load_png_from_buffer(bytes) != OK:
		return Image.create_empty(1, 1, false, Image.FORMAT_RGBA8)
	img.convert(Image.FORMAT_RGBA8)
	return img


## A .cur with PNG images (one per size).
static func _cur(pngs: Array[PackedByteArray], sizes: Array[int], hot: Vector2) -> PackedByteArray:
	var b := StreamPeerBuffer.new()
	b.put_u16(0)
	b.put_u16(2)
	b.put_u16(pngs.size())
	var offset := 6 + 16 * pngs.size()
	for i in pngs.size():
		var px: int = sizes[i]
		b.put_u8(px % 256)
		b.put_u8(px % 256)
		b.put_u8(0)
		b.put_u8(0)
		b.put_u16(roundi(hot.x * px / CursorSets.UNIT))
		b.put_u16(roundi(hot.y * px / CursorSets.UNIT))
		b.put_u32(pngs[i].size())
		b.put_u32(offset)
		offset += pngs[i].size()
	for p in pngs:
		b.put_data(p)
	return b.data_array


static func _chunk(tag: String, payload: PackedByteArray) -> PackedByteArray:
	var b := StreamPeerBuffer.new()
	b.put_data(tag.to_ascii_buffer())
	b.put_u32(payload.size())
	b.put_data(payload)
	if payload.size() % 2 == 1:
		b.put_u8(0)
	return b.data_array
