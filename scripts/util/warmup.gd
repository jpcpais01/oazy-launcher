class_name Warmup
extends Control
## Draws every shader once, hidden behind the wallpaper, right after loading.
## The OpenGL renderer compiles a shader the first time something uses it,
## which used to land on the first open of Start or a menu as a hitch. All of
## Oazy's windows share one GL context, so compiling here covers them all.

const DIR := "res://shaders"
const FRAMES := 3

var _left := FRAMES


static func run(host: Control) -> void:
	var w := Warmup.new()
	host.add_child(w)
	# Under the wallpaper, so nothing of it ever shows.
	host.move_child(w, 0)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	position = Vector2.ZERO
	size = Vector2(4, 4)
	for file in DirAccess.get_files_at(DIR):
		file = file.trim_suffix(".remap")
		if not file.ends_with(".gdshader"):
			continue
		var shader := load(DIR.path_join(file)) as Shader
		if shader == null:
			continue
		var mat := ShaderMaterial.new()
		mat.shader = shader
		var r := ColorRect.new()
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		r.material = mat
		r.size = Vector2(4, 4)
		add_child(r)
	# Prepare Start's contents too (tiles, rows, text), off the open path.
	var main := get_parent()
	if main and main.get("start") is StartPanel:
		(main.get("start") as StartPanel).prepare.call_deferred()


func _process(_delta: float) -> void:
	_left -= 1
	if _left <= 0:
		queue_free()
