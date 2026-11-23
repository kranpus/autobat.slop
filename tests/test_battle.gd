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
	test_ranked_pool()
	test_passwords()
	test_accounts()
	test_profile_logic()
	test_trinkets()
	test_harder_ghosts()
	test_leaderboard()
	test_drop_rates()
	test_rank_progression()
	test_challenges()
	test_target_modes()
	test_power_formula()
	test_ranged_splash_nerf()
	test_unit_stats()
	test_rating_speed()
	test_difficulty()
	test_abilities()
	test_audio()
	test_new_units()
	test_rank_scaling()
	test_player_command()
	test_caster_nerf()
	test_rarity_levels()
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
	check(int(c["squads"][0]["tier"]) == GameData.MAX_TIER and int(c["squads"][0]["level"]) == Army.max_level("titan", GameData.MAX_TIER), "out-of-range values clamped")


func test_no_unit_cap() -> void:
	print("no unit cap")
	var squads := big_army(["goblin", "kobold_slinger", "rat_swarm", "skeleton", "orc_warrior", "elf_archer", "dire_wolf", "dwarf_berserker"], 10, 1)
	check(Army.total_units(squads) == 4 * 180 + 4 * 95, "every squad deploys at full size (got %d)" % Army.total_units(squads))


func test_maps() -> void:
	print("maps")
	check(BattleMaps.map_ids().size() == 20, "20 battlefields for normal play (+%d challenge-only)" % (BattleMaps.MAPS.size() - 20))
	var a := big_army(["goblin", "elf_archer", "ogre", "griffon"], 4, 8)
	var b := big_army(["skeleton", "kobold_slinger", "orc_warrior", "lich"], 4, 8)
	for id in BattleMaps.MAPS:
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
	var recorded: Array = []
	room.battle_recorded.connect(func(squads: Array, score: float): recorded.append([squads, score]))
	var human_results: Array = []
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
					human_results.append(float(m[2][0]["outcome"]))
					room.shop_ready(42, room.round_num)
	check(room.phase == "over", "match finished (%d rounds played by the human)" % rounds)
	check(recorded.size() == human_results.size() and recorded.map(func(r): return r[1]) == human_results,
		"unit stats get the human's board and result every battle, never the bots' (%d battles)" % recorded.size())
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
		for rule in DropRates.pity_rules():
			since[rule["rarity"]] = 0
		if GameData.region_drops(region).is_empty():
			continue
		for i in 300:
			profile.data["maps"] = 99
			profile.data["pending_choice"] = {}
			profile.data["rating"] = 5000
			var res: Dictionary = profile.explore(region)
			var best := 0
			for o in res["options"]:
				best = maxi(best, int(GameData.RARITIES[GameData.UNITS[o["unit"]]["rarity"]]["order"]))
			for rule in DropRates.pity_rules():
				var r: String = rule["rarity"]
				var need := int(GameData.RARITIES[r]["order"])
				if not GameData.region_drops(region).keys().any(func(u): return int(GameData.RARITIES[GameData.UNITS[u]["rarity"]]["order"]) >= need):
					continue   # nothing that rare here (Badlands Camp has no epics)
				since[r] = 0 if best >= need else int(since[r]) + 1
				worst[r] = maxi(int(worst.get(r, 0)), int(since[r]))
			profile.data["pending_choice"] = {}
	for rule in DropRates.pity_rules():
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
	check(locked.size() == 32 and GameData.UNITS.size() == 100, "100 units, 32 of the 0.9 set locked by default (Badlands Camp's 8 and the 0.9.4 ones open)")
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
	check(UnitLocks.locked_list() == ["goblin"], "'unlock new' releases every unit locked by default")
	party.run_command("lock reset")
	check(UnitLocks.locked_list().size() == 32 and not UnitLocks.is_locked("goblin"), "'lock reset' restores the defaults")
	# Expedition regions.
	check(GameData.REGIONS.size() == 17 and UnitLocks.locked_regions().size() == 7, "17 regions, 7 from 0.9 locked by default")
	party.run_command("lock region badlands")
	party.run_command("lock all")
	check(not UnitLocks.is_region_locked("badlands"), "Badlands Camp can't be locked: there's always somewhere to explore")
	party.run_command("lock reset")
	var new_only := true
	for rid in UnitLocks.default_regions():
		if not GameData.REGIONS[rid]["drops"].keys().any(func(id): return bool(GameData.UNITS[id].get("locked", false))):
			new_only = false
	for rid in ["warrens", "crypt", "forest", "deep", "peaks", "badlands"]:
		for id in GameData.REGIONS[rid]["drops"]:
			if bool(GameData.UNITS[id].get("locked", false)):
				new_only = false
	check(new_only, "every locked region has locked units; the open starting regions have none")
	profile.data["maps"] = 99
	profile.data["rating"] = 5000
	profile.data["pending_choice"] = {}
	check(not profile.can_explore("dragons_hoard") and profile.explore("dragons_hoard").is_empty(), "a locked region can't be explored")
	party.run_command("unlock storm_dragon")
	check(not UnitLocks.is_region_locked("dragons_hoard") and profile.can_explore("dragons_hoard"), "unlocking a unit also unlocks the regions it drops in")
	var only_storm := true
	for i in 10:
		profile.data["pending_choice"] = {}
		profile.data["maps"] = 99
		for o in profile.explore("dragons_hoard")["options"]:
			if o["unit"] != "storm_dragon":
				only_storm = false
	check(only_storm, "an auto-unlocked region still only offers unlocked units")
	party.run_command("lock reset")
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
	check(UnitLocks.locked_regions().size() == 7 and UnitLocks.locked_list().size() == 32, "'lock reset' re-locks the new units and regions")
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
	check(not states.is_empty() and (states[0]["excluded"] as Array).size() == 32, "match state carries the server's locks to clients")
	profile.data = backup
	profile.save()


func test_ranked_pool() -> void:
	print("ranked matchmaking pool")
	var pool := RankedPool.new()
	var code := Army.encode("P", 1000, [{"unit": "goblin", "level": 3, "tier": 2, "row": "front"}])
	for r in [700, 940, 985, 1000, 1010, 1060, 1400]:
		pool.add("pid%d" % r, "Player %d" % r, r, code)
	pool.add("me", "Me", 1000, code)
	check(not pool.add("bad", "Bad", 1000, "garbage"), "invalid army codes are rejected")
	pool.add("pid1000", "Player 1000", 1003, code)
	check(pool.entries.size() == 8 and int(pool.entries["pid1000"]["rating"]) == 1003, "one saved army per player (latest replaces older)")
	var found := pool.find(1000, "me", 3)
	var ratings: Array = []
	var has_me := false
	for e in found:
		ratings.append(int(e["rating"]))
		if e["pid"] == "me":
			has_me = true
	check(found.size() == 3 and not has_me, "finds 3 opponents and never your own army (got %s)" % [ratings])
	check(int(found[0]["rating"]) == 1003, "closest rating first")
	var below := false
	var above := false
	for r in ratings:
		if int(r) <= 1000:
			below = true
		if int(r) >= 1000:
			above = true
		if absi(int(r) - 1000) > 100:
			below = false
	check(below and above, "one at/below and one at/above, all within 100 rating")
	var far := pool.find(2000, "me", 3)
	check(far.size() == 3 and int(far[0]["rating"]) == 1400, "the search window widens when nobody is close")
	pool.entries["pid700"]["saved_at"] = 1000
	pool.prune()
	check(not pool.entries.has("pid700"), "armies older than 30 days are dropped")


func test_passwords() -> void:
	print("password hashing")
	# RFC 7914 section 11 / Python hashlib test vectors for PBKDF2-HMAC-SHA256.
	check(Passwords.pbkdf2_sha256("passwd", "salt".to_utf8_buffer(), 1).hex_encode().begins_with("55ac046e56e3089fec1691c22544b605"), "PBKDF2 matches RFC 7914 (c=1)")
	check(Passwords.pbkdf2_sha256("password", "salt".to_utf8_buffer(), 4096).hex_encode() == "c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a", "PBKDF2 matches the reference (c=4096)")
	var rec := Passwords.make_record("hunter22", 1000)
	check(rec.has("salt") and rec.has("hash") and int(rec["iterations"]) == 1000, "a record holds salt, hash and iteration count")
	check(not JSON.stringify(rec).contains("hunter22"), "the record never contains the password")
	check(Passwords.verify("hunter22", rec), "the right password verifies")
	check(not Passwords.verify("hunter23", rec), "a wrong password is rejected")
	var rec2 := Passwords.make_record("hunter22", 1000)
	check(rec2["salt"] != rec["salt"] and rec2["hash"] != rec["hash"], "the same password gets a different salt and hash each time")
	check(Passwords.ITERATIONS >= 600000, "default work factor is at least 600,000 iterations")
	check(Passwords.check_new_password("abc") != "" and Passwords.check_new_password("longenough") == "", "short passwords are refused")
	var t := Passwords.random_token()
	check(t.length() == 64 and t != Passwords.random_token(), "tokens are 256 random bits")


func test_accounts() -> void:
	print("server accounts")
	var dir := "user://test_accounts_%d" % Time.get_ticks_usec()
	var store := AccountStore.new(dir)
	check(AccountStore.check_username("ab") != "" and AccountStore.check_username("bad name!") != "" and AccountStore.check_username("Good_Name1") == "", "usernames are validated")
	store.create("Tester", Passwords.make_record("secret-pass", 1000))
	check(store.exists("tester") and store.exists("TESTER"), "usernames are case-insensitive")
	var token := store.issue_token("Tester")
	check(store.check_token("Tester", token), "an issued token works")
	check(not store.check_token("Tester", Passwords.random_token()), "a random token doesn't")
	var pl := store.logic("Tester")
	pl.data["gold"] = 12345
	store.save("Tester")
	var text := FileAccess.get_file_as_string(dir + "/tester.json")
	check(text != "" and not text.contains("secret-pass"), "the account file doesn't contain the password")
	check(not text.contains(token), "the account file doesn't contain the login token (only its hash)")
	var fresh := AccountStore.new(dir)
	check(int(fresh.logic("Tester").gold()) == 12345, "profiles are saved on the server and reload")
	check(Passwords.verify("secret-pass", fresh.get_record("Tester")["password"]), "the password still verifies after reloading")
	fresh.revoke_token("Tester", token)
	check(not fresh.check_token("Tester", token), "a revoked token stops working")
	var t2 := fresh.issue_token("Tester")
	fresh.set_password("Tester", Passwords.make_record("new-secret", 1000))
	check(not fresh.check_token("Tester", t2), "changing the password signs out every device")
	for i in 8:
		fresh.issue_token("Tester")
	check((fresh.get_record("Tester")["tokens"] as Dictionary).size() <= AccountStore.MAX_TOKENS, "only the newest few tokens are kept")
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir + "/" + f)
	DirAccess.remove_absolute(dir)


