class_name QuickAnswers
## Things Start's search can do besides finding apps: work out sums, open web
## addresses and folders you type, jump to Windows settings pages and run
## system or Oazy commands ("lock", "wifi", "check for updates").
##
## Rows use the same shape as Catalog items, with refs of their own:
##   calc:<result>  copy the result      url:<address>   open in the browser
##   path:<path>    open the folder      cmd:<id>        a command below

## [id, name, extra search words, glyph, what runs]. A "what runs" starting
## with ms-settings: or shell: is opened by Windows; the rest are handled in run().
const COMMANDS := [
	["wifi", "Wi-Fi settings", "wifi wireless network internet", "wifi", "ms-settings:network-wifi"],
	["bluetooth", "Bluetooth & devices", "bluetooth devices headphones controller pair", "bluetooth", "ms-settings:bluetooth"],
	["display", "Display settings", "display screen resolution monitor brightness hdr scale", "monitor", "ms-settings:display"],
	["sound", "Sound settings", "sound audio speakers output microphone", "volume", "ms-settings:sound"],
	["mixer", "Volume mixer", "volume mixer app volume", "volume", "ms-settings:apps-volume"],
	["nightlight", "Night light", "night light blue light warm", "moon", "ms-settings:nightlight"],
	["power", "Power & battery", "power battery sleep energy saver", "battery", "ms-settings:powersleep"],
	["update", "Windows Update", "windows update updates patch", "refresh", "ms-settings:windowsupdate"],
	["apps", "Installed apps", "installed apps uninstall programs remove", "apps", "ms-settings:appsfeatures"],
	["defaults", "Default apps", "default apps browser", "apps", "ms-settings:defaultapps"],
	["storage", "Storage", "storage disk space cleanup drive", "folder", "ms-settings:storagesense"],
	["mouse", "Mouse settings", "mouse pointer cursor speed", "settings", "ms-settings:mousetouchpad"],
	["notifications", "Notifications", "notifications focus do not disturb", "info", "ms-settings:notifications"],
	["windows", "Windows Settings", "windows settings pc settings control", "settings", "ms-settings:"],
	["taskmgr", "Windows Task Manager", "windows task manager taskmgr services performance", "cpu", "taskmgr"],
	["recycle", "Recycle Bin", "recycle bin trash deleted", "trash", "shell:RecycleBinFolder"],
	["lock", "Lock", "lock pc", "lock", "lock"],
	["sleep", "Sleep", "sleep pc suspend", "moon", "sleep"],
	["restart", "Restart", "restart reboot pc", "restart", "restart"],
	["shutdown", "Shut down", "shut down shutdown power off turn off", "power", "shutdown"],
	["oazy_updates", "Check for Oazy updates", "check for updates oazy update", "download", "updates"],
	["oazy_notes", "Oazy patch notes", "patch notes whats new changelog oazy", "sparkles", "notes"],
	["oazy_scan", "Scan this PC for games", "scan games steam epic gog import", "sparkles", "scan"],
	["oazy_find_apps", "Find apps for your Library", "find apps library add installed programs", "apps", "find_apps"],
	["oazy_add", "Add a game or app", "add game app new", "plus", "add"],
	["oazy_clean", "Clean up Windows", "clean cleaner cleanup bloatware bloat debloat junk temp files startup apps privacy telemetry ads speed up faster optimise optimize tune", "wand", "cleaner"],
	["oazy_keys", "Keyboard shortcuts", "keyboard shortcuts keys hotkeys help", "keyboard", "shortcuts"],
]

const _CALC_WORDS := ["sqrt", "pow", "abs", "round", "floor", "ceil", "sin", "cos", "tan", "log", "exp", "pi"]

static var _calc_re: RegEx
static var _num_re: RegEx
static var _url_re: RegEx


