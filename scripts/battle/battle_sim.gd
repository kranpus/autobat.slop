class_name BattleSim
extends RefCounted
## Deterministic, data-oriented battle simulation built for 1000+ units.
##
## All per-unit state lives in packed arrays (struct-of-arrays) and spatial
## queries go through a uniform grid, so the whole fight runs in plain
## GDScript without physics nodes. Given the same armies and seed, every
## machine produces the same result, which is what PvP relies on: players
## exchange army codes + a seed and each client simulates locally.

const DT := 0.05                 # 20 simulation ticks per second
const MAX_TIME := 150.0          # seconds before the fight is decided on remaining HP
const OBSTACLE_MARGIN := 24.0     # max unit radius, used when bucketing obstacles into cells
const STUCK_TICKS := 20           # flip detour direction after this many ticks without progress
const CELL := 64.0
const RETARGET_TICKS := 12
const SEARCH_RINGS := 4
const FALLBACK_SAMPLES := 24
const SEPARATION_CHECKS := 10
const AOE_SPLASH_MULT := 0.6
const MAX_SPLASH_TARGETS := 6     # keeps splash damage from scaling with crowd density
const HALF_NEIGHBOURS := [Vector2i(1, 0), Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1)]

enum Ev { MELEE_HIT, SHOT, IMPACT, BLAST, HEAL, DIE }
enum Role { MELEE, RANGED, CASTER, HEALER, TANK }

# --- unit state -------------------------------------------------------------
var n := 0
var unit_ids: Array = []          # kind index -> unit id
var kind := PackedInt32Array()
var team := PackedInt32Array()
var alive := PackedInt32Array()
var role := PackedInt32Array()
var dtype := PackedInt32Array()
var armor := PackedInt32Array()
var flying := PackedInt32Array()
var proj := PackedInt32Array()
var target := PackedInt32Array()
var target_ally := PackedInt32Array()
var hit_tick := PackedInt32Array()
var death_tick := PackedInt32Array()
var attack_tick := PackedInt32Array()
var px := PackedFloat32Array()
var py := PackedFloat32Array()
var prev_x := PackedFloat32Array()
var prev_y := PackedFloat32Array()
var hp := PackedFloat32Array()
var max_hp := PackedFloat32Array()
var dmg := PackedFloat32Array()
var reach := PackedFloat32Array()
var speed := PackedFloat32Array()
var cooldown := PackedFloat32Array()
var cd_t := PackedFloat32Array()
var aoe := PackedFloat32Array()
var heal := PackedFloat32Array()
var regen := PackedFloat32Array()
var radius := PackedFloat32Array()

# --- projectiles (pooled) ---------------------------------------------------
var pr_count := 0
var pr_alive := PackedInt32Array()
var pr_kind := PackedInt32Array()
var pr_team := PackedInt32Array()
var pr_target := PackedInt32Array()
var pr_dtype := PackedInt32Array()
var pr_x := PackedFloat32Array()
var pr_y := PackedFloat32Array()
var pr_tx := PackedFloat32Array()
var pr_ty := PackedFloat32Array()
var pr_dmg := PackedFloat32Array()
var pr_aoe := PackedFloat32Array()
var pr_speed := PackedFloat32Array()
var pr_ang := PackedFloat32Array()
var pr_free: Array[int] = []

# --- map & obstacles --------------------------------------------------------
var map_id := BattleMaps.DEFAULT_MAP
var map_w := 2400.0
var map_h := 1400.0
var ob_x := PackedFloat32Array()
var ob_y := PackedFloat32Array()
var ob_r := PackedFloat32Array()
var cell_obs: Array = []          # cell -> PackedInt32Array of obstacles touching it
var detour := PackedInt32Array()  # per unit: 0 none, +1 / -1 direction to walk around obstacles
var detour_timer := PackedInt32Array()
var stuck := PackedInt32Array()

# --- spatial grid -----------------------------------------------------------
var gw := 0
var gh := 0
var cell_head := PackedInt32Array()
var cell_next := PackedInt32Array()
var team_lists: Array = [PackedInt32Array(), PackedInt32Array()]

