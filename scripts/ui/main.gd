extends Node
## Root of the game: owns the menu UI and swaps to a BattleScreen for fights.

const CollectionTab := preload("res://scripts/ui/collection_tab.gd")
const ArmyTab := preload("res://scripts/ui/army_tab.gd")
const ExpeditionTab := preload("res://scripts/ui/expedition_tab.gd")
const PvpTab := preload("res://scripts/ui/pvp_tab.gd")
const SettingsTab := preload("res://scripts/ui/settings_tab.gd")
const DraftLobbyTab := preload("res://scripts/ui/draft_lobby_tab.gd")
const DraftScreenScript := preload("res://scripts/ui/draft_screen.gd")
const BattleScreen := preload("res://scripts/battle/battle_screen.gd")
const LoginScreen := preload("res://scripts/ui/login_screen.gd")
const TrinketTab := preload("res://scripts/ui/trinket_tab.gd")
const LeaderboardTab := preload("res://scripts/ui/leaderboard_tab.gd")
const ChallengesTab := preload("res://scripts/ui/challenges_tab.gd")
const PatchNotesTab := preload("res://scripts/ui/patch_notes_tab.gd")
const TutorialScript := preload("res://scripts/ui/tutorial.gd")

var menu_layer: CanvasLayer
var tabs: TabContainer
var collection_tab: Control
var expedition_tab: Control
var trinket_tab: Control
var _gold_label: Label
var _maps_label: Label
var _rating_label: Label
var _battle: Node = null
var _battle_mode := ""
var draft_layer: CanvasLayer
var draft_screen: DraftScreenScript
var login_layer: CanvasLayer
var _account_label: Label
var _fullscreen_button: Button
var _update_dialog: AcceptDialog
var tutorial: CanvasLayer
var _toast_box: VBoxContainer
var _last_gold := -1
var _rotate_layer: CanvasLayer
var _gold_float_parent: Control


