extends Node
## Wi-Fi and wired networks, through the companion's Native Wifi calls (no
## admin needed): the link Oazy is on, the networks around, joining one (with
## its key), leaving, forgetting and the Wi-Fi radio. The tray icon reads
## `status`; the network flyout asks for the full list while it's open.

signal changed
## A join Oazy asked for finished. `reason` is Windows' own words when it failed.
signal joined(ok: bool, ssid: String, reason: String)

## The companion's last answer: {wifi, radio, hw_off, state, current?, ethernet, internet}.
var status := {}
## Networks around, strongest first: {id, ssid, signal, secure, auth, known, connected, connectable}.
var networks: Array = []
var scanning := false
## The id of the network being joined ("" when none).
var joining := ""

var _mocked := false
var _watching := false
var _poll: Timer
var _queued := false
var _fresh := false
var _join_serial := 0


func _ready() -> void:
	_poll = Timer.new()
	_poll.wait_time = 8.0
	_poll.autostart = true
	_poll.timeout.connect(refresh)
	add_child(_poll)
	Host.status_changed.connect(func(ok: bool) -> void:
		if ok:
			refresh()
	)
	Host.wifi_event.connect(_on_event)


## The flyout is open: keep the list fresh and look around now.
func watch(on: bool) -> void:
	_watching = on
	_poll.wait_time = 3.0 if on else 8.0
	_poll.start()
	if on:
		scan()
	refresh()


func refresh() -> void:
	_queued = false
	if _mocked or not Host.available:
		return
	Host.request(["wifi", "1" if _watching else "0"], _apply)


func _queue_refresh() -> void:
	if _queued:
		return
	_queued = true
	get_tree().create_timer(0.25).timeout.connect(refresh)


func _apply(d: Dictionary) -> void:
	if not d.get("ok", false):
		return
	status = d
	if d.has("networks"):
		networks = d["networks"]
	elif not radio_on():
		networks = []
	changed.emit()


func has_wifi() -> bool:
	return bool(status.get("wifi", false))


func radio_on() -> bool:
	return has_wifi() and bool(status.get("radio", false))


func current() -> Dictionary:
	var c: Variant = status.get("current")
	return c if c is Dictionary else {}


func internet() -> bool:
	return bool(status.get("internet", false))


## Wired adapters that are plugged in.
func wired() -> Array:
	var up := []
	for e in status.get("ethernet", []):
		if bool(e.get("up", false)):
			up.append(e)
	return up


func find(id: String) -> Dictionary:
	for n in networks:
		if str(n["id"]) == id:
			return n
	return {}


## 0-3 arcs for a signal quality (0-100), like Windows' own icon.
static func bars(signal_q: int) -> int:
	if signal_q >= 70:
		return 3
	if signal_q >= 45:
		return 2
	if signal_q >= 20:
		return 1
	return 0


static func speed(mbps: int) -> String:
	if mbps <= 0:
		return ""
	if mbps >= 1000:
		return ("%.1f Gbps" % (mbps / 1000.0)).replace(".0 ", " ")
	return "%d Mbps" % mbps


# --- Actions ------------------------------------------------------------------------

func scan() -> void:
	if _mocked or not Host.available or not radio_on() and not status.is_empty():
		return
	scanning = true
	changed.emit()
	Host.request(["wifi_scan"], func(d: Dictionary) -> void:
		if not d.get("ok", false):
			scanning = false
			changed.emit()
	)
	# Windows says when it's done; this is in case it never does.
	get_tree().create_timer(6.0).timeout.connect(func() -> void:
		if scanning:
			scanning = false
			refresh()
	)


## Joins a network. `key` is only needed for a secured one Windows hasn't saved
## (or to replace a saved key that stopped working).
func join(id: String, key: String = "", auto: bool = true) -> void:
	var ssid := str(find(id).get("ssid", ""))
	joining = id
	_join_serial += 1
	var serial := _join_serial
	changed.emit()
	if _mocked:
		return
	Host.request(["wifi_connect", id, Marshalls.utf8_to_base64(key) if key != "" else "", "1" if auto else "0"], func(d: Dictionary) -> void:
		if d.get("ok", false):
			_fresh = bool(d.get("created", false))
			return
		if joining == id:
			joining = ""
			_finish(false, ssid, str(d.get("error", "")))
	)
	get_tree().create_timer(25.0).timeout.connect(func() -> void:
		if joining == id and serial == _join_serial:
			joining = ""
			_finish(false, ssid, "Windows didn't manage to connect in time")
	)


func disconnect_wifi() -> void:
	if _mocked:
		return
	Host.request(["wifi_disconnect"], func(_d: Dictionary) -> void: _queue_refresh())


func forget(id: String, done: Callable = Callable()) -> void:
	if _mocked:
		return
	Host.request(["wifi_forget", id], func(d: Dictionary) -> void:
		if done.is_valid():
			done.call(d)
		_queue_refresh()
	)


## Turns the Wi-Fi radio on or off. Some PCs keep that switch for Windows'
## own settings; `done` then gets ok false and error "denied".
func set_radio(on: bool, done: Callable = Callable()) -> void:
	if _mocked:
		return
	Host.request(["wifi_radio", "1" if on else "0"], func(d: Dictionary) -> void:
		if done.is_valid():
			done.call(d)
		_queue_refresh()
	)


func _finish(ok: bool, ssid: String, reason: String) -> void:
	# A profile written just now with a key that didn't work isn't worth keeping.
	if not ok and _fresh:
		var id := ""
		for n in networks:
			if str(n["ssid"]) == ssid:
				id = str(n["id"])
		if id != "":
			Host.request(["wifi_forget", id])
	_fresh = false
	joined.emit(ok, ssid, reason)
	changed.emit()


func _on_event(d: Dictionary) -> void:
	var ssid := str(d.get("ssid", ""))
	var mine := joining != "" and (ssid == "" or ssid == str(find(joining).get("ssid", "")))
	match str(d.get("what", "")):
		"scan":
			scanning = false
		"connected":
			if mine:
				joining = ""
				_fresh = false
				joined.emit(true, ssid, "")
		"failed":
			if mine:
				joining = ""
				_finish(false, ssid, str(d.get("reason", "")))
	_queue_refresh()


## Screenshot runs and Linux: a believable set of networks.
func set_mock(s: Dictionary) -> void:
	_mocked = true
	status = s
	networks = s.get("networks", [])
	changed.emit()
