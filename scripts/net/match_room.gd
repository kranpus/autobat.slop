class_name MatchRoom
extends RefCounted
## One Legion Draft match, run by whoever is authoritative: the dedicated
## server (many rooms) or a player hosting on their LAN (one room).
##
## The room owns every player's DraftRun. Clients only send actions
## ("buy_unit", "sell", ...); the room replays them on its own copy with the
## same rules and RNG, so the boards that fight are always legitimate.
## Outgoing messages go through the `outbox` signal; Party delivers them.

signal outbox(peer_id: int, method: String, args: Array)
signal room_log(text: String)

const READY_TIMEOUT_MS := 200000
const AUTO_START_MS := 30000          # quick-match rooms start this long after 2+ players join
const SOLO_START_MS := 60000          # ...or this long with a single player (bots fill in)
const BOT_NAMES := ["Grimtooth", "Lady Ash", "Old Borin", "Vex", "Captain Rook", "Mira", "Hexa", "Tusk", "Sable", "Kael", "Nyx", "Brother Fen", "Ironjaw", "Wren"]

var code := ""
var public := true
var quick := false                    # created by Quick Match: auto-starts, fills with bots
var settings := {}
## Gold paid out at the end of the match; shared with (and editable from) the server.
var rewards := {"draft_mult": 1.0, "draft_table": [400, 250, 150, 60]}
var players := {}                     # id -> {name, bot, ready, lives, wins, done, place}
var owner_id := 0
var phase := "lobby"                  # lobby, shop, sim, viewing, over
var round_num := 0
var created_msec := 0
var over_msec := 0

var _runs := {}                       # id -> DraftRun (authoritative)
var _submitted := {}
var _last_boards := {}
var _shop_ready := {}
var _deadline := 0
var _auto_start_at := 0
var _sims: Array = []
var _next_bot := -1
var _next_top := 1
var _next_bottom := 0
var _rng := RandomNumberGenerator.new()


func _init(room_code: String, room_settings: Dictionary, is_public: bool, is_quick: bool) -> void:
	code = room_code
	public = is_public
	quick = is_quick
	settings = clean_settings(room_settings)
	created_msec = Time.get_ticks_msec()
	_rng.randomize()


## use_lives / use_wins / use_timer can switch those rules off. Without
## lives the match ends after max_rounds (ranked by wins, then fewest losses).
static func clean_settings(s: Dictionary) -> Dictionary:
	return {
		"wins": clampi(int(s.get("wins", 10)), 1, 30),
		"lives": clampi(int(s.get("lives", 5)), 1, 20),
		"max_players": clampi(int(s.get("max_players", 8)), 2, 16),
		"turn_time": clampi(int(s.get("turn_time", 75)), 20, 300),
		"slots": DraftData.valid_slots(int(s.get("slots", DraftData.BOARD_SLOTS))),
		"use_lives": bool(s.get("use_lives", true)),
		"use_wins": bool(s.get("use_wins", true)),
		"use_timer": bool(s.get("use_timer", true)),
		"max_rounds": clampi(int(s.get("max_rounds", 15)), 1, 100),
	}


func _send(id: int, method: String, args: Array) -> void:
	if players.has(id) and not players[id]["bot"]:
		outbox.emit(id, method, args)


func _send_all(method: String, args: Array) -> void:
	for id in players:
		_send(id, method, args)


func human_count() -> int:
	var n := 0
	for id in players:
		if not players[id]["bot"]:
			n += 1
	return n


func is_full() -> bool:
	return players.size() >= int(settings["max_players"])


func is_empty_of_humans() -> bool:
	return human_count() == 0


## Public listing entry for the server browser.
func info() -> Dictionary:
	var host_name := ""
	if players.has(owner_id):
		host_name = str(players[owner_id]["name"])
	return {"code": code, "name": host_name, "players": players.size(), "max": settings["max_players"],
		"settings": settings, "quick": quick}


func lobby_state() -> Dictionary:
	return {"code": code, "public": public, "quick": quick, "settings": settings, "players": players,
		"owner": owner_id, "phase": phase,
		"auto_start_in": maxi(0, _auto_start_at - Time.get_ticks_msec()) if _auto_start_at > 0 else -1}


