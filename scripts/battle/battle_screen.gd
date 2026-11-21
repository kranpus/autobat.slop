extends Node
## A full battle: deployment preview, the live fight (BattleView), HUD with
## speed controls, and the results/rewards panel.

signal closed

var config: Dictionary = {}
var sim: BattleSim
var view: BattleView
var _hud: CanvasLayer
var _count_a: Label
var _count_b: Label
var _bar_a: ProgressBar
var _bar_b: ProgressBar
var _clock: Label
var _start_panel: Control
var _result_panel: PanelContainer
var _verify_label: Label
var _local_team := 0
var _auto_start_timer: Timer


func _ready() -> void:
	_local_team = int(config.get("local_team", 0))
	sim = BattleSim.new()
	sim.setup(config["squads_a"], config["squads_b"], int(config["seed"]), str(config.get("map", BattleMaps.DEFAULT_MAP)))
	view = BattleView.new()
	add_child(view)
	view.setup(sim)
	view.battle_finished.connect(_on_finished)
	_build_hud()
	var mode: String = config.get("mode", "")
	if mode == "live":
		Net.result_verified.connect(_on_verified)
	if mode == "live" or mode == "draft":
		# Start automatically so multiplayer matches keep moving.
		_auto_start_timer = Timer.new()
		_auto_start_timer.one_shot = true
		_auto_start_timer.wait_time = 3.0
		_auto_start_timer.timeout.connect(_begin)
		add_child(_auto_start_timer)
		_auto_start_timer.start()


