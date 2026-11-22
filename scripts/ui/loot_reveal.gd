extends VBoxContainer
## Loot-box style reveal for an expedition's three finds (units) or a trinket
## hunt's three trinkets.
##
## Every slot spins through everything that could be found there, slowing
## down until it lands on the real find. Slots stop one after another from the
## least rare find to the rarest, so the best pull always comes last.
## Things the player hasn't found yet flash past as silhouettes.

signal finished

const SPIN_FIRST := 1.3        # seconds the first (least rare) slot spins
const SPIN_STEP := 0.85        # each later slot spins this much longer
const RARE_SUSPENSE := 0.6     # extra wait before an epic/legendary lands
const TICK_FAST := 0.045       # seconds per unit at full speed
const TICK_SLOW := 0.34        # ...just before stopping
const END_PAUSE := 1.0         # admire the result before the full cards appear

var _pool: Array = []
var _slots: Array = []
var _t := 0.0
var _end_at := -1.0
var _finished := false
var _skip: Button


var _compact := false
var _trinkets := false   # revealing trinkets instead of units


## Units from an expedition: options are [{unit, shards, guaranteed}].
func setup(region_id: String, options: Array, compact: bool = false) -> void:
	var pool: Array = GameData.region_drops(region_id).keys() if GameData.REGIONS.has(region_id) else []
	var opts: Array = []
	for o in options:
		opts.append({"id": o["unit"], "guaranteed": bool(o.get("guaranteed", false))})
	var region_name: String = GameData.REGIONS[region_id]["name"] if GameData.REGIONS.has(region_id) else "the wilds"
	_begin("Your scouts return from %s..." % region_name, pool, opts, compact)


## Trinkets from a hunt: `ids` are the three trinkets offered.
func setup_trinkets(site_id: String, ids: Array, compact: bool = false) -> void:
	_trinkets = true
	var pool: Array = []
	if Trinkets.SITES.has(site_id):
		var weights := Trinkets.site_weights(site_id)
		for t in Trinkets.ALL:
			if float(weights.get(Trinkets.rarity_of(t), 0.0)) > 0.0:
				pool.append(t)
	var opts: Array = []
	for t in ids:
		opts.append({"id": t, "guaranteed": false})
	var site_name: String = Trinkets.SITES[site_id]["name"] if Trinkets.SITES.has(site_id) else "the ruins"
	_begin("Your hunters return from %s..." % site_name, pool, opts, compact)


func _begin(title_text: String, pool: Array, options: Array, compact: bool) -> void:
	_compact = compact
	add_theme_constant_override("separation", 16)
	alignment = BoxContainer.ALIGNMENT_CENTER
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_pool = pool
	for o in options:
		if not _pool.has(o["id"]):
			_pool.append(o["id"])
	_pool.shuffle()

	var title := UIKit.label(title_text, 18 if compact else 22, UIKit.ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)

	var row := UIKit.hbox(8 if compact else 14)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(row)

	# Reveal order: least rare first; equal rarities keep their card order.
	var order: Array = range(options.size())
	order.sort_custom(func(a, b):
		var ra := _rarity_order(options[a]["id"])
		var rb := _rarity_order(options[b]["id"])
		return ra < rb if ra != rb else a < b)
	var stops := {}
	var t := SPIN_FIRST
	for rank in order.size():
		var i: int = order[rank]
		if rank > 0:
			t += SPIN_STEP
			if _rarity_order(options[i]["id"]) >= 3:
				t += RARE_SUSPENSE
		stops[i] = t

	for i in options.size():
		var slot := _make_slot(options[i], float(stops[i]))
		row.add_child(slot["panel"])
		_slots.append(slot)

	_skip = UIKit.button("Skip", _reveal_all)
	_skip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_skip.custom_minimum_size = Vector2(140, 36)
	add_child(_skip)


func _rarity(id: String) -> String:
	return Trinkets.rarity_of(id) if _trinkets else str(GameData.UNITS[id]["rarity"])


func _rarity_order(id: String) -> int:
	return int(GameData.RARITIES[_rarity(id)]["order"])


func _texture(id: String) -> Texture2D:
	return Trinkets.texture(id) if _trinkets else GameData.unit_texture(id)


func _name(id: String) -> String:
	return str(Trinkets.ALL[id]["name"]) if _trinkets else str(GameData.UNITS[id]["name"])


func _owned(id: String) -> bool:
	return Profile.owns_trinket(id) if _trinkets else Profile.owns(id)


