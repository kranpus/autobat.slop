extends SceneTree
## Renders screenshots of the main screens (needs a display or xvfb-run):
##   xvfb-run -s "-screen 0 1280x720x24" godot --rendering-driver opengl3 --resolution 1280x720 -s res://tests/screenshots.gd -- --out=/tmp/shots

var out_dir := "user://shots"
var main: Node
var step := 0
var wait := 0
const ARMY_A := [{"unit": "goblin", "level": 10, "tier": 10, "row": "front"}, {"unit": "orc_warrior", "level": 10, "tier": 10, "row": "front"},
	{"unit": "elf_archer", "level": 10, "tier": 10, "row": "back"}, {"unit": "ogre", "level": 10, "tier": 10, "row": "middle"},
	{"unit": "golden_dragon", "level": 10, "tier": 10, "row": "back"}, {"unit": "griffon", "level": 10, "tier": 6, "row": "middle"}]
const ARMY_B := [{"unit": "skeleton", "level": 10, "tier": 10, "row": "front"}, {"unit": "rat_swarm", "level": 10, "tier": 10, "row": "front"},
	{"unit": "kobold_slinger", "level": 10, "tier": 10, "row": "back"}, {"unit": "lich", "level": 10, "tier": 10, "row": "back"},
	{"unit": "dwarf_berserker", "level": 10, "tier": 10, "row": "middle"}, {"unit": "treant", "level": 10, "tier": 6, "row": "front"}]


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.get_slice("=", 1)
	DirAccess.make_dir_recursive_absolute(out_dir)
	var p = root.get_node("Profile")
	p.reset()
	p.data["gold"] = 5000
	for id in ["goblin", "kobold_slinger", "rat_swarm", "skeleton", "orc_warrior", "elf_archer", "ogre", "lich", "golden_dragon"]:
		p.data["units"][id] = {"level": 8, "tier": 6, "shards": 12}
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)


func _shot(shot_name: String) -> void:
	root.get_texture().get_image().save_png("%s/%s.png" % [out_dir, shot_name])
	print("saved ", shot_name)


func _battle(map: String) -> void:
	main.start_battle({"mode": "practice", "seed": 7, "squads_a": ARMY_A, "squads_b": ARMY_B, "name_a": "Blue", "name_b": "Red", "local_team": 0, "map": map})


func _process(_delta: float) -> bool:
	wait += 1
	if wait < 20:
		return false
	wait = 0
	step += 1
	match step:
		1:
			main.collection_tab.refresh()
			_shot("01_collection")
			main.tabs.current_tab = 1
		2:
			_shot("02_army")
			main.tabs.current_tab = 2
		3:
			_shot("03_expeditions")
			main.tabs.current_tab = 3
		4:
			_shot("04_battle_tab")
			main.tabs.current_tab = 4
		5:
			_shot("05_legion_draft_tab")
			_battle("twin_fords")
		6:
			_shot("06_battle_deploy")
			main._battle._begin()
		14:
			_shot("07_battle_fight_twin_fords")
			main._battle.view.skip_to_end()
		15:
			_shot("08_battle_result")
			main._battle.closed.emit()
		16:
			_battle("whispering_forest")
			main._battle._begin()
		24:
			_shot("09_battle_fight_forest")
			main._battle.closed.emit()
			var party = root.get_node("Party")
			party.host_lan("Screenshot", {"wins": 5, "lives": 3, "max_players": 4, "turn_time": 120})
			for i in 3:
				party.add_bot()
		25:
			main.tabs.current_tab = 4
		26:
			_shot("10_draft_lobby")
			root.get_node("Party").start_match()
		27:
			var party = root.get_node("Party")
			party.run.gold = 30
			for i in 4:
				var slot: int = party.run.slot_of_unit(party.run.shop_units[0]["unit"]) if not party.run.shop_units.is_empty() else -1
				if slot == -1:
					slot = party.run.first_empty_slot()
				party.do_action(["buy_unit", 0, slot])
			party.do_action(["buy_trinket", 0, 0])
			main.draft_screen._select("board", 0)
		28:
			_shot("11_draft_shop")
			quit(0)
	return false
