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
## Ranked opponents found on the server (saved armies of players with a
## similar rating). Empty when the server can't be reached.
signal ranked_opponents(list: Array)

const GAME_VERSION := "legion-draft-20"   # client and server must match exactly
const PORT := 24700                      # LAN hosting
const SERVER_PORT := 24702               # dedicated online server (ENet/UDP)
const WS_PORT := 24704                   # same server for browsers (WebSocket/TCP)
const WEB_PORT := 24705                  # the server can also host the web build (HTTP)
const MultiPeer := preload("res://scripts/net/multi_peer.gd")
const WebHost := preload("res://scripts/net/web_host.gd")
const DISCOVERY_PORT := 24701
const GAME_TAG := "autobat_draft_v2"
## Put your server's address here so players don't have to type it
## (players can still change it in the Legion Draft tab).
const DEFAULT_SERVER := "play.battleserver.tech"   # where players connect unless they type another server
const MAX_SERVER_PEERS := 1000
const MAX_ROOMS := 400
const REQUESTS_PER_SECOND := 30
const CODE_CHARS := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
const CONFIG_PATH := "user://server_config.json"
const DEFAULT_REWARDS := {"battle_mult": 1.0, "draft_mult": 1.0, "draft_table": [400, 250, 150, 60]}

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
## Playing Legion Draft against bots on this device (no network).
var solo := false
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
var _sync_only := false            # quick background check-in for locks/gold, then disconnect
var _sync_deadline := 0
var _ranked_only := false          # short connection just to fetch ranked opponents
var _ranked_request: Array = []
var _awaiting_ranked := false
var _ranked_deadline := 0
var ranked_pool: RankedPool         # server only: players' saved ranked armies
var unit_stats: UnitStats           # server only: unit use and win rates (admin console)

# Authority side (SERVER or HOST).
var _rooms := {}             # code -> MatchRoom
var _player_room := {}       # peer id -> room code
var _names := {}             # peer id -> pname (verified peers)
var _req_count := {}
var _req_window := 0
var _rng := RandomNumberGenerator.new()
## Gold economy set by the server admin (see console commands). Rooms share
## this dictionary, so changes apply to matches already in progress.
var rewards := DEFAULT_REWARDS.duplicate(true)
## This build's protocol version (tests can pretend to be another version
## with --fake-version=...). Players see the release version instead.
var game_version := GAME_VERSION


## The release version players see, e.g. "0.7" (Project Settings ->
## Application -> Config -> Version). GAME_VERSION is the compatibility
## number checked between game and server.
static func build_version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "?"))
## Where players get the new version (set with the 'update-url' console
## command or the UPDATE_URL environment variable). Sent to out-of-date games.
var update_url := ""

## The server or host runs a different version: {mine, theirs, older, url, host}.
## "older" is true when this game is the out-of-date one.
signal update_required(info: Dictionary)
## Ranked: only saved player armies within this many rating points of yours.
const DEFAULT_RANKED_RANGE := 200
var ranked_range := DEFAULT_RANKED_RANGE
var _stdin_thread: Thread
var _stdin_mutex := Mutex.new()
var _stdin_lines: Array = []
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
	# Version handshake: before any RPC, both sides exchange a small JSON
	# message that never changes between versions, so an out-of-date game is
	# told clearly (RPC numbering differs between versions, so RPC error
	# messages can't be trusted for this).
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--fake-version="):
			game_version = arg.get_slice("=", 1)
	mp.auth_callback = _on_auth
	mp.auth_timeout = 10.0
	mp.peer_authenticating.connect(_on_peer_authenticating)
	mp.peer_connected.connect(_on_peer_connected)
	mp.peer_disconnected.connect(_on_peer_disconnected)
	mp.connected_to_server.connect(_on_connected)
	mp.connection_failed.connect(func():
		if online:
			_check_cert_changed.call_deferred()
		if _auth_waiting:
			_auth_failed("Could not reach the server at %s." % server_address())
		elif _ranked_only:
			_ranked_failed()
		elif _sync_only:
			disconnect_all(true)  # background sync: stay quiet if the server is unreachable
		else:
			_drop_connection("Could not connect."))
	mp.server_disconnected.connect(func():
		if _auth_waiting:
			_auth_failed("The server closed the connection.")
		elif _ranked_only:
			_ranked_failed()
		elif _sync_only:
			disconnect_all(true)
		else:
			var was_session := _session_live
			_drop_connection("Lost connection to the server." + (" Reconnecting..." if was_session else ""))
			if was_session:
				_reconnect_at = Time.get_ticks_msec() + 3000
				session_changed.emit())


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


# --- version handshake ---------------------------------------------------------

const HANDSHAKE_PROTOCOL := 1


## A connection is being set up: clients introduce themselves first.
func _on_peer_authenticating(id: int) -> void:
	if role == Role.CLIENT and id == 1:
		mp.send_auth(1, JSON.stringify({"hs": HANDSHAKE_PROTOCOL, "version": game_version, "build": build_version()}).to_utf8_buffer())


func _on_auth(id: int, data: PackedByteArray) -> void:
	var msg = JSON.parse_string(data.get_string_from_utf8())
	if typeof(msg) != TYPE_DICTIONARY:
		mp.disconnect_peer(id)
		return
	if _authority():
		# A client: let it in when the versions match, otherwise explain.
		var theirs := str(msg.get("version", "")).left(40)
		if theirs == game_version:
			mp.send_auth(id, JSON.stringify({"hs": HANDSHAKE_PROTOCOL, "ok": true, "version": game_version}).to_utf8_buffer())
			mp.complete_auth(id)
		else:
			mp.send_auth(id, JSON.stringify({"hs": HANDSHAKE_PROTOCOL, "ok": false, "version": game_version, "build": build_version(),
				"update_url": update_url, "host": role == Role.HOST}).to_utf8_buffer())
			if role == Role.SERVER:
				_log("Turned away a game on version %s / %s (this server runs %s / %s)" % [str(msg.get("build", "?")).left(20), theirs, build_version(), game_version])
			# The game hangs up once told; if it doesn't, the handshake times out.
	elif id == 1:
		if bool(msg.get("ok", false)):
			mp.complete_auth(1)
		else:
			_version_rejected(str(msg.get("version", "?")).left(40), str(msg.get("update_url", "")).left(300), bool(msg.get("host", false)), str(msg.get("build", "")).left(20))


## "legion-draft-11" -> 11 (0 if unknown).
static func version_number(v: String) -> int:
	var tail := v.get_slice("-", v.get_slice_count("-") - 1)
	return int(tail) if tail.is_valid_int() else 0


func _version_rejected(theirs: String, url: String, from_host: bool, theirs_build: String = "") -> void:
	var older := version_number(game_version) < version_number(theirs)
	var who := "The match host" if from_host else "The server"
	# Show release versions ("0.7") when both sides know them.
	var their_label := theirs_build if theirs_build != "" else theirs
	var my_label := build_version() if theirs_build != "" else game_version
	if their_label == my_label:
		their_label = "%s (%s)" % [theirs_build, theirs]
		my_label = "%s (%s)" % [build_version(), game_version]
	var text := ("Update required: %s runs a newer version of the game (%s, you have %s)." % [who.to_lower(), their_label, my_label]) if older \
		else ("%s runs an older version of the game (%s, you have %s). It needs updating first." % [who, their_label, my_label])
	# Signed in: don't keep retrying every few seconds with the wrong version.
	_reconnect_at = Time.get_ticks_msec() + 600000
	update_required.emit({"mine": my_label, "theirs": their_label, "older": older, "url": url, "host": from_host})
	if _auth_waiting:
		_auth_failed(text)
	elif _ranked_only or _awaiting_ranked:
		_ranked_failed()
	elif _sync_only:
		_hang_up_later()
	else:
		_drop_connection(text)


## "Update now": the browser reloads the page (which fetches the new build);
## other platforms open the download page the server named.
func open_update(url: String) -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.location.reload()")
	elif url.begins_with("https://") or url.begins_with("http://"):
		OS.shell_open(url)


func server_address() -> String:
	var a := str(Profile.settings.get("server_address", ""))
	if a != "":
		return a
	# In the browser, default to the machine the page came from when the game
	# server hosts the web build itself (plain http on its web port), so home
	# players needn't type anything. Pages on other hosts (itch.io...) use
	# DEFAULT_SERVER instead.
	if OS.has_feature("web"):
		var host := str(JavaScriptBridge.eval("window.location.hostname", true))
		var port := str(JavaScriptBridge.eval("window.location.port", true))
		var proto := str(JavaScriptBridge.eval("window.location.protocol", true))
		# ...also when no server address has been built in (DEFAULT_SERVER
		# left at localhost): then the page's own site runs the server, as
		# with the VPS setup (server/docker-compose.vps.yml).
		if host != "" and (port == str(WEB_PORT) or proto == "http:" or DEFAULT_SERVER == "localhost"):
			return host
	return DEFAULT_SERVER


## The browser game talks to the server over WebSocket (browsers can't use
## UDP). `--websocket` makes a desktop build do the same, for testing.
static func use_websocket() -> bool:
	return OS.has_feature("web") or "--websocket" in OS.get_cmdline_user_args()


## True if the page is served over HTTPS (browsers then require wss://).
static func _page_is_https() -> bool:
	return OS.has_feature("web") and str(JavaScriptBridge.eval("window.location.protocol", true)) == "https:"


## WebSocket URL for a server address: a full ws:// / wss:// URL is used as
## typed; otherwise wss when the page itself is on HTTPS, ws otherwise.
static func _ws_url(addr: String, port: int) -> String:
	if addr.contains("://"):
		return addr
	return "%s://%s:%d" % ["wss" if _page_is_https() else "ws", addr, port]


## Whether passwords sent to this server travel encrypted. Desktop builds
## always use DTLS; browsers only with wss:// (plain ws:// is for home
## networks).
func connection_encrypted() -> bool:
	if not use_websocket():
		return true
	var a := _split_address()
	return _ws_url(a[0], a[1]).begins_with("wss://")


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
	# Encrypt every connection (passwords and tokens included) with DTLS.
	err = peer.host.dtls_server_setup(_server_tls())
	if err != OK:
		print("ERROR: could not set up encryption (error %d)" % err)
		peer.close()
		return err
	# One SceneMultiplayer serves both transports: ENet for the downloadable
	# game, WebSocket for the browser game.
	var multi := MultiPeer.new()
	multi.max_peers = MAX_SERVER_PEERS
	multi.add_transport(peer)
	var ws := _start_websocket()
	if ws:
		multi.add_transport(ws)
	mp.multiplayer_peer = multi
	role = Role.SERVER
	my_id = 1
	_start_cert_service(port + CERT_PORT_OFFSET)
	_start_web_host()
	_load_config()
	if OS.get_environment("UPDATE_URL") != "":
		update_url = OS.get_environment("UPDATE_URL").left(300)
	accounts = AccountStore.new()
	_log("Accounts: %d (passwords stored as salted PBKDF2-SHA256 hashes)" % accounts.count())
	ranked_pool = RankedPool.new()
	ranked_pool.load_file()
	unit_stats = UnitStats.new()
	unit_stats.load_file()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--battle-gold="):
			rewards["battle_mult"] = maxf(0.0, float(arg.get_slice("=", 1)))
		elif arg.begins_with("--draft-gold="):
			rewards["draft_mult"] = maxf(0.0, float(arg.get_slice("=", 1)))
	_log("Autobat Legions %s server (protocol %s) listening on UDP port %d" % [build_version(), game_version, port])
	_log("Gold: battles x%s, draft x%s, draft payouts %s. Type 'help' for commands." % [rewards["battle_mult"], rewards["draft_mult"], rewards["draft_table"]])
	_stdin_thread = Thread.new()
	_stdin_thread.start(_read_stdin)
	return OK


# --- server console -----------------------------------------------------------

## Runs on its own thread: reads admin commands typed into the server window.
func _read_stdin() -> void:
	while true:
		var line := OS.read_string_from_stdin().strip_edges()
		if line == "":
			OS.delay_msec(200)  # stdin closed or empty line
			continue
		_stdin_mutex.lock()
		_stdin_lines.append(line)
		_stdin_mutex.unlock()


