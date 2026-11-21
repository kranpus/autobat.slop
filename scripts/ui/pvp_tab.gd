extends HBoxContainer
## Battle hub: ranked arena (asynchronous battles against other commanders'
## armies), friend challenges via army codes, and live duels over the network.

signal battle_requested(config: Dictionary)

var _opponents_box: VBoxContainer
var _record_label: Label
var _code_input: LineEdit
var _status: Label
var _ip_input: LineEdit
var _port_input: SpinBox
var _rematch_btn: Button
var _map_picker: OptionButton
var _map_desc: Label
var _opponents: Array = []
var _searching := false


func _ready() -> void:
	add_theme_constant_override("separation", 12)

	# --- Ranked arena -------------------------------------------------------
	var left := UIKit.panel(UIKit.PANEL_LIGHT)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(left)
	var lv := UIKit.vbox(8)
	left.add_child(lv)
	lv.add_child(UIKit.label("Ranked Arena", 20, UIKit.ACCENT))
	_record_label = UIKit.label("", 14, UIKit.TEXT_DIM)
	lv.add_child(_record_label)
	var info := UIKit.label("Find Opponents saves your army on the server and matches you against armies other players saved at a similar rating. Stronger opponents give more rating and gold; wins also grant a scouting map.", 13, UIKit.TEXT_DIM)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lv.add_child(info)
	lv.add_child(UIKit.button("Find Opponents", _find_opponents))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	lv.add_child(scroll)
	_opponents_box = UIKit.vbox(8)
	_opponents_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_opponents_box)

	# --- Right column: friend challenge + live duel ------------------------
	# Right column scrolls so it also fits short (phone) screens.
	var right_scroll := ScrollContainer.new()
	right_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right_scroll.custom_minimum_size = Vector2(380 if UIKit.is_compact(self) else 420, 0)
	add_child(right_scroll)
	var right := UIKit.vbox(12)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_scroll.add_child(right)

	var fp := UIKit.panel(UIKit.PANEL_LIGHT)
	var mp := UIKit.panel(UIKit.PANEL_LIGHT)
	right.add_child(mp)
	var mv := UIKit.vbox(6)
	mp.add_child(mv)
	var mrow := UIKit.hbox(8)
	mrow.add_child(UIKit.label("Battlefield", 20, UIKit.ACCENT))
	_map_picker = OptionButton.new()
	_map_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map_picker.add_item("Random (%d maps)" % BattleMaps.MAPS.size())
	_map_picker.set_item_metadata(0, "")
	for id in BattleMaps.map_ids():
		_map_picker.add_item(BattleMaps.MAPS[id]["name"])
		_map_picker.set_item_metadata(_map_picker.item_count - 1, id)
	_map_picker.item_selected.connect(func(_i): _update_map_desc())
	mrow.add_child(_map_picker)
	mv.add_child(mrow)
	_map_desc = UIKit.label("", 13, UIKit.TEXT_DIM)
	_map_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mv.add_child(_map_desc)
	_update_map_desc()
	right.add_child(fp)
	var fv := UIKit.vbox(8)
	fp.add_child(fv)
	fv.add_child(UIKit.label("Friend Challenge", 20, UIKit.ACCENT))
	var finfo := UIKit.label("Paste a friend's army code (Army tab → Copy) to fight it. Unranked.", 13, UIKit.TEXT_DIM)
	finfo.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	fv.add_child(finfo)
	_code_input = LineEdit.new()
	_code_input.placeholder_text = Army.CODE_PREFIX + "..."
	fv.add_child(_code_input)
	var frow := UIKit.hbox(8)
	frow.add_child(UIKit.button("Fight", _fight_code))
	frow.add_child(UIKit.button("Copy my code", func():
		DisplayServer.clipboard_set(Profile.army_code())
		Audio.play_sfx("scroll")))
	fv.add_child(frow)

	var np := UIKit.panel(UIKit.PANEL_LIGHT)
	np.visible = Party.network_supported()   # no live duels in the browser
	right.add_child(np)
	var nv := UIKit.vbox(8)
	np.add_child(nv)
	nv.add_child(UIKit.label("Live Duel (LAN / Internet)", 20, UIKit.ACCENT))
	var ninfo := UIKit.label("One player hosts, the other joins with the host's IP. Both armies are exchanged, both games simulate the same battle, and results are cross-checked. Ranked.", 13, UIKit.TEXT_DIM)
	ninfo.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nv.add_child(ninfo)
	var prow := UIKit.hbox(8)
	prow.add_child(UIKit.label("Port", 14))
	_port_input = SpinBox.new()
	_port_input.min_value = 1024
	_port_input.max_value = 65535
	_port_input.value = Net.DEFAULT_PORT
	prow.add_child(_port_input)
	prow.add_child(UIKit.button("Host", func(): Net.host(int(_port_input.value), Profile.army_code(), _chosen_map())))
	nv.add_child(prow)
	var jrow := UIKit.hbox(8)
	_ip_input = LineEdit.new()
	_ip_input.text = "127.0.0.1"
	_ip_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	jrow.add_child(_ip_input)
	jrow.add_child(UIKit.button("Join", func(): Net.join(_ip_input.text.strip_edges(), int(_port_input.value), Profile.army_code())))
	nv.add_child(jrow)
	var crow := UIKit.hbox(8)
	_rematch_btn = UIKit.button("Rematch", func():
		if not Net.start_rematch(Profile.army_code(), _chosen_map()):
			_status.text = "No opponent connected (host only)."
	)
	crow.add_child(_rematch_btn)
	crow.add_child(UIKit.button("Disconnect", func():
		Net.close()
		_status.text = "Disconnected."))
	nv.add_child(crow)
	_status = UIKit.label("Not connected.", 13, UIKit.TEXT_DIM)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nv.add_child(_status)
	Net.status_changed.connect(func(t: String): _status.text = t)

	Party.ranked_opponents.connect(_on_ranked_opponents)
	Profile.changed.connect(refresh)
	refresh()


