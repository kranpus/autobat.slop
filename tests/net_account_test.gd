extends SceneTree
## End-to-end test of server accounts against a running server:
## register, server-side profile actions, a server-run ranked battle, log out,
## wrong password, password login, "remember me" token login, password change
## and checks that the server's account file holds no password or token.
##
##   godot --headless -- --server              (in another terminal)
##   godot --headless -s res://tests/net_account_test.gd -- --server=localhost
##
## The server and this test must share a user data folder for the file checks
## (they do when both run from this project on the same machine).
## Exit code 0 when everything passed.

var party: Node
var profile: Node
var _failures := 0
var _deadline := 0


func _initialize() -> void:
	var server := "localhost"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--server="):
			server = arg.get_slice("=", 1)
	party = root.get_node("Party")
	profile = root.get_node("Profile")
	profile.settings["server_address"] = server
	party.status.connect(func(t: String): print("    status: ", t))
	_deadline = Time.get_ticks_msec() + 180000
	_run.call_deferred()


func check(cond: bool, msg: String) -> void:
	if cond:
		print("  ok   ", msg)
	else:
		_failures += 1
		printerr("  FAIL ", msg)


func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() > _deadline:
		printerr("TIMEOUT")
		quit(1)
	return false


func _run() -> void:
	var user := "acct%d" % (randi() % 1000000)
	var password := "correct horse %d" % randi()
	party.login_result.connect(func(ok: bool, message: String): _last_login = [ok, message])

	print("register")
	party.register(user, "short", false)
	await _login_done()
	check(not _last_login[0], "a too-short password is refused (%s)" % _last_login[1])
	party.register(user, password, true)
	await _login_done()
	check(_last_login[0], "registered and signed in as %s" % user)
	check(profile.online and profile.account == user, "the game switched to the server profile")
	check(party.session_active(), "the session is live")
	var saved: Dictionary = profile.settings.get("account", {})
	check(str(saved.get("token", "")).length() == 64 and not JSON.stringify(profile.settings).contains(password), "remember me saved a token, not the password")

	print("server-side progress")
	var start_maps: int = profile.maps()
	var region := ""
	for r in GameData.REGIONS:
		if profile.can_explore(r):
			region = r
			break
	check(region != "", "a region can be explored")
	profile.explore(region)
	var choice: Dictionary = await profile.choice_ready
	check(choice.has("options") and choice["options"].size() == 3, "the server rolled a 1-of-3 recruit choice")
	check(profile.maps() == start_maps - int(GameData.REGIONS[region]["cost_maps"]), "the server spent the scouting map")
	profile.choose_recruit(0)
	var rec: Dictionary = await profile.recruit_result
	check(rec.has("unit") and profile.owns(rec["unit"]), "the server added the recruit (%s)" % rec.get("unit", "?"))
	var owned: Array = profile.data["units"].keys()
	profile.set_army([{"unit": owned[0], "row": "back"}])
	await profile.changed
	await _wait_ms(500)
	check(profile.data["army"].size() == 1 and profile.data["army"][0]["row"] == "back", "the server saved the army")
	# Cheating the local copy changes nothing: the server's copy wins.
	profile.data["gold"] = 99999999
	profile.level_up(owned[0])
	await _wait_ms(800)
	check(profile.gold() < 99999999, "a locally edited gold value is overwritten by the server's")

	print("trinkets on the server")
	var maps_before: int = profile.maps()
	profile.hunt_trinkets("camp")
	var tchoice: Dictionary = await profile.trinket_choice_ready
	check(tchoice.get("options", []).size() == 3 and profile.maps() == maps_before - 1, "the server rolled a trinket hunt and spent the map")
	profile.choose_trinket(0)
	var tres: Dictionary = await profile.trinket_result
	var trinket: String = tres.get("trinket", "")
	check(profile.owns_trinket(trinket), "the server added the trinket (%s)" % trinket)
	profile.equip_trinket(owned[0], 0, trinket)
	await profile.changed
	await _wait_ms(800)
	check(profile.trinkets_of(owned[0]) == [trinket], "the server saved the equipped trinket")
	profile.data["trinkets"]["octoring"] = true   # a forged trinket...
	profile.equip_trinket(owned[0], 1, "octoring")
	await _wait_ms(800)
	check(not profile.owns_trinket("octoring") and not profile.trinkets_of(owned[0]).has("octoring"), "a trinket the account doesn't own is refused")

	print("server-run ranked battle")
	var gold_before: int = profile.gold()
	var rating_before: int = profile.rating()
	party.request_ranked_opponents(profile.player_id(), profile.player_name(), profile.rating(), profile.army_code())
	var offers: Array = await party.ranked_opponents
	check(offers.size() == 3 and offers[0].has("squads") and offers[0].has("index"), "the server offered 3 opponents")
	party.request_ranked_battle(int(offers[0]["index"]))
	var cfg: Dictionary = await party.battle_ready
	check(cfg.get("mode", "") == "ranked_online", "the server started the battle")
	var summary: Dictionary = await party.ranked_result
	await _wait_ms(300)
	print("    result: ", summary)
	check(summary.has("gold") and summary.has("rating"), "the server reported the battle result")
	check(profile.gold() == gold_before + int(summary["gold"]) and profile.rating() == rating_before + int(summary["rating"]), "the server applied the rewards")
	var sim := BattleSim.new()
	sim.setup(cfg["squads_a"], cfg["squads_b"], int(cfg["seed"]), str(cfg["map"]))
	sim.run_to_end(200000)
	var local_score := 1.0 if sim.winner == 0 else (0.0 if sim.winner == 1 else 0.5)
	check(is_equal_approx(local_score, float(summary["score"])), "the replay on this device matches the server's result")
	party.request_ranked_battle(int(offers[1]["index"]))
	await _wait_ms(800)
	check(party.last_ranked_summary == summary, "an offer can't be fought again without searching again")

	check(cfg["squads_a"].any(func(sq): return sq.get("trinkets", []).has(trinket)), "the battle used the equipped trinket")

	print("unit stats on the server")
	var unit_name: String = GameData.UNITS[owned[0]]["name"]
	var table := await _admin("unitstats ranked games")
	print("    " + table.replace("\n", "\n    ").left(900))
	check(table.contains(unit_name), "the server counted the ranked battle for %s" % unit_name)
	check((await _admin("unitstats patches")).contains(ProjectSettings.get_setting("application/config/version")), "stats are kept under this patch")

	print("challenges on the server")
	var gold_c: int = profile.gold()
	party.request_challenge_battle("rat_problem")
	var ccfg: Dictionary = await party.battle_ready
	check(ccfg.get("mode", "") == "challenge_online" and ccfg.get("map", "") == "open_arena", "the server started the challenge on its battlefield")
	var cres: Dictionary = await party.ranked_result
	await _wait_ms(300)
	if bool(cres.get("won", false)):
		check(cres["first_clear"] and profile.gold() == gold_c + 150 and profile.challenge_cleared("rat_problem"), "the server paid the first-clear reward once")
		party.request_challenge_battle("rat_problem")
		await party.battle_ready
		var again: Dictionary = await party.ranked_result
		check(not again.get("first_clear", true), "a replay pays nothing")
	else:
		check(not profile.challenge_cleared("rat_problem"), "a lost challenge stays open (army too weak this run)")
	party.request_challenge_battle("golden_wyrm")
	await _wait_ms(800)
	check(not profile.challenge_cleared("golden_wyrm") and party.last_ranked_summary.get("challenge", "") != "golden_wyrm", "a locked challenge is refused")

	print("leaderboard")
	party.request_leaderboard()
	var got: Array = await party.leaderboard_received   # [top, me]
	var lb: Array = got[0]
	await _wait_ms(100)
	var me: Dictionary = party.last_leaderboard_me
	check(lb.size() > 0 and int(me.get("rank", 0)) > 0, "the leaderboard lists ranked players and your rank (#%d of %d)" % [int(me.get("rank", 0)), int(me.get("of", 0))])
	check(lb.any(func(e): return str(e["name"]) == user), "you appear on it after a ranked battle")

	print("account file on the server")
	var path := "user://accounts/%s.json" % user
	var text := FileAccess.get_file_as_string(path)
	check(text != "", "the account file exists")
	check(not text.contains(password), "it doesn't contain the password")
	check(not text.contains(str(profile.settings["account"]["token"])), "it doesn't contain the login token")
	var rec_json = JSON.parse_string(text)
	check(typeof(rec_json) == TYPE_DICTIONARY and int(rec_json["password"]["iterations"]) >= 600000 and str(rec_json["password"]["salt"]).length() == 32, "it holds a salted 600k-iteration PBKDF2 hash")

	print("log out / log in")
	var gold_now: int = profile.gold()
	var token: String = profile.settings["account"]["token"]
	party.logout()
	await _wait_ms(500)
	check(not profile.online and not party.logged_in and not profile.settings.has("account"), "logged out: back to the guest profile, saved login forgotten")
	party.login(user, "wrong password", false)
	await _login_done()
	check(not _last_login[0], "a wrong password is refused (%s)" % _last_login[1])
	party.login_with_token(user, token)
	await _login_done()
	check(not _last_login[0], "the token from before logging out no longer works")
	party.login(user.to_upper(), password, true)
	await _login_done()
	check(_last_login[0] and profile.gold() == gold_now, "password login (any letter case) restores the server profile")

	print("remember me")
	token = profile.settings["account"]["token"]
	party.disconnect_all(true)
	party.logged_in = false
	check(party.try_auto_login(), "a saved login is found")
	await _login_done()
	check(_last_login[0], "signed in with the saved token")
	var used := token
	party.disconnect_all(true)
	party.login_with_token(user, used)
	await _login_done()
	check(not _last_login[0], "tokens are single-use (a fresh one is issued every login)")
	check(not profile.online, "a refused token signs out")

	print("change password")
	party.login(user, password, true)
	await _login_done()
	var new_password := password + "!"
	party.change_password("not it", new_password)
	await _wait_ms(2500)
	party.change_password(password, new_password)
	await _wait_ms(2500)
	party.logout()
	await _wait_ms(400)
	party.login(user, password, false)
	await _login_done()
	check(not _last_login[0], "the old password stops working")
	party.login(user, new_password, false)
	await _login_done()
	check(_last_login[0], "the new password works")

	print("lockout")
	party.logout()
	await _wait_ms(400)
	for i in party.LOGIN_FAILURE_LIMIT:
		party.login(user, "bad guess %d" % i, false)
		await _login_done()
	party.login(user, new_password, false)
	await _login_done()
	check(not _last_login[0] and str(_last_login[1]).contains("Too many"), "repeated wrong passwords lock the account for a while")

	print("\n%s (%d failure%s)" % ["ALL ACCOUNT TESTS PASSED" if _failures == 0 else "ACCOUNT TESTS FAILED", _failures, "" if _failures == 1 else "s"])
	party.disconnect_all(true)
	quit(1 if _failures > 0 else 0)


var _last_login: Array = [false, ""]


func _login_done() -> void:
	await party.login_result


## Runs a console command on the server through its admin inbox (as admin.sh does).
func _admin(command: String) -> String:
	var id := "t%d" % randi()
	DirAccess.make_dir_recursive_absolute("user://admin")
	var f := FileAccess.open("user://admin/commands.txt", FileAccess.WRITE)
	f.store_string("%s\t%s\n" % [id, command])
	f.close()
	for _i in 40:
		await _wait_ms(250)
		var text := FileAccess.get_file_as_string("user://admin/replies.txt")
		var start := text.rfind("### %s\n" % id)
		var end := text.rfind("### end %s" % id)
		if start >= 0 and end > start:
			return text.substr(start + id.length() + 5, end - start - id.length() - 5).strip_edges()
	return ""


func _wait_ms(ms: int) -> void:
	await create_timer(ms / 1000.0).timeout
