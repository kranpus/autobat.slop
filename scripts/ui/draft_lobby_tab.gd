extends HBoxContainer
## Legion Draft menu: explains the mode, hosts / finds / joins matches and
## shows the lobby until the host starts.

var _wins: SpinBox
var _lives: SpinBox
var _max_players: SpinBox
var _turn_time: SpinBox
var _ip: LineEdit
var _found_box: VBoxContainer
var _lobby_box: VBoxContainer
var _status: Label
var _ready_btn: Button


func _ready() -> void:
	add_theme_constant_override("separation", 12)

	# --- left: rules + matchmaking -----------------------------------------
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
	rules.text = """A drafting game mode for a group of players. Your normal collection isn't used: everyone starts from scratch each match.
• Each round you get [b]%d gold[/b]. Buy units ([b]%d[/b]) and trinkets ([b]%d[/b]) from the shop, reroll for [b]%d[/b], freeze items to keep them.
• Place up to [b]%d squads[/b]: slots 1-2 are the front line, 3-4 the middle, 5-6 the back.
• Put a [b]duplicate[/b] on the same unit to level it up (Lv2 at 3 copies, Lv3 at 6). Higher levels mean bigger squads and stronger units.
• Every unit has a unique [b]out-of-battle ability[/b] (when bought, sold, levelled, at start or end of turn...).
• [b]Trinkets[/b] come in 6 tiers and change how a squad fights, or give permanent boosts.
• The [b]shop tier rises every %d battles[/b], unlocking rarer units and stronger trinkets.
• After each shop phase you battle another player's army. Reach the win target to finish on top; run out of lives and you're out.""" % [DraftData.TURN_GOLD, DraftData.UNIT_COST, DraftData.TRINKET_COST, DraftData.REROLL_COST, DraftData.BOARD_SLOTS, DraftData.BATTLES_PER_TIER]
	lv.add_child(rules)

	lv.add_child(UIKit.label("Match settings (when hosting)", 16, UIKit.ACCENT))
	var g := GridContainer.new()
	g.columns = 4
	g.add_theme_constant_override("h_separation", 12)
	_wins = _spin(g, "Wins to win", 1, 30, 10)
	_lives = _spin(g, "Lives", 1, 20, 5)
	_max_players = _spin(g, "Max players", 2, 16, 8)
	_turn_time = _spin(g, "Turn time (s)", 20, 300, 75)
	lv.add_child(g)

	var brow := UIKit.hbox(8)
	brow.add_child(UIKit.button("Quick Match", func(): Party.quick_match(Profile.player_name(), _settings())))
	brow.add_child(UIKit.button("Host Match", func(): Party.host_match(Profile.player_name(), _settings())))
	brow.add_child(UIKit.button("Find Matches", func(): Party.start_search()))
	lv.add_child(brow)
	var jrow := UIKit.hbox(8)
	jrow.add_child(UIKit.label("Join by IP:", 14))
	_ip = LineEdit.new()
	_ip.text = "127.0.0.1"
	_ip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	jrow.add_child(_ip)
	jrow.add_child(UIKit.button("Join", func(): Party.join_match(_ip.text.strip_edges(), Party.PORT, Profile.player_name())))
	lv.add_child(jrow)
	_status = UIKit.label("Not in a match.", 13, UIKit.TEXT_DIM)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lv.add_child(_status)
	var note := UIKit.label("Find Matches searches your local network. For internet play the host forwards UDP port %d and shares their IP." % Party.PORT, 12, UIKit.TEXT_DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lv.add_child(note)
	lv.add_child(UIKit.label("Matches found", 16, UIKit.ACCENT))
	_found_box = UIKit.vbox(6)
	lv.add_child(_found_box)

	# --- right: lobby -------------------------------------------------------
	var right := UIKit.panel(UIKit.PANEL_LIGHT)
	right.custom_minimum_size = Vector2(420, 0)
	add_child(right)
	_lobby_box = UIKit.vbox(8)
	right.add_child(_lobby_box)

	Party.lobby_changed.connect(_refresh_lobby)
	Party.lobbies_found.connect(_show_found)
	Party.status.connect(func(t: String): _status.text = t)
	_refresh_lobby()
	_show_found([])


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


func _show_found(list: Array) -> void:
	UIKit.clear(_found_box)
	if list.is_empty():
		_found_box.add_child(UIKit.label("None yet. Press Find Matches, or host one.", 13, UIKit.TEXT_DIM))
		return
	for l in list:
		var h := UIKit.hbox(10)
		h.add_child(UIKit.label("%s's match" % l["name"], 15))
		h.add_child(UIKit.label("%d/%d players · %d wins · %d lives" % [int(l["players"]), int(l["max"]), int(l["wins"]), int(l["lives"])], 13, UIKit.TEXT_DIM))
		h.add_child(UIKit.spacer())
		var b := UIKit.button("Join", func(): Party.join_match(l["ip"], int(l["port"]), Profile.player_name()))
		b.disabled = int(l["players"]) >= int(l["max"])
		h.add_child(b)
		_found_box.add_child(h)


func _refresh_lobby() -> void:
	UIKit.clear(_lobby_box)
	if not Party.is_active() or Party.phase == "connecting":
		_lobby_box.add_child(UIKit.label("Lobby", 20, UIKit.ACCENT))
		_lobby_box.add_child(UIKit.label("Host, find or join a match to see the players here.", 14, UIKit.TEXT_DIM))
		return
	var s := Party.settings
	_lobby_box.add_child(UIKit.label("Lobby (%s)" % ("you are hosting" if Party.is_host() else "joined"), 20, UIKit.ACCENT))
	_lobby_box.add_child(UIKit.label("First to %d wins · %d lives · up to %d players · %ds turns" % [int(s["wins"]), int(s["lives"]), int(s["max_players"]), int(s["turn_time"])], 13, UIKit.TEXT_DIM))
	var ids: Array = Party.players.keys()
	ids.sort()
	for id in ids:
		var p: Dictionary = Party.players[id]
		var h := UIKit.hbox(8)
		var tag := "  (host)" if int(id) == 1 else ("  (you)" if int(id) == Party.my_id else "")
		h.add_child(UIKit.label(str(p["name"]) + tag, 15))
		h.add_child(UIKit.spacer())
		h.add_child(UIKit.label("Ready" if p["ready"] else "Not ready", 13, UIKit.GOOD if p["ready"] else UIKit.BAD))
		if Party.is_host() and int(id) != 1:
			var pid: int = id
			h.add_child(UIKit.button("Remove", func(): Party.remove_player(pid)))
		_lobby_box.add_child(h)
	var row := UIKit.hbox(8)
	if Party.is_host():
		var add := UIKit.button("Add Bot", func(): Party.add_bot())
		add.disabled = Party.players.size() >= int(s["max_players"])
		row.add_child(add)
		var start := UIKit.button("Start Match", func(): Party.start_match())
		start.disabled = not Party.can_start()
		start.tooltip_text = "Needs at least 2 players (bots count) and everyone ready."
		row.add_child(start)
	else:
		var is_ready := bool(Party.me().get("ready", false))
		_ready_btn = UIKit.button("Not ready" if is_ready else "Ready!", func(): Party.set_ready(not is_ready))
		row.add_child(_ready_btn)
	row.add_child(UIKit.button("Leave", func(): Party.leave(true)))
	_lobby_box.add_child(row)