func test_profile_logic() -> void:
	print("server-side profile rules")
	var pl := ProfileLogic.new()
	var owned: Array = pl.data["units"].keys()
	check(owned.size() > 0, "a new profile starts with units")
	pl.set_army([{"unit": owned[0], "row": "back"}, {"unit": owned[0], "row": "front"}, {"unit": "not_a_unit", "row": "front"}, {"unit": owned[0 if owned.size() < 2 else 1], "row": "sideways"}])
	var army: Array = pl.data["army"]
	var ids := {}
	for e in army:
		ids[e["unit"]] = true
	check(not ids.has("not_a_unit") and ids.size() == army.size(), "set_army drops unowned and duplicate units")
	check(army[0]["row"] == "back" and army.back()["row"] in GameData.ROWS, "set_army keeps valid rows and fixes bad ones")
	pl.data["gold"] = 0
	var id: String = owned[0]
	var lvl := int(pl.unit(id)["level"])
	pl.level_up(id)
	check(int(pl.unit(id)["level"]) == lvl, "can't level up without gold")
	pl.data["gold"] = 1000000
	pl.level_up(id)
	check(int(pl.unit(id)["level"]) == lvl + 1, "level up spends gold")
	pl.data["maps"] = 0
	var region := ""
	for r in GameData.REGIONS:
		if pl.region_unlocked(r) and not UnitLocks.is_region_locked(r):
			region = r
			break
	check(pl.explore(region).is_empty(), "can't explore without a scouting map")
	pl.data["maps"] = 1
	var choice := pl.explore(region)
	check(choice.has("options") and pl.has_pending_choice(), "exploring rolls a recruit choice")
	var res := pl.choose_recruit(0)
	check(res.has("unit") and not pl.has_pending_choice(), "choosing a recruit resolves it")
	check(pl.choose_recruit(0).is_empty(), "a choice can't be taken twice")


func test_trinkets() -> void:
	print("trinkets")
	var counts := {}
	var names := {}
	var known_keys := ["hp_mult", "dmg_mult", "cooldown_mult", "speed_mult", "count_mult", "range_add", "aoe_add", "regen_pct", "lifesteal", "thorns", "armor", "damage", "flying"]
	var bad_keys: Array = []
	var missing_icons: Array = []
	for id in Trinkets.ALL:
		var t: Dictionary = Trinkets.ALL[id]
		counts[t["rarity"]] = int(counts.get(t["rarity"], 0)) + 1
		names[t["name"]] = true
		for k in t["mods"]:
			if k not in known_keys:
				bad_keys.append("%s.%s" % [id, k])
		if not ResourceLoader.exists("res://assets/sprites/items/%s.png" % id):
			missing_icons.append(id)
	check(Trinkets.ALL.size() == 100 and names.size() == 100, "100 trinkets with unique names")
	check(counts == {"common": 30, "uncommon": 25, "rare": 20, "epic": 15, "legendary": 10}, "30/25/20/15/10 by rarity (%s)" % [counts])
	check(bad_keys.is_empty(), "every trinket uses only supported battle effects %s" % [bad_keys])
	check(missing_icons.is_empty(), "every trinket has an icon %s" % [missing_icons])

	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var camp_ok := true
	for i in 200:
		for t in Trinkets.roll_hunt("camp", {}, rng):
			if Trinkets.rarity_of(t) in ["epic", "legendary"]:
				camp_ok = false
	check(camp_ok, "the war camp never offers epic or legendary trinkets")
	var all_commons := {}
	for t in Trinkets.ids_by_rarity("common"):
		all_commons[t] = true
	var owned_but_one := all_commons.duplicate()
	owned_but_one.erase("iron_band")
	var prefers_new := true
	for i in 50:
		var offer := Trinkets.roll_hunt("camp", owned_but_one, rng)
		var commons: Array = offer.filter(func(t): return Trinkets.rarity_of(t) == "common")
		if not commons.is_empty() and not commons.has("iron_band"):
			prefers_new = false
	check(prefers_new, "hunts offer trinkets you don't own yet before repeats")

	var pl := ProfileLogic.new()
	pl.data["maps"] = 10
	pl.data["rating"] = 1300
	check(not pl.equip_trinket("goblin", 0, "octoring"), "can't equip a trinket you don't own")
	var choice := pl.hunt_trinkets("trove")
	check(choice.get("options", []).size() == 3 and pl.maps() == 7, "a hunt spends maps and offers 3 trinkets")
	check(pl.hunt_trinkets("camp").is_empty(), "can't hunt again before choosing")
	var first: String = choice["options"][0]
	var res := pl.choose_trinket(0)
	check(res["trinket"] == first and res["new"] and pl.owns_trinket(first), "choosing keeps the trinket")
	pl.data["trinkets"]["iron_band"] = true
	pl.data["pending_trinket"] = {"site": "camp", "options": ["iron_band", "copper_band", "bronze_band"]}
	var gold_before := pl.gold()
	var dup := pl.choose_trinket(0)
	check(not dup["new"] and pl.gold() == gold_before + int(Trinkets.DUPLICATE_GOLD["common"]), "a trinket you already own is sold for gold")
	for t in ["octoring", "tiger_eye_ring", "standard_of_the_legion"]:
		pl.data["trinkets"][t] = true
	check(pl.equip_trinket("goblin", 0, "octoring") and pl.equip_trinket("goblin", 1, "tiger_eye_ring"), "two trinkets fit on a unit")
	check(not pl.equip_trinket("goblin", 2, "iron_band"), "there is no third slot")
	pl.equip_trinket("rat_swarm", 0, "octoring")
	check(pl.trinket_holder("octoring") == "rat_swarm" and not pl.trinkets_of("goblin").has("octoring"), "equipping a trinket elsewhere moves it")
	check(pl.unequip_trinket("rat_swarm", 0) and pl.trinkets_of("rat_swarm").is_empty(), "trinkets can be taken off")
	# Bad saved data is cleaned up.
	var messy := ProfileLogic.new({"trinkets": {"octoring": true, "not_real": true}, "units": {"goblin": {"level": 1, "tier": 0, "trinkets": ["octoring", "not_real", "iron_band"]},
		"rat_swarm": {"level": 1, "tier": 0, "trinkets": ["octoring"]}}})
	check(messy.trinkets_of("goblin") == ["octoring"] and messy.trinkets_of("rat_swarm").is_empty() and not messy.owns_trinket("not_real"), "saves can't hold unknown, unowned or doubled-up trinkets")

	# Trinkets in battle.
	var plain := {"unit": "orc_warrior", "level": 5, "tier": 2, "row": "front"}
	var geared := plain.merged({"trinkets": ["dragon_kings_crest", "standard_of_the_legion"]})
	check(Army.deploy_counts([geared])[0] == roundi(Army.squad_size("orc_warrior", 2) * 1.4), "Standard of the Legion adds 40% units")
	check(Army.army_power([geared]) > Army.army_power([plain]) * 1.5, "trinkets raise army power")
	var sim := BattleSim.new()
	sim.setup([geared], [plain], 3, "open_arena")
	var base_hp: float = Army.unit_stats("orc_warrior", Army.stat_level("orc_warrior", 5))["hp"]
	check(is_equal_approx(sim.max_hp[0], base_hp * 1.25), "the sim applies trinket HP (%.1f vs %.1f)" % [sim.max_hp[0], base_hp * 1.25])
	var a := BattleSim.new()
	a.setup([geared], [plain], 11, "open_arena")
	a.run_to_end(200000)
	var b := BattleSim.new()
	b.setup([geared], [plain], 11, "open_arena")
	b.run_to_end(200000)
	check(a.checksum() == b.checksum(), "battles with trinkets stay deterministic")

	# Army codes carry trinkets.
	var code := Army.encode("T", 1000, [geared, plain])
	var back := Army.decode(code)
	check(back["squads"][0].get("trinkets", []) == ["dragon_kings_crest", "standard_of_the_legion"] and not back["squads"][1].has("trinkets"), "army codes keep trinkets")
	var forged := Army.CODE_PREFIX + Marshalls.utf8_to_base64(JSON.stringify({"n": "x", "r": 1, "s": [["goblin", 1, 0, 0, ["octoring", "octoring", "fake", "iron_band"]], ["rat_swarm", 1, 0, 0, ["octoring"]]]}))
	var f := Army.decode(forged)
	check(f["squads"][0]["trinkets"] == ["octoring", "iron_band"] and not f["squads"][1].has("trinkets"), "codes can't hold fake, extra or doubled-up trinkets")
	var old_code := Army.CODE_PREFIX + Marshalls.utf8_to_base64(JSON.stringify({"n": "x", "r": 1, "s": [["goblin", 3, 1, 0]]}))
	check(Army.decode(old_code)["squads"].size() == 1, "older codes without trinkets still work")


func test_harder_ghosts() -> void:
	print("ranked opponents")
	var mine := Army.rank_power(1100)
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var total := 0.0
	var n := 0
	for i in 40:
		var offers: Array = []
		Army.fill_ghosts(offers, 1100, rng)
		for o in offers:
			total += Army.army_power(o["squads"]) / mine
			n += 1
	var avg := total / float(n)
	check(avg > 1.12 and avg < 1.25, "generated opponents average %.2fx the power expected at their rating (Easy 0.9x, Even 1.1x, Hard 1.5x)" % avg)
	var low := Army.generate_opponent(5000.0, 900, 5)
	var low_has: bool = low["squads"].any(func(sq): return sq.has("trinkets"))
	var high_count := 0
	for seed_i in 10:
		for sq in Army.generate_opponent(20000.0, 1500, seed_i)["squads"]:
			if sq.has("trinkets"):
				high_count += 1
	check(not low_has and high_count >= 10, "high-rated opponents carry trinkets, low-rated ones don't (%d squads)" % high_count)


func test_leaderboard() -> void:
	print("leaderboard")
	var dir := "user://test_board_%d" % Time.get_ticks_usec()
	var store := AccountStore.new(dir)
	var rec := Passwords.make_record("whatever1", 1000)
	for spec in [["alice", 1250, 10, 2], ["bob", 1100, 5, 5], ["cara", 1250, 12, 4], ["dan", 1000, 0, 0]]:
		store.create(spec[0], rec)
		var pl := store.logic(spec[0])
		pl.data["rating"] = spec[1]
		pl.data["wins"] = spec[2]
		pl.data["losses"] = spec[3]
		store.save(spec[0])
	var fresh := AccountStore.new(dir)   # built from the files
	var names: Array = fresh.leaderboard(10).map(func(e): return e["name"])
	check(names == ["cara", "alice", "bob"], "sorted by rating, then wins; players with no ranked games left out (%s)" % [names])
	check(fresh.rank_of("ALICE")["rank"] == 2 and fresh.rank_of("dan")["rank"] == 0, "your own rank is found (any letter case)")
	var pb := fresh.logic("bob")
	pb.data["rating"] = 1400
	fresh.save("bob")
	check(fresh.leaderboard(1)[0]["name"] == "bob", "the leaderboard updates when a profile is saved")
	check(fresh.leaderboard(2).size() == 2, "the size limit is respected")
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir + "/" + f)
	DirAccess.remove_absolute(dir)


