extends VBoxContainer
## Army builder laid out like the battlefield: three columns, Back | Middle |
## Front (the front line faces the enemy on the right, as in battle).
## Up to 8 squads. Move squads between columns with the arrow buttons or by
## dragging; ▲ ▼ change their order inside a column (top deploys first).

const COLUMNS := ["back", "middle", "front"]
const COLUMN_INFO := {
	"back": {"title": "Back line", "hint": "Protected. Archers, casters and healers."},
	"middle": {"title": "Middle", "hint": "Second wave. Mobile ranged and flankers."},
	"front": {"title": "Front line", "hint": "Engages first. Tanks and melee."},
}

var _summary: Label
var _columns := {}        # row -> {"list": VBoxContainer, "header": Label}
var _reserves: HBoxContainer
var _reserve_scroll: ScrollContainer
var _reserve_note: Label


func _ready() -> void:
	add_theme_constant_override("separation", 10)
	_summary = UIKit.label("", 18, UIKit.ACCENT)
	add_child(_summary)
	var compact := UIKit.is_compact(self)
	var tip := UIKit.label("Drag squads between columns (or use ◀ ▶) to choose where they fight; ▲ ▼ set the order. Your army deploys on the left, so the Front line faces the enemy.", 13, UIKit.TEXT_DIM)
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.visible = not compact   # phones: room goes to the columns
	add_child(tip)

	var cols := UIKit.hbox(10)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(cols)
	UIKit.tut(cols, "army_columns")
	for row in COLUMNS:
		var r: String = row
		var panel := UIKit.panel(UIKit.PANEL_LIGHT)
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		panel.size_flags_stretch_ratio = 1.0
		# Drop a squad anywhere on the column to move it to this row.
		panel.set_drag_forwarding(Callable(), _can_drop_squad, _drop_on_column.bind(r))
		cols.add_child(panel)
		var v := UIKit.vbox(6)
		panel.add_child(v)
		v.add_child(UIKit.label(COLUMN_INFO[r]["title"], 18, UIKit.ACCENT))
		var header := UIKit.label("", 13, Color.WHITE)
		v.add_child(header)
		var hint := UIKit.label(COLUMN_INFO[r]["hint"], 12, UIKit.TEXT_DIM)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(hint)
		var scroll := ScrollContainer.new()
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.mouse_filter = Control.MOUSE_FILTER_PASS   # let drops reach the column
		v.add_child(scroll)
		var list := UIKit.vbox(6)
		list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		list.mouse_filter = Control.MOUSE_FILTER_PASS
		scroll.add_child(list)
		_columns[r] = {"list": list, "header": header}

	# Reserves: owned units not in the army. Tap to add, or drag into a column.
	var res_panel := UIKit.panel(UIKit.PANEL)
	var rv := UIKit.vbox(4)
	res_panel.add_child(rv)
	var rhead := UIKit.hbox(8)
	rhead.add_child(UIKit.label("Reserves", 15, UIKit.ACCENT))
	_reserve_note = UIKit.label("", 12, UIKit.TEXT_DIM)
	rhead.add_child(_reserve_note)
	rhead.add_child(UIKit.spacer())
	var auto := UIKit.accent_button("Auto-build strongest", _auto_build, 15)
	auto.custom_minimum_size = Vector2(0, 36)
	auto.tooltip_text = "Fill the army with your strongest squads, each in the column that suits it."
	UIKit.tut(auto, "auto_build")
	rhead.add_child(auto)
	rhead.add_child(UIKit.button("Copy army code", func():
		DisplayServer.clipboard_set(Profile.army_code())
		Audio.play_sfx("scroll")
		UIKit.toast("Army code copied: friends can fight it from their Battle tab")))
	rv.add_child(rhead)
	var rscroll := ScrollContainer.new()
	rscroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rscroll.custom_minimum_size = Vector2(0, 66 if compact else 74)
	rv.add_child(rscroll)
	_reserve_scroll = rscroll
	_reserves = UIKit.hbox(6)
	rscroll.add_child(_reserves)
	add_child(res_panel)

	Profile.changed.connect(refresh)
	refresh()


