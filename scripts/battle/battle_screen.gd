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
var _rewards_box: VBoxContainer
var _hud_root: Control


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
	_hud_root = root
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

	var hint := UIKit.label("Pinch: zoom    Drag: pan" if UIKit.is_mobile() else "Mouse wheel: zoom    Drag: pan", 12, UIKit.TEXT_DIM)
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
		var go := UIKit.accent_button("FIGHT!", _begin, 22)
		go.custom_minimum_size = Vector2(200, 52)
		UIKit.tut(go, "battle_fight")
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
	# War drums (0.9.4: the old horn was harsh).
	Audio.play_sfx("battle_start", -3.0)
	if _has_boss():
		Audio.play_sfx("big_roar", 0.0)
	_banner("FIGHT!", UIKit.ACCENT, 0.9)


## A challenge with a named boss in it.
func _has_boss() -> bool:
	for sq in Challenges.get_challenge(str(config.get("challenge", ""))).get("enemy", []):
		if sq.has("title"):
			return true
	return false


## A big word that punches in and fades (FIGHT!, VICTORY, DEFEAT).
func _banner(text: String, color: Color, hold: float) -> void:
	var l := UIKit.label(text, 72, color)
	l.add_theme_constant_override("outline_size", 12)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_root.add_child(l)
	l.pivot_offset = get_viewport().get_visible_rect().size * 0.5
	l.scale = Vector2(2.2, 2.2)
	l.modulate.a = 0.0
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 1.0, 0.15)
	tw.chain().tween_interval(hold)
	tw.chain().tween_property(l, "modulate:a", 0.0, 0.35)
	tw.chain().tween_callback(l.queue_free)


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
	# Draft battles are decided and rewarded by the match host, and signed-in
	# ranked battles by the server, not here.
	var summary := {"gold": 0, "maps": 0, "rating": 0}
	if mode in ["ranked_online", "challenge_online"]:
		summary = Party.last_ranked_summary
	elif mode == "challenge":
		summary = Profile.complete_challenge(str(config.get("challenge", "")), score >= 1.0)
	elif mode != "draft":
		summary = Profile.apply_battle_result(mode, score, opp_rating, killed, bool(config.get("vs_ai", false)))
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
		var loss_note := "Loss: -1 life." if config.get("use_lives", true) else "Loss."
		var note := "Win: +1 win." if score >= 1.0 else (loss_note if score <= 0.0 else "Draw: no change.")
		v.add_child(UIKit.label(note, 16, title_color))
	else:
		_rewards_box = UIKit.vbox(6)
		v.add_child(_rewards_box)
		if mode in ["ranked_online", "challenge_online"] and summary.is_empty():
			_rewards_box.add_child(UIKit.label("Waiting for the server's result...", 14, UIKit.TEXT_DIM))
			Party.ranked_result.connect(_show_rewards.bind(mode), CONNECT_ONE_SHOT)
		else:
			_show_rewards(summary, mode)
	if mode == "live":
		_verify_label = UIKit.label("Verifying result with opponent...", 13, UIKit.TEXT_DIM)
		v.add_child(_verify_label)
	var cont := UIKit.accent_button("Continue", func(): closed.emit(), 17)
	UIKit.tut(cont, "battle_continue")
	v.add_child(cont)
	# The finish: a big banner and music sting, then the results.
	_banner(title_text, title_color, 0.6)
	if score >= 1.0:
		Audio.play_stinger("victory")
	elif score <= 0.0:
		Audio.play_stinger("defeat")
	view.shake(6.0 if score >= 1.0 else 3.0)
	get_tree().create_timer(1.1).timeout.connect(func():
		if is_instance_valid(_result_panel):
			_result_panel.visible = true)


