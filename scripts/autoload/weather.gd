extends Node
## Local weather for the taskbar. Finds roughly where you are from your IP
## address and asks Open-Meteo for the forecast: both free, keyless, nothing to
## set up. Cached on disk, so the taskbar shows the weather straight away and
## keeps showing a sensible forecast while you're offline.

signal changed

const CACHE := "user://weather.json"
const REFRESH := 30 * 60
const RETRY := 5 * 60
const LOCATION_TTL := 12 * 3600
## Countries that think in Fahrenheit.
const FAHRENHEIT := ["US", "LR", "MM", "BS", "BZ", "KY", "PW", "FM", "MH"]

const _LOCATE := [
	"https://get.geojs.io/v1/ip/geo.json",
	"https://ipapi.co/json/",
	"http://ip-api.com/json/?fields=status,city,lat,lon,countryCode",
]
const _FORECAST := "https://api.open-meteo.com/v1/forecast?latitude=%.3f&longitude=%.3f" \
	+ "&current=temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,is_day,wind_speed_10m" \
	+ "&hourly=temperature_2m,weather_code,is_day,precipitation_probability" \
	+ "&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,sunrise,sunset" \
	+ "&timezone=auto&forecast_days=7"

## Open-Meteo's answer, as last fetched.
var data := {}
## {lat, lon, city, country, at}
var place := {}
## When `data` was fetched (unix), 0 if never.
var updated := 0
## True when the last attempt to refresh failed (offline, or a service down).
var offline := false
var busy := false
var _last_try := 0


func _ready() -> void:
	_load()
	if App.smoke_test or App.screenshot_dir != "":
		return
	var t := Timer.new()
	t.wait_time = 60.0
	t.autostart = true
	t.timeout.connect(_check)
	add_child(t)
	_check.call_deferred()


func _now() -> int:
	return int(Time.get_unix_time_from_system())


func _check() -> void:
	var now := _now()
	var due := now - updated >= REFRESH
	if offline:
		due = now - _last_try >= RETRY
	if due and not busy:
		refresh()


func refresh() -> void:
	if busy:
		return
	busy = true
	_last_try = _now()
	changed.emit()
	if place.is_empty() or _now() - int(place.get("at", 0)) > LOCATION_TTL:
		var p := await _locate()
		if not p.is_empty():
			place = p
	var ok := false
	if not place.is_empty():
		var d: Variant = await _http_json(_FORECAST % [float(place["lat"]), float(place["lon"])])
		if d is Dictionary and d.get("current") is Dictionary and d.get("hourly") is Dictionary and d.get("daily") is Dictionary:
			data = d
			updated = _now()
			ok = true
			_save()
	offline = not ok
	busy = false
	changed.emit()


func _locate() -> Dictionary:
	for url in _LOCATE:
		var j: Variant = await _http_json(url)
		if not (j is Dictionary):
			continue
		var lat: Variant = j.get("latitude", j.get("lat"))
		var lon: Variant = j.get("longitude", j.get("lon"))
		if lat == null or lon == null or str(lat) == "" or str(lon) == "":
			continue
		return {
			"lat": float(str(lat)), "lon": float(str(lon)),
			"city": str(j.get("city", "")),
			"country": str(j.get("country_code", j.get("countryCode", ""))).to_upper(),
			"at": _now(),
		}
	return {}


func _http_json(url: String) -> Variant:
	var http := HTTPRequest.new()
	http.timeout = 12.0
	http.use_threads = true
	add_child(http)
	var out: Variant = null
	if http.request(url, ["User-Agent: %s/%s" % [App.USER_AGENT, App.version], "Accept: application/json"]) == OK:
		var res: Array = await http.request_completed
		if int(res[0]) == HTTPRequest.RESULT_SUCCESS and int(res[1]) == 200:
			out = JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8())
	http.queue_free()
	return out


func _load() -> void:
	if App.smoke_test or not FileAccess.file_exists(CACHE):
		return
	var j: Variant = JSON.parse_string(FileAccess.get_file_as_string(CACHE))
	if j is Dictionary:
		data = j.get("data", {}) if j.get("data") is Dictionary else {}
		place = j.get("place", {}) if j.get("place") is Dictionary else {}
		updated = int(j.get("updated", 0))


func _save() -> void:
	var f := FileAccess.open(CACHE, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"data": data, "place": place, "updated": updated}))


## Screenshots and tests: show this forecast instead of fetching one.
func set_mock(p: Dictionary, d: Dictionary) -> void:
	place = p
	data = d
	updated = _now()
	offline = false
	changed.emit()


# --- Reading the forecast -------------------------------------------------------------

func fahrenheit() -> bool:
	match str(Settings.get_value("weather_unit")):
		"c":
			return false
		"f":
			return true
	return str(place.get("country", "")) in FAHRENHEIT


