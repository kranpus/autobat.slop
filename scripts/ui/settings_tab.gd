extends VBoxContainer
## Player name, audio volume, save reset and asset credits.

const CREDITS := """[b]Art[/b]
• Dungeon Crawl Stone Soup 32x32 tiles (Crawl tiles team, collected by MedicineStorm): units, terrain and projectiles (CC0). opengameart.org/content/dungeon-crawl-32x32-tiles

[b]Sound effects[/b]
• Kenney: UI SFX Set and RPG Sounds (CC0). kenney.nl
• StarNinjas: 20 sword sound effects (CC0). opengameart.org/content/20-sword-sound-effects-attacks-and-clashes
• rubberduck: 80 CC0 RPG SFX (CC0). opengameart.org/content/80-cc0-rpg-sfx

[b]Music[/b]
• cynicmusic: "Battle Theme A" and "Town Theme RPG" (CC0). opengameart.org

[b]Engine[/b]
• Godot Engine (MIT). godotengine.org

See CREDITS.md for full details."""


func _ready() -> void:
	add_theme_constant_override("separation", 12)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 10)
	add_child(grid)

	grid.add_child(UIKit.label("Commander name", 15))
	var name_edit := LineEdit.new()
	name_edit.text = Profile.player_name()
	name_edit.max_length = 24
	name_edit.custom_minimum_size = Vector2(260, 0)
	name_edit.text_changed.connect(func(t: String):
		Profile.data["name"] = t.strip_edges() if t.strip_edges() != "" else "Commander")
	name_edit.focus_exited.connect(func(): Profile.save())
	name_edit.text_submitted.connect(func(_t): Profile.save())
	grid.add_child(name_edit)

	grid.add_child(UIKit.label("Music volume", 15))
	grid.add_child(_slider(Audio.music_volume, func(v: float): Audio.set_music_volume(v)))
	grid.add_child(UIKit.label("Effects volume", 15))
	grid.add_child(_slider(Audio.sfx_volume, func(v: float):
		Audio.set_sfx_volume(v)
		Audio.play_sfx("click")))

	var confirm := ConfirmationDialog.new()
	confirm.dialog_text = "Erase all progress and start over?"
	confirm.confirmed.connect(func(): Profile.reset())
	add_child(confirm)
	var reset := UIKit.button("Reset progress", func(): confirm.popup_centered())
	reset.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	add_child(reset)

	add_child(UIKit.label("Credits", 18, UIKit.ACCENT))
	var credits := RichTextLabel.new()
	credits.bbcode_enabled = true
	credits.text = CREDITS
	credits.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(credits)


func _slider(value: float, on_change: Callable) -> HSlider:
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.value = value
	s.custom_minimum_size = Vector2(260, 24)
	s.value_changed.connect(on_change)
	s.drag_ended.connect(func(_changed): Profile.save())
	return s
