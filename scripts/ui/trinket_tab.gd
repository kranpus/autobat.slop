extends VBoxContainer
## Expeditions -> Trinkets: spend scouting maps on trinket hunts, pick one of
## three trinkets, and browse the collection of all 100. Trinkets are equipped
## (two per unit) from the Collection tab.

const LootReveal := preload("res://scripts/ui/loot_reveal.gd")

var _header: Label
var _banner: PanelContainer
var _sites: VBoxContainer
var _grid: GridContainer
var _info: Label
var _choice_popup: PopupPanel
var _choice_box: VBoxContainer
var _result_dialog: AcceptDialog
var _result_box: VBoxContainer


func _ready() -> void:
	add_theme_constant_override("separation", 10)
	var intro := UIKit.label("Send hunters after trinkets. Each hunt turns up %d different trinkets and you keep ONE. There are %d unique trinkets to collect; each unit can carry %d of them (equip them in the Collection tab). A trinket you already own is sold for gold instead." % [3, Trinkets.ALL.size(), Trinkets.SLOTS], 14, UIKit.TEXT_DIM)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(intro)

	_banner = UIKit.panel(Color("4a3a14"))
	var bh := UIKit.hbox(12)
	_banner.add_child(bh)
	bh.add_child(UIKit.label("Your hunters are back: pick a trinket before hunting again.", 15, UIKit.ACCENT))
	bh.add_child(UIKit.spacer())
	bh.add_child(UIKit.button("Choose trinket", func(): _show_choice(false)))
	add_child(_banner)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var body := UIKit.vbox(10)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	_sites = UIKit.vbox(8)
	body.add_child(_sites)
	_header = UIKit.label("", 18, UIKit.ACCENT)
	body.add_child(_header)
	_info = UIKit.label("Hover or tap a trinket to see what it does.", 13, UIKit.TEXT_DIM)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(_info)
	_grid = GridContainer.new()
	_grid.add_theme_constant_override("h_separation", 6)
	_grid.add_theme_constant_override("v_separation", 6)
	_grid.columns = 8
	body.add_child(_grid)
	# Cells are ~96 px wide plus 6 px spacing; never ask for more than fit.
	scroll.resized.connect(func(): _grid.columns = clampi(int((scroll.size.x - 16.0) / 104.0), 3, 14))

	_choice_popup = PopupPanel.new()
	_choice_popup.theme = UIKit.make_theme()
	_choice_box = UIKit.vbox(10)
	_choice_popup.add_child(_choice_box)
	add_child(_choice_popup)
	_result_dialog = AcceptDialog.new()
	_result_dialog.title = "Trinket Found"
	_result_dialog.theme = UIKit.make_theme()
	_result_box = UIKit.vbox(8)
	_result_dialog.add_child(_result_box)
	add_child(_result_dialog)

	Profile.changed.connect(refresh)
	Profile.trinket_choice_ready.connect(func(_c: Dictionary):
		Audio.play_sfx("scroll")
		_show_choice(true))
	Profile.trinket_result.connect(_show_result)
	refresh()


func refresh() -> void:
	if not is_inside_tree():
		return
	_banner.visible = Profile.has_pending_trinket()
	UIKit.clear(_sites)
	for site_id in Trinkets.SITES:
		_sites.add_child(_make_site(site_id))
	_header.text = "Trinket collection: %d / %d" % [Profile.trinket_count(), Trinkets.ALL.size()]
	UIKit.clear(_grid)
	var ids: Array = Trinkets.ALL.keys()
	ids.sort_custom(func(a, b):
		var ra := Trinkets.RARITY_ORDER.find(Trinkets.rarity_of(a))
		var rb := Trinkets.RARITY_ORDER.find(Trinkets.rarity_of(b))
		return ra < rb if ra != rb else str(Trinkets.ALL[a]["name"]) < str(Trinkets.ALL[b]["name"]))
	for id in ids:
		_grid.add_child(_make_cell(id))


