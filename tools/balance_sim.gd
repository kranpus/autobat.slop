extends SceneTree
## Balance simulator: fights many battles with the real battle simulator and
## reports how each unit does. Runs headless, on the server (server/balance.sh)
## or any computer with Godot 4.3:
##
##   godot --headless --path . -s res://tools/balance_sim.gd -- [options]
##
## Modes:
##   --mode=armies   (default) random armies of equal power fight each other;
##                   each unit's win rate is how armies containing it did.
##   --mode=duels    every unit against every other unit, one squad each at
##                   equal power: who beats whom (a counter matrix).
##   --mode=calibrate  armies of different power: how often the stronger army
##                   wins at each power ratio (checks the Strength formula
##                   and ranked difficulty).
##
## Options:
##   --battles=N       armies/calibrate: pairings to fight (default 400; each
##                     pairing is fought twice, once from each side)
##   --minutes=M       stop after about M minutes instead (whichever is first)
##   --power=P|A-B     army power as shown in the game (default 200-3000)
##   --rating=R        unit pool by rating like ranked opponents: rarer units
##                     from 1200/1700/2500 (default 3500: every rarity)
##   --trinkets        give armies trinkets like ranked opponents (default off)
##   --all-units       include units the server has locked (default: the
##                     server's unlocked units, read from its settings file)
##   --units=a,b,c     only these units (ids)
##   --map=ID          one battlefield instead of random ones
##   --threads=N       battles at once (default: half the CPU cores, at least 1)
##   --seed=N          repeat a run exactly
##   --out=DIR         where to save the CSV and summary (default user://balance)
## Exit code 0 on success.

const SERVER_CONFIG := "user://server_config.json"

var opts := {
	"mode": "armies", "battles": 400, "minutes": 0.0, "power": "200-3000", "rating": 3500,
	"trinkets": false, "all_units": false, "units": "", "map": "", "threads": 0, "seed": 0,
	"out": "user://balance",
}
var _t0 := 0
var _pool: Array = []


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		var k := arg.trim_prefix("--").get_slice("=", 0).replace("-", "_")
		var v := arg.get_slice("=", 1) if arg.contains("=") else "true"
		if not opts.has(k):
			print("Unknown option %s. See the top of tools/balance_sim.gd." % arg)
			quit(2)
			return
		opts[k] = v
	opts["battles"] = int(opts["battles"])
	opts["minutes"] = float(opts["minutes"])
	opts["rating"] = int(opts["rating"])
	opts["threads"] = int(opts["threads"]) if int(opts["threads"]) > 0 else maxi(1, OS.get_processor_count() / 2)
	opts["seed"] = int(opts["seed"]) if int(opts["seed"]) != 0 else int(Time.get_unix_time_from_system()) % 1000000
	opts["trinkets"] = str(opts["trinkets"]) == "true"
	opts["all_units"] = str(opts["all_units"]) == "true"
	if not opts["mode"] in ["armies", "duels", "calibrate"]:
		print("Unknown mode %s (armies, duels or calibrate)." % opts["mode"])
		quit(2)
		return
	if opts["map"] != "" and BattleMaps.get_map(opts["map"]).is_empty():
		print("Unknown map %s. Maps: %s" % [opts["map"], ", ".join(PackedStringArray(BattleMaps.map_ids()))])
		quit(2)
		return
	_setup_pool()
	if _pool.size() < 2:
		print("Not enough units to simulate (%d)." % _pool.size())
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(opts["out"])
	_t0 = Time.get_ticks_msec()
	print("Autobat Legions %s balance simulator: mode %s, %d units, %d thread(s), seed %d" % [
		ProjectSettings.get_setting("application/config/version"), opts["mode"], _pool.size(), opts["threads"], opts["seed"]])
	match str(opts["mode"]):
		"duels":
			_run_duels()
		_:
			_run_armies(opts["mode"] == "calibrate")
	quit(0)