func refresh() -> void:
	if not is_inside_tree():
		return
	var my := Profile.battle_squads()
	_record_label.text = "Rating %d   ·   Wins %d   ·   Losses %d   ·   Your power %s" % [Profile.rating(), int(Profile.data["wins"]), int(Profile.data["losses"]), Army.format_power(Army.army_power(my))]


func _find_opponents() -> void:
	if Profile.battle_squads().is_empty():
		_show_search_message("Build an army first (Army tab).")
		return
	if Profile.online and not Party.session_active():
		_show_search_message("Reconnecting to the server... try again in a moment.")
		return
	_searching = true
	_show_search_message("Searching for players near rating %d..." % Profile.rating())
	# Saves your army on the server (with your current rating) and asks for
	# armies that other players saved at a similar rating.
	Party.request_ranked_opponents(Profile.player_id(), Profile.player_name(), Profile.rating(), Profile.army_code())


func _on_ranked_opponents(list: Array) -> void:
	if not _searching:
		return
	_searching = false
	var rating := Profile.rating()
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	_opponents.clear()
	for e in list:
		if e.has("index"):
			# Signed in: the server picked these opponents and will run the battle.
			_opponents.append(e)
			continue
		var army := Army.decode(str(e.get("code", "")))
		if army.is_empty():
			continue  # e.g. every unit in it is locked
		var r := int(e.get("rating", 1000))
		_opponents.append({
			"name": str(e.get("name", "Commander")), "rating": r, "squads": army["squads"],
			"difficulty": "Easy" if r < rating - 25 else ("Hard" if r > rating + 25 else "Even"),
			"map": BattleMaps.random_map_id(rng), "player": true, "saved_at": int(e.get("saved_at", 0)),
		})
	# Fill the remaining slots with generated opponents.
	var my_power := maxf(500.0, Army.army_power(Profile.battle_squads()))
	var tiers := [[0.8, -60, "Easy"], [1.0, 0, "Even"], [1.25, 70, "Hard"]]
	# First cover any missing difficulty, then top up to three.
	for pass_i in (0 if Profile.online else 2):
		for t in tiers:
			if _opponents.size() >= 3:
				break
			var taken := false
			for o in _opponents:
				if o["difficulty"] == t[2]:
					taken = true
			if taken and pass_i == 0:
				continue
			var opp := Army.generate_opponent(my_power * float(t[0]) * rng.randf_range(0.95, 1.05), maxi(0, rating + int(t[1]) + rng.randi_range(-15, 15)), rng.randi())
			opp["difficulty"] = t[2]
			opp["map"] = BattleMaps.random_map_id(rng)
			opp["player"] = false
			_opponents.append(opp)
	var order := {"Easy": 0, "Even": 1, "Hard": 2}
	_opponents.sort_custom(func(a, b): return int(order[a["difficulty"]]) < int(order[b["difficulty"]]))
	UIKit.clear(_opponents_box)
	var players := 0
	for o in _opponents:
		if o["player"]:
			players += 1
	var note := "%d real player arm%s near your rating" % [players, "y" if players == 1 else "ies"] if players > 0 else "No saved player armies near your rating yet (or the server is offline), so these are training opponents"
	_opponents_box.add_child(UIKit.label(note + ".", 12, UIKit.TEXT_DIM))
	for opp in _opponents:
		_opponents_box.add_child(_make_opponent_card(opp))
	Audio.play_sfx("scroll")


