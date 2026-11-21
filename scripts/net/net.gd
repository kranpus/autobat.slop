extends Node
## Autoload "Net": live 1v1 duels over ENet (LAN or port-forwarded internet).
##
## Protocol (deterministic lockstep-free): each side sends its army code once
## connected. The host picks a random seed and tells both sides to start.
## Each client then simulates the identical battle locally (BattleSim is
## deterministic) and reports a checksum so desyncs/cheats are detected.

signal status_changed(text: String)
signal match_ready(config: Dictionary)
signal result_verified(ok: bool)

const DEFAULT_PORT := 24680

var is_host := false
var my_code := ""
var remote_code := ""
var _my_check := -1
var _remote_check := -1
var _in_match := false
var map_choice := ""              # host's chosen battlefield, "" = random each match


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(func(): status_changed.emit("Connected. Exchanging armies..."))
	multiplayer.connection_failed.connect(func():
		status_changed.emit("Connection failed.")
		close())
	multiplayer.server_disconnected.connect(func():
		status_changed.emit("Host disconnected.")
		close())


func is_active() -> bool:
	return multiplayer.multiplayer_peer is ENetMultiplayerPeer


func host(port: int, army_code: String, map_id: String = "") -> Error:
	close()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, 1)
	if err != OK:
		status_changed.emit("Could not host on port %d (error %d)." % [port, err])
		return err
	multiplayer.multiplayer_peer = peer
	is_host = true
	my_code = army_code
	map_choice = map_id
	status_changed.emit("Hosting on port %d. Waiting for a challenger..." % port)
	return OK


func join(address: String, port: int, army_code: String) -> Error:
	close()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		status_changed.emit("Could not connect (error %d)." % err)
		return err
	multiplayer.multiplayer_peer = peer
	is_host = false
	my_code = army_code
	status_changed.emit("Connecting to %s:%d..." % [address, port])
	return OK


func close() -> void:
	if multiplayer.multiplayer_peer != null and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	is_host = false
	remote_code = ""
	_in_match = false
	_my_check = -1
	_remote_check = -1


func _on_peer_connected(id: int) -> void:
	_send_army.rpc_id(id, my_code)


func _on_peer_disconnected(_id: int) -> void:
	status_changed.emit("Opponent disconnected.")
	remote_code = ""
	if is_host:
		status_changed.emit("Opponent left. Still hosting, waiting for a challenger...")


@rpc("any_peer", "reliable")
func _send_army(code: String) -> void:
	if code.length() > 4096 or Army.decode(code).is_empty():
		status_changed.emit("Received an invalid army from the opponent.")
		return
	remote_code = code
	if is_host and not _in_match:
		var seed_value := randi()
		_begin.rpc(seed_value, my_code, remote_code, _pick_map())


@rpc("authority", "call_local", "reliable")
func _begin(seed_value: int, host_code: String, client_code: String, map_id: String) -> void:
	if not BattleMaps.MAPS.has(map_id):
		map_id = BattleMaps.DEFAULT_MAP
	var a := Army.decode(host_code)
	var b := Army.decode(client_code)
	if a.is_empty() or b.is_empty():
		status_changed.emit("Match aborted: invalid army data.")
		return
	_in_match = true
	_my_check = -1
	_remote_check = -1
	status_changed.emit("Battle started!")
	match_ready.emit({
		"mode": "live",
		"seed": seed_value,
		"squads_a": a["squads"],
		"squads_b": b["squads"],
		"name_a": a["name"],
		"name_b": b["name"],
		"rating_a": a["rating"],
		"rating_b": b["rating"],
		"local_team": 0 if is_host else 1,
		"map": map_id,
	})


## Called by the battle screen when the local simulation finishes.
func report_result(checksum: int) -> void:
	_my_check = checksum
	_in_match = false
	if is_active():
		_receive_result.rpc(checksum)
	_compare()


@rpc("any_peer", "reliable")
func _receive_result(checksum: int) -> void:
	_remote_check = checksum
	_compare()


func _compare() -> void:
	if _my_check >= 0 and _remote_check >= 0:
		result_verified.emit(_my_check == _remote_check)


## Host only: start another battle against the connected opponent.
func start_rematch(army_code: String, map_id: String = "") -> bool:
	if not is_host or remote_code == "" or not is_active():
		return false
	my_code = army_code
	map_choice = map_id
	_begin.rpc(randi(), my_code, remote_code, _pick_map())
	return true


func _pick_map() -> String:
	if BattleMaps.MAPS.has(map_choice):
		return map_choice
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return BattleMaps.random_map_id(rng)
