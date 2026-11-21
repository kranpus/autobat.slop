extends Node
## Autoload "Party": networking for Legion Draft.
##
## Roles
##   SERVER  dedicated matchmaking server (headless, many rooms, no local player)
##   HOST    a player hosting one match on their LAN (runs one MatchRoom)
##   CLIENT  a player connected to a LAN host or to the online server
##
## All match logic lives in MatchRoom and is authoritative: clients send only
## requests and shop actions; the room replays actions on its own DraftRun,
## so boards can't be forged. Uses its own SceneMultiplayer so it never
## interferes with the 1v1 duel networking in Net.

signal lobby_changed
signal lobbies_found(list: Array)
signal rooms_listed(list: Array)
signal online_changed
signal status(text: String)
signal match_started
signal shop_started(round_num: int, seconds: int)
signal battle_ready(config: Dictionary)
signal standings_changed
signal match_over(placements: Array)
signal left_match(reason: String)

const GAME_VERSION := "legion-draft-2"   # client and server must match exactly
const PORT := 24700                      # LAN hosting
const SERVER_PORT := 24702               # dedicated online server
const DISCOVERY_PORT := 24701
const GAME_TAG := "autobat_draft_v2"
## Put your server's address here so players don't have to type it
## (players can still change it in the Legion Draft tab).
const DEFAULT_SERVER := "localhost"
const MAX_SERVER_PEERS := 1000
const MAX_ROOMS := 400
const REQUESTS_PER_SECOND := 30
const CODE_CHARS := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

enum Role { NONE, SERVER, HOST, CLIENT }

var role := Role.NONE
var mp := SceneMultiplayer.new()
var online := false                      # CLIENT connected to the dedicated server

# Client-side view of the current room/match.
var settings := {"wins": 10, "lives": 5, "max_players": 8, "turn_time": 75}
var players := {}
var owner_id := 0
var room_code := ""
var room_public := true
var room_quick := false
var auto_start_msec := 0
var my_id := 0
var player_name := ""
var phase := "idle"          # idle, connecting, online, lobby, waiting, shop, battle, results, over
var round_num := 0
var run: DraftRun = null
var turn_deadline_msec := 0
var placements: Array = []
var last_outcome := -1.0
var _pending_online: Array = []

# Authority side (SERVER or HOST).
var _rooms := {}             # code -> MatchRoom
var _player_room := {}       # peer id -> room code
var _names := {}             # peer id -> pname (verified peers)
var _req_count := {}
var _req_window := 0
var _rng := RandomNumberGenerator.new()
var _local_calls := 0        # >0 while the LAN host runs its own request locally

# LAN discovery.
var _beacon: PacketPeerUDP
var _beacon_t := 0.0
var _listener: PacketPeerUDP
var _found := {}
var _found_t := 0.0
var _quick_deadline := 0
var _quick_settings := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	get_tree().set_multiplayer(mp, get_path())
	# Clients never talk to each other directly, so don't relay peer
	# join/leave notices to every client (that would be O(n^2) on a big server).
	mp.server_relay = false
	mp.peer_connected.connect(_on_peer_connected)
	mp.peer_disconnected.connect(_on_peer_disconnected)
	mp.connected_to_server.connect(_on_connected)
	mp.connection_failed.connect(func(): _drop_connection("Could not connect."))
	mp.server_disconnected.connect(func(): _drop_connection("Lost connection to the server."))


# --- state helpers ----------------------------------------------------------

func is_active() -> bool:
	return role != Role.NONE


func is_host() -> bool:
	return role == Role.HOST


func is_owner() -> bool:
	return my_id != 0 and owner_id == my_id


func is_in_lobby() -> bool:
	return phase == "lobby"


func is_in_match() -> bool:
	return phase in ["waiting", "shop", "battle", "results", "over"]


func me() -> Dictionary:
	return players.get(my_id, {})


func server_address() -> String:
	var a := str(Profile.data.get("server_address", ""))
	return a if a != "" else DEFAULT_SERVER