func _broadcast_lobby() -> void:
	_send_all("lobby", [lobby_state()])


# --- lobby ------------------------------------------------------------------

## Returns "" on success or a reason the player can't join.
func add_player(id: int, player_name: String) -> String:
	if phase != "lobby":
		return "That match has already started."
	if is_full():
		return "That match is full."
	var nm := player_name.strip_edges().left(24)
	if nm == "":
		nm = "Commander"
	players[id] = _new_player(nm, false)
	if owner_id == 0 or not players.has(owner_id):
		owner_id = id
	room_log.emit("%s joined room %s" % [nm, code])
	_update_auto_start()
	_broadcast_lobby()
	if quick and is_full():
		start(owner_id)
	return ""


func remove_player(id: int) -> void:
	if not players.has(id):
		return
	if phase == "lobby" or phase == "over":
		players.erase(id)
		if id == owner_id:
			owner_id = 0
			for other in players:
				if not players[other]["bot"]:
					owner_id = other
					break
		_update_auto_start()
		_broadcast_lobby()
		return
	# Mid-match: a bot takes over so the match can continue.
	var p: Dictionary = players[id]
	p["bot"] = true
	p["name"] = str(p["name"]) + " (bot)"
	if phase == "shop" and not p["done"] and not _submitted.has(id):
		_end_turn_for(id)
	_send_all("standings", [players])
	room_log.emit("%s left room %s; a bot took over" % [p["name"], code])


func _new_player(player_name: String, bot: bool) -> Dictionary:
	return {"name": player_name, "bot": bot, "ready": bot, "lives": 0, "wins": 0, "losses": 0, "done": false, "place": 0}


func set_ready(id: int, is_ready: bool) -> void:
	if phase == "lobby" and players.has(id):
		players[id]["ready"] = is_ready
		_broadcast_lobby()


func add_bot(by_id: int) -> void:
	if by_id != owner_id or phase != "lobby" or is_full():
		return
	_add_bot()
	_broadcast_lobby()


func _add_bot() -> void:
	var id := _next_bot
	_next_bot -= 1
	players[id] = _new_player("%s (bot)" % BOT_NAMES[(-id - 1) % BOT_NAMES.size()], true)


func kick(by_id: int, target: int) -> void:
	if by_id != owner_id or phase != "lobby" or target == owner_id or not players.has(target):
		return
	_send(target, "kicked", ["The host removed you from the match."])
	players.erase(target)
	_update_auto_start()
	_broadcast_lobby()


func can_start() -> bool:
	if phase != "lobby" or players.size() < 2:
		return false
	for id in players:
		if id != owner_id and not players[id]["ready"]:
			return false
	return true


## Quick-match rooms start on their own: 30 s after a second player joins,
## or after 60 s with a lone player (empty seats are filled with bots).
func _update_auto_start() -> void:
	if not quick or phase != "lobby" or human_count() == 0:
		_auto_start_at = 0
		return
	var now := Time.get_ticks_msec()
	var wait := AUTO_START_MS if human_count() >= 2 else SOLO_START_MS
	if _auto_start_at == 0:
		_auto_start_at = now + wait
	else:
		_auto_start_at = mini(_auto_start_at, now + wait)


# --- match flow -------------------------------------------------------------

func start(by_id: int) -> void:
	if by_id != owner_id and by_id != 0:
		return
	if quick:
		# Quick-match rooms fill empty seats with bots up to 4 players.
		while players.size() < mini(4, int(settings["max_players"])):
			_add_bot()
		for id in players:
			players[id]["ready"] = true
	if not can_start():
		return
	phase = "shop"
	_next_top = 1
	_next_bottom = players.size()
	_runs.clear()
	for id in players:
		var p: Dictionary = players[id]
		p["lives"] = int(settings["lives"]) if settings["use_lives"] else 0
		p["wins"] = 0
		p["losses"] = 0
		p["done"] = false
		p["place"] = 0
		var r := DraftRun.new(_rng.randi() | 1, int(settings["slots"]))
		r.lives = int(p["lives"])
		_runs[id] = r
	room_log.emit("Room %s started with %d players" % [code, players.size()])
	_send_all("match_start", [settings, players])
	_begin_shop()


