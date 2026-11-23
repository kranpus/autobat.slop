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
	p.settings.erase("account")         # show the sign-in screen first
	p.settings.erase("start_offline")
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


var check_log: Array = []
var _login_shot := false
var _drag_events: Array = []


## Queue a real mouse drag (press, several moves, release) between two controls.
func _queue_drag(from: Control, to: Control) -> void:
	# Convert UI coordinates to window pixels (they differ when the UI is scaled).
	var to_window := root.get_final_transform()
	var a := to_window * from.get_global_rect().get_center()
	var b := to_window * to.get_global_rect().get_center()
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = a
	press.global_position = a
	_drag_events.append(press)
	for k in range(1, 9):
		var m := InputEventMouseMotion.new()
		var p := a.lerp(b, float(k) / 8.0)
		m.position = p
		m.global_position = p
		m.relative = (b - a) / 8.0
		m.button_mask = MOUSE_BUTTON_MASK_LEFT
		_drag_events.append(m)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = b
	release.global_position = b
	_drag_events.append(release)


func _rows() -> Array:
	var out: Array = []
	for sq in root.get_node("Profile").data["army"]:
		out.append("%s:%s" % [sq["unit"], sq["row"]])
	return out


func _process(_delta: float) -> bool:
	if not _drag_events.is_empty():
		Input.parse_input_event(_drag_events.pop_front())
		return false
	wait += 1
	if wait < 20:
		return false
	wait = 0
	step += 1
	if not _login_shot:
		_login_shot = true
		_shot("00_login")
		for c in main.login_layer.get_children():
			c.queue_free()
		step -= 1
		return false
	match step:
		1:
			main.collection_tab.refresh()
			_shot("01_collection")
			main.tabs.current_tab = 1
		2:
			_shot("02_army")
			main.tabs.current_tab = 3
		3:
			_shot("03_expeditions")
			main.tabs.current_tab = 4
		4:
			_shot("04_battle_tab")
			main.tabs.current_tab = 8
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
			main.tabs.current_tab = 3
		25:
			_shot("10_expeditions_pity")
			var party = root.get_node("Party")
			party.host_lan("Screenshot", {"wins": 5, "lives": 3, "max_players": 4, "turn_time": 120, "slots": 8,
				"use_lives": false, "use_wins": false, "use_timer": false, "max_rounds": 10})
			for i in 3:
				party.add_bot()
			main.tabs.current_tab = 8
		26:
			_shot("11_draft_lobby")
			root.get_node("Party").start_match()
		27:
			# Real mouse drag: first shop unit -> front slot 1.
			var run = root.get_node("Party").run
			run.gold = 30
			main.draft_screen.refresh()
		28:
			# Positions are measured a step after the rebuild, once layout has run.
			_queue_drag(main.draft_screen._shop_row.get_child(0), main.draft_screen._slot_buttons[0])
		29:
			var run = root.get_node("Party").run
			check_log.append("after drag 1: slot 1 = %s" % [run.board[0].get("unit", "empty")])
			# Trinket (after the unit cards and the separator) -> the unit in slot 1.
			var row: HBoxContainer = main.draft_screen._shop_row
			_queue_drag(row.get_child(row.get_child_count() - 1), main.draft_screen._slot_buttons[0])
		31:
			var run = root.get_node("Party").run
			check_log.append("after drag 2: slot 1 trinket = %s" % [run.board[0].get("trinket", "")])
			# Board unit slot 1 -> slot 6 (move).
			_queue_drag(main.draft_screen._slot_buttons[0], main.draft_screen._slot_buttons[5])
		33:
			var run = root.get_node("Party").run
			check_log.append("after drag 3: slot 1 = %s, slot 6 = %s" % [run.board[0].get("unit", "empty"), run.board[5].get("unit", "empty")])
			_shot("12_draft_after_drags")
			# Slot 6 -> Sell button.
			_queue_drag(main.draft_screen._slot_buttons[5], main.draft_screen._sell_btn)
		35:
			var run = root.get_node("Party").run
			check_log.append("after drag 4 (sell): slot 6 = %s, gold = %d" % [run.board[5].get("unit", "empty"), run.gold])
			root.get_node("Party").disconnect_all()
			main.tabs.current_tab = 1
		36:
			# Army tab: drag the first Front line squad onto the Back line column.
			var army_tab = main.tabs.get_child(1)
			var front_list: VBoxContainer = army_tab._columns["front"]["list"]
			var back_list: VBoxContainer = army_tab._columns["back"]["list"]
			check_log.append("army before: %s" % [_rows()])
			_queue_drag(front_list.get_child(0), back_list)
		38:
			check_log.append("army after drag to back column: %s" % [_rows()])
			_shot("13_army_columns")
			for l in check_log:
				print("DRAG CHECK: ", l)
			quit(0)
	return false