func _poll_console() -> void:
	if role != Role.SERVER:
		return
	_stdin_mutex.lock()
	var lines := _stdin_lines.duplicate()
	_stdin_lines.clear()
	_stdin_mutex.unlock()
	for line in lines:
		run_command(line)
	_poll_admin_inbox()


## Commands can also be dropped into a file, which server/admin.sh does with
## `docker exec` (no need to attach to the console). Each request is
## "<id>\t<command>" in admin/commands.txt; the reply goes to
## admin/replies.txt between "### <id>" and "### end <id>".
const ADMIN_DIR := "user://admin"
var _admin_check_msec := 0


func _poll_admin_inbox() -> void:
	var now := Time.get_ticks_msec()
	if now - _admin_check_msec < 500:
		return
	_admin_check_msec = now
	var inbox := ADMIN_DIR + "/commands.txt"
	if not FileAccess.file_exists(inbox):
		return
	var text := FileAccess.get_file_as_string(inbox)
	DirAccess.remove_absolute(inbox)
	if text.strip_edges() == "":
		return
	var replies := ADMIN_DIR + "/replies.txt"
	var keep := FileAccess.file_exists(replies) and FileAccess.open(replies, FileAccess.READ).get_length() < 1 << 20
	var out := FileAccess.open(replies, FileAccess.READ_WRITE if keep else FileAccess.WRITE)
	if out == null:
		return
	out.seek_end()
	for line in text.split("\n", false):
		var id := line.get_slice("\t", 0).strip_edges()
		var cmd := line.substr(id.length() + 1).strip_edges() if line.contains("\t") else line.strip_edges()
		var reply := run_command(cmd) if cmd != "" else ""
		out.store_string("### %s\n%s\n### end %s\n" % [id, reply, id])
	out.close()


## Execute one admin command and print the result. Also usable from code/tests.
func run_command(line: String) -> String:
	var a := line.strip_edges().split(" ", false)
	var out := ""
	if a.is_empty():
		return out
	match a[0].to_lower():
		"help":
			out = """Commands:
  status                          players online, open rooms, gold settings
  rooms                           list rooms
  gold                            show gold settings
  gold battle <multiplier>        gold from every battle, e.g. 'gold battle 1.5'
  gold draft <multiplier>         Legion Draft finishing gold, e.g. 'gold draft 2'
  gold draft-table <1st> <2nd> <3rd> <rest>   base draft gold by placement
  gold reset                      back to defaults
  units                           list every unit and whether it is locked
  lock <unit> [unit...]           lock units (names or ids)
  unlock <unit> [unit...]         unlock units
  regions                         list expedition regions and whether they are locked
  lock region <region> [...]      lock expedition regions (names or ids)
  unlock region <region> [...]    unlock expedition regions
  lock new / unlock new           the unreleased set: units and regions locked by default
  unlock all                      every unit and region
  lock reset                      back to the defaults (the new units and regions locked)
  ranked                          how many player armies are saved for ranked matchmaking
  ranked clear                    delete all saved ranked armies
  ranked range <n>                only match players within n rating (default 200)
  say <message>                   show a message to every connected player
  drops                           show drop chance settings
  drops unit <rarity> <mult>      scale unit drop chances, e.g. 'drops unit legendary 0.25'
  drops trinket <rarity> <mult>   scale trinket hunt chances, e.g. 'drops trinket epic 2'
  drops pity <rarity> <n>         guarantee rare/epic/legendary every n expeditions (0 = off)
  drops reset                     back to the defaults
  difficulty                      show ranked opponent and challenge difficulty
  difficulty hard 1.5 [150]       a ranked tier's power vs your rating's [and rating offset];
                                  tiers: easy, even, hard
  difficulty ranked 1.2           scale all three ranked tiers' power
  difficulty challenges 1.3       challenge enemies' HP and damage (1 = as designed)
  difficulty training 1000 2500 [4 10]
                                  rating from training bands: in full below the first
                                  rating, divided by 4 from it, by 10 from the second
  difficulty reset                back to the defaults
  update-url <url>                where out-of-date games download the new version
  unitstats                       unit use and win rates in ranked and Legion Draft
                                  (this patch); options: ranked|draft, use|win|games|name,
                                  all, a row limit, a patch e.g. 'unitstats draft win 20'
  unitstats patches               patches with recorded stats
  unitstats csv [patch]           save a spreadsheet of a patch's stats
  unitstats reset [patch]         delete a patch's stats (default: this patch)
  accounts                        number of accounts and who is signed in
  accounts reset-password <user>  give a player who forgot their password a new
                                  temporary one (shown once) and sign them out
  player <user>                   a player's stats, units, trinkets and progress
  player <user> set <stat> <n>    rating, gold, maps, wins, losses, draft_wins, draft_played
  player <user> add <stat> <n>    add to a stat (a minus number takes away)
  player <user> name <new name>   change their commander name
  player <user> unit <unit> [level <n>] [tier <n>] [shards <n>]
                                  give a unit, or change one they own
  player <user> unit <unit> remove   take a unit away
  player <user> units all [level <n>] [tier <n>]   give every open unit
  player <user> trinket <trinket> [remove]   give (or take) a trinket
  player <user> trinkets all|none give every trinket / take them all
  player <user> challenge <id>|all [remove]   mark challenges cleared (or not)
  player <user> reset confirm     start their profile over (keeps the account)
  Changes are saved at once and sent to the player if they're online."""
		"unitstats":
			out = _unitstats_command(a.slice(1))
		"status":
			out = "%d players online, %d rooms. %s" % [_names.size(), _rooms.size(), _gold_text()]
			if mp.multiplayer_peer is MultiPeer and (mp.multiplayer_peer as MultiPeer).transport_count() > 1:
				var mpeer := mp.multiplayer_peer as MultiPeer
				out += " Connections: %d game app, %d browser." % [mpeer.peers_on(0), mpeer.peers_on(1)]
		"rooms":
			var lines: Array = []
			for c in _rooms:
				var r: MatchRoom = _rooms[c]
				lines.append("  %s  %s  %d/%d players  round %d%s" % [c, r.phase, r.players.size(), int(r.settings["max_players"]), r.round_num, "  (quick)" if r.quick else ""])
			out = "No rooms." if lines.is_empty() else "\n".join(PackedStringArray(lines))
		"gold":
			if a.size() == 1:
				out = _gold_text()
			elif a[1] == "reset":
				_set_rewards(DEFAULT_REWARDS.duplicate(true))
				out = "Gold reset. " + _gold_text()
			elif a[1] == "battle" and a.size() >= 3 and a[2].is_valid_float():
				rewards["battle_mult"] = clampf(float(a[2]), 0.0, 100.0)
				_set_rewards(rewards)
				out = "Battle gold is now x%s. " % rewards["battle_mult"]
			elif a[1] == "draft" and a.size() >= 3 and a[2].is_valid_float():
				rewards["draft_mult"] = clampf(float(a[2]), 0.0, 100.0)
				_set_rewards(rewards)
				out = "Draft gold is now x%s. " % rewards["draft_mult"]
			elif a[1] == "draft-table" and a.size() >= 3:
				var table: Array = []
				for i in range(2, a.size()):
					if a[i].is_valid_int():
						table.append(clampi(int(a[i]), 0, 1000000))
				if table.is_empty():
					out = "Usage: gold draft-table <1st> <2nd> <3rd> <rest>"
				else:
					rewards["draft_table"] = table
					_set_rewards(rewards)
					out = "Draft payouts are now %s (last value applies to every lower place). " % [table]
			else:
				out = "Usage: gold | gold battle <x> | gold draft <x> | gold draft-table <1st> <2nd> ... | gold reset"
		"units":
			var lines: Array = []
			for id in GameData.unit_ids_sorted():
				lines.append("  %-22s %-10s %s" % [id, GameData.UNITS[id]["rarity"], "LOCKED" if UnitLocks.is_locked(id) else "open"])
			out = "\n".join(PackedStringArray(lines)) + "\n%d of %d units locked." % [UnitLocks.locked_list().size(), GameData.UNITS.size()]
		"ranked":
			if a.size() >= 2 and a[1].to_lower() == "range":
				if a.size() == 3 and a[2].is_valid_int():
					ranked_range = clampi(int(a[2]), 10, 5000)
					_save_config()
					out = "Ranked players are now matched within %d rating of each other." % ranked_range
				else:
					out = "Ranked range: %d. Usage: ranked range <rating points>, e.g. 'ranked range 150'" % ranked_range
			elif ranked_pool == null:
				out = "Ranked pool only exists on the dedicated server."
			elif a.size() >= 2 and a[1].to_lower() == "clear":
				ranked_pool.entries.clear()
				ranked_pool.save_file()
				out = "Ranked pool cleared."
			else:
				out = ranked_pool.stats() + " Match range: within %d rating." % ranked_range
		"regions":
			var lines: Array = []
			for rid in GameData.REGIONS:
				lines.append("  %-16s %-20s %s" % [rid, GameData.REGIONS[rid]["name"], "LOCKED" if UnitLocks.is_region_locked(rid) else "open"])
			out = "\n".join(PackedStringArray(lines)) + "\n%d of %d regions locked." % [UnitLocks.locked_regions().size(), GameData.REGIONS.size()]
		"lock", "unlock":
			if a.size() >= 2 and a[1].to_lower() in ["region", "regions"]:
				out = _region_lock_command(a[0].to_lower() == "lock", a.slice(2))
			else:
				out = _lock_command(a[0].to_lower() == "lock", a.slice(1))
		"say":
			var msg := line.strip_edges().substr(4).strip_edges().left(200)
			for id in _names:
				_deliver(id, "notice", ["[Server] " + msg])
			out = "Sent: " + msg
		"accounts":
			out = _account_command(a)
		"player":
			out = _player_command(a.slice(1))
		"update-url":
			if a.size() == 2 and (a[1].begins_with("https://") or a[1].begins_with("http://")):
				update_url = a[1].left(300)
				_save_config()
				out = "Out-of-date games will be sent to %s" % update_url
			elif a.size() == 2 and a[1].to_lower() in ["none", "off", "clear"]:
				update_url = ""
				_save_config()
				out = "No download link: out-of-date games are just told to update."
			else:
				out = "Download link for out-of-date games: %s. Usage: update-url <https://...> | update-url none" % (update_url if update_url != "" else "(none)")
		"drops":
			out = _drops_command(a)
		"difficulty":
			out = _difficulty_command(a)
		_:
			out = "Unknown command '%s'. Type 'help'." % a[0]
	_log(out)
	return out


## lock/unlock: unit ids or names ("Storm Dragon" -> storm_dragon), or the
## keywords "new" (units locked by default), "all", and "reset" (lock only).
func _unitstats_command(args: PackedStringArray) -> String:
	if unit_stats == null:
		return "Unit stats are kept by the dedicated server only."
	var sub := args[0].to_lower() if not args.is_empty() else ""
	var patch := args[1] if args.size() > 1 else UnitStats.current_patch()
	match sub:
		"patches":
			var list := unit_stats.patches()
			if list.is_empty():
				return "No unit stats recorded yet."
			var parts: Array = []
			for p in list:
				parts.append("%s (%d ranked, %d draft armies)" % [p, unit_stats.armies(p, "ranked"), unit_stats.armies(p, "draft")])
			return "Patches with unit stats: " + ", ".join(PackedStringArray(parts)) + ". This server is patch %s." % UnitStats.current_patch()
		"reset":
			unit_stats.save_if_due(true)
			return "Deleted the unit stats of patch %s." % patch if unit_stats.reset(patch) else "No unit stats for patch %s." % patch
		"csv":
			unit_stats.save_if_due(true)
			var path := unit_stats.write_csv(patch)
			return "Saved %s" % path if path != "" else "Couldn't write the spreadsheet."
	return unit_stats.report(args)