func _ready() -> void:
	if "--server" in OS.get_cmdline_user_args():
		_run_dedicated_server()
		return
	UIKit.apply_startup_display()
	UIKit.apply_ui_scale(get_tree())
	menu_layer = CanvasLayer.new()
	add_child(menu_layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = UIKit.make_theme()
	menu_layer.add_child(root)

	var bg := ColorRect.new()
	bg.color = UIKit.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(margin)
	UIKit.apply_margins(margin, 8 if UIKit.is_compact(self) else 12)

	var layout := UIKit.vbox(8)
	margin.add_child(layout)
	layout.add_child(_build_top_bar())

	tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(tabs)

	collection_tab = CollectionTab.new()
	collection_tab.name = "Collection"
	tabs.add_child(collection_tab)
	var army_tab := ArmyTab.new()
	army_tab.name = "Army"
	tabs.add_child(army_tab)
	# Expeditions has two sub-tabs: regions (units) and trinket hunts.
	var exp_tabs := TabContainer.new()
	exp_tabs.name = "Expeditions"
	tabs.add_child(exp_tabs)
	expedition_tab = ExpeditionTab.new()
	expedition_tab.name = "Regions"
	exp_tabs.add_child(expedition_tab)
	trinket_tab = TrinketTab.new()
	trinket_tab.name = "Trinkets"
	exp_tabs.add_child(trinket_tab)
	exp_tabs.tab_changed.connect(func(_i): Audio.play_sfx("toggle", -8.0))
	var pvp_tab := PvpTab.new()
	pvp_tab.name = "Battle"
	pvp_tab.battle_requested.connect(start_battle)
	tabs.add_child(pvp_tab)
	var challenges_tab := ChallengesTab.new()
	challenges_tab.name = "Challenges"
	challenges_tab.battle_requested.connect(start_battle)
	tabs.add_child(challenges_tab)
	var board_tab := LeaderboardTab.new()
	board_tab.name = "Leaderboard"
	tabs.add_child(board_tab)
	var draft_tab := DraftLobbyTab.new()
	draft_tab.name = "Legion Draft"
	tabs.add_child(draft_tab)
	var notes_tab := PatchNotesTab.new()
	notes_tab.name = "Patch Notes"
	tabs.add_child(notes_tab)
	var settings_tab := SettingsTab.new()
	settings_tab.name = "Settings"
	tabs.add_child(settings_tab)
	tabs.tab_changed.connect(func(_i): Audio.play_sfx("toggle", -8.0))
	# Opening the Patch Notes tab marks this version's notes as read.
	var notes_index := notes_tab.get_index()
	tabs.tab_changed.connect(func(i: int):
		if i == notes_index and str(Profile.settings.get("seen_patch", "")) != PatchNotes.latest():
			Profile.settings["seen_patch"] = PatchNotes.latest()
			Profile.save_settings()
		_refresh_badges())

	Profile.changed.connect(_refresh_top_bar)
	Profile.changed.connect(_refresh_badges)
	Net.match_ready.connect(start_battle)
	_refresh_top_bar()
	_refresh_badges()
	_build_toasts()
	_build_rotate_prompt()

	# Legion Draft: full-screen shop layer shown while in a match.
	draft_layer = CanvasLayer.new()
	draft_layer.layer = 2
	draft_layer.visible = false
	add_child(draft_layer)
	draft_screen = DraftScreenScript.new()
	draft_layer.add_child(draft_screen)
	draft_screen.leave_requested.connect(func(): Party.leave())
	Party.match_started.connect(_show_draft)
	Party.battle_ready.connect(start_battle)
	Party.left_match.connect(_on_left_draft)

	var tick := Timer.new()
	tick.wait_time = 1.0
	tick.autostart = true
	tick.timeout.connect(_refresh_top_bar)
	add_child(tick)

	Audio.play_music("menu")

	# Sign-in screen on top: signs in with a saved login, or asks (unless the
	# player chose to play offline last time).
	login_layer = CanvasLayer.new()
	login_layer.layer = 5
	add_child(login_layer)
	Party.session_changed.connect(_refresh_top_bar)
	Party.update_required.connect(_on_update_required)
	# The tutorial waits until the player is in (signed in or offline).
	tutorial = TutorialScript.new()
	tutorial.main = self
	add_child(tutorial)
	var login_open := false
	if (Profile.settings.has("account") or not bool(Profile.settings.get("start_offline", false))):
		var screen := show_login()
		if not screen.auto_login() and bool(Profile.settings.get("start_offline", false)):
			screen.queue_free()
		else:
			login_open = true
	if not login_open:
		tutorial.start_if_new.call_deferred()

	# Check in with the server for unit/region locks and gold settings now and
	# every 5 minutes while idle in the menus (quietly skipped if unreachable,
	# and not needed while signed in: the session keeps them current).
	Party.sync_from_server.call_deferred()
	var sync_timer := Timer.new()
	sync_timer.wait_time = 300.0
	sync_timer.autostart = true
	sync_timer.timeout.connect(func():
		if _battle == null and not Party.is_active():
			Party.sync_from_server())
	add_child(sync_timer)


## Headless matchmaking server: `godot --headless -- --server [--port=24702]`
func _run_dedicated_server() -> void:
	Engine.max_fps = 30
	OS.low_processor_usage_mode = true
	var port := Party.SERVER_PORT
	var env_port := OS.get_environment("PORT")
	if env_port.is_valid_int():
		port = int(env_port)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--port="):
			port = int(arg.get_slice("=", 1))
	if Party.start_server(port) != OK:
		get_tree().quit(1)


func _build_top_bar() -> Control:
	var compact := UIKit.is_compact(self)
	var p := UIKit.panel(UIKit.PANEL)
	if compact:
		var sb := StyleBoxFlat.new()
		sb.bg_color = UIKit.PANEL
		sb.set_corner_radius_all(6)
		sb.set_content_margin_all(6)
		p.add_theme_stylebox_override("panel", sb)
	var h := UIKit.hbox(14 if compact else 24)
	p.add_child(h)
	h.add_child(UIKit.label("AUTOBAT LEGIONS", 17 if compact else 22, UIKit.ACCENT))
	_account_label = UIKit.label("", 12 if compact else 14, UIKit.TEXT_DIM)
	h.add_child(_account_label)
	h.add_child(UIKit.spacer())
	var fs := 14 if compact else 17
	_gold_label = UIKit.label("", fs, Color("ffd76a"))
	_maps_label = UIKit.label("", fs, Color("9fd3ff"))
	_rating_label = UIKit.label("", fs, Color("ffffff"))
	h.add_child(_gold_label)
	h.add_child(_maps_label)
	h.add_child(_rating_label)
	if UIKit.can_toggle_fullscreen():
		_fullscreen_button = UIKit.button("Fullscreen", func(): UIKit.toggle_fullscreen())
		_fullscreen_button.tooltip_text = "Fill the whole screen (F11). Esc or F11 to leave."
		_fullscreen_button.focus_mode = Control.FOCUS_NONE
		h.add_child(_fullscreen_button)
	return p


func _refresh_top_bar() -> void:
	if _fullscreen_button:
		_fullscreen_button.text = "Windowed" if UIKit.is_fullscreen() else "Fullscreen"
	_gold_label.text = "Gold: %d" % Profile.gold()
	if _last_gold >= 0 and Profile.gold() > _last_gold and menu_layer.visible:
		_float_gold(Profile.gold() - _last_gold)
	_last_gold = Profile.gold()
	var next := Profile.seconds_to_next_map()
	var timer_text := ""
	if next >= 0:
		@warning_ignore("integer_division")
		timer_text = "  (+1 in %d:%02d)" % [next / 60, next % 60]
	_maps_label.text = "%s: %d/%d%s" % ["Maps" if UIKit.is_compact(self) else "Scouting Maps", Profile.maps(), Profile.MAX_MAPS, timer_text]
	_rating_label.text = "Rating: %d   W/L %d/%d" % [Profile.rating(), int(Profile.data["wins"]), int(Profile.data["losses"])]
	if Profile.online:
		_account_label.text = Profile.account + ("" if Party.session_active() else " (reconnecting...)")
		_account_label.add_theme_color_override("font_color", UIKit.GOOD if Party.session_active() else UIKit.ACCENT)
	else:
		_account_label.text = "Guest (offline)"
		_account_label.add_theme_color_override("font_color", UIKit.TEXT_DIM)


## "+120" rising from the gold counter when gold comes in.
func _float_gold(amount: int) -> void:
	var l := UIKit.label("+%d" % amount, 18, Color("ffd76a"))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu_layer.add_child(l)
	l.global_position = _gold_label.global_position + Vector2(0, 18)
	var tw := l.create_tween().set_parallel(true)
	tw.tween_property(l, "global_position:y", l.global_position.y + 34.0, 1.1).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 1.1).set_delay(0.4)
	tw.chain().tween_callback(l.queue_free)
	Audio.play_sfx("coins", -10.0)


