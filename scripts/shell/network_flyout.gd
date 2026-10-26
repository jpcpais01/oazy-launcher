class_name NetworkFlyout
extends Flyout
## The network button's flyout: the link Oazy is on (Wi-Fi or a cable), the
## Wi-Fi networks around with their strength, and joining or leaving one right
## here, with the key typed in place. Wi-Fi on/off sits in the corner.

const LIST_MAX := 330.0
const ENTERPRISE_URI := "ms-availablenetworks:"

var _title: Label
var _head_status: Label
var _radio: ToggleSwitch
var _now: PanelContainer
var _now_glyph: SignalGlyph
var _now_icon: TextureRect
var _now_name: Label
var _now_sub: Label
var _leave: FxButton
var _wired: PanelContainer
var _wired_sub: Label
var _section: HBoxContainer
var _rescan: FxButton
var _scroll: ScrollContainer
var _list: VBoxContainer
var _empty: Label
var _rows := {}
## The network whose row is unfolded, and what Windows said when joining it failed.
var _open_id := ""
var _errors := {}


func _init() -> void:
	width = 400.0


func _build() -> void:
	var head := Kit.hbox(8)
	content.add_child(head)
	_title = Kit.label("Wi-Fi", 15, 700, App.TEXT)
	_title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_title)
	_head_status = Kit.label("", 12, 500, App.TEXT_MUTE)
	_head_status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_head_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_head_status.clip_text = true
	_head_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	head.add_child(_head_status)
	_radio = ToggleSwitch.new()
	_radio.focus_mode = Control.FOCUS_NONE
	_radio.tooltip_text = "Wi-Fi on or off"
	_radio.toggled.connect(_on_radio)
	head.add_child(_radio)

	_now = _card(true)
	content.add_child(_now)
	var row := Kit.hbox(12)
	_now.add_child(row)
	var badge := _badge(true)
	row.add_child(badge)
	_now_glyph = SignalGlyph.new(20)
	_now_glyph.color = Color.WHITE
	_now_glyph.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	badge.add_child(_now_glyph)
	_now_icon = Kit.icon_rect("ethernet", 20, Color.WHITE)
	_now_icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_now_icon.visible = false
	badge.add_child(_now_icon)
	var text := Kit.vbox(1)
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)
	_now_name = _clipped(Kit.label("", 15, 700, App.TEXT))
	text.add_child(_now_name)
	_now_sub = _clipped(Kit.label("", 12, 500, App.TEXT_DIM))
	text.add_child(_now_sub)
	_leave = FxButton.make("Disconnect", "", FxButton.Style.CHIP, 30)
	_leave.add_theme_font_size_override("font_size", 13)
	_leave.focus_mode = Control.FOCUS_NONE
	_leave.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_leave.pressed.connect(func() -> void: Network.disconnect_wifi())
	row.add_child(_leave)

	_wired = _card(false)
	content.add_child(_wired)
	var wrow := Kit.hbox(12)
	_wired.add_child(wrow)
	var wbadge := _badge(false)
	wrow.add_child(wbadge)
	var wicon := Kit.icon_rect("ethernet", 18, Color(1, 1, 1, 0.9))
	wicon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	wbadge.add_child(wicon)
	var wtext := Kit.vbox(1)
	wtext.alignment = BoxContainer.ALIGNMENT_CENTER
	wtext.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrow.add_child(wtext)
	wtext.add_child(Kit.label("Ethernet", 14, 700, App.TEXT))
	_wired_sub = _clipped(Kit.label("", 12, 500, App.TEXT_DIM))
	wtext.add_child(_wired_sub)

	_section = Kit.hbox(6)
	content.add_child(_section)
	var around := Kit.label("Networks around", 12, 700, App.TEXT_MUTE)
	around.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	around.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_section.add_child(around)
	_rescan = FxButton.icon_only("refresh", "Look again", 15, 28)
	_rescan.focus_mode = Control.FOCUS_NONE
	_rescan.pressed.connect(func() -> void: Network.scan())
	_section.add_child(_rescan)

	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(_scroll)
	_list = Kit.vbox(4)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_list)
	_list.minimum_size_changed.connect(_fit_list)

	_empty = Kit.label("", 13, 500, App.TEXT_MUTE)
	_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty.custom_minimum_size.y = 56
	_empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	content.add_child(_empty)

	var line := HSeparator.new()
	line.add_theme_stylebox_override("separator", Kit._line_box())
	content.add_child(line)
	var foot := Kit.hbox(6)
	content.add_child(foot)
	foot.add_child(Kit.spacer(0, 0, true))
	var more := FxButton.make("Network settings", "settings", FxButton.Style.CHIP, 30)
	more.icon = Icons.tex("settings", 15, Color.WHITE)
	more.focus_mode = Control.FOCUS_NONE
	more.pressed.connect(func() -> void:
		close()
		_open_uri("ms-settings:network")
	)
	foot.add_child(more)

	Network.changed.connect(func() -> void:
		if is_open:
			_fill()
	)
	Network.joined.connect(_on_joined)
	set_process(false)


