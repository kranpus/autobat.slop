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
	test_expedition_pity()
	test_board_sizes()
	test_room_rule_toggles()
	test_server_gold_commands()
	test_unit_locks()
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
			for s in run.slots:
				if not (run.board[s] as Dictionary).is_empty():
					return ["buy_trinket", 0, s]
			return ["reroll"]
	return ["move", 0, 1] if step == 3 else ["reroll"]


func test_expedition_pity() -> void:
	print("expedition pity")
	var profile := root.get_node("Profile")
	var backup: Dictionary = profile.data.duplicate(true)
	var worst := {}
	for region in GameData.REGIONS:
		if UnitLocks.is_region_locked(region):
			continue
		profile.data["pity"] = {}
		var since := {}
		for rule in GameData.PITY:
			since[rule["rarity"]] = 0
		for i in 300:
			profile.data["maps"] = 99
			profile.data["pending_choice"] = {}
			profile.data["rating"] = 5000
			var res: Dictionary = profile.explore(region)
			var best := 0
			for o in res["options"]:
				best = maxi(best, int(GameData.RARITIES[GameData.UNITS[o["unit"]]["rarity"]]["order"]))
			for rule in GameData.PITY:
				var r: String = rule["rarity"]
				since[r] = 0 if best >= int(GameData.RARITIES[r]["order"]) else int(since[r]) + 1
				worst[r] = maxi(int(worst.get(r, 0)), int(since[r]))
			profile.data["pending_choice"] = {}
	for rule in GameData.PITY:
		var r: String = rule["rarity"]
		if r == "legendary":
			continue  # not every region has legendaries
		check(int(worst[r]) < int(rule["every"]), "never more than %d expeditions in a row without %s+ (longest dry run %d)" % [int(rule["every"]) - 1, r, int(worst[r])])
	profile.data = backup
	profile.save()


func test_board_sizes() -> void:
	print("draft board sizes")
	for n in DraftData.BOARD_SIZES:
		var r := DraftRun.new(77, n)
		check(r.board.size() == n, "%d-slot board created" % n)
		r.gold = 99
		r.shop_units = []
		for i in n:
			r.shop_units.append({"unit": ["goblin", "elf_archer", "ogre", "skeleton"][i % 4], "frozen": false})
		for i in n:
			r.buy_unit(0, r.first_empty_slot())
		var sq := DraftData.board_to_squads(r.board)
		check(sq.size() == n and sq[0]["row"] == "front" and sq[n - 1]["row"] == "back", "%d units deploy, slot 1 front line and last slot back row" % n)
		var round_trip := DraftRun.new(1)
		round_trip.load_dict(r.to_dict())
		check(round_trip.slots == n and round_trip.board.size() == n, "%d-slot board survives network sync" % n)


func test_room_rule_toggles() -> void:
	print("draft rules switched off")
	var room := MatchRoom.new("RULES", {"use_lives": false, "use_wins": false, "use_timer": false, "max_rounds": 4, "slots": 8, "max_players": 4}, true, false)
	room.rewards = {"draft_mult": 2.0, "draft_table": [400, 250, 150, 60]}
	var inbox: Array = []
	room.outbox.connect(func(id: int, method: String, args: Array): inbox.append([id, method, args]))
	room.add_player(7, "Solo")
	for i in 3:
		room.add_bot(7)
	room.start(7)
	var shop_seconds := -1
	var board_size := 0
	var over: Array = []
	var started := Time.get_ticks_msec()
	while room.phase != "over" and Time.get_ticks_msec() - started < 120000:
		room.process()
		var msgs := inbox.duplicate()
		inbox.clear()
		for m in msgs:
			match str(m[1]):
				"shop":
					shop_seconds = int(m[2][1])
					board_size = (m[2][2]["board"] as Array).size() if not (m[2][2] as Dictionary).is_empty() else board_size
					room.submit(7, int(m[2][0]))
				"results":
					room.shop_ready(7, room.round_num)
				"over":
					over = m[2][0]
	check(shop_seconds == 0, "turn timer off: shop has no time limit")
	check(board_size == 8, "8-slot board used in the match")
	check(room.phase == "over" and room.round_num == 4, "without lives the match ends at the round limit (%d rounds)" % room.round_num)
	var lives_untouched := true
	for id in room.players:
		if int(room.players[id]["lives"]) != 0:
			lives_untouched = false
	check(lives_untouched, "lives are not used")
	var first_gold := -1
	for p in over:
		if int(p["place"]) == 1:
			first_gold = int(p["gold"])
	check(first_gold == 800, "server payout table x2 applied (1st place got %d gold)" % first_gold)


