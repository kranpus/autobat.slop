extends VBoxContainer
## The champion (0.9.9): portrait, name, stats and ability; equipment and
## appearance; and the Altar, where sigils are spent on random unlocks.

const ROW_CHOICES := ["", "front", "middle", "back"]

var _body: Control
var _result_label: Label
var _last_result := {}


func _ready() -> void:
	add_theme_constant_override("separation", 10)
	Profile.changed.connect(refresh)
	Profile.champion_rolled.connect(_show_roll)
	visibility_changed.connect(func():
		if is_visible_in_tree():
			refresh())
	refresh()


func refresh() -> void:
	if not is_inside_tree():
		return
	UIKit.clear(self)
	var top := UIKit.hbox(12)
	top.add_child(UIKit.label("Champion", 22, UIKit.ACCENT))
	top.add_child(UIKit.spacer())
	top.add_child(UIKit.label("Sigils: %d" % Profile.sigils(), 18, Color("c9a7ff")))
	add_child(top)
	if not Profile.has_champion():
		var lock := UIKit.label("Your champion joins you at commander level %d: a hero to lead your army, with its own looks, stats, abilities and champion-only equipment, all won at the Altar. (You're level %d; see the Quests tab.)" % [Progression.unlock_level("champion"), Profile.player_level()], 15, UIKit.TEXT_DIM)
		lock.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		add_child(lock)
		return
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var cols: BoxContainer = UIKit.hbox(14) if not UIKit.is_compact(self) else UIKit.vbox(14)
	cols.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(cols)
	var c := Profile.champion()
	cols.add_child(_hero_column(c))
	cols.add_child(_gear_column(c))
	cols.add_child(_altar_column(c))


# --- the champion ---------------------------------------------------------------------------

func _hero_column(c: Dictionary) -> Control:
	var p := UIKit.panel(UIKit.PANEL)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := UIKit.vbox(8)
	p.add_child(v)
	var portrait := TextureRect.new()
	portrait.texture = Champion.texture(c["look"], c["equipped"])
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	portrait.custom_minimum_size = Vector2(160, 160)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	v.add_child(portrait)
	var name_row := UIKit.hbox(6)
	var name_edit := LineEdit.new()
	name_edit.text = str(c["name"])
	name_edit.max_length = Champion.MAX_NAME
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.text_submitted.connect(func(t: String): Profile.champion_rename(t))
	name_row.add_child(name_edit)
	name_row.add_child(UIKit.button("Rename", func(): Profile.champion_rename(name_edit.text)))
	v.add_child(name_row)
	var cls := Champion.weapon_class(c)
	v.add_child(UIKit.label("%s champion" % {"melee": "Melee", "ranged": "Ranged", "caster": "Spellcasting"}[cls], 14, UIKit.TEXT_DIM))
	var row_box := UIKit.hbox(6)
	row_box.add_child(UIKit.label("Fights in:", 14))
	var row_pick := OptionButton.new()
	for r in ROW_CHOICES:
		row_pick.add_item("Auto (%s)" % Champion.row_of({"equipped": c["equipped"]}).capitalize() if r == "" else "%s line" % r.capitalize())
	row_pick.selected = ROW_CHOICES.find(str(c.get("row", "")))
	row_pick.item_selected.connect(func(i: int): Profile.champion_set_row(ROW_CHOICES[i]))
	row_box.add_child(row_pick)
	v.add_child(row_box)
	# Stats
	var sq := Champion.to_squad(Champion.battle_data(c, Profile.player_level()))
	var s := Army.unit_stats(sq["unit"], int(sq["level"]), sq["mods"])
	v.add_child(UIKit.label("HP %d   Damage %d   Attacks every %.2fs   Speed %d%s" % [roundi(s["hp"]), roundi(s["dmg"]), float(s["cooldown"]), roundi(s["speed"]),
		"   Range %d" % roundi(s["range"]) if float(s["range"]) >= 20.0 else ""], 13, Color.WHITE))
	v.add_child(UIKit.label("Grows with your commander level (now %d)." % Profile.player_level(), 12, UIKit.TEXT_DIM))
	var g := GridContainer.new()
	g.columns = 3
	g.add_theme_constant_override("h_separation", 10)
	for k in Champion.STAT_ORDER:
		g.add_child(UIKit.label(Champion.STATS[k]["name"], 14, UIKit.ACCENT))
		g.add_child(UIKit.label("%d / %d" % [int(c["stats"][k]), Champion.MAX_STAT], 14))
		var t := UIKit.label(Champion.STATS[k]["text"], 11, UIKit.TEXT_DIM)
		t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		t.custom_minimum_size = Vector2(150, 0)
		g.add_child(t)
	v.add_child(g)
	# Abilities: three slots
	v.add_child(UIKit.label("Abilities", 16, UIKit.ACCENT))
	var owned: Array = c["abilities"]
	var slots: Array = c["slots"]
	for k in Champion.ABILITY_SLOTS:
		var row := UIKit.hbox(6)
		row.add_child(UIKit.label("%d." % (k + 1), 14, UIKit.TEXT_DIM))
		var pick := OptionButton.new()
		pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var ids: Array = [""]
		pick.add_item("(empty)")
		for a in owned:
			pick.add_item(Champion.ABILITIES[a]["name"] + ("  (slot %d)" % (slots.find(a) + 1) if slots.has(a) and slots.find(a) != k else ""))
			ids.append(a)
		pick.selected = maxi(0, ids.find(str(slots[k])))
		var slot_i: int = k
		pick.item_selected.connect(func(i: int): Profile.champion_set_slot(slot_i, ids[i]))
		row.add_child(pick)
		v.add_child(row)
		if str(slots[k]) != "":
			var t := UIKit.label(Champion.ABILITIES[slots[k]]["text"], 12, UIKit.TEXT_DIM)
			t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			v.add_child(t)
	v.add_child(UIKit.label("%d of %d abilities found" % [owned.size(), Champion.ABILITIES.size()], 12, UIKit.TEXT_DIM))
	return p


