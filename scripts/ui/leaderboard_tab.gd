extends VBoxContainer
## The top ranked players on the server (signed-in accounts that have fought
## at least one ranked battle), plus your own place.

const REFRESH_AFTER_MS := 30000

var _status: Label
var _me: Label
var _table: VBoxContainer
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
	_table = UIKit.vbox(4)
	_table.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_table)

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
	if top.is_empty():
		return
	_table.add_child(_row(["#", "Player", "Rating", "Wins", "Losses", "Win rate"], UIKit.TEXT_DIM, false))
	for e in top:
		var rank := int(e["rank"])
		var color := Color.WHITE
		if rank == 1:
			color = Color("ffd76a")
		elif rank == 2:
			color = Color("d7dde6")
		elif rank == 3:
			color = Color("e0a06a")
		var w := int(e["wins"])
		var l := int(e["losses"])
		var you := me_name != "" and str(e["name"]).to_lower() == me_name.to_lower()
		_table.add_child(_row([str(rank), str(e["name"]) + ("  (you)" if you else ""), str(int(e["rating"])), str(w), str(l),
			"%d%%" % roundi(100.0 * float(w) / maxf(1.0, float(w + l)))], UIKit.GOOD if you else color, you))


func _row(cells: Array, color: Color, highlight: bool) -> Control:
	var p := UIKit.panel(Color("2f3f2f") if highlight else UIKit.PANEL_LIGHT)
	var h := UIKit.hbox(8)
	p.add_child(h)
	var widths := [50, 0, 90, 70, 70, 90]
	for i in cells.size():
		var l := UIKit.label(cells[i], 15, color)
		if widths[i] > 0:
			l.custom_minimum_size = Vector2(widths[i], 0)
		else:
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			l.clip_text = true
		h.add_child(l)
	return p