func _lock_command(lock: bool, words: PackedStringArray) -> String:
	if words.is_empty():
		return "Usage: lock <unit> [unit...] | unlock <unit> [unit...] | lock new | unlock new | unlock all | lock reset"
	var targets: Array = []
	var unknown: Array = []
	var joined := " ".join(words).to_lower()
	if joined == "reset" and lock:
		UnitLocks.set_locked_list(UnitLocks.defaults())
		UnitLocks.set_locked_regions(UnitLocks.default_regions())
		_locks_changed()
		return "Locks reset to defaults: %d units and %d regions locked." % [UnitLocks.locked_list().size(), UnitLocks.locked_regions().size()]
	var region_note := ""
	if joined == "all":
		targets = GameData.UNITS.keys()
		for rid in GameData.REGIONS:
			UnitLocks.set_region_locked(rid, lock)
		region_note = " All %d regions %s." % [GameData.REGIONS.size(), "locked" if lock else "unlocked"]
	elif joined == "new":
		targets = UnitLocks.defaults()
		for rid in UnitLocks.default_regions():
			UnitLocks.set_region_locked(rid, lock)
		region_note = " The %d new regions are %s." % [UnitLocks.default_regions().size(), "locked" if lock else "unlocked"]
	else:
		var whole := joined.replace(" ", "_")
		if GameData.UNITS.has(whole) or _unit_by_name(joined) != "":
			targets.append(whole if GameData.UNITS.has(whole) else _unit_by_name(joined))
		else:
			for w in words:
				var id := w.to_lower()
				if not GameData.UNITS.has(id):
					id = _unit_by_name(w)
				if id == "":
					unknown.append(w)
				else:
					targets.append(id)
	for id in targets:
		UnitLocks.set_locked(id, lock)
	# Unlocking a unit also opens the expedition regions it drops in, so it
	# can actually be found (those regions only ever offer unlocked units).
	if not lock and joined != "all" and joined != "new":
		var opened: Array = []
		for rid in GameData.REGIONS:
			if not UnitLocks.is_region_locked(rid):
				continue
			for id in targets:
				if GameData.REGIONS[rid]["drops"].has(id):
					UnitLocks.set_region_locked(rid, false)
					opened.append(GameData.REGIONS[rid]["name"])
					break
		if not opened.is_empty():
			region_note = " Also unlocked region%s %s so %s can be found." % ["" if opened.size() == 1 else "s", ", ".join(PackedStringArray(opened)), "it" if targets.size() == 1 else "they"]
	if not targets.is_empty():
		_locks_changed()
	var out := "%s %d unit%s. %d of %d units are now locked.%s" % ["Locked" if lock else "Unlocked", targets.size(), "" if targets.size() == 1 else "s", UnitLocks.locked_list().size(), GameData.UNITS.size(), region_note]
	if not unknown.is_empty():
		out += " Unknown: %s (type 'units' for the list)." % ", ".join(PackedStringArray(unknown))
	return out


func _region_lock_command(lock: bool, words: PackedStringArray) -> String:
	if words.is_empty():
		return "Usage: lock region <region> [...] | unlock region <region> [...]  (type 'regions' for the list)"
	var targets: Array = []
	var joined := " ".join(words).to_lower()
	var whole := joined.replace(" ", "_").replace("'", "")
	for rid in GameData.REGIONS:
		var nm := str(GameData.REGIONS[rid]["name"]).to_lower()
		if rid == whole or nm == joined or nm.replace("'", "") == joined.replace("'", ""):
			targets.append(rid)
	var unknown: Array = []
	if targets.is_empty():
		for w in words:
			var id := w.to_lower()
			if GameData.REGIONS.has(id):
				targets.append(id)
			else:
				unknown.append(w)
	for rid in targets:
		UnitLocks.set_region_locked(rid, lock)
	if not targets.is_empty():
		_locks_changed()
	var out := "%s %d region%s. %d of %d regions are now locked." % ["Locked" if lock else "Unlocked", targets.size(), "" if targets.size() == 1 else "s", UnitLocks.locked_regions().size(), GameData.REGIONS.size()]
	if not unknown.is_empty():
		out += " Unknown: %s (type 'regions' for the list)." % ", ".join(PackedStringArray(unknown))
	elif not lock:
		for rid in targets:
			if GameData.region_drops(rid).is_empty():
				out += " Note: every unit in %s is still locked, so it can't be explored until some are unlocked." % GameData.REGIONS[rid]["name"]
	return out


func _unit_by_name(text: String) -> String:
	var t := text.to_lower().strip_edges()
	for id in GameData.UNITS:
		if str(GameData.UNITS[id]["name"]).to_lower() == t:
			return id
	return ""


## Save the new locks and push them to every connected player. Matches in
## progress pick them up at their next shop phase.
func _locks_changed() -> void:
	_save_config()
	for id in _names:
		_deliver(id, "locks", [UnitLocks.locked_list(), UnitLocks.locked_regions()])


func _drops_command(a: PackedStringArray) -> String:
	var usage := "Usage: drops | drops unit <rarity> <multiplier> | drops trinket <rarity> <multiplier> | drops pity <rare|epic|legendary> <expeditions, 0 = off> | drops reset"
	if a.size() == 1:
		return DropRates.describe()
	var what := a[1].to_lower()
	if what == "reset" and a.size() == 2:
		DropRates.reset()
	elif what in ["unit", "units", "trinket", "trinkets"] and a.size() == 4:
		var r := a[2].to_lower()
		if r not in DropRates.RARITIES or not a[3].is_valid_float():
			return usage
		var v := clampf(float(a[3]), 0.0, DropRates.MAX_MULT)
		if what.begins_with("unit"):
			DropRates.unit_mult[r] = v
		else:
			DropRates.trinket_mult[r] = v
	elif what == "pity" and a.size() == 4:
		var r := a[2].to_lower()
		if r not in DropRates.PITY_RARITIES or not a[3].is_valid_int():
			return usage
		DropRates.pity[r] = clampi(int(a[3]), 0, DropRates.MAX_PITY)
	else:
		return usage
	_drops_changed()
	return "Drop chances updated. " + DropRates.describe()


## Save the drop settings and push them to every connected player.
func _drops_changed() -> void:
	_save_config()
	for id in _names:
		_deliver(id, "drops", [DropRates.to_dict()])


func _difficulty_command(a: PackedStringArray) -> String:
	var usage := "Usage: difficulty | difficulty easy|even|hard <power x> [rating offset] | difficulty ranked <factor> | difficulty challenges <x> | difficulty training <slow from> <slower from> [divisor] [later divisor] | difficulty reset"
	if a.size() == 1:
		return Difficulty.describe()
	var what := a[1].to_lower()
	var i := Difficulty.tier_index(what)
	if what == "reset" and a.size() == 2:
		Difficulty.reset()
	elif i >= 0 and a.size() in [3, 4] and a[2].is_valid_float() and (a.size() == 3 or a[3].is_valid_int()):
		Difficulty.set_tier(i, float(a[2]), int(a[3]) if a.size() == 4 else int(Difficulty.tiers[i][1]))
	elif what == "ranked" and a.size() == 3 and a[2].is_valid_float() and float(a[2]) > 0.0:
		for k in Difficulty.tiers.size():
			Difficulty.set_tier(k, float(Difficulty.tiers[k][0]) * float(a[2]), int(Difficulty.tiers[k][1]))
	elif what in ["challenge", "challenges"] and a.size() == 3 and a[2].is_valid_float():
		Difficulty.challenge_mult = clampf(float(a[2]), Difficulty.MIN_CHALLENGE, Difficulty.MAX_CHALLENGE)
	elif what == "training" and a.size() == 2:
		return "Rating from training bands: in full below %d, %s from %d, %s from %d. Usage: difficulty training <slow from> <slower from> [divisor] [later divisor], e.g. 'difficulty training 1500 3000' or 'difficulty training 1000 2500 4 10'." % [
			Difficulty.train_slow_from, Difficulty.share_text(Difficulty.train_div), Difficulty.train_slow_from, Difficulty.share_text(Difficulty.train_div_late), Difficulty.train_slower_from]
	elif what == "training" and a.size() in [4, 5, 6] and a[2].is_valid_int() and a[3].is_valid_int() and (a.size() < 5 or a[4].is_valid_float()) and (a.size() < 6 or a[5].is_valid_float()):
		Difficulty.set_training(int(a[2]), int(a[3]), float(a[4]) if a.size() >= 5 else -1.0, float(a[5]) if a.size() >= 6 else -1.0)
	else:
		return usage
	_save_config()
	for id in _names:
		_deliver(id, "difficulty", [Difficulty.to_dict()])
	return "Difficulty updated. " + Difficulty.describe()


func _gold_text() -> String:
	return "Gold: battles x%s, draft x%s, draft payouts %s." % [rewards["battle_mult"], rewards["draft_mult"], rewards["draft_table"]]


## Apply new reward settings: save them and tell every connected player.
func _set_rewards(new_rewards: Dictionary) -> void:
	for k in new_rewards:
		rewards[k] = new_rewards[k]
	_save_config()
	for id in _names:
		_deliver(id, "rewards", [{"battle_mult": rewards["battle_mult"]}])


func _load_config() -> void:
	if not FileAccess.file_exists(CONFIG_PATH):
		return
	var f := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	var parsed = JSON.parse_string(f.get_as_text()) if f else null
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	if typeof(parsed.get("locked")) == TYPE_ARRAY:
		UnitLocks.set_locked_list(parsed["locked"])
	if typeof(parsed.get("locked_regions")) == TYPE_ARRAY:
		UnitLocks.set_locked_regions(parsed["locked_regions"])
	if int(parsed.get("locks_version", 1)) < 2:
		# 0.9.5: Badlands Camp is always open, and its units are open by default.
		for id in GameData.REGIONS["badlands"]["drops"]:
			UnitLocks.set_locked(id, false)
		call_deferred("_save_config")
	DropRates.apply(parsed.get("drops", {}))
	Difficulty.apply(parsed.get("difficulty", {}))
	ranked_range = clampi(int(parsed.get("ranked_range", DEFAULT_RANKED_RANGE)), 10, 5000)
	update_url = str(parsed.get("update_url", update_url)).left(300)
	var r: Dictionary = parsed.get("rewards", {})
	rewards["battle_mult"] = clampf(float(r.get("battle_mult", 1.0)), 0.0, 100.0)
	rewards["draft_mult"] = clampf(float(r.get("draft_mult", 1.0)), 0.0, 100.0)
	var table: Array = []
	for v in r.get("draft_table", DEFAULT_REWARDS["draft_table"]):
		table.append(clampi(int(v), 0, 1000000))
	if not table.is_empty():
		rewards["draft_table"] = table


func _save_config() -> void:
	var f := FileAccess.open(CONFIG_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"rewards": rewards, "locked": UnitLocks.locked_list(), "locked_regions": UnitLocks.locked_regions(), "locks_version": 2, "drops": DropRates.to_dict(), "difficulty": Difficulty.to_dict(), "ranked_range": ranked_range, "update_url": update_url}, "\t"))


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


## LAN matches and live duels connect players directly over UDP (ENet),
## which browsers can't do. Online play through the server works everywhere.
static func lan_supported() -> bool:
	return not OS.has_feature("web")


## Legion Draft against bots on this device: the same authoritative room a
## LAN host runs, but with no network at all (works in the browser too).
func host_solo(pname: String, new_settings: Dictionary) -> Error:
	disconnect_all(true)
	var s := MatchRoom.clean_settings(new_settings)
	mp.multiplayer_peer = OfflineMultiplayerPeer.new()
	role = Role.HOST
	solo = true
	my_id = 1
	player_name = pname
	_reset_client_state()
	_names[1] = pname
	_create_room("LAN", s, false, false)
	_join_room(1, "LAN", pname)
	for i in mini(int(s["max_players"]), 8) - 1:
		add_bot()
	status.emit("Solo match against bots: add or remove bots, then press Start.")
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
	if logged_in and not session_active():
		status.emit("Reconnecting to the server... try again in a moment.")
		return
	if role == Role.CLIENT and online and phase != "connecting" and not _sync_only and not _ranked_only:
		if phase == "lobby" and req[0] != "_rq_list":
			_request("_rq_leave_room", [])
			_reset_client_state()
			phase = "online"
		_send_request(req)
		return
	var a := _split_address()
	_connect_to(a[0], a[1], pname, true, req)


func _send_request(req: Array) -> void:
	_request(str(req[0]), req.slice(1))


