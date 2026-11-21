extends HBoxContainer
## Legion Draft menu: rules, online matchmaking (dedicated server), LAN play,
## and the lobby of the match you're in.

var _wins: SpinBox
var _lives: SpinBox
var _max_players: SpinBox
var _turn_time: SpinBox
var _server: LineEdit
var _code: LineEdit
var _private: CheckBox
var _ip: LineEdit
var _rooms_box: VBoxContainer
var _found_box: VBoxContainer
var _lobby_box: VBoxContainer
var _status: Label
var _conn_label: Label


func _ready() -> void:
	add_theme_constant_override("separation", 12)

	var left := UIKit.panel(UIKit.PANEL_LIGHT)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(left)
	var lscroll := ScrollContainer.new()
	lscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(lscroll)
	var lv := UIKit.vbox(8)
	lv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lscroll.add_child(lv)

	lv.add_child(UIKit.label("Legion Draft", 22, UIKit.ACCENT))
	var rules := RichTextLabel.new()
	rules.bbcode_enabled = true
	rules.fit_content = true
	rules.text = """A drafting mode for a group of players. Your collection isn't used: everyone starts from scratch.
• Each round: [b]%d gold[/b]. Units and trinkets cost [b]%d[/b], reroll [b]%d[/b], freeze items to keep them.
• Up to [b]%d squads[/b]: slots 1-2 front line, 3-4 middle, 5-6 back. Put a [b]duplicate[/b] on a unit to level it (Lv2 at 3 copies, Lv3 at 6).
• Every unit has a unique [b]out-of-battle ability[/b]; [b]trinkets[/b] (6 tiers) change how squads fight.
• The [b]shop tier rises every %d battles[/b]. Battle other players each round: reach the win target, or run out of lives.""" % [DraftData.TURN_GOLD, DraftData.UNIT_COST, DraftData.REROLL_COST, DraftData.BOARD_SLOTS, DraftData.BATTLES_PER_TIER]
	lv.add_child(rules)

	lv.add_child(UIKit.label("Match settings (for matches you create)", 16, UIKit.ACCENT))
	var g := GridContainer.new()
	g.columns = 4
	g.add_theme_constant_override("h_separation", 12)
	_wins = _spin(g, "Wins to win", 1, 30, 10)
	_lives = _spin(g, "Lives", 1, 20, 5)
	_max_players = _spin(g, "Max players", 2, 16, 8)
	_turn_time = _spin(g, "Turn time (s)", 20, 300, 75)
	lv.add_child(g)

	# --- Online ---------------------------------------------------------------
	lv.add_child(HSeparator.new())
	lv.add_child(UIKit.label("Online", 18, UIKit.ACCENT))
	var srow := UIKit.hbox(8)
	srow.add_child(UIKit.label("Server", 14))
	_server = LineEdit.new()
	_server.text = Party.server_address()
	_server.placeholder_text = "play.example.com  (or host:port)"
	_server.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_server.text_changed.connect(func(t: String): Profile.data["server_address"] = t.strip_edges())
	_server.focus_exited.connect(func(): Profile.save())
	srow.add_child(_server)
	_conn_label = UIKit.label("", 13, UIKit.TEXT_DIM)
	srow.add_child(_conn_label)
	lv.add_child(srow)
	var orow := UIKit.hbox(8)
	orow.add_child(UIKit.button("Quick Match", func(): Party.online_quick(Profile.player_name(), _settings())))
	orow.add_child(UIKit.button("Create Match", func(): Party.online_create(Profile.player_name(), _settings(), not _private.button_pressed)))
	_private = CheckBox.new()
	_private.text = "Private (code only)"
	orow.add_child(_private)
	orow.add_child(UIKit.button("Browse", func(): Party.online_list(Profile.player_name())))
	lv.add_child(orow)
	var crow := UIKit.hbox(8)
	crow.add_child(UIKit.label("Join with code", 14))
	_code = LineEdit.new()
	_code.placeholder_text = "ABCDE"
	_code.max_length = 8
	_code.custom_minimum_size = Vector2(110, 0)
	crow.add_child(_code)
	crow.add_child(UIKit.button("Join", func(): Party.online_join(Profile.player_name(), _code.text)))
	crow.add_child(UIKit.spacer())
	crow.add_child(UIKit.button("Disconnect", func(): Party.disconnect_all()))
	lv.add_child(crow)
	var onote := UIKit.label("Quick Match puts you in an open room that starts by itself and fills empty seats with bots. Create Match gives you a code to share with friends.", 12, UIKit.TEXT_DIM)
	onote.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lv.add_child(onote)
	_rooms_box = UIKit.vbox(6)
	lv.add_child(_rooms_box)

	# --- LAN --------------------------------------------------------------------
	lv.add_child(HSeparator.new())
	lv.add_child(UIKit.label("Local network (no server needed)", 18, UIKit.ACCENT))
	var brow := UIKit.hbox(8)
	brow.add_child(UIKit.button("Quick Match (LAN)", func(): Party.quick_lan(Profile.player_name(), _settings())))
	brow.add_child(UIKit.button("Host Match", func(): Party.host_lan(Profile.player_name(), _settings())))
	brow.add_child(UIKit.button("Find Matches", func(): Party.start_search()))
	lv.add_child(brow)
	var jrow := UIKit.hbox(8)
	jrow.add_child(UIKit.label("Join by IP:", 14))
	_ip = LineEdit.new()
	_ip.text = "127.0.0.1"
	_ip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	jrow.add_child(_ip)
	jrow.add_child(UIKit.button("Join", func(): Party.join_lan(_ip.text.strip_edges(), Party.PORT, Profile.player_name())))
	lv.add_child(jrow)
	_found_box = UIKit.vbox(6)
	lv.add_child(_found_box)

	_status = UIKit.label("Not connected.", 13, UIKit.TEXT_DIM)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lv.add_child(_status)

	# --- Lobby ------------------------------------------------------------------
	var right := UIKit.panel(UIKit.PANEL_LIGHT)
	right.custom_minimum_size = Vector2(420, 0)
	add_child(right)
	_lobby_box = UIKit.vbox(8)
	right.add_child(_lobby_box)

	Party.lobby_changed.connect(_refresh_lobby)
	Party.online_changed.connect(_refresh_conn)
	Party.lobbies_found.connect(_show_found)
	Party.rooms_listed.connect(_show_rooms)
	Party.status.connect(func(t: String): _status.text = t)
	var tick := Timer.new()
	tick.wait_time = 1.0
	tick.autostart = true
	tick.timeout.connect(_on_tick)
	add_child(tick)
	_refresh_lobby()
	_refresh_conn()
	_show_found([])


