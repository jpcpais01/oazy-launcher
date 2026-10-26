class_name ChatMarkdown
## The Markdown Claude writes, as pieces a chat can draw: runs of text as
## RichTextLabel BBCode, and code blocks on their own. Paragraphs, headings,
## lists, quotes, tables, links, bold, italics and inline code. A code block
## still being streamed (no closing fence yet) counts as code already.


## [{"t": "text", "bb": String}, {"t": "code", "lang": String, "code": String}, ...]
static func blocks(md: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var prose := PackedStringArray()
	var lines := md.replace("\r\n", "\n").split("\n")
	var i := 0
	while i < lines.size():
		var line := lines[i]
		var fence := line.strip_edges()
		if fence.begins_with("```") or fence.begins_with("~~~"):
			if not prose.is_empty():
				out.append({"t": "text", "bb": _prose(prose)})
				prose.clear()
			var mark := fence.substr(0, 3)
			var code := PackedStringArray()
			i += 1
			while i < lines.size() and not lines[i].strip_edges().begins_with(mark):
				code.append(lines[i])
				i += 1
			out.append({"t": "code", "lang": fence.substr(3).strip_edges(), "code": "\n".join(code)})
			i += 1
			continue
		prose.append(line)
		i += 1
	if not prose.is_empty():
		var bb := _prose(prose)
		if bb != "":
			out.append({"t": "text", "bb": bb})
	return out


static func _prose(lines: PackedStringArray) -> String:
	var out := PackedStringArray()
	var para := PackedStringArray()
	var list := PackedStringArray()
	var list_kind := ""
	var table: Array[PackedStringArray] = []
	var flush_para := func() -> void:
		if not para.is_empty():
			out.append(inline(" ".join(para)))
			para.clear()
	var flush_list := func() -> void:
		if not list.is_empty():
			var tag := "ol type=1" if list_kind == "ol" else "ul bullet=•"
			out.append("[%s]%s[/%s]" % [tag, "\n".join(list), list_kind])
			list.clear()
	var flush_table := func() -> void:
		if not table.is_empty():
			out.append(_table(table))
			table.clear()
	var ol := RegEx.create_from_string("^\\s*\\d+[.)]\\s+(.*)$")
	for raw in lines:
		var line := raw.rstrip(" \t")
		var s := line.strip_edges()
		if s.begins_with("|"):
			flush_para.call()
			flush_list.call()
			var cells := PackedStringArray()
			for c in s.trim_prefix("|").trim_suffix("|").split("|"):
				cells.append(c.strip_edges())
			var rule := true
			for c in cells:
				if c.replace("-", "").replace(":", "").strip_edges() != "":
					rule = false
			if not rule:
				table.append(cells)
			continue
		flush_table.call()
		if s == "":
			flush_para.call()
			flush_list.call()
			continue
		var bullet := s.begins_with("- ") or s.begins_with("* ") or s.begins_with("+ ")
		var num := ol.search(line)
		if bullet or num:
			flush_para.call()
			var kind := "ul" if bullet else "ol"
			if kind != list_kind:
				flush_list.call()
			list_kind = kind
			var depth := (line.length() - line.lstrip(" \t").length()) / 2
			var text := s.substr(2) if bullet else num.get_string(1)
			list.append(("    ".repeat(depth) + ("◦ " if depth > 0 and bullet else "")) + inline(text))
			continue
		if not list.is_empty() and (line.begins_with("  ") or line.begins_with("\t")):
			# A list item's text running on to the next line.
			list[list.size() - 1] += " " + inline(s)
			continue
		flush_list.call()
		if s.begins_with("#"):
			flush_para.call()
			var level := s.length() - s.lstrip("#").length()
			var size := 18 if level <= 1 else (17 if level == 2 else 16)
			out.append("[font_size=%d][b]%s[/b][/font_size]" % [size, inline(s.lstrip("#").strip_edges())])
		elif s.begins_with(">"):
			flush_para.call()
			out.append("[color=#ffffff99][i]%s[/i][/color]" % inline(s.lstrip(">").strip_edges()))
		elif s == "---" or s == "***" or s == "___":
			flush_para.call()
			out.append("[color=#ffffff1f]────────────────[/color]")
		else:
			para.append(s)
	flush_para.call()
	flush_list.call()
	flush_table.call()
	return "\n".join(out)


static func _table(rows: Array[PackedStringArray]) -> String:
	var cols := 0
	for r in rows:
		cols = maxi(cols, r.size())
	var bb := "[table=%d]" % cols
	for ri in rows.size():
		for ci in cols:
			var c := inline(rows[ri][ci]) if ci < rows[ri].size() else ""
			if ri == 0:
				c = "[b]%s[/b]" % c
			bb += "[cell padding=0,3,18,3]%s[/cell]" % c
	return bb + "[/table]"


## Bold, italics, links and inline code; any other brackets come out as text.
static func inline(text: String) -> String:
	var s := Markdown.inline(text)
	return s.replace("[code]", "[bgcolor=#ffffff0f][color=#dfe8f5][code]").replace("[/code]", "[/code][/color][/bgcolor]")