# --- battle state -----------------------------------------------------------
var tick := 0
var time := 0.0
var finished := false
var winner := -1                  # 0 / 1, or 2 for a draw
var alive_count: Array[int] = [0, 0]
var start_count: Array[int] = [0, 0]
var start_hp: Array[float] = [0.0, 0.0]
var events: Array = []            # [Ev, x, y, extra] accumulated until drained
var rng := RandomNumberGenerator.new()


## squads_a / squads_b: arrays of squad dictionaries (see Army).
## map: an id from BattleMaps.MAPS.
func setup(squads_a: Array, squads_b: Array, seed_value: int, map: String = BattleMaps.DEFAULT_MAP) -> void:
	rng.seed = seed_value
	map_id = map if BattleMaps.MAPS.has(map) else BattleMaps.DEFAULT_MAP
	var size := BattleMaps.map_size(map_id)
	map_w = size.x
	map_h = size.y
	gw = int(ceil(map_w / CELL))
	gh = int(ceil(map_h / CELL))
	cell_head.resize(gw * gh)
	_build_obstacles()
	_spawn_army(squads_a, 0)
	_spawn_army(squads_b, 1)
	cell_next.resize(n)
	_resolve_obstacles()
	_rebuild_team_lists()


func _build_obstacles() -> void:
	cell_obs.resize(gw * gh)
	for c in gw * gh:
		cell_obs[c] = PackedInt32Array()
	for o in BattleMaps.obstacles(map_id):
		var idx := ob_x.size()
		ob_x.append(float(o[1]))
		ob_y.append(float(o[2]))
		ob_r.append(float(o[3]))
		var reach_r := float(o[3]) + OBSTACLE_MARGIN
		var x0 := clampi(int((float(o[1]) - reach_r) / CELL), 0, gw - 1)
		var x1 := clampi(int((float(o[1]) + reach_r) / CELL), 0, gw - 1)
		var y0 := clampi(int((float(o[2]) - reach_r) / CELL), 0, gh - 1)
		var y1 := clampi(int((float(o[2]) + reach_r) / CELL), 0, gh - 1)
		for gy in range(y0, y1 + 1):
			for gx in range(x0, x1 + 1):
				var list: PackedInt32Array = cell_obs[gy * gw + gx]
				list.append(idx)
				cell_obs[gy * gw + gx] = list


func _kind_index(uid: String) -> int:
	var k := unit_ids.find(uid)
	if k == -1:
		unit_ids.append(uid)
		k = unit_ids.size() - 1
	return k


func _spawn_army(squads: Array, t: int) -> void:
	var counts := Army.deploy_counts(squads)
	# Group squads by row and lay them out as blocks.
	# Distance of each row from the centre line scales with map width.
	var row_x := {"front": map_w * 0.15, "middle": map_w * 0.27, "back": map_w * 0.38}
	for row in GameData.ROWS:
		var members: Array = []
		for i in squads.size():
			if squads[i]["row"] == row and int(counts[i]) > 0:
				members.append(i)
		if members.is_empty():
			continue
		# Choose block depth (columns) so the row fits the map height.
		var depth_cols: Array = []
		for i in members:
			depth_cols.append(clampi(ceili(sqrt(float(counts[i]) / 4.0)), 1, 14))
		for _guard in 40:
			var total_h := 0.0
			for m in members.size():
				var i: int = members[m]
				var spacing := _spacing(squads[i]["unit"])
				total_h += ceilf(float(counts[i]) / float(depth_cols[m])) * spacing + 24.0
			if total_h <= map_h - 120.0:
				break
			for m in members.size():
				depth_cols[m] = int(depth_cols[m]) + 1
		var heights: Array = []
		var sum_h := 0.0
		for m in members.size():
			var i: int = members[m]
			var h := ceilf(float(counts[i]) / float(depth_cols[m])) * _spacing(squads[i]["unit"])
			heights.append(h)
			sum_h += h + 24.0
		var y_cursor := (map_h - sum_h) * 0.5 + 12.0
		for m in members.size():
			var i: int = members[m]
			var sq: Dictionary = squads[i]
			var cols: int = depth_cols[m]
			var spacing := _spacing(sq["unit"])
			var stats := Army.unit_stats(sq["unit"], int(sq["level"]))
			var front_x := map_w * 0.5 - float(row_x[row])
			for u in int(counts[i]):
				var c := u % cols
				@warning_ignore("integer_division")
				var rr := u / cols
				var x := maxf(12.0, front_x - float(c) * spacing + rng.randf_range(-2.0, 2.0))
				var y := clampf(y_cursor + float(rr) * spacing + spacing * 0.5 + rng.randf_range(-2.0, 2.0), 8.0, map_h - 8.0)
				if t == 1:
					x = map_w - x
				_add_unit(sq["unit"], stats, t, x, y)
			y_cursor += float(heights[m]) + 24.0