func _on_tick() -> void:
	# Only the quick-match countdown needs a live refresh.
	if Party.phase == "lobby" and Party.room_quick and Party.auto_start_msec > 0:
		_refresh_lobby()


func _spin(grid: GridContainer, text: String, lo: int, hi: int, value: int) -> SpinBox:
	grid.add_child(UIKit.label(text, 14))
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.value = value
	grid.add_child(s)
	return s


func _settings() -> Dictionary:
	return {"wins": int(_wins.value), "lives": int(_lives.value), "max_players": int(_max_players.value), "turn_time": int(_turn_time.value)}


func _refresh_conn() -> void:
	if Party.online and Party.phase != "connecting":
		_conn_label.text = "● connected"
		_conn_label.add_theme_color_override("font_color", UIKit.GOOD)
	elif Party.online:
		_conn_label.text = "connecting..."
		_conn_label.add_theme_color_override("font_color", UIKit.ACCENT)
	else:
		_conn_label.text = "offline"
		_conn_label.add_theme_color_override("font_color", UIKit.TEXT_DIM)


func _show_rooms(list: Array) -> void:
	UIKit.clear(_rooms_box)
	if list.is_empty():
		_rooms_box.add_child(UIKit.label("No open public matches right now. Try Quick Match or create one.", 13, UIKit.TEXT_DIM))
		return
	for r in list:
		var h := UIKit.hbox(10)
		h.add_child(UIKit.label("%s's match" % r["name"] if not r["quick"] else "Quick match", 15))
		h.add_child(UIKit.label("%d/%d players · %d wins · %d lives · %ds turns" % [int(r["players"]), int(r["max"]), int(r["wins"]), int(r["lives"]), int(r["turn_time"])], 12, UIKit.TEXT_DIM))
		h.add_child(UIKit.spacer())
		var code: String = r["code"]
		h.add_child(UIKit.button("Join", func(): Party.online_join(Profile.player_name(), code)))
		_rooms_box.add_child(h)