# --- equipment and looks -----------------------------------------------------------------

func _gear_column(c: Dictionary) -> Control:
	var p := UIKit.panel(UIKit.PANEL)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := UIKit.vbox(6)
	p.add_child(v)
	v.add_child(UIKit.label("Equipment", 18, UIKit.ACCENT))
	v.add_child(UIKit.label("%d of %d pieces found" % [(c["items"] as Array).size(), Champion.ITEMS.size()], 12, UIKit.TEXT_DIM))
	for slot in Champion.SLOTS:
		var h := UIKit.hbox(8)
		var eq := str(c["equipped"].get(slot, ""))
		var ic := TextureRect.new()
		ic.texture = Champion.item_texture(eq) if eq != "" else null
		ic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		ic.custom_minimum_size = Vector2(36, 36)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		h.add_child(ic)
		var lv := UIKit.vbox(0)
		lv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lv.add_child(UIKit.label(Champion.SLOT_NAMES[slot], 12, UIKit.TEXT_DIM))
		var pick := OptionButton.new()
		var ids: Array = []
		if slot != "weapon":
			pick.add_item("None")
			ids.append("")
		for id in c["items"]:
			if Champion.ITEMS[id]["slot"] == slot:
				pick.add_item("%s (%s)" % [Champion.ITEMS[id]["name"], Champion.ITEMS[id]["rarity"]])
				ids.append(id)
		pick.selected = maxi(0, ids.find(eq))
		pick.item_selected.connect(func(i: int): Profile.champion_equip(slot, ids[i]))
		pick.tooltip_text = _mods_text(Champion.ITEMS[eq]["mods"]) if eq != "" else ""
		lv.add_child(pick)
		if eq != "":
			lv.add_child(UIKit.label(_mods_text(Champion.ITEMS[eq]["mods"]), 11, GameData.rarity_color(Champion.ITEMS[eq]["rarity"])))
		h.add_child(lv)
		v.add_child(h)
	v.add_child(UIKit.label("Appearance", 18, UIKit.ACCENT))
	for part in Champion.LOOKS:
		var h := UIKit.hbox(8)
		var l := UIKit.label(Champion.LOOK_NAMES[part], 14)
		l.custom_minimum_size = Vector2(70, 0)
		h.add_child(l)
		var pick := OptionButton.new()
		var vals: Array = []
		if part != "race":
			pick.add_item("None")
			vals.append("")
		for val in c["looks"][part]:
			pick.add_item(Champion.look_name(part, val))
			vals.append(val)
		pick.selected = maxi(0, vals.find(str(c["look"].get(part, ""))))
		pick.item_selected.connect(func(i: int): Profile.champion_set_look(part, vals[i]))
		pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(pick)
		h.add_child(UIKit.label("%d/%d" % [(c["looks"][part] as Array).size(), (Champion.LOOKS[part] as Array).size()], 11, UIKit.TEXT_DIM))
		v.add_child(h)
	return p