func test_drop_rates() -> void:
	print("drop chances")
	DropRates.reset()
	check(is_equal_approx(DropRates.unit_mult["legendary"], 0.5) and DropRates.pity["legendary"] == 60 and is_equal_approx(DropRates.trinket_mult["legendary"], 0.5), "legendaries are rarer by default (half weight, guaranteed every 60)")
	var pl := ProfileLogic.new()
	var rarer := pl.drop_chance("peaks", "golden_dragon")
	DropRates.apply({"unit": {"legendary": 1.0}})
	var before := pl.drop_chance("peaks", "golden_dragon")
	check(rarer < before * 0.6, "Golden Dragon in Dragon Peaks: %.1f%% now, %.1f%% at the old weight" % [rarer * 100.0, before * 100.0])
	DropRates.apply({"unit": {"legendary": 0}, "pity": {"legendary": 0}})
	check(not GameData.region_drops("peaks").has("golden_dragon") and pl.drop_chance("peaks", "golden_dragon") == 0.0, "a multiplier of 0 switches a rarity off")
	pl.data["rating"] = 5000
	var saw_legendary := false
	for i in 200:
		pl.data["maps"] = 10
		pl.data["pending_choice"] = {}
		for o in pl.explore("peaks")["options"]:
			if GameData.UNITS[o["unit"]]["rarity"] == "legendary":
				saw_legendary = true
	check(not saw_legendary, "no legendary units in 200 expeditions with legendaries switched off")
	check(pl.pity_remaining("legendary") == -1 and DropRates.pity_rules().size() == 2, "a guarantee set to 0 is off")
	DropRates.apply({"trinket": {"legendary": 0}})
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var t_leg := false
	for i in 200:
		for t in Trinkets.roll_hunt("trove", {}, rng):
			if Trinkets.rarity_of(t) == "legendary":
				t_leg = true
	check(not t_leg and Trinkets.site_odds("trove")["legendary"] == 0.0, "trinket rarities can be switched off too")
	DropRates.apply({"unit": {"rare": -5, "epic": 1e9}, "pity": {"rare": -1}})
	check(DropRates.unit_mult["rare"] == 0.0 and DropRates.unit_mult["epic"] == DropRates.MAX_MULT and DropRates.pity["rare"] == 0, "bad values are clamped")
	DropRates.reset()
	check(is_equal_approx(Trinkets.site_odds("trove")["legendary"], 5.0 / 95.0), "Dragon's Trove legendary odds %.1f%% (was 10%%)" % (Trinkets.site_odds("trove")["legendary"] * 100.0))

	var party := root.get_node("Party")
	check(party.run_command("drops").begins_with("Unit drops:"), "'drops' shows the settings")
	party.run_command("drops unit legendary 0.25")
	party.run_command("drops trinket epic 2")
	party.run_command("drops pity legendary 80")
	check(is_equal_approx(DropRates.unit_mult["legendary"], 0.25) and is_equal_approx(DropRates.trinket_mult["epic"], 2.0) and DropRates.pity["legendary"] == 80, "the console sets unit, trinket and guarantee settings")
	var saved = JSON.parse_string(FileAccess.get_file_as_string(party.CONFIG_PATH))
	check(typeof(saved) == TYPE_DICTIONARY and is_equal_approx(float(saved["drops"]["unit"]["legendary"]), 0.25), "drop settings are saved with the server config")
	check(party.run_command("drops unit mythic 2").begins_with("Usage") and party.run_command("drops pity common 3").begins_with("Usage"), "bad drop commands show usage")
	party.run_command("drops reset")
	check(DropRates.to_dict() == {"unit": DropRates.DEFAULT_UNIT, "trinket": DropRates.DEFAULT_TRINKET, "pity": DropRates.DEFAULT_PITY}, "'drops reset' restores the defaults")


func test_rank_progression() -> void:
	print("rank progression")
	var spire := int(GameData.REGIONS["celestial_spire"]["min_rating"])
	var needs: Array = []
	for rid in GameData.REGIONS:
		needs.append(int(GameData.REGIONS[rid]["min_rating"]))
	needs.sort()
	check(spire == 3500 and needs.back() == 3500, "Celestial Spire is the last region, at 3500 rating")
	var gaps_ok := true
	var prev := -1
	for n in needs:
		if n > needs[0] and prev > 0 and n - prev < 100:   # the starting regions share one rating
			gaps_ok = false
		prev = n
	check(gaps_ok, "at least 100 rating between region unlocks after the starting ones (%s)" % [needs])
	var pl := ProfileLogic.new()
	pl.data["rating"] = 1250
	check(pl.region_unlocked("warrens") and not pl.region_unlocked("forest") and not pl.region_unlocked("peaks"), "at 1250: Warrens open, Forest (1300) and Peaks (2500) not yet")

	check(is_equal_approx(Army.win_gold_mult(900), 1.0) and is_equal_approx(Army.win_gold_mult(2000), 2.0) and is_equal_approx(Army.win_gold_mult(3500), 3.5), "win gold x1 up to 1000, x2 at 2000, x3.5 at 3500")
	var low := ProfileLogic.new()
	low.data["rating"] = 1000
	var high := ProfileLogic.new()
	high.data["rating"] = 2000
	var g_low := int(low.apply_battle_result("ranked", 1.0, 1000, 0)["gold"])
	var hs := high.apply_battle_result("ranked", 1.0, 1000, 0)
	check(int(hs["gold"]) == g_low * 2 and is_equal_approx(float(hs["rank_mult"]), 2.0), "a win at 2000 rating pays double (%d vs %d gold)" % [int(hs["gold"]), g_low])
	var l_low := int(low.apply_battle_result("ranked", 0.0, 1000, 0)["gold"])
	var l_high := int(high.apply_battle_result("ranked", 0.0, 1000, 0)["gold"])
	check(l_low == l_high, "losses pay the same at any rating")

	var pool := RankedPool.new()
	pool.entries.clear()
	var code := Army.encode("x", 1000, [{"unit": "goblin", "level": 1, "tier": 0, "row": "front"}])
	for r in [1000, 1150, 1300, 1600, 2500]:
		pool.add("p%d" % r, "P%d" % r, r, code)
	var near: Array = pool.find(1000, "", 3, 200).map(func(e): return int(e["rating"]))
	near.sort()
	check(near == [1000, 1150], "only players within the range are offered (%s)" % [near])
	check(pool.find(2000, "", 3, 200).is_empty(), "nobody in range: no player armies (training opponents fill in)")
	var party := root.get_node("Party")
	party.run_command("ranked range 150")
	check(party.ranked_range == 150, "'ranked range 150' sets the range")
	var saved = JSON.parse_string(FileAccess.get_file_as_string(party.CONFIG_PATH))
	check(typeof(saved) == TYPE_DICTIONARY and int(saved.get("ranked_range", 0)) == 150, "the range is saved with the server config")
	party.run_command("ranked range 200")


func test_challenges() -> void:
	print("challenges")
	var ids := {}
	var bad: Array = []
	var prev_rec := 0
	var rec_ok := true
	for c in Challenges.LIST:
		ids[c["id"]] = true
		if not BattleMaps.MAPS.has(c["map"]):
			bad.append("%s: map %s" % [c["id"], c["map"]])
		for sq in c["enemy"]:
			if not GameData.UNITS.has(sq["unit"]) or int(sq.get("count", 0)) < 1:
				bad.append("%s: squad %s" % [c["id"], sq])
		var r: Dictionary = c["reward"]
		if r.has("trinket") and not Trinkets.exists(r["trinket"]):
			bad.append("%s: trinket %s" % [c["id"], r["trinket"]])
		if r.has("unit") and not GameData.UNITS.has(r["unit"]):
			bad.append("%s: unit %s" % [c["id"], r["unit"]])
		if int(c["recommended"]) < prev_rec:
			rec_ok = false
		prev_rec = int(c["recommended"])
	check(Challenges.LIST.size() == 12 and ids.size() == 12, "12 challenges with unique ids")
	check(bad.is_empty(), "every challenge uses real maps, units, trinkets and rewards %s" % [bad])
	check(rec_ok, "recommended power rises from the first challenge to the last")
	check(BattleMaps.MAPS.has("narrow_bridge") and not BattleMaps.map_ids().has("narrow_bridge"), "challenge-only battlefields are never picked at random")
	var boss: Array = Challenges.enemy_squads("gruk")
	var gruk_hp: float = Army.unit_stats("ogre", 5, boss[0]["mods"])["hp"]
	check(Army.deploy_counts(boss)[0] == 1 and gruk_hp > Army.unit_stats("ogre", 5)["hp"] * 20.0, "bosses are single units with boosted stats (Gruk: %d HP)" % roundi(gruk_hp))

	# Clear the first one with the starting army.
	var pl := ProfileLogic.new()
	var sim := BattleSim.new()
	sim.setup(pl.battle_squads(), Challenges.enemy_squads("rat_problem"), 5, "open_arena")
	sim.run_to_end(200000)
	check(sim.winner == 0, "a brand-new army beats the first challenge")
	check(pl.challenge_unlocked("rat_problem") and not pl.challenge_unlocked("goblin_raid"), "only the first challenge is open at the start")
	var gold0 := pl.gold()
	var maps0 := int(pl.data["maps"])
	var lost := pl.complete_challenge("rat_problem", false)
	check(not lost["first_clear"] and pl.gold() == gold0 and not pl.challenge_cleared("rat_problem"), "losing gives nothing and keeps the reward waiting")
	var won := pl.complete_challenge("rat_problem", true)
	check(won["first_clear"] and pl.gold() == gold0 + 150 and int(pl.data["maps"]) == maps0 + 1, "the first win pays the set reward (150 gold, 1 map)")
	check(pl.challenge_unlocked("goblin_raid"), "clearing a challenge opens the next")
	var again := pl.complete_challenge("rat_problem", true)
	check(not again["first_clear"] and pl.gold() == gold0 + 150, "replays don't pay again")
	check(pl.complete_challenge("hold_bridge", true)["first_clear"] == false, "a locked challenge can't be claimed")
	var tr := pl.complete_challenge("goblin_raid", true)
	check(tr["trinket"] == "copper_band" and tr["trinket_new"] and pl.owns_trinket("copper_band"), "trinket rewards go into your collection")
	pl.data["challenges"]["hold_bridge"] = true
	var ur := pl.complete_challenge("gruk", true)
	check(ur["unit_new"] and pl.owns("ogre"), "unit rewards join your collection (Ogre Brute)")
	var pl2 := ProfileLogic.new()
	pl2.data["units"]["ogre"] = {"level": 1, "tier": 0, "shards": 2}
	for cid in ["rat_problem", "goblin_raid", "hold_bridge"]:
		pl2.data["challenges"][cid] = true
	var dup := pl2.complete_challenge("gruk", true)
	check(not dup["unit_new"] and int(pl2.unit("ogre")["shards"]) == 2 + Challenges.DUPLICATE_UNIT_SHARDS, "a reward unit you already own gives shards")
	var saved := ProfileLogic.new({"challenges": {"gruk": true, "made_up": true}})
	check(saved.challenge_cleared("gruk") and not saved.challenge_cleared("made_up"), "saves keep only real challenges")

	# Every challenge battle resolves on its battlefield.
	var strong := big_army(["orc_warrior", "elf_archer", "ogre", "griffon", "lich", "dwarf_berserker"], 10, 30)
	var stuck: Array = []
	for c in Challenges.LIST:
		var s2 := BattleSim.new()
		s2.setup(strong, Challenges.enemy_squads(c["id"]), 9, c["map"])
		s2.run_to_end(200000)
		if not s2.finished:
			stuck.append(c["id"])
	check(stuck.is_empty(), "every challenge battle finishes %s" % [stuck])


## Count what a squad's living units are targeting after a few retargets.
func _targets_of(sim: BattleSim, uid: String) -> Array:
	var out: Array = []
	for i in sim.n:
		if sim.alive[i] == 1 and sim.unit_ids[sim.kind[i]] == uid and sim.team[i] == 0 and sim.target[i] >= 0:
			out.append(sim.target[i])
	return out


