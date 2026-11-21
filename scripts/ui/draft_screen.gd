extends Control
## Legion Draft in-match screen: shop, board, trinkets, timer and standings.
##
## Click a shop unit/trinket, then click a board slot to buy it there.
## Click a board unit, then another slot to move, swap or merge duplicates.
## Sell / Freeze act on the current selection. Right-click clears it.

signal leave_requested

const SLOT_DISPLAY_ORDER := [5, 4, 3, 2, 1, 0]   # back row on the left, front row facing the enemy

var _sel_kind := ""        # "", "unit", "trinket", "board"
var _sel_index := -1
var _top_label: Label
var _timer_label: Label
var _board_row: HBoxContainer
var _shop_row: HBoxContainer
var _info: VBoxContainer
var _standings: VBoxContainer
var _log: RichTextLabel
var _msg: Label
var _sell_btn: Button
var _freeze_btn: Button
var _reroll_btn: Button
var _end_btn: Button
var _overlay: PanelContainer
var _overlay_box: VBoxContainer


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UIKit.make_theme()
	var bg := ColorRect.new()
	bg.color = UIKit.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	add_child(margin)
	var root := UIKit.vbox(8)
	margin.add_child(root)

	# Top bar
	var top := UIKit.panel()
	root.add_child(top)
	var th := UIKit.hbox(10)
	top.add_child(th)
	_top_label = UIKit.label("", 17)
	th.add_child(_top_label)
	th.add_child(UIKit.spacer())
	_timer_label = UIKit.label("", 20, UIKit.ACCENT)
	th.add_child(_timer_label)
	_reroll_btn = UIKit.button("Reroll (%dg)" % DraftData.REROLL_COST, _on_reroll)
	th.add_child(_reroll_btn)
	_freeze_btn = UIKit.button("Freeze", _on_freeze)
	th.add_child(_freeze_btn)
	_sell_btn = UIKit.button("Sell", _on_sell)
	th.add_child(_sell_btn)
	_end_btn = UIKit.button("End Turn ▶", func(): Party.submit_turn())
	_end_btn.add_theme_font_size_override("font_size", 18)
	th.add_child(_end_btn)
	th.add_child(UIKit.button("Leave", func(): leave_requested.emit()))

	var body := UIKit.hbox(10)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)
	var main_col := UIKit.vbox(8)
	main_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(main_col)

	main_col.add_child(UIKit.label("Your Legion   (back row  ←→  front row, facing the enemy)", 16, UIKit.ACCENT))
	_board_row = UIKit.hbox(8)
	main_col.add_child(_board_row)
	main_col.add_child(UIKit.label("Shop", 16, UIKit.ACCENT))
	_shop_row = UIKit.hbox(8)
	main_col.add_child(_shop_row)
	_msg = UIKit.label("Click a shop item, then a board slot. Click a unit then another slot to move or merge duplicates. Right-click to cancel.", 13, UIKit.TEXT_DIM)
	_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	main_col.add_child(_msg)
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log.custom_minimum_size = Vector2(0, 80)
	main_col.add_child(_log)

	var side_col := UIKit.vbox(8)
	side_col.custom_minimum_size = Vector2(340, 0)
	body.add_child(side_col)
	var ip := UIKit.panel(UIKit.PANEL_LIGHT)
	ip.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side_col.add_child(ip)
	var iscroll := ScrollContainer.new()
	iscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	ip.add_child(iscroll)
	_info = UIKit.vbox(5)
	_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	iscroll.add_child(_info)
	var sp := UIKit.panel(UIKit.PANEL_LIGHT)
	side_col.add_child(sp)
	_standings = UIKit.vbox(3)
	sp.add_child(_standings)

	# Waiting / results overlay
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_overlay = UIKit.panel(Color(0.08, 0.09, 0.12, 0.95))
	_overlay.custom_minimum_size = Vector2(460, 0)
	center.add_child(_overlay)
	_overlay_box = UIKit.vbox(8)
	_overlay.add_child(_overlay_box)

	Party.shop_started.connect(_on_shop_started)
	Party.standings_changed.connect(refresh)
	Party.match_over.connect(func(_l): refresh())
	refresh()


