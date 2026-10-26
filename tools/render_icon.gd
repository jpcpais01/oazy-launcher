extends Node
## Renders the Oazy icon (the water orb with the mark) to PNG, for
## assets/icon.png and the Windows .ico. Needs a real renderer:
##   xvfb-run godot --path . --rendering-driver opengl3 -- --render-icon=out.png


func _ready() -> void:
	var out := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--render-icon="):
			out = a.get_slice("=", 1)
	var px := 1024
	var vp := SubViewport.new()
	vp.size = Vector2i(px, px)
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var icon := OazyMark.icon(px, 0.94, -0.8)
	icon.size = Vector2(px, px)
	vp.add_child(icon)
	for i in 30:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	vp.get_texture().get_image().save_png(out)
	print("ICON: ", out)
	get_tree().quit(0)