# --- toasts and tab badges --------------------------------------------------------

func _build_toasts() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 15
	add_child(layer)
	var anchor := Control.new()
	anchor.set_anchors_preset(Control.PRESET_FULL_RECT)
	anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor.theme = UIKit.make_theme()
	layer.add_child(anchor)
	# Toasts rise from the bottom centre, clear of the tabs and top bar.
	_toast_box = UIKit.vbox(6)
	_toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_box.alignment = BoxContainer.ALIGNMENT_END
	_toast_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_toast_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_toast_box.offset_bottom = -70.0
	anchor.add_child(_toast_box)
	add_to_group("toast_host")


func show_toast(text: String, color: Color = Color.WHITE) -> void:
	if _toast_box == null:
		return
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.1, 0.14, 0.92)
	sb.border_color = Color(color, 0.7)
	sb.border_width_left = 4
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(10)
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(UIKit.label(text, 16, color))
	p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_toast_box.add_child(p)
	while _toast_box.get_child_count() > 3:
		_toast_box.get_child(0).queue_free()
	p.modulate.a = 0.0
	var tw := p.create_tween()
	tw.tween_property(p, "modulate:a", 1.0, 0.15)
	tw.tween_interval(2.2)
	tw.tween_property(p, "modulate:a", 0.0, 0.5)
	tw.tween_callback(p.queue_free)