func _on_open() -> void:
	_open_id = ""
	_errors.clear()
	Network.watch(true)
	_fill()
	set_process(true)


func close() -> void:
	if is_open:
		Network.watch(false)
	super.close()


func _process(delta: float) -> void:
	if Network.scanning:
		_rescan.rotation += delta * 5.0
	elif _rescan.rotation != 0.0:
		# Finish the turn rather than snapping back.
		var left := fposmod(-_rescan.rotation, TAU)
		_rescan.rotation = 0.0 if left < delta * 6.0 else _rescan.rotation + delta * 6.0
	elif not is_open:
		set_process(false)


# --- Filling ---------------------------------------------------------------------------

func _fill() -> void:
	var s := Network.status
	var known := not s.is_empty()
	var wifi := Network.has_wifi()
	var on := Network.radio_on()
	var cur := Network.current()
	var cables := Network.wired()

	_title.text = "Wi-Fi" if wifi or not known else "Network"
	_radio.visible = wifi
	if wifi and _radio.button_pressed != on:
		_radio.set_on(on)
	_head_status.text = ""
	if wifi and bool(s.get("hw_off", false)):
		_head_status.text = "Turned off by a switch on this PC"
	elif known and not Network.internet() and (not cur.is_empty() or not cables.is_empty()):
		_head_status.text = "No internet"

	# The link in use: Wi-Fi first, then a cable, else nothing yet.
	_now.visible = true
	_leave.visible = not cur.is_empty()
	_now_icon.visible = false
	_now_glyph.visible = true
	if not cur.is_empty():
		_now_glyph.off = false
		_now_glyph.level = Network.bars(int(cur.get("signal", 0)))
		_now_name.text = str(cur.get("ssid", ""))
		# The lit badge and Disconnect already say it's connected: keep the line for the link.
		var bits: Array[String] = ["Internet" if Network.internet() else "No internet"]
		if str(cur.get("ghz", "")) != "":
			bits.append(str(cur["ghz"]) + " GHz")
		var sp := Network.speed(int(cur.get("mbps", 0)))
		if sp != "":
			bits.append(sp)
		_now_sub.text = " · ".join(bits)
	elif not cables.is_empty():
		_now_glyph.visible = false
		_now_icon.visible = true
		_now_name.text = "Ethernet"
		_now_sub.text = _wired_text(cables[0])
	elif not known:
		_now_glyph.off = false
		_now_glyph.level = 0
		_now_name.text = "Checking networks…" if App.is_windows() else "Networks"
		_now_sub.text = "" if App.is_windows() else "Network controls work on Windows"
	else:
		_now_glyph.off = true
		_now_name.text = "Not connected"
		_now_sub.text = "Pick a network below" if on else ("Turn Wi-Fi on to see networks" if wifi else "Plug in a cable to get online")
	_set_badge_lit(_now, not cur.is_empty() or not cables.is_empty())
	# A cable alongside Wi-Fi gets its own line.
	_wired.visible = not cur.is_empty() and not cables.is_empty()
	if _wired.visible:
		_wired_sub.text = _wired_text(cables[0])

	var listing := wifi and on
	_section.visible = listing
	_rescan.disabled = Network.scanning
	var shown: Array = []
	if listing:
		for n in Network.networks:
			if not bool(n.get("connected", false)):
				shown.append(n)
	_scroll.visible = not shown.is_empty()
	_empty.visible = known and wifi and shown.is_empty()
	if not on:
		_empty.text = "Wi-Fi is off"
	elif Network.scanning or Network.networks.is_empty():
		_empty.text = "Looking for networks…"
	else:
		_empty.text = "No other networks in range"
	_fill_list(shown)


