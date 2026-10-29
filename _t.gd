extends SceneTree
func _init():
	var img := Image.create(40, 30, false, Image.FORMAT_RGB8)
	img.fill(Color.RED)
	var a := ClaudeAttach.from_image(img)
	var c = ClaudeAttach.content("what colour?", [a, {"kind":"file","path":"/home/x/a b.pdf","name":"a b.pdf"}])
	print(JSON.stringify(c).left(300))
	print(ClaudeAttach.split(c[1]["text"]))
	print(ClaudeAttach.images_in(c).size())
	var line := JSON.stringify({"type": "user", "message": {"role": "user", "content": c}, "parent_tool_use_id": null, "session_id": "default"})
	FileAccess.open("/tmp/claude-0/line.json", FileAccess.WRITE).store_string(line + "\n")
	quit()