func test_target_modes() -> void:
	print("flying unit targeting")
	check(GameData.UNITS["griffon"].get("targets", "") == "ranged" and GameData.UNITS["cave_bat"].get("targets", "") == "healers"
		and GameData.UNITS["hippogriff"].get("targets", "") == "backline", "griffons hunt ranged units, cave bats hunt healers, hippogriffs dive for the back line")
	check(GameData.target_text("griffon") != "" and GameData.target_text("goblin") == "", "the Collection explains who a unit targets")
	var enemy := [{"unit": "orc_warrior", "level": 5, "count": 60, "row": "front"},
		{"unit": "gnoll_shaman", "level": 5, "count": 10, "row": "middle"},
		{"unit": "elf_archer", "level": 5, "count": 30, "row": "back"}]
	for spec in [["griffon", BattleSim.Role.RANGED, "ranged"], ["cave_bat", BattleSim.Role.HEALER, "healer"]]:
		var sim := BattleSim.new()
		sim.setup([{"unit": spec[0], "level": 5, "count": 12, "row": "front"}, {"unit": "goblin", "level": 5, "count": 40, "row": "front"}], enemy, 4, "open_arena")
		for k in 15:
			sim.step()
		var picked := _targets_of(sim, spec[0])
		var hits := picked.filter(func(j): return sim.role[j] == spec[1]).size()
		check(picked.size() > 0 and hits == picked.size(), "%s go after %s units first (%d of %d)" % [spec[0], spec[2], hits, picked.size()])
		var goblins := _targets_of(sim, "goblin")
		var front := goblins.filter(func(j): return sim.unit_ids[sim.kind[j]] == "orc_warrior").size()
		check(front * 2 > goblins.size(), "ordinary units still fight the nearest enemies")
	var sim2 := BattleSim.new()
	sim2.setup([{"unit": "hippogriff", "level": 5, "count": 12, "row": "front"}], enemy, 4, "open_arena")
	for k in 15:
		sim2.step()
	var deep := 0
	var picked2 := _targets_of(sim2, "hippogriff")
	var max_x := 0.0
	for j in sim2.n:
		if sim2.team[j] == 1:
			max_x = maxf(max_x, sim2.px[j])
	for j in picked2:
		if sim2.px[j] > max_x - 250.0:
			deep += 1
	check(picked2.size() > 0 and deep == picked2.size(), "hippogriffs dive for the rear of the enemy formation (%d of %d)" % [deep, picked2.size()])
	# No healers left: cave bats fall back to ranged units, then anyone.
	var sim3 := BattleSim.new()
	sim3.setup([{"unit": "cave_bat", "level": 5, "count": 8, "row": "front"}], [{"unit": "goblin", "level": 1, "count": 20, "row": "front"}], 4, "open_arena")
	sim3.run_to_end(200000)
	check(sim3.finished, "units with a preferred target still fight when none are left")
	var a := BattleSim.new()
	a.setup([{"unit": "griffon", "level": 5, "count": 12, "row": "front"}, {"unit": "hippogriff", "level": 5, "count": 12, "row": "front"}], enemy, 77, "goblin_warrens")
	a.run_to_end(200000)
	var b := BattleSim.new()
	b.setup([{"unit": "griffon", "level": 5, "count": 12, "row": "front"}, {"unit": "hippogriff", "level": 5, "count": 12, "row": "front"}], enemy, 77, "goblin_warrens")
	b.run_to_end(200000)
	check(a.checksum() == b.checksum(), "battles with targeting stay deterministic")


func test_power_formula() -> void:
	print("army power")
	var big := Army.army_power([{"unit": "goblin", "level": 1, "count": 120, "row": "front"}])
	var small := Army.army_power([{"unit": "goblin", "level": 1, "count": 60, "row": "front"}])
	check(absf(big / small - 1.8) < 0.05, "doubling a melee squad counts as about 1.8x power (%.2fx)" % (big / small))
	var ra := Army.army_power([{"unit": "elf_archer", "level": 1, "count": 60, "row": "back"}])
	var rb := Army.army_power([{"unit": "elf_archer", "level": 1, "count": 30, "row": "back"}])
	check(is_equal_approx(ra / rb, 2.0), "ranged squads still count every unit")
	# Equal power should mean an even fight: level up a squad of 60 goblins
	# until it beats 120 goblins; that should happen close to equal power.
	var target := Army.squad_power("goblin", 1, 120)
	var crossover := 0.0
	for level in range(1, 25):
		var wins := 0
		for seed_i in 4:
			var sim := BattleSim.new()
			sim.setup([{"unit": "goblin", "level": 1, "count": 120, "row": "front"}], [{"unit": "goblin", "level": level, "count": 60, "row": "front"}], 40 + seed_i, "open_arena")
			sim.run_to_end(200000)
			if sim.winner == 1:
				wins += 1
		if wins >= 2:
			crossover = Army.squad_power("goblin", level, 60) / target
			break
	check(crossover > 0.85 and crossover < 1.15, "half as many melee units win at about equal power (%.2fx)" % crossover)


func test_ranged_splash_nerf() -> void:
	print("ranged splash (patches 0.9, 0.9.1)")
	# The same hit, once as a melee blow and once as a projectile: the units
	# next to the target take less from the projectile's splash.
	var lost := []
	for melee in [true, false]:
		var sim := BattleSim.new()
		sim.setup([{"unit": "lich", "level": 1, "count": 1, "row": "back"}], [{"unit": "ogre", "level": 30, "count": 4, "row": "front"}], 5, "open_arena")
		var targets: Array = []
		for i in sim.team.size():
			if sim.team[i] == 1:
				targets.append(i)
		for k in targets.size():
			sim.px[targets[k]] = 600.0 + 4.0 * k
			sim.py[targets[k]] = 400.0
		sim._rebuild_grid()
		var before := 0.0
		for k in range(1, targets.size()):
			before += sim.hp[targets[k]]
		sim._deal_damage(-1, 0, 0, 100.0, targets[0], 600.0, 400.0, 40.0, melee)
		var after := 0.0
		for k in range(1, targets.size()):
			after += sim.hp[targets[k]]
		lost.append(before - after)
	check(lost[1] > 0.0 and absf(lost[1] / lost[0] - BattleSim.RANGED_SPLASH_MULT / BattleSim.AOE_SPLASH_MULT) < 0.001,
		"projectile splash deals %.0f%% of melee splash (%.1f vs %.1f)" % [100.0 * lost[1] / lost[0], lost[1], lost[0]])
	check(is_equal_approx(BattleSim.RANGED_SPLASH_MULT, 0.35) and is_equal_approx(BattleSim.AOE_SPLASH_MULT, 0.45), "ranged splash 35% of the hit (0.9.1), melee splash 45% (0.9.2)")
	# Strength follows: a splash caster lost power, a melee splasher didn't.
	var caster := Army.unit_power("orc_sorcerer", 1) / _old_power("orc_sorcerer")
	var brute := Army.unit_power("hill_giant", 1) / _old_power("hill_giant")
	check(caster < brute and brute < 1.0 and is_equal_approx(Army.unit_power("goblin", 1), _old_power("goblin")), "splash counts for less in Strength, ranged splash most (%.2fx, %.2fx)" % [caster, brute])
	check(PatchNotes.latest() == UnitStats.current_patch(), "the patch notes cover this version (%s)" % PatchNotes.latest())


## Unit power with the pre-0.9 splash formula (every splash counted fully).
func _old_power(unit_id: String) -> float:
	var s := Army.unit_stats(unit_id, 1)
	var dmg := float(s["dmg"]) / Army.dmg_nerf(unit_id)   # before any damage nerfs
	var dps: float = (dmg * (1.0 + minf(float(s["aoe"]), 60.0) / 40.0) + float(s["heal"]) * 1.5) / float(s["cooldown"]) + float(s["regen"])
	return sqrt(float(s["hp"]) * dps * (1.0 + minf(float(s["range"]), 260.0) / 520.0)) * float(GameData.RARITIES[s["rarity"]]["power_mult"])


func test_unit_stats() -> void:
	print("unit stats (server)")
	var st := UnitStats.new()
	var patch := UnitStats.current_patch()
	st.record("ranked", [{"unit": "goblin"}, {"unit": "goblin"}, {"unit": "elf_archer"}], 1.0)
	st.record("ranked", [{"unit": "goblin"}], 0.0)
	st.record("ranked", [{"unit": "lich"}], 0.5)
	st.record("draft", [{"unit": "goblin"}, {"unit": "ogre"}], 0.0)
	st.record("draft", [{"unit": "nope"}], 1.0)          # unknown units are ignored
	st.record("challenge", [{"unit": "goblin"}], 1.0)     # only ranked and draft count
	check(st.armies(patch, "ranked") == 3 and st.armies(patch, "draft") == 1, "armies counted per mode")
	var rows := {}
	for r in st.rows(patch):
		rows[r["unit"]] = r
	var g: Dictionary = rows["goblin"]["ranked"]
	check(g["games"] == 2 and g["wins"] == 1 and g["losses"] == 1, "a unit counts once per army (goblin 1-1 in ranked)")
	check(is_equal_approx(g["use"], 2.0 / 3.0) and is_equal_approx(g["win"], 0.5), "use rate and win rate")
	check(is_equal_approx(rows["lich"]["ranked"]["win"], 0.5) and rows["lich"]["ranked"]["draws"] == 1, "draws count half")
	check(rows["ogre"]["draft"]["losses"] == 1 and is_equal_approx(rows["ogre"]["draft"]["use"], 1.0) and rows["ogre"]["ranked"]["games"] == 0, "draft kept apart from ranked")
	var text := st.report(PackedStringArray())
	check(text.contains("Goblin Skirmisher") and text.contains("66.7%") and text.contains("3 ranked armies") and not text.contains("Titan"), "the console table lists used units with their rates")
	check(st.report(PackedStringArray(["draft", "win"])).contains("Sorted by draft win"), "the table can be sorted by one mode")
	check(st.report(PackedStringArray(["bogus"])).begins_with("Unknown option"), "bad options explain the usage")
	check(st.report(PackedStringArray(["all"])).contains("Titan"), "'all' includes unused units")


func test_rating_speed() -> void:
	print("rating speed (patch 0.9)")
	check(Army.elo_delta(1000, 1000, 1.0) == 12 and Army.elo_delta(1000, 1000, 0.0) == -12, "an even battle at 1000 is +12 / -12")
	check(Army.elo_delta(3200, 3200, 1.0) == 6, "an even win near the top is +6")
	var mid := Army.elo_delta(2100, 2100, 1.0)
	check(mid > 6 and mid < 12, "in between in the middle of the ladder (+%d at 2100)" % mid)
	# With the measured odds (an ordinary army), no tier pays on average.
	var odds := {"Easy": 0.55, "Even": 0.21, "Hard": 0.05}
	for t in Army.GHOST_TIERS:
		var p: float = odds[t[2]]
		var ev := p * Army.elo_delta(1500, 1500 + int(t[1]), 1.0) + (1.0 - p) * Army.elo_delta(1500, 1500 + int(t[1]), 0.0)
		check(ev < 0.5, "%s opponents are no free climb (%.2f rating per battle on average)" % [t[2], ev])
	check(Army.elo_delta(1000, 1000 + int(Army.GHOST_TIERS[2][1]), 1.0) > Army.elo_delta(1000, 1000 + int(Army.GHOST_TIERS[0][1]), 1.0) + 5, "beating Hard pays clearly more than beating Easy")


