extends VBoxContainer
## Patch notes: balance changes and other notable changes, newest first.

const KIND_TAGS := {
	"nerf": ["NERF", "e06a5c"],
	"buff": ["BUFF", "7fd17a"],
	"change": ["CHANGE", "f2c14e"],
	"note": ["NOTE", "a0a4b8"],
}


func _ready() -> void:
	add_theme_constant_override("separation", 10)
	var top := UIKit.hbox(10)
	top.add_child(UIKit.label("Patch Notes", 22, UIKit.ACCENT))
	top.add_child(UIKit.spacer())
	top.add_child(UIKit.label("Your version: %s" % Party.build_version(), 13, UIKit.TEXT_DIM))
	add_child(top)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var list := UIKit.vbox(12)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for patch in PatchNotes.LIST:
		list.add_child(_patch_card(patch))


func _patch_card(patch: Dictionary) -> Control:
	var p := UIKit.panel(UIKit.PANEL_LIGHT)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := UIKit.vbox(6)
	p.add_child(v)
	var head := UIKit.hbox(10)
	head.add_child(UIKit.label("Patch %s: %s" % [patch["version"], patch["title"]], 20, UIKit.ACCENT))
	head.add_child(UIKit.spacer())
	head.add_child(UIKit.label(str(patch["date"]), 13, UIKit.TEXT_DIM))
	v.add_child(head)
	var summary := UIKit.label(str(patch.get("summary", "")), 14)
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(summary)
	for section in patch["sections"]:
		var sl := UIKit.label(str(section["name"]), 16, Color.WHITE)
		v.add_child(sl)
		for note in section["notes"]:
			v.add_child(_note_row(note))
	return p


func _note_row(note: Dictionary) -> Control:
	var h := UIKit.hbox(10)
	var tag: Array = KIND_TAGS.get(str(note.get("kind", "note")), KIND_TAGS["note"])
	var t := UIKit.label(tag[0], 12, Color(tag[1]))
	t.custom_minimum_size = Vector2(64, 0)
	t.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	h.add_child(t)
	var text := UIKit.label(str(note["text"]), 14, UIKit.TEXT_DIM if note.get("kind", "") == "note" else Color(0.92, 0.92, 0.95))
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(text)
	return h
