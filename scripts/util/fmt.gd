class_name Fmt
## Human friendly formatting helpers.


static func playtime(seconds: int) -> String:
	if seconds < 60:
		return "Not played yet" if seconds <= 0 else "Less than a minute"
	var minutes := seconds / 60
	if minutes < 60:
		return "%d min played" % minutes
	var hours := minutes / 60
	var rem := minutes % 60
	if hours < 10 and rem > 0:
		return "%dh %dm played" % [hours, rem]
	return "%s hours played" % _thousands(hours)


static func ago(unix: int, now: int = -1) -> String:
	if unix <= 0:
		return "Never played"
	if now < 0:
		now = int(Time.get_unix_time_from_system())
	var d := maxi(0, now - unix)
	if d < 90:
		return "Just now"
	if d < 3600:
		return "%d minutes ago" % (d / 60)
	if d < 7200:
		return "An hour ago"
	if d < 86400:
		return "%d hours ago" % (d / 3600)
	if d < 172800:
		return "Yesterday"
	if d < 86400 * 14:
		return "%d days ago" % (d / 86400)
	if d < 86400 * 60:
		return "%d weeks ago" % (d / (86400 * 7))
	if d < 86400 * 365:
		return "%d months ago" % (d / (86400 * 30))
	return "Over a year ago"


static func bytes(n: float) -> String:
	if n < 1024.0:
		return "%d B" % int(n)
	if n < 1024.0 * 1024.0:
		return "%.0f KB" % (n / 1024.0)
	if n < 1024.0 * 1024.0 * 1024.0:
		return "%.1f MB" % (n / 1048576.0)
	return "%.2f GB" % (n / 1073741824.0)


static func duration(seconds: float) -> String:
	if seconds < 0.0 or is_inf(seconds) or is_nan(seconds):
		return "--"
	var s := int(ceil(seconds))
	if s < 60:
		return "%ds" % s
	return "%dm %02ds" % [s / 60, s % 60]


static func date(iso: String) -> String:
	# "2026-10-25T15:03:36Z" -> "Oct 25, 2026"
	if iso.length() < 10:
		return iso
	var months := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
	var y := iso.substr(0, 4)
	var m := clampi(int(iso.substr(5, 2)) - 1, 0, 11)
	var dd := int(iso.substr(8, 2))
	return "%s %d, %s" % [months[m], dd, y]


static func initials(name: String) -> String:
	var words := PackedStringArray()
	for w in name.replace("-", " ").replace("_", " ").replace(":", " ").split(" ", false):
		if w.length() > 0 and (w[0].to_upper() != w[0].to_lower() or w[0].is_valid_int()):
			words.append(w)
	if words.is_empty():
		return name.substr(0, 2).to_upper()
	if words.size() == 1:
		return words[0].substr(0, 2).to_upper() if words[0].length() > 1 else words[0].to_upper()
	return (words[0][0] + words[1][0]).to_upper()


## "witcher3_x64" -> "Witcher3 X64"
static func pretty_name(file_name: String) -> String:
	var base := file_name.get_file().get_basename()
	base = base.replace("_", " ").replace("-", " ").replace(".", " ")
	var words := PackedStringArray()
	for w in base.split(" ", false):
		words.append(w.substr(0, 1).to_upper() + w.substr(1))
	return " ".join(words) if not words.is_empty() else file_name


static func _thousands(n: int) -> String:
	var s := str(n)
	var out := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return out