func _active_ids() -> Array:
	var out: Array = []
	for id in players:
		if not players[id]["done"]:
			out.append(id)
	out.sort()
	return out


func _begin_shop() -> void:
	round_num += 1
	_submitted.clear()
	_shop_ready.clear()
	_deadline = Time.get_ticks_msec() + int(settings["turn_time"]) * 1000 if settings["use_timer"] else 0
	phase = "shop"
	var locked := UnitLocks.as_dict()
	for id in _active_ids():
		var r: DraftRun = _runs[id]
		r.excluded = locked   # server's current locks apply from this shop on
		r.begin_turn()
		if players[id]["bot"]:
			r.auto_play()
			_end_turn_for(id)
	for id in players:
		var p: Dictionary = players[id]
		if p["bot"]:
			continue
		var state: Dictionary = (_runs[id] as DraftRun).to_dict() if not p["done"] else {}
		_send(id, "shop", [round_num, int(settings["turn_time"]) if settings["use_timer"] else 0, state])


## A player's shop action, replayed on the authoritative run.
func action(id: int, r: int, act: Array) -> void:
	if phase != "shop" or r != round_num or not _runs.has(id) or _submitted.has(id) or players[id]["done"]:
		return
	(_runs[id] as DraftRun).apply_action(act)


func submit(id: int, r: int) -> void:
	if phase == "shop" and r == round_num and _runs.has(id) and not _submitted.has(id) and not players[id]["done"]:
		_end_turn_for(id)


func _end_turn_for(id: int) -> void:
	_submitted[id] = (_runs[id] as DraftRun).end_turn()


func shop_ready(id: int, r: int) -> void:
	if r == round_num:
		_shop_ready[id] = true


## Called every frame by Party.
func process() -> void:
	var now := Time.get_ticks_msec()
	match phase:
		"lobby":
			if _auto_start_at > 0 and now >= _auto_start_at:
				_auto_start_at = 0
				start(0)
		"shop":
			var waiting := false
			for id in _active_ids():
				if not _submitted.has(id):
					waiting = true
					break
			if not waiting:
				_start_battles()
			elif _deadline > 0 and now >= _deadline:
				for id in _active_ids():
					if not _submitted.has(id):
						_end_turn_for(id)
						_send(id, "force_end", [round_num])
				_start_battles()
		"sim":
			for s in _sims:
				if not WorkerThreadPool.is_task_completed(int(s["task"])):
					return
			for s in _sims:
				WorkerThreadPool.wait_for_task_completion(int(s["task"]))
			_finish_battles()
		"viewing":
			var all_ready := true
			for id in _active_ids():
				if not players[id]["bot"] and not _shop_ready.get(id, false):
					all_ready = false
					break
			if all_ready or now >= _deadline:
				_begin_shop()


