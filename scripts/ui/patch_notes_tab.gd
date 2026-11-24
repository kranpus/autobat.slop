extends VBoxContainer
## Patch notes, newest first: each patch is a decree on its own scroll,
## unrolled when the tab is opened.

const KIND_TAGS := {
	"nerf": ["NERF", FantasySkin.INK_BAD],
	"buff": ["BUFF", FantasySkin.INK_GOOD],
	"change": ["CHANGE", FantasySkin.INK_ACCENT],
	"fix": ["FIX", FantasySkin.INK_GOOD],
	"note": ["NOTE", FantasySkin.INK_DIM],
}

var _scrolls: Array = []
var _opened := false


## How many of the newest patches unroll with an animation.
const ANIMATED := 4


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
	var list := UIKit.vbox(18)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for patch in PatchNotes.LIST:
		var s := _decree(patch)
		list.add_child(s)
		_scrolls.append(s)
	visibility_changed.connect(func():
		if is_visible_in_tree() and not _opened:
			_opened = true
			# Unroll the newest at once (one scroll sound), the next few just
			# after, silently, and open the older ones straight away (0.9.9:
			# every patch used to play the sound).
			for i in _scrolls.size():
				var s := _scrolls[i] as ScrollUnroll
				if i < ANIMATED:
					get_tree().create_timer(0.15 * i).timeout.connect(s.unroll.bind(0.6, i == 0))
				else:
					s.unroll(0.01, false))


func _decree(patch: Dictionary) -> ScrollUnroll:
	var s := ScrollUnroll.new()
	var v := s.content
	var head := UIKit.hbox(10)
	head.add_child(ScrollUnroll.ink("Patch %s: %s" % [patch["version"], patch["title"]], 22))
	head.add_child(UIKit.spacer())
	head.add_child(ScrollUnroll.ink(str(patch["date"]), 13, FantasySkin.INK_DIM))
	v.add_child(head)
	var summary := ScrollUnroll.ink(str(patch.get("summary", "")), 15)
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(summary)
	for section in patch["sections"]:
		v.add_child(ScrollUnroll.rule())
		v.add_child(ScrollUnroll.ink(str(section["name"]), 18, FantasySkin.INK_ACCENT))
		for note in section["notes"]:
			v.add_child(_note_row(note))
	return s


func _note_row(note: Dictionary) -> Control:
	var h := UIKit.hbox(10)
	var tag: Array = KIND_TAGS.get(str(note.get("kind", "note")), KIND_TAGS["note"])
	var t := ScrollUnroll.ink(tag[0], 12, tag[1])
	t.custom_minimum_size = Vector2(64, 0)
	t.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	h.add_child(t)
	var text := ScrollUnroll.ink(str(note["text"]), 14, FantasySkin.INK_DIM if note.get("kind", "") == "note" else FantasySkin.INK)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(text)
	return h
