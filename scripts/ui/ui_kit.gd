class_name UIKit
extends RefCounted
## Small helpers for building the UI in code.

const BG := Color("1b1d24")
const PANEL := Color("262a35")
const PANEL_LIGHT := Color("323748")
const ACCENT := Color("e0b04a")
const TEXT_DIM := Color("b3a383")   # warm, like faded ink on wood
const GOOD := Color("6fdc6f")
const BAD := Color("ff6b6b")


static func make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 15
	# Wood and gold (FantasySkin draws the textures at startup).
	t.set_stylebox("panel", "PanelContainer", FantasySkin.frame_box(0))
	t.set_stylebox("normal", "Button", FantasySkin.frame_box(2, 8.0))
	t.set_stylebox("hover", "Button", FantasySkin.frame_box(3, 8.0))
	t.set_stylebox("pressed", "Button", FantasySkin.frame_box(4, 8.0))
	t.set_stylebox("disabled", "Button", FantasySkin.frame_box(5, 8.0))
	for state in ["normal", "hover", "pressed", "disabled"]:
		var sb := t.get_stylebox(state, "Button") as StyleBoxTexture
		sb.content_margin_left = 14
		sb.content_margin_right = 14
		sb.content_margin_top = 7
		sb.content_margin_bottom = 7
		t.set_stylebox(state, "OptionButton", sb)
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	# Check boxes and switches stay plain (no wooden plate around them).
	for cls in ["CheckBox", "CheckButton"]:
		for state in ["normal", "hover", "pressed", "disabled", "hover_pressed", "focus"]:
			var e := StyleBoxEmpty.new()
			e.set_content_margin_all(4)
			t.set_stylebox(state, cls, e)
		t.set_color("font_color", cls, Color("e8dcc0"))
		t.set_color("font_hover_color", cls, Color("fff4d6"))
		t.set_color("font_pressed_color", cls, Color("e8dcc0"))
		t.set_color("font_hover_pressed_color", cls, Color("fff4d6"))
	t.set_color("font_color", "Button", Color("f0e2c0"))
	t.set_color("font_hover_color", "Button", Color("fff4d6"))
	t.set_color("font_pressed_color", "Button", ACCENT)
	t.set_color("font_disabled_color", "Button", Color("7d7465"))
	# Tabs: wooden tabs, the open one trimmed in gold and lettered in Cinzel.
	var tab_sel := FantasySkin.frame_box(1, 0.0)
	tab_sel.content_margin_left = 16
	tab_sel.content_margin_right = 16
	tab_sel.content_margin_top = 8
	tab_sel.content_margin_bottom = 8
	var tab_un := FantasySkin.frame_box(4, 0.0)
	tab_un.content_margin_left = 16
	tab_un.content_margin_right = 16
	tab_un.content_margin_top = 8
	tab_un.content_margin_bottom = 8
	tab_un.modulate_color = Color(0.62, 0.6, 0.58)
	for cls in ["TabContainer", "TabBar"]:
		t.set_stylebox("tab_selected", cls, tab_sel)
		t.set_stylebox("tab_unselected", cls, tab_un)
		t.set_stylebox("tab_hovered", cls, tab_un)
		t.set_font("font", cls, FantasySkin.heading_font())
		t.set_font_size("font_size", cls, 15)
		t.set_color("font_selected_color", cls, ACCENT)
		t.set_color("font_unselected_color", cls, Color("a8987a"))
		t.set_color("font_hovered_color", cls, Color("f0e2c0"))
	var tc_panel := FantasySkin.frame_box(0, 12.0)
	t.set_stylebox("panel", "TabContainer", tc_panel)
	# Text fields: a dark inset.
	var field := StyleBoxFlat.new()
	field.bg_color = Color("17130f")
	field.border_color = FantasySkin.GOLD_DARK
	field.set_border_width_all(1)
	field.set_corner_radius_all(3)
	field.set_content_margin_all(7)
	t.set_stylebox("normal", "LineEdit", field)
	t.set_stylebox("read_only", "LineEdit", field)
	var focus := field.duplicate() as StyleBoxFlat
	focus.border_color = ACCENT
	t.set_stylebox("focus", "LineEdit", focus)
	# Tooltips on parchment, in ink.
	t.set_stylebox("panel", "TooltipPanel", FantasySkin.parchment_box(10.0))
	t.set_color("font_color", "TooltipLabel", FantasySkin.INK)
	# Popups get the wooden frame too.
	t.set_stylebox("panel", "PopupPanel", FantasySkin.frame_box(0, 14.0))
	t.set_stylebox("panel", "AcceptDialog", FantasySkin.frame_box(0, 14.0))
	t.set_stylebox("embedded_border", "Window", FantasySkin.frame_box(0, 0.0))
	return t


