class_name AccountPicker
extends Modal
## "Sign in to Oazy": your Google accounts from Chrome to pick from, or any
## other account. Picking one opens Google's sign-in (Account.sign_in) with
## it filled in.

var _first: Button


func _init() -> void:
	width = 540.0


func _build() -> void:
	title_block("Sign in to Oazy", "With your Google account. Your name and photo become your Oazy profile, and Oazy Browser, Flow and your other web apps sign in with it too.", "user")
	content.add_child(Kit.spacer(0, 2))
	var list := Kit.vbox(4)
	content.add_child(list)
	var accounts := Account.chrome_accounts()
	if not accounts.is_empty():
		var head := Kit.label("ON THIS PC", 12, 600, App.TEXT_DIM)
		var m := MarginContainer.new()
		m.add_theme_constant_override("margin_left", 6)
		m.add_theme_constant_override("margin_bottom", 2)
		m.add_child(head)
		list.add_child(m)
	for acc in accounts.slice(0, 6):
		var named := str(acc["name"]) != ""
		var row := _row(str(acc["name"]) if named else str(acc["email"]), str(acc["email"]) if named else "Google account", str(acc.get("from", "")))
		var av: Avatar = row.get_meta("avatar")
		av.set_person(str(acc["name"]) if str(acc["name"]) != "" else str(acc["email"]), null)
		Account.picture(acc, func(t: Texture2D) -> void:
			if is_instance_valid(av):
				av.set_person(str(acc["name"]), t)
		)
		row.pressed.connect(func() -> void: _pick(acc))
		list.add_child(row)
	var other := _row("Use another account" if not accounts.is_empty() else "Continue with Google", "Sign in on Google's page", "")
	var plus: Avatar = other.get_meta("avatar")
	plus.visible = false
	var bubble := PanelContainer.new()
	bubble.custom_minimum_size = Vector2(44, 44)
	bubble.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bubble.add_theme_stylebox_override("panel", Kit.box(Color(1, 1, 1, 0.06), 999, Color(1, 1, 1, 0.1), 1))
	var ic := Kit.icon_rect("plus" if not accounts.is_empty() else "user", 20, App.TEXT)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bubble.add_child(ic)
	plus.get_parent().add_child(bubble)
	plus.get_parent().move_child(bubble, 0)
	other.pressed.connect(func() -> void: _pick({}))
	list.add_child(other)

	var note := Kit.label("Google asks for your password or passkey on its own page, in a small Oazy window. Oazy never sees it, and Chrome stays signed in as it is.", 13, 500, App.TEXT_MUTE)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var nm := MarginContainer.new()
	nm.add_theme_constant_override("margin_left", 6)
	nm.add_theme_constant_override("margin_right", 6)
	nm.add_theme_constant_override("margin_top", 6)
	nm.add_child(note)
	content.add_child(nm)


## A pickable account: picture, name, email and where it came from.
func _row(title: String, sub: String, from: String) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size.y = 64
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_stylebox_override("normal", Kit.empty())
	b.add_theme_stylebox_override("hover", Kit.box(Color(1, 1, 1, 0.06), 14, Color(1, 1, 1, 0.06), 1))
	b.add_theme_stylebox_override("pressed", Kit.box(Color(1, 1, 1, 0.1), 14, Color(1, 1, 1, 0.08), 1))
	b.add_theme_stylebox_override("focus", Kit.box(Color(0, 0, 0, 0), 14, Color(1, 1, 1, 0.5), 1))
	var row := Kit.hbox(14)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 10
	row.offset_right = -12
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(row)
	var av := Avatar.new(44)
	av.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(av)
	b.set_meta("avatar", av)
	var text := Kit.vbox(1)
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(text)
	var t := Kit.label(title, 16, 600, App.TEXT)
	t.clip_text = true
	t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	text.add_child(t)
	var s := Kit.label(sub, 13, 500, App.TEXT_DIM)
	s.clip_text = true
	s.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	text.add_child(s)
	if from != "":
		var f := Kit.label(from, 12, 500, App.TEXT_MUTE)
		f.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(f)
	var chev := Kit.icon_rect("chevron_right", 16, App.TEXT_MUTE)
	chev.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(chev)
	if _first == null:
		_first = b
	return b


func _pick(acc: Dictionary) -> void:
	Sfx.play(&"select")
	close()
	Account.sign_in(acc)


func _focus_first() -> void:
	if _first:
		_first.grab_focus()
