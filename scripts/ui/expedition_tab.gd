extends VBoxContainer
## Expeditions: spend scouting maps to search a region. The scouts come back
## with three different units from that region's drop table and the player
## recruits ONE of them. Each region has its own table, so hunting a specific
## unit means choosing where to look.

var _list: VBoxContainer
var _pity_label: RichTextLabel
var _banner: PanelContainer
var _choice_popup: PopupPanel
var _choice_box: VBoxContainer
var _result_dialog: AcceptDialog
var _result_box: VBoxContainer


func _ready() -> void:
	add_theme_constant_override("separation", 10)
	var intro := UIKit.label("Send scouts into a region. They return with %d different units from that region. Read their descriptions and recruit ONE: a new unit joins your collection, a unit you already own gives shards for squad upgrades. Maps refill over time and from ranked wins." % GameData.FINDS_PER_EXPEDITION, 14, UIKit.TEXT_DIM)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(intro)
	_pity_label = RichTextLabel.new()
	_pity_label.bbcode_enabled = true
	_pity_label.fit_content = true
	_pity_label.scroll_active = false
	add_child(_pity_label)

	# Shown while a recruit choice is waiting (e.g. the window was closed).
	_banner = UIKit.panel(Color("4a3a14"))
	var bh := UIKit.hbox(12)
	_banner.add_child(bh)
	bh.add_child(UIKit.label("Your scouts are waiting: choose a recruit before exploring again.", 15, UIKit.ACCENT))
	bh.add_child(UIKit.spacer())
	bh.add_child(UIKit.button("Choose recruit", _show_choice))
	add_child(_banner)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_list = UIKit.vbox(8)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)

	_choice_popup = PopupPanel.new()
	_choice_popup.theme = UIKit.make_theme()
	_choice_box = UIKit.vbox(10)
	_choice_popup.add_child(_choice_box)
	add_child(_choice_popup)

	_result_dialog = AcceptDialog.new()
	_result_dialog.title = "New Recruit"
	_result_dialog.theme = UIKit.make_theme()
	_result_box = UIKit.vbox(8)
	_result_dialog.add_child(_result_box)
	add_child(_result_dialog)

	Profile.changed.connect(refresh)
	refresh()


func refresh() -> void:
	if not is_inside_tree():
		return
	_banner.visible = Profile.has_pending_choice()
	var parts: Array = []
	for rule in GameData.PITY:
		var r: String = rule["rarity"]
		var left := Profile.pity_remaining(r)
		var when := "on your NEXT expedition" if left <= 1 else "within %d expeditions" % left
		parts.append("[color=#%s]%s%s[/color] %s" % [GameData.RARITIES[r]["color"], GameData.RARITIES[r]["name"], "" if r == "legendary" else "+", when])
	_pity_label.text = "[b]Guaranteed pulls:[/b]  " + "   ·   ".join(PackedStringArray(parts)) + "  [color=#9aa0b0](Legendary only counts in regions that have them)[/color]"
	UIKit.clear(_list)
	for rid in GameData.REGIONS:
		if UnitLocks.is_region_locked(rid):
			continue  # locked by the server: hidden until released
		_list.add_child(_make_region(rid))


