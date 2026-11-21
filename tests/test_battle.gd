extends SceneTree
## Headless checks for the simulation and army codes.
## Run:  godot --headless --import   (once, so class_names are registered)
##       godot --headless -s res://tests/test_battle.gd

var _failures := 0


func _initialize() -> void:
	test_army_code_roundtrip()
	test_no_unit_cap()
	test_maps()
	test_determinism_and_scale()
	test_opponent_generation()
	test_draft_rules()
	test_draft_bot_tournament()
	test_match_room()
	print("\n%s (%d failure%s)" % ["ALL TESTS PASSED" if _failures == 0 else "TESTS FAILED", _failures, "" if _failures == 1 else "s"])
	quit(1 if _failures > 0 else 0)


func check(cond: bool, msg: String) -> void:
	if cond:
		print("  ok   ", msg)
	else:
		_failures += 1
		printerr("  FAIL ", msg)


func big_army(units: Array, tier: int, level: int) -> Array:
	var squads: Array = []
	for id in units:
		squads.append({"unit": id, "level": level, "tier": tier, "row": GameData.default_row_for(id)})
	return squads


func test_army_code_roundtrip() -> void:
	print("army codes")
	var squads := big_army(["goblin", "elf_archer", "ogre"], 3, 9)
	var code := Army.encode("Tester", 1234, squads)
	var back := Army.decode(code)
	check(not back.is_empty(), "decode succeeds")
	check(back["name"] == "Tester" and int(back["rating"]) == 1234, "name and rating survive")
	check(back["squads"].size() == 3 and back["squads"][1]["unit"] == "elf_archer" and int(back["squads"][2]["level"]) == 9, "squads survive")
	check(Army.decode("garbage").is_empty(), "invalid code rejected")
	var cheat := Army.encode("Cheater", 1000, [{"unit": "titan", "level": 999, "tier": 99, "row": "front"}])
	var c := Army.decode(cheat)
	check(int(c["squads"][0]["tier"]) == GameData.MAX_TIER and int(c["squads"][0]["level"]) == Army.max_level_for_tier(GameData.MAX_TIER), "out-of-range values clamped")


func test_no_unit_cap() -> void:
	print("no unit cap")
	var squads := big_army(["goblin", "kobold_slinger", "rat_swarm", "skeleton", "orc_warrior", "elf_archer", "dire_wolf", "dwarf_berserker"], 10, 1)
	check(Army.total_units(squads) == 4 * 180 + 4 * 95, "every squad deploys at full size (got %d)" % Army.total_units(squads))


func test_maps() -> void:
	print("maps")
	check(BattleMaps.MAPS.size() == 20, "20 battlefields defined")
	var a := big_army(["goblin", "elf_archer", "ogre", "griffon"], 4, 8)
	var b := big_army(["skeleton", "kobold_slinger", "orc_warrior", "lich"], 4, 8)
	for id in BattleMaps.map_ids():
		var tex := load("res://assets/sprites/tiles/%s.png" % BattleMaps.MAPS[id]["tile"])
		check(tex != null, "%s floor texture loads" % id)
		var sim := BattleSim.new()
		sim.setup(a, b, 99, id)
		sim.run_to_end()
		var inside := 0
		for i in sim.n:
			if sim.alive[i] == 1 and sim.flying[i] == 0 and sim.is_blocked(sim.px[i], sim.py[i], sim.radius[i] - 1.0):
				inside += 1
		check(sim.finished and sim.time < BattleSim.MAX_TIME, "%s: battle resolves in %.0fs" % [id, sim.time])
		check(inside == 0, "%s: no ground units stuck inside obstacles" % id)


