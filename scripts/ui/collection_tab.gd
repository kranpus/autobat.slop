extends HBoxContainer
## Collection: browse every unit, see where to find locked ones, and spend
## gold/shards on levels (stats) and squad tiers (unit quantity).

var _grid: GridContainer
var _detail: VBoxContainer
var _selected := ""


func _ready() -> void:
	add_theme_constant_override("separation", 12)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_grid = GridContainer.new()
	# Start with as many columns as fit next to the details panel.
	var detail_w := 310.0 if UIKit.is_compact(self) else 400.0
	_grid.columns = clampi(int((get_viewport_rect().size.x - detail_w - 120.0) / 136.0), 2, 8)
	_grid.add_theme_constant_override("h_separation", 8)
	_grid.add_theme_constant_override("v_separation", 8)
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_grid)
	# Fit as many card columns as the width allows (phones get fewer).
	scroll.resized.connect(func(): _grid.columns = clampi(int(scroll.size.x / 136.0), 2, 8))

	var dp := UIKit.panel(UIKit.PANEL_LIGHT)
	dp.custom_minimum_size = Vector2(310 if UIKit.is_compact(self) else 400, 0)
	add_child(dp)
	var dscroll := ScrollContainer.new()
	dscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	dp.add_child(dscroll)
	_detail = UIKit.vbox(8)
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dscroll.add_child(_detail)

	_selected = GameData.STARTER_UNITS[0]
	Profile.changed.connect(refresh)
	refresh()


func refresh() -> void:
	if not is_inside_tree():
		return
	UIKit.clear(_grid)
	if UnitLocks.is_locked(_selected) and not Profile.owns(_selected):
		_selected = GameData.STARTER_UNITS[0]
	for id in GameData.unit_ids_sorted():
		# Locked units stay hidden unless you already own one.
		if UnitLocks.is_locked(id) and not Profile.owns(id):
			continue
		_grid.add_child(_make_card(id))
	_build_detail()


func _make_card(id: String) -> Control:
	var owned := Profile.owns(id)
	var def: Dictionary = GameData.UNITS[id]
	var b := Button.new()
	b.custom_minimum_size = Vector2(128, 120)
	b.toggle_mode = true
	b.button_pressed = id == _selected
	b.pressed.connect(func():
		_selected = id
		refresh())
	Audio.hook_button(b)
	var v := UIKit.vbox(2)
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(v)
	var ic := UIKit.unit_icon(id, 56, not owned)
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(ic)
	var name_l := UIKit.label(def["name"] if owned else "???", 13, GameData.rarity_color(def["rarity"]))
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	v.add_child(name_l)
	var info := "Lv %d  ·  x%d" % [int(Profile.unit(id)["level"]), Profile.squad_size(id)] if owned else "Not found"
	var info_l := UIKit.label(info, 12, UIKit.TEXT_DIM)
	info_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(info_l)
	if UnitLocks.is_locked(id):
		var lk := UIKit.label("🔒 locked by server", 11, UIKit.BAD)
		lk.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(lk)
	elif owned and (Profile.can_tier_up(id) or Profile.can_level_up(id)):
		var up := UIKit.label("▲ upgrade ready", 11, UIKit.GOOD)
		up.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(up)
	return b


