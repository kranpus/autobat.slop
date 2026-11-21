extends VBoxContainer
## Expeditions: spend scouting maps to search regions for specific units.
## Each region has its own drop table, so hunting a particular unit means
## choosing where to look.

var _list: VBoxContainer
var _result_dialog: AcceptDialog
var _result_box: VBoxContainer


func _ready() -> void:
	add_theme_constant_override("separation", 10)
	var intro := UIKit.label("Send scouts into a region to find units. Each expedition yields %d finds: new units join your collection, duplicates become shards for squad upgrades. Maps refill over time and from ranked wins." % GameData.FINDS_PER_EXPEDITION, 14, UIKit.TEXT_DIM)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(intro)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_list = UIKit.vbox(8)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)

	_result_dialog = AcceptDialog.new()
	_result_dialog.title = "Expedition Report"
	_result_dialog.min_size = Vector2i(460, 200)
	_result_box = UIKit.vbox(8)
	_result_dialog.add_child(_result_box)
	add_child(_result_dialog)

	Profile.changed.connect(refresh)
	refresh()


func refresh() -> void:
	if not is_inside_tree():
		return
	UIKit.clear(_list)
	for rid in GameData.REGIONS:
		_list.add_child(_make_region(rid))


func _make_region(rid: String) -> Control:
	var region: Dictionary = GameData.REGIONS[rid]
	var unlocked := Profile.region_unlocked(rid)
	var p := UIKit.panel(UIKit.PANEL_LIGHT)
	var h := UIKit.hbox(14)
	p.add_child(h)
	var tile := UIKit.icon(GameData.tile_texture(region["tile"]), 72)
	h.add_child(tile)
	var v := UIKit.vbox(4)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(UIKit.label(region["name"], 19, UIKit.ACCENT if unlocked else UIKit.TEXT_DIM))
	v.add_child(UIKit.label(region["desc"], 13, UIKit.TEXT_DIM))
	var drops := UIKit.hbox(10)
	var ids: Array = region["drops"].keys()
	ids.sort_custom(func(a, b): return int(region["drops"][a]) > int(region["drops"][b]))
	for id in ids:
		var dv := UIKit.vbox(0)
		var owned := Profile.owns(id)
		var ic := UIKit.unit_icon(id, 36, not owned)
		ic.tooltip_text = "%s (%s)" % [GameData.UNITS[id]["name"] if owned else "Unknown unit", GameData.RARITIES[GameData.UNITS[id]["rarity"]]["name"]]
		dv.add_child(ic)
		var pct := UIKit.label("%.0f%%" % (Profile.drop_chance(rid, id) * 100.0) if Profile.drop_chance(rid, id) >= 0.01 else "<1%", 11, GameData.rarity_color(GameData.UNITS[id]["rarity"]))
		pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		dv.add_child(pct)
		drops.add_child(dv)
	v.add_child(drops)
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
	elif not Profile.can_explore(rid):
		b.disabled = true
		b.tooltip_text = "Not enough scouting maps."
	side.add_child(b)
	h.add_child(side)
	return p


func _explore(rid: String) -> void:
	var res := Profile.explore(rid)
	if res.is_empty():
		return
	UIKit.clear(_result_box)
	_result_box.add_child(UIKit.label("Your scouts return from %s:" % GameData.REGIONS[rid]["name"], 16, UIKit.ACCENT))
	var best_rarity := 0
	for f in res["finds"]:
		var id: String = f["unit"]
		var h := UIKit.hbox(10)
		h.add_child(UIKit.unit_icon(id, 48))
		var v := UIKit.vbox(0)
		v.add_child(UIKit.label(GameData.UNITS[id]["name"], 16, GameData.rarity_color(GameData.UNITS[id]["rarity"])))
		var line := "+%d shards" % int(f["shards"])
		if bool(f["new"]):
			line = "NEW UNIT!  " + line
		v.add_child(UIKit.label(line, 13, UIKit.GOOD if bool(f["new"]) else UIKit.TEXT_DIM))
		h.add_child(v)
		_result_box.add_child(h)
		best_rarity = maxi(best_rarity, int(GameData.RARITIES[GameData.UNITS[id]["rarity"]]["order"]))
	_result_box.add_child(UIKit.label("+%d gold" % int(res["gold"]), 14, Color("ffd76a")))
	Audio.play_sfx("roar" if best_rarity >= 3 else "gem")
	_result_dialog.popup_centered()