func _make_slot(opt: Dictionary, stop_at: float) -> Dictionary:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = UIKit.PANEL_LIGHT
	style.set_corner_radius_all(8)
	style.set_border_width_all(3)
	style.border_color = Color(1, 1, 1, 0.15)
	style.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", style)
	panel.custom_minimum_size = Vector2(150, 190) if _compact else Vector2(220, 250)
	var v := UIKit.vbox(6)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(v)
	var rarity_l := UIKit.label("?", 13, UIKit.TEXT_DIM)
	rarity_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(rarity_l)
	var icon := UIKit.icon(_texture(_pool[randi() % _pool.size()]), 80 if _compact else 120)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(icon)
	var name_l := UIKit.label("", 17)
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(name_l)
	var tag := UIKit.label(" ", 13, UIKit.GOOD)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(tag)
	return {
		"id": opt["id"], "guaranteed": bool(opt.get("guaranteed", false)), "stop_at": stop_at,
		"panel": panel, "style": style, "icon": icon, "name": name_l, "rarity": rarity_l, "tag": tag,
		"idx": randi() % _pool.size(), "next_tick": 0.0, "done": false,
	}


func _process(delta: float) -> void:
	if _finished:
		return
	_t += delta
	for s in _slots:
		if s["done"]:
			continue
		if _t >= float(s["stop_at"]):
			_land(s)
		elif _t >= float(s["next_tick"]):
			s["idx"] = (int(s["idx"]) + 1) % _pool.size()
			_show_unit(s, _pool[s["idx"]], false)
			# Slow down towards the stop: fast at first, crawling at the end.
			var p := clampf(_t / float(s["stop_at"]), 0.0, 1.0)
			s["next_tick"] = _t + lerpf(TICK_FAST, TICK_SLOW, p * p * p)
			Audio.play_sfx("click", -16.0)
	if _end_at < 0.0:
		var all_done := true
		for s in _slots:
			all_done = all_done and s["done"]
		if all_done:
			_end_at = _t + END_PAUSE
			_skip.text = "Continue"
	elif _t >= _end_at:
		_finish()


## Show a unit in a spinning slot: unfound units as silhouettes, and the
## frame tinted by the rarity flashing past.
func _show_unit(s: Dictionary, id: String, final: bool) -> void:
	var icon: TextureRect = s["icon"]
	icon.texture = _texture(id)
	var known := final or _owned(id)
	icon.modulate = Color.WHITE if known else Color(0, 0, 0, 0.85)
	var color := GameData.rarity_color(_rarity(id))
	(s["name"] as Label).text = _name(id) if known else "???"
	(s["name"] as Label).add_theme_color_override("font_color", color if final else Color(color, 0.7))
	(s["style"] as StyleBoxFlat).border_color = color if final else Color(color, 0.45)


func _land(s: Dictionary) -> void:
	s["done"] = true
	var id: String = s["id"]
	var rarity := _rarity(id)
	var color := GameData.rarity_color(rarity)
	var order := _rarity_order(id)
	var is_new := not _owned(id)
	_show_unit(s, id, true)
	var style: StyleBoxFlat = s["style"]
	style.bg_color = UIKit.PANEL_LIGHT.lerp(color, 0.12 + 0.04 * order)
	style.set_border_width_all(3 + order)
	(s["rarity"] as Label).text = GameData.RARITIES[rarity]["name"].to_upper()
	(s["rarity"] as Label).add_theme_color_override("font_color", color)
	var tags: Array = []
	if is_new:
		tags.append("NEW TRINKET!" if _trinkets else "NEW UNIT!")
	elif _trinkets:
		tags.append("Owned: +%d gold" % int(Trinkets.DUPLICATE_GOLD[rarity]))
	if s["guaranteed"]:
		tags.append("★ GUARANTEED")
	(s["tag"] as Label).text = "  ".join(PackedStringArray(tags)) if not tags.is_empty() else " "

	# Pop + flash, bigger for rarer finds.
	var icon: TextureRect = s["icon"]
	icon.pivot_offset = icon.size / 2.0
	var tw := create_tween().set_parallel(true)
	icon.scale = Vector2.ONE * (1.25 + 0.1 * order)
	tw.tween_property(icon, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var panel: Control = s["panel"]
	panel.modulate = Color(1.0 + 0.35 * (order + 1), 1.0 + 0.35 * (order + 1), 1.0 + 0.35 * (order + 1))
	tw.tween_property(panel, "modulate", Color.WHITE, 0.45 + 0.1 * order)
	match order:
		0, 1:
			Audio.play_sfx("gem", -6.0)
		2:
			Audio.play_sfx("gem")
		3:
			Audio.play_sfx("coins")
			Audio.play_sfx("gem")
		_:
			Audio.play_sfx("roar")
			Audio.play_sfx("coins")


## Skip: land everything at once (or move on if it's already done).
func _reveal_all() -> void:
	if _end_at >= 0.0:
		_finish()
		return
	var pending: Array = []
	for s in _slots:
		if not s["done"]:
			pending.append(s)
	pending.sort_custom(func(a, b): return float(a["stop_at"]) < float(b["stop_at"]))
	for s in pending:
		_land(s)


func _finish() -> void:
	if _finished:
		return
	_finished = true
	finished.emit()
