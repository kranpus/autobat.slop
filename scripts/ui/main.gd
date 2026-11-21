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

var menu_layer: CanvasLayer
var tabs: TabContainer
var collection_tab: Control
var _gold_label: Label
var _maps_label: Label
var _rating_label: Label
var _battle: Node = null
var _battle_mode := ""
var draft_layer: CanvasLayer
var draft_screen: DraftScreenScript
var login_layer: CanvasLayer
var _account_label: Label


func _ready() -> void:
	if "--server" in OS.get_cmdline_user_args():
		_run_dedicated_server()
		return
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
	var exp_tab := ExpeditionTab.new()
	exp_tab.name = "Expeditions"
	tabs.add_child(exp_tab)
	var pvp_tab := PvpTab.new()
	pvp_tab.name = "Battle"
	pvp_tab.battle_requested.connect(start_battle)
	tabs.add_child(pvp_tab)
	var draft_tab := DraftLobbyTab.new()
	draft_tab.name = "Legion Draft"
	tabs.add_child(draft_tab)
	var settings_tab := SettingsTab.new()
	settings_tab.name = "Settings"
	tabs.add_child(settings_tab)
	tabs.tab_changed.connect(func(_i): Audio.play_sfx("toggle", -8.0))

	Profile.changed.connect(_refresh_top_bar)
	Net.match_ready.connect(start_battle)
	_refresh_top_bar()

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
	if (Profile.settings.has("account") or not bool(Profile.settings.get("start_offline", false))):
		var screen := show_login()
		if not screen.auto_login() and bool(Profile.settings.get("start_offline", false)):
			screen.queue_free()

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
	return p


func _refresh_top_bar() -> void:
	_gold_label.text = "Gold: %d" % Profile.gold()
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


## Open the sign-in screen (also used by Settings).
func show_login() -> Control:
	for c in login_layer.get_children():
		c.queue_free()
	var screen := LoginScreen.new()
	login_layer.add_child(screen)
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
	Audio.play_music("battle")


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