func _make_region(rid: String) -> Control:
	var region: Dictionary = GameData.REGIONS[rid]
	var unlocked := Profile.region_unlocked(rid)
	var p := UIKit.panel(UIKit.PANEL_LIGHT)
	var h := UIKit.hbox(14)
	p.add_child(h)
	h.add_child(UIKit.icon(GameData.tile_texture(region["tile"]), 72))
	var v := UIKit.vbox(4)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(UIKit.label(region["name"], 19, UIKit.ACCENT if unlocked else UIKit.TEXT_DIM))
	v.add_child(UIKit.label(region["desc"], 13, UIKit.TEXT_DIM))
	var drops := UIKit.hbox(10)
	var region_drops := GameData.region_drops(rid)
	var ids: Array = region_drops.keys()
	ids.sort_custom(func(a, b): return int(region_drops[a]) > int(region_drops[b]))
	for id in ids:
		var dv := UIKit.vbox(0)
		var owned := Profile.owns(id)
		var ic := UIKit.unit_icon(id, 36, not owned)
		ic.tooltip_text = "%s (%s)\n%.0f%% chance to be offered per expedition" % [GameData.UNITS[id]["name"] if owned else "Unknown unit", GameData.RARITIES[GameData.UNITS[id]["rarity"]]["name"], Profile.drop_chance(rid, id) * 100.0]
		dv.add_child(ic)
		var chance := Profile.drop_chance(rid, id)
		var pct := UIKit.label("%.0f%%" % (chance * 100.0) if chance >= 0.01 else "<1%", 11, GameData.rarity_color(GameData.UNITS[id]["rarity"]))
		pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		dv.add_child(pct)
		drops.add_child(dv)
	v.add_child(drops)
	v.add_child(UIKit.label("% = chance the unit is among the 3 offered", 11, UIKit.TEXT_DIM))
	h.add_child(v)
	var side := UIKit.vbox(6)
	side.alignment = BoxContainer.ALIGNMENT_CENTER
	var cost := int(region["cost_maps"])
	side.add_child(UIKit.label("Cost: %d map%s" % [cost, "s" if cost > 1 else ""], 14))
	var b := UIKit.button("Explore", func(): _explore(rid))
	b.custom_minimum_size = Vector2(130, 40)
	if not unlocked:
		b.text = "Needs %d rating" % int(region["min_rating"])
		b.disabled = true
	elif Profile.has_pending_choice():
		b.disabled = true
		b.tooltip_text = "Choose your waiting recruit first."
	elif not Profile.can_explore(rid):
		b.disabled = true
		b.tooltip_text = "Not enough scouting maps."
	side.add_child(b)
	h.add_child(side)
	return p


func _explore(rid: String) -> void:
	if Profile.explore(rid).is_empty():
		return
	Audio.play_sfx("scroll")
	_show_choice()


func _show_choice() -> void:
	var pc := Profile.pending_choice()
	if pc.is_empty():
		return
	UIKit.clear(_choice_box)
	var region_name: String = GameData.REGIONS[pc["region"]]["name"] if GameData.REGIONS.has(pc["region"]) else "the wilds"
	_choice_box.add_child(UIKit.label("Your scouts return from %s" % region_name, 22, UIKit.ACCENT))
	_choice_box.add_child(UIKit.label("Three units answered the call (+%d gold found). Recruit ONE:" % int(pc["gold"]), 15, UIKit.TEXT_DIM))
	var row := UIKit.hbox(12)
	_choice_box.add_child(row)
	var best_rarity := 0
	for i in pc["options"].size():
		var opt: Dictionary = pc["options"][i]
		row.add_child(_make_choice_card(i, opt["unit"], int(opt["shards"]), bool(opt.get("guaranteed", false))))
		best_rarity = maxi(best_rarity, int(GameData.RARITIES[GameData.UNITS[opt["unit"]]["rarity"]]["order"]))
	if best_rarity >= 3:
		Audio.play_sfx("roar")
	_choice_popup.popup_centered(Vector2i(980, 520))