func _sender() -> int:
	# A host's own request can run while an incoming RPC is being processed,
	# so local calls are flagged explicitly instead of trusting the RPC context.
	if _local_calls > 0:
		return my_id
	var id := mp.get_remote_sender_id()
	return id if id != 0 else my_id


func _close_peer() -> void:
	if mp.multiplayer_peer != null and not (mp.multiplayer_peer is OfflineMultiplayerPeer):
		mp.multiplayer_peer.close()
	mp.multiplayer_peer = OfflineMultiplayerPeer.new()


func _reset_client_state() -> void:
	players = {}
	owner_id = 0
	room_code = ""
	run = null
	round_num = 0
	placements = []
	last_outcome = -1.0


# --- dedicated server -------------------------------------------------------

func start_server(port: int = SERVER_PORT) -> Error:
	disconnect_all(true)
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_SERVER_PEERS)
	if err != OK:
		print("ERROR: could not listen on UDP port %d (error %d)" % [port, err])
		return err
	mp.multiplayer_peer = peer
	role = Role.SERVER
	my_id = 1
	_log("Legion Draft server %s listening on UDP port %d" % [GAME_VERSION, port])
	return OK


func _log(text: String) -> void:
	if role == Role.SERVER:
		print("[%s] %s" % [Time.get_datetime_string_from_system(), text])
	else:
		status.emit(text)


# --- LAN hosting ------------------------------------------------------------

func host_lan(pname: String, new_settings: Dictionary) -> Error:
	disconnect_all(true)
	var s := MatchRoom.clean_settings(new_settings)
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, int(s["max_players"]) - 1)
	if err != OK:
		status.emit("Could not host on port %d (is another match running?)." % PORT)
		return err
	mp.multiplayer_peer = peer
	role = Role.HOST
	my_id = 1
	player_name = pname
	_reset_client_state()
	_names[1] = pname
	_create_room("LAN", s, true, false)
	_join_room(1, "LAN", pname)
	_beacon = PacketPeerUDP.new()
	_beacon.set_broadcast_enabled(true)
	_beacon.set_dest_address("255.255.255.255", DISCOVERY_PORT)
	status.emit("Hosting on your network (port %d). Others can find it or join with your IP." % PORT)
	return OK


func join_lan(address: String, port: int, pname: String) -> Error:
	return _connect_to(address, port, pname, false, [])


## Find a LAN match with space and join it; otherwise host one.
func quick_lan(pname: String, new_settings: Dictionary) -> void:
	player_name = pname
	_quick_settings = new_settings.duplicate()
	start_search()
	_quick_deadline = Time.get_ticks_msec() + 2500
	status.emit("Looking for an open match on your network...")


# --- online (dedicated server) ----------------------------------------------

func online_quick(pname: String, new_settings: Dictionary) -> void:
	_online_request(pname, ["_rq_quick", new_settings])


func online_create(pname: String, new_settings: Dictionary, is_public: bool) -> void:
	_online_request(pname, ["_rq_create", new_settings, is_public])


func online_join(pname: String, code: String) -> void:
	_online_request(pname, ["_rq_join", code.strip_edges().to_upper()])


func online_list(pname: String) -> void:
	_online_request(pname, ["_rq_list"])


func _online_request(pname: String, req: Array) -> void:
	player_name = pname
	if role == Role.CLIENT and online and phase != "connecting":
		if phase == "lobby" and req[0] != "_rq_list":
			_request("_rq_leave_room", [])
			_reset_client_state()
			phase = "online"
		_send_request(req)
		return
	var addr := server_address().strip_edges()
	var port := SERVER_PORT
	if addr.count(":") == 1:
		port = int(addr.get_slice(":", 1))
		addr = addr.get_slice(":", 0)
	_connect_to(addr, port, pname, true, req)


func _send_request(req: Array) -> void:
	_request(str(req[0]), req.slice(1))


func _connect_to(address: String, port: int, pname: String, is_online: bool, pending: Array) -> Error:
	disconnect_all(true)
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		status.emit("Could not connect to %s:%d (error %d)." % [address, port, err])
		return err
	mp.multiplayer_peer = peer
	role = Role.CLIENT
	online = is_online
	player_name = pname
	_pending_online = pending
	phase = "connecting"
	status.emit("Connecting to %s:%d..." % [address, port])
	online_changed.emit()
	lobby_changed.emit()
	return OK