func _mods_text(m: Dictionary) -> String:
	var parts: Array = []
	for k in m:
		var val = m[k]
		match k:
			"hp_mult":
				parts.append("+%d%% HP" % roundi((float(val) - 1.0) * 100.0))
			"dmg_mult":
				parts.append("+%d%% damage" % roundi((float(val) - 1.0) * 100.0))
			"cooldown_mult":
				parts.append("attacks %d%% %s" % [absi(roundi((1.0 / float(val) - 1.0) * 100.0)), "faster" if float(val) < 1.0 else "slower"])
			"speed_mult":
				parts.append("%+d%% speed" % roundi((float(val) - 1.0) * 100.0))
			"range_add":
				parts.append("+%d range" % roundi(float(val)))
			"lifesteal":
				parts.append("heals %d%% of damage" % roundi(float(val) * 100.0))
			"thorns":
				parts.append("%d%% thorns" % roundi(float(val) * 100.0))
			"regen_pct":
				parts.append("regenerates %s%% HP/s" % str(snappedf(float(val) * 100.0, 0.1)))
	return ", ".join(PackedStringArray(parts))


# --- the Altar ----------------------------------------------------------------------------------

func _altar_column(c: Dictionary) -> Control:
	var p := UIKit.parchment_panel(18.0)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := UIKit.vbox(8)
	p.add_child(v)
	v.add_child(ScrollUnroll.ink("The Altar", 22, FantasySkin.INK))
	var intro := ScrollUnroll.ink("Offer a sigil and the Altar grants your champion something at random: a stat point (%d%%), a piece of equipment (%d%%), a new look (%d%%) or an ability (%d%%). It never gives what you already have." % [
		Champion.ROLL_ODDS["stat"], Champion.ROLL_ODDS["item"], Champion.ROLL_ODDS["look"], Champion.ROLL_ODDS["ability"]], 13, FantasySkin.INK_DIM)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(intro)
	v.add_child(ScrollUnroll.ink("You have %d sigil%s." % [Profile.sigils(), "" if Profile.sigils() == 1 else "s"], 16, FantasySkin.INK))
	var roll := ScrollUnroll.seal_button("Offer a sigil", _roll)
	roll.disabled = Profile.sigils() < 1
	roll.custom_minimum_size = Vector2(0, 46)
	v.add_child(roll)
	var buy := UIKit.button("Buy a sigil (%d gold)" % Champion.SIGIL_GOLD, func():
		if Profile.buy_sigil():
			Audio.play_sfx("coins"))
	buy.disabled = Profile.gold() < Champion.SIGIL_GOLD
	v.add_child(buy)
	var earn := ScrollUnroll.ink("Earn sigils: 2 per commander level, 1 per daily quest, 3 per weekly quest, 2 per story quest (5 for every fifth).", 12, FantasySkin.INK_DIM)
	earn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(earn)
	v.add_child(ScrollUnroll.rule())
	_result_label = ScrollUnroll.ink("", 16, FantasySkin.INK_GOOD)
	_result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var last: Dictionary = _last_result if not _last_result.is_empty() else c.get("last_roll", {})
	_result_label.text = ("Last offering: " + str(last.get("text", ""))) if not last.is_empty() else "No offerings yet."
	v.add_child(_result_label)
	v.add_child(ScrollUnroll.ink("Offerings made: %d" % int(c.get("rolls", 0)), 12, FantasySkin.INK_DIM))
	return p


func _roll() -> void:
	var res := Profile.champion_roll()
	if not res.is_empty():
		_show_roll(res)


func _show_roll(res: Dictionary) -> void:
	_last_result = res
	Audio.play_sfx("fanfare" if res.get("kind", "") in ["ability", "item"] else "gem")
	UIKit.toast("The Altar grants: %s" % str(res.get("text", "")), Color("c9a7ff"))
	refresh()
