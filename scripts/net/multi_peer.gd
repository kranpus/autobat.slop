extends MultiplayerPeerExtension
## Server-side multiplayer peer that combines several transports into one:
## the ENet (UDP + DTLS) listener used by the desktop and mobile game, and the
## WebSocket listener used by the browser game. SceneMultiplayer sees a single
## peer, so every RPC, room and account works the same whichever way a player
## connected, and players on both transports meet in the same matches.
##
## Each transport numbers its own connections; this peer gives every
## connection a unique id across all of them and translates in both directions.

var _subs: Array[MultiplayerPeer] = []
var _to_sub := {}          # our id -> [transport index, transport's id]
var _from_sub: Array = []  # per transport: transport's id -> our id
var _target := 0
var _mode := MultiplayerPeer.TRANSFER_MODE_RELIABLE
var _channel := 0
var _refusing := false
var _closed := false
var _rng := RandomNumberGenerator.new()
## Most connections allowed in total (each transport may enforce its own too).
var max_peers := 1000


func _init() -> void:
	_rng.randomize()


## Add a transport that is already listening (create_server done).
func add_transport(peer: MultiplayerPeer) -> void:
	var index := _subs.size()
	_subs.append(peer)
	_from_sub.append({})
	peer.peer_connected.connect(_on_sub_connected.bind(index))
	peer.peer_disconnected.connect(_on_sub_disconnected.bind(index))


func transport_count() -> int:
	return _subs.size()


## How many players are connected through transport `index`.
func peers_on(index: int) -> int:
	return (_from_sub[index] as Dictionary).size()


## True while `id` is connected and can be sent to (not mid-disconnect).
func is_open(id: int) -> bool:
	if not _to_sub.has(id):
		return false
	var sub: MultiplayerPeer = _subs[_to_sub[id][0]]
	var sid: int = _to_sub[id][1]
	if sub is ENetMultiplayerPeer:
		var pp := (sub as ENetMultiplayerPeer).get_peer(sid)
		return pp != null and pp.get_state() == ENetPacketPeer.STATE_CONNECTED
	if sub is WebSocketMultiplayerPeer:
		var ws := (sub as WebSocketMultiplayerPeer).get_peer(sid)
		return ws != null and ws.get_ready_state() == WebSocketPeer.STATE_OPEN
	return true


func _on_sub_connected(sub_id: int, index: int) -> void:
	if _refusing or _to_sub.size() >= max_peers:
		_subs[index].disconnect_peer(sub_id, true)
		return
	# Keep the transport's own id when it's free (easier to read in logs).
	var id := sub_id
	while id <= 1 or _to_sub.has(id):
		id = _rng.randi_range(2, 2147483647)
	_to_sub[id] = [index, sub_id]
	_from_sub[index][sub_id] = id
	peer_connected.emit(id)


func _on_sub_disconnected(sub_id: int, index: int) -> void:
	var id: int = _from_sub[index].get(sub_id, 0)
	if id == 0:
		return
	_from_sub[index].erase(sub_id)
	_to_sub.erase(id)
	peer_disconnected.emit(id)


# --- receiving ---------------------------------------------------------------

## The transport whose next packet SceneMultiplayer is reading, or -1.
## Packets from connections we haven't registered are dropped here.
func _current() -> int:
	for i in _subs.size():
		var sub := _subs[i]
		while sub.get_available_packet_count() > 0:
			if _from_sub[i].has(sub.get_packet_peer()):
				return i
			sub.get_packet()  # unknown sender: discard
	return -1


func _get_available_packet_count() -> int:
	if _current() < 0:
		return 0
	var n := 0
	for sub in _subs:
		n += sub.get_available_packet_count()
	return n


func _get_packet_script() -> PackedByteArray:
	var i := _current()
	return _subs[i].get_packet() if i >= 0 else PackedByteArray()


func _get_packet_peer() -> int:
	var i := _current()
	return _from_sub[i].get(_subs[i].get_packet_peer(), 0) if i >= 0 else 0


func _get_packet_mode() -> MultiplayerPeer.TransferMode:
	var i := _current()
	return _subs[i].get_packet_mode() if i >= 0 else MultiplayerPeer.TRANSFER_MODE_RELIABLE


func _get_packet_channel() -> int:
	var i := _current()
	return _subs[i].get_packet_channel() if i >= 0 else 0


# --- sending -------------------------------------------------------------------

func _put_packet_script(buffer: PackedByteArray) -> Error:
	if _target > 0:
		if not _to_sub.has(_target):
			return ERR_UNAVAILABLE
		return _send(_to_sub[_target][0], _to_sub[_target][1], buffer)
	# Broadcast (0) or everyone except one peer (-id).
	var skip: Array = _to_sub.get(-_target, [-1, 0]) if _target < 0 else [-1, 0]
	for i in _subs.size():
		if (_from_sub[i] as Dictionary).is_empty():
			continue
		_send(i, -int(skip[1]) if int(skip[0]) == i else 0, buffer)
	return OK


func _send(index: int, sub_target: int, buffer: PackedByteArray) -> Error:
	var sub := _subs[index]
	sub.transfer_mode = _mode
	sub.transfer_channel = _channel
	sub.set_target_peer(sub_target)
	return sub.put_packet(buffer)


func _set_target_peer(peer: int) -> void:
	_target = peer


func _set_transfer_mode(mode: MultiplayerPeer.TransferMode) -> void:
	_mode = mode


func _get_transfer_mode() -> MultiplayerPeer.TransferMode:
	return _mode


func _set_transfer_channel(channel: int) -> void:
	_channel = channel


func _get_transfer_channel() -> int:
	return _channel


func _get_max_packet_size() -> int:
	return 1 << 24


# --- connection --------------------------------------------------------------------

func _poll() -> void:
	for sub in _subs:
		sub.poll()


func _get_unique_id() -> int:
	return 1


func _is_server() -> bool:
	return true


func _is_server_relay_supported() -> bool:
	return false


func _get_connection_status() -> MultiplayerPeer.ConnectionStatus:
	return MultiplayerPeer.CONNECTION_DISCONNECTED if _closed else MultiplayerPeer.CONNECTION_CONNECTED


func _disconnect_peer(peer: int, force: bool) -> void:
	if _to_sub.has(peer):
		_subs[_to_sub[peer][0]].disconnect_peer(_to_sub[peer][1], force)


func _set_refuse_new_connections(enable: bool) -> void:
	_refusing = enable
	for sub in _subs:
		sub.refuse_new_connections = enable


func _is_refusing_new_connections() -> bool:
	return _refusing


func _close() -> void:
	_closed = true
	for sub in _subs:
		sub.close()
	_to_sub.clear()
	for d in _from_sub:
		(d as Dictionary).clear()
