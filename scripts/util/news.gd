class_name News
extends Node
## Headlines for the desktop from Google News' public RSS feeds (keyless),
## with the BBC as a fallback. Fetched only while the section is on screen,
## at most every quarter of an hour per topic, and cached on disk.

signal changed

const CACHE := "user://news.json"
const REFRESH := 15 * 60
const RETRY := 2 * 60
const MAX_ITEMS := 12
const GOOGLE := "https://news.google.com/rss%s"
const EDITION := "hl=en-US&gl=US&ceid=US:en"
## id -> [label, Google News path, BBC fallback feed]
const TOPICS := {
	"top": ["Top", "", "https://feeds.bbci.co.uk/news/rss.xml"],
	"world": ["World", "/headlines/section/topic/WORLD", "https://feeds.bbci.co.uk/news/world/rss.xml"],
	"business": ["Business", "/headlines/section/topic/BUSINESS", "https://feeds.bbci.co.uk/news/business/rss.xml"],
	"tech": ["Tech", "/headlines/section/topic/TECHNOLOGY", "https://feeds.bbci.co.uk/news/technology/rss.xml"],
	"games": ["Games", "/search?q=video%20games%20when:2d", ""],
	"science": ["Science", "/headlines/section/topic/SCIENCE", "https://feeds.bbci.co.uk/news/science_and_environment/rss.xml"],
}
const MONTHS := ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]

## topic -> {"at": unix, "items": [{title, source, link, at}]}
var feeds := {}
var busy := false
var _last_try := {}


func _ready() -> void:
	_load()


static func topic() -> String:
	var t := str(Settings.get_value("news_topic"))
	return t if TOPICS.has(t) else "top"


func items(t: String = "") -> Array:
	var f: Variant = feeds.get(t if t != "" else topic(), {})
	return f.get("items", []) if f is Dictionary else []


func _now() -> int:
	return int(Time.get_unix_time_from_system())


func refresh(force: bool = false) -> void:
	if busy or App.smoke_test or (App.screenshot_dir != "" and not force):
		return
	var t := topic()
	var now := _now()
	var f: Dictionary = feeds.get(t, {})
	if not force and (now - int(f.get("at", 0)) < REFRESH or now - int(_last_try.get(t, 0)) < RETRY):
		return
	busy = true
	_last_try[t] = now
	changed.emit()
	var spec: Array = TOPICS[t]
	var path := str(spec[1])
	var list := await _fetch(GOOGLE % path + ("&" if path.contains("?") else "?") + EDITION)
	if list.is_empty() and str(spec[2]) != "":
		list = await _fetch(str(spec[2]))
	busy = false
	if not list.is_empty():
		feeds[t] = {"at": now, "items": list}
		_save()
	changed.emit()


func _fetch(url: String) -> Array:
	var http := HTTPRequest.new()
	http.timeout = 12.0
	http.use_threads = true
	add_child(http)
	var out := []
	if http.request(url, ["User-Agent: %s/%s" % [App.USER_AGENT, App.version], "Accept: application/rss+xml, application/xml"]) == OK:
		var res: Array = await http.request_completed
		if int(res[0]) == HTTPRequest.RESULT_SUCCESS and int(res[1]) == 200:
			out = parse_rss(res[3])
	http.queue_free()
	return out


## RSS 2.0 -> [{title, source, link, at}], newest first. Google News titles
## end in " - Source"; that part becomes the source.
static func parse_rss(bytes: PackedByteArray) -> Array:
	var out := []
	if bytes.is_empty():
		return out
	var xml := XMLParser.new()
	if xml.open_buffer(bytes) != OK:
		return out
	var cur := {}
	var field := ""
	var in_item := false
	while xml.read() == OK:
		match xml.get_node_type():
			XMLParser.NODE_ELEMENT:
				var n := xml.get_node_name()
				if n == "item":
					in_item = true
					cur = {"title": "", "source": "", "link": "", "at": 0}
					field = ""
				elif in_item and n in ["title", "link", "pubDate", "source"]:
					field = n
					if xml.is_empty():
						field = ""
				else:
					field = ""
			XMLParser.NODE_TEXT, XMLParser.NODE_CDATA:
				if in_item and field != "":
					# CDATA keeps its text in the node's name.
					var text := xml.get_node_name() if xml.get_node_type() == XMLParser.NODE_CDATA else xml.get_node_data()
					if field == "pubDate":
						cur["at"] = parse_date(text.strip_edges())
					elif field == "title":
						cur["title"] = str(cur["title"]) + text
					elif field == "link":
						cur["link"] = str(cur["link"]) + text.strip_edges()
					else:
						cur["source"] = str(cur["source"]) + text.strip_edges()
			XMLParser.NODE_ELEMENT_END:
				var n := xml.get_node_name()
				if n == "item" and in_item:
					in_item = false
					var item := _tidy(cur)
					if not item.is_empty():
						out.append(item)
				field = ""
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["at"]) > int(b["at"]))
	return out.slice(0, MAX_ITEMS)


static func _tidy(it: Dictionary) -> Dictionary:
	var title := str(it["title"]).strip_edges().xml_unescape().replace("\n", " ")
	var source := str(it["source"]).xml_unescape()
	var cut := title.rfind(" - ")
	if cut > 20:
		var tail := title.substr(cut + 3).strip_edges()
		if source == "" or tail == source:
			source = tail
			title = title.substr(0, cut).strip_edges()
	if title == "" or str(it["link"]) == "":
		return {}
	return {"title": title, "source": source, "link": str(it["link"]), "at": int(it["at"])}


## "Sun, 26 Oct 2026 10:04:00 GMT" (or +0100) -> unix time, 0 if unreadable.
static func parse_date(s: String) -> int:
	var parts := s.replace(",", " ").split(" ", false)
	if parts.size() < 5:
		return 0
	var i := 1 if not parts[0].is_valid_int() else 0
	if parts.size() < i + 4:
		return 0
	var month := MONTHS.find(parts[i + 1].substr(0, 3).to_lower())
	var hms := parts[i + 3].split(":")
	if month < 0 or hms.size() < 2:
		return 0
	var d := {
		"year": int(parts[i + 2]), "month": month + 1, "day": int(parts[i]),
		"hour": int(hms[0]), "minute": int(hms[1]), "second": int(hms[2]) if hms.size() > 2 else 0,
	}
	var t := Time.get_unix_time_from_datetime_dict(d)
	if parts.size() > i + 4:
		var zone := parts[i + 4]
		if (zone.begins_with("+") or zone.begins_with("-")) and zone.length() == 5:
			var off := int(zone.substr(1, 2)) * 3600 + int(zone.substr(3, 2)) * 60
			t -= off if zone.begins_with("+") else -off
	return t


func _load() -> void:
	if App.smoke_test or not FileAccess.file_exists(CACHE):
		return
	var j: Variant = JSON.parse_string(FileAccess.get_file_as_string(CACHE))
	if j is Dictionary and j.get("feeds") is Dictionary:
		feeds = j["feeds"]


func _save() -> void:
	var f := FileAccess.open(CACHE, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"feeds": feeds}))


func set_mock(t: String, list: Array) -> void:
	feeds[t] = {"at": _now(), "items": list}
	changed.emit()