func _spacing(uid: String) -> float:
	return float(GameData.UNITS[uid]["radius"]) * 2.0 + 3.0


func _add_unit(uid: String, s: Dictionary, t: int, x: float, y: float) -> void:
	var i := n
	n += 1
	kind.append(_kind_index(uid))
	team.append(t)
	alive.append(1)
	role.append(GameData.ROLES.find(s["role"]))
	dtype.append(GameData.DAMAGE_TYPES.find(s["damage"]))
	armor.append(GameData.ARMOR_TYPES.find(s["armor"]))
	flying.append(1 if s["flying"] else 0)
	proj.append(GameData.PROJECTILES.find(s["projectile"]))
	target.append(-1)
	target_ally.append(0)
	hit_tick.append(-100)
	death_tick.append(-1)
	attack_tick.append(-100)
	detour.append(0)
	detour_timer.append(0)
	stuck.append(0)
	px.append(x)
	py.append(y)
	prev_x.append(x)
	prev_y.append(y)
	hp.append(s["hp"])
	max_hp.append(s["hp"])
	dmg.append(s["dmg"])
	reach.append(s["range"])
	speed.append(s["speed"])
	cooldown.append(s["cooldown"])
	cd_t.append(rng.randf_range(0.0, float(s["cooldown"])))
	aoe.append(s["aoe"])
	heal.append(s["heal"])
	regen.append(s["regen"])
	radius.append(s["radius"])
	alive_count[t] += 1
	start_count[t] += 1
	start_hp[t] += float(s["hp"])
	assert(i == n - 1)


# --- main loop --------------------------------------------------------------

func step() -> void:
	if finished:
		return
	tick += 1
	time += DT
	_rebuild_grid()
	if tick % 5 == 0:
		_rebuild_team_lists()
	for i in n:
		prev_x[i] = px[i]
		prev_y[i] = py[i]
		if alive[i] == 0:
			continue
		if regen[i] > 0.0 and hp[i] < max_hp[i]:
			hp[i] = minf(max_hp[i], hp[i] + regen[i] * DT)
		cd_t[i] -= DT
		if role[i] == Role.HEALER:
			_healer_ai(i)
		else:
			_combat_ai(i)
	_separate()
	_resolve_obstacles()
	_update_projectiles()
	_check_end()


func run_to_end(max_ticks: int = 100000) -> void:
	var guard := 0
	while not finished and guard < max_ticks:
		step()
		events.clear()
		guard += 1


func drain_events() -> Array:
	var e := events
	events = []
	return e


# --- AI ---------------------------------------------------------------------

func _combat_ai(i: int) -> void:
	var t := target[i]
	if t < 0 or alive[t] == 0 or target_ally[i] == 1 or (tick + i) % RETARGET_TICKS == 0:
		t = _find_enemy(i)
		target[i] = t
		target_ally[i] = 0
	if t < 0:
		return
	_approach_and_act(i, t, false)


func _healer_ai(i: int) -> void:
	var t := target[i]
	var need_new := t < 0 or alive[t] == 0 or (tick + i) % RETARGET_TICKS == 0
	if not need_new and target_ally[i] == 1 and hp[t] >= max_hp[t]:
		need_new = true
	if need_new:
		t = _find_wounded_ally(i)
		if t >= 0:
			target_ally[i] = 1
		else:
			t = _find_enemy(i)
			target_ally[i] = 0
		target[i] = t
	if t < 0:
		return
	_approach_and_act(i, t, target_ally[i] == 1)