func _build_detail() -> void:
	UIKit.clear(_detail)
	var id := _selected
	var def: Dictionary = GameData.UNITS[id]
	var owned := Profile.owns(id)
	var rarity: Dictionary = GameData.RARITIES[def["rarity"]]

	var head := UIKit.hbox(12)
	head.add_child(UIKit.unit_icon(id, 64 if UIKit.is_compact(self) else 96, not owned))
	var hv := UIKit.vbox(2)
	hv.add_child(UIKit.label(def["name"], 22, GameData.rarity_color(def["rarity"])))
	hv.add_child(UIKit.label("%s %s" % [rarity["name"], String(def["role"]).capitalize()], 14, UIKit.TEXT_DIM))
	var desc := UIKit.label(def["desc"], 13)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(170 if UIKit.is_compact(self) else 240, 0)
	hv.add_child(desc)
	head.add_child(hv)
	_detail.add_child(head)

	if UnitLocks.is_locked(id):
		var note := UIKit.label("🔒 Locked by the server: this unit can't be found or deployed until it's unlocked. You keep it and its upgrades.", 13, UIKit.BAD)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.custom_minimum_size = Vector2(240, 0)
		_detail.add_child(note)
	if not owned:
		_detail.add_child(UIKit.label("You haven't found this unit yet.", 15, UIKit.BAD))
		_detail.add_child(UIKit.label("Where to find it:", 14, UIKit.ACCENT))
		for rid in GameData.REGIONS:
			if GameData.region_drops(rid).has(id):
				_detail.add_child(UIKit.label("  • %s: %.1f%% chance to be offered per expedition" % [GameData.REGIONS[rid]["name"], Profile.drop_chance(rid, id) * 100.0], 14))
		_add_stats(id, 1)
		return

	var u := Profile.unit(id)
	var level := int(u["level"])
	var tier := int(u["tier"])
	var cap := Profile.level_cap(id)
	_detail.add_child(UIKit.label("Level %d / %d     Squad tier %d / %d" % [level, cap, tier, GameData.MAX_TIER], 16, UIKit.ACCENT))
	_add_stats(id, level)

	# Level up
	var lvl_box := UIKit.vbox(4)
	if level < cap:
		var nxt := Army.unit_stats(id, level + 1)
		var cur := Army.unit_stats(id, level)
		lvl_box.add_child(UIKit.label("Next level: HP %d → %d, Damage %d → %d" % [roundi(cur["hp"]), roundi(nxt["hp"]), roundi(cur["dmg"]), roundi(nxt["dmg"])], 13, UIKit.TEXT_DIM))
		var b := UIKit.button("Level Up  (%d gold)" % Profile.level_up_cost(id), func():
			if Profile.level_up(id):
				Audio.play_sfx("coins"))
		b.disabled = not Profile.can_level_up(id)
		lvl_box.add_child(b)
	else:
		lvl_box.add_child(UIKit.label("Level cap reached. Upgrade the squad tier to raise it (+%d levels)." % GameData.LEVELS_PER_TIER, 13, UIKit.TEXT_DIM))
	_detail.add_child(lvl_box)

	# Quantity (squad tier)
	var size_now := Profile.squad_size(id)
	_detail.add_child(UIKit.label("Squad size: %d units" % size_now, 16, Color.WHITE))
	var shard_bar := ProgressBar.new()
	shard_bar.show_percentage = false
	shard_bar.custom_minimum_size = Vector2(0, 14)
	var tier_box := UIKit.vbox(4)
	if tier < GameData.MAX_TIER:
		var cost := Profile.tier_up_cost(id)
		var size_next := Army.squad_size(id, tier + 1)
		shard_bar.max_value = int(cost["shards"])
		shard_bar.value = mini(int(u["shards"]), int(cost["shards"]))
		tier_box.add_child(UIKit.label("Shards: %d / %d  (find more on expeditions)" % [int(u["shards"]), int(cost["shards"])], 13, UIKit.TEXT_DIM))
		tier_box.add_child(shard_bar)
		var b2 := UIKit.button("Upgrade Squad → %d units  (%d shards, %d gold)" % [size_next, int(cost["shards"]), int(cost["gold"])], func():
			if Profile.tier_up(id):
				Audio.play_sfx("gem"))
		b2.disabled = not Profile.can_tier_up(id)
		tier_box.add_child(b2)
	else:
		tier_box.add_child(UIKit.label("Max squad tier! Shards: %d" % int(u["shards"]), 13, UIKit.GOOD))
	_detail.add_child(tier_box)

	_detail.add_child(UIKit.label("Squad power: %s" % Army.format_power(Army.unit_power(id, level) * float(size_now)), 14, UIKit.ACCENT))

	# Army membership
	var in_army := false
	for sq in Profile.data["army"]:
		if sq["unit"] == id:
			in_army = true
	if in_army:
		_detail.add_child(UIKit.button("Remove from Army", func():
			var army: Array = []
			for sq in Profile.data["army"]:
				if sq["unit"] != id:
					army.append(sq)
			Profile.set_army(army)))
	else:
		var add := UIKit.button("Add to Army", func():
			var army: Array = Profile.data["army"].duplicate()
			army.append({"unit": id, "row": GameData.default_row_for(id)})
			Profile.set_army(army))
		add.disabled = Profile.data["army"].size() >= GameData.MAX_SQUADS or UnitLocks.is_locked(id)
		_detail.add_child(add)


func _add_stats(id: String, level: int) -> void:
	var s := Army.unit_stats(id, level)
	var g := GridContainer.new()
	g.columns = 4
	g.add_theme_constant_override("h_separation", 14)
	var cd: float = s["cooldown"]
	var rows := [
		["HP", str(roundi(s["hp"]))],
		["Damage", str(roundi(s["dmg"]))],
		["Attack every", "%.1fs" % cd],
		["DPS", "%.1f" % (float(s["dmg"]) / cd)],
		["Range", "Melee" if float(s["range"]) < 20.0 else str(roundi(s["range"]))],
		["Speed", str(roundi(s["speed"]))],
		["Damage type", String(s["damage"]).capitalize()],
		["Armor", String(s["armor"]).capitalize()],
	]
	if float(s["aoe"]) > 0.0:
		rows.append(["Splash radius", str(roundi(s["aoe"]))])
	if float(s["heal"]) > 0.0:
		rows.append(["Heal", str(roundi(s["heal"]))])
	if float(s["regen"]) > 0.0:
		rows.append(["Regen/s", str(roundi(s["regen"]))])
	if bool(s["flying"]):
		rows.append(["Flying", "Yes"])
	for r in rows:
		g.add_child(UIKit.label(r[0], 13, UIKit.TEXT_DIM))
		g.add_child(UIKit.label(r[1], 13))
	_detail.add_child(g)