func test_determinism_and_scale() -> void:
	print("simulation")
	var a := big_army(["golden_dragon", "goblin", "kobold_slinger", "skeleton", "rat_swarm", "elf_archer", "orc_warrior", "dire_wolf"], 10, 20)
	var b := big_army(["titan", "goblin", "kobold_slinger", "skeleton", "rat_swarm", "dwarf_berserker", "gnoll_shaman", "orc_warrior"], 10, 20)
	var results: Array = []
	for run in 2:
		var sim := BattleSim.new()
		sim.setup(a, b, 424242, "twin_fords")
		if run == 0:
			check(sim.n >= 2000, "1000+ vs 1000+ battle spawned (%d units)" % sim.n)
		var t0 := Time.get_ticks_msec()
		sim.run_to_end()
		var ms := Time.get_ticks_msec() - t0
		print("    run %d: winner=%d ticks=%d survivors=%d/%d  %.2f ms/tick" % [run, sim.winner, sim.tick, sim.alive_count[0], sim.alive_count[1], float(ms) / maxf(1.0, float(sim.tick))])
		check(sim.finished, "battle finishes")
		results.append(sim.checksum())
	check(results[0] == results[1], "same seed -> identical result (checksum %d)" % results[0])
	var sim2 := BattleSim.new()
	sim2.setup(a, b, 7)
	sim2.run_to_end()
	check(sim2.finished, "different seed also finishes")


func test_opponent_generation() -> void:
	print("opponents")
	var target := 60000.0
	var opp := Army.generate_opponent(target, 1200, 99)
	var p := Army.army_power(opp["squads"])
	check(p >= target * 0.9, "generated power %.0f near target %.0f" % [p, target])
	check(opp["squads"].size() <= GameData.MAX_SQUADS, "opponent within squad limit")


func test_draft_rules() -> void:
	print("legion draft rules")
	var r := DraftRun.new(1234)
	r.begin_turn()
	check(r.gold == DraftData.TURN_GOLD and r.shop_units.size() == 3 and r.shop_trinkets.size() == 1, "turn 1: 10 gold, 3 units, 1 trinket in shop")
	# Force a known shop and merge three copies into one slot.
	r.gold = 100
	r.shop_units = [{"unit": "goblin", "frozen": false}, {"unit": "goblin", "frozen": false}, {"unit": "goblin", "frozen": false}]
	check(r.buy_unit(0, 0), "buy into empty slot")
	check(r.buy_unit(0, 0), "buy duplicate onto same unit")
	check(r.buy_unit(0, 0) and DraftData.entry_level(r.board[0]) == 2, "3 copies -> level 2")
	check(DraftData.entry_count(r.board[0]) == 32, "level 2 commons field 32 units")
	r.shop_units = [{"unit": "elf_archer", "frozen": false}]
	check(not r.buy_unit(0, 0), "can't place a different unit on an occupied slot")
	check(r.buy_unit(0, 4), "archer placed in back row")
	r.shop_trinkets = [{"trinket": "whetstone", "frozen": false}]
	check(r.buy_trinket(0, 4) and str(r.board[4]["trinket"]) == "whetstone", "equip trinket")
	var sq := DraftData.board_to_squads(r.board)
	check(sq.size() == 2 and sq[1]["row"] == "back" and float(sq[1]["mods"]["dmg_mult"]) > 1.1, "board converts to squads with rows and trinket mods")
	var gold_before := r.gold
	check(r.sell(0) and r.gold == gold_before + 2 + 2, "selling a Lv2 goblin gives 2 gold + Scavenger bonus")
	r.shop_units = [{"unit": "titan", "frozen": false}]
	var dmg_before := int(r.board[4]["dmg_b"])
	r.buy_unit(0, 1)
	check(int(r.board[4]["dmg_b"]) == dmg_before + 8, "Titan's on-buy ability buffs allies")
	check(DraftData.tier_for_battles(0) == 1 and DraftData.tier_for_battles(3) == 2 and DraftData.tier_for_battles(30) == 6, "shop tier rises every 3 battles, max 6")
	var cheat := DraftData.sanitize_board([{"unit": "titan", "xp": 99, "hp_b": 9999, "trinket": "nope"}])
	check(int(cheat[0]["xp"]) == DraftData.MAX_XP and int(cheat[0]["hp_b"]) == DraftData.MAX_BONUS and cheat[0]["trinket"] == "", "network boards are sanitized")


