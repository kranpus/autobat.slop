extends Node
## Autoload "Party": multiplayer lobbies and matches for Legion Draft.
##
## One player hosts (ENet server); others find the lobby on the LAN (UDP
## broadcast beacons) or join by IP. The host is authoritative: it collects
## every player's board after each shop phase, pairs players, decides each
## battle by running the deterministic BattleSim on worker threads, and
## tracks lives/wins/placements. Each player watches a replay of their own
## battle locally (same seed + boards = same fight).
##
## This node uses its own SceneMultiplayer so it never interferes with the
## 1v1 duel networking in Net.

signal lobby_changed
signal lobbies_found(list: Array)
signal status(text: String)
signal match_started
signal shop_started(round_num: int, seconds: int)
signal battle_ready(config: Dictionary)
signal standings_changed
signal match_over(placements: Array)
signal left_match(reason: String)

const PORT := 24700
const DISCOVERY_PORT := 24701
const GAME_TAG := "autobat_draft_v1"
const READY_TIMEOUT_MS := 200000     # max wait for players to finish watching battles
const FORCE_GRACE_MS := 4000         # wait for late boards after the turn timer
const BOT_NAMES := ["Grimtooth", "Lady Ash", "Old Borin", "Vex", "Captain Rook", "Mira", "Hexa", "Tusk", "Sable", "Kael", "Nyx", "Brother Fen"]

enum Role { NONE, HOST, CLIENT }

var role := Role.NONE
var mp := SceneMultiplayer.new()
var settings := {"wins": 10, "lives": 5, "max_players": 8, "turn_time": 75}
var players := {}            # id -> {name, bot, ready, lives, wins, done, place}
var my_id := 0
var host_name := ""

# Local player state (host and clients).
var phase := "idle"          # idle, connecting, lobby, shop, waiting, battle, results, over
var round_num := 0
var run: DraftRun = null
var turn_deadline_msec := 0
var placements: Array = []
var last_outcome := -1.0     # outcome of this player's latest battle per the host
var _submitted := false
var _pending_results := {}   # results for my last battle, applied when received

# Host-only match state.
var _host_phase := ""        # lobby, shop, sim, viewing, over
var _boards := {}
var _last_boards := {}
var _bot_runs := {}
var _shop_ready := {}
var _deadline := 0
var _forced := false
var _grace := 0
var _sims: Array = []        # [{task, sim, a, b, ghost}]
var _next_bot := 100000
var _next_top := 1
var _next_bottom := 0
var _rng := RandomNumberGenerator.new()
var _beacon: PacketPeerUDP
var _beacon_t := 0.0

# Discovery.
var _listener: PacketPeerUDP
var _found := {}
var _found_t := 0.0
var _quick_deadline := 0
var _quick_name := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().set_multiplayer(mp, get_path())
	mp.peer_connected.connect(_on_peer_connected)
	mp.peer_disconnected.connect(_on_peer_disconnected)
	mp.connected_to_server.connect(_on_connected)
	mp.connection_failed.connect(func(): _leave_with("Could not connect to that match."))
	mp.server_disconnected.connect(func(): _leave_with("The host closed the match."))


func is_in_lobby() -> bool:
	return role != Role.NONE and phase == "lobby"


func is_in_match() -> bool:
	return role != Role.NONE and phase not in ["idle", "connecting", "lobby"]


func is_active() -> bool:
	return role != Role.NONE


func is_host() -> bool:
	return role == Role.HOST


func me() -> Dictionary:
	return players.get(my_id, {})


# --- hosting / joining ------------------------------------------------------

