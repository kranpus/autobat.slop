class_name UIKit
extends RefCounted
## Small helpers for building the UI in code.

const BG := Color("1b1d24")
const PANEL := Color("262a35")
const PANEL_LIGHT := Color("323748")
const ACCENT := Color("e0b04a")
const TEXT_DIM := Color("9aa0b0")
const GOOD := Color("6fdc6f")
const BAD := Color("ff6b6b")


static func make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 15
	var panel := StyleBoxFlat.new()
	panel.bg_color = PANEL
	panel.set_corner_radius_all(6)
	panel.set_content_margin_all(10)
	t.set_stylebox("panel", "PanelContainer", panel)
	var btn := StyleBoxFlat.new()
	btn.bg_color = Color("3a4157")
	btn.set_corner_radius_all(5)
	btn.content_margin_left = 12
	btn.content_margin_right = 12
	btn.content_margin_top = 6
	btn.content_margin_bottom = 6
	var hover := btn.duplicate() as StyleBoxFlat
	hover.bg_color = Color("4a5370")
	var pressed := btn.duplicate() as StyleBoxFlat
	pressed.bg_color = Color("5d4a1f")
	var disabled := btn.duplicate() as StyleBoxFlat
	disabled.bg_color = Color("2a2e3a")
	t.set_stylebox("normal", "Button", btn)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("pressed", "Button", pressed)
	t.set_stylebox("disabled", "Button", disabled)
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_disabled_color", "Button", Color("6a7080"))
	var tab_sel := StyleBoxFlat.new()
	tab_sel.bg_color = PANEL
	tab_sel.set_corner_radius_all(6)
	tab_sel.corner_radius_bottom_left = 0
	tab_sel.corner_radius_bottom_right = 0
	tab_sel.content_margin_left = 16
	tab_sel.content_margin_right = 16
	tab_sel.content_margin_top = 8
	tab_sel.content_margin_bottom = 8
	var tab_un := tab_sel.duplicate() as StyleBoxFlat
	tab_un.bg_color = Color("1f222b")
	t.set_stylebox("tab_selected", "TabContainer", tab_sel)
	t.set_stylebox("tab_unselected", "TabContainer", tab_un)
	t.set_stylebox("tab_hovered", "TabContainer", tab_un)
	var tc_panel := StyleBoxFlat.new()
	tc_panel.bg_color = PANEL
	tc_panel.set_content_margin_all(12)
	t.set_stylebox("panel", "TabContainer", tc_panel)
	return t


static func label(text: String, size: int = 15, color: Color = Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func button(text: String, callback: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(callback)
	Audio.hook_button(b)
	return b


static func icon(tex: Texture2D, px: int) -> TextureRect:
	var r := TextureRect.new()
	r.texture = tex
	r.custom_minimum_size = Vector2(px, px)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return r


static func unit_icon(id: String, px: int, locked: bool = false) -> TextureRect:
	var r := icon(GameData.unit_texture(id), px)
	if locked:
		r.modulate = Color(0, 0, 0, 0.85)
	return r


static func panel(bg: Color = PANEL) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(10)
	p.add_theme_stylebox_override("panel", sb)
	return p


static func hbox(sep: int = 8) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


static func vbox(sep: int = 6) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


static func spacer() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c


static func clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()


static func squad_strip(squads: Array, px: int = 28) -> HBoxContainer:
	var h := hbox(2)
	var counts := Army.deploy_counts(squads)
	for i in squads.size():
		var sq: Dictionary = squads[i]
		var v := vbox(0)
		var ic := unit_icon(sq["unit"], px)
		ic.tooltip_text = "%s  Lv %d  x%d" % [GameData.UNITS[sq["unit"]]["name"], int(sq["level"]), int(counts[i])]
		v.add_child(ic)
		var l := label("x%d" % int(counts[i]), 11, TEXT_DIM)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(l)
		h.add_child(v)
	return h
