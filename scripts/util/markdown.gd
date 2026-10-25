class_name Markdown
## Converts the small subset of Markdown used in patch notes into RichTextLabel BBCode.


static func to_bbcode(md: String, accent: Color = Color("8f84ff")) -> String:
	var out := PackedStringArray()
	var accent_hex := accent.to_html(false)
	for raw in md.replace("\r\n", "\n").split("\n"):
		var line := raw.rstrip(" \t")
		var stripped := line.strip_edges()
		if stripped.is_empty():
			out.append("")
			continue
		if stripped.begins_with("<!--"):
			continue
		if stripped.begins_with("### "):
			out.append("[font_size=17][b]%s[/b][/font_size]" % inline(stripped.substr(4)))
		elif stripped.begins_with("## "):
			out.append("[font_size=21][b]%s[/b][/font_size]" % inline(stripped.substr(3)))
		elif stripped.begins_with("# "):
			out.append("[font_size=26][b]%s[/b][/font_size]" % inline(stripped.substr(2)))
		elif stripped.begins_with("- ") or stripped.begins_with("* ") or stripped.begins_with("+ "):
			var indent := line.length() - line.lstrip(" \t").length()
			var bullet := "•" if indent < 2 else "◦"
			var pad := "    ".repeat(indent / 2)
			out.append("%s[color=#%s]%s[/color]  %s" % [pad, accent_hex, bullet, inline(stripped.substr(2))])
		elif stripped == "---" or stripped == "***":
			out.append("[color=#ffffff22]────────────────────────[/color]")
		else:
			out.append(inline(stripped))
	# Collapse runs of blank lines.
	var text := "\n".join(out)
	while text.contains("\n\n\n"):
		text = text.replace("\n\n\n", "\n\n")
	return text.strip_edges()


static func inline(text: String) -> String:
	# Escape BBCode brackets that are not part of markdown links first.
	var s := text.replace("[", "[lb]").replace("]", "[rb]")
	# Links: [label](url) -> after escaping they look like [lb]label[rb](url)
	var link := RegEx.create_from_string("\\[lb\\](.+?)\\[rb\\]\\((https?://[^)\\s]+)\\)")
	s = link.sub(s, "[url=$2]$1[/url]", true)
	var bold := RegEx.create_from_string("\\*\\*(.+?)\\*\\*")
	s = bold.sub(s, "[b]$1[/b]", true)
	var italic := RegEx.create_from_string("(?<![\\w*])[*_](?!\\s)(.+?)(?<!\\s)[*_](?![\\w*])")
	s = italic.sub(s, "[i]$1[/i]", true)
	var code := RegEx.create_from_string("`([^`]+)`")
	s = code.sub(s, "[code]$1[/code]", true)
	return s
