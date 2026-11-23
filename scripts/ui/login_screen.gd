extends Control
## Sign in / create an account on the server, or play offline as a guest.
##
## Signed in, your collection, army and rating live on the server (so they
## follow you to any device and can't be edited locally). Offline play keeps
## a separate guest profile on this device.

signal finished

var _server_edit: LineEdit
var _user_edit: LineEdit
var _pass_edit: LineEdit
var _pass2_edit: LineEdit
var _pass2_row: Control
var _remember: CheckBox
var _status: Label
var _main_button: Button
var _toggle_button: Button
var _buttons: Array[Button] = []
var _creating := false
var _busy := false
var _note: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UIKit.make_theme()
	add_child(UIKit.background())

	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	var panel := UIKit.panel(UIKit.PANEL)
	center.add_child(panel)
	var v := UIKit.vbox(10)
	v.custom_minimum_size = Vector2(minf(420.0, get_viewport_rect().size.x - 48.0), 0)
	panel.add_child(v)

	var title := UIKit.label("AUTOBAT LEGIONS", 28, UIKit.ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var intro := UIKit.label("Sign in to keep your legion on the server: play from any device, with ranked battles and draft rewards checked by the server.", 13, UIKit.TEXT_DIM)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(intro)

	v.add_child(UIKit.label("Server", 14))
	_server_edit = _field(v, Party.server_address(), "host or IP[:port]")
	v.add_child(UIKit.label("Username", 14))
	_user_edit = _field(v, str(Profile.settings.get("last_user", "")), "3-20 letters, numbers or _")
	_user_edit.max_length = AccountStore.USERNAME_MAX
	v.add_child(UIKit.label("Password", 14))
	_pass_edit = _field(v, "", "at least %d characters" % Passwords.MIN_LENGTH)
	_pass_edit.secret = true
	_pass_edit.max_length = Passwords.MAX_LENGTH
	_pass2_row = UIKit.vbox(6)
	_pass2_row.add_child(UIKit.label("Repeat password", 14))
	v.add_child(_pass2_row)
	_pass2_edit = _field(_pass2_row, "", "the same password again")
	_pass2_edit.secret = true
	_pass2_edit.max_length = Passwords.MAX_LENGTH
	_pass2_row.visible = false
	_user_edit.text_submitted.connect(func(_t): _pass_edit.grab_focus())
	_pass_edit.text_submitted.connect(func(_t):
		if _creating:
			_pass2_edit.grab_focus()
		else:
			_submit())
	_pass2_edit.text_submitted.connect(func(_t): _submit())

	_remember = CheckBox.new()
	_remember.text = "Keep me signed in on this device"
	_remember.button_pressed = true
	v.add_child(_remember)

	_main_button = UIKit.button("Sign in", _submit)
	_main_button.custom_minimum_size = Vector2(0, 44)
	v.add_child(_main_button)
	_toggle_button = UIKit.button("New here? Create an account", _toggle_mode)
	v.add_child(_toggle_button)
	var offline := UIKit.button("Play offline (guest)", _play_offline)
	offline.tooltip_text = "Progress is kept on this device only. You can sign in later from Settings."
	v.add_child(offline)
	_buttons = [_main_button, _toggle_button]

	_status = UIKit.label("", 13, UIKit.TEXT_DIM)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_status)
	var ver := UIKit.label("Version %s" % Party.build_version(), 11, UIKit.TEXT_DIM)
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.add_child(ver)
	_note = UIKit.label("", 11, UIKit.TEXT_DIM)
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_note)
	_server_edit.text_changed.connect(func(t: String):
		Profile.settings["server_address"] = t.strip_edges()
		_update_note())
	_update_note()

	Party.login_result.connect(_on_login_result)
	Party.status.connect(_on_status)


## Says whether the password travels encrypted. In the browser that depends
## on the server: wss:// is encrypted, plain ws:// (home networks) is not.
func _update_note() -> void:
	if Party.connection_encrypted():
		_note.text = "Your password is sent over an encrypted connection and the server keeps only a salted hash of it, never the password itself."
		_note.add_theme_color_override("font_color", UIKit.TEXT_DIM)
	else:
		_note.text = "This server connection is NOT encrypted (fine on your home network). Don't reuse a password from anything important. The server stores only a salted hash of it."
		_note.add_theme_color_override("font_color", UIKit.ACCENT)


## Sign in with the saved login straight away (shows progress meanwhile).
func auto_login() -> bool:
	if not Party.try_auto_login():
		return false
	_set_busy(true, "Signing in as %s..." % str(Profile.settings["account"]["user"]))
	return true


func _field(parent: Control, text: String, placeholder: String) -> LineEdit:
	var e := LineEdit.new()
	e.text = text
	e.placeholder_text = placeholder
	e.custom_minimum_size = Vector2(0, 36)
	parent.add_child(e)
	return e


func _toggle_mode() -> void:
	_creating = not _creating
	_pass2_row.visible = _creating
	_main_button.text = "Create account" if _creating else "Sign in"
	_toggle_button.text = "Have an account? Sign in" if _creating else "New here? Create an account"
	_status.text = ""


func _submit() -> void:
	if _busy:
		return
	var user := _user_edit.text.strip_edges()
	var problem := AccountStore.check_username(user)
	if problem == "" and _creating:
		problem = Passwords.check_new_password(_pass_edit.text)
		if problem == "" and _pass_edit.text != _pass2_edit.text:
			problem = "The passwords don't match."
	elif problem == "" and _pass_edit.text == "":
		problem = "Enter your password."
	if problem != "":
		_show_error(problem)
		return
	var addr := _server_edit.text.strip_edges()
	Profile.settings["server_address"] = addr
	Profile.settings["last_user"] = user
	Profile.save_settings()
	_set_busy(true, "Creating your account..." if _creating else "Signing in...")
	if _creating:
		Party.register(user, _pass_edit.text, _remember.button_pressed)
	else:
		Party.login(user, _pass_edit.text, _remember.button_pressed)


func _play_offline() -> void:
	if Party.logged_in:
		Party.logout()
	elif _busy:
		Party.disconnect_all(true)
	Profile.settings["start_offline"] = true
	Profile.save_settings()
	_close()


func _on_login_result(ok: bool, message: String) -> void:
	if ok:
		Profile.settings.erase("start_offline")
		Profile.save_settings()
		Audio.play_sfx("coins")
		_close()
	else:
		_set_busy(false, "")
		_show_error(message)


func _on_status(text: String) -> void:
	if _busy:
		_status.text = text


func _show_error(text: String) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", UIKit.BAD)
	_pass_edit.text = ""
	_pass2_edit.text = ""


func _set_busy(busy: bool, text: String) -> void:
	_busy = busy
	for b in _buttons:
		b.disabled = busy
	if text != "":
		_status.text = text
		_status.add_theme_color_override("font_color", UIKit.TEXT_DIM)


func _close() -> void:
	_pass_edit.text = ""
	_pass2_edit.text = ""
	finished.emit()
	queue_free()