func _approach_and_act(i: int, t: int, healing: bool) -> void:
	var dx := px[t] - px[i]
	var dy := py[t] - py[i]
	var d2 := dx * dx + dy * dy
	var r := reach[i] + radius[i] + radius[t]
	if d2 > r * r:
		var d := sqrt(d2)
		_move(i, dx / d, dy / d, minf(speed[i] * DT, d - r + 0.5))
		return
	if cd_t[i] > 0.0:
		return
	cd_t[i] = cooldown[i]
	attack_tick[i] = tick
	if healing:
		hp[t] = minf(max_hp[t], hp[t] + heal[i])
		events.append([Ev.HEAL, px[t], py[t], t])
		return
	if proj[i] == 0:
		events.append([Ev.MELEE_HIT, px[t], py[t], i])
		_deal_damage(team[i], dtype[i], dmg[i], t, px[t], py[t], aoe[i], true)
	else:
		_spawn_projectile(i, t)
		events.append([Ev.SHOT, px[i], py[i], proj[i]])


func _find_enemy(i: int) -> int:
	var my_team := team[i]
	var x := px[i]
	var y := py[i]
	var cx := clampi(int(x / CELL), 0, gw - 1)
	var cy := clampi(int(y / CELL), 0, gh - 1)
	var best := -1
	var best_d2 := INF
	var found_ring := -1
	for ring in SEARCH_RINGS + 1:
		for gy in range(cy - ring, cy + ring + 1):
			if gy < 0 or gy >= gh:
				continue
			for gx in range(cx - ring, cx + ring + 1):
				if gx < 0 or gx >= gw:
					continue
				if absi(gx - cx) != ring and absi(gy - cy) != ring:
					continue
				var j := cell_head[gy * gw + gx]
				while j != -1:
					if team[j] != my_team and alive[j] == 1:
						var dx := px[j] - x
						var dy := py[j] - y
						var d2 := dx * dx + dy * dy
						if d2 < best_d2:
							best_d2 = d2
							best = j
					j = cell_next[j]
		if best != -1:
			if found_ring == -1:
				found_ring = ring
			elif ring > found_ring:
				break  # scanned one extra ring for correctness, done
	if best != -1:
		return best
	# Nothing nearby: sample the enemy army to pick a direction of travel.
	var list: PackedInt32Array = team_lists[1 - my_team]
	var count := list.size()
	if count == 0:
		return -1
	var stride := maxi(1, count / FALLBACK_SAMPLES)
	var offset := i % stride
	var k := offset
	while k < count:
		var j := list[k]
		if alive[j] == 1:
			var dx := px[j] - x
			var dy := py[j] - y
			var d2 := dx * dx + dy * dy
			if d2 < best_d2:
				best_d2 = d2
				best = j
		k += stride
	return best


func _find_wounded_ally(i: int) -> int:
	var my_team := team[i]
	var x := px[i]
	var y := py[i]
	var search := reach[i] + 120.0
	var rings := mini(3, ceili(search / CELL))
	var cx := clampi(int(x / CELL), 0, gw - 1)
	var cy := clampi(int(y / CELL), 0, gh - 1)
	var best := -1
	var best_ratio := 0.95
	for gy in range(maxi(0, cy - rings), mini(gh, cy + rings + 1)):
		for gx in range(maxi(0, cx - rings), mini(gw, cx + rings + 1)):
			var j := cell_head[gy * gw + gx]
			while j != -1:
				if j != i and team[j] == my_team and alive[j] == 1:
					var ratio := hp[j] / max_hp[j]
					if ratio < best_ratio:
						var dx := px[j] - x
						var dy := py[j] - y
						if dx * dx + dy * dy <= search * search:
							best_ratio = ratio
							best = j
				j = cell_next[j]
	return best


# --- damage -----------------------------------------------------------------

