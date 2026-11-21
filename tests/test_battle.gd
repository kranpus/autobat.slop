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