func refresh() -> void:
	if not is_inside_tree():
		return
	var squads := Profile.army_squads()
	var counts := Army.deploy_counts(squads)
	var deploy := Profile.battle_squads()
	_summary.text = "Army: %d units     Power: %s     Squads: %d / %d" % [Army.total_units(deploy), Army.format_power(Army.army_power(deploy)), squads.size(), GameData.MAX_SQUADS]
	for row in COLUMNS:
		var list: VBoxContainer = _columns[row]["list"]
		UIKit.clear(list)
		var units := 0
		var power := 0.0
		var indexes: Array = []
		for i in squads.size():
			if squads[i]["row"] == row:
				indexes.append(i)
				if UnitLocks.is_locked(squads[i]["unit"]):
					continue  # locked squads don't deploy
				units += int(counts[i])
				power += Army.squad_power(squads[i]["unit"], int(squads[i]["level"]), int(counts[i]), Army.squad_mods(squads[i]))
		(_columns[row]["header"] as Label).text = "%d squad%s · %d units · Power %s" % [indexes.size(), "" if indexes.size() == 1 else "s", units, Army.format_power(power)]
		if indexes.is_empty():
			var empty := UIKit.label("Drop squads here", 13, UIKit.TEXT_DIM)
			empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			empty.custom_minimum_size = Vector2(0, 60)
			empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			empty.mouse_filter = Control.MOUSE_FILTER_PASS
			list.add_child(empty)
		for k in indexes.size():
			var i: int = indexes[k]
			list.add_child(_make_card(i, squads[i], int(counts[i]), k == 0, k == indexes.size() - 1))
	UIKit.clear(_reserves)
	var in_army := {}
	for sq in squads:
		in_army[sq["unit"]] = true
	var full := squads.size() >= GameData.MAX_SQUADS
	var spare := 0
	for id in GameData.unit_ids_sorted():
		if Profile.owns(id) and not in_army.has(id) and not UnitLocks.is_locked(id):
			_reserves.add_child(_make_reserve(id, full))
			spare += 1
	_reserve_scroll.visible = spare > 0
	if spare == 0:
		_reserve_note.text = "Every unit you own is in the army. Recruit more on Expeditions."
	elif full:
		_reserve_note.text = "Army full (%d squads): remove one (✕) to make room." % GameData.MAX_SQUADS
	else:
		_reserve_note.text = "Tap a unit to add it, or drag it into a column."


func _make_card(index: int, sq: Dictionary, deployed: int, first: bool, last: bool) -> Control:
	var p := UIKit.panel(UIKit.PANEL)
	p.mouse_default_cursor_shape = Control.CURSOR_DRAG
	p.set_drag_forwarding(_drag_squad.bind(index), _can_drop_squad, _drop_on_card.bind(index))
	p.set_meta("drag_source", true)   # touch scrolling: only along the list
	var v := UIKit.vbox(4)
	p.add_child(v)
	var id: String = sq["unit"]
	var h := UIKit.hbox(8)
	h.add_child(UIKit.unit_icon(id, 40))
	var info := UIKit.vbox(0)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name_l := UIKit.label(GameData.UNITS[id]["name"], 15, GameData.rarity_color(GameData.UNITS[id]["rarity"]))
	name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	info.add_child(name_l)
	if UnitLocks.is_locked(id):
		info.add_child(UIKit.label("⊘ Locked by server: won't deploy", 12, UIKit.BAD))
	else:
		info.add_child(UIKit.label("Lv %d · x%d · Power %s" % [int(sq["level"]), deployed, Army.format_power(Army.squad_power(id, int(sq["level"]), deployed, Army.squad_mods(sq)))], 12, UIKit.TEXT_DIM))
	h.add_child(info)
	v.add_child(h)
	var buttons := UIKit.hbox(4)
	var col := COLUMNS.find(sq["row"])
	var left := _small_button("◀", "Move toward the back", func(): _set_row(index, COLUMNS[col - 1]))
	left.disabled = col <= 0
	buttons.add_child(left)
	var right := _small_button("▶", "Move toward the front", func(): _set_row(index, COLUMNS[col + 1]))
	right.disabled = col >= COLUMNS.size() - 1
	buttons.add_child(right)
	var up := _small_button("▲", "Deploy earlier in this column", func(): _shift_in_row(index, -1))
	up.disabled = first
	buttons.add_child(up)
	var down := _small_button("▼", "Deploy later in this column", func(): _shift_in_row(index, 1))
	down.disabled = last
	buttons.add_child(down)
	buttons.add_child(UIKit.spacer())
	buttons.add_child(_small_button("✕", "Remove from army", func():
		var army: Array = Profile.data["army"].duplicate(true)
		army.remove_at(index)
		Profile.set_army(army)))
	v.add_child(buttons)
	return p


func _small_button(text: String, tip: String, callback: Callable) -> Button:
	var b := UIKit.button(text, callback)
	b.tooltip_text = tip
	b.custom_minimum_size = Vector2(34, 0)
	return b


# --- army edits ---------------------------------------------------------------

func _set_row(index: int, row: String) -> void:
	var army: Array = Profile.data["army"].duplicate(true)
	if index < 0 or index >= army.size():
		return
	army[index]["row"] = row
	Profile.set_army(army)


## Swap with the previous/next squad in the same column.
func _shift_in_row(index: int, dir: int) -> void:
	var army: Array = Profile.data["army"].duplicate(true)
	var row: String = army[index]["row"]
	var j := index + dir
	while j >= 0 and j < army.size() and army[j]["row"] != row:
		j += dir
	if j < 0 or j >= army.size():
		return
	var tmp = army[index]
	army[index] = army[j]
	army[j] = tmp
	Profile.set_army(army)


