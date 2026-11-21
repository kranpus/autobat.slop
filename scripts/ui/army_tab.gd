extends VBoxContainer
## Army builder: choose up to 8 squads, set their battle row and order.
## Squads deploy in order until the 1000-unit army cap is reached.

const ROW_LABELS := {"front": "Front line", "middle": "Middle", "back": "Back line"}

var _list: VBoxContainer
var _summary: Label
var _cap_bar: ProgressBar
var _add_picker: OptionButton
var _add_button: Button
var _code_edit: LineEdit


func _ready() -> void:
	add_theme_constant_override("separation", 10)
	_summary = UIKit.label("", 18, UIKit.ACCENT)
	add_child(_summary)
	_cap_bar = ProgressBar.new()
	_cap_bar.max_value = GameData.ARMY_UNIT_CAP
	_cap_bar.custom_minimum_size = Vector2(0, 18)
	add_child(_cap_bar)
	var tip := UIKit.label("Squads deploy top to bottom until the %d-unit cap. Front line engages first; back line is protected. Ranged units and healers belong in the back." % GameData.ARMY_UNIT_CAP, 13, UIKit.TEXT_DIM)
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(tip)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_list = UIKit.vbox(6)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)

	var add_row := UIKit.hbox(8)
	add_row.add_child(UIKit.label("Add squad:", 15))
	_add_picker = OptionButton.new()
	_add_picker.custom_minimum_size = Vector2(260, 0)
	add_row.add_child(_add_picker)
	_add_button = UIKit.button("Add", _on_add)
	add_row.add_child(_add_button)
	add_row.add_child(UIKit.spacer())
	add_row.add_child(UIKit.button("Auto-build strongest", _auto_build))
	add_child(add_row)

	var code_row := UIKit.hbox(8)
	code_row.add_child(UIKit.label("Army code:", 15))
	_code_edit = LineEdit.new()
	_code_edit.editable = false
	_code_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	code_row.add_child(_code_edit)
	code_row.add_child(UIKit.button("Copy", func():
		DisplayServer.clipboard_set(_code_edit.text)
		Audio.play_sfx("scroll")))
	add_child(code_row)

	Profile.changed.connect(refresh)
	refresh()


func refresh() -> void:
	if not is_inside_tree():
		return
	var squads := Profile.army_squads()
	var counts := Army.deploy_counts(squads)
	var total := Army.total_units(squads)
	_summary.text = "Army: %d / %d units     Power: %s     Squads: %d / %d" % [total, GameData.ARMY_UNIT_CAP, Army.format_power(Army.army_power(squads)), squads.size(), GameData.MAX_SQUADS]
	_cap_bar.value = total
	UIKit.clear(_list)
	if squads.is_empty():
		_list.add_child(UIKit.label("Your army is empty. Add squads below or from the Collection tab.", 15, UIKit.BAD))
	for i in squads.size():
		_list.add_child(_make_row(i, squads[i], int(counts[i])))
	_add_picker.clear()
	var in_army := {}
	for sq in squads:
		in_army[sq["unit"]] = true
	for id in GameData.unit_ids_sorted():
		if Profile.owns(id) and not in_army.has(id):
			_add_picker.add_item("%s  (Lv %d, x%d)" % [GameData.UNITS[id]["name"], int(Profile.unit(id)["level"]), Profile.squad_size(id)])
			_add_picker.set_item_metadata(_add_picker.item_count - 1, id)
	_add_button.disabled = _add_picker.item_count == 0 or squads.size() >= GameData.MAX_SQUADS
	_code_edit.text = Profile.army_code()


func _make_row(index: int, sq: Dictionary, deployed: int) -> Control:
	var p := UIKit.panel(UIKit.PANEL_LIGHT)
	var h := UIKit.hbox(10)
	p.add_child(h)
	var id: String = sq["unit"]
	h.add_child(UIKit.unit_icon(id, 40))
	var v := UIKit.vbox(0)
	v.custom_minimum_size = Vector2(220, 0)
	v.add_child(UIKit.label(GameData.UNITS[id]["name"], 16, GameData.rarity_color(GameData.UNITS[id]["rarity"])))
	var full := Army.squad_size(id, int(sq["tier"]))
	var count_text := "x%d" % deployed
	if deployed < full:
		count_text += "  (cap: %d of %d deploy)" % [deployed, full]
	v.add_child(UIKit.label("Lv %d   %s" % [int(sq["level"]), count_text], 13, UIKit.BAD if deployed < full else UIKit.TEXT_DIM))
	h.add_child(v)
	h.add_child(UIKit.label("Power %s" % Army.format_power(Army.unit_power(id, int(sq["level"])) * float(deployed)), 13, UIKit.ACCENT))
	h.add_child(UIKit.spacer())
	var row_pick := OptionButton.new()
	for r in GameData.ROWS:
		row_pick.add_item(ROW_LABELS[r])
	row_pick.selected = GameData.ROWS.find(sq["row"])
	row_pick.item_selected.connect(func(sel: int):
		var army: Array = Profile.data["army"].duplicate(true)
		army[index]["row"] = GameData.ROWS[sel]
		Profile.set_army(army))
	h.add_child(row_pick)
	var up := UIKit.button("▲", func(): _move(index, -1))
	up.disabled = index == 0
	h.add_child(up)
	var down := UIKit.button("▼", func(): _move(index, 1))
	down.disabled = index >= Profile.data["army"].size() - 1
	h.add_child(down)
	h.add_child(UIKit.button("Remove", func():
		var army: Array = Profile.data["army"].duplicate(true)
		army.remove_at(index)
		Profile.set_army(army)))
	return p


func _move(index: int, dir: int) -> void:
	var army: Array = Profile.data["army"].duplicate(true)
	var j := index + dir
	if j < 0 or j >= army.size():
		return
	var tmp = army[index]
	army[index] = army[j]
	army[j] = tmp
	Profile.set_army(army)


func _on_add() -> void:
	if _add_picker.selected < 0:
		return
	var id: String = _add_picker.get_item_metadata(_add_picker.selected)
	var army: Array = Profile.data["army"].duplicate(true)
	if army.size() >= GameData.MAX_SQUADS:
		return
	army.append({"unit": id, "row": GameData.default_row_for(id)})
	Profile.set_army(army)


## Greedy: pick the owned squads with the best power until slots/cap run out.
func _auto_build() -> void:
	var options: Array = []
	for id in Profile.data["units"]:
		var u := Profile.unit(id)
		options.append({"unit": id, "power": Army.unit_power(id, int(u["level"])) * float(Profile.squad_size(id))})
	options.sort_custom(func(a, b): return float(a["power"]) > float(b["power"]))
	var army: Array = []
	for o in options.slice(0, GameData.MAX_SQUADS):
		army.append({"unit": o["unit"], "row": GameData.default_row_for(o["unit"])})
	Profile.set_army(army)