func _on_connected() -> void:
	my_id = mp.get_unique_id()
	_request("_rq_hello", [player_name, GAME_VERSION])


## Leave the current room/match. Online players stay connected to the server.
func leave() -> void:
	if role == Role.CLIENT and online:
		_request("_rq_leave_room", [])
		_reset_client_state()
		phase = "online"
		left_match.emit("You left the match.")
		lobby_changed.emit()
		return
	disconnect_all()


func disconnect_all(silent: bool = false) -> void:
	stop_search()
	_quick_deadline = 0
	_close_peer()
	if _beacon:
		_beacon.close()
		_beacon = null
	var was := role != Role.NONE
	role = Role.NONE
	online = false
	phase = "idle"
	_rooms.clear()
	_player_room.clear()
	_names.clear()
	_reset_client_state()
	if was and not silent:
		left_match.emit("Disconnected.")
	lobby_changed.emit()
	online_changed.emit()


func _drop_connection(reason: String) -> void:
	var was := role != Role.NONE
	disconnect_all(true)
	status.emit(reason)
	if was:
		left_match.emit(reason)


# --- requests (client -> authority) ----------------------------------------

## Send a request to the authority. When we ARE the authority (LAN host),
## the handler runs directly with our own id as the sender.
func _request(method: String, args: Array) -> void:
	if role == Role.HOST:
		_local_calls += 1
		callv(method, args)
		_local_calls -= 1
	elif role == Role.CLIENT:
		var call_args: Array = [1, method]
		call_args.append_array(args)
		callv("rpc_id", call_args)


func _authority() -> bool:
	return role == Role.SERVER or role == Role.HOST


## Basic flood protection for the server.
func _allow(id: int) -> bool:
	if role != Role.SERVER:
		return true
	var now := Time.get_ticks_msec()
	if now - _req_window >= 1000:
		_req_window = now
		_req_count.clear()
	_req_count[id] = int(_req_count.get(id, 0)) + 1
	return int(_req_count[id]) <= REQUESTS_PER_SECOND


func _room_of(id: int) -> MatchRoom:
	return _rooms.get(_player_room.get(id, ""), null)


@rpc("any_peer", "reliable")
func _rq_hello(pname: String, version: String) -> void:
	if not _authority():
		return
	var id := _sender()
	if version != GAME_VERSION:
		_deliver(id, "error", ["Version mismatch: you have %s, the host runs %s. Please update the game." % [version.left(32), GAME_VERSION]])
		return
	var nm := pname.strip_edges().left(24)
	_names[id] = nm if nm != "" else "Commander"
	if role == Role.HOST:
		var err := _join_room(id, "LAN", _names[id])
		if err != "":
			_deliver(id, "kicked", [err])
		return
	_log("%s connected (%d online)" % [_names[id], _names.size()])
	_deliver(id, "welcome", [{"rooms": _rooms.size(), "players": _names.size()}])


@rpc("any_peer", "reliable")
func _rq_list() -> void:
	var id := _sender()
	if role != Role.SERVER or not _names.has(id) or not _allow(id):
		return
	_deliver(id, "rooms", [_public_rooms()])


func _public_rooms() -> Array:
	var out: Array = []
	for c in _rooms:
		var r: MatchRoom = _rooms[c]
		if r.public and r.phase == "lobby" and not r.is_full():
			out.append(r.info())
	return out


@rpc("any_peer", "reliable")
func _rq_quick(new_settings: Dictionary) -> void:
	var id := _sender()
	if role != Role.SERVER or not _names.has(id) or not _allow(id) or _player_room.has(id):
		return
	# Join the fullest open quick-match room, or open a new one.
	var best: MatchRoom = null
	for c in _rooms:
		var r: MatchRoom = _rooms[c]
		if r.quick and r.phase == "lobby" and not r.is_full():
			if best == null or r.players.size() > best.players.size():
				best = r
	if best == null:
		best = _create_room("", new_settings, true, true)
		if best == null:
			_deliver(id, "error", ["The server is busy. Try again in a moment."])
			return
	_join_room(id, best.code, _names[id])