func _connect_to(address: String, port: int, pname: String, is_online: bool, pending: Array) -> Error:
	if is_online and not _have_cert(address, port):
		status.emit("Contacting the server...")
		_ensure_cert(address, port, func(ok: bool):
			if ok:
				_connect_to(address, port, pname, is_online, pending)
			else:
				status.emit("Could not reach the server at %s:%d." % [address, port]))
		return OK
	disconnect_all(true)
	var peer: MultiplayerPeer
	if is_online:
		peer = _server_client_peer(address, port)   # dedicated server
		if peer == null:
			status.emit("Could not connect to %s:%d." % [address, port])
			return FAILED
	else:
		var lan := ENetMultiplayerPeer.new()
		var err := lan.create_client(address, port)
		if err != OK:
			status.emit("Could not connect to %s:%d (error %d)." % [address, port, err])
			return err
		peer = lan
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
	if not _auth_request.is_empty():
		var req := _auth_request
		_auth_request = []   # don't keep the password around
		_request(str(req[0]), req.slice(1))
		return
	if _ranked_only:
		_request("_rq_ranked", _ranked_request)
		return
	if _sync_only:
		_request("_rq_sync", [game_version])
		return
	_request("_rq_hello", [player_name, game_version])


# --- ranked opponents ---------------------------------------------------------

## Save this army on the server (with the current rating) and ask for armies
## other players saved at a similar rating. Answers with `ranked_opponents`.
func request_ranked_opponents(pid: String, pname: String, rating: int, code: String) -> void:
	var req: Array = [game_version, pid, pname, rating, code]
	_awaiting_ranked = true
	_ranked_deadline = Time.get_ticks_msec() + 6000
	if role == Role.CLIENT and online and phase not in ["connecting", "syncing"] and not _sync_only and not _ranked_only:
		_request("_rq_ranked", req)  # already connected to the server
		return
	if logged_in:
		_ranked_failed()  # signed in but reconnecting
		return
	if _sync_only:
		disconnect_all(true)
	if role != Role.NONE:
		_ranked_failed()  # busy with a LAN match: use generated opponents
		return
	var a := _split_address()
	if not _have_cert(a[0], a[1]):
		_ensure_cert(a[0], a[1], func(ok: bool):
			if ok and _awaiting_ranked:
				request_ranked_opponents(pid, pname, rating, code)
			else:
				_ranked_failed())
		return
	var peer := _server_client_peer(a[0], a[1])
	if peer == null:
		_ranked_failed()
		return
	mp.multiplayer_peer = peer
	role = Role.CLIENT
	online = true
	_ranked_only = true
	_ranked_request = req
	phase = "syncing"


func _ranked_failed() -> void:
	if _awaiting_ranked:
		_awaiting_ranked = false
		ranked_opponents.emit([])
	if _ranked_only:
		_hang_up_later()


@rpc("any_peer", "reliable")
func _rq_ranked(version: String, pid: String, pname: String, rating: int, code: String) -> void:
	if role != Role.SERVER or ranked_pool == null:
		return
	var id := _sender()
	if not _allow(id):
		return
	if version != game_version:
		_deliver(id, "error", ["Your game is out of date (you have %s, the server runs %s). Please update." % [version.left(32), game_version]])
		return
	if _sessions.has(id):
		# Signed in: the server uses the account's own army and rating.
		_deliver(id, "ranked_offers", [_ranked_offer_for(id)])
		return
	if ranked_pool.add(pid, pname, rating, code):
		ranked_pool.save_file()
	var out: Array = []
	for e in ranked_pool.find(clampi(rating, 0, 10000) + Army.RANKED_SEARCH_BIAS, pid.left(40), 3, ranked_range):
		out.append({"name": e["name"], "rating": e["rating"], "code": e["code"], "saved_at": e["saved_at"]})
	_deliver(id, "ranked", [out])


@rpc("authority", "reliable")
func _rc_ranked(list: Array) -> void:
	_awaiting_ranked = false
	ranked_opponents.emit(list)
	if _ranked_only:
		_hang_up_later()


## Background check-in: fetch the server's unit/region locks and gold
## settings, then disconnect. Lets offline play (expeditions, collection,
## ranked) follow what the server admin unlocked. Silent if unreachable.
func sync_from_server() -> void:
	if role != Role.NONE or logged_in or OS.get_cmdline_user_args().has("--server"):
		return
	var a := _split_address()
	if not _have_cert(a[0], a[1]):
		_ensure_cert(a[0], a[1], func(ok: bool):
			if ok:
				sync_from_server())
		return
	var peer := _server_client_peer(a[0], a[1])
	if peer == null:
		return
	mp.multiplayer_peer = peer
	role = Role.CLIENT
	online = true
	_sync_only = true
	_sync_deadline = Time.get_ticks_msec() + 8000
	phase = "syncing"


@rpc("any_peer", "reliable")
func _rq_sync(version: String) -> void:
	if role != Role.SERVER:
		return
	var id := _sender()
	if version != game_version:
		_deliver(id, "error", ["Your game is out of date (you have %s, the server runs %s). Please update." % [version.left(32), game_version]])
		return
	_deliver(id, "synced", [{"rewards": {"battle_mult": rewards["battle_mult"]}, "locked": UnitLocks.locked_list(), "locked_regions": UnitLocks.locked_regions(), "drops": DropRates.to_dict(), "difficulty": Difficulty.to_dict(),
		"leaderboard": accounts.leaderboard(LEADERBOARD_SIZE) if accounts else []}])


@rpc("authority", "reliable")
func _rc_synced(info: Dictionary) -> void:
	if typeof(info.get("leaderboard")) == TYPE_ARRAY:
		_rc_leaderboard(info["leaderboard"], {})
	_rc_rewards(info.get("rewards", {}))
	_rc_locks(info.get("locked", []), info.get("locked_regions", []))
	if typeof(info.get("drops")) == TYPE_DICTIONARY:
		_rc_drops(info["drops"])
	if typeof(info.get("difficulty")) == TYPE_DICTIONARY:
		_rc_difficulty(info["difficulty"])
	if _sync_only:
		_hang_up_later()


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
	var was := role != Role.NONE and not _sync_only and not _ranked_only
	_sync_only = false
	_ranked_only = false
	_session_live = false
	_auth_waiting = false
	_auth_request = []
	_sessions.clear()
	_ranked_offers.clear()
	solo = false
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
	if version != game_version:
		_deliver(id, "error", ["Version mismatch: you have %s, the host runs %s. Please update the game." % [version.left(32), game_version]])
		return
	var nm := pname.strip_edges().left(24)
	_names[id] = nm if nm != "" else "Commander"
	if role == Role.HOST:
		var err := _join_room(id, "LAN", _names[id])
		if err != "":
			_deliver(id, "kicked", [err])
		return
	_log("%s connected (%d online)" % [_names[id], _names.size()])
	_deliver(id, "welcome", [{"rooms": _rooms.size(), "players": _names.size(), "rewards": {"battle_mult": rewards["battle_mult"]}, "locked": UnitLocks.locked_list(), "locked_regions": UnitLocks.locked_regions(), "drops": DropRates.to_dict(), "difficulty": Difficulty.to_dict()}])


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
	r.rewards = rewards
	r.outbox.connect(_deliver)
	r.room_log.connect(_log)
	if role == Role.SERVER:
		r.finished.connect(_credit_draft)   # draft rewards go to signed-in accounts
		r.battle_recorded.connect(func(squads: Array, score: float): unit_stats.record("draft", squads, score))
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
	elif mp.multiplayer_peer is MultiPeer and not (mp.multiplayer_peer as MultiPeer).is_open(id):
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
	_end_session(id)
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
	_rc_rewards(info.get("rewards", {}))
	if typeof(info.get("locked")) == TYPE_ARRAY:
		_rc_locks(info["locked"], info.get("locked_regions", UnitLocks.locked_regions()))
	if typeof(info.get("drops")) == TYPE_DICTIONARY:
		_rc_drops(info["drops"])
	if typeof(info.get("difficulty")) == TYPE_DICTIONARY:
		_rc_difficulty(info["difficulty"])
	status.emit("Connected to the server (%d players online, %d matches)." % [int(info.get("players", 0)), int(info.get("rooms", 0))])
	online_changed.emit()
	lobby_changed.emit()
	if not _pending_online.is_empty():
		var req := _pending_online
		_pending_online = []
		_send_request(req)


## The server's gold settings for battles; kept in the profile so the
## economy the server admin chose applies to all your battles.
@rpc("authority", "reliable")
func _rc_rewards(r: Dictionary) -> void:
	if r.has("battle_mult"):
		Profile.settings["server_rewards"] = {"battle_mult": clampf(float(r["battle_mult"]), 0.0, 100.0)}
		Profile.save_settings()
		Profile.logic.gold_mult = Profile.battle_gold_mult()
		Profile.changed.emit()


## The server's unit locks. Remembered in the device settings so they also
## apply to expeditions, ranked battles and army codes while offline.
## The server's drop chance settings, remembered like the unit locks so
## offline expeditions and hunts follow them too.
@rpc("authority", "reliable")
func _rc_drops(d: Dictionary) -> void:
	DropRates.apply(d)
	Profile.settings["drop_rates"] = DropRates.to_dict()
	Profile.save_settings()
	Profile.changed.emit()


## The server's fight difficulty, remembered like the drop chances so offline
## ranked opponents and challenges follow it too.
@rpc("authority", "reliable")
func _rc_difficulty(d: Dictionary) -> void:
	Difficulty.apply(d)
	Profile.settings["difficulty"] = Difficulty.to_dict()
	Profile.save_settings()
	Profile.changed.emit()


@rpc("authority", "reliable")
func _rc_locks(list: Array, regions: Array) -> void:
	UnitLocks.set_locked_list(list)
	UnitLocks.set_locked_regions(regions)
	Profile.settings["unit_locks"] = UnitLocks.locked_list()
	Profile.settings["region_locks"] = UnitLocks.locked_regions()
	Profile.save_settings()
	Profile.changed.emit()


@rpc("authority", "reliable")
func _rc_notice(text: String) -> void:
	status.emit(text.left(220))


@rpc("authority", "reliable")
func _rc_error(text: String) -> void:
	status.emit(text)
	if _ranked_only or _awaiting_ranked:
		_ranked_failed()
	if _sync_only:
		_hang_up_later()
	elif phase == "connecting":
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
	run = DraftRun.new(0, int(settings.get("slots", DraftData.BOARD_SLOTS)))
	run.lives = int(settings["lives"]) if settings.get("use_lives", true) else 0
	placements = []
	phase = "waiting"
	match_started.emit()


@rpc("authority", "reliable")
func _rc_shop(r: int, seconds: int, state: Dictionary) -> void:
	round_num = r
	turn_deadline_msec = Time.get_ticks_msec() + seconds * 1000 if seconds > 0 else 0
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
	for p in list:
		if int(p["id"]) == my_id and int(p["place"]) > 0:
			Profile.add_draft_reward(int(p.get("gold", 0)), int(p.get("maps", 0)), int(p["place"]))
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

func _notification(what: int) -> void:
	# Stopping the server (window closed, Ctrl+C, docker stop): keep the
	# latest unit stats.
	if (what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE) and unit_stats:
		unit_stats.save_if_due(true)


func _process(delta: float) -> void:
	mp.poll()
	_poll_console()
	if unit_stats:
		unit_stats.save_if_due()
	if _sync_only and Time.get_ticks_msec() > _sync_deadline:
		disconnect_all(true)
	if _awaiting_ranked and Time.get_ticks_msec() > _ranked_deadline:
		_ranked_failed()
	_poll_discovery(delta)
	_poll_cert_fetch()
	if role == Role.SERVER:
		_poll_cert_service()
		if _web_host:
			_web_host.poll()
		_poll_auth_jobs()
		_poll_ranked_jobs()
	_client_session_tick()
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


# ==============================================================================
# Accounts: logins, server-side profiles and server-run ranked battles
# ==============================================================================

const TLS_KEY_PATH := "user://server_tls.key"
const TLS_CERT_PATH := "user://server_tls.crt"
## Ship your server's certificate here (copied from its user data folder) to
## pin it: the game then refuses to talk to any other server at that address.
const PINNED_CERT_PATH := "res://server_cert.crt"
const CERT_CACHE_DIR := "user://server_certs"
const CERT_PORT_OFFSET := 1            # certificate service: UDP SERVER_PORT + 1
const CERT_MAGIC := "AUTOBAT-CERT1"
const CERT_REQUEST_SIZE := 1400
const LOGIN_FAILURE_LIMIT := 5
const LOGIN_LOCKOUT_SEC := 300
const MAX_AUTH_JOBS := 8         # password hashes running at once (~1 s each)

