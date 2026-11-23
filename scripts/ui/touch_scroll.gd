extends Node
## Touch scrolling for every menu (autoload "TouchScroll"): on a touchscreen,
## drag anywhere on a scrollable list (over cards, buttons, text) to scroll
## it, not just on its scroll bar, and it keeps gliding a little when you let
## go. A short tap still presses whatever is under the finger; once the
## finger has moved far enough to count as a scroll, the button it started
## on is let go instead of pressed.
##
## Only touch input scrolls this way (on phones the browser and Android turn
## touches into mouse events marked as emulated); a real mouse keeps the
## wheel and the scroll bar. Lists whose cards can be dragged and dropped
## (the Army tab, the draft board) only scroll when the finger moves along
## the list, so sideways drags still pick the card up.

## How far (pixels) a finger has to move before it scrolls instead of tapping.
const DRAG_START := 12.0
## Momentum after letting go: how quickly the glide slows (per second).
const FRICTION := 5.0
const MIN_GLIDE_SPEED := 20.0
const MAX_GLIDE_SPEED := 3000.0

## Treat mouse drags like touches too (for tests).
var mouse_too := false

var _pressing := false
var _press_pos := Vector2.ZERO
var _scroll: ScrollContainer = null
var _start_scroll := Vector2.ZERO
var _touched: Control = null
var _dragging := false
var _drag_source := false
var _velocity := Vector2.ZERO
var _last_time := 0
var _glide: ScrollContainer = null
var _synth := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func is_dragging() -> bool:
	return _dragging


func _input(event: InputEvent) -> void:
	if _synth:
		return
	var mb := event as InputEventMouseButton
	if mb and mb.button_index == MOUSE_BUTTON_LEFT and _is_touch(mb):
		if mb.pressed:
			_begin(mb.position)
		else:
			_end()
		return
	var mm := event as InputEventMouseMotion
	if mm and _pressing and _is_touch(mm):
		_move(mm.position)


func _is_touch(e: InputEvent) -> bool:
	return e.device == InputEvent.DEVICE_ID_EMULATION or mouse_too


func _begin(pos: Vector2) -> void:
	_glide = null
	_pressing = true
	_dragging = false
	_press_pos = pos
	_velocity = Vector2.ZERO
	_last_time = Time.get_ticks_msec()
	_touched = control_at(pos)
	_scroll = null
	_drag_source = false
	var c: Node = _touched
	while c != null and c is Control:
		if c is ScrollBar:
			_scroll = null   # the scroll bar works by itself
			return
		if (c as Control).has_meta("drag_source"):
			_drag_source = true
		if c is ScrollContainer and _can_scroll(c):
			_scroll = c
			_start_scroll = Vector2(_scroll.scroll_horizontal, _scroll.scroll_vertical)
			return
		c = c.get_parent()


func _move(pos: Vector2) -> void:
	if _scroll == null or not is_instance_valid(_scroll):
		return
	var total := pos - _press_pos
	if not _dragging:
		if total.length() < DRAG_START:
			if _drag_source:
				# Hold the movement back until we know which way it goes, or
				# the card's own drag-and-drop would start first.
				get_viewport().set_input_as_handled()
			return
		if get_viewport().gui_is_dragging():
			_scroll = null   # a card is being dragged and dropped
			return
		var v := _can_scroll_v(_scroll)
		var h := _can_scroll_h(_scroll)
		# Drag-and-drop cards: scroll only when moving along the list.
		if _drag_source and not ((v and absf(total.y) > absf(total.x) * 1.5) or (h and absf(total.x) > absf(total.y) * 1.5)):
			_scroll = null
			return
		_dragging = true
		_release_pressed()
	var now := Time.get_ticks_msec()
	var prev := Vector2(_scroll.scroll_horizontal, _scroll.scroll_vertical)
	_scroll.scroll_horizontal = int(_start_scroll.x - total.x) if _can_scroll_h(_scroll) else _scroll.scroll_horizontal
	_scroll.scroll_vertical = int(_start_scroll.y - total.y) if _can_scroll_v(_scroll) else _scroll.scroll_vertical
	var dt := maxf(0.008, float(now - _last_time) / 1000.0)
	_velocity = _velocity.lerp((Vector2(_scroll.scroll_horizontal, _scroll.scroll_vertical) - prev) / dt, 0.5).limit_length(MAX_GLIDE_SPEED)
	_last_time = now
	# Nothing else should see this finger move: no button hover changes, no
	# drag-and-drop starting.
	get_viewport().set_input_as_handled()