func _show_rewards(summary: Dictionary, mode: String) -> void:
	if not is_instance_valid(_rewards_box):
		return
	UIKit.clear(_rewards_box)
	if mode in ["challenge", "challenge_online"]:
		_show_challenge_rewards(summary, mode)
		return
	if mode == "tutorial":
		_rewards_box.add_child(UIKit.label("Training battle%s" % ("" if Profile.online else ": +%d gold" % int(summary.get("gold", 0))), 16, Color("ffd76a")))
		return
	if Profile.online and mode in ["practice", "live"]:
		_rewards_box.add_child(UIKit.label("While signed in, only ranked battles and Legion Draft earn rewards.", 13, UIKit.TEXT_DIM))
		return
	var gold_text := "+%d gold" % int(summary.get("gold", 0))
	if float(summary.get("rank_mult", 1.0)) > 1.0:
		gold_text += "  (rank bonus x%s)" % str(snappedf(float(summary["rank_mult"]), 0.01))
	_rewards_box.add_child(UIKit.label(gold_text, 16, Color("ffd76a")))
	if int(summary.get("maps", 0)) > 0:
		_rewards_box.add_child(UIKit.label("+%d scouting map" % int(summary["maps"]), 16, Color("9fd3ff")))
	if mode in ["ranked", "ranked_online", "live"]:
		var d := int(summary.get("rating", 0))
		_rewards_box.add_child(UIKit.label("Rating %s%d  (now %d)" % ["+" if d >= 0 else "", d, Profile.rating()], 16, UIKit.GOOD if d >= 0 else UIKit.BAD))
	if int(summary.get("xp", 0)) > 0:
		_rewards_box.add_child(UIKit.label("+%d XP%s" % [int(summary["xp"]), "  ·  Commander level %d!" % int(summary["level"]) if bool(summary.get("level_up", false)) else ""], 15, UIKit.ACCENT))
	if mode == "ranked_online":
		_rewards_box.add_child(UIKit.label("Battle checked and rewarded by the server.", 12, UIKit.TEXT_DIM))


func _show_challenge_rewards(summary: Dictionary, mode: String) -> void:
	if not bool(summary.get("won", false)):
		_rewards_box.add_child(UIKit.label("Challenge failed. Strengthen your army and try again: the reward is still waiting.", 14, UIKit.TEXT_DIM))
		return
	if not bool(summary.get("first_clear", false)):
		_rewards_box.add_child(UIKit.label("Challenge cleared again. Rewards are only given the first time.", 14, UIKit.TEXT_DIM))
		return
	_rewards_box.add_child(UIKit.label("Challenge complete! First-clear reward:", 15, UIKit.GOOD))
	Audio.play_sfx("fanfare", -2.0)
	if int(summary.get("gold", 0)) > 0:
		_rewards_box.add_child(UIKit.label("+%d gold" % int(summary["gold"]), 16, Color("ffd76a")))
	if int(summary.get("maps", 0)) > 0:
		_rewards_box.add_child(UIKit.label("+%d scouting map%s" % [int(summary["maps"]), "" if int(summary["maps"]) == 1 else "s"], 16, Color("9fd3ff")))
	var t := str(summary.get("trinket", ""))
	if Trinkets.exists(t):
		var h := UIKit.hbox(8)
		h.add_child(UIKit.icon(Trinkets.texture(t), 28))
		h.add_child(UIKit.label(("New trinket: %s" if bool(summary.get("trinket_new", false)) else "%s (already owned, sold for gold)") % Trinkets.ALL[t]["name"], 15, GameData.rarity_color(Trinkets.rarity_of(t))))
		_rewards_box.add_child(h)
	var u := str(summary.get("unit", ""))
	if GameData.UNITS.has(u):
		var h2 := UIKit.hbox(8)
		h2.add_child(UIKit.unit_icon(u, 28))
		h2.add_child(UIKit.label(("New unit: %s joins your collection!" if bool(summary.get("unit_new", false)) else "%s: +" + str(int(summary.get("shards", 0))) + " shards") % GameData.UNITS[u]["name"], 15, GameData.rarity_color(GameData.UNITS[u]["rarity"])))
		_rewards_box.add_child(h2)
	if mode == "challenge_online":
		_rewards_box.add_child(UIKit.label("Battle checked and rewarded by the server.", 12, UIKit.TEXT_DIM))


func _on_verified(ok: bool) -> void:
	if _verify_label:
		_verify_label.text = "Result verified: both players saw the same battle." if ok else "Warning: results differ between players (desync or modified client)."
		_verify_label.add_theme_color_override("font_color", UIKit.GOOD if ok else UIKit.BAD)


func _exit_tree() -> void:
	if Net.result_verified.is_connected(_on_verified):
		Net.result_verified.disconnect(_on_verified)
