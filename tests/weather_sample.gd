extends RefCounted
## A made-up but realistic Open-Meteo answer around the current hour, for the
## smoke test and screenshots (no network in CI).


static func place() -> Dictionary:
	return {"lat": 38.72, "lon": -9.14, "city": "Lisbon", "country": "PT", "at": int(Time.get_unix_time_from_system())}


static func forecast() -> Dictionary:
	var now := int(Time.get_unix_time_from_system())
	var hour0 := now - now % 3600 - 6 * 3600
	var hourly := {"time": [], "temperature_2m": [], "weather_code": [], "is_day": [], "precipitation_probability": []}
	var codes := [1, 1, 2, 2, 3, 3, 61, 63, 61, 3, 2, 1, 0, 0]
	for i in 7 * 24:
		var t := hour0 + i * 3600
		var h := int(Time.get_datetime_dict_from_unix_time(t)["hour"])
		hourly["time"].append(Time.get_datetime_string_from_unix_time(t).substr(0, 16))
		hourly["temperature_2m"].append(16.0 + 5.0 * sin((h - 9) / 24.0 * TAU) + (i / 24) * 0.4)
		hourly["weather_code"].append(codes[(i / 2) % codes.size()])
		hourly["is_day"].append(1 if h >= 7 and h < 19 else 0)
		hourly["precipitation_probability"].append(70 if codes[(i / 2) % codes.size()] >= 61 else 5)
	var daily := {"time": [], "weather_code": [], "temperature_2m_max": [], "temperature_2m_min": [], "precipitation_probability_max": []}
	var day_codes := [2, 61, 3, 0, 1, 95, 2]
	var day0 := now - now % 86400
	for d in 7:
		daily["time"].append(Time.get_date_string_from_unix_time(day0 + d * 86400))
		daily["weather_code"].append(day_codes[d])
		daily["temperature_2m_max"].append([21.0, 18.5, 19.0, 23.5, 24.0, 17.0, 20.0][d])
		daily["temperature_2m_min"].append([13.0, 12.5, 11.0, 12.0, 14.5, 13.0, 12.0][d])
		daily["precipitation_probability_max"].append([10, 80, 30, 0, 5, 90, 15][d])
	return {
		"utc_offset_seconds": 0,
		"current": {"temperature_2m": 18.4, "apparent_temperature": 17.6, "relative_humidity_2m": 64, "weather_code": 2, "is_day": 1, "wind_speed_10m": 14.2},
		"hourly": hourly,
		"daily": daily,
	}
