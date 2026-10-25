class_name NotesDialog
extends Modal
## Patch notes viewer: either a fixed Markdown text, or the full release
## history fetched from GitHub.

var title := "Patch notes"
var subtitle := ""
var markdown := ""
var history := false
var _text: RichTextLabel


func _init() -> void:
	width = 780.0


func _build() -> void:
	title_block(title, subtitle, "sparkles")
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", Kit.box(Color(0, 0, 0, 0.22), 18, Color(1, 1, 1, 0.06), 1, 22, 18))
	content.add_child(frame)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.fit_content = false
	_text.scroll_active = true
	_text.custom_minimum_size = Vector2(0, 420)
	_text.selection_enabled = true
	_text.meta_clicked.connect(func(meta: Variant) -> void: OS.shell_open(str(meta)))
	frame.add_child(_text)
	var row := Kit.hbox(12)
	row.alignment = BoxContainer.ALIGNMENT_END
	content.add_child(row)
	var ok := FxButton.make("Close", "check", FxButton.Style.PRIMARY, 46)
	ok.pressed.connect(close)
	row.add_child(ok)
	if history:
		Updater.state_changed.connect(_on_state)
		if Updater.releases.is_empty():
			_text.text = "[color=#ffffff88]Fetching release history from GitHub…[/color]"
			Updater.check()
		else:
			_render_history()
	else:
		_text.text = Markdown.to_bbcode(markdown, App.accent.lightened(0.25))


func _on_state(state: StringName) -> void:
	if not is_inside_tree():
		return
	if state == &"error" and Updater.releases.is_empty():
		_text.text = "[color=#ffffff88]%s[/color]" % Updater.error_text
	elif state != &"checking":
		_render_history()


func _render_history() -> void:
	if Updater.releases.is_empty():
		_text.text = "[color=#ffffff88]No releases published yet.[/color]"
		return
	var md := PackedStringArray()
	for r in Updater.releases:
		var tag := ""
		if Semver.compare(r["version"], App.version) == 0:
			tag = "  ·  installed"
		elif Semver.is_newer(r["version"], App.version):
			tag = "  ·  new"
		md.append("## Version %s\n*%s%s*\n\n%s" % [r["version"], Fmt.date(str(r["date"])), tag, str(r["notes"]).strip_edges()])
	_text.text = Markdown.to_bbcode("\n\n---\n\n".join(md), App.accent.lightened(0.25))