func _show_found(list: Array) -> void:
	UIKit.clear(_found_box)
	if list.is_empty():
		_found_box.add_child(UIKit.label("No LAN matches found yet.", 13, UIKit.TEXT_DIM))
		return
	for l in list:
		var h := UIKit.hbox(10)
		h.add_child(UIKit.label("%s's match" % l["name"], 15))
		h.add_child(UIKit.label("%d/%d players · %d wins · %d lives" % [int(l["players"]), int(l["max"]), int(l["wins"]), int(l["lives"])], 13, UIKit.TEXT_DIM))
		h.add_child(UIKit.spacer())
		var b := UIKit.button("Join", func(): Party.join_lan(l["ip"], int(l["port"]), Profile.player_name()))
		b.disabled = int(l["players"]) >= int(l["max"])
		h.add_child(b)
		_found_box.add_child(h)


func _refresh_lobby() -> void:
	if not is_inside_tree():
		return
	_refresh_conn()
	UIKit.clear(_lobby_box)
	if Party.phase != "lobby":
		_lobby_box.add_child(UIKit.label("Lobby", 20, UIKit.ACCENT))
		var msg := "Connecting..." if Party.phase == "connecting" else ("Connected. Pick Quick Match, Create Match, Browse or a code." if Party.phase == "online" else "Find, create or join a match to see the players here.")
		_lobby_box.add_child(_wrapped(msg, 14, UIKit.TEXT_DIM))
		return
	var s := Party.settings
	var where := "LAN match" if not Party.online else ("Quick match" if Party.room_quick else "Match")
	_lobby_box.add_child(UIKit.label(where, 20, UIKit.ACCENT))
	if Party.online and not Party.room_quick:
		var code_row := UIKit.hbox(8)
		code_row.add_child(UIKit.label("Code: %s" % Party.room_code, 22, Color.WHITE))
		code_row.add_child(UIKit.button("Copy", func(): DisplayServer.clipboard_set(Party.room_code)))
		_lobby_box.add_child(code_row)
		_lobby_box.add_child(UIKit.label("Public: anyone can join from Browse" if Party.room_public else "Private: share the code with friends", 12, UIKit.TEXT_DIM))
	_lobby_box.add_child(UIKit.label("First to %d wins · %d lives · up to %d players · %ds turns" % [int(s["wins"]), int(s["lives"]), int(s["max_players"]), int(s["turn_time"])], 13, UIKit.TEXT_DIM))
	if Party.room_quick and Party.auto_start_msec > 0:
		@warning_ignore("integer_division")
		var secs := maxi(0, (Party.auto_start_msec - Time.get_ticks_msec()) / 1000)
		_lobby_box.add_child(UIKit.label("Starting in %ds (empty seats get bots)" % secs, 15, UIKit.GOOD))
	var ids: Array = Party.players.keys()
	ids.sort()
	for id in ids:
		var p: Dictionary = Party.players[id]
		var h := UIKit.hbox(8)
		var tag := ""
		if int(id) == Party.owner_id:
			tag += "  (host)"
		if int(id) == Party.my_id:
			tag += "  (you)"
		h.add_child(UIKit.label(str(p["name"]) + tag, 15))
		h.add_child(UIKit.spacer())
		h.add_child(UIKit.label("Ready" if p["ready"] or int(id) == Party.owner_id else "Not ready", 13, UIKit.GOOD if p["ready"] or int(id) == Party.owner_id else UIKit.BAD))
		if Party.is_owner() and int(id) != Party.my_id:
			var pid: int = id
			h.add_child(UIKit.button("Remove", func(): Party.kick(pid)))
		_lobby_box.add_child(h)
	var row := UIKit.hbox(8)
	if Party.is_owner():
		var add := UIKit.button("Add Bot", func(): Party.add_bot())
		add.disabled = Party.players.size() >= int(s["max_players"])
		row.add_child(add)
		var start := UIKit.button("Start Match", func(): Party.start_match())
		start.disabled = not Party.can_start()
		start.tooltip_text = "Needs at least 2 players (bots count) and everyone ready."
		row.add_child(start)
	else:
		var is_ready := bool(Party.me().get("ready", false))
		row.add_child(UIKit.button("Not ready" if is_ready else "Ready!", func(): Party.set_ready(not is_ready)))
	row.add_child(UIKit.button("Leave", func(): Party.leave()))
	_lobby_box.add_child(row)


func _wrapped(text: String, size: int, color: Color) -> Label:
	var l := UIKit.label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l