func host_match(player_name: String, new_settings: Dictionary) -> Error:
	leave(true)
	settings = {
		"wins": clampi(int(new_settings.get("wins", 10)), 1, 30),
		"lives": clampi(int(new_settings.get("lives", 5)), 1, 20),
		"max_players": clampi(int(new_settings.get("max_players", 8)), 2, 16),
		"turn_time": clampi(int(new_settings.get("turn_time", 75)), 20, 300),
	}
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, int(settings["max_players"]) - 1)
	if err != OK:
		status.emit("Could not host on port %d (is another match running?)." % PORT)
		return err
	mp.multiplayer_peer = peer
	role = Role.HOST
	my_id = 1
	host_name = player_name
	players = {1: _new_player(player_name, false)}
	players[1]["ready"] = true
	phase = "lobby"
	_host_phase = "lobby"
	_beacon = PacketPeerUDP.new()
	_beacon.set_broadcast_enabled(true)
	_beacon.set_dest_address("255.255.255.255", DISCOVERY_PORT)
	status.emit("Hosting a match on port %d. Players on your network can find it; others join with your IP." % PORT)
	lobby_changed.emit()
	return OK


func join_match(address: String, port: int, player_name: String) -> Error:
	leave(true)
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		status.emit("Could not connect (error %d)." % err)
		return err
	mp.multiplayer_peer = peer
	role = Role.CLIENT
	host_name = player_name
	phase = "connecting"
	status.emit("Connecting to %s:%d..." % [address, port])
	return OK


## Look on the LAN for a lobby with space; join it, otherwise host one.
func quick_match(player_name: String, new_settings: Dictionary) -> void:
	_quick_name = player_name
	settings = new_settings.duplicate()
	start_search()
	_quick_deadline = Time.get_ticks_msec() + 2500
	status.emit("Looking for an open match...")


func leave(silent: bool = false) -> void:
	stop_search()
	_quick_deadline = 0
	if mp.multiplayer_peer != null and not (mp.multiplayer_peer is OfflineMultiplayerPeer):
		mp.multiplayer_peer.close()
	mp.multiplayer_peer = OfflineMultiplayerPeer.new()
	if _beacon:
		_beacon.close()
		_beacon = null
	var was_active := role != Role.NONE
	role = Role.NONE
	phase = "idle"
	players = {}
	run = null
	_sims.clear()
	_bot_runs.clear()
	round_num = 0
	if was_active and not silent:
		left_match.emit("You left the match.")
	lobby_changed.emit()


func _leave_with(reason: String) -> void:
	var was := role != Role.NONE
	leave(true)
	status.emit(reason)
	if was:
		left_match.emit(reason)


func _on_connected() -> void:
	my_id = mp.get_unique_id()
	_rq_hello.rpc_id(1, host_name)


func _on_peer_connected(_id: int) -> void:
	pass  # clients introduce themselves with _rq_hello


func _on_peer_disconnected(id: int) -> void:
	if role != Role.HOST or not players.has(id):
		return
	if _host_phase == "lobby":
		players.erase(id)
		_broadcast_lobby()
		return
	# Mid-match: a bot takes over their army so the match can continue.
	var p: Dictionary = players[id]
	p["bot"] = true
	p["name"] = str(p["name"]) + " (bot)"
	var r := DraftRun.new(_rng.randi())
	r.board = DraftData.sanitize_board(_last_boards.get(id, []))
	r.battles_played = maxi(0, round_num - 1)
	r.lives = int(p["lives"])
	r.wins = int(p["wins"])
	_bot_runs[id] = r
	_shop_ready[id] = true
	if _host_phase == "shop" and not p["done"]:
		r.begin_turn()
		r.auto_play()
		_boards[id] = r.end_turn()
	_broadcast_standings()
	status.emit("%s disconnected and was replaced by a bot." % p["name"])


func _new_player(player_name: String, bot: bool) -> Dictionary:
	return {"name": player_name.strip_edges().left(24), "bot": bot, "ready": bot, "lives": 0, "wins": 0, "done": false, "place": 0}


# --- lobby (host) -----------------------------------------------------------