func _setup_pool() -> void:
	# The same units the live server allows, unless asked for all of them.
	if opts["all_units"]:
		UnitLocks.set_locked_list([])
	else:
		var cfg = JSON.parse_string(FileAccess.get_file_as_string(SERVER_CONFIG)) if FileAccess.file_exists(SERVER_CONFIG) else null
		if typeof(cfg) == TYPE_DICTIONARY and typeof(cfg.get("locked")) == TYPE_ARRAY:
			UnitLocks.set_locked_list(cfg["locked"])
			print("Using the server's unit locks (%d locked; --all-units to include them)." % cfg["locked"].size())
	if str(opts["units"]) != "":
		var keep: Array = []
		for u in str(opts["units"]).split(",", false):
			if GameData.UNITS.has(u.strip_edges()):
				keep.append(u.strip_edges())
			else:
				print("Unknown unit %s (ignored)." % u)
		UnitLocks.set_locked_list(GameData.UNITS.keys().filter(func(u): return not keep.has(u)))
	_pool = UnitLocks.unlocked_ids()


func _power_range() -> Vector2:
	var p := str(opts["power"])
	if p.contains("-"):
		return Vector2(float(p.get_slice("-", 0)), float(p.get_slice("-", 1))) * 10.0
	return Vector2(float(p), float(p)) * 10.0


func _out_of_time(done: int, total: int) -> bool:
	if done >= total:
		return true
	return float(opts["minutes"]) > 0.0 and Time.get_ticks_msec() - _t0 > int(float(opts["minutes"]) * 60000.0)


func _map(rng: RandomNumberGenerator) -> String:
	return str(opts["map"]) if opts["map"] != "" else BattleMaps.random_map_id(rng)


## Runs the sims to the end on --threads worker threads.
func _run_batch(sims: Array) -> void:
	var state := {"next": 0}
	var mutex := Mutex.new()
	var threads: Array = []
	for _i in mini(int(opts["threads"]), sims.size()):
		var th := Thread.new()
		th.start(_worker.bind(sims, state, mutex))
		threads.append(th)
	for th in threads:
		th.wait_to_finish()


func _worker(sims: Array, state: Dictionary, mutex: Mutex) -> void:
	while true:
		mutex.lock()
		var i: int = state["next"]
		state["next"] = i + 1
		mutex.unlock()
		if i >= sims.size():
			return
		(sims[i] as BattleSim).run_to_end(200000)


static func _score(sim: BattleSim, team: int) -> float:
	return 1.0 if sim.winner == team else (0.0 if sim.winner == 1 - team else 0.5)


# --- armies / calibrate ---------------------------------------------------------

func _run_armies(calibrate: bool) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(opts["seed"])
	var pr := _power_range()
	var units := {}            # unit -> [games, score]
	var buckets := {}          # power ratio bucket -> [games, score of the stronger army]
	var done := 0
	var total: int = opts["battles"]
	var batch_size := maxi(8, int(opts["threads"]) * 4)
	while not _out_of_time(done, total):
		var jobs: Array = []
		var sims: Array = []
		for _i in mini(batch_size, total - done):
			var target := exp(rng.randf_range(log(pr.x), log(pr.y)))
			var a := Army.generate_opponent(target, opts["rating"], rng.randi(), opts["trinkets"], true, false)
			var pa := Army.army_power(a["squads"])
			var ratio := rng.randf_range(0.7, 1.5) if calibrate else 1.0
			var b := Army.generate_opponent(pa * ratio, opts["rating"], rng.randi(), opts["trinkets"], true, false)
			var map := _map(rng)
			var seed_v := rng.randi()
			var s1 := BattleSim.new()
			s1.setup(a["squads"], b["squads"], seed_v, map)
			var s2 := BattleSim.new()
			s2.setup(b["squads"], a["squads"], seed_v, map)
			sims.append_array([s1, s2])
			jobs.append({"a": a["squads"], "b": b["squads"], "ratio": Army.army_power(b["squads"]) / pa, "s1": s1, "s2": s2})
		_run_batch(sims)
		for j in jobs:
			var score_a := _score(j["s1"], 0) + _score(j["s2"], 1)   # 0..2
			var ua := _unit_set(j["a"])
			var ub := _unit_set(j["b"])
			for u in ua:
				if not ub.has(u):
					_add(units, u, 2, score_a)
			for u in ub:
				if not ua.has(u):
					_add(units, u, 2, 2.0 - score_a)
			# Calibration from the stronger army's side.
			var r: float = j["ratio"]
			var strong_score := (2.0 - score_a) if r >= 1.0 else score_a
			var rr := r if r >= 1.0 else 1.0 / r
			_add(buckets, clampi(roundi((rr - 1.0) * 20.0), 0, 20), 2, strong_score)
		done += jobs.size()
		print("  %d / %d pairings (%d battles), %ds" % [done, total, done * 2, (Time.get_ticks_msec() - _t0) / 1000])
	var lines: Array = []
	lines.append("Balance run: %s, patch %s, %d pairings (%d battles), power %s, rating %d, trinkets %s, seed %d" % [
		opts["mode"], ProjectSettings.get_setting("application/config/version"), done, done * 2, opts["power"], opts["rating"], "on" if opts["trinkets"] else "off", opts["seed"]])
	if calibrate:
		lines.append("")
		lines.append("Stronger army's win rate by power ratio (Strength formula check: 1.00x should be ~50%):")
		var keys := buckets.keys()
		keys.sort()
		for k in keys:
			lines.append("  %.2fx  %5.1f%%  (%d battles)" % [1.0 + k / 20.0, 100.0 * buckets[k][1] / buckets[k][0], buckets[k][0]])
	lines.append("")
	lines.append(_unit_table(units, "Win rate of armies containing each unit (equal power%s):" % (", random power ratios" if calibrate else "")))
	_finish(lines, units, null)


