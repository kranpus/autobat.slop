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
var _add_picker: OptionButton
var _add_button: Button
var _code_edit: LineEdit


func _ready() -> void:
	add_theme_constant_override("separation", 10)
	_summary = UIKit.label("", 18, UIKit.ACCENT)
	add_child(_summary)
	var compact := UIKit.is_compact(self)
	var tip := UIKit.label("Every squad fights at full size. Drag squads between columns (or use ◀ ▶) to choose where they fight; ▲ ▼ set the order within a column. Your army deploys on the left of the battlefield, so the Front line column faces the enemy.", 13, UIKit.TEXT_DIM)
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.visible = not compact   # phones: room goes to the columns
	add_child(tip)

	var cols := UIKit.hbox(10)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(cols)
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

	var add_row := UIKit.hbox(8)
	add_row.add_child(UIKit.label("Add squad:", 15))
	_add_picker = OptionButton.new()
	_add_picker.custom_minimum_size = Vector2(260, 0)
	add_row.add_child(_add_picker)
	_add_button = UIKit.button("Add", _on_add)
	_add_button.tooltip_text = "Added to the column that suits the unit's role; drag it elsewhere if you like."
	add_row.add_child(_add_button)
	add_row.add_child(UIKit.spacer())
	add_row.add_child(UIKit.button("Auto-build" if compact else "Auto-build strongest", _auto_build))
	if compact:
		add_row.add_child(UIKit.button("Copy army code", func():
			DisplayServer.clipboard_set(Profile.army_code())
			Audio.play_sfx("scroll")))
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
	code_row.visible = not compact
	add_child(code_row)

	Profile.changed.connect(refresh)
	refresh()


func refresh() -> void:
	if not is_inside_tree():
		return
	var squads := Profile.army_squads()
	var counts := Army.deploy_counts(squads)
	_summary.text = "Army: %d units     Power: %s     Squads: %d / %d" % [Army.total_units(squads), Army.format_power(Army.army_power(squads)), squads.size(), GameData.MAX_SQUADS]
	for row in COLUMNS:
		var list: VBoxContainer = _columns[row]["list"]
		UIKit.clear(list)
		var units := 0
		var power := 0.0
		var indexes: Array = []
		for i in squads.size():
			if squads[i]["row"] == row:
				indexes.append(i)
				units += int(counts[i])
				power += Army.unit_power(squads[i]["unit"], int(squads[i]["level"])) * float(counts[i])
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


func _make_card(index: int, sq: Dictionary, deployed: int, first: bool, last: bool) -> Control:
	var p := UIKit.panel(UIKit.PANEL)
	p.mouse_default_cursor_shape = Control.CURSOR_DRAG
	p.set_drag_forwarding(_drag_squad.bind(index), _can_drop_squad, _drop_on_card.bind(index))
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
	info.add_child(UIKit.label("Lv %d · x%d · Power %s" % [int(sq["level"]), deployed, Army.format_power(Army.unit_power(id, int(sq["level"])) * float(deployed))], 12, UIKit.TEXT_DIM))
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
	return typeof(data) == TYPE_DICTIONARY and data.has("army_index")


func _drop_on_column(_at: Vector2, data: Variant, row: String) -> void:
	_move_squad(int(data["army_index"]), row, -1)


func _drop_on_card(_at: Vector2, data: Variant, target: int) -> void:
	var from := int(data["army_index"])
	if from == target:
		return
	_move_squad(from, str(Profile.data["army"][target]["row"]), target)


# --- adding -------------------------------------------------------------------

func _on_add() -> void:
	if _add_picker.selected < 0:
		return
	var id: String = _add_picker.get_item_metadata(_add_picker.selected)
	var army: Array = Profile.data["army"].duplicate(true)
	if army.size() >= GameData.MAX_SQUADS:
		return
	army.append({"unit": id, "row": GameData.default_row_for(id)})
	Profile.set_army(army)


## Greedy: pick the owned squads with the best power until the slots run out.
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