func test_difficulty() -> void:
	print("difficulty (server setting)")
	var party := root.get_node("Party")
	Difficulty.reset()
	check(Difficulty.is_default() and Difficulty.tiers == Army.GHOST_TIERS, "defaults are the built-in ranked tiers")
	var mine := Army.rank_power(1100)
	var hard_power := func() -> float:
		var rng := RandomNumberGenerator.new()
		rng.seed = 4
		var total := 0.0
		for i in 10:
			var offers: Array = []
			Army.fill_ghosts(offers, 1100, rng)
			total += Army.army_power(offers[2]["squads"]) / mine
		return total / 10.0
	var before: float = hard_power.call()
	check(party.run_command("difficulty hard 2.0 200").begins_with("Difficulty updated"), "the console sets a tier")
	var after: float = hard_power.call()
	check(after > before * 1.2 and Difficulty.tiers[2][1] == 200, "Hard opponents follow it (%.2fx -> %.2fx your power)" % [before, after])
	party.run_command("difficulty ranked 0.5")
	check(is_equal_approx(Difficulty.tiers[0][0], 0.45) and is_equal_approx(Difficulty.tiers[2][0], 1.0), "'difficulty ranked' scales every tier")
	var wyrm := Challenges.enemy_power("golden_wyrm")
	var rec := Challenges.recommended("golden_wyrm")
	party.run_command("difficulty challenges 1.5")
	check(absf(Challenges.enemy_power("golden_wyrm") / wyrm - 1.5) < 0.01 and Challenges.recommended("golden_wyrm") == roundi(rec * 1.5), "challenge enemies and their recommended power scale")
	check(Challenges.get_challenge("golden_wyrm")["enemy"][0]["mods"]["hp_mult"] == 150.0, "the challenge data itself is untouched")
	var saved := Difficulty.to_dict()
	Difficulty.reset()
	Difficulty.apply(saved)
	check(is_equal_approx(Difficulty.challenge_mult, 1.5) and Difficulty.tiers[2][1] == 200, "settings survive a save and reload (sent to players the same way)")
	Difficulty.apply({"hard": [99, 99999], "challenges": -3, "even": "junk"})
	check(Difficulty.tiers[2][0] == Difficulty.MAX_POWER and Difficulty.tiers[2][1] == Difficulty.MAX_RATING_OFFSET and Difficulty.challenge_mult == Difficulty.MIN_CHALLENGE and Difficulty.tiers[1] == Army.GHOST_TIERS[1], "bad values are clamped or ignored")
	check(party.run_command("difficulty sideways 2").begins_with("Usage"), "bad commands show usage")
	party.run_command("difficulty reset")
	check(Difficulty.is_default(), "reset restores the defaults")


## Runs a battle step by step, counting events and status-effect ticks.
func _ability_battle(squads_a: Array, squads_b: Array, seed_v: int = 3) -> Dictionary:
	var sim := BattleSim.new()
	sim.setup(squads_a, squads_b, seed_v, "open_arena")
	var out := {"sim": sim, "ev": {}, "stun": 0, "chill": 0, "burn": 0, "curse": 0, "weaken": 0}
	while not sim.finished and sim.tick < 3000:
		sim.step()
		for e in sim.drain_events():
			out["ev"][e[0]] = int(out["ev"].get(e[0], 0)) + 1
		for i in sim.n:
			for k in ["stun", "chill", "burn", "curse", "weaken"]:
				if (sim.get(k + "_until") as PackedInt32Array)[i] > sim.tick:
					out[k] += 1
	return out


func test_abilities() -> void:
	print("battle abilities (patch 0.9.2)")
	var splashers: Array = GameData.UNITS.keys().filter(func(u): return float(GameData.UNITS[u]["aoe"]) > 0.0)
	var with_ability: Array = GameData.UNITS.keys().filter(func(u): return not GameData.ability_of(u).is_empty())
	check(splashers.size() == 6 and with_ability.size() == 63, "splash is rare now: %d units splash, %d have abilities" % [splashers.size(), with_ability.size()])
	var big: Array = GameData.UNITS.keys().filter(func(u): return GameData.UNITS[u]["rarity"] in ["epic", "legendary"])
	var big_ids: Array = big.map(func(u): return str(GameData.ability_of(u).get("id", "")))
	check(big_ids.all(func(x): return x != "" and big_ids.count(x) == 1), "every epic and legendary has an ability of its own (%d units)" % big.size())
	check(with_ability.all(func(u): return BattleSim.AB_IDS.has(GameData.ability_of(u)["id"]) and GameData.ability_text(u) != ""), "every ability is simulated and described")
	check(is_equal_approx(BattleSim.AOE_SPLASH_MULT, 0.45), "melee splash nerfed to 45% of the blow")
	UnitLocks.set_locked_list([])
	var foes := [{"unit": "orc_warrior", "level": 6, "tier": 6, "row": "front"}, {"unit": "elf_archer", "level": 6, "tier": 4, "row": "back"}]
	var one := func(u: String) -> Array: return [{"unit": u, "level": 10, "tier": 3, "row": GameData.default_row_for(u)}]
	var r: Dictionary = _ability_battle(one.call("ogre"), foes)
	check(int(r["ev"].get(BattleSim.Ev.STUN, 0)) > 0 and r["stun"] > 0, "Ogre stuns")
	r = _ability_battle(one.call("ice_dragon"), foes)
	check(r["chill"] > 0, "Ice Dragon chills")
	r = _ability_battle(one.call("salamander_firebrand"), foes)
	check(r["burn"] > 0, "Salamander Firebrand burns")
	r = _ability_battle(one.call("frost_giant"), foes)
	check(r["curse"] > 0, "Frost Giant shatters armour")
	r = _ability_battle(one.call("sphinx"), foes)
	check(r["weaken"] > 0, "Sphinx withers")
	r = _ability_battle(one.call("storm_dragon"), foes)
	check(int(r["ev"].get(BattleSim.Ev.CHAIN, 0)) > 0, "Storm Dragon's lightning chains")
	r = _ability_battle(one.call("minotaur"), foes)
	check(int(r["ev"].get(BattleSim.Ev.CHARGE, 0)) > 1, "Minotaur charges each new target")
	r = _ability_battle(one.call("phoenix"), foes)
	var sim: BattleSim = r["sim"]
	check(int(r["ev"].get(BattleSim.Ev.REBIRTH, 0)) > 0, "Phoenix is reborn")
	check(range(sim.n).all(func(i): return sim.ab_id[i] != BattleSim.Ab.REBIRTH or sim.ab_used[i] <= 1), "...only once each")
	r = _ability_battle(one.call("lich"), [{"unit": "goblin", "level": 3, "tier": 6, "row": "front"}])
	sim = r["sim"]
	var raised: Array = range(sim.n).filter(func(i): return sim.raised[i] == 1)
	check(raised.size() > 0 and raised.all(func(i): return sim.team[i] == 0 and sim.unit_ids[sim.kind[i]] == "skeleton"), "the Lich raises its victims as skeletons on its side (%d)" % raised.size())
	var liches: Array = range(sim.n).filter(func(i): return sim.ab_id[i] == BattleSim.Ab.RAISE_DEAD)
	check(liches.all(func(i): return sim.ab_used[i] <= 8), "up to 8 per Lich")
	var again: Dictionary = _ability_battle(one.call("lich"), [{"unit": "goblin", "level": 3, "tier": 6, "row": "front"}])
	check((again["sim"] as BattleSim).checksum() == sim.checksum(), "battles with raised units stay deterministic")
	# Direct checks: double strike, unstoppable, devour.
	var s2 := BattleSim.new()
	s2.setup([{"unit": "ettin", "level": 5, "tier": 0, "row": "front"}], [{"unit": "goblin", "level": 1, "tier": 0, "row": "front"}], 1, "open_arena")
	var ettin := 0
	var gobs: Array = range(s2.n).filter(func(i): return s2.team[i] == 1).slice(0, 2)
	for k in gobs.size():
		s2.px[gobs[k]] = s2.px[ettin] + 12.0
		s2.py[gobs[k]] = s2.py[ettin] + (-6.0 if k == 0 else 6.0)
	s2._rebuild_grid()
	var before := [s2.hp[gobs[0]], s2.hp[gobs[1]]]
	s2.cd_t[ettin] = 0.0
	s2._approach_and_act(ettin, gobs[0], false)
	check(s2.hp[gobs[0]] < before[0] and s2.hp[gobs[1]] < before[1], "Ettin's double strike hits two enemies")
	var s3 := BattleSim.new()
	s3.setup([{"unit": "juggernaut", "level": 1, "tier": 0, "row": "front"}], [{"unit": "hill_giant", "level": 1, "tier": 0, "row": "front"}], 1, "open_arena")
	var jug := 0
	var giant: int = range(s3.n).filter(func(i): return s3.team[i] == 1)[0]
	var h0 := s3.hp[jug]
	s3.rng.seed = 9
	s3._damage_unit(jug, 100.0, 0, true)
	var melee_loss := h0 - s3.hp[jug]
	h0 = s3.hp[jug]
	s3.rng.seed = 9
	s3._damage_unit(jug, 100.0, 0, false)
	var ranged_loss := h0 - s3.hp[jug]
	check(absf(ranged_loss / melee_loss - 0.65) < 0.01, "Juggernaut takes 35% less from projectiles")
	s3.ab_id[giant] = BattleSim.Ab.STUN
	s3.ab_val[giant] = 2.0
	s3._on_hit(giant, 1, jug, 10.0, 10.0, 0)
	check(s3.stun_until[jug] == 0, "...and can't be stunned")
	check(is_equal_approx(float(Army.unit_stats("shadow_dragon", 1)["lifesteal"]), 0.75), "Shadow Dragon devours (75% lifesteal)")
	var mino := Army.ability_power(Army.unit_stats("minotaur", 5))
	check(mino.y > 1.1, "abilities count toward Strength (Minotaur's charge: x%.2f damage)" % mino.y)
	# Epic and legendary abilities.
	r = _ability_battle(one.call("hill_giant"), foes)
	check(int(r["ev"].get(BattleSim.Ev.QUAKE, 0)) > 0 and r["stun"] > 0, "Hill Giant's quake stuns")
	r = _ability_battle(one.call("golden_dragon"), foes)
	check(r["weaken"] > 0, "Golden Dragon's dread weakens enemies nearby")
	r = _ability_battle(one.call("seraph") + [{"unit": "orc_warrior", "level": 8, "tier": 6, "row": "front"}], foes)
	sim = r["sim"]
	var back: Array = range(sim.n).filter(func(i): return sim.raised[i] == 2)
	check(int(r["ev"].get(BattleSim.Ev.RESURRECT, 0)) > 0 and back.all(func(i): return sim.team[i] == 0), "Seraph resurrects fallen allies (%d)" % back.size())
	r = _ability_battle(one.call("hydra"), foes)
	sim = r["sim"]
	var hydras: Array = range(sim.n).filter(func(i): return sim.ab_id[i] == BattleSim.Ab.HEADS)
	check(hydras.any(func(i): return sim.ab_used[i] > 0 and sim.cooldown[i] < sim.ab_base[i]), "Hydra attacks faster as it loses heads")
	r = _ability_battle(one.call("titan"), foes)
	sim = r["sim"]
	check(range(sim.n).any(func(i): return sim.ab_id[i] == BattleSim.Ab.RISING_STORM and sim.ab_used[i] > 3), "Storm Titan's storm builds up")
	r = _ability_battle(one.call("bone_dragon"), foes)
	sim = r["sim"]
	check(range(sim.n).any(func(i): return sim.ab_id[i] == BattleSim.Ab.SOUL_HARVEST and sim.ab_used[i] > 0 and sim.ab_used[i] <= 5), "Bone Dragon harvests souls (up to 5 stacks)")
	r = _ability_battle(one.call("grand_avatar") + [{"unit": "orc_warrior", "level": 8, "tier": 6, "row": "front"}], foes)
	check(int(r["ev"].get(BattleSim.Ev.AURA, 0)) > 0, "Grand Avatar shields its allies")
	r = _ability_battle(one.call("fire_giant"), [{"unit": "goblin", "level": 30, "tier": 10, "row": "front"}])
	sim = r["sim"]
	check(range(sim.n).any(func(i): return sim.ab_id[i] == BattleSim.Ab.DEATH_BLAST and sim.alive[i] == 0), "Fire Giants fall (and erupt)")
	var s4 := BattleSim.new()
	s4.setup([{"unit": "griffon", "level": 1, "tier": 0, "row": "front"}], [{"unit": "elf_archer", "level": 1, "tier": 0, "row": "back"}, {"unit": "orc_warrior", "level": 1, "tier": 0, "row": "front"}], 1, "open_arena")
	var archer: int = range(s4.n).filter(func(i): return s4.team[i] == 1 and s4.role[i] == BattleSim.Role.RANGED)[0]
	var orc: int = range(s4.n).filter(func(i): return s4.team[i] == 1 and s4.role[i] == BattleSim.Role.MELEE)[0]
	var a0 := s4.hp[archer]
	s4.rng.seed = 3
	s4._damage_unit(archer, 5.0, 0, true, 0)
	var o0 := s4.hp[orc]
	s4.rng.seed = 3
	s4._damage_unit(orc, 5.0, 0, true, 0)
	var vs_ranged := (a0 - s4.hp[archer]) / float(s4._dmg_mult[0 * s4._armor_count + s4.armor[archer]])
	var vs_melee := (o0 - s4.hp[orc]) / float(s4._dmg_mult[0 * s4._armor_count + s4.armor[orc]])
	var pred := 1.0 + float(GameData.ability_of("griffon")["value"])
	check(absf(vs_ranged / vs_melee - pred) < 0.01, "Griffon's predator: x%.1f damage to ranged units (measured x%.2f)" % [pred, vs_ranged / vs_melee])
	var s5 := BattleSim.new()
	s5.setup([{"unit": "stone_giant", "level": 1, "tier": 0, "row": "back"}], [{"unit": "goblin", "level": 1, "tier": 0, "row": "front"}], 1, "open_arena")
	var gob: int = range(s5.n).filter(func(i): return s5.team[i] == 1)[0]
	var x0 := s5.px[gob]
	s5._on_hit(0, 0, gob, 10.0, 10.0, 0)
	check(s5.px[gob] > x0 + float(GameData.ability_of("stone_giant")["value"]) - 1.0 and s5.stun_until[gob] > s5.tick, "Stone Giant's boulders knock enemies back")
	# Slower squad growth.
	var pl := ProfileLogic.new()
	pl.data["units"]["golden_dragon"] = {"level": 1, "tier": 4, "shards": 0}
	pl.data["units"]["hill_giant"] = {"level": 1, "tier": 4, "shards": 0}
	pl.data["units"]["ogre"] = {"level": 1, "tier": 4, "shards": 0}
	check(int(pl.tier_up_cost("golden_dragon")["shards"]) == ceili(2 * 5 * 0.75 * 2.0) and int(pl.tier_up_cost("hill_giant")["shards"]) == ceili(3 * 5 * 0.75 * 1.75) and int(pl.tier_up_cost("ogre")["shards"]) == ceili(5 * 5 * 0.75), "epic and legendary squads need more shards to grow")
	UnitLocks.set_locked_list(UnitLocks.defaults())


