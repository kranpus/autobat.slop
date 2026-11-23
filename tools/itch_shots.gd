extends SceneTree
## Screenshots for the itch.io page (itch/screenshots/). Needs a display:
##   xvfb-run -a -s "-screen 0 1920x1080x24" godot --rendering-driver opengl3 \
##     --resolution 1920x1080 --path . -s res://tools/itch_shots.gd -- --out=itch/screenshots
## Plays offline with a well-stocked profile; the real profile is restored
## afterwards.

const ARMY_A := [
	{"unit": "orc_warrior", "level": 22, "tier": 10, "row": "front"}, {"unit": "snapping_turtle", "level": 20, "tier": 10, "row": "front"},
	{"unit": "hell_hound", "level": 20, "tier": 10, "row": "middle"}, {"unit": "elf_archer", "level": 22, "tier": 10, "row": "back"},
	{"unit": "merfolk_javelineer", "level": 20, "tier": 10, "row": "back"}, {"unit": "ogre", "level": 22, "tier": 8, "row": "middle"},
	{"unit": "golden_dragon", "level": 20, "tier": 4, "row": "back"}, {"unit": "pit_fiend", "level": 20, "tier": 4, "row": "middle"},
]
const ARMY_B := [
	{"unit": "skeleton", "level": 22, "tier": 10, "row": "front"}, {"unit": "ooze", "level": 20, "tier": 10, "row": "front"},
	{"unit": "rat_swarm", "level": 22, "tier": 10, "row": "front"}, {"unit": "cave_spider", "level": 20, "tier": 10, "row": "middle"},
	{"unit": "kobold_slinger", "level": 22, "tier": 10, "row": "back"}, {"unit": "lich", "level": 20, "tier": 5, "row": "back"},
	{"unit": "hellion", "level": 20, "tier": 8, "row": "back"}, {"unit": "rime_lindwurm", "level": 20, "tier": 4, "row": "front"},
]
const OWNED := ["goblin", "kobold_slinger", "rat_swarm", "skeleton", "orc_warrior", "elf_archer", "gnoll_shaman", "dwarf_berserker",
	"dire_wolf", "ogre", "centaur", "orc_sorcerer", "treant", "lich", "griffon", "golden_dragon", "cave_spider", "ooze",
	"snapping_turtle", "mermaid", "hell_hound", "imp", "yak", "warg", "pit_fiend", "merfolk_avatar", "hellion", "jackal",
	"hobgoblin", "war_hound", "orc_knight", "cyclops", "spectral_dragon", "kraken", "balrug"]

var out_dir := "user://itch_shots"
var main: Node
var profile: Node
var backup_data: Dictionary
var backup_settings: Dictionary


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.get_slice("=", 1)
	DirAccess.make_dir_recursive_absolute(out_dir)
	profile = root.get_node("Profile")
	backup_data = profile.data.duplicate(true)
	backup_settings = profile.settings.duplicate(true)
	profile.settings["start_offline"] = true
	profile.settings.erase("account")
	profile.settings["server_address"] = "127.0.0.1:1"   # offline: training bands
	profile.settings["tutorial"] = {"done": ["first_battle", "level_up", "recruit", "army", "ranked", "challenges", "finale"], "seen": ["trinkets", "draft", "leaderboard"]}
	profile.settings["ai_rating_notice"] = true
	profile.reset()
	var d: Dictionary = profile.data
	d["name"] = "Commander Vale"
	d["gold"] = 48250
	d["maps"] = 10
	d["rating"] = 1840
	d["wins"] = 61
	d["losses"] = 27
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for id in OWNED:
		var tier := rng.randi_range(3, 9)
		var cap := Army.max_level(id, tier)
		d["units"][id] = {"level": rng.randi_range(maxi(1, cap / 2), cap), "tier": tier, "shards": rng.randi_range(0, 40), "trinkets": []}
	d["army"] = []
	for id in ["orc_warrior", "snapping_turtle", "ogre", "hell_hound", "elf_archer", "mermaid", "golden_dragon", "pit_fiend"]:
		d["army"].append({"unit": id, "row": GameData.default_row_for(id)})
	for c in Challenges.LIST.slice(0, 6):
		d["challenges"][c["id"]] = true
	for t in Trinkets.ALL.keys().slice(0, 30):
		d["trinkets"][t] = true
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _shot(name: String) -> void:
	await process_frame
	root.get_texture().get_image().save_png("%s/%s.png" % [out_dir, name])
	print("saved ", name)


