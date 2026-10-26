class_name NotesCards
extends ScrollContainer
## Patch notes as a column of glass cards: each `###` headline becomes a card
## with an icon picked from its words, `## Version x` becomes a quiet divider.
## Call reveal() to bring the cards in one after another.

## First matching word picks the icon.
const ICON_WORDS := [
	["alt+tab", "layers"], ["window", "window"], ["taskbar", "apps"], ["start", "search"],
	["search", "search"], ["game", "gamepad"], ["art", "image"], ["cover", "image"],
	["update", "download"], ["install", "download"], ["fast", "bolt"], ["smooth", "bolt"],
	["menu", "more"], ["setting", "settings"], ["weather", "sun"], ["clock", "clock"],
	["calendar", "calendar"], ["volume", "volume"], ["music", "music"], ["media", "music"],
	["wi-fi", "wifi"], ["bluetooth", "bluetooth"], ["desktop", "desktop"], ["icon", "palette"],
	["glass", "palette"], ["look", "palette"], ["keyboard", "keyboard"], ["shortcut", "keyboard"],
	["fix", "check"], ["steadier", "check"], ["stop", "check"],
]

var _cards: Array[Control] = []


func _init(markdown: String = "") -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var list := Kit.vbox(12)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(list)
	for section in parse(markdown):
		var node: Control
		if section["kind"] == "version":
			node = _divider(str(section["title"]))
		else:
			node = _card(str(section["title"]), str(section["body"]))
		list.add_child(node)
		_cards.append(node)
	if _cards.is_empty():
		var empty := _card("Behind-the-scenes improvements", "- Small fixes and polish all over.")
		list.add_child(empty)
		_cards.append(empty)


## Splits notes into {kind: "version"|"card", title, body} sections.
static func parse(md: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var cur := {}
	for raw in md.replace("\r\n", "\n").split("\n"):
		var line := raw.strip_edges()
		if line.begins_with("<!--") or line == "---" or line == "***":
			continue
		if line.begins_with("## ") or line.begins_with("# "):
			cur = {}
			out.append({"kind": "version", "title": line.lstrip("#").strip_edges(), "body": ""})
		elif line.begins_with("### "):
			cur = {"kind": "card", "title": line.substr(4).strip_edges(), "body": ""}
			out.append(cur)
		elif line != "":
			if cur.is_empty():
				cur = {"kind": "card", "title": "", "body": ""}
				out.append(cur)
			cur["body"] = str(cur["body"]) + raw.rstrip(" \t") + "\n"
	return out


static func icon_for(text: String) -> String:
	# Match word starts only, so "restart" isn't "art".
	var low := " " + RegEx.create_from_string("[^a-z0-9+\\-]+").sub(text.to_lower(), " ", true)
	for pair in ICON_WORDS:
		if low.contains(" " + pair[0]):
			return pair[1]
	return "sparkles"


func reveal(delay: float = 0.0) -> void:
	var i := 0
	for c in _cards:
		c.modulate.a = 0.0
		c.pivot_offset = Vector2(c.size.x * 0.5, 0.0)
		c.scale = Vector2.ONE * 0.97
		var t := c.create_tween().set_parallel(true).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
		var at := delay + minf(i, 10) * 0.07
		t.tween_property(c, "modulate:a", 1.0, 0.45).set_delay(at)
		t.tween_property(c, "scale", Vector2.ONE, 0.6).set_delay(at)
		i += 1


func _divider(title: String) -> Control:
	var row := Kit.hbox(12)
	row.add_child(Kit.label(title.to_upper(), 12, 700, App.accent.lightened(0.35)))
	var line := ColorRect.new()
	line.color = Color(1, 1, 1, 0.08)
	line.custom_minimum_size.y = 1
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(line)
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_top", 6)
	pad.add_child(row)
	return pad


func _card(title: String, body: String) -> Control:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", Kit.box(Color(1, 1, 1, 0.045), 18, Color(1, 1, 1, 0.075), 1, 20, 16))
	var row := Kit.hbox(16)
	card.add_child(row)
	var bubble := PanelContainer.new()
	bubble.add_theme_stylebox_override("panel", Kit.box(Color(App.accent, 0.18), 14, Color(App.accent, 0.35), 1, 10, 10))
	bubble.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var icon := icon_for(title)
	if icon == "sparkles":
		icon = icon_for(body)
	bubble.add_child(Kit.icon_rect(icon, 20, App.accent.lightened(0.55)))
	row.add_child(bubble)
	var col := Kit.vbox(6)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	if title != "":
		var head := Kit.label(title, 18, 800, Color.WHITE, true)
		head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(head)
	if body.strip_edges() != "":
		var text := RichTextLabel.new()
		text.bbcode_enabled = true
		text.fit_content = true
		text.scroll_active = false
		text.selection_enabled = true
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.add_theme_color_override("default_color", Color(App.TEXT, 0.82))
		text.text = Markdown.to_bbcode(body, App.accent.lightened(0.25))
		text.meta_clicked.connect(func(meta: Variant) -> void: OS.shell_open(str(meta)))
		col.add_child(text)
	return card