func _make_site(site_id: String) -> Control:
	var site: Dictionary = Trinkets.SITES[site_id]
	var unlocked := Profile.trinket_site_unlocked(site_id)
	var p := UIKit.panel(UIKit.PANEL_LIGHT)
	var h := UIKit.hbox(14)
	p.add_child(h)
	h.add_child(UIKit.icon(GameData.tile_texture(site["tile"]), 64))
	var v := UIKit.vbox(4)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(UIKit.label(site["name"], 18, UIKit.ACCENT if unlocked else UIKit.TEXT_DIM))
	var d := UIKit.label(site["desc"], 13, UIKit.TEXT_DIM)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(d)
	var odds := RichTextLabel.new()
	odds.bbcode_enabled = true
	odds.fit_content = true
	odds.scroll_active = false
	odds.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var parts: Array = []
	var chances := Trinkets.site_odds(site_id)
	for r in Trinkets.RARITY_ORDER:
		if float(chances[r]) > 0.0:
			parts.append("[color=#%s]%s %d%%[/color]" % [GameData.RARITIES[r]["color"], GameData.RARITIES[r]["name"], roundi(float(chances[r]) * 100.0)])
	odds.text = "[font_size=12]Each trinket offered:  " + "  ·  ".join(PackedStringArray(parts)) + "[/font_size]"
	v.add_child(odds)
	h.add_child(v)
	var side := UIKit.vbox(6)
	side.alignment = BoxContainer.ALIGNMENT_CENTER
	var cost := int(site["cost_maps"])
	side.add_child(UIKit.label("Cost: %d map%s" % [cost, "s" if cost > 1 else ""], 14))
	var b := UIKit.button("Hunt", func(): _hunt(site_id))
	b.custom_minimum_size = Vector2(130, 40)
	UIKit.tut(b, "trinket_hunt")
	if not unlocked:
		b.text = "Needs %d rating" % int(site["min_rating"])
		b.disabled = true
	elif Profile.has_pending_trinket():
		b.disabled = true
		b.tooltip_text = "Pick your waiting trinket first."
	elif not Profile.can_hunt_trinkets(site_id):
		b.disabled = true
		b.tooltip_text = "Not enough scouting maps."
	side.add_child(b)
	h.add_child(side)
	return p


