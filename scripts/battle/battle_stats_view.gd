extends VBoxContainer
## Battle Stats (0.9.9): what every squad did in a finished battle (damage,
## kills, healing, damage taken, losses), from BattleSim.battle_stats().
## One side at a time; tap a column heading to sort by it.

const COLUMNS := [
	["damage", "Damage", "Damage dealt to enemies (not counting overkill)"],
	["kills", "Kills", "Enemies finished off"],
	["healing", "Healing", "Health restored to itself and its allies"],
	["taken", "Taken", "Damage it took"],
	["lost", "Lost", "Units lost / units fielded"],
]

var _rows: Array = []
var _local_team := 0
var _side := 0
var _sort := "damage"
var _side_buttons: Array = []
var _grid: GridContainer
var _totals: Label


func setup(stats: Array, local_team: int) -> void:
	_rows = stats
	_local_team = local_team
	_side = local_team


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	var sides := UIKit.hbox(6)
	add_child(sides)
	for t in [_local_team, 1 - _local_team]:
		var b := UIKit.button("Your army" if t == _local_team else "Enemy army", _pick_side.bind(t))
		b.toggle_mode = true
		b.set_meta("team", t)
		sides.add_child(b)
		_side_buttons.append(b)
	sides.add_child(UIKit.spacer())
	_totals = UIKit.label("", 13, UIKit.TEXT_DIM)
	sides.add_child(_totals)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 300)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = 1 + COLUMNS.size()
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 14)
	_grid.add_theme_constant_override("v_separation", 4)
	scroll.add_child(_grid)
	_refresh()


func _pick_side(t: int) -> void:
	_side = t
	_refresh()


func _sort_by(key: String) -> void:
	_sort = key
	_refresh()


func _refresh() -> void:
	for b in _side_buttons:
		b.button_pressed = int(b.get_meta("team")) == _side
	UIKit.clear(_grid)
	var rows := _rows.filter(func(r): return int(r["team"]) == _side)
	var key := _sort
	rows.sort_custom(func(a, b):
		if key == "lost":
			return float(a["lost"]) / maxf(1.0, a["count"]) > float(b["lost"]) / maxf(1.0, b["count"])
		return float(a[key]) > float(b[key]))
	# Headings: tap to sort.
	_grid.add_child(UIKit.label("Squad", 13, UIKit.TEXT_DIM))
	for c in COLUMNS:
		var h := Button.new()
		h.text = c[1] + (" ▼" if c[0] == _sort else "")
		h.flat = true
		h.tooltip_text = c[2] + ". Tap to sort."
		h.add_theme_font_size_override("font_size", 13)
		h.add_theme_color_override("font_color", UIKit.ACCENT if c[0] == _sort else UIKit.TEXT_DIM)
		h.pressed.connect(_sort_by.bind(c[0]))
		_grid.add_child(h)
	var best := {}
	for c in ["damage", "kills", "healing", "taken"]:
		var top := 0.0
		for r in rows:
			top = maxf(top, float(r[c]))
		best[c] = top
	var tot := {"damage": 0.0, "kills": 0, "healing": 0.0, "count": 0, "lost": 0}
	for r in rows:
		_grid.add_child(_name_cell(r, float(r["damage"]) > 0.0 and float(r["damage"]) >= best["damage"]))
		for c in ["damage", "kills", "healing", "taken"]:
			_grid.add_child(_value_cell(float(r[c]), best[c], c))
		var lost := UIKit.label("%d / %d" % [r["lost"], r["count"]], 14, UIKit.BAD if r["lost"] >= r["count"] else Color.WHITE)
		lost.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_grid.add_child(lost)
		for k in ["damage", "kills", "healing", "count", "lost"]:
			tot[k] += r[k]
	if rows.is_empty():
		_grid.add_child(UIKit.label("Nothing to show.", 14, UIKit.TEXT_DIM))
	_totals.text = "Total: %s damage, %d kills, %s healing, %d / %d lost" % [_num(tot["damage"]), tot["kills"], _num(tot["healing"]), tot["lost"], tot["count"]]


func _name_cell(r: Dictionary, mvp: bool) -> Control:
	var h := UIKit.hbox(6)
	h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var uid := str(r["unit"])
	h.add_child(UIKit.unit_icon(uid, 28))
	var v := UIKit.vbox(0)
	var def := GameData.unit(uid)
	var uname := str(def.get("name", uid))
	var col := GameData.rarity_color(str(def.get("rarity", "common"))) if not def.is_empty() else Color.WHITE
	v.add_child(UIKit.label(uname, 14, col))
	var sub := "summoned in battle" if bool(r["summoned"]) else ("champion" if Champion.is_champion(uid) else "x%d" % int(r["count"]))
	v.add_child(UIKit.label(sub, 11, UIKit.TEXT_DIM))
	h.add_child(v)
	if mvp:
		h.add_child(UIKit.label("MVP", 12, UIKit.ACCENT))
	return h


## The number, with a thin bar showing it against the side's best.
func _value_cell(value: float, best_value: float, kind: String) -> Control:
	var v := UIKit.vbox(1)
	v.custom_minimum_size = Vector2(70, 0)
	var l := UIKit.label(str(int(value)) if kind == "kills" else _num(value), 14, Color.WHITE if value > 0.0 else UIKit.TEXT_DIM)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.add_child(l)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(70, 4)
	bar.max_value = maxf(best_value, 1.0)
	bar.value = value
	var fill := StyleBoxFlat.new()
	fill.bg_color = {"damage": Color("e06a4a"), "kills": Color("e0b04a"), "healing": Color("6fdc6f"), "taken": Color("8a9bb8")}[kind]
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(1, 1, 1, 0.08)
	bar.add_theme_stylebox_override("fill", fill)
	bar.add_theme_stylebox_override("background", bg)
	v.add_child(bar)
	return v


static func _num(x: float) -> String:
	if x >= 999_500.0:
		return "%.1fM" % (x / 1_000_000.0)
	if x >= 9_995.0:
		return "%dk" % int(round(x / 1000.0))
	if x >= 1000.0:
		return "%.1fk" % (x / 1000.0)
	return str(int(round(x)))