func _process(_delta: float) -> void:
	if not visible:
		return
	if Party.phase == "shop":
		var left := maxi(0, (Party.turn_deadline_msec - Time.get_ticks_msec()) / 1000)
		@warning_ignore("integer_division")
		_timer_label.text = "%d:%02d" % [left / 60, left % 60]
		_timer_label.add_theme_color_override("font_color", UIKit.BAD if left <= 10 else UIKit.ACCENT)
	else:
		_timer_label.text = ""


func _on_shop_started(_r: int, _s: int) -> void:
	_clear_sel()
	refresh()


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		_clear_sel()
		refresh()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_RIGHT:
		_clear_sel()
		refresh()


func _clear_sel() -> void:
	_sel_kind = ""
	_sel_index = -1


# --- refresh ----------------------------------------------------------------

func refresh() -> void:
	if not is_inside_tree():
		return
	var run := Party.run
	var shopping := Party.phase == "shop" and run != null
	if run != null:
		var tier := run.tier()
		var next := run.battles_to_next_tier()
		var me := Party.me()
		_top_label.text = "Round %d   ·   Shop tier %d%s   ·   Gold %d   ·   Lives %d/%d   ·   Wins %d/%d" % [
			Party.round_num, tier, ("" if next < 0 else " (next in %d)" % next), run.gold,
			int(me.get("lives", run.lives)), int(Party.settings["lives"]), int(me.get("wins", run.wins)), int(Party.settings["wins"])]
	_reroll_btn.disabled = not shopping or run.gold < DraftData.REROLL_COST
	_end_btn.disabled = not shopping
	_sell_btn.disabled = not shopping or _sel_kind != "board"
	_freeze_btn.disabled = not shopping or not (_sel_kind == "unit" or _sel_kind == "trinket")
	_build_board(shopping)
	_build_shop(shopping)
	_build_info()
	_build_standings()
	_build_log()
	_build_overlay()