## The stone background behind the menus.
static func background() -> TextureRect:
	var r := TextureRect.new()
	r.texture = FantasySkin.stone_texture()
	r.stretch_mode = TextureRect.STRETCH_TILE
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## A sword for a mouse pointer (desktop and browser).
static func apply_cursor() -> void:
	if OS.has_feature("mobile") or DisplayServer.get_name() == "headless":
		return
	var tex := load("res://assets/sprites/ui/cursor_sword.png") as Texture2D
	if tex:
		Input.set_custom_mouse_cursor(tex, Input.CURSOR_ARROW, Vector2(2, 2))


static func label(text: String, size: int = 15, color: Color = Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	# Headings are lettered in Cinzel.
	if size >= 18:
		l.add_theme_font_override("font", FantasySkin.heading_font())
	return l


static func button(text: String, callback: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(callback)
	Audio.hook_button(b)
	return b


## A prominent call-to-action button (gold background, dark text).
static func accent_button(text: String, callback: Callable, font_size: int = 18) -> Button:
	var b := button(text, callback)
	# A gilded plate lettered in Cinzel.
	var plate := FantasySkin.frame_box(6, 10.0)
	var hover := plate.duplicate() as StyleBoxTexture
	hover.modulate_color = Color(1.12, 1.1, 1.0)
	var pressed := plate.duplicate() as StyleBoxTexture
	pressed.modulate_color = Color(0.8, 0.75, 0.65)
	b.add_theme_stylebox_override("normal", plate)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(c, Color("2a1a0c"))
	b.add_theme_font_override("font", FantasySkin.heading_font())
	b.add_theme_font_size_override("font_size", font_size)
	b.custom_minimum_size = Vector2(0, 46)
	return b


## Show a popup centred, then centre it again once its content has settled
## (wrapped text can make it taller a frame later), keeping it on screen.
static func popup_fit(popup: Popup, min_size: Vector2i) -> void:
	popup.popup_centered(min_size)
	var recentre := func():
		if not is_instance_valid(popup) or not popup.visible:
			return
		var view := Vector2i(popup.get_parent().get_viewport().get_visible_rect().size)
		popup.reset_size()   # shrink to the content (it may have been bigger before)
		popup.size = Vector2i(mini(maxi(popup.size.x, min_size.x), view.x - 16), mini(popup.size.y, view.y - 16))
		popup.position = (view - popup.size) / 2
	recentre.call_deferred()
	popup.get_tree().create_timer(0.05).timeout.connect(recentre)


## Marks a control as a tutorial target (see scripts/ui/tutorial.gd).
static func tut(node: Control, id: String) -> Control:
	node.set_meta("tut", id)
	node.add_to_group("tut")
	return node


## A short message that pops up at the top of the screen and fades
## ("Goblin Skirmisher reached level 2"). Main hosts them.
static func toast(text: String, color: Color = Color.WHITE) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var host := tree.get_first_node_in_group("toast_host")
	if host:
		host.call("show_toast", text, color)


static var _dot: Texture2D


## The small red dot on tabs that have something waiting.
static func badge_dot() -> Texture2D:
	if _dot == null:
		var img := Image.create(14, 14, false, Image.FORMAT_RGBA8)
		for y in 14:
			for x in 14:
				var d := Vector2(x - 6.5, y - 6.5).length()
				var a := clampf(6.5 - d, 0.0, 1.0)
				img.set_pixel(x, y, Color(1.0, 0.3, 0.28, a) if d < 5.0 else Color(1, 1, 1, a))
		_dot = ImageTexture.create_from_image(img)
	return _dot


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


## A wooden panel with gold trim (PANEL: dark, PANEL_LIGHT: a lighter card).
## Other colours (overlays, highlights) keep a flat fill with a thin gold edge.
static func panel(bg: Color = PANEL) -> PanelContainer:
	var p := PanelContainer.new()
	if bg == PANEL or bg == PANEL_LIGHT:
		p.add_theme_stylebox_override("panel", FantasySkin.frame_box(0 if bg == PANEL else 1, 12.0))
		return p
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = Color(FantasySkin.GOLD_DARK, minf(1.0, bg.a + 0.2))
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(10)
	p.add_theme_stylebox_override("panel", sb)
	return p


## Aged parchment (write on it in ink: ScrollUnroll.ink).
static func parchment_panel(margin: float = 18.0) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", FantasySkin.parchment_box(margin))
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


static func squad_strip(squads: Array, px: int = 28, text_color: Color = TEXT_DIM) -> HBoxContainer:
	var h := hbox(2)
	var counts := Army.deploy_counts(squads)
	for i in squads.size():
		var sq: Dictionary = squads[i]
		var v := vbox(0)
		var ic := unit_icon(sq["unit"], px)
		ic.tooltip_text = "%s  Lv %d  x%d" % [GameData.UNITS[sq["unit"]]["name"], int(sq["level"]), int(counts[i])]
		v.add_child(ic)
		var l := label("x%d" % int(counts[i]), 11, text_color)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(l)
		h.add_child(v)
	return h


# --- screen size / mobile -------------------------------------------------------

const UI_SCALES := ["auto", "1.0", "1.25", "1.5", "1.75", "2.0"]


static func is_mobile() -> bool:
	return OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")


## Interface scale chosen from the physical screen size: 1.0 on desktop, larger
## on phones so text and buttons are big enough to read and tap.
static func auto_ui_scale() -> float:
	if not is_mobile():
		return 1.0
	var screen := DisplayServer.screen_get_size()
	var dpi := maxf(96.0, float(DisplayServer.screen_get_dpi()))
	var short_side_inches := float(mini(screen.x, screen.y)) / dpi
	# Aim for roughly 110 logical pixels per inch of screen height...
	var logical_height := clampf(short_side_inches * 110.0, 430.0, 720.0)
	var factor := 720.0 / logical_height
	# ...but keep the layout at least 960 logical pixels wide.
	var aspect := float(maxi(screen.x, screen.y)) / float(maxi(1, mini(screen.x, screen.y)))
	return clampf(minf(factor, 720.0 * aspect / 960.0), 1.0, 2.0)


# --- fullscreen ---------------------------------------------------------------

## Phones and tablets are always fullscreen; desktop windows and browser
## pages can switch.
static func can_toggle_fullscreen() -> bool:
	return not OS.has_feature("mobile")


static func is_fullscreen() -> bool:
	var m := DisplayServer.window_get_mode()
	return m == DisplayServer.WINDOW_MODE_FULLSCREEN or m == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN


## Fullscreen on or off, remembered in the device settings. In a browser
## this must come from a click or key press (browsers only allow fullscreen
## in response to the player).
static func set_fullscreen(on: bool) -> void:
	if not can_toggle_fullscreen() or DisplayServer.get_name() == "headless":
		return
	if on:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	Profile.settings["fullscreen"] = on
	Profile.save_settings()


static func toggle_fullscreen() -> void:
	set_fullscreen(not is_fullscreen())


## At startup: exported desktop builds open fullscreen unless the player
## turned it off. (Browsers can't start fullscreen: the page fills the
## browser window or the itch.io frame, and the Fullscreen button goes
## further. Running from the editor stays windowed unless chosen.)
static func apply_startup_display() -> void:
	if OS.has_feature("web") or OS.has_feature("mobile") or DisplayServer.get_name() == "headless":
		return
	var want: bool = Profile.settings.get("fullscreen", OS.has_feature("template"))
	if want and not is_fullscreen():
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


## Apply the player's interface size (Settings) or the automatic one.
## `--ui-scale=1.6` on the command line overrides it (handy for testing).
## Symbols used in the UI (arrows, stars, triangles...) come from a bundled
## subset of DejaVu Sans. Desktop systems usually have such a font already,
## but browsers and some phones don't, and showed empty boxes instead.
static func install_symbol_font() -> void:
	var base: Font = ThemeDB.fallback_font
	if base == null or not base.fallbacks.is_empty():
		return
	var symbols := load("res://assets/fonts/DejaVuSans-Symbols.ttf") as Font
	if symbols:
		base.fallbacks = [symbols]


static func apply_ui_scale(tree: SceneTree) -> void:
	install_symbol_font()
	var setting := str(Profile.settings.get("ui_scale", "auto"))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--ui-scale="):
			setting = arg.get_slice("=", 1)
	var factor := auto_ui_scale() if setting == "auto" or not setting.is_valid_float() else clampf(float(setting), 0.75, 2.5)
	tree.root.content_scale_factor = factor


## True on short screens (phones in landscape): screens use tighter layouts.
static func is_compact(node: Node) -> bool:
	var size := node.get_viewport().get_visible_rect().size
	return size.y < 560.0 or size.x < 1100.0


## Extra margins (in UI pixels) that keep content clear of notches and
## rounded corners on phones. Zero on desktop.
static func safe_margins(node: Node) -> Dictionary:
	var out := {"left": 0.0, "top": 0.0, "right": 0.0, "bottom": 0.0}
	if not is_mobile():
		return out
	var safe := DisplayServer.get_display_safe_area()
	var screen := DisplayServer.screen_get_size()
	var view := node.get_viewport().get_visible_rect().size
	if safe.size.x <= 0 or screen.x <= 0:
		return out
	var k := view.x / float(screen.x)
	out["left"] = float(safe.position.x) * k
	out["top"] = float(safe.position.y) * k
	out["right"] = float(screen.x - safe.end.x) * k
	out["bottom"] = float(screen.y - safe.end.y) * k
	return out


## Apply a base margin plus the safe-area insets to a MarginContainer.
static func apply_margins(m: MarginContainer, base: int) -> void:
	var safe := safe_margins(m)
	for side in ["left", "top", "right", "bottom"]:
		m.add_theme_constant_override("margin_" + side, base + int(safe[side]))