## Login attempt finished: ok, message.
signal login_result(ok: bool, message: String)
## Logged in / logged out / reconnecting changed.
signal session_changed
## A server-run ranked battle finished: {gold, maps, rating, score, ...}.
signal ranked_result(summary: Dictionary)
## The server's leaderboard arrived: top players, and your own rank
## ({rank, of, rating}; empty for guests).
signal leaderboard_received(top: Array, me: Dictionary)

const LEADERBOARD_SIZE := 50

# Client side.
var logged_in := false          # signed in to an account (survives brief disconnects)
var _session_live := false      # connected and authenticated right now
var _session_user := ""
var _session_token := ""
var _remember := false
var _auth_request: Array = []   # login request to send once connected
var _auth_waiting := false      # waiting for the server to answer a login
var _reconnect_at := 0
var last_ranked_summary: Dictionary = {}
var last_leaderboard: Array = []
var last_leaderboard_me: Dictionary = {}
var last_leaderboard_msec := 0
## The server presented a different certificate than the one saved here.
var cert_changed := false
var _last_server: Array = []
var _cert_fetch: PacketPeerUDP
var _cert_fetch_key := ""
var _cert_fetch_target: Array = []
var _cert_waiters: Array = []
var _cert_deadline := 0
var _cert_next_send := 0

# Server side.
var accounts: AccountStore
var _sessions := {}             # peer id -> account key
var _auth_jobs: Array = []      # background password hashing jobs
var _failures := {}             # account key -> {count, until}
var _ranked_offers := {}        # peer id -> offered opponents
var _ranked_jobs: Array = []    # server-simulated ranked battles
var _cert_server: PacketPeerUDP
var _web_host: RefCounted   # WebHost: serves the browser build over HTTP
var _cert_pem: X509Certificate
var _cert_reply := PackedByteArray()
var _cert_window := 0
var _cert_sent := 0


## Close the current client connection after this frame (or `delay` seconds),
## unless a new connection has replaced it by then.
func _hang_up_later(delay: float = 0.0) -> void:
	var peer := mp.multiplayer_peer
	var hang_up := func():
		if mp.multiplayer_peer == peer and role == Role.CLIENT:
			disconnect_all(true)
	if delay > 0.0:
		get_tree().create_timer(delay).timeout.connect(hang_up)
	else:
		hang_up.call_deferred()


func session_active() -> bool:
	return _session_live and role == Role.CLIENT


# --- encryption (DTLS) -----------------------------------------------------------

## Server certificate: generated once (self-signed) and kept in user data.
func _server_tls() -> TLSOptions:
	var crypto := Crypto.new()
	var key := CryptoKey.new()
	var cert := X509Certificate.new()
	var have := FileAccess.file_exists(TLS_KEY_PATH) and FileAccess.file_exists(TLS_CERT_PATH)
	if not have or key.load(TLS_KEY_PATH) != OK or cert.load(TLS_CERT_PATH) != OK:
		key = crypto.generate_rsa(2048)
		cert = crypto.generate_self_signed_certificate(key, "CN=autobat-legions-server,O=Autobat Legions,C=US", "20250101000000", "20450101000000")
		key.save(TLS_KEY_PATH)
		cert.save(TLS_CERT_PATH)
		print("Created a new TLS certificate: %s" % ProjectSettings.globalize_path(TLS_CERT_PATH))
	print("Connections are encrypted (DTLS). Certificate: %s" % ProjectSettings.globalize_path(TLS_CERT_PATH))
	return TLSOptions.server(key, cert)


## The certificate to pin for a server: one bundled with the game, or the one
## saved the first time this device talked to that server (trust on first use,
## like SSH). null if neither exists yet.
func _server_cert(addr: String, port: int) -> X509Certificate:
	var cert := X509Certificate.new()
	if FileAccess.file_exists(PINNED_CERT_PATH) and cert.load(PINNED_CERT_PATH) == OK:
		return cert
	var path := _cert_cache_path(addr, port)
	if FileAccess.file_exists(path) and cert.load(path) == OK:
		return cert
	return null


func _cert_cache_path(addr: String, port: int) -> String:
	var safe := ""
	for c in addr.to_lower():
		safe += c if (c >= "a" and c <= "z") or (c >= "0" and c <= "9") or c in [".", "-"] else "_"
	return "%s/%s_%d.crt" % [CERT_CACHE_DIR, safe, port]


## Forget the saved certificate for the current server (e.g. after the
## server was reinstalled and made a new one).
func forget_server_certificate() -> void:
	var a := _split_address()
	var path := _cert_cache_path(a[0], a[1])
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	cert_changed = false
	status.emit("Saved server certificate forgotten; the next connection will trust the server's current one.")


## A client connection to the dedicated server, encrypted with DTLS and
## pinned to the server's certificate. null on failure (or no certificate yet:
## call _ensure_cert first).
func _server_client_peer(addr: String, port: int) -> MultiplayerPeer:
	if use_websocket():
		return _ws_client_peer(addr, port)
	var cert := _server_cert(addr, port)
	if cert == null:
		return null
	var peer := ENetMultiplayerPeer.new()
	if addr == "" or peer.create_client(addr, port) != OK:
		return null
	# The certificate itself is the trust anchor (the server is self-signed),
	# so its name doesn't have to match the address players typed in.
	if peer.host.dtls_client_setup(addr, TLSOptions.client_unsafe(cert)) != OK:
		peer.close()
		return null
	_last_server = [addr, port]
	return peer


## A WebSocket connection to the server (browser build, or --websocket).
func _ws_client_peer(addr: String, port: int) -> MultiplayerPeer:
	if addr == "":
		return null
	var peer := WebSocketMultiplayerPeer.new()
	peer.inbound_buffer_size = 1 << 20
	peer.outbound_buffer_size = 1 << 20
	peer.max_queued_packets = 4096
	if peer.create_client(_ws_url(addr, port)) != OK:
		return null
	_last_server = [addr, port]
	return peer


## True when we can connect right away (no certificate to fetch first).
func _have_cert(addr: String, port: int) -> bool:
	return use_websocket() or _server_cert(addr, port) != null


## Make sure we have the server's certificate, fetching it the first time.
## Calls `then(ok)` (right away if we already have it).
func _ensure_cert(addr: String, port: int, then: Callable) -> void:
	if addr == "":
		then.call(false)
		return
	if use_websocket():
		then.call(true)  # the browser checks wss:// certificates itself
		return
	if _server_cert(addr, port) != null:
		then.call(true)
		return
	var key := "%s:%d" % [addr, port]
	if _cert_fetch != null and _cert_fetch_key != key:
		_finish_cert_fetch(false)
	_cert_waiters.append(then)
	if _cert_fetch != null:
		return
	var ip := addr if addr.is_valid_ip_address() else IP.resolve_hostname(addr)
	if ip == "":
		_finish_cert_fetch(false)
		return
	_cert_fetch = PacketPeerUDP.new()
	_cert_fetch.set_dest_address(ip, port + CERT_PORT_OFFSET)
	_cert_fetch_key = key
	_cert_fetch_target = [addr, port]
	_cert_deadline = Time.get_ticks_msec() + 4000
	_cert_next_send = 0


func _poll_cert_fetch() -> void:
	if _cert_fetch == null:
		return
	var now := Time.get_ticks_msec()
	while _cert_fetch.get_available_packet_count() > 0:
		var pkt := _cert_fetch.get_packet().get_string_from_utf8()
		if not pkt.begins_with(CERT_MAGIC):
			continue
		var cert := X509Certificate.new()
		if cert.load_from_string(pkt.substr(CERT_MAGIC.length())) != OK:
			continue
		DirAccess.make_dir_recursive_absolute(CERT_CACHE_DIR)
		cert.save(_cert_cache_path(_cert_fetch_target[0], _cert_fetch_target[1]))
		_finish_cert_fetch(true)
		return
	if now > _cert_deadline:
		_finish_cert_fetch(false)
	elif now >= _cert_next_send:
		_cert_next_send = now + 500
		# Padded so the reply is never much bigger than the request (no use
		# as a traffic amplifier).
		var req := (CERT_MAGIC + "?").to_utf8_buffer()
		req.resize(CERT_REQUEST_SIZE)
		_cert_fetch.put_packet(req)


func _finish_cert_fetch(ok: bool) -> void:
	if _cert_fetch:
		_cert_fetch.close()
	_cert_fetch = null
	_cert_fetch_key = ""
	var waiters := _cert_waiters
	_cert_waiters = []
	for w in waiters:
		w.call(ok)


## A connection to the server failed. If the server now presents a different
## certificate than the one saved here, say so instead of silently trusting it.
func _check_cert_changed() -> void:
	if _last_server.is_empty() or use_websocket() or FileAccess.file_exists(PINNED_CERT_PATH):
		return
	var addr: String = _last_server[0]
	var port: int = _last_server[1]
	var saved := _server_cert(addr, port)
	if saved == null:
		return
	var path := _cert_cache_path(addr, port)
	DirAccess.rename_absolute(path, path + ".old")
	_ensure_cert(addr, port, func(ok: bool):
		var fresh := _server_cert(addr, port)
		if ok and fresh != null and fresh.save_to_string() != saved.save_to_string():
			# Keep trusting the old one until the player says otherwise.
			DirAccess.remove_absolute(path)
			DirAccess.rename_absolute(path + ".old", path)
			cert_changed = true
			session_changed.emit()
			status.emit("Warning: the server's security certificate has changed. If the server was reinstalled, choose 'Trust new server certificate' in Settings; otherwise someone may be impersonating it.")
		else:
			if FileAccess.file_exists(path + ".old"):
				if FileAccess.file_exists(path):
					DirAccess.remove_absolute(path + ".old")
				else:
					DirAccess.rename_absolute(path + ".old", path))


# --- server: browsers (WebSocket + web page) ----------------------------------------

## Port from `--name=value`, else the environment variable, else the default.
static func _arg_port(flag: String, env: String, fallback: int) -> int:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(flag + "="):
			return int(arg.get_slice("=", 1))
	var e := OS.get_environment(env)
	return int(e) if e.is_valid_int() else fallback