@rpc("any_peer", "reliable")
func _rq_hello(player_name: String) -> void:
	if role != Role.HOST:
		return
	var id := mp.get_remote_sender_id()
	if _host_phase != "lobby":
		_rc_reject.rpc_id(id, "That match has already started.")
		return
	if players.size() >= int(settings["max_players"]):
		_rc_reject.rpc_id(id, "That match is full.")
		return
	var nm := player_name.strip_edges().left(24)
	if nm == "":
		nm = "Commander"
	players[id] = _new_player(nm, false)
	status.emit("%s joined." % nm)
	_broadcast_lobby()


@rpc("any_peer", "reliable")
func _rq_ready(is_ready: bool) -> void:
	var id := mp.get_remote_sender_id()
	if role == Role.HOST and players.has(id) and _host_phase == "lobby":
		players[id]["ready"] = is_ready
		_broadcast_lobby()


func set_ready(is_ready: bool) -> void:
	if role == Role.CLIENT:
		_rq_ready.rpc_id(1, is_ready)


func add_bot() -> void:
	if role != Role.HOST or _host_phase != "lobby" or players.size() >= int(settings["max_players"]):
		return
	var id := _next_bot
	_next_bot += 1
	players[id] = _new_player("%s (bot)" % BOT_NAMES[(id - 100000) % BOT_NAMES.size()], true)
	_broadcast_lobby()


func remove_player(id: int) -> void:
	if role != Role.HOST or _host_phase != "lobby" or id == 1 or not players.has(id):
		return
	if not players[id]["bot"]:
		_rc_reject.rpc_id(id, "The host removed you from the lobby.")
	players.erase(id)
	_broadcast_lobby()


func can_start() -> bool:
	if role != Role.HOST or _host_phase != "lobby" or players.size() < 2:
		return false
	for id in players:
		if not players[id]["ready"]:
			return false
	return true


func _lobby_state() -> Dictionary:
	return {"settings": settings, "players": players, "host": players.get(1, {}).get("name", "")}


func _broadcast_lobby() -> void:
	_rc_lobby.rpc(_lobby_state())
	lobby_changed.emit()


@rpc("authority", "reliable")
func _rc_lobby(state: Dictionary) -> void:
	settings = state.get("settings", settings)
	players = state.get("players", {})
	if phase == "connecting":
		phase = "lobby"
		status.emit("Joined %s's match." % state.get("host", "the"))
	lobby_changed.emit()


@rpc("authority", "reliable")
func _rc_reject(reason: String) -> void:
	_leave_with(reason)


# --- discovery --------------------------------------------------------------

func start_search() -> void:
	stop_search()
	_found.clear()
	_listener = PacketPeerUDP.new()
	var err := _listener.bind(DISCOVERY_PORT)
	if err != OK:
		status.emit("Can't listen for local matches (port %d busy). You can still join by IP." % DISCOVERY_PORT)
		_listener = null
		return
	status.emit("Searching your network for matches...")


func stop_search() -> void:
	if _listener:
		_listener.close()
		_listener = null


func found_lobbies() -> Array:
	var out: Array = []
	var now := Time.get_ticks_msec()
	for k in _found:
		if now - int(_found[k]["seen"]) < 4000:
			out.append(_found[k])
	return out


func _poll_discovery(delta: float) -> void:
	if _listener == null:
		return
	while _listener.get_available_packet_count() > 0:
		var pkt := _listener.get_packet()
		var ip := _listener.get_packet_ip()
		var info = JSON.parse_string(pkt.get_string_from_utf8())
		if typeof(info) != TYPE_DICTIONARY or info.get("tag", "") != GAME_TAG:
			continue
		var key := "%s:%d" % [ip, int(info.get("port", PORT))]
		_found[key] = {"ip": ip, "port": int(info.get("port", PORT)), "name": str(info.get("name", "?")).left(24),
			"players": int(info.get("players", 0)), "max": int(info.get("max", 8)),
			"wins": int(info.get("wins", 10)), "lives": int(info.get("lives", 5)), "seen": Time.get_ticks_msec()}
	_found_t += delta
	if _found_t >= 0.5:
		_found_t = 0.0
		lobbies_found.emit(found_lobbies())