@rpc("any_peer", "reliable")
func _rq_create(new_settings: Dictionary, is_public: bool) -> void:
	var id := _sender()
	if role != Role.SERVER or not _names.has(id) or not _allow(id) or _player_room.has(id):
		return
	var r := _create_room("", new_settings, is_public, false)
	if r == null:
		_deliver(id, "error", ["The server is busy. Try again in a moment."])
		return
	_join_room(id, r.code, _names[id])


@rpc("any_peer", "reliable")
func _rq_join(code: String) -> void:
	var id := _sender()
	if role != Role.SERVER or not _names.has(id) or not _allow(id) or _player_room.has(id):
		return
	code = code.left(8)
	if not _rooms.has(code):
		_deliver(id, "error", ["No match with code %s." % code])
		return
	var err := _join_room(id, code, _names[id])
	if err != "":
		_deliver(id, "error", [err])


@rpc("any_peer", "reliable")
func _rq_leave_room() -> void:
	var id := _sender()
	if not _authority() or not _allow(id):
		return
	var r := _room_of(id)
	if r:
		r.remove_player(id)
	_player_room.erase(id)


@rpc("any_peer", "reliable")
func _rq_ready(is_ready: bool) -> void:
	var id := _sender()
	var r := _room_of(id) if _authority() and _allow(id) else null
	if r:
		r.set_ready(id, is_ready)


@rpc("any_peer", "reliable")
func _rq_add_bot() -> void:
	var id := _sender()
	var r := _room_of(id) if _authority() and _allow(id) else null
	if r:
		r.add_bot(id)


@rpc("any_peer", "reliable")
func _rq_kick(target: int) -> void:
	var id := _sender()
	var r := _room_of(id) if _authority() and _allow(id) else null
	if r and r.players.has(target):
		r.kick(id, target)
		if not r.players.has(target):
			_player_room.erase(target)


@rpc("any_peer", "reliable")
func _rq_start() -> void:
	var id := _sender()
	var r := _room_of(id) if _authority() and _allow(id) else null
	if r:
		r.start(id)


@rpc("any_peer", "reliable")
func _rq_action(r_num: int, act: Array) -> void:
	var id := _sender()
	var r := _room_of(id) if _authority() and _allow(id) else null
	if r and act.size() <= 4:
		r.action(id, r_num, act)


@rpc("any_peer", "reliable")
func _rq_submit(r_num: int) -> void:
	var id := _sender()
	var r := _room_of(id) if _authority() else null
	if r:
		r.submit(id, r_num)


@rpc("any_peer", "reliable")
func _rq_shop_ready(r_num: int) -> void:
	var id := _sender()
	var r := _room_of(id) if _authority() else null
	if r:
		r.shop_ready(id, r_num)


# --- rooms (authority side) -------------------------------------------------

func _create_room(code: String, new_settings: Dictionary, is_public: bool, quick: bool) -> MatchRoom:
	if _rooms.size() >= MAX_ROOMS:
		return null
	if code == "":
		for _attempt in 50:
			code = ""
			for _i in 5:
				code += CODE_CHARS[_rng.randi_range(0, CODE_CHARS.length() - 1)]
			if not _rooms.has(code):
				break
	var r := MatchRoom.new(code, new_settings, is_public, quick)
	r.outbox.connect(_deliver)
	r.room_log.connect(_log)
	_rooms[code] = r
	return r


func _join_room(id: int, code: String, pname: String) -> String:
	var r: MatchRoom = _rooms.get(code, null)
	if r == null:
		return "That match no longer exists."
	_player_room[id] = code
	var err := r.add_player(id, pname)
	if err != "":
		_player_room.erase(id)
	return err