static func _arg_text(flag: String, env: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(flag + "="):
			return arg.substr(flag.length() + 1)
	return OS.get_environment(env)


## The WebSocket listener for the browser game. Encrypted (wss://) when a
## certificate the browsers trust is given (--ws-cert / --ws-key, e.g. from
## Let's Encrypt, or ws_tls.crt / ws_tls.key in the server's data folder);
## otherwise plain ws://, which is fine on a home network.
func _start_websocket() -> WebSocketMultiplayerPeer:
	var ws_port := _arg_port("--ws-port", "WS_PORT", WS_PORT)
	if ws_port <= 0:
		print("WebSocket listener disabled (--ws-port=0): browsers can't connect.")
		return null
	var tls: TLSOptions = null
	var cert_path := _arg_text("--ws-cert", "WS_CERT")
	var key_path := _arg_text("--ws-key", "WS_KEY")
	if cert_path == "" and FileAccess.file_exists("user://ws_tls.crt"):
		cert_path = "user://ws_tls.crt"
		key_path = "user://ws_tls.key"
	if cert_path != "":
		var cert := X509Certificate.new()
		var key := CryptoKey.new()
		if cert.load(cert_path) != OK or key.load(key_path) != OK:
			print("ERROR: could not load the WebSocket certificate %s / key %s" % [cert_path, key_path])
			return null
		tls = TLSOptions.server(key, cert)
	var ws := WebSocketMultiplayerPeer.new()
	ws.inbound_buffer_size = 1 << 18
	ws.outbound_buffer_size = 1 << 18
	ws.max_queued_packets = 1024
	ws.handshake_timeout = 5.0
	var err := ws.create_server(ws_port, "*", tls)
	if err != OK:
		print("WARNING: could not listen for browsers on TCP port %d (error %d)." % [ws_port, err])
		return null
	if tls:
		print("Browsers connect with wss:// on TCP port %d (encrypted)." % ws_port)
	elif OS.get_environment("WS_BEHIND_TLS_PROXY") == "1":
		print("Browsers connect through the HTTPS proxy (wss://, encrypted), which forwards to TCP port %d." % ws_port)
	else:
		print("Browsers connect with ws:// on TCP port %d. NOT encrypted: fine on your home network; for the internet use --ws-cert/--ws-key (see HOSTING.md)." % ws_port)
	return ws


## Serve the exported web build (export/web) over plain HTTP so devices on
## the network can play in a browser by opening http://<server-ip>:24705.
func _start_web_host() -> void:
	var web_port := _arg_port("--web-port", "WEB_PORT", WEB_PORT)
	var dir := _arg_text("--web-dir", "WEB_DIR")
	if dir == "":
		dir = ProjectSettings.globalize_path("res://export/web")
	if web_port <= 0:
		return
	if not FileAccess.file_exists(dir.path_join("index.html")):
		print("No web build in %s, so the browser version isn't hosted here (build it with tools/build_web, see WEB.md)." % dir)
		return
	_web_host = WebHost.new()
	if _web_host.start(web_port, dir) != OK:
		print("WARNING: could not serve the web build on TCP port %d." % web_port)
		_web_host = null
		return
	print("Browser version: open http://<this computer's address>:%d" % web_port)


# --- server: certificate service -------------------------------------------------

func _start_cert_service(cert_port: int) -> void:
	_cert_pem = X509Certificate.new()
	var pem := ""
	if (_cert_pem as X509Certificate).load(TLS_CERT_PATH) == OK:
		pem = (_cert_pem as X509Certificate).save_to_string()
	_cert_reply = (CERT_MAGIC + pem).to_utf8_buffer()
	_cert_server = PacketPeerUDP.new()
	if _cert_server.bind(cert_port) != OK:
		print("WARNING: could not listen on UDP port %d; new players can't fetch the server certificate." % cert_port)
		_cert_server = null
	else:
		print("Certificate service on UDP port %d (new players fetch the certificate here once)." % cert_port)


func _poll_cert_service() -> void:
	if _cert_server == null:
		return
	var now := Time.get_ticks_msec()
	if now - _cert_window >= 1000:
		_cert_window = now
		_cert_sent = 0
	while _cert_server.get_available_packet_count() > 0:
		var pkt := _cert_server.get_packet()
		if pkt.size() < CERT_REQUEST_SIZE or _cert_sent >= 50:
			continue
		if pkt.slice(0, CERT_MAGIC.length()).get_string_from_utf8() != CERT_MAGIC:
			continue
		_cert_sent += 1
		_cert_server.set_dest_address(_cert_server.get_packet_ip(), _cert_server.get_packet_port())
		_cert_server.put_packet(_cert_reply)


func _split_address() -> Array:
	var addr := server_address().strip_edges()
	var port := WS_PORT if use_websocket() else SERVER_PORT
	if addr.contains("://"):
		return [addr, port]   # a full WebSocket URL
	if addr.count(":") == 1:
		port = int(addr.get_slice(":", 1))
		addr = addr.get_slice(":", 0)
	return [addr, port]


# --- client: logging in -----------------------------------------------------------

func login(username: String, password: String, remember: bool) -> void:
	_start_auth(["_rq_login", game_version, username.strip_edges(), password], remember)


func register(username: String, password: String, remember: bool) -> void:
	_start_auth(["_rq_register", game_version, username.strip_edges(), password], remember)


## Sign in with a saved "remember me" token (no password needed).
func login_with_token(username: String, token: String, remember: bool = true) -> void:
	_start_auth(["_rq_login_token", game_version, username, token], remember)


## Try the token saved by "remember me", if any. Returns false if none.
func try_auto_login() -> bool:
	var saved: Dictionary = Profile.settings.get("account", {})
	if str(saved.get("user", "")) == "" or str(saved.get("token", "")) == "":
		return false
	login_with_token(str(saved["user"]), str(saved["token"]), true)
	return true


func _start_auth(request: Array, remember: bool) -> void:
	_remember = remember
	var a := _split_address()
	if not _have_cert(a[0], a[1]):
		status.emit("Contacting the server...")
		_ensure_cert(a[0], a[1], func(ok: bool):
			if ok:
				_start_auth(request, remember)
			else:
				_auth_failed("Could not reach the server at %s." % server_address()))
		return
	disconnect_all(true)
	var peer := _server_client_peer(a[0], a[1])
	if peer == null:
		login_result.emit(false, "Could not reach the server at %s." % server_address())
		return
	mp.multiplayer_peer = peer
	role = Role.CLIENT
	online = true
	phase = "connecting"
	_auth_request = request
	_auth_waiting = true
	_sync_deadline = Time.get_ticks_msec() + 15000   # give up if nobody answers
	status.emit("Signing in...")


func logout() -> void:
	if session_active():
		_request("_rq_logout", [_session_token])
	logged_in = false
	_session_live = false
	_session_user = ""
	_session_token = ""
	Profile.settings.erase("account")
	Profile.save_settings()
	# Give the logout message a moment to reach the server before hanging up
	# (unless something else has replaced the connection by then).
	_hang_up_later(0.3)
	Profile.leave_online()
	session_changed.emit()


func change_password(old_password: String, new_password: String) -> void:
	if not session_active():
		status.emit("Not connected to the server.")
		return
	_request("_rq_change_password", [old_password, new_password])


## Send a progress action (level up, explore...) for the server to apply.
func profile_action(action: Array) -> void:
	if not session_active():
		status.emit("Not connected to the server; reconnecting...")
		return
	_request("_rq_profile_action", [action])


func request_ranked_battle(index: int) -> void:
	if session_active():
		_request("_rq_ranked_battle", [index])


## Signed in: the server runs the challenge battle and pays the reward.
## The battle opens with `battle_ready`; the result comes as `ranked_result`.
func request_challenge_battle(challenge_id: String) -> void:
	if session_active():
		_request("_rq_challenge_battle", [challenge_id])
	else:
		status.emit("Not connected to the server; reconnecting...")


@rpc("authority", "reliable")
func _rc_login_ok(info: Dictionary) -> void:
	_auth_waiting = false
	logged_in = true
	_session_live = true
	_session_user = str(info.get("username", ""))
	_session_token = str(info.get("token", ""))
	if _remember:
		Profile.settings["account"] = {"user": _session_user, "token": _session_token}
	else:
		Profile.settings.erase("account")
	Profile.save_settings()
	phase = "online"
	_rc_rewards(info.get("rewards", {}))
	_rc_locks(info.get("locked", []), info.get("locked_regions", []))
	if typeof(info.get("drops")) == TYPE_DICTIONARY:
		_rc_drops(info["drops"])
	if typeof(info.get("difficulty")) == TYPE_DICTIONARY:
		_rc_difficulty(info["difficulty"])
	Profile.enter_online(_session_user, info.get("profile", {}))
	status.emit("Signed in as %s." % _session_user)
	login_result.emit(true, "Signed in as %s." % _session_user)
	session_changed.emit()
	online_changed.emit()
	lobby_changed.emit()


@rpc("authority", "reliable")
func _rc_auth_error(message: String) -> void:
	_auth_waiting = false
	if not _session_live:
		# A saved token that no longer works is forgotten.
		if logged_in or Profile.settings.has("account"):
			Profile.settings.erase("account")
			Profile.save_settings()
		if logged_in:
			logged_in = false
			Profile.leave_online()
			session_changed.emit()
		_hang_up_later()
	status.emit(message)
	login_result.emit(false, message)


## A login attempt couldn't reach the server (a saved login is kept for retrying).
func _auth_failed(message: String) -> void:
	disconnect_all(true)
	status.emit(message)
	login_result.emit(false, message)
	if logged_in:
		_reconnect_at = Time.get_ticks_msec() + 10000
		session_changed.emit()


@rpc("authority", "reliable")
func _rc_ranked_offers(list: Array) -> void:
	_awaiting_ranked = false
	ranked_opponents.emit(list)


@rpc("authority", "reliable")
func _rc_session_ended(message: String) -> void:
	# Signed in somewhere else (or the password changed).
	logged_in = false
	_session_live = false
	Profile.settings.erase("account")
	Profile.save_settings()
	_hang_up_later()
	Profile.leave_online()
	status.emit(message)
	session_changed.emit()


@rpc("authority", "reliable")
func _rc_profile(profile_data: Dictionary, event: String, payload: Dictionary) -> void:
	Profile.apply_server_profile(profile_data)
	match event:
		"choice":
			Profile.choice_ready.emit(payload)
		"recruit":
			Profile.recruit_result.emit(payload)
		"trinket_choice":
			Profile.trinket_choice_ready.emit(payload)
		"trinket_result":
			Profile.trinket_result.emit(payload)


@rpc("authority", "reliable")
func _rc_ranked_start(cfg: Dictionary) -> void:
	last_ranked_summary = {}
	battle_ready.emit(cfg)


@rpc("authority", "reliable")
func _rc_ranked_result(summary: Dictionary) -> void:
	last_ranked_summary = summary
	ranked_result.emit(summary)


@rpc("authority", "reliable")
func _rc_password_changed(token: String) -> void:
	_session_token = token
	if Profile.settings.has("account"):
		Profile.settings["account"] = {"user": _session_user, "token": token}
		Profile.save_settings()
	status.emit("Password changed. Other devices have been signed out.")


## Keep a signed-in player connected: reconnect with the session token after
## the connection drops (or after a LAN match ends).
func _client_session_tick() -> void:
	if _auth_waiting and Time.get_ticks_msec() > _sync_deadline:
		_auth_failed("The server didn't answer.")
	if logged_in and role == Role.NONE and _session_token != "" and Time.get_ticks_msec() > _reconnect_at:
		_reconnect_at = Time.get_ticks_msec() + 10000
		login_with_token(_session_user, _session_token, Profile.settings.has("account"))


# --- server: authentication ---------------------------------------------------------

func _auth_ok_version(id: int, version: String) -> bool:
	if version != game_version:
		_deliver(id, "auth_error", ["Your game is out of date (you have %s, the server runs %s). Please update." % [version.left(32), game_version]])
		return false
	return true


func _locked_out(key: String) -> bool:
	var f: Dictionary = _failures.get(key, {})
	return int(f.get("until", 0)) > int(Time.get_unix_time_from_system())


func _note_failure(key: String) -> void:
	var f: Dictionary = _failures.get(key, {"count": 0, "until": 0})
	f["count"] = int(f["count"]) + 1
	if int(f["count"]) >= LOGIN_FAILURE_LIMIT:
		f["until"] = int(Time.get_unix_time_from_system()) + LOGIN_LOCKOUT_SEC
		f["count"] = 0
	_failures[key] = f


func _busy_with_auth(id: int) -> bool:
	if _auth_jobs.size() >= MAX_AUTH_JOBS:
		_deliver(id, "auth_error", ["The server is busy signing other players in. Try again in a few seconds."])
		return true
	for j in _auth_jobs:
		if int(j["peer"]) == id:
			return true
	return false


## Run password hashing on a worker thread so the server keeps running.
func _queue_auth(id: int, kind: String, username: String, work: Callable, holder: Dictionary) -> void:
	_auth_jobs.append({"task": WorkerThreadPool.add_task(work, false, "password hash"), "peer": id, "kind": kind, "user": username, "holder": holder})


@rpc("any_peer", "reliable")
func _rq_register(version: String, username: String, password: String) -> void:
	if role != Role.SERVER or accounts == null:
		return
	var id := _sender()
	if not _allow(id) or not _auth_ok_version(id, version) or _busy_with_auth(id):
		return
	var problem := AccountStore.check_username(username)
	if problem == "":
		problem = Passwords.check_new_password(password)
	if problem == "" and accounts.exists(username):
		problem = "That username is taken."
	if problem != "":
		_deliver(id, "auth_error", [problem])
		return
	var holder := {}
	_queue_auth(id, "register", username.strip_edges(), func(): holder["record"] = Passwords.make_record(password), holder)


@rpc("any_peer", "reliable")
func _rq_login(version: String, username: String, password: String) -> void:
	if role != Role.SERVER or accounts == null:
		return
	var id := _sender()
	if not _allow(id) or not _auth_ok_version(id, version) or _busy_with_auth(id):
		return
	var key := AccountStore.key_of(username)
	if _locked_out(key):
		_deliver(id, "auth_error", ["Too many failed attempts. Try again in a few minutes."])
		return
	var record := accounts.get_record(username)
	var stored: Dictionary = record.get("password", {})
	var holder := {}
	# Unknown usernames are hashed too, so timing doesn't reveal which exist.
	var check := stored if not stored.is_empty() else {"salt": "00000000000000000000000000000000", "hash": "00", "iterations": Passwords.ITERATIONS}
	_queue_auth(id, "login", username.strip_edges(), func(): holder["ok"] = Passwords.verify(password, check) and not stored.is_empty(), holder)


@rpc("any_peer", "reliable")
func _rq_login_token(version: String, username: String, token: String) -> void:
	if role != Role.SERVER or accounts == null:
		return
	var id := _sender()
	if not _allow(id) or not _auth_ok_version(id, version):
		return
	if not accounts.check_token(username, token):
		_deliver(id, "auth_error", ["Your saved login has expired. Please sign in again."])
		return
	accounts.revoke_token(username, token)   # tokens are single-use; a new one is issued
	_finish_login(id, username)


@rpc("any_peer", "reliable")
func _rq_logout(token: String) -> void:
	if role != Role.SERVER:
		return
	var id := _sender()
	if _sessions.has(id):
		accounts.revoke_token(_sessions[id], token)
		_end_session(id)


@rpc("any_peer", "reliable")
func _rq_change_password(old_password: String, new_password: String) -> void:
	if role != Role.SERVER:
		return
	var id := _sender()
	if not _sessions.has(id) or not _allow(id) or _busy_with_auth(id):
		return
	var problem := Passwords.check_new_password(new_password)
	if problem != "":
		_deliver(id, "notice", [problem])
		return
	var user: String = _sessions[id]
	var stored: Dictionary = accounts.get_record(user).get("password", {})
	var holder := {}
	_queue_auth(id, "change_password", user, func():
		holder["ok"] = Passwords.verify(old_password, stored)
		if holder["ok"]:
			holder["record"] = Passwords.make_record(new_password), holder)


func _poll_auth_jobs() -> void:
	var still: Array = []
	for j in _auth_jobs:
		if not WorkerThreadPool.is_task_completed(int(j["task"])):
			still.append(j)
			continue
		WorkerThreadPool.wait_for_task_completion(int(j["task"]))
		var id := int(j["peer"])
		var user: String = j["user"]
		var holder: Dictionary = j["holder"]
		match str(j["kind"]):
			"register":
				if accounts.exists(user):
					_deliver(id, "auth_error", ["That username is taken."])
				else:
					accounts.create(user, holder["record"])
					_log("New account: %s (%d accounts)" % [user, accounts.count()])
					_finish_login(id, user)
			"login":
				if bool(holder.get("ok", false)):
					_failures.erase(AccountStore.key_of(user))
					_finish_login(id, user)
				else:
					_note_failure(AccountStore.key_of(user))
					_deliver(id, "auth_error", ["Wrong username or password."])
			"change_password":
				if bool(holder.get("ok", false)):
					accounts.set_password(user, holder["record"])
					# Sign out this account's other sessions.
					for p in _sessions.keys():
						if p != id and _sessions[p] == AccountStore.key_of(user):
							_deliver(p, "session_ended", ["Your password was changed. Please sign in again."])
							_end_session(p)
					_deliver(id, "password_changed", [accounts.issue_token(user)])
				else:
					_deliver(id, "notice", ["Your current password was wrong."])
	_auth_jobs = still


func _finish_login(id: int, username: String) -> void:
	if not mp.get_peers().has(id):
		return
	var key := AccountStore.key_of(username)
	# One session per account: the newest login wins.
	for p in _sessions.keys():
		if p != id and _sessions[p] == key:
			_deliver(p, "session_ended", ["You signed in on another device."])
			_end_session(p)
	var record := accounts.get_record(username)
	var display := str(record.get("username", username))
	_sessions[id] = key
	_names[id] = display
	var pl := accounts.logic(username)
	pl.gold_mult = float(rewards["battle_mult"])
	_deliver(id, "login_ok", [{
		"username": display, "token": accounts.issue_token(username), "profile": pl.data,
		"rewards": {"battle_mult": rewards["battle_mult"]},
		"locked": UnitLocks.locked_list(), "locked_regions": UnitLocks.locked_regions(), "drops": DropRates.to_dict(),
		"difficulty": Difficulty.to_dict(),
	}])
	_log("%s signed in (%d online)" % [display, _sessions.size()])


func _end_session(id: int) -> void:
	_sessions.erase(id)
	_ranked_offers.erase(id)


# --- server: profile actions -----------------------------------------------------------

@rpc("any_peer", "reliable")
func _rq_profile_action(action: Array) -> void:
	if role != Role.SERVER:
		return
	var id := _sender()
	if not _sessions.has(id) or not _allow(id) or action.is_empty() or action.size() > 4:
		return
	var user: String = _sessions[id]
	var pl := accounts.logic(user)
	var event := ""
	var payload := {}
	match str(action[0]):
		"level_up":
			pl.level_up(str(action[1]) if action.size() > 1 else "")
		"tier_up":
			pl.tier_up(str(action[1]) if action.size() > 1 else "")
		"explore":
			var region := str(action[1]) if action.size() > 1 else ""
			if GameData.REGIONS.has(region) and pl.can_explore(region):
				payload = pl.explore(region)
				event = "choice"
		"choose_recruit":
			payload = pl.choose_recruit(int(action[1]) if action.size() > 1 else -1)
			event = "recruit" if not payload.is_empty() else ""
		"set_army":
			if action.size() > 1 and typeof(action[1]) == TYPE_ARRAY:
				pl.set_army(action[1])
		"hunt_trinkets":
			var site := str(action[1]) if action.size() > 1 else ""
			if pl.can_hunt_trinkets(site):
				payload = pl.hunt_trinkets(site)
				event = "trinket_choice"
		"choose_trinket":
			payload = pl.choose_trinket(int(action[1]) if action.size() > 1 else -1)
			event = "trinket_result" if not payload.is_empty() else ""
		"equip_trinket":
			if action.size() == 4:
				pl.equip_trinket(str(action[1]), int(action[2]), str(action[3]))
		"unequip_trinket":
			if action.size() == 3:
				pl.unequip_trinket(str(action[1]), int(action[2]))
		_:
			return
	accounts.save(user)
	_deliver(id, "profile", [pl.data, event, payload])


func _account_command(a: PackedStringArray) -> String:
	if accounts == null:
		return "Accounts are only available on the dedicated server."
	if a.size() == 1:
		var online_names: Array = []
		for id in _sessions:
			online_names.append(_names.get(id, _sessions[id]))
		return "%d accounts, %d signed in%s" % [accounts.count(), _sessions.size(), (": " + ", ".join(PackedStringArray(online_names))) if not online_names.is_empty() else ""]
	if a.size() == 3 and a[1].to_lower() == "reset-password":
		if not accounts.exists(a[2]):
			return "No account called '%s'." % a[2]
		var temp := Passwords.random_token().left(12)
		accounts.set_password(a[2], Passwords.make_record(temp))
		for p in _sessions.keys():
			if _sessions[p] == AccountStore.key_of(a[2]):
				_deliver(p, "session_ended", ["Your password was reset by the server admin. Sign in with your new password."])
				_end_session(p)
		_failures.erase(AccountStore.key_of(a[2]))
		return "New temporary password for %s: %s  (tell them to change it in Settings)" % [a[2], temp]
	return "Usage: accounts | accounts reset-password <user>"


# --- player admin ------------------------------------------------------------------

const PLAYER_STATS := ["rating", "gold", "maps", "wins", "losses", "draft_wins", "draft_played"]
const PLAYER_KEYWORDS := ["level", "tier", "shards", "remove"]


## The 'player' console command: look at and change a signed-in account's
## profile. Saved straight away and pushed to the player's open sessions.
func _player_command(a: PackedStringArray) -> String:
	if accounts == null:
		return "Player accounts are only available on the dedicated server."
	if a.is_empty():
		return "Usage: player <user> [set|add|name|unit|units|trinket|trinkets|challenge|reset] ...  (see 'help')"
	var user := a[0]
	if not accounts.exists(user):
		return "No account called '%s'." % user
	var pl := accounts.logic(user)
	if a.size() == 1:
		return _player_summary(user, pl)
	var sub := a[1].to_lower()
	var args := a.slice(2)
	var out := ""
	match sub:
		"set", "add":
			if args.size() != 2 or not args[0].to_lower() in PLAYER_STATS or not args[1].is_valid_int():
				return "Usage: player <user> %s <%s> <number>" % [sub, "|".join(PackedStringArray(PLAYER_STATS))]
			var stat := args[0].to_lower()
			var v := int(args[1])
			if sub == "add":
				v += int(pl.data.get(stat, 0))
			v = clampi(v, 0, 1000000000)
			pl.data[stat] = v
			out = "%s's %s is now %d." % [user, stat, v]
		"name":
			var nm := " ".join(args).strip_edges().left(24)
			if nm == "":
				return "Usage: player <user> name <new name>"
			pl.data["name"] = nm
			out = "%s's commander name is now %s." % [user, nm]
		"unit":
			out = _player_unit(pl, user, args)
		"units":
			if args.is_empty() or args[0].to_lower() != "all":
				return "Usage: player <user> units all [level <n>] [tier <n>]"
			var opts := _player_opts(args.slice(1))
			var n := 0
			for id in UnitLocks.unlocked_ids():
				_player_set_unit(pl, id, opts)
				n += 1
			out = "Gave %s all %d open units%s." % [user, n, _opts_text(opts)]
		"trinket":
			if args.is_empty():
				return "Usage: player <user> trinket <trinket> [remove]"
			var remove := args[args.size() - 1].to_lower() == "remove"
			var words := args.slice(0, args.size() - 1) if remove else args
			var t := _trinket_by_name(" ".join(words))
			if t == "":
				return "Unknown trinket '%s'." % " ".join(words)
			if remove:
				pl.data["trinkets"].erase(t)
				out = "Took %s from %s." % [Trinkets.ALL[t]["name"], user]
			else:
				pl.data["trinkets"][t] = true
				out = "Gave %s to %s." % [Trinkets.ALL[t]["name"], user]
		"trinkets":
			var which := args[0].to_lower() if not args.is_empty() else ""
			if which == "all":
				for t in Trinkets.ALL:
					pl.data["trinkets"][t] = true
				out = "Gave %s all %d trinkets." % [user, Trinkets.ALL.size()]
			elif which == "none":
				pl.data["trinkets"] = {}
				out = "Took every trinket from %s." % user
			else:
				return "Usage: player <user> trinkets all|none"
		"challenge":
			if args.is_empty():
				return "Usage: player <user> challenge <id>|all [remove]"
			var remove := args.size() > 1 and args[1].to_lower() == "remove"
			var ids: Array = []
			if args[0].to_lower() == "all":
				for c in Challenges.LIST:
					ids.append(c["id"])
			else:
				var cid := _challenge_by_name(args[0])
				if cid == "":
					return "Unknown challenge '%s'. Ids: %s" % [args[0], ", ".join(PackedStringArray(Challenges.LIST.map(func(c): return str(c["id"]))))]
				ids.append(cid)
			for cid in ids:
				if remove:
					pl.data["challenges"].erase(cid)
				else:
					pl.data["challenges"][cid] = true
			out = "%s %d challenge%s for %s." % ["Un-cleared" if remove else "Cleared", ids.size(), "" if ids.size() == 1 else "s", user]
		"reset":
			if args.is_empty() or args[0].to_lower() != "confirm":
				return "This wipes %s's progress (units, gold, rating...). Type 'player %s reset confirm' to do it." % [user, user]
			var nm := str(pl.data.get("name", user))
			pl.reset()
			pl.data["name"] = nm
			out = "%s's profile has been reset." % user
		_:
			return "Unknown 'player' option '%s'. Type 'help'." % sub
	_player_changed(user, pl)
	return out


func _player_summary(user: String, pl: ProfileLogic) -> String:
	var d := pl.data
	var rank := accounts.rank_of(user)
	var lines: Array = []
	lines.append("%s (commander name %s)%s" % [user, d.get("name", user), "  ONLINE" if _player_sessions(user).size() > 0 else ""])
	lines.append("  rating %d%s, wins %d, losses %d, gold %d, maps %d, Legion Draft %d wins of %d" % [pl.rating(),
		(" (#%d of %d)" % [int(rank["rank"]), int(rank["of"])]) if int(rank.get("rank", 0)) > 0 else "", int(d["wins"]), int(d["losses"]),
		pl.gold(), pl.maps(), int(d.get("draft_wins", 0)), int(d.get("draft_played", 0))])
	var units: Array = []
	for id in GameData.unit_ids_sorted():
		if d["units"].has(id):
			var u: Dictionary = d["units"][id]
			units.append("%s Lv%d T%d" % [id, int(u["level"]), int(u["tier"])])
	lines.append("  units (%d of %d): %s" % [units.size(), GameData.UNITS.size(), ", ".join(PackedStringArray(units))])
	lines.append("  army: %s" % ", ".join(PackedStringArray(d.get("army", []).map(func(sq): return "%s (%s)" % [sq["unit"], sq["row"]]))))
	lines.append("  trinkets: %d of %d    challenges cleared: %d of %d" % [d["trinkets"].size(), Trinkets.ALL.size(), d["challenges"].size(), Challenges.LIST.size()])
	return "\n".join(PackedStringArray(lines))


func _player_unit(pl: ProfileLogic, user: String, args: PackedStringArray) -> String:
	var name_words: Array = []
	var i := 0
	while i < args.size() and not args[i].to_lower() in PLAYER_KEYWORDS:
		name_words.append(args[i])
		i += 1
	var joined := " ".join(PackedStringArray(name_words)).to_lower()
	var id := joined.replace(" ", "_") if GameData.UNITS.has(joined.replace(" ", "_")) else _unit_by_name(joined)
	if id == "":
		return "Unknown unit '%s' (type 'units' for the list)." % joined
	var rest := args.slice(i)
	if not rest.is_empty() and rest[0].to_lower() == "remove":
		if not pl.data["units"].has(id):
			return "%s doesn't own %s." % [user, id]
		pl.data["units"].erase(id)
		pl.data["army"] = pl.data["army"].filter(func(sq): return str(sq["unit"]) != id)
		return "Took %s from %s (and out of their army)." % [GameData.UNITS[id]["name"], user]
	var opts := _player_opts(rest)
	var had: bool = pl.data["units"].has(id)
	_player_set_unit(pl, id, opts)
	var u: Dictionary = pl.data["units"][id]
	return "%s %s %s: level %d, tier %d, %d shards." % ["Updated" if had else "Gave", user, GameData.UNITS[id]["name"], int(u["level"]), int(u["tier"]), int(u["shards"])]


## level / tier / shards from "level 5 tier 2 shards 10".
func _player_opts(words: PackedStringArray) -> Dictionary:
	var opts := {}
	var k := 0
	while k + 1 < words.size():
		var key := words[k].to_lower()
		if key in ["level", "tier", "shards"] and words[k + 1].is_valid_int():
			opts[key] = int(words[k + 1])
		k += 2
	return opts


func _opts_text(opts: Dictionary) -> String:
	if opts.is_empty():
		return ""
	var parts: Array = []
	for k in opts:
		parts.append("%s %d" % [k, opts[k]])
	return " (" + ", ".join(PackedStringArray(parts)) + ")"


func _player_set_unit(pl: ProfileLogic, id: String, opts: Dictionary) -> void:
	if not pl.data["units"].has(id):
		pl.data["units"][id] = {"level": 1, "tier": 0, "shards": 0, "trinkets": []}
	var u: Dictionary = pl.data["units"][id]
	if opts.has("tier"):
		u["tier"] = clampi(int(opts["tier"]), 0, GameData.MAX_TIER)
	if opts.has("level"):
		u["level"] = int(opts["level"])
	u["level"] = clampi(int(u["level"]), 1, Army.max_level(id, int(u["tier"])))
	if opts.has("shards"):
		u["shards"] = clampi(int(opts["shards"]), 0, 1000000)


func _trinket_by_name(text: String) -> String:
	var t := text.strip_edges().to_lower()
	if Trinkets.ALL.has(t.replace(" ", "_")):
		return t.replace(" ", "_")
	for id in Trinkets.ALL:
		if str(Trinkets.ALL[id]["name"]).to_lower() == t or str(Trinkets.ALL[id]["name"]).to_lower().replace("'", "") == t.replace("'", ""):
			return id
	return ""


func _challenge_by_name(text: String) -> String:
	var t := text.strip_edges().to_lower()
	for c in Challenges.LIST:
		if str(c["id"]) == t or str(c["name"]).to_lower() == t:
			return str(c["id"])
	return ""


func _player_sessions(user: String) -> Array:
	var out: Array = []
	for p in _sessions:
		if _sessions[p] == AccountStore.key_of(user):
			out.append(p)
	return out


## Clean up (the profile's own rules), save, and send to the player.
func _player_changed(user: String, pl: ProfileLogic) -> void:
	pl.load_from(pl.data.duplicate(true))
	accounts.save(user)
	for p in _player_sessions(user):
		_deliver(p, "profile", [pl.data, "", {}])


# --- leaderboard -------------------------------------------------------------------

## Ask for the leaderboard: over the session when signed in, otherwise with
## a quick check-in (which carries it). Answers with `leaderboard_received`.
func request_leaderboard() -> void:
	if session_active():
		_request("_rq_leaderboard", [])
	elif role == Role.NONE and not logged_in:
		sync_from_server()
	else:
		leaderboard_received.emit(last_leaderboard, last_leaderboard_me)


@rpc("any_peer", "reliable")
func _rq_leaderboard() -> void:
	if role != Role.SERVER or accounts == null:
		return
	var id := _sender()
	if not _allow(id):
		return
	var me := accounts.rank_of(_sessions[id]) if _sessions.has(id) else {}
	_deliver(id, "leaderboard", [accounts.leaderboard(LEADERBOARD_SIZE), me])


@rpc("authority", "reliable")
func _rc_leaderboard(top: Array, me: Dictionary) -> void:
	last_leaderboard = top
	last_leaderboard_me = me
	last_leaderboard_msec = Time.get_ticks_msec()
	leaderboard_received.emit(top, me)


func _credit_draft(list: Array) -> void:
	for p in list:
		var id := int(p["id"])
		if not _sessions.has(id) or int(p.get("place", 0)) <= 0:
			continue
		var user: String = _sessions[id]
		var pl := accounts.logic(user)
		pl.add_draft_reward(int(p.get("gold", 0)), int(p.get("maps", 0)), int(p.get("place", 0)))
		accounts.save(user)
		_deliver(id, "profile", [pl.data, "", {}])


# --- server: ranked battles ---------------------------------------------------------------

## Ranked opponents for a signed-in player: real saved armies near their
## rating plus generated ones to fill three slots. Remembered so the player
## can then pick one to fight.
func _ranked_offer_for(id: int) -> Array:
	var user: String = _sessions[id]
	var pl := accounts.logic(user)
	var rating := pl.rating()
	var offers: Array = []
	var code := pl.army_code()
	if ranked_pool.add("acct:" + user, str(pl.data.get("name", user)), rating, code):
		ranked_pool.save_file()
	for e in ranked_pool.find(rating + Army.RANKED_SEARCH_BIAS, "acct:" + user, 3, ranked_range):
		var army := Army.decode(str(e["code"]))
		if army.is_empty():
			continue
		var r := int(e["rating"])
		offers.append({"name": e["name"], "rating": r, "squads": army["squads"], "player": true, "saved_at": e["saved_at"],
			"difficulty": "Easy" if r < rating - Army.RANKED_LABEL_GAP else ("Hard" if r > rating + Army.RANKED_LABEL_GAP else "Even")})
	Army.fill_ghosts(offers, rating, _rng)
	for i in offers.size():
		offers[i]["map"] = BattleMaps.random_map_id(_rng)
		offers[i]["index"] = i
	_ranked_offers[id] = offers
	return offers


@rpc("any_peer", "reliable")
func _rq_ranked_battle(index: int) -> void:
	if role != Role.SERVER:
		return
	var id := _sender()
	if not _sessions.has(id) or not _allow(id):
		return
	var offers: Array = _ranked_offers.get(id, [])
	if index < 0 or index >= offers.size():
		_deliver(id, "notice", ["That opponent is no longer available. Find opponents again."])
		return
	_ranked_offers.erase(id)   # one battle per search
	var opp: Dictionary = offers[index]
	var user: String = _sessions[id]
	var pl := accounts.logic(user)
	var mine := pl.battle_squads()
	if mine.is_empty():
		_deliver(id, "notice", ["Build an army first."])
		return
	var seed_value := _rng.randi()
	var sim := BattleSim.new()
	sim.setup(mine, opp["squads"], seed_value, opp["map"])
	var task := WorkerThreadPool.add_task(sim.run_to_end.bind(200000), false, "ranked battle")
	_ranked_jobs.append({"task": task, "sim": sim, "peer": id, "user": user, "opp": opp, "mine": mine})
	_deliver(id, "ranked_start", [{
		"mode": "ranked_online", "seed": seed_value, "map": opp["map"], "squads_a": mine, "squads_b": opp["squads"],
		"name_a": str(pl.data.get("name", user)), "name_b": opp["name"], "rating_a": pl.rating(), "rating_b": int(opp["rating"]),
		"local_team": 0,
	}])


@rpc("any_peer", "reliable")
func _rq_challenge_battle(challenge_id: String) -> void:
	if role != Role.SERVER:
		return
	var id := _sender()
	if not _sessions.has(id) or not _allow(id):
		return
	var user: String = _sessions[id]
	var pl := accounts.logic(user)
	var c := Challenges.get_challenge(challenge_id)
	if c.is_empty() or not pl.challenge_unlocked(challenge_id):
		_deliver(id, "notice", ["That challenge isn't open yet."])
		return
	for j in _ranked_jobs:
		if int(j["peer"]) == id:
			return  # one battle at a time
	var mine := pl.battle_squads()
	if mine.is_empty():
		_deliver(id, "notice", ["Build an army first."])
		return
	var enemy := Challenges.enemy_squads(challenge_id)
	var seed_value := _rng.randi()
	var sim := BattleSim.new()
	sim.setup(mine, enemy, seed_value, c["map"])
	var task := WorkerThreadPool.add_task(sim.run_to_end.bind(200000), false, "challenge battle")
	_ranked_jobs.append({"task": task, "sim": sim, "peer": id, "user": user, "challenge": challenge_id})
	_deliver(id, "ranked_start", [{
		"mode": "challenge_online", "challenge": challenge_id, "seed": seed_value, "map": c["map"],
		"squads_a": mine, "squads_b": enemy, "name_a": str(pl.data.get("name", user)), "name_b": c["name"],
		"rating_a": pl.rating(), "rating_b": 0, "local_team": 0,
	}])


func _poll_ranked_jobs() -> void:
	var still: Array = []
	for j in _ranked_jobs:
		if not WorkerThreadPool.is_task_completed(int(j["task"])):
			still.append(j)
			continue
		WorkerThreadPool.wait_for_task_completion(int(j["task"]))
		var sim: BattleSim = j["sim"]
		var score := 1.0 if sim.winner == 0 else (0.0 if sim.winner == 1 else 0.5)
		var killed := sim.start_count[1] - sim.alive_count[1]
		var user: String = j["user"]
		var pl := accounts.logic(user)
		pl.gold_mult = float(rewards["battle_mult"])
		var summary: Dictionary
		if j.has("challenge"):
			summary = pl.complete_challenge(str(j["challenge"]), score >= 1.0)
		else:
			summary = pl.apply_battle_result("ranked", score, int(j["opp"]["rating"]), killed, not bool(j["opp"].get("player", false)))
			unit_stats.record("ranked", j["mine"], score)
		summary["score"] = score
		accounts.save(user)
		var id := int(j["peer"])
		if _sessions.get(id, "") == user:
			_deliver(id, "ranked_result", [summary])
			_deliver(id, "profile", [pl.data, "", {}])
	_ranked_jobs = still
