class_name UpdateWelcome
extends Modal
## Shown once after an update relaunches Oazy: the orb from the update screen
## fills, a shockwave runs out, the new version number rolls into place and
## the patch notes arrive as cards.

var version := ""
var from_version := ""
var markdown := ""
var show_all := Callable()
var _orb: UpdateOrb
var _check: TextureRect
var _version_label: Label
var _cards: NotesCards
var _roll_time := -0.35
var _rolling := true


func _init() -> void:
	width = 920.0


func _build() -> void:
	var hero := Kit.hbox(26)
	content.add_child(hero)
	var orb_box := Control.new()
	orb_box.custom_minimum_size = Vector2(150, 150)
	hero.add_child(orb_box)
	_orb = UpdateOrb.new(150, 0.74)
	_orb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_orb.mat.set_shader_parameter("waves", 0.6)
	orb_box.add_child(_orb)
	_check = Kit.icon_rect("check", 44, Color.WHITE)
	_check.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_check.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	_check.pivot_offset = Vector2(75, 75)
	_check.scale = Vector2.ZERO
	orb_box.add_child(_check)

	var col := Kit.vbox(4)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	hero.add_child(col)
	col.add_child(Kit.label("UPDATE COMPLETE", 13, 700, App.accent.lightened(0.35)))
	var title := Kit.hbox(12)
	title.add_child(Kit.label("Welcome to Oazy", 34, 700, Color.WHITE, true))
	_version_label = Kit.label(_scramble(0.0), 34, 700, App.accent.lightened(0.4), true)
	title.add_child(_version_label)
	col.add_child(title)
	var sub := "Everything is right where you left it."
	if from_version != "" and from_version != version:
		sub = "Updated from %s. Everything is right where you left it." % from_version
	var s := Kit.label(sub, 16, 500, App.TEXT_DIM)
	s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(s)

	content.add_child(Kit.spacer(0, 4))
	var head := Kit.hbox(10)
	head.add_child(Kit.icon_rect("sparkles", 18, Color.WHITE))
	head.add_child(Kit.label("What's new", 20, 700, Color.WHITE, true))
	content.add_child(head)
	_cards = NotesCards.new(markdown)
	_cards.custom_minimum_size.y = 400
	content.add_child(_cards)

	var row := Kit.hbox(12)
	row.alignment = BoxContainer.ALIGNMENT_END
	content.add_child(row)
	if show_all.is_valid():
		var all := FxButton.make("All patch notes", "document", FxButton.Style.GHOST, 46)
		all.pressed.connect(func() -> void:
			close()
			show_all.call()
		)
		row.add_child(all)
	var ok := FxButton.make("Let's go", "check", FxButton.Style.PRIMARY, 46)
	ok.pressed.connect(close)
	row.add_child(ok)
	ok.grab_focus.call_deferred()

	_play.call_deferred()


func _play() -> void:
	_orb.target = 1.0
	_cards.reveal(0.55)
	var t := create_tween()
	t.tween_interval(0.75)
	t.tween_callback(func() -> void:
		_orb.shockwave()
		_orb.set_look({"waves": 0.3}, 1.2)
		Sfx.play(&"notify")
	)
	t.tween_property(_check, "scale", Vector2.ONE, 0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _process(delta: float) -> void:
	if not _rolling:
		return
	_roll_time += delta
	_version_label.text = _scramble(_roll_time)


## Each digit spins through random numbers, then lands, left to right.
func _scramble(t: float) -> String:
	var out := ""
	var landed := true
	for i in version.length():
		var ch := version[i]
		var lands_at := 0.12 + i * 0.07
		if ch >= "0" and ch <= "9" and t < lands_at:
			out += str(randi() % 10) if t > -0.2 else "0"
			landed = false
		else:
			out += ch
	if landed and t > 0.0:
		_rolling = false
	return out