## Deliver a room message to a player: locally for the LAN host's own
## player, otherwise as an RPC.
func _deliver(id: int, method: String, args: Array) -> void:
	if id == my_id and role == Role.HOST:
		callv("_rc_" + method, args)
		return
	if not mp.get_peers().has(id):
		return
	var enet := mp.multiplayer_peer as ENetMultiplayerPeer
	if enet:
		var pp := enet.get_peer(id)
		if pp == null or pp.get_state() != ENetPacketPeer.STATE_CONNECTED:
			return  # peer is disconnecting
	var call_args: Array = [id, "_rc_" + method]
	call_args.append_array(args)
	callv("rpc_id", call_args)


func _on_peer_connected(_id: int) -> void:
	pass  # peers introduce themselves with _rq_hello


func _on_peer_disconnected(id: int) -> void:
	if not _authority():
		return
	var r := _room_of(id)
	if r:
		r.remove_player(id)
	_player_room.erase(id)
	if role == Role.SERVER and _names.has(id):
		_log("%s disconnected" % _names[id])
	_names.erase(id)
	_req_count.erase(id)


func _cleanup_rooms() -> void:
	if role != Role.SERVER:
		return
	var now := Time.get_ticks_msec()
	for c in _rooms.keys():
		var r: MatchRoom = _rooms[c]
		var dead := r.is_empty_of_humans() and r.phase != "sim"
		if r.phase == "over" and now - r.over_msec > 120000:
			dead = true
		if dead:
			for id in r.players:
				if _player_room.get(id, "") == c:
					_player_room.erase(id)
			_rooms.erase(c)
			_log("Room %s closed (%d rooms open)" % [c, _rooms.size()])


# --- client handlers (authority -> client) ----------------------------------

@rpc("authority", "reliable")
func _rc_welcome(info: Dictionary) -> void:
	phase = "online"
	status.emit("Connected to the server (%d players online, %d matches)." % [int(info.get("players", 0)), int(info.get("rooms", 0))])
	online_changed.emit()
	lobby_changed.emit()
	if not _pending_online.is_empty():
		var req := _pending_online
		_pending_online = []
		_send_request(req)


@rpc("authority", "reliable")
func _rc_error(text: String) -> void:
	status.emit(text)
	if phase == "connecting":
		_drop_connection(text)


@rpc("authority", "reliable")
func _rc_rooms(list: Array) -> void:
	rooms_listed.emit(list)


@rpc("authority", "reliable")
func _rc_kicked(reason: String) -> void:
	if online:
		_reset_client_state()
		phase = "online"
		status.emit(reason)
		left_match.emit(reason)
		lobby_changed.emit()
	else:
		_drop_connection(reason)


@rpc("authority", "reliable")
func _rc_lobby(state: Dictionary) -> void:
	settings = state.get("settings", settings)
	players = state.get("players", {})
	owner_id = int(state.get("owner", 0))
	room_code = str(state.get("code", ""))
	room_public = bool(state.get("public", true))
	room_quick = bool(state.get("quick", false))
	var ms := int(state.get("auto_start_in", -1))
	auto_start_msec = Time.get_ticks_msec() + ms if ms >= 0 else 0
	if phase in ["connecting", "online", "idle"]:
		status.emit(("Joined match %s." % room_code) if online else "Joined the match.")
	if phase not in ["waiting", "shop", "battle", "results"]:
		phase = "lobby"
	lobby_changed.emit()


@rpc("authority", "reliable")
func _rc_match_start(new_settings: Dictionary, new_players: Dictionary) -> void:
	stop_search()
	settings = new_settings
	players = new_players
	run = DraftRun.new()
	run.lives = int(settings["lives"])
	placements = []
	phase = "waiting"
	match_started.emit()


@rpc("authority", "reliable")
func _rc_shop(r: int, seconds: int, state: Dictionary) -> void:
	round_num = r
	turn_deadline_msec = Time.get_ticks_msec() + seconds * 1000
	last_outcome = -1.0
	if state.is_empty() or run == null:
		phase = "waiting"
		standings_changed.emit()
		return
	run.load_dict(state)
	phase = "shop"
	shop_started.emit(r, seconds)