func test_server_gold_commands() -> void:
	print("server gold commands")
	var party := root.get_node("Party")
	party.run_command("gold battle 1.5")
	party.run_command("gold draft 2")
	party.run_command("gold draft-table 500 300 200 100")
	check(is_equal_approx(float(party.rewards["battle_mult"]), 1.5) and is_equal_approx(float(party.rewards["draft_mult"]), 2.0), "gold multipliers set from the console")
	check(party.rewards["draft_table"] == [500, 300, 200, 100], "draft payout table set from the console")
	check(party.run_command("gold nonsense").begins_with("Usage"), "bad command shows usage")
	party.run_command("gold reset")
	check(is_equal_approx(float(party.rewards["battle_mult"]), 1.0), "gold reset restores defaults")


func test_unit_locks() -> void:
	print("unit locks")
	var profile := root.get_node("Profile")
	var party := root.get_node("Party")
	var backup: Dictionary = profile.data.duplicate(true)
	UnitLocks.set_locked_list(UnitLocks.defaults())
	var locked := UnitLocks.locked_list()
	check(locked.size() == 40 and GameData.UNITS.size() == 60, "60 units, the 40 new ones locked by default")
	var assets_ok := true
	for id in locked:
		var in_region := false
		for rid in GameData.REGIONS:
			if GameData.REGIONS[rid]["drops"].has(id):
				in_region = true
		if load("res://assets/sprites/units/%s.png" % id) == null or not DraftData.ABILITIES.has(id) or not in_region:
			assets_ok = false
			print("    missing data for ", id)
	check(assets_ok, "every new unit has a sprite, a draft ability and a region")
	# Expeditions never offer locked units.
	var leaked := false
	for i in 400:
		profile.data["maps"] = 99
		profile.data["pending_choice"] = {}
		profile.data["rating"] = 5000
		var open_regions: Array = []
		for rid in GameData.REGIONS:
			if not UnitLocks.is_region_locked(rid):
				open_regions.append(rid)
		var region: String = open_regions[i % open_regions.size()]
		for o in profile.explore(region)["options"]:
			if UnitLocks.is_locked(o["unit"]):
				leaked = true
	profile.data["pending_choice"] = {}
	check(not leaked, "400 expeditions never offered a locked unit")
	# Draft shops never offer them, even at the top tier.
	var run := DraftRun.new(321)
	run.battles_played = 30
	run.gold = 1000
	run.begin_turn()
	var shop_leak := false
	for i in 300:
		for su in run.shop_units:
			if UnitLocks.is_locked(su["unit"]):
				shop_leak = true
		run.reroll()
	check(not shop_leak, "300 tier-6 draft shops never offered a locked unit")
	# Ranked ghosts and army codes skip them.
	var ghost_leak := false
	for i in 50:
		for sq in Army.generate_opponent(80000.0, 1500, i)["squads"]:
			if UnitLocks.is_locked(sq["unit"]):
				ghost_leak = true
	check(not ghost_leak, "ranked opponents never use locked units")
	var code := Army.encode("X", 1000, [{"unit": "storm_dragon", "level": 5, "tier": 2, "row": "back"}, {"unit": "goblin", "level": 1, "tier": 0, "row": "front"}])
	var dec := Army.decode(code)
	check(dec["squads"].size() == 1 and dec["squads"][0]["unit"] == "goblin", "army codes drop locked units")
	profile.data["units"]["storm_dragon"] = {"level": 1, "tier": 0, "shards": 0}
	profile.data["army"] = [{"unit": "storm_dragon", "row": "back"}, {"unit": "goblin", "row": "front"}]
	check(profile.army_squads().size() == 2 and profile.battle_squads().size() == 1, "an owned locked unit stays in the army but doesn't deploy")
	# Server commands.
	party.run_command("unlock Storm Dragon")
	check(not UnitLocks.is_locked("storm_dragon") and GameData.region_drops("dragons_hoard").has("storm_dragon"), "'unlock Storm Dragon' makes it available (in the Dragon's Hoard drop table)")
	check(profile.battle_squads().size() == 2, "unlocked unit deploys again")
	party.run_command("lock goblin")
	check(UnitLocks.is_locked("goblin") and not DraftData.units_for_tier(1, UnitLocks.as_dict()).has("goblin"), "'lock goblin' removes an original unit from shops")
	check(party.run_command("lock nosuchunit").contains("Unknown"), "unknown names are reported")
	party.run_command("unlock new")
	check(UnitLocks.locked_list() == ["goblin"], "'unlock new' releases all 40 new units")
	party.run_command("lock reset")
	check(UnitLocks.locked_list().size() == 40 and not UnitLocks.is_locked("goblin"), "'lock reset' restores the defaults")
	# Expedition regions.
	check(GameData.REGIONS.size() == 13 and UnitLocks.locked_regions().size() == 8, "13 regions, the 8 new ones locked by default")
	var new_only := true
	for rid in UnitLocks.default_regions():
		for id in GameData.REGIONS[rid]["drops"]:
			if not bool(GameData.UNITS[id].get("locked", false)):
				new_only = false
	for rid in ["warrens", "crypt", "forest", "deep", "peaks"]:
		for id in GameData.REGIONS[rid]["drops"]:
			if bool(GameData.UNITS[id].get("locked", false)):
				new_only = false
	check(new_only, "new regions hold only new units; the original 5 hold none")
	profile.data["maps"] = 99
	profile.data["rating"] = 5000
	profile.data["pending_choice"] = {}
	check(not profile.can_explore("dragons_hoard") and profile.explore("dragons_hoard").is_empty(), "a locked region can't be explored")
	party.run_command("unlock region Dragon's Hoard")
	check(not UnitLocks.is_region_locked("dragons_hoard") and not profile.can_explore("dragons_hoard"), "an unlocked region whose units are all locked still can't be explored")
	party.run_command("unlock new")
	check(UnitLocks.locked_list().is_empty() and UnitLocks.locked_regions().is_empty(), "'unlock new' opens the new units and regions")
	var saw_new := false
	for i in 20:
		profile.data["pending_choice"] = {}
		profile.data["maps"] = 99
		for o in profile.explore("dragons_hoard")["options"]:
			if bool(GameData.UNITS[o["unit"]].get("locked", false)):
				saw_new = true
	check(saw_new, "new units are found in the new regions once unlocked")
	party.run_command("lock region bone_fields")
	check(UnitLocks.is_region_locked("bone_fields") and not profile.can_explore("bone_fields"), "'lock region bone_fields' closes a region")
	party.run_command("lock reset")
	check(UnitLocks.locked_regions().size() == 8 and UnitLocks.locked_list().size() == 40, "'lock reset' re-locks the new units and regions")
	profile.data["pending_choice"] = {}
	# A server-run match syncs the lock list into every run state.
	var room := MatchRoom.new("LOCKS", {"max_players": 2}, true, false)
	var states: Array = []
	room.outbox.connect(func(id: int, method: String, args: Array):
		if method == "shop":
			states.append(args[2]))
	room.add_player(5, "P")
	room.add_bot(5)
	room.start(5)
	check(not states.is_empty() and (states[0]["excluded"] as Array).size() == 40, "match state carries the server's locks to clients")
	profile.data = backup
	profile.save()