## Rows that go above app results (a sum, an address, a path).
static func top(text: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var q := text.strip_edges()
	var sum := calc(q)
	if sum != "":
		out.append({"ref": "calc:" + sum, "name": "= " + sum, "kind": "oazy", "glyph": "calculator", "sub": "Copy result"})
	var path := as_path(q)
	if path != "":
		out.append({"ref": "path:" + path, "name": path, "kind": "oazy", "glyph": "folder", "sub": "Open"})
	var url := as_url(q)
	if url != "":
		out.append({"ref": "url:" + url, "name": url.trim_prefix("https://"), "kind": "oazy", "glyph": "external", "sub": "Open in browser"})
	return out


## Matching commands, best first, each with a "score" like Catalog.match_score.
static func commands(text: String, limit: int = 3) -> Array[Dictionary]:
	var needle := text.strip_edges().to_lower()
	var scored: Array = []
	if needle.length() < 2:
		return []
	for c in COMMANDS:
		var s := maxi(Catalog.match_score(str(c[1]), needle), _words_score(str(c[2]), needle))
		if s > 0:
			scored.append([s, c])
	scored.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	var out: Array[Dictionary] = []
	for s in scored.slice(0, limit):
		var c: Array = s[1]
		var sub := "Windows" if str(c[4]).begins_with("ms-settings:") else ("Oazy" if str(c[0]).begins_with("oazy_") else "System")
		out.append({"ref": "cmd:" + str(c[0]), "name": c[1], "kind": "oazy", "glyph": c[3], "sub": sub, "score": s[0]})
	return out


static func _words_score(words: String, needle: String) -> int:
	if (" " + words + " ").contains(" " + needle + " "):
		return 90
	if words.begins_with(needle):
		return 70
	for w in words.split(" ", false):
		if w.begins_with(needle):
			return 55
	if needle.length() >= 4 and words.contains(needle):
		return 40
	return 0


static func owns(ref: String) -> bool:
	return ref.begins_with("calc:") or ref.begins_with("url:") or ref.begins_with("path:") or ref.begins_with("cmd:")


## Does what a quick row says. `main` is the shell root (for dialogs).
static func run(ref: String, main: Node) -> void:
	if ref.begins_with("calc:"):
		DisplayServer.clipboard_set(ref.substr(5))
		App.toast("Copied %s" % ref.substr(5), &"success")
	elif ref.begins_with("url:"):
		var url := ref.substr(4)
		if Browser.handles_links() and (url.begins_with("http://") or url.begins_with("https://")):
			Browser.open(url)
		else:
			OS.shell_open(url)
	elif ref.begins_with("path:"):
		var p := ref.substr(5)
		if DirAccess.dir_exists_absolute(p):
			Files.open_folder(p)
		elif App.is_windows():
			OS.create_process("explorer.exe", [p.replace("/", "\\")])
		else:
			OS.shell_open(p)
	elif ref.begins_with("cmd:"):
		var id := ref.substr(4)
		for c in COMMANDS:
			if c[0] == id:
				_run_command(str(c[4]), main)


static func _run_command(what: String, main: Node) -> void:
	if what.begins_with("ms-settings:") or what.begins_with("shell:"):
		if not App.is_windows():
			App.toast("That opens on Windows")
		elif what.begins_with("shell:"):
			OS.create_process("explorer.exe", [what])
		else:
			OS.shell_open(what)
		return
	match what:
		"taskmgr":
			if App.is_windows():
				OS.create_process("taskmgr.exe", [])
		"lock":
			Host.lock_pc()
		"sleep":
			Host.sleep_pc()
		"restart", "shutdown":
			main.confirm_power(what)
		"updates":
			main.show_update()
		"notes":
			main.show_patch_notes()
		"scan":
			main.scan_stores()
		"find_apps":
			main.find_apps()
		"add":
			main.open_add({})
		"shortcuts":
			main.show_shortcuts()
		"cleaner":
			main.open_app(&"cleaner")


# --- Sums --------------------------------------------------------------------------------

## The answer to a typed sum ("12*4", "2^10", "sqrt(2)", "19.99 × 3"), or ""
## when the text isn't one.
static func calc(text: String) -> String:
	var q := text.strip_edges().to_lower().replace("×", "*").replace("÷", "/").replace(" x ", " * ")
	# A comma is a decimal point ("2,5 * 4") unless it separates arguments.
	if not q.contains("("):
		q = q.replace(",", ".")
	q = q.trim_prefix("=").strip_edges()
	if q.length() < 3 or q.length() > 120:
		return ""
	if _calc_re == null:
		_calc_re = RegEx.create_from_string("^[0-9a-z+\\-*/^()., ]+$")
		_num_re = RegEx.create_from_string("(?<![a-z0-9.])(\\d+)(?![\\d.])")
	if _calc_re.search(q) == null:
		return ""
	# Only known function names may appear, and there must be an operator or a call.
	var letters := q
	for w in _CALC_WORDS:
		letters = letters.replace(w, "")
	for ch in letters:
		if ch >= "a" and ch <= "z":
			return ""
	var has_digit := false
	for ch in q:
		if ch >= "0" and ch <= "9":
			has_digit = true
			break
	if not has_digit and not q.contains("pi"):
		return ""
	var has_op := false
	for op in ["+", "-", "*", "/", "^", "("]:
		if q.substr(1).contains(op):
			has_op = true
	if not has_op:
		return ""
	# Whole numbers become floats so 7/2 is 3.5, not 3.
	var expr_text := _num_re.sub(q, "$1.0", true).replace("^", "**").replace("pi", "PI")
	var e := Expression.new()
	if e.parse(expr_text) != OK:
		return ""
	var v: Variant = e.execute([], null, false, true)
	if e.has_execute_failed() or not (v is float or v is int):
		return ""
	var f := float(v)
	if is_nan(f) or is_inf(f):
		return ""
	return format_number(f)


static func format_number(f: float) -> String:
	if absf(f - roundf(f)) < 1e-9 and absf(f) < 1e15:
		return str(int(roundf(f)))
	var s := "%.10f" % f
	s = s.rstrip("0").rstrip(".")
	return s


# --- Addresses and paths -------------------------------------------------------------------

## "github.com", "https://x.dev/a" or "localhost:3000" as a URL, or "".
static func as_url(text: String) -> String:
	var q := text.strip_edges()
	if q.contains(" ") or q.length() < 4:
		return ""
	if q.begins_with("http://") or q.begins_with("https://"):
		return q
	if _url_re == null:
		_url_re = RegEx.create_from_string("^(localhost(:\\d+)?|([a-z0-9-]+\\.)+[a-z]{2,24}(:\\d+)?)(/\\S*)?$")
	if _url_re.search(q.to_lower()) == null:
		return ""
	# "1.5" or "file.exe" aren't addresses.
	var host := q.to_lower().split("/")[0].split(":")[0]
	var tld := host.get_extension()
	if tld in ["exe", "lnk", "txt", "png", "jpg", "zip", "dll", "bat", "json", "md"]:
		return ""
	return ("http://" if host == "localhost" else "https://") + q


## A typed folder or file path ("C:\Games", "~/Downloads") that exists, or "".
static func as_path(text: String) -> String:
	var q := text.strip_edges()
	if q.begins_with("~"):
		q = OS.get_environment("USERPROFILE" if App.is_windows() else "HOME") + q.substr(1)
	var is_drive := q.length() >= 2 and q[1] == ":" and ((q[0] >= "a" and q[0] <= "z") or (q[0] >= "A" and q[0] <= "Z"))
	if not (is_drive or q.begins_with("/") or q.begins_with("\\\\")):
		return ""
	var norm := q.replace("\\", "/")
	if DirAccess.dir_exists_absolute(norm) or FileAccess.file_exists(norm):
		return q
	return ""