func _make_cell(id: String) -> Control:
	var owned := Profile.owns_trinket(id)
	var t: Dictionary = Trinkets.ALL[id]
	var color := GameData.rarity_color(t["rarity"])
	var b := UIKit.panel(UIKit.PANEL_LIGHT if owned else Color("2b303d"))
	b.custom_minimum_size = Vector2(96, 92)
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	var v := UIKit.vbox(2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	var ic := UIKit.icon(Trinkets.texture(id), 44)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not owned:
		ic.modulate = Color(0, 0, 0, 0.8)
	v.add_child(ic)
	var nl := UIKit.label(t["name"] if owned else "???", 10, color if owned else Color(color, 0.6))
	nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nl.clip_text = true
	nl.custom_minimum_size = Vector2(76, 0)
	nl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(nl)
	var holder := Profile.trinket_holder(id) if owned else ""
	if holder != "":
		var hl := UIKit.label("on " + str(GameData.UNITS[holder]["name"]), 9, UIKit.TEXT_DIM)
		hl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hl.clip_text = true
		hl.custom_minimum_size = Vector2(76, 0)
		hl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(hl)
	b.add_child(v)
	var text := describe(id, owned)
	b.tooltip_text = text
	b.gui_input.connect(func(e: InputEvent):
		if (e is InputEventMouseButton and e.pressed) or (e is InputEventScreenTouch and e.pressed):
			_info.text = text)
	return b


## Text for a trinket: name, rarity, effect, and who holds it.
static func describe(id: String, owned: bool = true) -> String:
	var t: Dictionary = Trinkets.ALL[id]
	var rarity: String = GameData.RARITIES[t["rarity"]]["name"]
	if not owned:
		return "??? (%s trinket, not found yet)" % rarity
	var holder := Profile.trinket_holder(id)
	var where := ("Carried by %s." % GameData.UNITS[holder]["name"]) if holder != "" else "Not equipped."
	return "%s (%s): %s %s" % [t["name"], rarity, t["desc"], where]


func _hunt(site_id: String) -> void:
	if Profile.online:
		Profile.hunt_trinkets(site_id)   # the choice arrives through trinket_choice_ready
		return
	if Profile.hunt_trinkets(site_id).is_empty():
		return
	Audio.play_sfx("scroll")
	_show_choice(true)


## The trinket choice, revealed loot-box style first when `animate`.
func _show_choice(animate: bool) -> void:
	var pt := Profile.pending_trinket()
	if pt.is_empty():
		return
	UIKit.clear(_choice_box)
	if animate:
		var reveal := LootReveal.new()
		reveal.setup_trinkets(str(pt["site"]), pt["options"], UIKit.is_compact(self))
		reveal.finished.connect(func():
			if _choice_popup.visible:
				_build_choice(pt))
		_choice_box.add_child(reveal)
		_choice_popup.popup_centered(Vector2i(900, 460))
		return
	_build_choice(pt)
	_choice_popup.popup_centered(Vector2i(900, 460))


func _build_choice(pt: Dictionary) -> void:
	if not Profile.has_pending_trinket():
		return
	UIKit.clear(_choice_box)
	var site_name: String = Trinkets.SITES[pt["site"]]["name"] if Trinkets.SITES.has(pt["site"]) else "the ruins"
	_choice_box.add_child(UIKit.label("Your hunters return from %s" % site_name, 22, UIKit.ACCENT))
	_choice_box.add_child(UIKit.label("Three trinkets were found. Keep ONE:", 15, UIKit.TEXT_DIM))
	var row := UIKit.hbox(12)
	_choice_box.add_child(row)
	for i in pt["options"].size():
		row.add_child(_make_choice_card(i, pt["options"][i]))


func _make_choice_card(index: int, id: String) -> Control:
	var t: Dictionary = Trinkets.ALL[id]
	var color := GameData.rarity_color(t["rarity"])
	var owned := Profile.owns_trinket(id)
	var p := UIKit.panel(UIKit.PANEL_LIGHT)
	p.custom_minimum_size = Vector2(270, 0)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := UIKit.vbox(6)
	p.add_child(v)
	var head := UIKit.hbox(10)
	head.add_child(UIKit.icon(Trinkets.texture(id), 64))
	var hv := UIKit.vbox(2)
	hv.add_child(UIKit.label(t["name"], 18, color))
	hv.add_child(UIKit.label("%s trinket" % GameData.RARITIES[t["rarity"]]["name"], 13, UIKit.TEXT_DIM))
	if owned:
		hv.add_child(UIKit.label("Already owned: +%d gold" % int(Trinkets.DUPLICATE_GOLD[t["rarity"]]), 13, UIKit.ACCENT))
	else:
		hv.add_child(UIKit.label("NEW TRINKET!", 14, UIKit.GOOD))
	head.add_child(hv)
	v.add_child(head)
	var desc := UIKit.label(t["desc"], 14)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(desc)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(spacer)
	var b := UIKit.button(("Sell for %d gold" % int(Trinkets.DUPLICATE_GOLD[t["rarity"]])) if owned else ("Take %s" % t["name"]), func(): _choose(index))
	b.custom_minimum_size = Vector2(0, 40)
	v.add_child(b)
	return p


func _choose(index: int) -> void:
	var res := Profile.choose_trinket(index)
	_choice_popup.hide()
	if not res.is_empty():
		_show_result(res)   # offline; online it arrives through trinket_result


func _show_result(res: Dictionary) -> void:
	if res.is_empty() or not Trinkets.exists(str(res.get("trinket", ""))):
		return
	var id: String = res["trinket"]
	var t: Dictionary = Trinkets.ALL[id]
	UIKit.clear(_result_box)
	var h := UIKit.hbox(12)
	h.add_child(UIKit.icon(Trinkets.texture(id), 64))
	var v := UIKit.vbox(2)
	v.add_child(UIKit.label(t["name"], 18, GameData.rarity_color(t["rarity"])))
	if bool(res.get("new", false)):
		v.add_child(UIKit.label("Added to your trinkets!", 14, UIKit.GOOD))
		v.add_child(UIKit.label("Equip it on a unit in the Collection tab.", 13, UIKit.TEXT_DIM))
	else:
		v.add_child(UIKit.label("You already had it: sold for %d gold." % int(res.get("gold", 0)), 14, UIKit.ACCENT))
	h.add_child(v)
	_result_box.add_child(h)
	Audio.play_sfx("gem")
	_result_dialog.popup_centered()
