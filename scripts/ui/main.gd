extends Node
## Root of the game: owns the menu UI and swaps to a BattleScreen for fights.

const CollectionTab := preload("res://scripts/ui/collection_tab.gd")
const ArmyTab := preload("res://scripts/ui/army_tab.gd")
const ExpeditionTab := preload("res://scripts/ui/expedition_tab.gd")
const PvpTab := preload("res://scripts/ui/pvp_tab.gd")
const SettingsTab := preload("res://scripts/ui/settings_tab.gd")
const BattleScreen := preload("res://scripts/battle/battle_screen.gd")

var menu_layer: CanvasLayer
var tabs: TabContainer
var collection_tab: Control
var _gold_label: Label
var _maps_label: Label
var _rating_label: Label
var _battle: Node = null


func _ready() -> void:
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
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	root.add_child(margin)

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
	var settings_tab := SettingsTab.new()
	settings_tab.name = "Settings"
	tabs.add_child(settings_tab)
	tabs.tab_changed.connect(func(_i): Audio.play_sfx("toggle", -8.0))

	Profile.changed.connect(_refresh_top_bar)
	Net.match_ready.connect(start_battle)
	_refresh_top_bar()

	var tick := Timer.new()
	tick.wait_time = 1.0
	tick.autostart = true
	tick.timeout.connect(_refresh_top_bar)
	add_child(tick)

	Audio.play_music("menu")


func _build_top_bar() -> Control:
	var p := UIKit.panel(UIKit.PANEL)
	var h := UIKit.hbox(24)
	p.add_child(h)
	h.add_child(UIKit.label("AUTOBAT LEGIONS", 22, UIKit.ACCENT))
	h.add_child(UIKit.spacer())
	_gold_label = UIKit.label("", 17, Color("ffd76a"))
	_maps_label = UIKit.label("", 17, Color("9fd3ff"))
	_rating_label = UIKit.label("", 17, Color("ffffff"))
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
	_maps_label.text = "Scouting Maps: %d/%d%s" % [Profile.maps(), Profile.MAX_MAPS, timer_text]
	_rating_label.text = "Rating: %d   W/L %d/%d" % [Profile.rating(), int(Profile.data["wins"]), int(Profile.data["losses"])]


## config keys: mode, seed, squads_a, squads_b, name_a, name_b,
## rating_a, rating_b, local_team, tile
func start_battle(config: Dictionary) -> void:
	if _battle != null:
		return
	menu_layer.visible = false
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
	menu_layer.visible = true
	Audio.play_music("menu")
	Profile.changed.emit()