func _unit_set(squads: Array) -> Dictionary:
	var d := {}
	for sq in squads:
		d[str(sq["unit"])] = true
	return d


static func _add(d: Dictionary, key, games: int, score: float) -> void:
	if not d.has(key):
		d[key] = [0, 0.0]
	d[key][0] += games
	d[key][1] += score


func _unit_table(units: Dictionary, title: String) -> String:
	var rows: Array = units.keys()
	rows.sort_custom(func(x, y): return units[x][1] / units[x][0] > units[y][1] / units[y][0])
	var lines: Array = [title, "  %-24s %-10s %-7s %6s %7s %8s" % ["Unit", "Rarity", "Role", "Games", "Win", "±95%"]]
	for u in rows:
		var n := float(units[u][0])
		var p: float = units[u][1] / n
		lines.append("  %-24s %-10s %-7s %6d %6.1f%% %7.1f%%" % [str(GameData.UNITS[u]["name"]).left(24), GameData.UNITS[u]["rarity"], GameData.UNITS[u]["role"],
			int(n), 100.0 * p, 196.0 * sqrt(maxf(p * (1.0 - p), 0.0001) / n)])
	lines.append("  ±95%: the true rate is within this of the measured one 95% of the time; run more battles to narrow it.")
	return "\n".join(PackedStringArray(lines))


# --- duels ---------------------------------------------------------------------