func _wait(sec: float) -> void:
	await create_timer(sec).timeout


func _run() -> void:
	await _wait(1.0)
	for c in main.login_layer.get_children():
		c.queue_free()
	await _wait(0.5)
	# Battle in full swing.
	# Close up on the clash...
	main.start_battle({"mode": "practice", "seed": 11, "squads_a": ARMY_A, "squads_b": ARMY_B, "name_a": "Commander Vale", "name_b": "Warlord Grak", "local_team": 0, "map": "whispering_forest"})
	await _wait(1.0)
	main._battle._begin()
	await _wait(6.5)
	var cam: Camera2D = main._battle.view._camera
	cam.zoom *= 1.7
	await _wait(1.0)
	await _shot("01_battle")
	main._battle.closed.emit()
	await _wait(0.5)
	# ...and the whole field.
	main.start_battle({"mode": "practice", "seed": 4, "squads_a": ARMY_A, "squads_b": ARMY_B, "name_a": "Commander Vale", "name_b": "Warlord Grak", "local_team": 0, "map": "twin_fords"})
	await _wait(1.0)
	main._battle._begin()
	await _wait(8.0)
	await _shot("02_battle_field")
	main._battle.closed.emit()
	await _wait(0.5)
	# Ranked: the Call to Arms scroll.
	main.tabs.current_tab = 3
	await _wait(0.3)
	var pvp = main.tabs.get_child(3)
	pvp._searching = true
	pvp._on_ranked_opponents([])   # offline: three training bands
	await _wait(2.0)
	await _shot("03_call_to_arms")
	# Collection with a legendary picked.
	main.tabs.current_tab = 0
	main.collection_tab._selected = "golden_dragon"
	main.collection_tab.refresh()
	await _wait(0.6)
	await _shot("04_collection")
	# Expedition: the Scout's Report.
	main.tabs.current_tab = 2
	await _wait(0.3)
	main.expedition_tab._explore("tidewater_grotto")
	await _wait(3.0)
	await _shot("05_scouts_report")
	for p in root.find_children("*", "Popup", true, false):
		p.hide()
	for p in main.find_children("*", "Popup", true, false):
		p.hide()
	profile.data["pending_choice"] = {}
	main.expedition_tab.refresh()
	# Army.
	main.tabs.current_tab = 1
	await _wait(0.6)
	await _shot("06_army")
	# Challenges.
	main.tabs.current_tab = 4
	await _wait(1.0)
	await _shot("07_challenges")
	# Legion Draft: a board mid-game.
	var party := root.get_node("Party")
	party.host_lan("Tavern Brawl", {"wins": 5, "lives": 3, "max_players": 4, "turn_time": 120, "slots": 8,
		"use_lives": true, "use_wins": true, "use_timer": false, "max_rounds": 0})
	for i in 3:
		party.add_bot()
	main.tabs.current_tab = 7
	await _wait(0.5)
	party.start_match()
	await _wait(1.0)
	var run = party.run
	var picks := ["orc_warrior", "ogre", "dire_wolf", "elf_archer", "gnoll_shaman", "mermaid"]
	for i in picks.size():
		var e := DraftData.new_entry(picks[i])
		e["xp"] = [1, 3, 1, 6, 3, 1][i]
		run.board[i] = e
	run.gold = 7
	main.draft_screen.refresh()
	await _wait(1.0)
	await _shot("08_legion_draft")
	party.disconnect_all()
	await _wait(0.3)
	profile.data = backup_data
	profile.settings = backup_settings
	profile.save()
	profile.save_settings()
	quit(0)