func _start_battles() -> void:
	var active := _active_ids()
	for id in active:
		_last_boards[id] = _submitted.get(id, (_runs[id] as DraftRun).board.duplicate(true))
	for i in range(active.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp = active[i]
		active[i] = active[j]
		active[j] = tmp
	_sims.clear()
	var k := 0
	while k < active.size():
		var a: int = active[k]
		if k + 1 < active.size():
			_queue_battle(a, active[k + 1], false)
		else:
			var others: Array = []
			for id in _last_boards:
				if id != a and players.has(id) and not DraftData.board_is_empty(_last_boards[id]):
					others.append(id)
			var ghost: int = others[_rng.randi_range(0, others.size() - 1)] if not others.is_empty() else a
			_queue_battle(a, ghost, true)
		k += 2
	phase = "sim"


func _queue_battle(a: int, b: int, ghost: bool) -> void:
	var sq_a := DraftData.board_to_squads(_last_boards[a])
	var sq_b := DraftData.board_to_squads(_last_boards.get(b, []))
	var seed_value := _rng.randi()
	var map := BattleMaps.random_map_id(_rng)
	var sim := BattleSim.new()
	sim.setup(sq_a, sq_b, seed_value, map)
	var task := WorkerThreadPool.add_task(sim.run_to_end.bind(200000), false, "draft battle")
	_sims.append({"task": task, "sim": sim, "a": a, "b": b, "ghost": ghost})
	var cfg := {
		"mode": "draft", "round": round_num, "seed": seed_value, "map": map, "use_lives": settings["use_lives"],
		"squads_a": sq_a, "squads_b": sq_b,
		"name_a": players[a]["name"], "name_b": str(players[b]["name"]) + (" (copy)" if ghost else ""),
	}
	var ca := cfg.duplicate()
	ca["local_team"] = 0
	_send(a, "battle", [ca])
	if not ghost:
		var cb := cfg.duplicate()
		cb["local_team"] = 1
		_send(b, "battle", [cb])


func _finish_battles() -> void:
	var outcome := {}
	for s in _sims:
		var sim: BattleSim = s["sim"]
		var w := sim.winner
		outcome[s["a"]] = 1.0 if w == 0 else (0.0 if w == 1 else 0.5)
		if not s["ghost"]:
			outcome[s["b"]] = 1.0 if w == 1 else (0.0 if w == 0 else 0.5)
	_sims.clear()
	var winners: Array = []
	var losers: Array = []
	for id in outcome:
		var p: Dictionary = players[id]
		if outcome[id] >= 1.0:
			p["wins"] = int(p["wins"]) + 1
		elif outcome[id] <= 0.0:
			p["losses"] = int(p["losses"]) + 1
			if settings["use_lives"]:
				p["lives"] = int(p["lives"]) - 1
		(_runs[id] as DraftRun).apply_battle_result(outcome[id], int(p["lives"]), int(p["wins"]))
		if settings["use_wins"] and int(p["wins"]) >= int(settings["wins"]):
			winners.append(id)
		elif settings["use_lives"] and int(p["lives"]) <= 0:
			losers.append(id)
	winners.sort_custom(func(x, y): return int(players[x]["lives"]) > int(players[y]["lives"]))
	for id in winners:
		players[id]["done"] = true
		players[id]["place"] = _next_top
		_next_top += 1
	losers.sort_custom(func(x, y): return int(players[x]["wins"]) < int(players[y]["wins"]))
	for id in losers:
		players[id]["done"] = true
		players[id]["place"] = _next_bottom
		_next_bottom -= 1
	var active := _active_ids()
	if not settings["use_lives"] and round_num >= int(settings["max_rounds"]):
		# Round limit reached: rank everyone still playing by wins, then fewest losses.
		active.sort_custom(func(x, y):
			if int(players[x]["wins"]) != int(players[y]["wins"]):
				return int(players[x]["wins"]) > int(players[y]["wins"])
			return int(players[x]["losses"]) < int(players[y]["losses"]))
		for id in active:
			players[id]["done"] = true
			players[id]["place"] = _next_top
			_next_top += 1
	elif active.size() == 1:
		players[active[0]]["done"] = true
		players[active[0]]["place"] = _next_top
		_next_top += 1
	for id in outcome:
		var p: Dictionary = players[id]
		_send(id, "results", [{"round": round_num, "outcome": outcome[id], "lives": p["lives"], "wins": p["wins"], "losses": p["losses"], "done": p["done"], "place": p["place"]}, players])
	_send_all("standings", [players])
	if _active_ids().is_empty():
		_end_match()
		return
	phase = "viewing"
	_deadline = Time.get_ticks_msec() + READY_TIMEOUT_MS


func _end_match() -> void:
	phase = "over"
	over_msec = Time.get_ticks_msec()
	var list: Array = []
	var table: Array = rewards.get("draft_table", [400, 250, 150, 60])
	var top_half := maxi(1, ceili(float(players.size()) / 2.0))
	for id in players:
		var p: Dictionary = players[id]
		var place := int(p["place"])
		var base := int(table[clampi(place - 1, 0, table.size() - 1)]) if not table.is_empty() else 0
		list.append({"id": id, "name": p["name"], "place": place, "wins": p["wins"], "lives": p["lives"], "losses": p["losses"], "bot": p["bot"],
			"gold": maxi(0, roundi(float(base) * float(rewards.get("draft_mult", 1.0)))), "maps": 1 if place <= top_half else 0})
	list.sort_custom(func(x, y): return int(x["place"]) < int(y["place"]))
	room_log.emit("Room %s finished; winner %s" % [code, list[0]["name"] if not list.is_empty() else "-"])
	_send_all("over", [list])