func _end() -> void:
	if _dragging and _scroll != null and is_instance_valid(_scroll) and Time.get_ticks_msec() - _last_time < 120:
		_glide = _scroll
	else:
		_velocity = Vector2.ZERO
	_pressing = false
	_dragging = false
	_scroll = null
	_touched = null


func _process(delta: float) -> void:
	if _glide == null or not is_instance_valid(_glide) or not _glide.is_visible_in_tree():
		_glide = null
		return
	if _velocity.length() < MIN_GLIDE_SPEED:
		_glide = null
		return
	var before := Vector2(_glide.scroll_horizontal, _glide.scroll_vertical)
	_glide.scroll_horizontal = int(before.x + _velocity.x * delta)
	_glide.scroll_vertical = int(before.y + _velocity.y * delta)
	if Vector2(_glide.scroll_horizontal, _glide.scroll_vertical) == before:
		_glide = null   # hit the end
		return
	_velocity *= maxf(0.0, 1.0 - FRICTION * delta)


## The button the finger came down on stops being pressed (so lifting the
## finger after a scroll doesn't press it).
func _release_pressed() -> void:
	var c: Node = _touched
	while c != null and c != _scroll:
		if c is BaseButton and not (c as BaseButton).disabled:
			# Disabling a button drops the press in progress (a toggle keeps
			# its state).
			var b := c as BaseButton
			b.disabled = true
			b.disabled = false
			return
		c = c.get_parent()


static func _can_scroll_v(s: ScrollContainer) -> bool:
	return s.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED and s.get_v_scroll_bar().max_value > s.get_v_scroll_bar().page + 1.0


static func _can_scroll_h(s: ScrollContainer) -> bool:
	return s.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED and s.get_h_scroll_bar().max_value > s.get_h_scroll_bar().page + 1.0


static func _can_scroll(s: ScrollContainer) -> bool:
	return _can_scroll_v(s) or _can_scroll_h(s)


# --- finding the control under the finger ------------------------------------------

## The control that would receive a click at `pos` in the main window, the
## same way the GUI picks it: the last-drawn visible control that doesn't
## ignore the mouse, searching higher canvas layers first.
func control_at(pos: Vector2) -> Control:
	var roots: Array = []
	_collect_roots(get_tree().root, 0, roots)
	roots.sort_custom(func(a, b): return a[0] < b[0] if a[0] != b[0] else a[1] < b[1])
	for i in range(roots.size() - 1, -1, -1):
		var hit := _find_in(roots[i][2], pos)
		if hit != null:
			return hit
	return null


func _collect_roots(n: Node, layer: int, out: Array) -> void:
	for child in n.get_children():
		if child is Window:
			continue   # popups have their own windows
		if child is CanvasLayer:
			if (child as CanvasLayer).visible:
				_collect_roots(child, (child as CanvasLayer).layer, out)
			continue
		if child is Control:
			out.append([layer, out.size(), child])
		elif child is CanvasItem and not (child as CanvasItem).visible:
			continue
		else:
			_collect_roots(child, layer, out)


func _find_in(c: Control, pos: Vector2) -> Control:
	if not c.visible:
		return null
	var inside := c.get_global_rect().has_point(pos)
	if c.clip_contents and not inside:
		return null
	for i in range(c.get_child_count() - 1, -1, -1):
		var child := c.get_child(i) as Control
		if child == null or child.top_level:
			continue
		var hit := _find_in(child, pos)
		if hit != null:
			return hit
	if inside and c.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		return c
	return null
