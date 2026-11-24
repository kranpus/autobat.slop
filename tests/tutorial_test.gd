extends SceneTree
## Plays through the whole tutorial as a new player would: presses whatever
## the spotlight points at, fast-forwards battles, picks a recruit. Checks
## every chapter can be finished and the game ends up in the expected state.
##
##   godot --headless -s res://tests/tutorial_test.gd
## With a display, `-- --shots=DIR` also saves a screenshot of every step.
## `-- --existing`: a player who has already played isn't shown it, and
## Settings' replay and the skip button work.
## Exit code 0 when everything passed.

var main: Node
var profile: Node
var tut: Node
var frames := 0
var _failures := 0
var _last_key := ""
var _stuck := 0
var _actions: Array = []
var _start_units := 0
var _shots := ""
var _shot_at := -1
var _existing := false


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--existing":
			_existing = true
		if arg.begins_with("--shots="):
			_shots = arg.get_slice("=", 1)
			DirAccess.make_dir_recursive_absolute(_shots)
	profile = root.get_node("Profile")
	profile.settings["start_offline"] = true
	profile.settings.erase("account")
	profile.settings.erase("tutorial")
	profile.settings["server_address"] = "127.0.0.1:1"   # no server: offline opponents
	profile.reset()
	_start_units = profile.data["units"].size()
	if _existing:
		profile.data["wins"] = 4
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)


func check(cond: bool, msg: String) -> void:
	if cond:
		print("  ok   ", msg)
	else:
		_failures += 1
		printerr("  FAIL ", msg)


func _finish() -> void:
	var p: Dictionary = profile.settings.get("tutorial", {})
	print("steps taken: ", " > ".join(PackedStringArray(_actions)))
	check((p.get("done", []) as Array).size() == tut.CHAIN.size(), "every chapter finished (%s)" % [p.get("done", [])])
	check(int(profile.data["wins"]) + int(profile.data["losses"]) >= 1, "a ranked battle was fought")
	check(profile.data["units"].size() > _start_units or _units_with_shards() > 0, "a unit was recruited")
	check(profile.data["army"].size() > 0, "the army is set")
	check(not tut.is_running(), "the tutorial is over")
	print("\n%s (%d failure%s)" % ["ALL TUTORIAL TESTS PASSED" if _failures == 0 else "TUTORIAL TESTS FAILED", _failures, "" if _failures == 1 else "s"])
	quit(1 if _failures > 0 else 0)


func _units_with_shards() -> int:
	var n := 0
	for id in profile.data["units"]:
		n += int(profile.data["units"][id]["shards"])
	return n


func _process(_d: float) -> bool:
	frames += 1
	if _existing:
		return _existing_player()
	if frames == 5:
		tut = main.get("tutorial")
		check(tut != null and tut.is_running(), "a new player gets the tutorial")
	if frames < 10 or tut == null:
		return false
	if frames > 60 * 120:
		printerr("TIMEOUT in chapter '%s' step %d" % [tut.get("_chapter"), tut.get("_i")])
		_failures += 1
		_finish()
		return true
	if not tut.is_running():
		_finish()
		return true
	if frames % 6 != 0:
		return false   # give the UI a few frames between actions
	var step: Dictionary = tut.call("_current_step")
	var key := "%s/%d" % [tut.get("_chapter"), tut.get("_i")]
	if key != _last_key:
		_last_key = key
		_stuck = 0
		_actions.append(str(step.get("target", "")) if str(step.get("target", "")) != "" else ("[%s]" % ("hidden" if step.get("hide", false) else "message")))
		if _shots != "":
			_shot_at = frames + 24
			return false
	if _shot_at > 0:
		if frames < _shot_at:
			return false
		root.get_texture().get_image().save_png("%s/%02d_%s.png" % [_shots, _actions.size(), _actions[-1].replace(":", "_").replace("[", "").replace("]", "").replace(" ", "_")])
		_shot_at = -1
	_stuck += 1
	if _stuck > 400:
		printerr("STUCK at %s: %s" % [key, step])
		_failures += 1
		_finish()
		return true
	_act(step)
	return false


## Do what the tutorial asks.
func _act(step: Dictionary) -> void:
	if step.has("button"):
		var b: Button = tut.get("_action")
		if b.is_visible_in_tree():
			b.pressed.emit()
		return
	var battle = main.get("_battle")
	if step.get("hide", false):
		if battle != null and battle.view.running and not battle.sim.finished:
			battle.view.skip_to_end()
		if profile.has_pending_choice():
			profile.choose_recruit(0)
		return
	var target := str(step.get("target", ""))
	if target.begins_with("tab:"):
		main.show_tab(target.substr(4))
		return
	for n in get_nodes_in_group("tut"):
		if str(n.get_meta("tut", "")) == target and n.is_visible_in_tree() and n is BaseButton and not n.disabled:
			(n as BaseButton).pressed.emit()
			return


func _existing_player() -> bool:
	tut = main.get("tutorial")
	if frames == 10:
		check(not tut.is_running() and bool(profile.settings["tutorial"]["off"]), "a player who already played isn't shown the tutorial")
		tut.replay()
	if frames == 20:
		check(tut.is_running() and str(tut.get("_chapter")) == "first_battle", "Settings → Replay tutorial starts it from the beginning")
		tut.skip_all()
	if frames == 30:
		check(not tut.is_running() and bool(profile.settings["tutorial"]["off"]), "Skip tutorial turns it off (and it stays off)")
		print("\n%s (%d failure%s)" % ["ALL TUTORIAL TESTS PASSED" if _failures == 0 else "TUTORIAL TESTS FAILED", _failures, "" if _failures == 1 else "s"])
		quit(1 if _failures > 0 else 0)
		return true
	return false
