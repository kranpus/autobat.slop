extends SceneTree
## Touch scrolling (TouchScroll autoload): fakes a finger on the real menus.
## Also checks the one-time notice at 1000 rating.
## A drag over the Collection's unit cards scrolls the list and doesn't
## select the card it started on; a tap still selects; the Expeditions and
## Patch Notes lists scroll the same way; a real mouse drag doesn't scroll.
##
##   godot --headless -s res://tests/touch_scroll_test.gd
## Exit code 0 when everything passed.

var main: Node
var profile: Node
var frames := 0
var _ts: Node
var _failures := 0


func _initialize() -> void:
	profile = root.get_node("Profile")
	_ts = root.get_node("TouchScroll")
	profile.settings["start_offline"] = true
	profile.settings.erase("account")
	profile.settings["server_address"] = "127.0.0.1:1"
	profile.reset()
	profile.data["wins"] = 4   # not a new player: no tutorial
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func check(cond: bool, msg: String) -> void:
	if cond:
		print("  ok   ", msg)
	else:
		_failures += 1
		printerr("  FAIL ", msg)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _run() -> void:
	await _frames(20)
	for c in main.login_layer.get_children():
		c.queue_free()
	await _frames(10)
	await _collection_drag()
	await _frames(5)
	await _collection_tap()
	await _frames(5)
	await _expedition_drag()
	await _frames(5)
	await _patch_notes_drag()
	await create_timer(1.0).timeout   # let the glide settle
	await _mouse_drag()
	await _rating_notice()
	await _toasts()
	_finish()


func _touch(pos: Vector2, pressed: bool, device: int = InputEvent.DEVICE_ID_EMULATION) -> void:
	var b := InputEventMouseButton.new()
	b.device = device
	b.button_index = MOUSE_BUTTON_LEFT
	b.pressed = pressed
	b.position = _win(pos)
	b.global_position = b.position
	b.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	Input.parse_input_event(b)
	Input.flush_buffered_events()


func _drag(from: Vector2, to: Vector2, steps: int = 10, device: int = InputEvent.DEVICE_ID_EMULATION) -> void:
	_touch(from, true, device)
	var last := from
	for k in range(1, steps + 1):
		var p := from.lerp(to, float(k) / float(steps))
		var m := InputEventMouseMotion.new()
		m.device = device
		m.position = _win(p)
		m.global_position = m.position
		m.relative = _win(p) - _win(last)
		m.button_mask = MOUSE_BUTTON_MASK_LEFT
		last = p
		Input.parse_input_event(m)
		Input.flush_buffered_events()
	_touch(to, false, device)


## Events arrive in window pixels; the UI works in (stretched) viewport units.
func _win(p: Vector2) -> Vector2:
	return root.get_final_transform() * p


func _scroll_of(n: Node) -> ScrollContainer:
	while n != null and not (n is ScrollContainer):
		n = n.get_parent()
	return n


func _center(c: Control) -> Vector2:
	return c.get_global_rect().get_center()


func _collection_drag() -> void:
	print("touch scrolling")
	main.tabs.current_tab = 0
	main.collection_tab.refresh()
	await process_frame
	await process_frame
	var tab = main.collection_tab
	var card: Button = tab._grid.get_child(1)
	var scroll := _scroll_of(card)
	check(scroll != null and _ts._can_scroll_v(scroll), "the Collection list is long enough to scroll")
	var was: String = tab._selected
	var start := _center(card)
	check(_ts.control_at(start) == card, "the finger finds the card under it")
	_drag(start, start - Vector2(0, 260))
	await process_frame
	check(scroll.scroll_vertical > 150, "dragging up over the cards scrolls the list (%d px)" % scroll.scroll_vertical)
	check(tab._selected == was, "...without selecting the card the drag started on")


func _collection_tap() -> void:
	var tab = main.collection_tab
	var scroll := _scroll_of(tab._grid)
	var before := scroll.scroll_vertical
	var card: Button = null
	for c in tab._grid.get_children():
		if c is Button and scroll.get_global_rect().encloses(c.get_global_rect()):
			card = c
			break
	var pos := _center(card)
	_touch(pos, true)
	_touch(pos, false)
	await process_frame
	check(tab._selected != "", "a tap still selects a card (%s)" % tab._selected)
	check(absi(scroll.scroll_vertical - before) < 4, "...and doesn't scroll")


