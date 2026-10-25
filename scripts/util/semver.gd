class_name Semver
## Tiny version helpers. Accepts "1.2.3", "v1.2.3" and "1.2.3-dev" style strings.


static func parse(version: String) -> PackedInt32Array:
	var clean := version.strip_edges().trim_prefix("v").trim_prefix("V")
	var dash := clean.find("-")
	if dash >= 0:
		clean = clean.substr(0, dash)
	var plus := clean.find("+")
	if plus >= 0:
		clean = clean.substr(0, plus)
	var parts := PackedInt32Array()
	for piece in clean.split("."):
		parts.append(int(piece) if piece.is_valid_int() else 0)
	while parts.size() < 3:
		parts.append(0)
	return parts


## Returns -1 when a < b, 0 when equal, 1 when a > b.
static func compare(a: String, b: String) -> int:
	var pa := parse(a)
	var pb := parse(b)
	var n := maxi(pa.size(), pb.size())
	for i in n:
		var x := pa[i] if i < pa.size() else 0
		var y := pb[i] if i < pb.size() else 0
		if x != y:
			return -1 if x < y else 1
	return 0


static func is_newer(candidate: String, current: String) -> bool:
	return compare(candidate, current) > 0
