class_name ClaudeAttach
## Files and pictures sent to Claude with a message. Pictures go inline as
## stream-json image blocks (made small enough for the API first); any other
## file is named by its path at the end of the message, for Claude Code to
## read itself. Oazy Claude (native/claude) writes the same lines.

## Pictures Claude can see. Others (gif, heic...) go by path.
const IMAGE_EXTS := ["png", "jpg", "jpeg", "webp", "bmp", "tga"]
## The longest side the API looks at; bigger is only slower.
const MAX_SIDE := 1568
## Raw bytes we keep as they are (base64 stays under the API's 5 MB).
const MAX_RAW := 3_500_000
## One line per file at the end of the message, after a blank line.
const FILE_PREFIX := "[Attached file: "
## The most at once.
const MOST := 10


## A picture or file to send: {kind: "image"|"file", name, path, media_type,
## data (base64), image (Image, for thumbnails)}. {} if it can't be read.
## Reads and re-encodes: call off the main thread.
static func from_path(path: String) -> Dictionary:
	path = path.replace("\\", "/")
	if not FileAccess.file_exists(path):
		return {}
	var a := {"kind": "file", "name": path.get_file(), "path": path}
	if path.get_extension().to_lower() in IMAGE_EXTS:
		var bytes := FileAccess.get_file_as_bytes(path)
		var img := Image.new()
		if img.load(path) == OK and not img.is_empty():
			var ext := path.get_extension().to_lower()
			var mt := {"png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg", "webp": "image/webp"}.get(ext, "")
			# Already small and in a format the API takes: sent untouched.
			if mt != "" and bytes.size() <= MAX_RAW and maxi(img.get_width(), img.get_height()) <= MAX_SIDE:
				a.merge({"kind": "image", "media_type": mt, "data": Marshalls.raw_to_base64(bytes), "image": img}, true)
			else:
				a.merge(from_image(img, a["name"], false), true)
				a["path"] = path
	return a


## A picture shrunk to MAX_SIDE and encoded: PNG if `lossless` (pasted
## screenshots, text stays crisp) or see-through, while that's small enough.
static func from_image(img: Image, name: String = "Pasted image", lossless: bool = true) -> Dictionary:
	img = img.duplicate()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	var side := maxi(img.get_width(), img.get_height())
	if side > MAX_SIDE:
		var k := float(MAX_SIDE) / side
		img.resize(maxi(1, roundi(img.get_width() * k)), maxi(1, roundi(img.get_height() * k)), Image.INTERPOLATE_LANCZOS)
	var bytes := PackedByteArray()
	var mt := "image/jpeg"
	if lossless or img.detect_alpha() != Image.ALPHA_NONE:
		bytes = img.save_png_to_buffer()
		mt = "image/png"
	if bytes.is_empty() or bytes.size() > MAX_RAW:
		var flat := img
		if img.detect_alpha() != Image.ALPHA_NONE:
			flat = Image.create(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8)
			flat.fill(Color.WHITE)
			flat.blend_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i.ZERO)
		flat.convert(Image.FORMAT_RGB8)
		bytes = flat.save_jpg_to_buffer(0.88)
		mt = "image/jpeg"
	return {"kind": "image", "name": name, "path": "", "media_type": mt, "data": Marshalls.raw_to_base64(bytes), "image": img}


## What claude gets for a message: a plain string, or blocks when there are
## pictures. Files are lines at the end of the text.
static func content(text: String, atts: Array) -> Variant:
	var files := PackedStringArray()
	var blocks: Array = []
	for a: Dictionary in atts:
		if a["kind"] == "image":
			blocks.append({"type": "image", "source": {"type": "base64", "media_type": a["media_type"], "data": a["data"]}})
		else:
			files.append(FILE_PREFIX + _native(str(a["path"])) + "]")
	if not files.is_empty():
		text = (text + "\n\n" if text != "" else "") + "\n".join(files)
	if blocks.is_empty():
		return text
	if text != "":
		blocks.append({"type": "text", "text": text})
	return blocks


## Splits the file lines off the end of a message: [text, paths].
static func split(text: String) -> Array:
	var paths := PackedStringArray()
	var ls := text.split("\n")
	while not ls.is_empty():
		var l := ls[ls.size() - 1].strip_edges()
		if l.begins_with(FILE_PREFIX) and l.ends_with("]"):
			paths.insert(0, l.trim_prefix(FILE_PREFIX).trim_suffix("]"))
			ls.remove_at(ls.size() - 1)
		elif l == "" and not paths.is_empty():
			ls.remove_at(ls.size() - 1)
		else:
			break
	return ["\n".join(ls).strip_edges(), paths]


## The pictures in a sent (or remembered) message's blocks, as Images.
static func images_in(c: Variant) -> Array[Image]:
	var out: Array[Image] = []
	if not c is Array:
		return out
	for b in c:
		if b is Dictionary and str(b.get("type", "")) == "image" and b.get("source") is Dictionary:
			var img := decode(str(b["source"].get("data", "")), str(b["source"].get("media_type", "")))
			if img:
				out.append(img)
	return out


static func decode(data: String, media_type: String) -> Image:
	var bytes := Marshalls.base64_to_raw(data)
	var img := Image.new()
	var err := ERR_FILE_UNRECOGNIZED
	match media_type:
		"image/png": err = img.load_png_from_buffer(bytes)
		"image/jpeg": err = img.load_jpg_from_buffer(bytes)
		"image/webp": err = img.load_webp_from_buffer(bytes)
	return img if err == OK and not img.is_empty() else null


## A thumbnail exactly w x h (or at most, with `fit`), cropped to fill: drawn
## at UV 0..1 so rounded_tex's corners land on the picture's.
static func thumb(img: Image, w: int, h: int, fit: bool = false) -> Texture2D:
	var t := img.duplicate() as Image
	if t.is_compressed():
		t.decompress()
	var iw := t.get_width()
	var ih := t.get_height()
	if fit:
		var k := minf(float(w) / iw, float(h) / ih)
		w = maxi(24, roundi(iw * k))
		h = maxi(24, roundi(ih * k))
	var want := float(w) / h
	if float(iw) / ih > want:
		var cw := maxi(1, roundi(ih * want))
		t = t.get_region(Rect2i((iw - cw) / 2, 0, cw, ih))
	else:
		var ch := maxi(1, roundi(iw / want))
		t = t.get_region(Rect2i(0, (ih - ch) / 2, iw, ch))
	# Twice the size it's drawn at, for sharp corners at 2x scale.
	t.resize(w * 2, h * 2, Image.INTERPOLATE_LANCZOS)
	return ImageTexture.create_from_image(t)


static func _native(p: String) -> String:
	return p.replace("/", "\\") if App.is_windows() else p