## A red dot on tabs with something waiting: a squad upgrade you can afford,
## scouting maps piling up, a challenge your army can take, unread notes.
func _refresh_badges() -> void:
	if tabs == null:
		return
	var power := Army.army_power(Profile.battle_squads()) / 10.0
	for i in tabs.get_tab_count():
		var dot := false
		match str(tabs.get_tab_control(i).name):
			"Collection":
				for id in Profile.data["units"]:
					if Profile.can_tier_up(id):
						dot = true
						break
			"Expeditions":
				dot = Profile.maps() >= Profile.MAX_MAPS or Profile.has_pending_choice() or Profile.has_pending_trinket()
			"Challenges":
				for c in Challenges.LIST:
					if Profile.challenge_unlocked(c["id"]) and not Profile.challenge_cleared(c["id"]) and power >= Challenges.recommended(c["id"]):
						dot = true
						break
			"Patch Notes":
				dot = str(Profile.settings.get("seen_patch", "")) != PatchNotes.latest()
		tabs.set_tab_icon(i, UIKit.badge_dot() if dot else null)


# --- phones held upright ------------------------------------------------------------

## The game is laid out for landscape. A phone browser held upright gets a
## friendly prompt to turn it (the app itself is locked to landscape).
func _build_rotate_prompt() -> void:
	_rotate_layer = CanvasLayer.new()
	_rotate_layer.layer = 30
	_rotate_layer.visible = false
	add_child(_rotate_layer)
	var bg := ColorRect.new()
	bg.color = UIKit.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rotate_layer.add_child(bg)
	var c := CenterContainer.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rotate_layer.add_child(c)
	var v := UIKit.vbox(16)
	c.add_child(v)
	var icon := UIKit.label("↻", 96, UIKit.ACCENT)
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(icon)
	var t := UIKit.label("Turn your phone sideways", 40, Color.WHITE)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var s := UIKit.label("Autobat Legions plays in landscape.", 26, UIKit.TEXT_DIM)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(s)
	get_viewport().size_changed.connect(_update_rotate_prompt)
	_update_rotate_prompt()


func _update_rotate_prompt() -> void:
	var size := get_viewport().get_visible_rect().size
	var upright := UIKit.is_mobile() and size.y > size.x * 1.1
	if "--portrait-test" in OS.get_cmdline_user_args():
		upright = size.y > size.x * 1.1
	_rotate_layer.visible = upright


# --- tutorial -----------------------------------------------------------------------

## The tutorial's first fight: your army against a small pack of rats.
func start_tutorial_battle() -> void:
	tabs.current_tab = 0
	start_battle({
		"mode": "tutorial", "seed": 7, "map": "open_arena",
		"squads_a": Profile.battle_squads(),
		"squads_b": [{"unit": "rat_swarm", "level": 1, "count": 18, "row": "front"}],
		"name_a": Profile.player_name(), "name_b": "Rat Pack",
		"rating_a": Profile.rating(), "rating_b": 0, "local_team": 0,
	})