func test_draft_bot_tournament() -> void:
	print("legion draft bots")
	var bots: Array = []
	for i in 4:
		bots.append(DraftRun.new(100 + i))
	var ok := true
	var max_units := 0
	for rnd in 15:
		var boards: Array = []
		for b in bots:
			var r: DraftRun = b
			r.begin_turn()
			r.auto_play()
			boards.append(r.end_turn())
			if r.gold < 0 or r.board.size() != DraftData.BOARD_SLOTS:
				ok = false
		for pair in [[0, 1], [2, 3]]:
			var sim := BattleSim.new()
			sim.setup(DraftData.board_to_squads(boards[pair[0]]), DraftData.board_to_squads(boards[pair[1]]), rnd * 7 + 1, BattleMaps.random_map_id(sim.rng))
			max_units = maxi(max_units, sim.n)
			sim.run_to_end()
			if not sim.finished:
				ok = false
			for side in 2:
				var r: DraftRun = bots[pair[side]]
				var outcome := 0.5 if sim.winner == 2 else (1.0 if sim.winner == side else 0.0)
				r.apply_battle_result(outcome, r.lives - (1 if outcome == 0.0 else 0), r.wins + (1 if outcome == 1.0 else 0))
	check(ok, "15 rounds of bot drafting and battles run cleanly")
	check((bots[0] as DraftRun).tier() == 6, "bots reached shop tier 6")
	print("    largest draft battle: %d units" % max_units)


## Server-side room logic end to end: one scripted "human" (whose actions are
## replayed by the room, exactly as over the network) plus three bots.
func test_match_room() -> void:
	print("match room (server logic)")
	var room := MatchRoom.new("TEST1", {"wins": 3, "lives": 2, "max_players": 4, "turn_time": 60}, true, false)
	var inbox: Array = []
	room.outbox.connect(func(id: int, method: String, args: Array): inbox.append([id, method, args]))
	check(room.add_player(42, "Tester") == "", "human joins the room")
	for i in 3:
		room.add_bot(42)
	check(room.players.size() == 4 and room.can_start(), "owner fills the room with bots")
	room.start(42)
	var client := DraftRun.new()
	var replay_ok := true
	var rounds := 0
	var started := Time.get_ticks_msec()
	while room.phase != "over" and Time.get_ticks_msec() - started < 300000:
		room.process()
		var msgs := inbox.duplicate()
		inbox.clear()
		for m in msgs:
			if int(m[0]) != 42:
				continue
			match str(m[1]):
				"shop":
					var state: Dictionary = m[2][2]
					if state.is_empty():
						continue
					rounds += 1
					client.load_dict(state)
					var r: int = m[2][0]
					for step in 8:
						var act := _scripted_action(client, step)
						if client.apply_action(act):
							room.action(42, r, act)
					client.end_turn()
					room.submit(42, r)
					var server_board: Array = room._submitted[42]
					if JSON.stringify(server_board, "", true) != JSON.stringify(client.board, "", true):
						replay_ok = false
				"results":
					room.shop_ready(42, room.round_num)
	check(room.phase == "over", "match finished (%d rounds played by the human)" % rounds)
	check(replay_ok, "server's replayed board always matches the client's board")
	var places := {}
	for id in room.players:
		places[int(room.players[id]["place"])] = true
	check(places.size() == 4 and places.has(1) and places.has(4), "placements 1-4 assigned")


func _scripted_action(run: DraftRun, step: int) -> Array:
	match step % 4:
		0, 1:
			if run.shop_units.is_empty():
				return ["reroll"]
			var uid: String = run.shop_units[0]["unit"]
			var slot := run.slot_of_unit(uid)
			if slot == -1:
				slot = run.first_empty_slot()
			if slot == -1:
				return ["sell", 5]
			return ["buy_unit", 0, slot]
		2:
			for s in DraftData.BOARD_SLOTS:
				if not (run.board[s] as Dictionary).is_empty():
					return ["buy_trinket", 0, s]
			return ["reroll"]
	return ["move", 0, 1] if step == 3 else ["reroll"]
