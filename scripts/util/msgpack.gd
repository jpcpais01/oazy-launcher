class_name MsgPack
## A small MessagePack writer, byte-for-byte what Python's msgpack.packb makes
## (Hyperliquid hashes actions in this form before they're signed). Maps keep
## their insertion order, so build them in the order the exchange expects.


static func pack(v: Variant) -> PackedByteArray:
	var out := PackedByteArray()
	_put(out, v)
	return out


static func _put(out: PackedByteArray, v: Variant) -> void:
	match typeof(v):
		TYPE_NIL:
			out.append(0xc0)
		TYPE_BOOL:
			out.append(0xc3 if v else 0xc2)
		TYPE_INT:
			_int(out, v)
		TYPE_FLOAT:
			out.append(0xcb)
			var b := PackedByteArray()
			b.resize(8)
			b.encode_double(0, v)
			b.reverse()
			out.append_array(b)
		TYPE_STRING, TYPE_STRING_NAME:
			var s := str(v).to_utf8_buffer()
			var n := s.size()
			if n < 32:
				out.append(0xa0 | n)
			elif n < 256:
				out.append(0xd9)
				out.append(n)
			elif n < 65536:
				out.append(0xda)
				_be(out, n, 2)
			else:
				out.append(0xdb)
				_be(out, n, 4)
			out.append_array(s)
		TYPE_ARRAY:
			var a: Array = v
			_head(out, a.size(), 0x90, 0xdc, 0xdd)
			for x in a:
				_put(out, x)
		TYPE_DICTIONARY:
			var d: Dictionary = v
			_head(out, d.size(), 0x80, 0xde, 0xdf)
			for k in d:
				_put(out, k)
				_put(out, d[k])
		_:
			push_error("MsgPack: can't pack %s" % type_string(typeof(v)))


static func _head(out: PackedByteArray, n: int, fix: int, b16: int, b32: int) -> void:
	if n < 16:
		out.append(fix | n)
	elif n < 65536:
		out.append(b16)
		_be(out, n, 2)
	else:
		out.append(b32)
		_be(out, n, 4)


static func _int(out: PackedByteArray, n: int) -> void:
	if n >= 0:
		if n < 128:
			out.append(n)
		elif n < 256:
			out.append(0xcc)
			out.append(n)
		elif n < 65536:
			out.append(0xcd)
			_be(out, n, 2)
		elif n < 4294967296:
			out.append(0xce)
			_be(out, n, 4)
		else:
			out.append(0xcf)
			_be(out, n, 8)
	elif n >= -32:
		out.append(0x100 + n)
	elif n >= -128:
		out.append(0xd0)
		_be(out, n & 0xff, 1)
	elif n >= -32768:
		out.append(0xd1)
		_be(out, n & 0xffff, 2)
	elif n >= -2147483648:
		out.append(0xd2)
		_be(out, n & 0xffffffff, 4)
	else:
		out.append(0xd3)
		_be(out, n, 8)


static func _be(out: PackedByteArray, n: int, bytes: int) -> void:
	for i in range(bytes - 1, -1, -1):
		out.append((n >> (8 * i)) & 0xff)