func test_audio() -> void:
	print("sound and music (0.9.4)")
	var audio := root.get_node("Audio")
	var missing: Array = []
	for key in audio.SFX:
		for path in audio.SFX[key]:
			if not ResourceLoader.exists(path):
				missing.append(path)
	for key in audio.MUSIC:
		for path in audio.MUSIC[key]:
			if not ResourceLoader.exists(path):
				missing.append(path)
	check(missing.is_empty(), "every sound and music file exists %s" % [missing])
	check((audio.MUSIC["menu"] as Array).size() >= 4 and "menu" in audio.PLAYLISTS, "the lobby plays a playlist of %d tracks" % (audio.MUSIC["menu"] as Array).size())
	var repeats := 0
	var last := ""
	for i in 40:
		audio.set("_music_path", last)
		var next: String = audio.call("_pick_track", "menu")
		if next == last:
			repeats += 1
		last = next
	check(repeats == 0, "the playlist never plays the same track twice in a row")
	check(audio.SFX.has("battle_start") and audio.SFX.has("ab_zap") and audio.SFX.has("ab_ice"), "a new battle start and ability sounds")
	# Status abilities announce themselves, so the battle can play their sound.
	UnitLocks.set_locked_list([])
	var seen := {}
	for u in ["ice_dragon", "salamander_firebrand", "frost_giant", "sphinx", "stone_giant", "bone_dragon"]:
		var sim := BattleSim.new()
		sim.setup([{"unit": u, "level": 10, "tier": 3, "row": GameData.default_row_for(u)}], [{"unit": "orc_warrior", "level": 5, "tier": 6, "row": "front"}, {"unit": "elf_archer", "level": 5, "tier": 4, "row": "back"}], 3, "open_arena")
		while not sim.finished and sim.tick < 2500:
			sim.step()
			for e in sim.drain_events():
				if e[0] == BattleSim.Ev.ABILITY:
					seen[int(e[3])] = true
	var want := [BattleSim.Ab.CHILL, BattleSim.Ab.BURN, BattleSim.Ab.CURSE, BattleSim.Ab.WEAKEN, BattleSim.Ab.KNOCKBACK, BattleSim.Ab.SOUL_HARVEST]
	check(want.all(func(a): return seen.has(a)), "chill, burn, shatter, wither, knockback and soul harvest each play a sound (%d of %d seen)" % [want.filter(func(a): return seen.has(a)).size(), want.size()])
	UnitLocks.set_locked_list(UnitLocks.defaults())


func _status_battle(squads_a: Array, squads_b: Array, seed_v: int = 3) -> Dictionary:
	var sim := BattleSim.new()
	sim.setup(squads_a, squads_b, seed_v, "open_arena")
	var out := {"sim": sim, "n0": sim.n, "ev": {}, "ab": {}, "st": {}, "corrode": 0.0}
	var keys := ["poison", "root", "fear", "shell", "phase", "entomb", "haste", "inspire", "taunt", "chill", "stun"]
	for k in keys:
		out["st"][k] = 0
	while not sim.finished and sim.tick < 3000:
		sim.step()
		for e in sim.drain_events():
			out["ev"][e[0]] = int(out["ev"].get(e[0], 0)) + 1
			if e[0] == BattleSim.Ev.ABILITY:
				out["ab"][int(e[3])] = int(out["ab"].get(int(e[3]), 0)) + 1
		for i in sim.n:
			if sim.alive[i] == 0:
				continue
			for k in keys:
				if (sim.get(k + "_until") as PackedInt32Array)[i] > sim.tick:
					out["st"][k] += 1
			out["corrode"] = maxf(out["corrode"], sim.corrode[i])
	return out


