extends VBoxContainer
## Challenges: preset battles against hand-made armies on chosen battlefields,
## unlocked one after another, each with a fixed reward for the first win.

signal battle_requested(config: Dictionary)

var _header: Label
var _list: VBoxContainer
var _status: Label


func _ready() -> void:
	add_theme_constant_override("separation", 10)
	var top := UIKit.hbox(10)
	top.add_child(UIKit.label("Challenges", 22, UIKit.ACCENT))
	top.add_child(UIKit.spacer())
	_header = UIKit.label("", 15)
	top.add_child(_header)
	add_child(top)
	var intro := UIKit.label("Hand-made battles against set armies and named bosses, on chosen battlefields. Win one to unlock the next. Each pays its reward the first time you clear it; you can replay any cleared challenge.", 14, UIKit.TEXT_DIM)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(intro)
	_status = UIKit.label("", 13, UIKit.ACCENT)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_list = UIKit.vbox(8)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	Profile.changed.connect(refresh)
	refresh()


func refresh() -> void:
	if not is_inside_tree():
		return
	_header.text = "%d / %d cleared" % [Profile.challenges_cleared(), Challenges.LIST.size()]
	UIKit.clear(_list)
	var my_power := Army.army_power(Profile.battle_squads())
	var chapter := -1
	for c in Challenges.LIST:
		if int(c["chapter"]) != chapter:
			chapter = int(c["chapter"])
			var ch: Dictionary = Challenges.CHAPTERS[chapter]
			_list.add_child(UIKit.label("Chapter %d: %s" % [chapter + 1, ch["name"]], 18, UIKit.ACCENT))
			var d := UIKit.label(ch["desc"], 13, UIKit.TEXT_DIM)
			d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_list.add_child(d)
		_list.add_child(_make_card(c, my_power))


func _make_card(c: Dictionary, my_power: float) -> Control:
	var id: String = c["id"]
	var unlocked := Profile.challenge_unlocked(id)
	var cleared := Profile.challenge_cleared(id)
	var p := UIKit.panel(UIKit.PANEL_LIGHT if unlocked else UIKit.PANEL)
	var h := UIKit.hbox(12)
	p.add_child(h)
	var map_def := BattleMaps.get_map(c["map"])
	var tile := UIKit.icon(GameData.tile_texture(map_def["tile"]), 64)
	tile.tooltip_text = "%s: %s" % [map_def["name"], map_def["desc"]]
	if not unlocked:
		tile.modulate = Color(0.5, 0.5, 0.5)
	h.add_child(tile)

	var v := UIKit.vbox(4)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title := UIKit.hbox(8)
	title.add_child(UIKit.label(c["name"], 18, (UIKit.GOOD if cleared else UIKit.ACCENT) if unlocked else UIKit.TEXT_DIM))
	if cleared:
		title.add_child(UIKit.label("✓ Cleared", 13, UIKit.GOOD))
	elif not unlocked:
		title.add_child(UIKit.label("Locked: clear the previous challenge", 13, UIKit.TEXT_DIM))
	v.add_child(title)
	var desc := UIKit.label(c["desc"], 13, UIKit.TEXT_DIM if unlocked else Color(UIKit.TEXT_DIM, 0.6))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(desc)

	if unlocked:
		var row := UIKit.hbox(12)
		row.add_child(UIKit.squad_strip(Challenges.enemy_squads(id), 28))
		var bosses: Array = []
		for sq in c["enemy"]:
			if sq.has("title"):
				bosses.append("%s (%s)" % [sq["title"], GameData.UNITS[sq["unit"]]["name"]])
		if not bosses.is_empty():
			row.add_child(UIKit.label("Boss: " + ", ".join(PackedStringArray(bosses)), 13, UIKit.BAD))
		v.add_child(row)
		var rec := int(c["recommended"])
		var mine := roundi(my_power / 10.0)
		var info := UIKit.label("Battlefield: %s   ·   Recommended power %d   ·   Your army %d" % [map_def["name"], rec, mine], 12,
			UIKit.GOOD if mine >= rec else (UIKit.ACCENT if mine >= rec * 0.75 else UIKit.BAD))
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(info)
	v.add_child(_reward_row(c["reward"], cleared))
	h.add_child(v)

	var side := UIKit.vbox(6)
	side.alignment = BoxContainer.ALIGNMENT_CENTER
	var b := UIKit.button("Replay" if cleared else "Fight", func(): _start(id))
	b.custom_minimum_size = Vector2(120, 40)
	b.disabled = not unlocked
	side.add_child(b)
	h.add_child(side)
	return p


func _reward_row(reward: Dictionary, cleared: bool) -> Control:
	var h := UIKit.hbox(8)
	h.add_child(UIKit.label("Reward claimed:" if cleared else "Reward:", 13, UIKit.TEXT_DIM if cleared else Color.WHITE))
	if int(reward.get("gold", 0)) > 0:
		h.add_child(UIKit.label("%d gold" % int(reward["gold"]), 13, Color("ffd76a")))
	if int(reward.get("maps", 0)) > 0:
		h.add_child(UIKit.label("%d map%s" % [int(reward["maps"]), "" if int(reward["maps"]) == 1 else "s"], 13, Color("9fd3ff")))
	var t := str(reward.get("trinket", ""))
	if Trinkets.exists(t):
		var ic := UIKit.icon(Trinkets.texture(t), 22)
		ic.tooltip_text = "%s: %s" % [Trinkets.ALL[t]["name"], Trinkets.ALL[t]["desc"]]
		h.add_child(ic)
		h.add_child(UIKit.label(Trinkets.ALL[t]["name"], 13, GameData.rarity_color(Trinkets.rarity_of(t))))
	var u := str(reward.get("unit", ""))
	if GameData.UNITS.has(u):
		h.add_child(UIKit.unit_icon(u, 22))
		var owned := Profile.owns(u)
		h.add_child(UIKit.label(GameData.UNITS[u]["name"] + (" (+%d shards: owned)" % Challenges.DUPLICATE_UNIT_SHARDS if owned and not cleared else ""), 13, GameData.rarity_color(GameData.UNITS[u]["rarity"])))
	if cleared:
		h.modulate = Color(1, 1, 1, 0.55)
	return h


func _start(id: String) -> void:
	var mine := Profile.battle_squads()
	if mine.is_empty():
		_status.text = "Build an army first (Army tab)."
		return
	if not Profile.challenge_unlocked(id):
		return
	_status.text = ""
	if Profile.online:
		if not Party.session_active():
			_status.text = "Reconnecting to the server... try again in a moment."
			return
		_status.text = "Starting the battle on the server..."
		Party.request_challenge_battle(id)   # the battle opens when the server answers
		return
	var c := Challenges.get_challenge(id)
	battle_requested.emit({
		"mode": "challenge", "challenge": id, "seed": randi(), "map": c["map"],
		"squads_a": mine, "squads_b": Challenges.enemy_squads(id),
		"name_a": Profile.player_name(), "name_b": c["name"],
		"rating_a": Profile.rating(), "rating_b": 0, "local_team": 0,
	})
