extends VBoxContainer
## Account, player name, audio volume, save reset and asset credits.

var _account_box: VBoxContainer
var _account_status: Label
var _name_edit: LineEdit
var _reset_button: Button

const CREDITS := """[b]Art[/b]
• Dungeon Crawl Stone Soup 32x32 tiles (Crawl tiles team, collected by MedicineStorm): units, terrain and projectiles (CC0). opengameart.org/content/dungeon-crawl-32x32-tiles

[b]Sound effects[/b]
• Kenney: UI SFX Set and RPG Sounds (CC0). kenney.nl
• StarNinjas: 20 sword sound effects (CC0). opengameart.org/content/20-sword-sound-effects-attacks-and-clashes
• rubberduck: 80 CC0 RPG SFX, 75 CC0 hit SFX and 80 CC0 creature SFX (CC0). opengameart.org
• Ogrebane, JaggedStone, NenadSimic, StumpyStrust, fvcalderan: battle swishes, spells, explosion, war horn, fanfare (CC0)

[b]Music[/b]
• cynicmusic: "Battle Theme A", "Battle Theme B" and "Town Theme RPG" (CC0). opengameart.org
• Emma_MA: "Determined Pursuit" and "QaziJamJam" (CC0); celestialghost8: "Victory"; RandomMind: "Medieval: Defeat Theme" (CC0)

[b]Engine[/b]
• Godot Engine (MIT). godotengine.org

See CREDITS.md for full details."""


func _ready() -> void:
	add_theme_constant_override("separation", 12)
	add_child(UIKit.label("Account", 18, UIKit.ACCENT))
	_account_box = UIKit.vbox(8)
	add_child(_account_box)
	_account_status = UIKit.label("", 13, UIKit.TEXT_DIM)
	_account_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_account_status)
	Party.session_changed.connect(_build_account)
	Party.status.connect(func(t: String):
		if is_visible_in_tree():
			_account_status.text = t)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 10)
	add_child(grid)

	grid.add_child(UIKit.label("Commander name", 15))
	var name_edit := LineEdit.new()
	_name_edit = name_edit
	name_edit.text = Profile.player_name()
	name_edit.max_length = 24
	name_edit.custom_minimum_size = Vector2(260, 0)
	name_edit.text_changed.connect(func(t: String):
		Profile.data["name"] = t.strip_edges() if t.strip_edges() != "" else "Commander")
	name_edit.editable = not Profile.online   # logged in: your name is your account
	name_edit.focus_exited.connect(func(): Profile.save())
	name_edit.text_submitted.connect(func(_t): Profile.save())
	grid.add_child(name_edit)

	grid.add_child(UIKit.label("Music volume", 15))
	grid.add_child(_slider(Audio.music_volume, func(v: float): Audio.set_music_volume(v)))
	grid.add_child(UIKit.label("Effects volume", 15))
	grid.add_child(_slider(Audio.sfx_volume, func(v: float):
		Audio.set_sfx_volume(v)
		Audio.play_sfx("click")))

	if UIKit.can_toggle_fullscreen():
		grid.add_child(UIKit.label("Display", 15))
		var fs := CheckBox.new()
		fs.text = "Fullscreen  (F11)"
		fs.button_pressed = UIKit.is_fullscreen()
		fs.toggled.connect(func(on: bool): UIKit.set_fullscreen(on))
		# Keep the box in step when fullscreen changes another way (F11, Esc).
		get_tree().root.size_changed.connect(func():
			if is_instance_valid(fs):
				fs.set_pressed_no_signal(UIKit.is_fullscreen()))
		grid.add_child(fs)

	grid.add_child(UIKit.label("Battles", 15))
	var shake_box := CheckBox.new()
	shake_box.text = "Screen shake"
	shake_box.button_pressed = bool(Profile.settings.get("screen_shake", true))
	shake_box.toggled.connect(func(on: bool):
		Profile.settings["screen_shake"] = on
		Profile.save_settings())
	grid.add_child(shake_box)

	grid.add_child(UIKit.label("Interface size", 15))
	var size_pick := OptionButton.new()
	var current := str(Profile.settings.get("ui_scale", "auto"))
	for opt in UIKit.UI_SCALES:
		var o: String = opt
		size_pick.add_item("Auto (%d%%)" % roundi(UIKit.auto_ui_scale() * 100.0) if o == "auto" else "%d%%" % roundi(float(o) * 100.0))
		size_pick.set_item_metadata(size_pick.item_count - 1, o)
		if o == current:
			size_pick.selected = size_pick.item_count - 1
	size_pick.tooltip_text = "Bigger text and buttons for phones and tablets. Auto picks a size from your screen."
	size_pick.item_selected.connect(func(i: int):
		Profile.settings["ui_scale"] = size_pick.get_item_metadata(i)
		Profile.save_settings()
		UIKit.apply_ui_scale(get_tree())
		# Rebuild the menus so every screen lays itself out for the new size.
		if not Party.is_in_match():
			get_tree().reload_current_scene.call_deferred())
	grid.add_child(size_pick)

	var confirm := ConfirmationDialog.new()
	confirm.dialog_text = "Erase all progress and start over?"
	confirm.confirmed.connect(func(): Profile.reset())
	add_child(confirm)
	var reset := UIKit.button("Reset progress", func(): confirm.popup_centered())
	reset.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	reset.tooltip_text = "Erases the offline (guest) profile on this device."
	_reset_button = reset
	add_child(reset)
	_build_account()

	add_child(UIKit.label("Autobat Legions %s" % Party.build_version(), 13, UIKit.TEXT_DIM))
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
	s.drag_ended.connect(func(_changed): Profile.save_settings())
	return s


