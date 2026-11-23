class_name ScrollUnroll
extends VBoxContainer
## A parchment scroll between two wooden rods that unrolls to show its
## content (and rolls up again). Put entries in `content`, then unroll().

signal unrolled

var content: VBoxContainer
var _clip: Control
var _body: PanelContainer
var _tween: Tween
var _target := 0.0


func _init() -> void:
	add_theme_constant_override("separation", -6)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_rod())
	_body = PanelContainer.new()
	_body.add_theme_stylebox_override("panel", FantasySkin.parchment_box(0.0))
	_body.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_body)
	_clip = Control.new()
	_clip.clip_contents = true
	_clip.mouse_filter = Control.MOUSE_FILTER_PASS
	_body.add_child(_clip)
	var pad := MarginContainer.new()
	pad.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	for side in ["left", "right"]:
		pad.add_theme_constant_override("margin_" + side, 30)
	for side in ["top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 18)
	pad.mouse_filter = Control.MOUSE_FILTER_PASS
	_clip.add_child(pad)
	content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	content.mouse_filter = Control.MOUSE_FILTER_PASS
	pad.add_child(content)
	add_child(_rod())
	_clip.resized.connect(func(): pad.size.x = _clip.size.x)
	pad.minimum_size_changed.connect(_on_content_size)


func _rod() -> NinePatchRect:
	var r := NinePatchRect.new()
	r.texture = FantasySkin.rod_texture()
	r.patch_margin_left = 14
	r.patch_margin_right = 14
	r.custom_minimum_size = Vector2(0, 22)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


func _content_height() -> float:
	return (_clip.get_child(0) as Control).get_combined_minimum_size().y


func _on_content_size() -> void:
	# Already open: follow the content's height.
	if _target > 0.0 and (_tween == null or not _tween.is_running()):
		_target = _content_height()
		_clip.custom_minimum_size.y = _target


## Unroll to show the content (with the scroll sound).
func unroll(seconds: float = 0.55) -> void:
	_target = _content_height()
	if _tween:
		_tween.kill()
	_clip.custom_minimum_size.y = 0.0
	_tween = create_tween()
	_tween.tween_property(_clip, "custom_minimum_size:y", _target, seconds).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_callback(func(): unrolled.emit())
	Audio.play_sfx("scroll")


## Roll up (closed: just the two rods).
func roll_up(seconds: float = 0.25) -> void:
	_target = 0.0
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_clip, "custom_minimum_size:y", 0.0, seconds).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)


func clear() -> void:
	for c in content.get_children():
		c.queue_free()


# --- ink-on-parchment helpers -------------------------------------------------------

static func ink(text: String, size: int = 15, color: Color = FantasySkin.INK) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if size >= 17:
		l.add_theme_font_override("font", FantasySkin.heading_font())
	return l


## A thin ink rule between entries.
static func rule() -> Control:
	var r := ColorRect.new()
	r.color = Color(FantasySkin.INK, 0.25)
	r.custom_minimum_size = Vector2(0, 1)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## A wax-seal button (red), used for "Attack".
static func seal_button(text: String, callback: Callable) -> Button:
	var b := UIKit.button(text, callback)
	var boxes := FantasySkin.seal_button_boxes()
	for state in boxes:
		b.add_theme_stylebox_override(state, boxes[state])
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(c, Color("f6e7c8"))
	b.add_theme_font_override("font", FantasySkin.heading_font())
	b.add_theme_font_size_override("font_size", 15)
	return b
