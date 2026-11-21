extends SceneTree
## Network smoke test / tiny load generator for the Legion Draft server.
## Connects as a player, uses Quick Match, plays every shop turn with simple
## scripted actions, skips battle replays and prints the final placement.
##
##   godot --headless -s res://tests/net_smoke_client.gd -- --server=HOST[:PORT] --name=Bot1
## LAN modes (no server):
##   ... -- --lan-host --name=Host        host a LAN match, start once someone joins
##   ... -- --lan-join=127.0.0.1 --name=P2  join a LAN host by IP
##   ... -- --lan-quick --name=P3           find a LAN match via broadcast, else host
##
## Exit code 0 when the match finished, 1 on timeout or disconnect.

var party: Node
var player := "Smoke"
var started := 0
var turns := 0
var done := false


func _initialize() -> void:
	var server := "localhost"
	var mode := "online"
	var lan_ip := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--server="):
			server = arg.get_slice("=", 1)
		elif arg.begins_with("--name="):
			player = arg.get_slice("=", 1)
		elif arg == "--lan-host":
			mode = "lan-host"
		elif arg == "--lan-quick":
			mode = "lan-quick"
		elif arg.begins_with("--lan-join="):
			mode = "lan-join"
			lan_ip = arg.get_slice("=", 1)
	started = Time.get_ticks_msec()
	party = root.get_node("Party")
	root.get_node("Profile").data["server_address"] = server
	party.status.connect(func(t: String): print("[%s] status: %s" % [player, t]))
	party.match_started.connect(func(): print("[%s] match started with %d players" % [player, party.players.size()]))
	party.shop_started.connect(_on_shop)
	party.battle_ready.connect(func(cfg: Dictionary):
		print("[%s] round %d battle on %s vs %s" % [player, int(cfg["round"]), cfg["map"], cfg["name_b"] if int(cfg["local_team"]) == 0 else cfg["name_a"]])
		party.battle_viewed())
	party.match_over.connect(_on_over)
	party.left_match.connect(func(r: String):
		if not done:
			print("[%s] LEFT: %s" % [player, r])
			quit(1))
	party.lobby_changed.connect(_on_lobby)
	var settings := {"wins": 3, "lives": 2, "max_players": 4, "turn_time": 20}
	match mode:
		"online":
			party.online_quick(player, settings)
		"lan-host":
			party.host_lan(player, settings)
		"lan-join":
			party.join_lan(lan_ip, party.PORT, player)
		"lan-quick":
			party.quick_lan(player, settings)


## LAN lobbies: guests ready up; the owner fills with bots and starts once
## another human has joined.
func _on_lobby() -> void:
	if party.phase != "lobby":
		return
	if not party.is_owner():
		if not bool(party.me().get("ready", false)):
			party.set_ready(true)
		return
	var humans := 0
	for id in party.players:
		if not party.players[id]["bot"]:
			humans += 1
	if humans >= 2:
		if party.players.size() < 4:
			party.add_bot()
		elif party.can_start():
			print("[%s] starting LAN match" % player)
			party.start_match()


func _on_shop(r: int, _s: int) -> void:
	turns += 1
	var run: DraftRun = party.run
	var ok := 0
	for step in 10:
		var act: Array = ["reroll"]
		if step % 3 != 2 and not run.shop_units.is_empty():
			var uid: String = run.shop_units[0]["unit"]
			var slot := run.slot_of_unit(uid)
			if slot == -1:
				slot = run.first_empty_slot()
			if slot != -1:
				act = ["buy_unit", 0, slot]
		elif not run.shop_trinkets.is_empty() and run.unit_count() > 0:
			act = ["buy_trinket", 0, 0 if not (run.board[0] as Dictionary).is_empty() else run.first_empty_slot()]
		if party.do_action(act):
			ok += 1
	print("[%s] round %d shop: %d actions, %d units on board, %d gold left" % [player, r, ok, run.unit_count(), run.gold])
	party.submit_turn()


func _on_over(list: Array) -> void:
	done = true
	for p in list:
		print("[%s] final #%d %s (%d wins, %d losses) +%d gold" % [player, int(p["place"]), p["name"], int(p["wins"]), int(p.get("losses", 0)), int(p.get("gold", 0))])
	print("[%s] server battle gold multiplier: x%s" % [player, root.get_node("Profile").battle_gold_mult()])
	print("[%s] server unit locks: %d locked, storm_dragon %s, goblin %s" % [player, UnitLocks.locked_list().size(),
		"locked" if UnitLocks.is_locked("storm_dragon") else "open", "locked" if UnitLocks.is_locked("goblin") else "open"])
	print("[%s] server region locks: %s" % [player, UnitLocks.locked_regions()])
	quit(0)


func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - started > 600000:
		print("[%s] TIMEOUT" % player)
		quit(1)
	return false