func _card_style(border: Color, width: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("323748")
	sb.set_corner_radius_all(6)
	sb.set_border_width_all(width)
	sb.border_color = border
	sb.set_content_margin_all(6)
	return sb


func _card(size: Vector2, border: Color, width: int, on_press: Callable) -> Button:
	var b := Button.new()
	b.custom_minimum_size = size
	for st in ["normal", "hover", "pressed", "disabled"]:
		var sb := _card_style(border, width)
		if st == "hover":
			sb.bg_color = Color("3d4357")
		b.add_theme_stylebox_override(st, sb)
	b.pressed.connect(on_press)
	Audio.hook_button(b)
	return b


func _card_content(b: Button) -> VBoxContainer:
	var v := UIKit.vbox(1)
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 6
	v.offset_right = -6
	v.offset_top = 4
	v.offset_bottom = -4
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(v)
	return v


func _centered(l: Label) -> Label:
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return l


func _build_board(shopping: bool) -> void:
	UIKit.clear(_board_row)
	var run := Party.run
	if run == null:
		return
	for slot in SLOT_DISPLAY_ORDER:
		var e: Dictionary = run.board[slot]
		var border := Color("4a5068")
		var width := 2
		if _sel_kind == "board" and _sel_index == slot:
			border = UIKit.ACCENT
			width = 4
		elif shopping and _slot_is_target(slot):
			border = UIKit.GOOD
			width = 3
		var s: int = slot
		var b := _card(Vector2(132, 178), border, width, func(): _on_slot(s))
		var v := _card_content(b)
		v.add_child(_centered(UIKit.label("%s · slot %d" % [String(DraftData.SLOT_ROWS[slot]).capitalize(), slot + 1], 11, UIKit.TEXT_DIM)))
		if e.is_empty():
			v.add_child(_centered(UIKit.label("(empty)", 13, UIKit.TEXT_DIM)))
		else:
			var uid: String = e["unit"]
			var ic := UIKit.unit_icon(uid, 52)
			ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
			ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			v.add_child(ic)
			v.add_child(_centered(UIKit.label(GameData.UNITS[uid]["name"], 12, GameData.rarity_color(GameData.UNITS[uid]["rarity"]))))
			var lvl := DraftData.entry_level(e)
			v.add_child(_centered(UIKit.label("Lv %d  (%s)" % [lvl, DraftData.xp_text(int(e["xp"]))], 11, UIKit.ACCENT)))
			v.add_child(_centered(UIKit.label("x%d  +%d%% HP  +%d%% dmg" % [DraftData.entry_count(e), int(e["hp_b"]), int(e["dmg_b"])], 11)))
			var t := str(e["trinket"])
			if t != "":
				v.add_child(_centered(UIKit.label("◆ " + str(DraftData.TRINKETS[t]["name"]), 11, Color("9fd3ff"))))
			b.tooltip_text = _unit_tooltip(uid, lvl)
		_board_row.add_child(b)


func _slot_is_target(slot: int) -> bool:
	var run := Party.run
	var e: Dictionary = run.board[slot]
	match _sel_kind:
		"unit":
			return run.can_place_unit(run.shop_units[_sel_index]["unit"], slot)
		"trinket":
			return not e.is_empty()
		"board":
			if slot == _sel_index:
				return false
			var from: Dictionary = run.board[_sel_index]
			return e.is_empty() or e["unit"] != from["unit"] or int(e["xp"]) < DraftData.MAX_XP
	return false


func _build_shop(shopping: bool) -> void:
	UIKit.clear(_shop_row)
	var run := Party.run
	if run == null or not shopping:
		_shop_row.add_child(UIKit.label("The shop opens at the start of each round.", 13, UIKit.TEXT_DIM))
		return
	for i in run.shop_units.size():
		var su: Dictionary = run.shop_units[i]
		var uid: String = su["unit"]
		var border := Color("4fa0ff") if bool(su["frozen"]) else Color("4a5068")
		var width := 3 if bool(su["frozen"]) else 2
		if _sel_kind == "unit" and _sel_index == i:
			border = UIKit.ACCENT
			width = 4
		var idx: int = i
		var b := _card(Vector2(118, 150), border, width, func(): _select("unit", idx))
		var v := _card_content(b)
		var ic := UIKit.unit_icon(uid, 48)
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		v.add_child(ic)
		v.add_child(_centered(UIKit.label(GameData.UNITS[uid]["name"], 12, GameData.rarity_color(GameData.UNITS[uid]["rarity"]))))
		v.add_child(_centered(UIKit.label(str(DraftData.ABILITIES[uid]["name"]), 11, UIKit.TEXT_DIM)))
		v.add_child(_centered(UIKit.label("%d gold%s" % [DraftData.UNIT_COST, "  ❄" if bool(su["frozen"]) else ""], 12, Color("ffd76a"))))
		b.tooltip_text = _unit_tooltip(uid, 1)
		_shop_row.add_child(b)
	var sep := VSeparator.new()
	_shop_row.add_child(sep)
	for i in run.shop_trinkets.size():
		var st: Dictionary = run.shop_trinkets[i]
		var tid: String = st["trinket"]
		var tdef: Dictionary = DraftData.TRINKETS[tid]
		var border := Color("4fa0ff") if bool(st["frozen"]) else Color("6a5a3a")
		var width := 3 if bool(st["frozen"]) else 2
		if _sel_kind == "trinket" and _sel_index == i:
			border = UIKit.ACCENT
			width = 4
		var idx: int = i
		var b := _card(Vector2(118, 150), border, width, func(): _select("trinket", idx))
		var v := _card_content(b)
		var ic := UIKit.icon(DraftData.trinket_texture(tid), 44)
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		v.add_child(ic)
		v.add_child(_centered(UIKit.label(tdef["name"], 12, Color("9fd3ff"))))
		v.add_child(_centered(UIKit.label("Tier %d %s" % [int(tdef["tier"]), "trinket" if tdef["kind"] == "equip" else "consumable"], 11, UIKit.TEXT_DIM)))
		v.add_child(_centered(UIKit.label("%d gold%s" % [DraftData.TRINKET_COST, "  ❄" if bool(st["frozen"]) else ""], 12, Color("ffd76a"))))
		b.tooltip_text = "%s: %s" % [tdef["name"], tdef["desc"]]
		_shop_row.add_child(b)


func _unit_tooltip(uid: String, lvl: int) -> String:
	var ab: Dictionary = DraftData.ABILITIES[uid]
	return "%s\n%s\nAbility (%s): %s  (x%d at this level)" % [GameData.UNITS[uid]["name"], GameData.UNITS[uid]["desc"], ab["name"], ab["text"], lvl]


func _build_info() -> void:
	UIKit.clear(_info)
	var run := Party.run
	if run == null:
		return
	var uid := ""
	var entry: Dictionary = {}
	match _sel_kind:
		"unit":
			uid = run.shop_units[_sel_index]["unit"]
		"board":
			entry = run.board[_sel_index]
			uid = entry.get("unit", "")
		"trinket":
			var tid: String = run.shop_trinkets[_sel_index]["trinket"]
			var t: Dictionary = DraftData.TRINKETS[tid]
			var h := UIKit.hbox(8)
			h.add_child(UIKit.icon(DraftData.trinket_texture(tid), 48))
			var hv := UIKit.vbox(0)
			hv.add_child(UIKit.label(t["name"], 18, Color("9fd3ff")))
			hv.add_child(UIKit.label("Tier %d %s" % [int(t["tier"]), "trinket (held)" if t["kind"] == "equip" else "consumable (used at once)"], 12, UIKit.TEXT_DIM))
			h.add_child(hv)
			_info.add_child(h)
			_info.add_child(_wrap(UIKit.label(t["desc"], 14)))
			_info.add_child(_wrap(UIKit.label("Click one of your units to give it this. A unit holds one trinket; a new one replaces the old.", 12, UIKit.TEXT_DIM)))
			return
	if uid == "":
		_info.add_child(UIKit.label("Legion Draft", 18, UIKit.ACCENT))
		_info.add_child(_wrap(UIKit.label("Select a shop item or one of your units to see its details and ability.", 13, UIKit.TEXT_DIM)))
		_info.add_child(_wrap(UIKit.label("Lv2 at 3 copies, Lv3 at 6. Each level: bigger squad and +40% stats. Shop tier %d/%d." % [run.tier(), DraftData.MAX_TIER], 13, UIKit.TEXT_DIM)))
		return
	var def: Dictionary = GameData.UNITS[uid]
	var lvl := DraftData.entry_level(entry) if not entry.is_empty() else 1
	var h := UIKit.hbox(8)
	h.add_child(UIKit.unit_icon(uid, 64))
	var hv := UIKit.vbox(0)
	hv.add_child(UIKit.label(def["name"], 18, GameData.rarity_color(def["rarity"])))
	hv.add_child(UIKit.label("%s %s · Lv %d" % [GameData.RARITIES[def["rarity"]]["name"], String(def["role"]).capitalize(), lvl], 12, UIKit.TEXT_DIM))
	h.add_child(hv)
	_info.add_child(h)
	_info.add_child(_wrap(UIKit.label(def["desc"], 13)))
	var ab: Dictionary = DraftData.ABILITIES[uid]
	_info.add_child(UIKit.label("Ability: %s" % ab["name"], 15, UIKit.ACCENT))
	_info.add_child(_wrap(UIKit.label("%s  (effect x%d at Lv %d)" % [ab["text"], lvl, lvl], 13)))
	var e := entry if not entry.is_empty() else DraftData.new_entry(uid)
	var squads := DraftData.board_to_squads([e])
	var sq: Dictionary = squads[0]
	var s := Army.unit_stats(uid, int(sq["level"]), sq["mods"])
	var g := GridContainer.new()
	g.columns = 4
	g.add_theme_constant_override("h_separation", 10)
	var cd: float = s["cooldown"]
	for pair in [["Units", "x%d" % int(sq["count"])], ["HP", str(roundi(s["hp"]))], ["Damage", str(roundi(s["dmg"]))], ["DPS", "%.1f" % (float(s["dmg"]) / cd)],
			["Range", "Melee" if float(s["range"]) < 20.0 else str(roundi(s["range"]))], ["Speed", str(roundi(s["speed"]))],
			["Type", String(s["damage"]).capitalize()], ["Armor", String(s["armor"]).capitalize()]]:
		g.add_child(UIKit.label(pair[0], 12, UIKit.TEXT_DIM))
		g.add_child(UIKit.label(pair[1], 12))
	_info.add_child(g)
	if not entry.is_empty():
		var t := str(entry["trinket"])
		if t != "":
			_info.add_child(_wrap(UIKit.label("Trinket: %s: %s" % [DraftData.TRINKETS[t]["name"], DraftData.TRINKETS[t]["desc"]], 13, Color("9fd3ff"))))
		_info.add_child(UIKit.label("Sells for %d gold." % lvl, 12, UIKit.TEXT_DIM))
	else:
		_info.add_child(UIKit.label("Costs %d gold. Click a slot to buy it there." % DraftData.UNIT_COST, 12, UIKit.TEXT_DIM))


func _wrap(l: Label) -> Label:
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(300, 0)
	return l


func _build_standings() -> void:
	UIKit.clear(_standings)
	_standings.add_child(UIKit.label("Players", 16, UIKit.ACCENT))
	var ids: Array = Party.players.keys()
	ids.sort_custom(func(a, b):
		var pa: Dictionary = Party.players[a]
		var pb: Dictionary = Party.players[b]
		if int(pa["wins"]) != int(pb["wins"]):
			return int(pa["wins"]) > int(pb["wins"])
		return int(pa["lives"]) > int(pb["lives"]))
	for id in ids:
		var p: Dictionary = Party.players[id]
		var status := ""
		if bool(p["done"]):
			status = "#%d %s" % [int(p["place"]), "★" if int(p["wins"]) >= int(Party.settings["wins"]) else "out"]
		var txt := "%s%s   ♥%d  W%d  %s" % [p["name"], "  (you)" if int(id) == Party.my_id else "", int(p["lives"]), int(p["wins"]), status]
		_standings.add_child(UIKit.label(txt, 13, UIKit.TEXT_DIM if bool(p["done"]) else Color.WHITE))


func _build_log() -> void:
	var run := Party.run
	if run == null:
		_log.text = ""
		return
	var lines: Array = run.log_lines.slice(maxi(0, run.log_lines.size() - 8))
	_log.text = "[color=#9aa0b0]" + "\n".join(PackedStringArray(lines)) + "[/color]"


func _build_overlay() -> void:
	UIKit.clear(_overlay_box)
	var phase := Party.phase
	if phase == "shop":
		_overlay.visible = false
		return
	_overlay.visible = true
	if phase == "over":
		_overlay_box.add_child(UIKit.label("Match Over", 28, UIKit.ACCENT))
		for p in Party.placements:
			var mine := int(p["id"]) == Party.my_id
			_overlay_box.add_child(UIKit.label("#%d  %s   (%d wins, %d lives)%s" % [int(p["place"]), p["name"], int(p["wins"]), int(p["lives"]), "  ← you" if mine else ""], 16, UIKit.GOOD if mine else Color.WHITE))
		var my_place := 0
		for p in Party.placements:
			if int(p["id"]) == Party.my_id:
				my_place = int(p["place"])
		if my_place > 0:
			_overlay_box.add_child(UIKit.label("Rewards added to your collection: gold%s." % (" and a scouting map" if my_place <= maxi(1, ceili(float(Party.placements.size()) / 2.0)) else ""), 13, UIKit.TEXT_DIM))
		_overlay_box.add_child(UIKit.button("Back to menu", func(): leave_requested.emit()))
		return
	var me := Party.me()
	if bool(me.get("done", false)):
		var won := int(me.get("wins", 0)) >= int(Party.settings["wins"])
		_overlay_box.add_child(UIKit.label("You finished #%d!" % int(me["place"]) if won else "Out of lives. You placed #%d." % int(me["place"]), 22, UIKit.GOOD if won else UIKit.BAD))
		_overlay_box.add_child(UIKit.label("Waiting for the remaining players to finish...", 14, UIKit.TEXT_DIM))
		_overlay_box.add_child(UIKit.button("Leave match", func(): leave_requested.emit()))
		return
	if Party.last_outcome >= 0.0:
		var o := Party.last_outcome
		var title := "Victory! +1 win" if o >= 1.0 else ("Defeat. -1 life" if o <= 0.0 else "Draw")
		_overlay_box.add_child(UIKit.label(title, 24, UIKit.GOOD if o >= 1.0 else (UIKit.BAD if o <= 0.0 else UIKit.ACCENT)))
	_overlay_box.add_child(UIKit.label("Waiting for other players...", 18))
	_overlay_box.add_child(UIKit.label("The next shop opens when everyone has finished their turn or watched their battle.", 13, UIKit.TEXT_DIM))


# --- actions ----------------------------------------------------------------

func _select(kind: String, index: int) -> void:
	if _sel_kind == kind and _sel_index == index:
		_clear_sel()
	else:
		_sel_kind = kind
		_sel_index = index
	refresh()


func _on_slot(slot: int) -> void:
	var run := Party.run
	if run == null or Party.phase != "shop":
		return
	match _sel_kind:
		"unit":
			var uid: String = run.shop_units[_sel_index]["unit"]
			var before := run.board[slot].duplicate() as Dictionary
			if run.gold < DraftData.UNIT_COST:
				_say("Not enough gold.")
			elif Party.do_action(["buy_unit", _sel_index, slot]):
				_clear_sel()
				var after: Dictionary = run.board[slot]
				if not before.is_empty() and DraftData.entry_level(after) > DraftData.entry_level(before):
					Audio.play_sfx("gem")
				else:
					Audio.play_sfx("coins")
				_say("Bought %s." % GameData.UNITS[uid]["name"])
			else:
				_say("That slot holds a different unit (or is max level). Pick an empty slot or a matching unit.")
		"trinket":
			if run.gold < DraftData.TRINKET_COST:
				_say("Not enough gold.")
			elif Party.do_action(["buy_trinket", _sel_index, slot]):
				_clear_sel()
				Audio.play_sfx("gem")
			else:
				_say("Give trinkets to a unit on your board.")
		"board":
			if slot == _sel_index:
				_clear_sel()
			elif Party.do_action(["move", _sel_index, slot]):
				_clear_sel()
				Audio.play_sfx("toggle")
		_:
			if not (run.board[slot] as Dictionary).is_empty():
				_sel_kind = "board"
				_sel_index = slot
	refresh()


func _on_sell() -> void:
	if _sel_kind == "board" and Party.do_action(["sell", _sel_index]):
		Audio.play_sfx("coins")
		_clear_sel()
		refresh()


func _on_freeze() -> void:
	if _sel_kind == "unit":
		Party.do_action(["freeze_unit", _sel_index])
	elif _sel_kind == "trinket":
		Party.do_action(["freeze_trinket", _sel_index])
	refresh()


func _on_reroll() -> void:
	if Party.do_action(["reroll"]):
		_clear_sel()
		Audio.play_sfx("scroll")
	refresh()


func _say(text: String) -> void:
	_msg.text = text