func _deal_damage(src_team: int, dt_idx: int, amount: float, primary: int, x: float, y: float, radius_aoe: float, melee: bool) -> void:
	if primary >= 0 and alive[primary] == 1:
		_damage_unit(primary, amount, dt_idx, melee)
	if radius_aoe <= 0.0:
		return
	events.append([Ev.BLAST, x, y, radius_aoe])
	var splash := amount * AOE_SPLASH_MULT
	var hits := 0
	var rings := ceili(radius_aoe / CELL)
	var cx := clampi(int(x / CELL), 0, gw - 1)
	var cy := clampi(int(y / CELL), 0, gh - 1)
	for gy in range(maxi(0, cy - rings), mini(gh, cy + rings + 1)):
		for gx in range(maxi(0, cx - rings), mini(gw, cx + rings + 1)):
			var j := cell_head[gy * gw + gx]
			while j != -1:
				if j != primary and team[j] != src_team and alive[j] == 1:
					var dx := px[j] - x
					var dy := py[j] - y
					var rr := radius_aoe + radius[j]
					if dx * dx + dy * dy <= rr * rr:
						_damage_unit(j, splash, dt_idx, melee)
						hits += 1
						if hits >= MAX_SPLASH_TARGETS:
							return
				j = cell_next[j]


func _damage_unit(j: int, amount: float, dt_idx: int, melee: bool) -> void:
	var row: Array = GameData.DAMAGE_MULT[dt_idx]
	var m: float = row[armor[j]]
	if melee and flying[j] == 1:
		m *= GameData.MELEE_VS_FLYING_MULT
	hp[j] -= amount * m * rng.randf_range(0.9, 1.1)
	hit_tick[j] = tick
	if hp[j] <= 0.0 and alive[j] == 1:
		hp[j] = 0.0
		alive[j] = 0
		death_tick[j] = tick
		alive_count[team[j]] -= 1
		events.append([Ev.DIE, px[j], py[j], j])


# --- projectiles ------------------------------------------------------------

func _spawn_projectile(i: int, t: int) -> void:
	var p: int
	if pr_free.is_empty():
		p = pr_count
		pr_count += 1
		pr_alive.append(0)
		pr_kind.append(0)
		pr_team.append(0)
		pr_target.append(-1)
		pr_dtype.append(0)
		pr_x.append(0.0)
		pr_y.append(0.0)
		pr_tx.append(0.0)
		pr_ty.append(0.0)
		pr_dmg.append(0.0)
		pr_aoe.append(0.0)
		pr_speed.append(0.0)
		pr_ang.append(0.0)
	else:
		p = pr_free.pop_back()
	pr_alive[p] = 1
	pr_kind[p] = proj[i]
	pr_team[p] = team[i]
	pr_target[p] = t
	pr_dtype[p] = dtype[i]
	pr_x[p] = px[i]
	pr_y[p] = py[i] - radius[i] * 0.5
	pr_tx[p] = px[t]
	pr_ty[p] = py[t]
	pr_dmg[p] = dmg[i]
	pr_aoe[p] = aoe[i]
	pr_speed[p] = GameData.PROJECTILE_SPEED[proj[i]]
	pr_ang[p] = atan2(py[t] - py[i], px[t] - px[i])


func _update_projectiles() -> void:
	for p in pr_count:
		if pr_alive[p] == 0:
			continue
		var t := pr_target[p]
		if t >= 0 and alive[t] == 1:
			pr_tx[p] = px[t]
			pr_ty[p] = py[t]
		else:
			pr_target[p] = -1
		var dx := pr_tx[p] - pr_x[p]
		var dy := pr_ty[p] - pr_y[p]
		var d := sqrt(dx * dx + dy * dy)
		var stp := pr_speed[p] * DT
		if d <= stp:
			pr_alive[p] = 0
			pr_free.append(p)
			events.append([Ev.IMPACT, pr_tx[p], pr_ty[p], pr_kind[p]])
			_deal_damage(pr_team[p], pr_dtype[p], pr_dmg[p], pr_target[p], pr_tx[p], pr_ty[p], pr_aoe[p], false)
		else:
			pr_x[p] += dx / d * stp
			pr_y[p] += dy / d * stp
			pr_ang[p] = atan2(dy, dx)


# --- movement & obstacles ---------------------------------------------------