## Perform a shop action locally (instant feedback) and send it to the
## authority, which replays it on the real run.
func do_action(act: Array) -> bool:
	if phase != "shop" or run == null:
		return false
	var ok := run.apply_action(act)
	if ok:
		_request("_rq_action", [round_num, act])
	return ok


func submit_turn() -> void:
	if phase != "shop" or run == null:
		return
	run.end_turn()
	phase = "waiting"
	status.emit("Turn submitted. Waiting for other players...")
	_request("_rq_submit", [round_num])
	standings_changed.emit()


@rpc("authority", "reliable")
func _rc_force_end(r: int) -> void:
	if phase == "shop" and r == round_num and run:
		run.end_turn()
		phase = "waiting"
		standings_changed.emit()


@rpc("authority", "reliable")
func _rc_battle(cfg: Dictionary) -> void:
	phase = "battle"
	battle_ready.emit(cfg)


@rpc("authority", "reliable")
func _rc_results(res: Dictionary, new_players: Dictionary) -> void:
	players = new_players
	last_outcome = float(res["outcome"])
	if run:
		run.lives = int(res["lives"])
		run.wins = int(res["wins"])
	if phase == "waiting":
		phase = "results"
	standings_changed.emit()


@rpc("authority", "reliable")
func _rc_standings(new_players: Dictionary) -> void:
	players = new_players
	standings_changed.emit()


@rpc("authority", "reliable")
func _rc_over(list: Array) -> void:
	placements = list
	phase = "over"
	var place := 0
	for p in list:
		if int(p["id"]) == my_id:
			place = int(p["place"])
	if place > 0:
		Profile.apply_draft_result(place, list.size())
	match_over.emit(list)


# --- client actions -----------------------------------------------------------

func set_ready(is_ready: bool) -> void:
	_request("_rq_ready", [is_ready])


func add_bot() -> void:
	_request("_rq_add_bot", [])


func kick(id: int) -> void:
	_request("_rq_kick", [id])


func start_match() -> void:
	_request("_rq_start", [])


func can_start() -> bool:
	if not is_owner() or phase != "lobby":
		return false
	if players.size() < 2 and not room_quick:
		return false
	for id in players:
		if id != owner_id and not players[id]["ready"]:
			return false
	return true


## The local player finished watching their battle replay.
func battle_viewed() -> void:
	if phase == "battle":
		phase = "results" if last_outcome >= 0.0 else "waiting"
	_request("_rq_shop_ready", [round_num])
	standings_changed.emit()


# --- LAN discovery ------------------------------------------------------------

func start_search() -> void:
	stop_search()
	_found.clear()
	_listener = PacketPeerUDP.new()
	if _listener.bind(DISCOVERY_PORT) != OK:
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
	var r: MatchRoom = _rooms.get("LAN", null)
	if _beacon == null or r == null or r.phase != "lobby":
		return
	_beacon_t += delta
	if _beacon_t < 1.0:
		return
	_beacon_t = 0.0
	var info := {"tag": GAME_TAG, "name": player_name, "port": PORT, "players": r.players.size(),
		"max": r.settings["max_players"], "wins": r.settings["wins"], "lives": r.settings["lives"]}
	_beacon.put_packet(JSON.stringify(info).to_utf8_buffer())


# --- per frame ----------------------------------------------------------------

func _process(delta: float) -> void:
	mp.poll()
	_poll_discovery(delta)
	if _authority():
		for c in _rooms.keys():
			if _rooms.has(c):
				(_rooms[c] as MatchRoom).process()
		_cleanup_rooms()
	if role == Role.HOST:
		_send_beacon(delta)
	if _quick_deadline > 0 and Time.get_ticks_msec() >= _quick_deadline:
		_quick_deadline = 0
		var best: Dictionary = {}
		for l in found_lobbies():
			if int(l["players"]) < int(l["max"]):
				best = l
				break
		stop_search()
		if best.is_empty():
			host_lan(player_name, _quick_settings)
			status.emit("No open matches on your network, so you're hosting one. Add bots or wait for players.")
		else:
			join_lan(best["ip"], int(best["port"]), player_name)