func _wired_text(e: Dictionary) -> String:
	var sp := Network.speed(int(e.get("mbps", 0)))
	return "Connected" + (" · " + sp if sp != "" else "")


func _fill_list(shown: Array) -> void:
	var keep := {}
	for i in shown.size():
		var n: Dictionary = shown[i]
		var id := str(n["id"])
		keep[id] = true
		var r: NetRow = _rows.get(id)
		if r == null:
			r = NetRow.new(self, id)
			_list.add_child(r)
			_rows[id] = r
		_list.move_child(r, i)
		r.show_network(n)
	for id in _rows.keys():
		if not keep.has(id):
			_rows[id].queue_free()
			_rows.erase(id)
	if _open_id != "" and not keep.has(_open_id):
		_open_id = ""


func _fit_list() -> void:
	_scroll.custom_minimum_size.y = minf(_list.get_combined_minimum_size().y, LIST_MAX)


# --- Actions ---------------------------------------------------------------------------

func _toggle_row(id: String) -> void:
	var was := _open_id
	_open_id = "" if was == id else id
	for k in _rows:
		_rows[k].fold(k == _open_id)
	Sfx.play(&"toggle")


## A row's main action: join with what Windows already knows, or with the key typed.
func _join(id: String, key: String, auto: bool) -> void:
	var n := Network.find(id)
	if n.is_empty():
		return
	if str(n.get("auth", "")) == "enterprise":
		close()
		_open_uri(ENTERPRISE_URI)
		return
	_errors.erase(id)
	Network.join(id, key, auto)
	if _rows.has(id):
		_rows[id].fold(true)
	Sfx.play(&"select")


func _forget(id: String) -> void:
	Network.forget(id, func(d: Dictionary) -> void:
		if not d.get("ok", false):
			App.toast(str(d.get("error", "Couldn't forget that network")), &"error")
		elif _rows.has(id):
			_rows[id].fold(_open_id == id)
	)


func _on_joined(ok: bool, ssid: String, reason: String) -> void:
	if ok:
		_open_id = ""
		Sfx.play(&"notify", 1.2)
		if not is_open:
			App.toast("Connected to " + ssid)
	else:
		for n in Network.networks:
			if str(n["ssid"]) == ssid:
				_errors[str(n["id"])] = reason if reason != "" else "Couldn't connect"
				_open_id = str(n["id"])
		Sfx.play(&"error")
		if not is_open:
			App.toast("Couldn't connect to " + ssid, &"error")
	if is_open:
		_fill()
		for k in _rows:
			_rows[k].fold(k == _open_id)


func _on_radio(on: bool) -> void:
	Network.set_radio(on, func(d: Dictionary) -> void:
		if d.get("ok", false):
			return
		_radio.set_on(not on)
		if str(d.get("error", "")) == "denied":
			App.toast("Windows keeps the Wi-Fi switch in its own settings")
			_open_uri("ms-settings:network-wifi")
	)


func _open_uri(uri: String) -> void:
	if not App.is_windows():
		App.toast("That opens on Windows")
		return
	OS.shell_open(uri)


# --- Bits ------------------------------------------------------------------------------

func _card(lit: bool) -> PanelContainer:
	var p := PanelContainer.new()
	var bg := Color(App.accent, 0.13) if lit else Color(1, 1, 1, 0.05)
	var edge := Color(App.accent, 0.3) if lit else Color(1, 1, 1, 0.08)
	p.add_theme_stylebox_override("panel", Kit.box(bg, 16, edge, 1, 12, 10))
	return p


func _badge(lit: bool) -> Control:
	var b := Panel.new()
	b.name = "Badge"
	b.custom_minimum_size = Vector2(40, 40)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_style_badge(b, lit)
	return b


func _style_badge(b: Panel, lit: bool) -> void:
	var st := Kit.box(Color(App.accent, 0.85) if lit else Color(1, 1, 1, 0.1), 20)
	if lit:
		Kit.shadowed(st, Color(App.accent, 0.45), 10, Vector2(0, 2))
	b.add_theme_stylebox_override("panel", st)