## "18°" in the unit the user reads.
func temp(celsius: float) -> String:
	var v := celsius * 9.0 / 5.0 + 32.0 if fahrenheit() else celsius
	return "%d°" % roundi(v)


func wind(kmh: float) -> String:
	return "%d mph" % roundi(kmh / 1.609) if fahrenheit() else "%d km/h" % roundi(kmh)


## The forecast's local clock right now, as "YYYY-MM-DDTHH:MM:SS".
func local_now() -> String:
	return Time.get_datetime_string_from_unix_time(_now() + int(data.get("utc_offset_seconds", 0)))


func _hour_index() -> int:
	var times: Array = data.get("hourly", {}).get("time", [])
	var key := local_now().substr(0, 13)
	for i in times.size():
		if str(times[i]).substr(0, 13) == key:
			return i
	return -1


## What it's like now: {temp, feels, humidity, wind, code, day}, or {} when
## there's nothing current enough to show. Old data falls back to the hourly
## forecast for this hour, so being offline for a while still looks right.
func current() -> Dictionary:
	if data.is_empty():
		return {}
	var c: Dictionary = data.get("current", {})
	if _now() - updated < 75 * 60 and c.has("temperature_2m"):
		return {
			"temp": float(c["temperature_2m"]), "feels": float(c.get("apparent_temperature", c["temperature_2m"])),
			"humidity": int(c.get("relative_humidity_2m", -1)), "wind": float(c.get("wind_speed_10m", -1.0)),
			"code": int(c.get("weather_code", 0)), "day": int(c.get("is_day", 1)) == 1,
		}
	var i := _hour_index()
	if i < 0:
		return {}
	var h: Dictionary = data["hourly"]
	return {
		"temp": float(h["temperature_2m"][i]), "feels": NAN, "humidity": -1, "wind": -1.0,
		"code": int(h["weather_code"][i]), "day": int(h["is_day"][i]) == 1,
	}


## The next `count` hours, `step` apart, starting with this one:
## [{time, temp, code, day, rain}].
func hours(count: int = 7, step: int = 2) -> Array:
	var out := []
	var i := _hour_index()
	if i < 0:
		return out
	var h: Dictionary = data["hourly"]
	var probs: Array = h.get("precipitation_probability", [])
	while out.size() < count and i < (h["time"] as Array).size():
		out.append({
			"time": str(h["time"][i]), "temp": float(h["temperature_2m"][i]),
			"code": int(h["weather_code"][i]), "day": int(h["is_day"][i]) == 1,
			"rain": int(probs[i]) if i < probs.size() and probs[i] != null else 0,
		})
		i += step
	return out


## Today and the days after: [{date, max, min, code, rain}].
func days() -> Array:
	var out := []
	var d: Dictionary = data.get("daily", {})
	var today := local_now().substr(0, 10)
	var times: Array = d.get("time", [])
	for i in times.size():
		if str(times[i]) < today:
			continue
		var probs: Array = d.get("precipitation_probability_max", [])
		out.append({
			"date": str(times[i]), "max": float(d["temperature_2m_max"][i]), "min": float(d["temperature_2m_min"][i]),
			"code": int(d["weather_code"][i]), "rain": int(probs[i]) if i < probs.size() and probs[i] != null else 0,
		})
	return out


func city() -> String:
	return str(place.get("city", ""))


## WMO weather code → one of WeatherIcons' kinds.
static func kind_for(code: int) -> String:
	if code <= 0:
		return "clear"
	if code <= 2:
		return "partly"
	if code == 3:
		return "cloudy"
	if code in [45, 48]:
		return "fog"
	if code >= 51 and code <= 57:
		return "drizzle"
	if (code >= 61 and code <= 67) or (code >= 80 and code <= 82):
		return "rain"
	if (code >= 71 and code <= 77) or code in [85, 86]:
		return "snow"
	if code >= 95:
		return "storm"
	return "cloudy"


static func describe(code: int) -> String:
	match code:
		0: return "Clear"
		1: return "Mostly clear"
		2: return "Partly cloudy"
		3: return "Cloudy"
		45, 48: return "Fog"
		51, 53: return "Drizzle"
		55: return "Heavy drizzle"
		56, 57: return "Freezing drizzle"
		61: return "Light rain"
		63: return "Rain"
		65: return "Heavy rain"
		66, 67: return "Freezing rain"
		71: return "Light snow"
		73: return "Snow"
		75: return "Heavy snow"
		77: return "Snow grains"
		80: return "Showers"
		81, 82: return "Heavy showers"
		85, 86: return "Snow showers"
		95: return "Thunderstorm"
		96, 99: return "Thunderstorm with hail"
	return "Cloudy"