func _expedition_drag() -> void:
	main.tabs.current_tab = 2
	await process_frame
	await process_frame
	var scroll: ScrollContainer = null
	for s in main.expedition_tab.find_children("*", "ScrollContainer", true, false):
		if s.is_visible_in_tree() and _ts._can_scroll_v(s):
			scroll = s
			break
	check(scroll != null, "the Expeditions list scrolls")
	if scroll == null:
		return
	var pos := scroll.get_global_rect().get_center()
	_drag(pos, pos - Vector2(0, 200))
	await process_frame
	check(scroll.scroll_vertical > 100, "dragging over a region card scrolls the regions (%d px)" % scroll.scroll_vertical)


func _patch_notes_drag() -> void:
	main.tabs.current_tab = 8
	await create_timer(1.5).timeout   # the scrolls unroll
	var scroll: ScrollContainer = null
	for s in main.tabs.get_child(8).find_children("*", "ScrollContainer", true, false):
		if s.is_visible_in_tree() and _ts._can_scroll_v(s):
			scroll = s
	check(scroll != null, "the patch notes scroll")
	if scroll == null:
		return
	var pos := scroll.get_global_rect().get_center()
	_drag(pos, pos - Vector2(0, 220))
	await process_frame
	check(scroll.scroll_vertical > 100, "dragging over the text scrolls the patch notes (%d px)" % scroll.scroll_vertical)
	var at := scroll.scroll_vertical
	await create_timer(0.3).timeout
	check(scroll.scroll_vertical > at, "a quick flick keeps gliding after the finger lifts (%d -> %d px)" % [at, scroll.scroll_vertical])
	_mouse_scroll = scroll


var _mouse_scroll: ScrollContainer


func _mouse_drag() -> void:
	if _mouse_scroll == null:
		return
	var before := _mouse_scroll.scroll_vertical
	var pos := _mouse_scroll.get_global_rect().get_center()
	_drag(pos, pos + Vector2(0, 200), 10, 0)
	await process_frame
	check(absi(_mouse_scroll.scroll_vertical - before) < 4, "a real mouse drag doesn't scroll (mouse users have the wheel and bar)")


## Not touch scrolling, but the same real-menu setup: the one-time notice at
## 1000 rating that training bands now count for less.
func _rating_notice() -> void:
	print("rating notice")
	profile.settings.erase("ai_rating_notice")
	profile.data["rating"] = 990
	main._rating_notice()
	check(get_nodes_in_group("rating_notice").is_empty(), "no notice below 1000")
	profile.data["rating"] = 1003
	main._rating_notice()
	await process_frame
	var shown := get_nodes_in_group("rating_notice")
	check(shown.size() == 1 and (shown[0] as AcceptDialog).visible and (shown[0] as AcceptDialog).dialog_text.contains("quarter"), "reaching 1000 shows the notice")
	for d in shown:
		d.queue_free()
	await process_frame
	main._rating_notice()
	check(get_nodes_in_group("rating_notice").is_empty(), "...only once")
	profile.settings.erase("ai_rating_notice")


## UIKit loaded at runtime: naming it in this script would compile it before
## the autoloads it uses exist.
func _ui_kit() -> GDScript:
	return load("res://scripts/ui/ui_kit.gd")


## 0.9.7: a 4th toast while 3 were showing froze the game.
func _toasts() -> void:
	print("toasts")
	var box: VBoxContainer = main._toast_box
	for i in 10:
		_ui_kit().toast("Toast %d" % i)
	check(box.get_child_count() == 3, "ten toasts in a row: the game keeps running, 3 on screen (%d)" % box.get_child_count())
	var last := box.get_child(2).get_child(0) as Label
	check(last != null and last.text == "Toast 9", "the newest is shown last")
	await process_frame
	_ui_kit().toast("One more")
	check(box.get_child_count() == 3, "...and another one after a frame")


func _finish() -> void:
	print("\n%s (%d failure%s)" % ["ALL TOUCH SCROLL TESTS PASSED" if _failures == 0 else "TOUCH SCROLL TESTS FAILED", _failures, "" if _failures == 1 else "s"])
	quit(1 if _failures > 0 else 0)