## Move unit i along (nx, ny) by mv pixels. Ground units that would walk into
## an obstacle slide around it instead, keeping a consistent direction
## (detour) so they work their way along rivers and walls, and flip that
## direction if they stop making progress (e.g. pinned against the map edge).
func _move(i: int, nx: float, ny: float, mv: float) -> void:
	var x := px[i] + nx * mv
	var y := py[i] + ny * mv
	var blocked := false
	if flying[i] == 0 and not ob_x.is_empty():
		var obs: PackedInt32Array = cell_obs[_cell_of(x, y)]
		for o in obs:
			var ox := x - ob_x[o]
			var oy := y - ob_y[o]
			var rr := ob_r[o] + radius[i]
			if ox * ox + oy * oy >= rr * rr:
				continue
			blocked = true
			# Outward normal from the obstacle at the unit's current position.
			var ux := px[i] - ob_x[o]
			var uy := py[i] - ob_y[o]
			var ul := sqrt(ux * ux + uy * uy)
			if ul < 0.001:
				ux = 1.0
				uy = 0.0
				ul = 1.0
			ux /= ul
			uy /= ul
			if detour[i] == 0:
				# Pick the side of the obstacle that heads toward the goal.
				var side := -uy * nx + ux * ny
				if absf(side) < 0.05:
					detour[i] = 1 if i % 2 == 0 else -1
				else:
					detour[i] = 1 if side > 0.0 else -1
			var tx := -uy * float(detour[i])
			var ty := ux * float(detour[i])
			x = px[i] + tx * mv
			y = py[i] + ty * mv
			# Stay on the obstacle's edge.
			var ex := x - ob_x[o]
			var ey := y - ob_y[o]
			var el := sqrt(ex * ex + ey * ey)
			if el < rr and el > 0.001:
				x = ob_x[o] + ex / el * rr
				y = ob_y[o] + ey / el * rr
			break
	x = clampf(x, 0.0, map_w)
	y = clampf(y, 0.0, map_h)
	if blocked:
		detour_timer[i] = 30
		var moved := absf(x - px[i]) + absf(y - py[i])
		if moved < mv * 0.3:
			stuck[i] += 1
			if stuck[i] > STUCK_TICKS:
				detour[i] = -detour[i]
				stuck[i] = 0
		else:
			stuck[i] = 0
	elif detour_timer[i] > 0:
		detour_timer[i] -= 1
		if detour_timer[i] == 0:
			detour[i] = 0
			stuck[i] = 0
	px[i] = x
	py[i] = y


## Push ground units that ended up inside an obstacle (spawn, crowd pushing)
## back out to its edge.
func _resolve_obstacles() -> void:
	if ob_x.is_empty():
		return
	for i in n:
		if alive[i] == 0 or flying[i] == 1:
			continue
		var obs: PackedInt32Array = cell_obs[_cell_of(px[i], py[i])]
		# Two passes so units wedged where two obstacles overlap settle outside both.
		for _pass in 2:
			for o in obs:
				var ox := px[i] - ob_x[o]
				var oy := py[i] - ob_y[o]
				var rr := ob_r[o] + radius[i]
				var d2 := ox * ox + oy * oy
				if d2 >= rr * rr:
					continue
				var d := sqrt(d2)
				if d < 0.001:
					ox = 1.0 if team[i] == 0 else -1.0
					oy = 0.0
					d = 1.0
				px[i] = clampf(ob_x[o] + ox / d * rr, 0.0, map_w)
				py[i] = clampf(ob_y[o] + oy / d * rr, 0.0, map_h)
				# Still inside because the map edge clamped us? Push sideways instead.
				var ey := py[i] - ob_y[o]
				var ex := px[i] - ob_x[o]
				if ex * ex + ey * ey < rr * rr:
					var hx := sqrt(maxf(0.0, rr * rr - ey * ey))
					px[i] = clampf(ob_x[o] + (hx if ex >= 0.0 else -hx), 0.0, map_w)


func _cell_of(x: float, y: float) -> int:
	return clampi(int(y / CELL), 0, gh - 1) * gw + clampi(int(x / CELL), 0, gw - 1)


## True if the point is inside any obstacle (for tools/AI; flyers ignore this).
func is_blocked(x: float, y: float, r: float = 0.0) -> bool:
	if ob_x.is_empty():
		return false
	var obs: PackedInt32Array = cell_obs[_cell_of(x, y)]
	for o in obs:
		var dx := x - ob_x[o]
		var dy := y - ob_y[o]
		if dx * dx + dy * dy < (ob_r[o] + r) * (ob_r[o] + r):
			return true
	return false


