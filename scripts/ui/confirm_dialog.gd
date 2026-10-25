class_name ConfirmDialog
extends Modal
## Yes/no question with a clear primary action.

var title := ""
var message := ""
var confirm_text := "Confirm"
var danger := false
var on_confirm := Callable()
var _confirm: FxButton


func _init() -> void:
	width = 520.0


func _build() -> void:
	title_block(title, message, "alert" if danger else "info")
	content.add_child(Kit.spacer(0, 6))
	var row := Kit.hbox(12)
	row.alignment = BoxContainer.ALIGNMENT_END
	content.add_child(row)
	var cancel := FxButton.make("Cancel", "", FxButton.Style.GHOST, 46)
	cancel.pressed.connect(close)
	row.add_child(cancel)
	_confirm = FxButton.make(confirm_text, "trash" if danger else "check", FxButton.Style.DANGER if danger else FxButton.Style.PRIMARY, 46)
	_confirm.pressed.connect(func() -> void:
		if on_confirm.is_valid():
			on_confirm.call()
		close()
	)
	row.add_child(_confirm)


func _focus_first() -> void:
	_confirm.grab_focus()