func _build_account() -> void:
	if not is_instance_valid(_account_box):
		return
	UIKit.clear(_account_box)
	if is_instance_valid(_name_edit):
		_name_edit.text = Profile.player_name()
		_name_edit.editable = not Profile.online
	if is_instance_valid(_reset_button):
		_reset_button.disabled = Profile.online
	if Profile.online:
		var h := UIKit.hbox(12)
		var live := Party.session_active()
		h.add_child(UIKit.label("Signed in as %s on %s%s" % [Profile.account, Party.server_address(), "" if live else " (reconnecting...)"], 15, UIKit.GOOD if live else UIKit.ACCENT))
		h.add_child(UIKit.spacer())
		h.add_child(UIKit.button("Log out", func():
			Party.logout()
			_account_status.text = "Logged out. You're playing offline as a guest."))
		_account_box.add_child(h)
		var info := UIKit.label("Your legion is saved on the server. Ranked battles and Legion Draft rewards are checked and paid by the server.", 12, UIKit.TEXT_DIM)
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_account_box.add_child(info)
		var pw := UIKit.hbox(8)
		var old_pw := _secret("Current password")
		var new_pw := _secret("New password")
		pw.add_child(old_pw)
		pw.add_child(new_pw)
		pw.add_child(UIKit.button("Change password", func():
			var problem := Passwords.check_new_password(new_pw.text)
			if problem != "":
				_account_status.text = problem
				return
			Party.change_password(old_pw.text, new_pw.text)
			_account_status.text = "Changing password..."
			old_pw.text = ""
			new_pw.text = ""))
		_account_box.add_child(pw)
	else:
		var h := UIKit.hbox(12)
		h.add_child(UIKit.label("Playing offline as a guest: progress is saved on this device only.", 15))
		h.add_child(UIKit.spacer())
		h.add_child(UIKit.button("Sign in / create account", func():
			var main := get_tree().current_scene
			if main and main.has_method("show_login"):
				main.show_login()))
		_account_box.add_child(h)
		if Party.logged_in:
			_account_box.add_child(UIKit.label("Reconnecting to the server...", 13, UIKit.ACCENT))
	if Party.cert_changed:
		var c := UIKit.hbox(8)
		var warn := UIKit.label("The server's security certificate changed since you last connected.", 13, UIKit.BAD)
		warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		warn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		c.add_child(warn)
		c.add_child(UIKit.button("Trust new server certificate", func():
			Party.forget_server_certificate()
			_build_account()))
		_account_box.add_child(c)


func _secret(placeholder: String) -> LineEdit:
	var e := LineEdit.new()
	e.secret = true
	e.placeholder_text = placeholder
	e.max_length = Passwords.MAX_LENGTH
	e.custom_minimum_size = Vector2(160, 0)
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return e