## The server (or LAN host) runs a different version of the game.
func _on_update_required(info: Dictionary) -> void:
	if _update_dialog and _update_dialog.visible:
		return
	if _update_dialog:
		_update_dialog.queue_free()
	var older := bool(info.get("older", true))
	var where := "match host" if bool(info.get("host", false)) else "server"
	var url := str(info.get("url", ""))
	_update_dialog = AcceptDialog.new()
	_update_dialog.theme = UIKit.make_theme()
	_update_dialog.title = "Update required" if older else "The %s needs updating" % where
	var text: String
	if older:
		text = "A new version of Autobat Legions is out.\n\nThe %s runs %s; your game is %s. Update to keep playing online (offline play still works)." % [where, info.get("theirs", "?"), info.get("mine", "?")]
		if not OS.has_feature("web") and url == "":
			text += "\n\nGet the new version from whoever runs the %s." % where
	else:
		text = "The %s runs an older version (%s) than your game (%s), so they can't play together until it's updated." % [where, info.get("theirs", "?"), info.get("mine", "?")]
	_update_dialog.dialog_text = text
	_update_dialog.dialog_autowrap = true
	_update_dialog.min_size = Vector2i(460, 0)
	if older and (OS.has_feature("web") or url != ""):
		_update_dialog.ok_button_text = "Reload to update" if OS.has_feature("web") else "Download update"
		_update_dialog.confirmed.connect(func(): Party.open_update(url))
		_update_dialog.add_cancel_button("Later")
	else:
		_update_dialog.ok_button_text = "OK"
	add_child(_update_dialog)
	_update_dialog.popup_centered()
	Audio.play_sfx("scroll")


## Open the sign-in screen (also used by Settings).
func show_login() -> Control:
	for c in login_layer.get_children():
		c.queue_free()
	var screen := LoginScreen.new()
	login_layer.add_child(screen)
	screen.finished.connect(func():
		if tutorial:
			tutorial.start_if_new())
	return screen


## config keys: mode, seed, squads_a, squads_b, name_a, name_b,
## rating_a, rating_b, local_team, tile
func start_battle(config: Dictionary) -> void:
	if _battle != null:
		return
	_battle_mode = str(config.get("mode", ""))
	if _battle_mode != "draft" and Party.is_in_match():
		return
	menu_layer.visible = false
	draft_layer.visible = false
	var screen := BattleScreen.new()
	screen.config = config
	screen.closed.connect(_on_battle_closed)
	_battle = screen
	add_child(screen)
	# Challenge fights with a named boss get the boss theme.
	var boss := false
	for sq in Challenges.get_challenge(str(config.get("challenge", ""))).get("enemy", []):
		boss = boss or sq.has("title")
	Audio.play_music("boss" if boss else "battle")


func _on_battle_closed() -> void:
	if _battle:
		_battle.queue_free()
		_battle = null
	Audio.play_music("menu")
	if _battle_mode == "draft" and Party.is_in_match():
		Party.battle_viewed()
		_show_draft()
		return
	menu_layer.visible = true
	Profile.changed.emit()


## Android back button / gesture: close a finished battle, otherwise step
## back to the first tab, and quit from there.
## F11 or Alt+Enter toggles fullscreen everywhere it's possible.
func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	if k.keycode == KEY_F11 or (k.keycode == KEY_ENTER and k.alt_pressed):
		UIKit.toggle_fullscreen()
		_refresh_top_bar()
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what != NOTIFICATION_WM_GO_BACK_REQUEST or menu_layer == null:
		return
	if _battle != null:
		var sim = _battle.get("sim")
		if sim != null and sim.finished:
			_battle.emit_signal("closed")
		return
	if draft_layer.visible:
		return  # use the Leave button so a match isn't quit by accident
	if tabs.current_tab != 0:
		tabs.current_tab = 0
	else:
		get_tree().quit()


func _show_draft() -> void:
	menu_layer.visible = false
	draft_layer.visible = true
	draft_screen.refresh()


func _on_left_draft(_reason: String) -> void:
	if _battle and _battle_mode == "draft":
		_battle.queue_free()
		_battle = null
	draft_layer.visible = false
	menu_layer.visible = true
	Audio.play_music("menu")
	Profile.changed.emit()
