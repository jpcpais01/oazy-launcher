class_name Vdf
## Parser for Valve's KeyValues text format (libraryfolders.vdf, appmanifest_*.acf).


static func parse(text: String) -> Dictionary:
	var tokens := _tokenize(text)
	var index := [0]
	return _parse_object(tokens, index)


## Case-insensitive key lookup, Steam is not consistent about key casing.
static func get_key(dict: Dictionary, key: String, default: Variant = null) -> Variant:
	if dict.has(key):
		return dict[key]
	var lower := key.to_lower()
	for k in dict.keys():
		if str(k).to_lower() == lower:
			return dict[k]
	return default


static func _tokenize(text: String) -> PackedStringArray:
	var out := PackedStringArray()
	var i := 0
	var n := text.length()
	while i < n:
		var c := text[i]
		if c == "\"":
			var buf := ""
			i += 1
			while i < n and text[i] != "\"":
				if text[i] == "\\" and i + 1 < n:
					var nx := text[i + 1]
					match nx:
						"n": buf += "\n"
						"t": buf += "\t"
						"\\": buf += "\\"
						"\"": buf += "\""
						_: buf += nx
					i += 2
					continue
				buf += text[i]
				i += 1
			out.append("s:" + buf)
			i += 1
		elif c == "{" or c == "}":
			out.append(c)
			i += 1
		elif c == "/" and i + 1 < n and text[i + 1] == "/":
			while i < n and text[i] != "\n":
				i += 1
		elif c == " " or c == "\t" or c == "\n" or c == "\r":
			i += 1
		else:
			# Unquoted token.
			var buf2 := ""
			while i < n and not (text[i] in [" ", "\t", "\n", "\r", "{", "}", "\""]):
				buf2 += text[i]
				i += 1
			out.append("s:" + buf2)
	return out


static func _parse_object(tokens: PackedStringArray, index: Array) -> Dictionary:
	var result := {}
	while index[0] < tokens.size():
		var tok := tokens[index[0]]
		if tok == "}":
			index[0] += 1
			return result
		if not tok.begins_with("s:"):
			index[0] += 1
			continue
		var key := tok.substr(2)
		index[0] += 1
		if index[0] >= tokens.size():
			break
		var next := tokens[index[0]]
		if next == "{":
			index[0] += 1
			result[key] = _parse_object(tokens, index)
		elif next.begins_with("s:"):
			result[key] = next.substr(2)
			index[0] += 1
		else:
			index[0] += 1
	return result