## Move squad `from` to `row`, placed just before squad `before` (or last).
func _move_squad(from: int, row: String, before: int) -> void:
	var army: Array = Profile.data["army"].duplicate(true)
	if from < 0 or from >= army.size():
		return
	var sq: Dictionary = army[from]
	sq["row"] = row
	army.remove_at(from)
	if before < 0:
		army.append(sq)
	else:
		if before > from:
			before -= 1
		army.insert(clampi(before, 0, army.size()), sq)
	Profile.set_army(army)
	Audio.play_sfx("toggle", -6.0)


# --- drag and drop ------------------------------------------------------------

func _drag_squad(_at: Vector2, index: int) -> Variant:
	var army: Array = Profile.data["army"]
	if index >= army.size():
		return null
	var preview := Control.new()
	var ic := UIKit.unit_icon(army[index]["unit"], 48)
	ic.position = Vector2(-24, -24)
	ic.modulate = Color(1, 1, 1, 0.85)
	preview.add_child(ic)
	set_drag_preview(preview)
	return {"army_index": index}


func _can_drop_squad(_at: Vector2, data: Variant) -> bool:
	return typeof(data) == TYPE_DICTIONARY and (data.has("army_index") or data.has("reserve_unit"))


func _drop_on_column(_at: Vector2, data: Variant, row: String) -> void:
	if data.has("reserve_unit"):
		_add_unit(str(data["reserve_unit"]), row)
		return
	_move_squad(int(data["army_index"]), row, -1)


func _drop_on_card(_at: Vector2, data: Variant, target: int) -> void:
	if data.has("reserve_unit"):
		_add_unit(str(data["reserve_unit"]), str(Profile.data["army"][target]["row"]))
		return
	var from := int(data["army_index"])
	if from == target:
		return
	_move_squad(from, str(Profile.data["army"][target]["row"]), target)


# --- adding -------------------------------------------------------------------

func _make_reserve(id: String, full: bool) -> Control:
	var b := Button.new()
	b.custom_minimum_size = Vector2(150, 0)
	b.disabled = full
	b.tooltip_text = "%s: Lv %d, %d units. %s" % [GameData.UNITS[id]["name"], int(Profile.unit(id)["level"]), Profile.squad_size(id), "Army full." if full else "Tap to add to the %s." % COLUMN_INFO[GameData.default_row_for(id)]["title"].to_lower()]
	b.pressed.connect(func(): _add_unit(id, GameData.default_row_for(id)))
	b.set_meta("drag_source", true)
	b.set_drag_forwarding(func(_at: Vector2) -> Variant:
		if full:
			return null
		var preview := Control.new()
		var ic := UIKit.unit_icon(id, 48)
		ic.position = Vector2(-24, -24)
		preview.add_child(ic)
		set_drag_preview(preview)
		return {"reserve_unit": id}, Callable(), Callable())
	Audio.hook_button(b)
	var h := UIKit.hbox(6)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 4)
	var ic := UIKit.unit_icon(id, 40)
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(ic)
	var v := UIKit.vbox(0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var n := UIKit.label(GameData.UNITS[id]["name"], 13, GameData.rarity_color(GameData.UNITS[id]["rarity"]))
	n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	n.custom_minimum_size = Vector2(96, 0)
	v.add_child(n)
	v.add_child(UIKit.label("Lv %d · x%d" % [int(Profile.unit(id)["level"]), Profile.squad_size(id)], 11, UIKit.TEXT_DIM))
	h.add_child(v)
	b.add_child(h)
	b.custom_minimum_size.y = 56
	return b


func _add_unit(id: String, row: String) -> void:
	var army: Array = Profile.data["army"].duplicate(true)
	if army.size() >= GameData.MAX_SQUADS:
		return
	for sq in army:
		if sq["unit"] == id:
			return
	army.append({"unit": id, "row": row})
	Profile.set_army(army)
	Audio.play_sfx("toggle", -6.0)


## Greedy: pick the owned squads with the best power until the slots run out.
func _auto_build() -> void:
	var options: Array = []
	for id in Profile.data["units"]:
		var u := Profile.unit(id)
		options.append({"unit": id, "power": Army.squad_power(id, int(u["level"]), Profile.squad_size(id))})
	options.sort_custom(func(a, b): return float(a["power"]) > float(b["power"]))
	var army: Array = []
	for o in options.slice(0, GameData.MAX_SQUADS):
		army.append({"unit": o["unit"], "row": GameData.default_row_for(o["unit"])})
	Profile.set_army(army)
	UIKit.toast("Army built from your %d strongest squads" % army.size(), UIKit.GOOD)