func _send_beacon(delta: float) -> void:
	if _beacon == null or _host_phase != "lobby":
		return
	_beacon_t += delta
	if _beacon_t < 1.0:
		return
	_beacon_t = 0.0
	var info := {"tag": GAME_TAG, "name": host_name, "port": PORT, "players": players.size(),
		"max": settings["max_players"], "wins": settings["wins"], "lives": settings["lives"]}
	_beacon.put_packet(JSON.stringify(info).to_utf8_buffer())


# --- match flow (host) ------------------------------------------------------

func start_match() -> void:
	if not can_start():
		return
	_rng.randomize()
	_host_phase = "shop"
	_next_top = 1
	_next_bottom = players.size()
	_last_boards.clear()
	_bot_runs.clear()
	for id in players:
		var p: Dictionary = players[id]
		p["lives"] = int(settings["lives"])
		p["wins"] = 0
		p["done"] = false
		p["place"] = 0
		if p["bot"]:
			var r := DraftRun.new(_rng.randi())
			r.lives = int(settings["lives"])
			_bot_runs[id] = r
	round_num = 0
	_rc_match_start.rpc(settings, players)
	_on_match_start(settings, players)
	_begin_shop()


@rpc("authority", "reliable")
func _rc_match_start(new_settings: Dictionary, new_players: Dictionary) -> void:
	_on_match_start(new_settings, new_players)


func _on_match_start(new_settings: Dictionary, new_players: Dictionary) -> void:
	stop_search()
	settings = new_settings
	players = new_players
	run = DraftRun.new()
	run.lives = int(settings["lives"])
	placements = []
	phase = "waiting"
	match_started.emit()


func _begin_shop() -> void:
	round_num += 1
	_boards.clear()
	_shop_ready.clear()
	_forced = false
	for id in _bot_runs:
		if players.has(id) and not players[id]["done"]:
			var r: DraftRun = _bot_runs[id]
			r.begin_turn()
			r.auto_play()
			_boards[id] = r.end_turn()
	_deadline = Time.get_ticks_msec() + int(settings["turn_time"]) * 1000
	_host_phase = "shop"
	_rc_shop.rpc(round_num, int(settings["turn_time"]))
	_on_shop(round_num, int(settings["turn_time"]))


@rpc("authority", "reliable")
func _rc_shop(r: int, seconds: int) -> void:
	_on_shop(r, seconds)


func _on_shop(r: int, seconds: int) -> void:
	round_num = r
	turn_deadline_msec = Time.get_ticks_msec() + seconds * 1000
	_submitted = false
	last_outcome = -1.0
	if bool(me().get("done", false)):
		phase = "waiting"
		standings_changed.emit()
		return
	phase = "shop"
	run.begin_turn()
	shop_started.emit(r, seconds)


## Local player ends their shop turn.
func submit_turn() -> void:
	if phase != "shop" or _submitted or run == null:
		return
	_submitted = true
	var board := run.end_turn()
	phase = "waiting"
	status.emit("Turn submitted. Waiting for other players...")
	if role == Role.HOST:
		_receive_board(1, board)
	else:
		_rq_submit.rpc_id(1, round_num, board)
	standings_changed.emit()


@rpc("authority", "reliable")
func _rc_force_end(r: int) -> void:
	if r == round_num:
		submit_turn()


@rpc("any_peer", "reliable")
func _rq_submit(r: int, board: Array) -> void:
	if role != Role.HOST or r != round_num:
		return
	_receive_board(mp.get_remote_sender_id(), board)


func _receive_board(id: int, board: Array) -> void:
	if not players.has(id) or _host_phase != "shop":
		return
	_boards[id] = DraftData.sanitize_board(board)