func _set_badge_lit(card: PanelContainer, lit: bool) -> void:
	card.add_theme_stylebox_override("panel", Kit.box(Color(App.accent, 0.13) if lit else Color(1, 1, 1, 0.05), 16, Color(App.accent, 0.3) if lit else Color(1, 1, 1, 0.08), 1, 12, 10))
	var b := card.find_child("Badge", true, false)
	if b is Panel:
		_style_badge(b, lit)


static func _clipped(l: Label) -> Label:
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


static func security_text(n: Dictionary) -> String:
	if bool(n.get("known", false)):
		return "Saved" + (", secured" if bool(n.get("secure", false)) else "")
	match str(n.get("auth", "")):
		"open":
			return "Secured (WEP)" if bool(n.get("secure", false)) else "Open"
		"owe":
			return "Open, encrypted"
		"enterprise":
			return "Secured, signs in with an account"
		"wpa3":
			return "Secured (WPA3)"
	return "Secured"


static func needs_key(n: Dictionary) -> bool:
	if bool(n.get("known", false)):
		return false
	var auth := str(n.get("auth", ""))
	return bool(n.get("secure", false)) and auth != "owe" and auth != "enterprise"


## One network in the list. Click to unfold its actions: connect (asking for
## the key in place when Windows doesn't have it), or forget a saved one.
class NetRow extends PanelContainer:
	var fly: NetworkFlyout
	var id := ""
	var net := {}
	var _glyph: SignalGlyph
	var _name: Label
	var _sub: Label
	var _lock: TextureRect
	var _more: VBoxContainer
	var _key: LineEdit
	var _auto: ToggleSwitch
	var _hover := false
	var _open := false

	func _init(f: NetworkFlyout, network_id: String) -> void:
		fly = f
		id = network_id
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var col := Kit.vbox(10)
		add_child(col)
		var top := Kit.hbox(12)
		top.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(top)
		_glyph = SignalGlyph.new(20)
		top.add_child(_glyph)
		var text := Kit.vbox(0)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.mouse_filter = Control.MOUSE_FILTER_IGNORE
		top.add_child(text)
		_name = NetworkFlyout._clipped(Kit.label("", 14, 600, App.TEXT))
		_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
		text.add_child(_name)
		_sub = NetworkFlyout._clipped(Kit.label("", 12, 500, App.TEXT_MUTE))
		_sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
		text.add_child(_sub)
		_lock = Kit.icon_rect("lock", 14, Color(1, 1, 1, 0.45))
		_lock.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_lock.mouse_filter = Control.MOUSE_FILTER_IGNORE
		top.add_child(_lock)
		_more = Kit.vbox(10)
		_more.visible = false
		col.add_child(_more)
		mouse_entered.connect(func() -> void:
			_hover = true
			_restyle()
		)
		mouse_exited.connect(func() -> void:
			_hover = false
			_restyle()
		)
		_restyle()

	func show_network(n: Dictionary) -> void:
		var had_key := needs_key_now()
		net = n
		_name.text = str(n.get("ssid", ""))
		var sig := int(n.get("signal", 0))
		_glyph.level = Network.bars(sig)
		_lock.visible = bool(n.get("secure", false))
		tooltip_text = "Signal %d%%" % sig
		if Network.joining == id:
			_sub.text = "Connecting…"
			_sub.add_theme_color_override("font_color", App.accent.lightened(0.25))
		elif fly._errors.has(id):
			_sub.text = "Couldn't connect"
			_sub.add_theme_color_override("font_color", App.DANGER.lightened(0.2))
		else:
			_sub.text = NetworkFlyout.security_text(n)
			_sub.add_theme_color_override("font_color", App.TEXT_MUTE)
		# Saved-ness or the join state changed under an unfolded row: redo its actions.
		if _open and (had_key != needs_key_now() or _more.get_meta("joining", false) != (Network.joining == id)):
			_fill_more()

	func needs_key_now() -> bool:
		return not net.is_empty() and (NetworkFlyout.needs_key(net) or fly._errors.has(id) and bool(net.get("secure", false)) and str(net.get("auth", "")) != "enterprise")

	func fold(open: bool) -> void:
		if open:
			_fill_more()
		elif _open:
			for c in _more.get_children():
				c.queue_free()
			_key = null
			_auto = null
		_open = open
		_more.visible = open
		_restyle()
		if open and _key and is_instance_valid(_key):
			_key.grab_focus.call_deferred()

	func _restyle() -> void:
		var bg := Color(1, 1, 1, 0.09) if _open else (Color(1, 1, 1, 0.06) if _hover else Color(1, 1, 1, 0.0))
		var edge := Color(1, 1, 1, 0.12) if _open else Color(0, 0, 0, 0)
		add_theme_stylebox_override("panel", Kit.box(bg, 14, edge, 1, 12, 9))
		_glyph.color = Color.WHITE if _open or _hover else Color(1, 1, 1, 0.85)

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			# Clicks inside the unfolded part belong to its buttons and field.
			if _open and get_global_mouse_position().y > _more.get_global_rect().position.y - 4.0:
				return
			fly._toggle_row(id)
			accept_event()

	func _fill_more() -> void:
		for c in _more.get_children():
			_more.remove_child(c)
			c.queue_free()
		_key = null
		_auto = null
		var joining := Network.joining == id
		_more.set_meta("joining", joining)
		if fly._errors.has(id):
			var err := Kit.label(str(fly._errors[id]), 12, 500, App.DANGER.lightened(0.25))
			err.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			err.custom_minimum_size.x = 260
			_more.add_child(err)
		if joining:
			var wait := Kit.label("Joining " + str(net.get("ssid", "")) + "…", 12, 500, App.TEXT_DIM)
			_more.add_child(wait)
			return
		var auth := str(net.get("auth", ""))
		var known := bool(net.get("known", false))
		if auth == "enterprise":
			var why := Kit.label("This network signs in with an account, so Windows takes it from here.", 12, 500, App.TEXT_DIM)
			why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			why.custom_minimum_size.x = 260
			_more.add_child(why)
		elif not bool(net.get("secure", false)) and auth == "open" and not known:
			var warn := Kit.label("Open network: others nearby may see what you send.", 12, 500, App.WARNING.lightened(0.1))
			warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			warn.custom_minimum_size.x = 260
			_more.add_child(warn)
		if needs_key_now():
			var field := Kit.hbox(6)
			_more.add_child(field)
			_key = LineEdit.new()
			_key.secret = true
			_key.placeholder_text = "New network key" if known else "Network key"
			_key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_key.custom_minimum_size.y = 38
			_key.text_submitted.connect(func(_t: String) -> void: _go())
			field.add_child(_key)
			var eye := FxButton.icon_only("eye", "Show the key", 16, 38)
			eye.focus_mode = Control.FOCUS_NONE
			eye.pressed.connect(func() -> void:
				_key.secret = not _key.secret
				eye.icon = Icons.tex("eye" if _key.secret else "eye_off", 16, Color.WHITE)
				eye.tooltip_text = "Show the key" if _key.secret else "Hide the key"
			)
			field.add_child(eye)
		if not known and auth != "enterprise":
			var auto_row := Kit.hbox(8)
			_more.add_child(auto_row)
			var l := Kit.label("Connect automatically", 12, 500, App.TEXT_DIM)
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			auto_row.add_child(l)
			_auto = ToggleSwitch.new()
			_auto.focus_mode = Control.FOCUS_NONE
			_auto.set_on(bool(net.get("secure", false)))
			auto_row.add_child(_auto)
		var acts := Kit.hbox(8)
		_more.add_child(acts)
		if known:
			var forget := FxButton.make("Forget", "", FxButton.Style.CHIP, 34)
			forget.focus_mode = Control.FOCUS_NONE
			forget.tooltip_text = "Remove the saved key for this network"
			forget.pressed.connect(func() -> void: fly._forget(id))
			acts.add_child(forget)
		acts.add_child(Kit.spacer(0, 0, true))
		var go := FxButton.make("Open in Windows" if auth == "enterprise" else "Connect", "", FxButton.Style.ACCENT, 34)
		go.focus_mode = Control.FOCUS_NONE
		go.custom_minimum_size.x = 112
		go.pressed.connect(_go)
		acts.add_child(go)

	func _go() -> void:
		var key := _key.text if _key and is_instance_valid(_key) else ""
		if _key and is_instance_valid(_key) and key.length() < 8 and str(net.get("auth", "")) in ["wpa", "wpa2", "wpa3"]:
			_key.placeholder_text = "Keys are at least 8 characters"
			_key.text = ""
			Sfx.play(&"error")
			return
		var auto := _auto.button_pressed if _auto and is_instance_valid(_auto) else true
		fly._join(id, key, auto)
