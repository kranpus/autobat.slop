extends SceneTree
## Records a battle for the itch.io page's animated GIF. Run with Godot's
## movie maker (frames go to the --write-movie folder), then make the GIF
## with ffmpeg (see itch/README.md):
##   xvfb-run -a -s "-screen 0 960x540x24" godot --rendering-driver opengl3 --resolution 960x540 \
##     --fixed-fps 20 --write-movie /tmp/frames/f.png --path . -s res://tools/itch_gif.gd

const SECONDS := 14.0
var main: Node
var profile: Node
var backup_settings: Dictionary


func _initialize() -> void:
	profile = root.get_node("Profile")
	backup_settings = profile.settings.duplicate(true)
	profile.settings["start_offline"] = true
	profile.settings["server_address"] = "127.0.0.1:1"
	profile.settings["tutorial"] = {"done": ["first_battle", "level_up", "recruit", "army", "ranked", "challenges", "finale"], "seen": ["trinkets", "draft", "leaderboard"]}
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _run() -> void:
	await create_timer(0.5).timeout
	for c in main.login_layer.get_children():
		c.queue_free()
	var shots := load("res://tools/itch_shots.gd")
	main.start_battle({"mode": "practice", "seed": 11, "squads_a": shots.ARMY_A, "squads_b": shots.ARMY_B,
		"name_a": "Commander Vale", "name_b": "Warlord Grak", "local_team": 0, "map": "whispering_forest"})
	await create_timer(0.3).timeout
	main._battle._begin()
	var cam: Camera2D = main._battle.view._camera
	cam.zoom *= 1.5
	await create_timer(SECONDS).timeout
	profile.settings = backup_settings
	profile.save_settings()
	quit(0)
