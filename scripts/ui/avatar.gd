class_name Avatar
extends Control
## A person's round picture: their Google photo, or their initial on a soft
## accent plate when there's no photo.

const ROUNDED := preload("res://shaders/rounded_tex.gdshader")

var _plate: Panel
var _letter: Label
var _photo: TextureRect
var _mat: ShaderMaterial
var _ring: Panel
var _name := ""


func _init(px: float = 42.0) -> void:
	custom_minimum_size = Vector2(px, px)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plate = Panel.new()
	_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plate.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_plate)
	_letter = Kit.label("", 18, 700, Color.WHITE, true)
	_letter.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_letter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_letter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_letter)
	_photo = TextureRect.new()
	_photo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_photo.stretch_mode = TextureRect.STRETCH_SCALE
	_photo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_photo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_mat = ShaderMaterial.new()
	_mat.shader = ROUNDED
	_photo.material = _mat
	add_child(_photo)
	# A hairline round the edge, so a dark photo still reads as a circle.
	_ring = Panel.new()
	_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ring.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ring.add_theme_stylebox_override("panel", Kit.box(Color(0, 0, 0, 0), 999, Color(1, 1, 1, 0.16), 1))
	add_child(_ring)


func _ready() -> void:
	resized.connect(_sync)
	App.accent_changed.connect(func(_c: Color) -> void: _sync_plate())
	_sync_plate()
	_sync()


## Shows `tex`, or the first letter of `person` when it's null.
func set_person(person: String, tex: Texture2D) -> void:
	_name = person
	# Square it up (centre crop): the round mask works on the whole texture.
	if tex and tex.get_width() != tex.get_height():
		var img := tex.get_image()
		var side := mini(img.get_width(), img.get_height())
		img = img.get_region(Rect2i((img.get_width() - side) / 2, (img.get_height() - side) / 2, side, side))
		tex = ImageTexture.create_from_image(img)
	_photo.texture = tex
	_photo.visible = tex != null
	_letter.visible = tex == null
	_letter.text = person.strip_edges().substr(0, 1).to_upper()


func _sync_plate() -> void:
	_plate.add_theme_stylebox_override("panel", Kit.box(Color(App.accent, 0.35), 999, Color(1, 1, 1, 0.3), 1))


func _sync() -> void:
	_mat.set_shader_parameter("size", size)
	_mat.set_shader_parameter("radius", minf(size.x, size.y) * 0.5)
	_letter.add_theme_font_size_override("font_size", int(clampf(minf(size.x, size.y) * 0.42, 10.0, 64.0)))