func _active_ids() -> Array:
	var out: Array = []
	for id in players:
		if not players[id]["done"]:
			out.append(id)
	out.sort()
	return out


func _host_process() -> void:
	var now := Time.get_ticks_msec()
	match _host_phase:
		"shop":
			var waiting := false
			for id in _active_ids():
				if not _boards.has(id):
					waiting = true
					break
			if not waiting:
				_start_battles()
			elif not _forced and now >= _deadline:
				_forced = true
				_grace = now + FORCE_GRACE_MS
				_rc_force_end.rpc(round_num)
				_rc_force_end(round_num)
			elif _forced and now >= _grace:
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


## Pair players, send each their battle, and simulate all battles on threads.
func _start_battles() -> void:
	var active := _active_ids()
	for id in active:
		if not _boards.has(id):
			_boards[id] = DraftData.sanitize_board(_last_boards.get(id, []))
		_last_boards[id] = _boards[id]
	# Fisher-Yates shuffle with the match RNG.
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
			_queue_battle(a, active[k + 1], _boards[a], _boards[active[k + 1]], false)
		else:
			# Odd player out fights a copy of another player's army.
			var others: Array = []
			for id in _last_boards:
				if id != a and not DraftData.board_is_empty(_last_boards[id]):
					others.append(id)
			var ghost: int = others[_rng.randi_range(0, others.size() - 1)] if not others.is_empty() else a
			_queue_battle(a, ghost, _boards[a], _last_boards.get(ghost, []), true)
		k += 2
	_host_phase = "sim"


func _queue_battle(a: int, b: int, board_a: Array, board_b: Array, ghost: bool) -> void:
	var sq_a := DraftData.board_to_squads(board_a)
	var sq_b := DraftData.board_to_squads(DraftData.sanitize_board(board_b))
	var seed_value := _rng.randi()
	var map := BattleMaps.random_map_id(_rng)
	var sim := BattleSim.new()
	sim.setup(sq_a, sq_b, seed_value, map)
	var task := WorkerThreadPool.add_task(sim.run_to_end.bind(200000), true, "draft battle")
	_sims.append({"task": task, "sim": sim, "a": a, "b": b, "ghost": ghost})
	var name_b: String = str(players[b]["name"]) + (" (copy)" if ghost else "")
	var cfg := {
		"mode": "draft", "round": round_num, "seed": seed_value, "map": map,
		"squads_a": sq_a, "squads_b": sq_b,
		"name_a": players[a]["name"], "name_b": name_b,
	}
	_send_battle(a, cfg, 0)
	if not ghost:
		_send_battle(b, cfg, 1)


func _send_battle(id: int, cfg: Dictionary, team: int) -> void:
	if players[id]["bot"]:
		return
	var c := cfg.duplicate()
	c["local_team"] = team
	if id == 1:
		_on_battle(c)
	else:
		_rc_battle.rpc_id(id, c)


@rpc("authority", "reliable")
func _rc_battle(cfg: Dictionary) -> void:
	_on_battle(cfg)


func _on_battle(cfg: Dictionary) -> void:
	phase = "battle"
	_pending_results = {}
	battle_ready.emit(cfg)