func _show_search_message(text: String) -> void:
	_opponents.clear()
	UIKit.clear(_opponents_box)
	_opponents_box.add_child(UIKit.label(text, 14, UIKit.TEXT_DIM))


func _make_opponent_card(opp: Dictionary) -> Control:
	var p := UIKit.panel(UIKit.PANEL)
	var v := UIKit.vbox(4)
	p.add_child(v)
	var h := UIKit.hbox(10)
	var diff: String = opp["difficulty"]
	var diff_color: Color = {"Easy": UIKit.GOOD, "Even": UIKit.ACCENT, "Hard": UIKit.BAD}[diff]
	h.add_child(UIKit.label(opp["name"], 17))
	h.add_child(UIKit.label(diff, 14, diff_color))
	if opp.get("player", false):
		var days := int((Time.get_unix_time_from_system() - float(opp.get("saved_at", 0))) / 86400.0)
		var tag := UIKit.label("Player · saved %s" % ("today" if days < 1 else "%d day%s ago" % [days, "" if days == 1 else "s"]), 12, Color("9fd3ff"))
		tag.tooltip_text = "A real player's army, saved when they had rating %d." % int(opp["rating"])
		h.add_child(tag)
	else:
		h.add_child(UIKit.label("Training", 12, UIKit.TEXT_DIM))
	h.add_child(UIKit.spacer())
	h.add_child(UIKit.label("Rating %d · Power %s · %d units" % [int(opp["rating"]), Army.format_power(Army.army_power(opp["squads"])), Army.total_units(opp["squads"])], 13, UIKit.TEXT_DIM))
	v.add_child(h)
	var h2 := UIKit.hbox(10)
	h2.add_child(UIKit.squad_strip(opp["squads"], 28))
	h2.add_child(UIKit.spacer())
	h2.add_child(UIKit.label("on %s" % BattleMaps.get_map(opp["map"])["name"], 13, UIKit.TEXT_DIM))
	var win_delta := Army.elo_delta(Profile.rating(), int(opp["rating"]), 1.0)
	h2.add_child(UIKit.button("Attack  (+%d)" % win_delta, func(): _start(opp, "ranked")))
	v.add_child(h2)
	return p


func _fight_code() -> void:
	var opp := Army.decode(_code_input.text)
	if opp.is_empty():
		_code_input.text = ""
		_code_input.placeholder_text = "Invalid code - paste a code starting with " + Army.CODE_PREFIX
		return
	_start(opp, "practice")


func _start(opp: Dictionary, mode: String) -> void:
	var mine := Profile.battle_squads()
	if mine.is_empty():
		_status.text = "Build an army first (Army tab)."
		return
	if mode == "ranked" and opp.has("index"):
		# The server simulates the battle and pays the rewards; the battle
		# screen opens when it answers.
		Party.request_ranked_battle(int(opp["index"]))
		_opponents.clear()
		UIKit.clear(_opponents_box)
		_opponents_box.add_child(UIKit.label("Starting the battle on the server...", 14, UIKit.TEXT_DIM))
		return
	battle_requested.emit({
		"mode": mode,
		"seed": randi(),
		"squads_a": mine,
		"squads_b": opp["squads"],
		"name_a": Profile.player_name(),
		"name_b": opp["name"],
		"rating_a": Profile.rating(),
		"rating_b": int(opp["rating"]),
		"local_team": 0,
		"map": str(opp.get("map", _chosen_map_or_random())),
	})
	if mode == "ranked":
		_opponents.clear()
		UIKit.clear(_opponents_box)


## "" when the player picked Random.
func _chosen_map() -> String:
	return str(_map_picker.get_item_metadata(_map_picker.selected))


func _chosen_map_or_random() -> String:
	var id := _chosen_map()
	if id != "":
		return id
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return BattleMaps.random_map_id(rng)


func _update_map_desc() -> void:
	var id := _chosen_map()
	if id == "":
		_map_desc.text = "A random battlefield for friend challenges and live duels you host. Ranked opponents each come with their own map."
	else:
		var m := BattleMaps.get_map(id)
		var sz: Array = m["size"]
		_map_desc.text = "%s  (%dx%d, %d obstacles)" % [m["desc"], int(sz[0]), int(sz[1]), BattleMaps.obstacles(id).size()]