func test_new_units() -> void:
	print("40 new units (patch 0.9.4)")
	UnitLocks.set_locked_list(UnitLocks.defaults())
	var fresh: Array = GameData.UNITS.keys().slice(60)
	check(fresh.size() == 40 and fresh.all(func(u): return not UnitLocks.is_locked(u)), "40 new units, open by default")
	check(fresh.all(func(u): return not GameData.ability_of(u).is_empty() and BattleSim.AB_IDS.has(GameData.ability_of(u)["id"]) and GameData.ability_text(u) != ""), "every new unit, commons included, has a battle ability")
	var commons: Array = fresh.filter(func(u): return GameData.UNITS[u]["rarity"] == "common")
	var common_ids: Array = commons.map(func(u): return str(GameData.ability_of(u)["id"]))
	check(common_ids.all(func(x): return common_ids.count(x) == 1), "no two new commons share an ability (%d commons)" % commons.size())
	var data_ok := true
	for u in GameData.UNITS:
		if load("res://assets/sprites/units/%s.png" % u) == null or not DraftData.ABILITIES.has(u) or GameData.regions_for_unit(u).is_empty():
			data_ok = false
			print("    missing data for ", u)
	check(data_ok, "all 100 units have a sprite, a draft ability and a region")
	var order: Array = GameData.region_ids_by_unlock()
	var sorted_ok := order.size() == GameData.REGIONS.size()
	for k in range(1, order.size()):
		if int(GameData.REGIONS[order[k]]["min_rating"]) < int(GameData.REGIONS[order[k - 1]]["min_rating"]):
			sorted_ok = false
	check(sorted_ok and order[0] == "badlands", "regions are listed in unlock order (%s first, %s last)" % [order[0], order[-1]])
	var sites: Array = Trinkets.site_ids_by_unlock()
	var sites_ok := true
	for k in range(1, sites.size()):
		if int(Trinkets.SITES[sites[k]]["min_rating"]) < int(Trinkets.SITES[sites[k - 1]]["min_rating"]):
			sites_ok = false
	check(sites_ok, "trinket sites too")
	for rid in ["fungal_hollows", "tidewater_grotto", "abyssal_rift", "frostfell_wastes"]:
		check(GameData.REGIONS.has(rid) and not UnitLocks.is_region_locked(rid) and load("res://assets/sprites/tiles/%s.png" % rid) != null, "%s is open and has its tile" % rid)
	# Each mechanic in a real battle.
	var foes := [{"unit": "orc_warrior", "level": 6, "tier": 6, "row": "front"}, {"unit": "elf_archer", "level": 6, "tier": 4, "row": "back"}, {"unit": "orc_sorcerer", "level": 5, "tier": 3, "row": "back"}]
	var one := func(u: String) -> Array: return [{"unit": u, "level": 8, "tier": 4, "row": GameData.default_row_for(u)}]
	var guard := [{"unit": "orc_warrior", "level": 6, "tier": 6, "row": "front"}]
	var r := _status_battle(one.call("cave_spider"), foes)
	check(r["st"]["poison"] > 0, "Cave Spider poisons")
	r = _status_battle(one.call("ooze"), foes)
	check(int(r["ab"].get(BattleSim.Ab.SPLIT, 0)) > 0 and (r["sim"] as BattleSim).n > int(r["n0"]), "Ooze splits when it dies (%d -> %d)" % [r["n0"], (r["sim"] as BattleSim).n])
	var again := _status_battle(one.call("ooze"), foes)
	check((again["sim"] as BattleSim).checksum() == (r["sim"] as BattleSim).checksum(), "split battles stay deterministic")
	r = _status_battle(one.call("giant_snail"), foes)
	check(r["st"]["shell"] > 0, "Giant Snail hides in its shell")
	r = _status_battle(one.call("trapdoor_spider"), foes)
	check(r["st"]["root"] > 0, "Trapdoor Spider roots")
	r = _status_battle(one.call("wolf_spider"), foes)
	check(int(r["ab"].get(BattleSim.Ab.POUNCE, 0)) > 0, "Wolf Spider pounces")
	r = _status_battle(one.call("deathcap"), foes)
	check(r["corrode"] > 0.0, "Deathcap corrodes armour")
	r = _status_battle(one.call("spider_matriarch"), foes)
	var sim: BattleSim = r["sim"]
	check(int(r["ab"].get(BattleSim.Ab.SUMMON, 0)) > 0 and range(sim.n).any(func(i): return sim.team[i] == 0 and sim.unit_ids[sim.kind[i]] == "cave_spider"), "Spider Matriarch summons cave spiders")
	r = _status_battle(one.call("snapping_turtle"), foes)
	check(int(r["ab"].get(BattleSim.Ab.BLOCK, 0)) > 0, "Snapping Turtle blocks")
	r = _status_battle(one.call("giant_newt"), foes)
	check(int(r["ab"].get(BattleSim.Ab.EVASION, 0)) > 0, "Giant Newt dodges")
	r = _status_battle(one.call("mermaid") + guard, foes)
	check(r["st"]["haste"] > 0, "Mermaid's song hastens allies")
	r = _status_battle(one.call("guardian_serpent") + [{"unit": "elf_archer", "level": 6, "tier": 4, "row": "back"}], foes)
	check(r["st"]["taunt"] > 0, "Guardian Serpent taunts")
	r = _status_battle(one.call("kraken"), foes)
	check(int(r["ab"].get(BattleSim.Ab.PULL, 0)) > 0, "Kraken pulls")
	r = _status_battle(one.call("merfolk_avatar"), foes)
	check(int(r["ev"].get(BattleSim.Ev.WAVE, 0)) > 0, "Merfolk Avatar's tidal wave")
	r = _status_battle(one.call("hellion"), foes)
	check(int(r["ev"].get(BattleSim.Ev.STRIKE, 0)) > 0, "Hellion calls down fire")
	r = _status_battle(one.call("pit_fiend"), foes)
	check(r["st"]["fear"] > 0, "Pit Fiend terrifies")
	r = _status_battle(one.call("warg") + guard, foes)
	check(r["st"]["inspire"] > 0, "Warg inspires")
	r = _status_battle(one.call("ice_fiend"), foes)
	check(r["st"]["entomb"] > 0, "Ice Fiend entombs")
	r = _status_battle(one.call("spectral_dragon"), foes)
	check(r["st"]["phase"] > 0, "Spectral Dragon phases out")
	r = _status_battle(one.call("rakshasa"), foes)
	check(int(r["ab"].get(BattleSim.Ab.REFLECT, 0)) > 0, "Rakshasa reflects projectiles")
	# Passive effects, checked directly.
	check(is_equal_approx(float(Army.unit_stats("acid_blob", 1)["thorns"]), 0.4), "Acid Blob's spikes hurt attackers (40% thorns)")
	var s := BattleSim.new()
	s.setup([{"unit": "sporeling", "level": 1, "tier": 0, "row": "back"}, {"unit": "goblin", "level": 1, "tier": 0, "row": "front"}], [{"unit": "goblin", "level": 1, "tier": 0, "row": "front"}], 1, "open_arena")
	var spore: int = range(s.n).filter(func(i): return s.ab_id[i] == BattleSim.Ab.PURIFY)[0]
	var ally: int = range(s.n).filter(func(i): return s.team[i] == 0 and i != spore)[0]
	s.px[spore] = s.px[ally] + 10.0
	s.py[spore] = s.py[ally]
	s._rebuild_grid()
	s.hp[ally] = s.max_hp[ally] * 0.5
	s.burn_until[ally] = s.tick + 200
	s.poison_until[ally] = s.tick + 200
	s.cd_t[spore] = 0.0
	s._approach_and_act(spore, ally, true)
	check(s.burn_until[ally] == 0 and s.poison_until[ally] == 0, "Sporeling's healing purifies burns and poison")
	var e := BattleSim.new()
	e.setup([{"unit": "executioner", "level": 1, "tier": 0, "row": "front"}], [{"unit": "troll", "level": 1, "tier": 0, "row": "front"}], 1, "open_arena")
	var ex: int = range(e.n).filter(func(i): return e.team[i] == 0)[0]
	var tr: int = range(e.n).filter(func(i): return e.team[i] == 1)[0]
	e.rng.seed = 4
	var h0 := e.hp[tr]
	e._damage_unit(tr, 10.0, 0, true, ex)
	var full := h0 - e.hp[tr]
	e.hp[tr] = e.max_hp[tr] * 0.2
	h0 = e.hp[tr]
	e.rng.seed = 4
	e._damage_unit(tr, 10.0, 0, true, ex)
	var low := h0 - e.hp[tr]
	check(absf(low / full - 2.5) < 0.05, "Executioner hits much harder below 30%% health (%.0f vs %.0f)" % [low, full])
	var proto: String = root.get_node("Party").GAME_VERSION
	check(proto.trim_prefix("legion-draft-").to_int() >= 18, "protocol bumped for the new units (%s)" % proto)
	UnitLocks.set_locked_list(UnitLocks.defaults())


func test_rank_scaling() -> void:
	print("rating start, training bands by rank, AI rating (patch 0.9.5)")
	check(int(ProfileLogic.default_profile()["rating"]) == 0, "new commanders start at 0 rating")
	check(int(GameData.REGIONS["badlands"]["min_rating"]) == 0 and not UnitLocks.is_region_locked("badlands") and int(GameData.REGIONS["warrens"]["min_rating"]) == 250 and int(GameData.REGIONS["crypt"]["min_rating"]) == 500, "Badlands Camp is open from the start, then Goblin Warrens at 250 and Haunted Crypt at 500")
	var fresh := ProfileLogic.new()
	fresh.data["maps"] = 5
	check(fresh.can_explore("badlands") and not fresh.can_explore("warrens"), "a brand-new commander can explore Badlands Camp")
	fresh.data["rating"] = 5
	var lost := fresh.apply_battle_result("ranked", 0.0, 40, 0, true)
	check(fresh.rating() == 0 and int(lost["rating"]) == -5, "rating never goes below 0 (and the result shows the real change)")
	check(int(GameData.REGIONS["fungal_hollows"]["min_rating"]) == 800 and GameData.region_ids_by_unlock()[3] == "fungal_hollows", "Fungal Hollows at 800 is the first step up")
	check((root.get_node("Audio").MUSIC["menu"] as Array).size() == 8, "eight lobby tracks")
	var starter: Array = []
	for id in GameData.STARTER_UNITS:
		starter.append({"unit": id, "level": 1, "tier": 0, "row": GameData.default_row_for(id)})
	var sp := Army.army_power(starter)
	check(absf(Army.rank_power(0) / sp - 1.0) < 0.15, "training bands at 0 are built around a starting army (%.0f vs %.0f)" % [Army.rank_power(0), sp])
	var rising := true
	for r in range(0, 5000, 50):
		if Army.rank_power(r + 50) <= Army.rank_power(r):
			rising = false
	check(rising, "the expected power rises with every step of rating")
	# The same rating gives the same strength of opponents, whatever your army.
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var offers: Array = []
	Army.fill_ghosts(offers, 2000, rng)
	var dupes := false
	for seed_i in 200:
		rng.seed = seed_i
		var o3: Array = []
		Army.fill_ghosts(o3, 1500, rng)
		var names: Array = o3.map(func(o): return o["name"])
		if names.any(func(n): return names.count(n) > 1):
			dupes = true
	check(not dupes, "the three training bands in a search always have different names")
	rng.seed = 7
	var p_easy := Army.army_power(offers[0]["squads"]) / Army.rank_power(2000)
	check(p_easy > 0.8 and p_easy < 1.05, "Easy at 2000 is about 0.9x of %.0f (%.2fx)" % [Army.rank_power(2000) / 10.0, p_easy])
	# AI battles count in full below 1000, then move rating less.
	check(Army.ranked_delta(600, 660, 1.0, true) == Army.elo_delta(600, 660, 1.0) and Army.ranked_delta(999, 960, 0.0, true) == Army.elo_delta(999, 960, 0.0), "below 1000, training bands count in full")
	var full := Army.elo_delta(1000, 1060, 1.0)
	var ai := Army.ranked_delta(1000, 1060, 1.0, true)
	check(ai == roundi(float(full) / 4.0) or absi(ai * 4 - full) <= 2, "beating a training band below 2500 gives a quarter of the rating (%d vs %d)" % [ai, full])
	var full_hi := Army.elo_delta(2600, 2660, 1.0)
	var ai_hi := Army.ranked_delta(2600, 2660, 1.0, true)
	check(ai_hi >= 1 and ai_hi <= maxi(1, roundi(float(full_hi) / 10.0) + 1), "from 2500 a tenth (%d vs %d), but at least 1" % [ai_hi, full_hi])
	check(Army.ranked_delta(1000, 960, 0.0, true) < 0 and Army.ranked_delta(1000, 960, 0.0, true) > Army.elo_delta(1000, 960, 0.0), "losses shrink the same way")
	check(Army.ranked_delta(1000, 1060, 1.0, false) == full, "saved player armies and live duels count in full")
	var pl := ProfileLogic.new()
	pl.data["rating"] = 1000
	var s_ai := pl.apply_battle_result("ranked", 1.0, 1060, 0, true)
	pl.data["rating"] = 1000
	var s_real := pl.apply_battle_result("ranked", 1.0, 1060, 0, false)
	pl.data["rating"] = 1000
	var s_live := pl.apply_battle_result("live", 1.0, 1060, 0, true)
	check(int(s_ai["rating"]) == ai and int(s_real["rating"]) == full and int(s_live["rating"]) == full, "battle results use it (AI %+d, player army %+d, live duel %+d)" % [int(s_ai["rating"]), int(s_real["rating"]), int(s_live["rating"])])


