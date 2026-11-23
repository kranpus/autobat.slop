extends VBoxContainer
## The top ranked players on the server (signed-in accounts that have fought
## at least one ranked battle), plus your own place.

const REFRESH_AFTER_MS := 30000

var _status: Label
var _me: Label
var _table: VBoxContainer
var _scroll: ScrollUnroll
var _shown_key := ""
var _waiting := false
var _stale := false


func _ready() -> void:
	add_theme_constant_override("separation", 10)
	var top := UIKit.hbox(10)
	top.add_child(UIKit.label("Leaderboard", 22, UIKit.ACCENT))
	top.add_child(UIKit.spacer())
	top.add_child(UIKit.button("Refresh", refresh_now))
	add_child(top)
	_me = UIKit.label("", 15)
	_me.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_me)
	_status = UIKit.label("", 13, UIKit.TEXT_DIM)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	# The rankings are a hall-of-fame scroll.
	_scroll = ScrollUnroll.new()
	scroll.add_child(_scroll)
	_table = _scroll.content

	Party.leaderboard_received.connect(_show)
	# Signing in or out changes "your rank": fetch again (now, or when shown).
	Party.session_changed.connect(func():
		_stale = true
		_show(Party.last_leaderboard, {})
		if is_visible_in_tree():
			refresh_now())
	visibility_changed.connect(func():
		if is_visible_in_tree() and _needs_refresh():
			refresh_now())
	_show(Party.last_leaderboard, Party.last_leaderboard_me)


func _needs_refresh() -> bool:
	return _stale or Party.last_leaderboard_msec == 0 or Time.get_ticks_msec() - Party.last_leaderboard_msec > REFRESH_AFTER_MS


func refresh_now() -> void:
	_stale = false
	_waiting = true
	_status.text = "Fetching the leaderboard from %s..." % Party.server_address()
	Party.request_leaderboard()
	# Quiet check-ins give up silently when the server is unreachable.
	get_tree().create_timer(10.0).timeout.connect(func():
		if _waiting and is_instance_valid(_status):
			_waiting = false
			_status.text = "Couldn't reach the server at %s." % Party.server_address())


func _show(top: Array, me: Dictionary) -> void:
	_waiting = false
	if not is_inside_tree():
		return
	UIKit.clear(_table)
	var me_name := Profile.account if Profile.online else ""
	if Profile.online:
		if int(me.get("rank", 0)) > 0:
			_me.text = "You (%s) are #%d of %d with rating %d." % [me_name, int(me["rank"]), int(me["of"]), int(me["rating"])]
		else:
			_me.text = "Win or lose a ranked battle to get on the leaderboard."
	else:
		_me.text = "Sign in (Settings → Account) to appear on the leaderboard. Offline progress isn't ranked."
	if Party.last_leaderboard_msec == 0:
		_status.text = "Not loaded yet."
		return
	_status.text = "Top %d players by rating%s." % [top.size(), "" if top.size() > 0 else " (nobody has played a ranked battle yet)"]
	var title := ScrollUnroll.ink("Hall of Heroes", 26, FantasySkin.INK)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_table.add_child(title)
	if top.is_empty():
		var none := ScrollUnroll.ink("No names are written here yet. Fight a ranked battle to be the first.", 15, FantasySkin.INK_DIM)
		none.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_table.add_child(none)
	else:
		_table.add_child(_row(["", "Commander", "Rating", "Wins", "Losses", "Win rate"], FantasySkin.INK_DIM, false, 13))
		_table.add_child(ScrollUnroll.rule())
	for e in top:
		var rank := int(e["rank"])
		# Gold, silver and bronze ink for the top three.
		var color := FantasySkin.INK
		if rank == 1:
			color = Color("8a6410")
		elif rank == 2:
			color = Color("5b6068")
		elif rank == 3:
			color = Color("7e4a20")
		var w := int(e["wins"])
		var l := int(e["losses"])
		var you := me_name != "" and str(e["name"]).to_lower() == me_name.to_lower()
		var medal := "★" if rank <= 3 else ""
		_table.add_child(_row(["%s %d" % [medal, rank], str(e["name"]) + ("  (you)" if you else ""), str(int(e["rating"])), str(w), str(l),
			"%d%%" % roundi(100.0 * float(w) / maxf(1.0, float(w + l)))], FantasySkin.INK_GOOD if you else color, you, 19 if rank <= 3 else 16))
	# Unroll when the list changes (not on every quiet refresh).
	var key := JSON.stringify(top)
	if key != _shown_key:
		_shown_key = key
		_scroll.unroll(0.6)


func _row(cells: Array, color: Color, highlight: bool, size: int = 16) -> Control:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.3, 0.5, 0.2, 0.18) if highlight else Color(0, 0, 0, 0)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	p.add_theme_stylebox_override("panel", sb)
	var h := UIKit.hbox(8)
	p.add_child(h)
	var widths := [56, 0, 90, 70, 70, 90]
	for i in cells.size():
		var l := ScrollUnroll.ink(cells[i], size if i < 2 else mini(size, 16), color)
		if widths[i] > 0:
			l.custom_minimum_size = Vector2(widths[i], 0)
		else:
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			l.clip_text = true
		h.add_child(l)
	return p
