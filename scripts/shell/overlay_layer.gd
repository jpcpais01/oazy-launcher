class_name OverlayLayer
extends Control
## Holds dialogs and full-screen overlays. In shell mode its layer covers the
## screen while anything is open and comes to the front with focus.


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	child_entered_tree.connect(func(_c: Node) -> void: Shell.focus.call_deferred(self))


func shell_shape() -> Variant:
	for c in get_children():
		if not c.is_queued_for_deletion():
			return null
	return [] as Array[Rect2]