func test_player_command() -> void:
	print("server 'player' command (patch 0.9.5)")
	var party := root.get_node("Party")
	var saved_accounts = party.accounts
	var store := AccountStore.new("user://test_player_cmd_%d" % Time.get_ticks_usec())
	store.create("Bob", Passwords.make_record("whatever1", 1000))
	party.accounts = store
	check(party.run_command("player nobody").begins_with("No account"), "unknown players are reported")
	check(party.run_command("player bob").contains("rating 0"), "shows a player's stats")
	party.run_command("player bob set rating 1500")
	party.run_command("player bob add gold 250")
	party.run_command("player Bob add gold -100")
	party.run_command("player bob set maps 9")
	var pl: ProfileLogic = store.logic("bob")
	check(pl.rating() == 1500 and pl.gold() == 600 + 150 and pl.maps() == 9, "set and add change stats (rating %d, gold %d, maps %d)" % [pl.rating(), pl.gold(), pl.maps()])
	party.run_command("player bob add rating -99999")
	check(pl.rating() == 0, "rating can't go below 0")
	party.run_command("player bob name Lord Bob")
	check(str(pl.data["name"]) == "Lord Bob", "renames the commander")
	party.run_command("player bob unit Orc Warrior level 12 tier 2 shards 30")
	var u: Dictionary = pl.data["units"].get("orc_warrior", {})
	check(int(u.get("level", 0)) == 12 and int(u.get("tier", 0)) == 2 and int(u.get("shards", 0)) == 30, "gives a unit by name with level, tier and shards")
	party.run_command("player bob unit orc_warrior level 999")
	check(int(pl.data["units"]["orc_warrior"]["level"]) == Army.max_level("orc_warrior", 2), "levels are capped by the tier")
	party.run_command("player bob unit storm_dragon level 999 tier 10")
	check(int(pl.data["units"]["storm_dragon"]["level"]) == 10, "a legendary tops out at level 10")
	party.run_command("player bob unit goblin remove")
	check(not pl.data["units"].has("goblin") and pl.data["army"].all(func(sq): return sq["unit"] != "goblin"), "takes a unit away, out of the army too")
	party.run_command("player bob units all level 5")
	check(UnitLocks.unlocked_ids().all(func(id): return pl.data["units"].has(id)), "'units all' gives every open unit (%d)" % UnitLocks.unlocked_ids().size())
	party.run_command("player bob trinket Copper Band")
	check(pl.data["trinkets"].has("copper_band"), "gives a trinket by name")
	party.run_command("player bob trinket copper_band remove")
	check(not pl.data["trinkets"].has("copper_band"), "...and takes it back")
	party.run_command("player bob trinkets all")
	check(pl.data["trinkets"].size() == Trinkets.ALL.size(), "'trinkets all'")
	party.run_command("player bob challenge all")
	party.run_command("player bob challenge rat_problem remove")
	check(pl.data["challenges"].size() == Challenges.LIST.size() - 1 and not pl.data["challenges"].has("rat_problem"), "clears and un-clears challenges")
	var reloaded := AccountStore.new(store.dir)
	check(reloaded.logic("bob").rating() == 0 and reloaded.logic("bob").data["trinkets"].size() == Trinkets.ALL.size(), "changes are saved to the account file")
	check(party.run_command("player bob reset").contains("reset confirm"), "reset asks for confirmation")
	party.run_command("player bob reset confirm")
	check(pl.data["units"].size() == GameData.STARTER_UNITS.size() and pl.rating() == 0 and str(pl.data["name"]) == "Lord Bob", "reset starts the profile over (name kept)")
	party.accounts = saved_accounts


func test_caster_nerf() -> void:
	print("caster nerf (patch 0.9.6)")
	var nerfed: Array = GameData.UNITS.keys().filter(func(u): return Army.caster_nerfed(u))
	check(nerfed.size() == 10 and nerfed.all(func(u): return GameData.UNITS[u]["role"] == "caster" and not GameData.UNITS[u]["rarity"] in ["epic", "legendary"]), "10 casters below epic are nerfed")
	check(not Army.caster_nerfed("lich") and not Army.caster_nerfed("storm_dragon") and not Army.caster_nerfed("elf_archer"), "epic and legendary casters and other roles aren't")
	var s := Army.unit_stats("orc_sorcerer", 5)
	var raw := float(GameData.UNITS["orc_sorcerer"]["dmg"]) * Army.level_mult(5)
	check(is_equal_approx(float(Army.unit_stats("elf_mage", 5)["dmg"]), float(GameData.UNITS["elf_mage"]["dmg"]) * Army.level_mult(5) * 0.85), "their damage is 85%")
	check(is_equal_approx(float(s["dmg"]), raw * 0.85 * 0.77), "the Orc Sorcerer's standalone nerf stacks on top (%.1f of %.1f, x0.65)" % [float(s["dmg"]), raw])
	var over: Array = Army.UNIT_DMG_MULT.keys()
	check(over.size() == 8 and over.all(func(u): return GameData.UNITS[u]["role"] == "caster" and float(Army.UNIT_DMG_MULT[u]) < 1.0), "8 casters over 53% get a standalone damage nerf, epics and legendaries included")
	check(is_equal_approx(Army.dmg_nerf("sphinx"), 0.92) and is_equal_approx(Army.dmg_nerf("lich"), 1.0), "Sphinx (epic) deals 92%; the Lich is untouched")
	var sim := BattleSim.new()
	sim.setup([{"unit": "orc_sorcerer", "level": 5, "tier": 0, "row": "back"}], [{"unit": "goblin", "level": 1, "tier": 0, "row": "front"}], 1, "open_arena")
	check(is_equal_approx(sim.dmg[0], float(Army.unit_stats("orc_sorcerer", Army.stat_level("orc_sorcerer", 5))["dmg"])) and is_equal_approx(float(Army.unit_stats("orc_sorcerer", 9)["dmg"]), float(GameData.UNITS["orc_sorcerer"]["dmg"]) * Army.level_mult(9) * 0.85 * 0.77), "...in battle too")
	# Strength stays what it was before the nerf.
	var s_full := s.duplicate()
	s_full["dmg"] = raw
	var cd: float = s_full["cooldown"]
	var splash := minf(float(s_full["aoe"]), 60.0) / 40.0 * BattleSim.RANGED_SPLASH_MULT / Army.SPLASH_POWER_REF
	var dps := raw * (1.0 + splash) / cd + float(s_full["regen"])
	var ab := Army.ability_power(s_full)
	var s_sph := Army.unit_stats("sphinx", 5)
	check(is_equal_approx(float(s_sph["dmg"]), float(GameData.UNITS["sphinx"]["dmg"]) * Army.level_mult(5) * 0.92), "the Sphinx hits 8% softer")
	var before := sqrt(float(s_full["hp"]) * ab.x * dps * ab.y * (1.0 + minf(float(s_full["range"]), 260.0) / 520.0)) * float(GameData.RARITIES["rare"]["power_mult"])
	check(absf(Army.unit_power("orc_sorcerer", 5) / before - 1.0) < 0.001, "each one's Strength is unchanged by the damage cut")
	check(Army.squad_size("orc_sorcerer", 0) == 4 and Army.squad_size("orc_sorcerer", 10) == 25 and Army.squad_size("ogre", 10) == 36, "their squads are 70%% the size (Orc Sorcerer %d at tier 10, Ogre Brute 36)" % Army.squad_size("orc_sorcerer", 10))
	check(Army.squad_size("elf_mage", 0) == 11 and Army.squad_size("lich", 0) == 2, "uncommons too; epics keep theirs")
	check(DraftData.entry_count({"unit": "orc_sorcerer", "xp": 1}) < DraftData.entry_count({"unit": "ogre", "xp": 1}) and DraftData.entry_count({"unit": "elf_mage", "xp": 1}) == roundi(float(DraftData.BASE_COUNT["uncommon"]) * 0.7), "Legion Draft squads shrink the same way")
	var deployed: Array = Army.deploy_counts([{"unit": "orc_sorcerer", "level": 1, "tier": 10, "row": "back"}])
	check(int(deployed[0]) == 25, "and so do the squads that deploy in battle")


func test_rarity_levels() -> void:
	print("levels by rarity (patch 0.9.7)")
	var caps := ["goblin", "orc_warrior", "ogre", "lich", "golden_dragon"].map(func(u): return Army.max_level(u, GameData.MAX_TIER))
	check(caps == [50, 40, 30, 20, 10], "fully upgraded caps: common 50, uncommon 40, rare 30, epic 20, legendary 10 (%s)" % [caps])
	var caps0 := ["goblin", "orc_warrior", "ogre", "lich", "golden_dragon"].map(func(u): return Army.max_level(u, 0))
	check(caps0 == [10, 8, 6, 4, 2], "at tier 0 a fifth of that (%s)" % [caps0])
	check(Army.stat_level("goblin", 1) == 1 and Army.stat_level("orc_warrior", 1) == 11 and Army.stat_level("ogre", 1) == 21 and Army.stat_level("lich", 1) == 31 and Army.stat_level("golden_dragon", 1) == 41, "level 1 of each rarity is as strong as a common at 1, 11, 21, 31 and 41")
	var same_top := true
	for u in GameData.UNITS:
		if Army.stat_level(u, Army.max_level(u, GameData.MAX_TIER)) != Army.STAT_MAX_LEVEL:
			same_top = false
	check(same_top, "every unit's top level has exactly the stats it had at level 50 before")
	var lich1 := float(Army.unit_stats("lich", Army.stat_level("lich", 1))["hp"])
	check(is_equal_approx(lich1, float(GameData.UNITS["lich"]["hp"]) * Army.level_mult(31)), "a level 1 Lich has %.0f HP (x%.1f its base)" % [lich1, Army.level_mult(31)])
	var a := Army.army_power([{"unit": "ogre", "level": 1, "tier": 0, "row": "front"}])
	var b := Army.army_power([{"unit": "ogre", "level": 21, "tier": 0, "row": "front", "count": Army.squad_size("ogre", 0)}])
	check(absf(a / b - 1.0) < 0.001, "Strength follows the stat level")
	# Old saves and codes.
	var old := ProfileLogic.new({"rating": 900, "units": {"goblin": {"level": 17, "tier": 3, "shards": 0}, "ogre": {"level": 26, "tier": 5, "shards": 2},
		"golden_dragon": {"level": 12, "tier": 2, "shards": 0}}, "army": [{"unit": "ogre", "row": "front"}]})
	var lv: Array = ["goblin", "ogre", "golden_dragon"].map(func(u): return int(old.data["units"][u]["level"]))
	check(lv == [17, 6, 1] and int(old.data["levels_version"]) == 2, "old saves move to the new levels without losing strength (%s)" % [lv])
	var again := ProfileLogic.new(old.data.duplicate(true))
	check(int(again.data["units"]["ogre"]["level"]) == 6, "...only once")
	var fresh := ProfileLogic.new()
	fresh.data["gold"] = 1000000
	fresh.data["units"]["ogre"] = {"level": 1, "tier": 0, "shards": 0}
	check(fresh.level_up_cost("ogre") == roundi(40.0 * pow(21.0, 1.6) * 2.5), "a rare's first level costs what a common's 21st did (x the rare price)")
	var old_code := "AB1:" + Marshalls.utf8_to_base64(JSON.stringify({"n": "Old", "r": 1500, "s": [["ogre", 26, 5, 0], ["goblin", 17, 3, 0]]}))
	var dec := Army.decode(old_code)
	check(not dec.is_empty() and int(dec["squads"][0]["level"]) == 6 and int(dec["squads"][1]["level"]) == 17, "army codes from before 0.9.7 still work, converted")
	check(Army.encode("X", 1, [{"unit": "goblin", "level": 3, "tier": 0, "row": "front"}]).begins_with("AB2:"), "new codes are AB2")
	var proto: String = root.get_node("Party").GAME_VERSION
	check(proto == "legion-draft-20", "protocol bumped (%s)" % proto)
	# Legion Draft and challenges keep the stat scale.
	var d_sq: Dictionary = DraftData.board_to_squads([DraftData.new_entry("golden_dragon")])[0]
	check(Army.squad_stat_level(d_sq) == int(d_sq["level"]), "Legion Draft squads aren't shifted")
	check(Challenges.enemy_squads("golden_wyrm").all(func(sq): return Army.squad_stat_level(sq) == int(sq["level"])), "nor challenge enemies")