func _run_duels() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(opts["seed"])
	var pr := _power_range()
	var target := sqrt(pr.x * pr.y)   # one power for every duel (the middle of the range)
	var squads := {}
	for u in _pool:
		squads[u] = _squad_at_power(u, target)
	var pairs: Array = []
	for i in _pool.size():
		for k in range(i + 1, _pool.size()):
			pairs.append([_pool[i], _pool[k]])
	var matrix := {}           # u -> {v: score of u vs v, 0..1}
	var units := {}
	var done := 0
	var batch_size := maxi(16, int(opts["threads"]) * 8)
	while done < pairs.size() and not (float(opts["minutes"]) > 0.0 and Time.get_ticks_msec() - _t0 > int(float(opts["minutes"]) * 60000.0)):
		var jobs: Array = []
		var sims: Array = []
		for p in pairs.slice(done, mini(done + batch_size, pairs.size())):
			var map := _map(rng) if opts["map"] != "" else "open_arena"
			var seed_v := rng.randi()
			var s1 := BattleSim.new()
			s1.setup([squads[p[0]]], [squads[p[1]]], seed_v, map)
			var s2 := BattleSim.new()
			s2.setup([squads[p[1]]], [squads[p[0]]], seed_v, map)
			sims.append_array([s1, s2])
			jobs.append([p[0], p[1], s1, s2])
		_run_batch(sims)
		for j in jobs:
			var su := (_score(j[2], 0) + _score(j[3], 1)) / 2.0
			if not matrix.has(j[0]):
				matrix[j[0]] = {}
			if not matrix.has(j[1]):
				matrix[j[1]] = {}
			matrix[j[0]][j[1]] = su
			matrix[j[1]][j[0]] = 1.0 - su
			_add(units, j[0], 2, su * 2.0)
			_add(units, j[1], 2, (1.0 - su) * 2.0)
		done += jobs.size()
		print("  %d / %d matchups, %ds" % [done, pairs.size(), (Time.get_ticks_msec() - _t0) / 1000])
	var lines: Array = []
	lines.append("Duel run: patch %s, %d units, %d matchups (each fought from both sides), every squad at power %d, map %s, seed %d" % [
		ProjectSettings.get_setting("application/config/version"), _pool.size(), done, roundi(target / 10.0), opts["map"] if opts["map"] != "" else "open_arena", opts["seed"]])
	lines.append("")
	lines.append(_unit_table(units, "One squad vs one squad at equal power: share of duels won"))
	lines.append("")
	lines.append("Matchups: each unit's 3 worst and 3 best opponents (its share of those duels won).")
	lines.append("Healers can't win a duel alone; their numbers only mean something in armies.")
	for u in _pool:
		if not matrix.has(u):
			continue
		var opp: Array = matrix[u].keys()
		opp.sort_custom(func(x, y): return matrix[u][x] < matrix[u][y])
		var worst: Array = opp.slice(0, 3).map(func(v): return "%s %d%%" % [_short(v), roundi(100.0 * matrix[u][v])])
		var best: Array = opp.slice(maxi(0, opp.size() - 3)).map(func(v): return "%s %d%%" % [_short(v), roundi(100.0 * matrix[u][v])])
		best.reverse()
		lines.append("  %-20s worst: %-48s best: %s" % [_short(u), ", ".join(PackedStringArray(worst)), ", ".join(PackedStringArray(best))])
	_finish(lines, units, matrix)


static func _short(u: String) -> String:
	return str(GameData.UNITS[u]["name"]).left(20)


## One squad of a unit, upgraded (tier, then level) until it reaches target power.
func _squad_at_power(u: String, target: float) -> Dictionary:
	var sq := {"unit": u, "level": 1, "tier": 0, "row": GameData.default_row_for(u)}
	for _i in 400:
		if Army.army_power([sq]) >= target:
			break
		if int(sq["level"]) < Army.max_level_for_tier(int(sq["tier"])):
			sq["level"] = int(sq["level"]) + 1
		elif int(sq["tier"]) < GameData.MAX_TIER:
			sq["tier"] = int(sq["tier"]) + 1
		else:
			break
	return sq


# --- output --------------------------------------------------------------------

func _finish(lines: Array, units: Dictionary, matrix) -> void:
	var stamp := Time.get_datetime_string_from_system().replace(":", "").replace("T", "-").left(17)
	var base := "%s/balance_%s_%s_%s" % [opts["out"], opts["mode"], str(ProjectSettings.get_setting("application/config/version")), stamp]
	var text := "\n".join(PackedStringArray(lines))
	print("")
	print(text)
	var f := FileAccess.open(base + ".txt", FileAccess.WRITE)
	if f:
		f.store_string(text + "\n")
		f.close()
	f = FileAccess.open(base + ".csv", FileAccess.WRITE)
	if f:
		f.store_line("unit,name,rarity,role,games,win_rate")
		for u in units:
			f.store_line("%s,\"%s\",%s,%s,%d,%.4f" % [u, GameData.UNITS[u]["name"], GameData.UNITS[u]["rarity"], GameData.UNITS[u]["role"], units[u][0], units[u][1] / units[u][0]])
		f.close()
	if matrix != null:
		f = FileAccess.open(base + "_matrix.csv", FileAccess.WRITE)
		if f:
			var ids: Array = matrix.keys()
			f.store_line("unit vs," + ",".join(PackedStringArray(ids)))
			for u in ids:
				var cells: Array = [u]
				for v in ids:
					cells.append("" if u == v else "%.3f" % float(matrix[u].get(v, 0.5)))
				f.store_line(",".join(PackedStringArray(cells)))
			f.close()
	print("")
	print("Saved %s.txt and .csv%s" % [ProjectSettings.globalize_path(base), " (+ _matrix.csv)" if matrix != null else ""])
	print("Took %ds." % ((Time.get_ticks_msec() - _t0) / 1000))