func _build_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.layer = 5
	add_child(_hud)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UIKit.make_theme()
	_hud.add_child(root)

	# Top bar
	var top := UIKit.panel(Color(0.08, 0.09, 0.12, 0.85))
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 10
	top.offset_right = -10
	top.offset_top = 8
	root.add_child(top)
	var h := UIKit.hbox(16)
	top.add_child(h)
	var a_name := "%s%s" % [config.get("name_a", "Blue"), "  (you)" if _local_team == 0 else ""]
	var b_name := "%s%s" % [config.get("name_b", "Red"), "  (you)" if _local_team == 1 else ""]
	var av := UIKit.vbox(2)
	av.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	av.add_child(UIKit.label(a_name, 16, Color("7fb2ff")))
	_bar_a = _make_bar(Color("3f7fff"))
	av.add_child(_bar_a)
	_count_a = UIKit.label("", 13, UIKit.TEXT_DIM)
	av.add_child(_count_a)
	h.add_child(av)
	_clock = UIKit.label("0:00", 22, UIKit.ACCENT)
	_clock.custom_minimum_size = Vector2(90, 0)
	_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	h.add_child(_clock)
	var bv := UIKit.vbox(2)
	bv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var bl := UIKit.label(b_name, 16, Color("ff8a80"))
	bl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bv.add_child(bl)
	_bar_b = _make_bar(Color("ff4f40"))
	_bar_b.fill_mode = ProgressBar.FILL_END_TO_BEGIN
	bv.add_child(_bar_b)
	_count_b = UIKit.label("", 13, UIKit.TEXT_DIM)
	_count_b.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bv.add_child(_count_b)
	h.add_child(bv)

	# Bottom controls
	var bottom := UIKit.hbox(6)
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	bottom.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom.offset_left = -12
	bottom.offset_top = -12
	bottom.offset_right = -12
	bottom.offset_bottom = -12
	root.add_child(bottom)
	bottom.add_child(UIKit.label("Speed", 14, UIKit.TEXT_DIM))
	for s in [1, 2, 4]:
		var sp: int = s
		bottom.add_child(UIKit.button("%dx" % sp, func(): view.speed_mult = float(sp)))
	bottom.add_child(UIKit.button("Recenter", func(): view.fit_camera()))
	if config.get("mode", "") != "live":
		bottom.add_child(UIKit.button("Skip to result", func():
			_begin()
			view.skip_to_end()))

	var hint := UIKit.label("Mouse wheel: zoom    Drag: pan", 12, UIKit.TEXT_DIM)
	hint.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hint.offset_left = 12
	hint.offset_right = 12
	hint.offset_top = -14
	hint.offset_bottom = -14
	root.add_child(hint)

	# Deployment / start panel
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)
	var sp_panel := UIKit.panel(Color(0.08, 0.09, 0.12, 0.9))
	center.add_child(sp_panel)
	_start_panel = sp_panel
	var sv := UIKit.vbox(10)
	sp_panel.add_child(sv)
	var title := UIKit.label("%d  vs  %d units" % [sim.start_count[0], sim.start_count[1]], 26, UIKit.ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sv.add_child(title)
	var pa := Army.format_power(Army.army_power(config["squads_a"]))
	var pb := Army.format_power(Army.army_power(config["squads_b"]))
	var sub := UIKit.label("Power %s  vs  %s" % [pa, pb], 15, UIKit.TEXT_DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sv.add_child(sub)
	var map_def := BattleMaps.get_map(sim.map_id)
	var map_l := UIKit.label("Battlefield: %s" % map_def["name"], 18, Color.WHITE)
	map_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sv.add_child(map_l)
	var map_d := UIKit.label(String(map_def["desc"]) + ("" if map_def["obstacles"].is_empty() else "  Flying units ignore terrain."), 13, UIKit.TEXT_DIM)
	map_d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	map_d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	map_d.custom_minimum_size = Vector2(380, 0)
	sv.add_child(map_d)
	if config.get("mode", "") == "live":
		sv.add_child(UIKit.label("Live duel starting...", 16))
	elif config.get("mode", "") == "draft":
		var rl := UIKit.label("Legion Draft round %d. Starting..." % int(config.get("round", 0)), 16)
		rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sv.add_child(rl)
	else:
		var go := UIKit.button("FIGHT!", _begin)
		go.custom_minimum_size = Vector2(200, 48)
		go.add_theme_font_size_override("font_size", 22)
		go.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		sv.add_child(go)

	# Result panel (hidden until the end)
	var rc := CenterContainer.new()
	rc.set_anchors_preset(Control.PRESET_FULL_RECT)
	rc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(rc)
	_result_panel = UIKit.panel(Color(0.08, 0.09, 0.12, 0.94))
	_result_panel.custom_minimum_size = Vector2(420, 0)
	_result_panel.visible = false
	rc.add_child(_result_panel)
	_update_hud()


func _make_bar(color: Color) -> ProgressBar:
	var b := ProgressBar.new()
	b.show_percentage = false
	b.custom_minimum_size = Vector2(0, 12)
	b.max_value = 1.0
	b.value = 1.0
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(3)
	b.add_theme_stylebox_override("fill", fill)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.5)
	bg.set_corner_radius_all(3)
	b.add_theme_stylebox_override("background", bg)
	return b


func _begin() -> void:
	if view.running:
		return
	_start_panel.visible = false
	view.running = true
	Audio.play_sfx("roar", -4.0)


func _process(_delta: float) -> void:
	_update_hud()


func _update_hud() -> void:
	if sim == null or _count_a == null:
		return
	_count_a.text = "%d / %d alive" % [sim.alive_count[0], sim.start_count[0]]
	_count_b.text = "%d / %d alive" % [sim.alive_count[1], sim.start_count[1]]
	_bar_a.value = float(sim.alive_count[0]) / maxf(1.0, float(sim.start_count[0]))
	_bar_b.value = float(sim.alive_count[1]) / maxf(1.0, float(sim.start_count[1]))
	var secs := int(sim.time)
	@warning_ignore("integer_division")
	_clock.text = "%d:%02d" % [secs / 60, secs % 60]


func _on_finished(winner: int) -> void:
	var mode: String = config.get("mode", "practice")
	var score := 0.5
	if winner == _local_team:
		score = 1.0
	elif winner != 2:
		score = 0.0
	var enemy := 1 - _local_team
	var killed := sim.start_count[enemy] - sim.alive_count[enemy]
	var opp_rating := int(config.get("rating_b", 1000)) if _local_team == 0 else int(config.get("rating_a", 1000))
	# Draft battles are decided and rewarded by the match host, not here.
	var summary := {"gold": 0, "maps": 0, "rating": 0}
	if mode != "draft":
		summary = Profile.apply_battle_result(mode, score, opp_rating, killed)
	if mode == "live":
		Net.report_result(sim.checksum())

	var v := UIKit.vbox(8)
	_result_panel.add_child(v)
	var title_text := "DRAW"
	var title_color := UIKit.ACCENT
	if score >= 1.0:
		title_text = "VICTORY"
		title_color = UIKit.GOOD
		Audio.play_sfx("coins")
	elif score <= 0.0:
		title_text = "DEFEAT"
		title_color = UIKit.BAD
	var t := UIKit.label(title_text, 34, title_color)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var mine := _local_team
	v.add_child(UIKit.label("Your survivors: %d / %d" % [sim.alive_count[mine], sim.start_count[mine]], 15))
	v.add_child(UIKit.label("Enemies defeated: %d / %d" % [killed, sim.start_count[enemy]], 15))
	v.add_child(UIKit.label("Battle time: %d s" % int(sim.time), 15, UIKit.TEXT_DIM))
	if mode == "draft":
		var note := "Win: +1 win toward the goal." if score >= 1.0 else ("Loss: -1 life." if score <= 0.0 else "Draw: no change.")
		v.add_child(UIKit.label(note, 16, title_color))
	else:
		v.add_child(UIKit.label("+%d gold" % int(summary["gold"]), 16, Color("ffd76a")))
	if int(summary["maps"]) > 0:
		v.add_child(UIKit.label("+%d scouting map" % int(summary["maps"]), 16, Color("9fd3ff")))
	if mode == "ranked" or mode == "live":
		var d := int(summary["rating"])
		v.add_child(UIKit.label("Rating %s%d  (now %d)" % ["+" if d >= 0 else "", d, Profile.rating()], 16, UIKit.GOOD if d >= 0 else UIKit.BAD))
	if mode == "live":
		_verify_label = UIKit.label("Verifying result with opponent...", 13, UIKit.TEXT_DIM)
		v.add_child(_verify_label)
	var cont := UIKit.button("Continue", func(): closed.emit())
	cont.custom_minimum_size = Vector2(0, 40)
	v.add_child(cont)
	_result_panel.visible = true


func _on_verified(ok: bool) -> void:
	if _verify_label:
		_verify_label.text = "Result verified: both players saw the same battle." if ok else "Warning: results differ between players (desync or modified client)."
		_verify_label.add_theme_color_override("font_color", UIKit.GOOD if ok else UIKit.BAD)


func _exit_tree() -> void:
	if Net.result_verified.is_connected(_on_verified):
		Net.result_verified.disconnect(_on_verified)