# --- spatial helpers --------------------------------------------------------

func _rebuild_grid() -> void:
	cell_head.fill(-1)
	for i in n:
		if alive[i] == 0:
			continue
		var c := clampi(int(py[i] / CELL), 0, gh - 1) * gw + clampi(int(px[i] / CELL), 0, gw - 1)
		cell_next[i] = cell_head[c]
		cell_head[c] = i


func _rebuild_team_lists() -> void:
	var a := PackedInt32Array()
	var b := PackedInt32Array()
	for i in n:
		if alive[i] == 1:
			if team[i] == 0:
				a.append(i)
			else:
				b.append(i)
	team_lists = [a, b]


## Push overlapping units apart. Uses the grid built at the start of the tick
## and checks the unit's own cell plus half of its neighbourhood, so every
## nearby pair is considered once.
func _separate() -> void:
	for i in n:
		if alive[i] == 0:
			continue
		var cx := clampi(int(px[i] / CELL), 0, gw - 1)
		var cy := clampi(int(py[i] / CELL), 0, gh - 1)
		var checks := 0
		# own cell: only units after i in the chain
		var j := cell_next[i]
		while j != -1 and checks < SEPARATION_CHECKS:
			checks += 1
			_push_pair(i, j)
			j = cell_next[j]
		# half neighbourhood: right, down-left, down, down-right
		for off in HALF_NEIGHBOURS:
			var gx: int = cx + off.x
			var gy: int = cy + off.y
			if gx < 0 or gx >= gw or gy >= gh:
				continue
			j = cell_head[gy * gw + gx]
			while j != -1 and checks < SEPARATION_CHECKS:
				checks += 1
				_push_pair(i, j)
				j = cell_next[j]


func _push_pair(i: int, j: int) -> void:
	if alive[j] == 0 or flying[i] != flying[j]:
		return
	var dx := px[j] - px[i]
	var dy := py[j] - py[i]
	var min_d := radius[i] + radius[j]
	var d2 := dx * dx + dy * dy
	if d2 >= min_d * min_d:
		return
	if d2 < 0.0001:
		dx = float((i % 7) - 3) * 0.1 + 0.05
		dy = float((j % 5) - 2) * 0.1 + 0.05
		d2 = dx * dx + dy * dy
	var d := sqrt(d2)
	var push := (min_d - d) * 0.5
	# Heavier (bigger) units get pushed less.
	var wi := radius[j] / (radius[i] + radius[j])
	var wj := 1.0 - wi
	var nx := dx / d
	var ny := dy / d
	px[i] = clampf(px[i] - nx * push * wi * 2.0, 0.0, map_w)
	py[i] = clampf(py[i] - ny * push * wi * 2.0, 0.0, map_h)
	px[j] = clampf(px[j] + nx * push * wj * 2.0, 0.0, map_w)
	py[j] = clampf(py[j] + ny * push * wj * 2.0, 0.0, map_h)


# --- end conditions ---------------------------------------------------------

func _check_end() -> void:
	if alive_count[0] == 0 and alive_count[1] == 0:
		_finish(2)
	elif alive_count[1] == 0:
		_finish(0)
	elif alive_count[0] == 0:
		_finish(1)
	elif time >= MAX_TIME:
		var a := remaining_hp_ratio(0)
		var b := remaining_hp_ratio(1)
		if absf(a - b) < 0.001:
			_finish(2)
		else:
			_finish(0 if a > b else 1)


func _finish(w: int) -> void:
	finished = true
	winner = w


func remaining_hp_ratio(t: int) -> float:
	var total := 0.0
	for i in n:
		if team[i] == t and alive[i] == 1:
			total += hp[i]
	return total / maxf(1.0, start_hp[t])


## Compact fingerprint of the final state, used to verify both PvP clients
## simulated the same battle.
func checksum() -> int:
	var h := 1469598103
	for i in n:
		h = (h * 31 + int(hp[i] * 10.0) + alive[i] * 7) & 0x7fffffff
	h = (h * 31 + tick) & 0x7fffffff
	h = (h * 31 + winner) & 0x7fffffff
	return h