func _finish_battles() -> void:
	var outcome := {}
	for s in _sims:
		var sim: BattleSim = s["sim"]
		var a: int = s["a"]
		var b: int = s["b"]
		var w := sim.winner
		outcome[a] = 1.0 if w == 0 else (0.0 if w == 1 else 0.5)
		if not s["ghost"]:
			outcome[b] = 1.0 if w == 1 else (0.0 if w == 0 else 0.5)
	_sims.clear()
	var winners: Array = []
	var losers: Array = []
	for id in outcome:
		var p: Dictionary = players[id]
		if outcome[id] >= 1.0:
			p["wins"] = int(p["wins"]) + 1
		elif outcome[id] <= 0.0:
			p["lives"] = int(p["lives"]) - 1
		if int(p["wins"]) >= int(settings["wins"]):
			winners.append(id)
		elif int(p["lives"]) <= 0:
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
	if active.size() == 1:
		players[active[0]]["done"] = true
		players[active[0]]["place"] = _next_top
		_next_top += 1
	# Bots learn their results; humans get theirs over the network.
	for id in outcome:
		var p: Dictionary = players[id]
		if p["bot"] and _bot_runs.has(id):
			(_bot_runs[id] as DraftRun).apply_battle_result(outcome[id], int(p["lives"]), int(p["wins"]))
		elif not p["bot"]:
			var res := {"round": round_num, "outcome": outcome[id], "lives": p["lives"], "wins": p["wins"], "done": p["done"], "place": p["place"]}
			if id == 1:
				_on_results(res, players)
			else:
				_rc_results.rpc_id(id, res, players)
	_broadcast_standings()
	if _active_ids().is_empty():
		_end_match()
		return
	_host_phase = "viewing"
	_deadline = Time.get_ticks_msec() + READY_TIMEOUT_MS


@rpc("authority", "reliable")
func _rc_results(res: Dictionary, new_players: Dictionary) -> void:
	_on_results(res, new_players)


func _on_results(res: Dictionary, new_players: Dictionary) -> void:
	players = new_players
	last_outcome = float(res["outcome"])
	if run:
		run.apply_battle_result(float(res["outcome"]), int(res["lives"]), int(res["wins"]))
	if phase == "waiting" or phase == "results":
		phase = "results"
	standings_changed.emit()


func _broadcast_standings() -> void:
	_rc_standings.rpc(players)
	standings_changed.emit()


@rpc("authority", "reliable")
func _rc_standings(new_players: Dictionary) -> void:
	players = new_players
	standings_changed.emit()


## Local player finished watching their battle.
func battle_viewed() -> void:
	if phase == "battle":
		phase = "waiting"
	if role == Role.HOST:
		_shop_ready[1] = true
	elif role == Role.CLIENT:
		_rq_shop_ready.rpc_id(1, round_num)
	standings_changed.emit()


@rpc("any_peer", "reliable")
func _rq_shop_ready(r: int) -> void:
	if role == Role.HOST and r == round_num:
		_shop_ready[mp.get_remote_sender_id()] = true


func _end_match() -> void:
	_host_phase = "over"
	var list: Array = []
	for id in players:
		var p: Dictionary = players[id]
		list.append({"id": id, "name": p["name"], "place": p["place"], "wins": p["wins"], "lives": p["lives"], "bot": p["bot"]})
	list.sort_custom(func(x, y): return int(x["place"]) < int(y["place"]))
	_rc_over.rpc(list)
	_on_over(list)


@rpc("authority", "reliable")
func _rc_over(list: Array) -> void:
	_on_over(list)


func _on_over(list: Array) -> void:
	placements = list
	phase = "over"
	var place := 0
	for p in list:
		if int(p["id"]) == my_id:
			place = int(p["place"])
	if place > 0:
		Profile.apply_draft_result(place, list.size())
	match_over.emit(list)


# --- per-frame --------------------------------------------------------------

func _process(delta: float) -> void:
	mp.poll()
	_poll_discovery(delta)
	if role == Role.HOST:
		_send_beacon(delta)
		_host_process()
	if _quick_deadline > 0 and Time.get_ticks_msec() >= _quick_deadline:
		_quick_deadline = 0
		var best: Dictionary = {}
		for l in found_lobbies():
			if int(l["players"]) < int(l["max"]):
				best = l
				break
		stop_search()
		if best.is_empty():
			host_match(_quick_name, settings)
			status.emit("No open matches found, so you are now hosting one. Add bots or wait for players.")
		else:
			join_match(best["ip"], int(best["port"]), _quick_name)