func _make_choice_card(index: int, id: String, shards: int, guaranteed: bool = false) -> Control:
	var def: Dictionary = GameData.UNITS[id]
	var color := GameData.rarity_color(def["rarity"])
	var owned := Profile.owns(id)
	var p := UIKit.panel(UIKit.PANEL_LIGHT)
	p.custom_minimum_size = Vector2(300, 0)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := UIKit.vbox(6)
	p.add_child(v)

	var head := UIKit.hbox(10)
	head.add_child(UIKit.unit_icon(id, 72))
	var hv := UIKit.vbox(2)
	hv.add_child(UIKit.label(def["name"], 18, color))
	hv.add_child(UIKit.label("%s %s" % [GameData.RARITIES[def["rarity"]]["name"], String(def["role"]).capitalize()], 13, UIKit.TEXT_DIM))
	if guaranteed:
		v.add_child(UIKit.label("★ GUARANTEED PULL", 13, UIKit.ACCENT))
	if owned:
		var u := Profile.unit(id)
		hv.add_child(UIKit.label("Owned: Lv %d, squad x%d" % [int(u["level"]), Profile.squad_size(id)], 13, UIKit.TEXT_DIM))
	else:
		hv.add_child(UIKit.label("NEW UNIT!", 14, UIKit.GOOD))
	head.add_child(hv)
	v.add_child(head)

	var desc := UIKit.label(def["desc"], 14)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(desc)
	var role_l := UIKit.label(_role_text(id), 13, UIKit.TEXT_DIM)
	role_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(role_l)

	var s := Army.unit_stats(id, 1)
	var cd: float = s["cooldown"]
	var g := GridContainer.new()
	g.columns = 4
	g.add_theme_constant_override("h_separation", 10)
	for pair in [
		["HP", str(roundi(s["hp"]))], ["DPS", "%.1f" % (float(s["dmg"]) / cd)],
		["Range", "Melee" if float(s["range"]) < 20.0 else str(roundi(s["range"]))], ["Speed", str(roundi(s["speed"]))],
		["Damage", String(s["damage"]).capitalize()], ["Armor", String(s["armor"]).capitalize()],
		["Squad", "x%d" % Army.squad_size(id, 0)], ["Special", _special_text(s)],
	]:
		g.add_child(UIKit.label(pair[0], 12, UIKit.TEXT_DIM))
		g.add_child(UIKit.label(pair[1], 12))
	v.add_child(g)

	var reward := "Unlocks the unit + %d shards" % shards if not owned else "+%d shards toward a bigger squad" % shards
	v.add_child(UIKit.label(reward, 13, UIKit.ACCENT))
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(spacer)
	var b := UIKit.button("Recruit %s" % def["name"], func(): _choose(index))
	b.custom_minimum_size = Vector2(0, 40)
	v.add_child(b)
	return p


func _role_text(id: String) -> String:
	var def: Dictionary = GameData.UNITS[id]
	var strong: Array = []
	var weak: Array = []
	var row: Array = GameData.DAMAGE_MULT[GameData.DAMAGE_TYPES.find(def["damage"])]
	for a in GameData.ARMOR_TYPES.size():
		if float(row[a]) >= 1.15:
			strong.append(GameData.ARMOR_TYPES[a])
		elif float(row[a]) <= 0.75:
			weak.append(GameData.ARMOR_TYPES[a])
	var text := "Best placed in the %s row." % GameData.default_row_for(id)
	if not strong.is_empty():
		text += " Strong vs %s armor." % ", ".join(PackedStringArray(strong))
	if not weak.is_empty():
		text += " Weak vs %s armor." % ", ".join(PackedStringArray(weak))
	return text


func _special_text(s: Dictionary) -> String:
	var parts: Array = []
	if bool(s["flying"]):
		parts.append("Flying")
	if float(s["aoe"]) > 0.0:
		parts.append("Splash")
	if float(s["heal"]) > 0.0:
		parts.append("Heals")
	if float(s["regen"]) > 0.0:
		parts.append("Regen")
	return "-" if parts.is_empty() else ", ".join(PackedStringArray(parts))


func _choose(index: int) -> void:
	var res := Profile.choose_recruit(index)
	_choice_popup.hide()
	if res.is_empty():
		return
	var id: String = res["unit"]
	UIKit.clear(_result_box)
	var h := UIKit.hbox(12)
	h.add_child(UIKit.unit_icon(id, 64))
	var v := UIKit.vbox(2)
	v.add_child(UIKit.label(GameData.UNITS[id]["name"], 18, GameData.rarity_color(GameData.UNITS[id]["rarity"])))
	if bool(res["new"]):
		v.add_child(UIKit.label("Joined your collection! (+%d shards)" % int(res["shards"]), 14, UIKit.GOOD))
		v.add_child(UIKit.label("Add it to your army in the Army or Collection tab.", 13, UIKit.TEXT_DIM))
	else:
		v.add_child(UIKit.label("+%d shards" % int(res["shards"]), 14, UIKit.ACCENT))
	h.add_child(v)
	_result_box.add_child(h)
	Audio.play_sfx("gem")
	_result_dialog.popup_centered()
