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
const AOE_SPLASH_MULT := 0.45       # splash damage of melee attacks, as a share of the hit (0.6 before 0.9.2)
const RANGED_SPLASH_MULT := 0.35    # ...and of projectiles (0.6 before patch 0.9, 0.45 in 0.9)
const MAX_SPLASH_TARGETS := 6     # keeps splash damage from scaling with crowd density
const HALF_NEIGHBOURS := [Vector2i(1, 0), Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1)]

enum Ev { MELEE_HIT, SHOT, IMPACT, BLAST, HEAL, DIE, CHAIN, STUN, REBIRTH, RAISE, CHARGE, QUAKE, RESURRECT, AURA, ABILITY, STRIKE, WAVE }
## Battle abilities (GameData "ability": {"id", "value"}); see GameData.ABILITIES.
enum Ab { NONE, STUN, CHILL, BURN, CHAIN, REBIRTH, CHARGE, DOUBLE_STRIKE, CURSE, WEAKEN, UNSTOPPABLE, DEVOUR, RAISE_DEAD,
	QUAKE, PREDATOR, KNOCKBACK, DEATH_BLAST, HEADS, SOUL_HARVEST, DREAD, RISING_STORM, RESURRECT, AEGIS,
	VENOM, PURIFY, SPLIT, SHELL, ENSNARE, POUNCE, CORRODE, SPIKES, SUMMON, BLINK, BLOCK, VOLLEY, EVASION,
	SONG, UNDERTOW, FRENZY, TAUNT, PULL, TIDAL_WAVE, DETONATE, MARTYR, PACK, REFLECT, BERSERK, THUNDERSTRIKE,
	IMMOLATE, EXECUTE, TERROR, WARD, INSPIRE, FROST_ARMOR, FROST_AURA, ENTOMB, FORTIFY, PHASE, AVALANCHE }
const AB_IDS := {"stun": Ab.STUN, "chill": Ab.CHILL, "burn": Ab.BURN, "chain": Ab.CHAIN, "rebirth": Ab.REBIRTH,
	"charge": Ab.CHARGE, "double_strike": Ab.DOUBLE_STRIKE, "curse": Ab.CURSE, "weaken": Ab.WEAKEN,
	"unstoppable": Ab.UNSTOPPABLE, "devour": Ab.DEVOUR, "raise_dead": Ab.RAISE_DEAD,
	"quake": Ab.QUAKE, "predator": Ab.PREDATOR, "knockback": Ab.KNOCKBACK, "death_blast": Ab.DEATH_BLAST,
	"heads": Ab.HEADS, "soul_harvest": Ab.SOUL_HARVEST, "dread": Ab.DREAD, "rising_storm": Ab.RISING_STORM,
	"resurrect": Ab.RESURRECT, "aegis": Ab.AEGIS,
	"venom": Ab.VENOM, "purify": Ab.PURIFY, "split": Ab.SPLIT, "shell": Ab.SHELL, "ensnare": Ab.ENSNARE,
	"pounce": Ab.POUNCE, "corrode": Ab.CORRODE, "spikes": Ab.SPIKES, "summon": Ab.SUMMON, "blink": Ab.BLINK,
	"block": Ab.BLOCK, "volley": Ab.VOLLEY, "evasion": Ab.EVASION, "song": Ab.SONG, "undertow": Ab.UNDERTOW,
	"frenzy": Ab.FRENZY, "taunt": Ab.TAUNT, "pull": Ab.PULL, "tidal_wave": Ab.TIDAL_WAVE, "detonate": Ab.DETONATE,
	"martyr": Ab.MARTYR, "pack": Ab.PACK, "reflect": Ab.REFLECT, "berserk": Ab.BERSERK, "thunderstrike": Ab.THUNDERSTRIKE,
	"immolate": Ab.IMMOLATE, "execute": Ab.EXECUTE, "terror": Ab.TERROR, "ward": Ab.WARD, "inspire": Ab.INSPIRE,
	"frost_armor": Ab.FROST_ARMOR, "frost_aura": Ab.FROST_AURA, "entomb": Ab.ENTOMB, "fortify": Ab.FORTIFY,
	"phase": Ab.PHASE, "avalanche": Ab.AVALANCHE}
const QUAKE_EVERY := 3            # every 3rd blow shakes the ground
const QUAKE_RADIUS := 70.0
const DEATH_BLAST_RADIUS := 90.0
const AURA_RADIUS := 150.0        # dread and divine aegis
const AURA_TICKS := 10            # auras refresh twice a second
const CHAMPION_AURA_MULT := 1.8    # a champion's aura radius (x AURA_RADIUS)
const CHAMPION_AURA_CAP := 160     # ...and how many it reaches
const CHAMPION_FX_CAP := 600       # how many units one champion effect reaches
const CHAMPION_FIRST_SUMMON := 5.0 # the first summoned wave comes after this many seconds
const AEGIS_MULT := 0.8           # allies under divine aegis take 20% less damage
const HARVEST_MAX_STACKS := 5     # soul harvest: +10% damage per kill, up to +50%
const STORM_MAX_STACKS := 20      # rising storm: up to 20 stacks
const RESURRECT_RANGE := 300.0
const MAX_AREA_TARGETS := 10
# The 0.9.4 set.
const POISON_SECONDS := 5.0
const POISON_MAX_STACKS := 5
const SHELL_MULT := 0.4           # shell: 60% less damage
const ENTOMB_MULT := 0.5          # entombed: half damage
const CORRODE_MAX := 0.3
const PACK_RADIUS := 70.0
const PACK_MAX := 5
const FRENZY_MAX := 5
const MARTYR_RAGE := 0.25
const MARTYR_RADIUS := 90.0
const EXECUTE_BELOW := 0.3
const FORTIFY_MAX := 0.4
const SUMMON_EVERY := 5.0
const SUMMON_UNIT := "cave_spider"
const WAVE_RADIUS := 110.0
const WAVE_MULT := 1.0            # tidal wave / avalanche damage, x the unit's damage
const STRIKE_MULT := 2.5          # hellfire
const DETONATE_RADIUS := 55.0
const TERROR_RADIUS := 60.0
const UNDERTOW_EVERY := 3
const ENTOMB_EVERY := 3
const PHASE_SECONDS := 2.0
const PULL_ROOT := 1.5
const POUNCE_COOLDOWN := 3.0
const CHILL_MULT := 0.5           # chilled units move and attack at half speed
const CURSE_MULT := 1.3           # cursed units take 30% more damage
const WEAKEN_MULT := 0.65         # weakened units deal 35% less damage
const BURN_SECONDS := 4.0         # burn deals its damage over this long
const CHAIN_RANGE := 110.0        # how far chain lightning jumps
const CHAIN_FALLOFF := 0.7        # each jump deals 70% of the previous one
const RAISE_UNIT := "skeleton"
enum Role { MELEE, RANGED, CASTER, HEALER, TANK }
## Who a unit attacks first (GameData "targets"): the nearest enemy, or the
## nearest of a preferred kind anywhere on the field (flyers hunting the
## enemy's ranged units, healers or back line).
enum Target { NEAREST, RANGED, HEALERS, BACKLINE }
const TARGET_MODES := {"ranged": Target.RANGED, "healers": Target.HEALERS, "backline": Target.BACKLINE}
const BACKLINE_SHARE := 0.35      # the rearmost 35% of the enemy formation counts as back line

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
var champ := PackedByteArray()     # 1: a champion (its auras reach further, 0.9.9)
var heal := PackedFloat32Array()
var regen := PackedFloat32Array()
var radius := PackedFloat32Array()
var lifesteal := PackedFloat32Array()
var thorns := PackedFloat32Array()
var tmode := PackedInt32Array()      # Target mode per unit
var ab_id := PackedInt32Array()      # Ab per unit
var ab_val := PackedFloat32Array()   # its strength (seconds, jumps, share...)
var ab_tpl := PackedInt32Array()     # raise dead: index into _raise_templates
# Status effects: the tick each one runs out (0 = none).
var stun_until := PackedInt32Array()
var chill_until := PackedInt32Array()
var burn_until := PackedInt32Array()
var burn_dps := PackedFloat32Array()
var curse_until := PackedInt32Array()
var weaken_until := PackedInt32Array()
var aegis_until := PackedInt32Array()
var ab_base := PackedFloat32Array()   # base damage/cooldown for abilities that change them
var _aura_units: Array = []           # units with dread / divine aegis
var _resurrectors: Array = []         # units with resurrection
var ab_used := PackedInt32Array()     # rebirth used / dead raised / charge spent
var ab_timer := PackedInt32Array()    # periodic abilities: the tick they next fire
# 0.9.4 statuses.
var poison_stacks := PackedInt32Array()
var poison_until := PackedInt32Array()
var poison_dps := PackedFloat32Array()   # per stack
var root_until := PackedInt32Array()
var fear_until := PackedInt32Array()
var fear_x := PackedFloat32Array()
var fear_y := PackedFloat32Array()
var shell_until := PackedInt32Array()
var inspire_until := PackedInt32Array()
var inspire_amt := PackedFloat32Array()
var haste_until := PackedInt32Array()
var haste_amt := PackedFloat32Array()
var corrode := PackedFloat32Array()
var phase_until := PackedInt32Array()
var entomb_until := PackedInt32Array()
var taunt_until := PackedInt32Array()
var taunt_src := PackedInt32Array()
var _periodic: Array = []             # units with timed abilities
var _champions: Array = []            # {"i", "fx": effects, "next": per-effect tick} (0.9.9)
var regen_until := PackedInt32Array() # champion's healing ground: extra regeneration...
var regen_pct := PackedFloat32Array() # ...as a share of max HP per second
var raised := PackedInt32Array()      # 1 for units raised from the dead mid-battle
# Battle stats (0.9.9): what each unit did, for the results screen. Only
# counted, never read by the battle itself, so they can't change a result.
var st_dmg := PackedFloat32Array()     # damage dealt (not counting overkill)
var st_taken := PackedFloat32Array()   # damage taken
var st_heal := PackedFloat32Array()    # health restored to itself or allies
var st_kills := PackedInt32Array()
var st_summoned := PackedByteArray()   # 1: joined mid-battle (summoned, raised, split)
var burn_src := PackedInt32Array()     # who set it burning / poisoned it /
var poison_src := PackedInt32Array()   # gave it the champion's regeneration,
var regen_src := PackedInt32Array()    # for the stats
var _raise_templates: Array = []      # resolved stats of the units raise dead creates

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
var pr_src := PackedInt32Array()
var pr_free: Array[int] = []

# --- map & obstacles --------------------------------------------------------
var map_id := BattleMaps.DEFAULT_MAP
# Private copies of shared tables, made in setup(). Battles run on worker
# threads (server, balance simulator), and reading the shared constant arrays
# from several threads at once crashes Godot 4.3 (their reference counts race).
var _dmg_mult := PackedFloat64Array()     # damage type * armor count + armor
var _armor_count := 0
var _proj_speed := PackedFloat64Array()
var _flying_mult := 1.0
var _half_neighbours: Array = []
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
	_armor_count = GameData.ARMOR_TYPES.size()
	_dmg_mult.clear()
	for row in GameData.DAMAGE_MULT:
		for v in row:
			_dmg_mult.append(float(v))
	_proj_speed = PackedFloat64Array(GameData.PROJECTILE_SPEED)
	_flying_mult = GameData.MELEE_VS_FLYING_MULT
	_half_neighbours = HALF_NEIGHBOURS.duplicate()
	map_id = map if BattleMaps.MAPS.has(map) else BattleMaps.DEFAULT_MAP
	var size := BattleMaps.map_size(map_id)
	map_w = size.x
	map_h = size.y
	gw = int(ceil(map_w / CELL))
	gh = int(ceil(map_h / CELL))
	cell_head.resize(gw * gh)
	_build_obstacles()
	_spawn_army(_with_champions(squads_a), 0)
	_spawn_army(_with_champions(squads_b), 1)
	cell_next.resize(n)
	_resolve_obstacles()
	_rebuild_team_lists()


## Champion squads (0.9.9) rebuilt from their battle data, so every machine
## registers the same champion under the same id.
func _with_champions(squads: Array) -> Array:
	var out: Array = []
	for sq in squads:
		if typeof(sq) == TYPE_DICTIONARY and sq.has("champion"):
			var bd := Champion.sanitize_battle(sq["champion"])
			if not bd.is_empty():
				out.append(Champion.to_squad(bd))
		else:
			out.append(sq)
	return out


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
			var lvl := Army.squad_stat_level(sq)
			var stats := Army.unit_stats(sq["unit"], lvl, Army.squad_mods(sq))
			stats["level"] = lvl
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
	return float(GameData.unit(uid)["radius"]) * 2.0 + 3.0


func _add_unit(uid: String, s: Dictionary, t: int, x: float, y: float) -> void:
	_add_resolved(_resolve(uid, s), t, x, y)


## Unit stats turned into plain numbers, so units can also be added during
## the battle (raise dead) without touching shared game data from a worker
## thread. Called on the thread that runs setup().
func _resolve(uid: String, s: Dictionary) -> Dictionary:
	var ab: Dictionary = s.get("ability", {}) if typeof(s.get("ability")) == TYPE_DICTIONARY else {}
	var r := {
		"kind": _kind_index(uid), "role": GameData.ROLES.find(s["role"]), "dtype": GameData.DAMAGE_TYPES.find(s["damage"]),
		"armor": GameData.ARMOR_TYPES.find(s["armor"]), "flying": 1 if s["flying"] else 0, "proj": GameData.PROJECTILES.find(s["projectile"]),
		"hp": float(s["hp"]), "dmg": float(s["dmg"]), "range": float(s["range"]), "speed": float(s["speed"]), "cooldown": float(s["cooldown"]),
		"aoe": float(s["aoe"]), "heal": float(s["heal"]), "regen": float(s["regen"]), "radius": float(s["radius"]),
		"champ": 1 if bool(s.get("champion", false)) else 0,
		"lifesteal": float(s.get("lifesteal", 0.0)), "thorns": float(s.get("thorns", 0.0)),
		"tmode": int(TARGET_MODES.get(str(s.get("targets", "")), Target.NEAREST)),
		"ab": int(AB_IDS.get(str(ab.get("id", "")), Ab.NONE)), "ab_val": float(ab.get("value", 0.0)), "tpl": -1,
	}
	if r["ab"] == Ab.RAISE_DEAD:
		# The raised dead fight at the necromancer's level.
		r["tpl"] = _raise_templates.size()
		_raise_templates.append(_resolve(RAISE_UNIT, Army.unit_stats(RAISE_UNIT, int(s.get("level", 1)))))
	elif r["ab"] == Ab.SUMMON:
		# The brood hatches at the matriarch's level.
		r["tpl"] = _raise_templates.size()
		_raise_templates.append(_resolve(SUMMON_UNIT, Army.unit_stats(SUMMON_UNIT, int(s.get("level", 1)))))
	if s.has("effects"):
		# A champion (0.9.9): its ability effects, with templates for what it summons.
		var fxs: Array = []
		for fx in s["effects"]:
			var f: Dictionary = fx.duplicate()
			if f["type"] == "summon" and GameData.UNITS.has(str(f["unit"])):
				f["tpl"] = _raise_templates.size()
				_raise_templates.append(_resolve(str(f["unit"]), Army.unit_stats(str(f["unit"]), int(s.get("level", 1)))))
			fxs.append(f)
		r["champ_fx"] = fxs
	if r["ab"] == Ab.SPLIT:
		# The halves: weaker copies that don't split again.
		var half := s.duplicate()
		half["hp"] = float(s["hp"]) * r["ab_val"]
		half["dmg"] = float(s["dmg"]) * r["ab_val"]
		half["radius"] = float(s["radius"]) * 0.8
		half.erase("ability")
		r["tpl"] = _raise_templates.size()
		_raise_templates.append(_resolve(uid, half))
	return r


func _add_resolved(r: Dictionary, t: int, x: float, y: float) -> void:
	var i := n
	n += 1
	kind.append(r["kind"])
	team.append(t)
	alive.append(1)
	role.append(r["role"])
	dtype.append(r["dtype"])
	armor.append(r["armor"])
	flying.append(r["flying"])
	proj.append(r["proj"])
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
	hp.append(r["hp"])
	max_hp.append(r["hp"])
	dmg.append(r["dmg"])
	reach.append(r["range"])
	speed.append(r["speed"])
	cooldown.append(r["cooldown"])
	cd_t.append(rng.randf_range(0.0, float(r["cooldown"])))
	aoe.append(r["aoe"])
	champ.append(int(r.get("champ", 0)))
	heal.append(r["heal"])
	regen.append(r["regen"])
	radius.append(r["radius"])
	lifesteal.append(r["lifesteal"])
	thorns.append(r["thorns"])
	tmode.append(r["tmode"])
	ab_id.append(r["ab"])
	ab_val.append(r["ab_val"])
	ab_tpl.append(r["tpl"])
	# (Packed arrays are values: append to each member directly.)
	stun_until.append(0)
	chill_until.append(0)
	burn_until.append(0)
	curse_until.append(0)
	weaken_until.append(0)
	aegis_until.append(0)
	ab_base.append(r["cooldown"] if r["ab"] == Ab.HEADS else r["dmg"])
	if r["ab"] == Ab.DREAD or r["ab"] == Ab.AEGIS:
		_aura_units.append(i)
	if r["ab"] == Ab.RESURRECT:
		_resurrectors.append(i)
	ab_used.append(0)
	raised.append(0)
	burn_dps.append(0.0)
	var first := 0
	match int(r["ab"]):
		Ab.SUMMON:
			first = int(SUMMON_EVERY / DT)
		Ab.THUNDERSTRIKE, Ab.TIDAL_WAVE, Ab.AVALANCHE, Ab.PHASE:
			first = int(float(r["ab_val"]) / DT)
		Ab.FORTIFY:
			first = int(1.0 / DT)
	ab_timer.append(first)
	if first > 0:
		_periodic.append(i)
	if r["ab"] in [Ab.SONG, Ab.INSPIRE, Ab.IMMOLATE, Ab.FROST_AURA]:
		_aura_units.append(i)
	regen_until.append(0)
	regen_pct.append(0.0)
	st_dmg.append(0.0)
	st_taken.append(0.0)
	st_heal.append(0.0)
	st_kills.append(0)
	st_summoned.append(1 if tick > 0 else 0)
	burn_src.append(-1)
	poison_src.append(-1)
	regen_src.append(-1)
	if r.has("champ_fx"):
		var nexts: Array = []
		for fx in r["champ_fx"]:
			nexts.append(int(CHAMPION_FIRST_SUMMON / DT) if fx["type"] == "summon" else int(float(fx.get("every", 0.0)) / DT))
		_champions.append({"i": i, "fx": r["champ_fx"], "next": nexts})
	poison_stacks.append(0)
	poison_until.append(0)
	poison_dps.append(0.0)
	root_until.append(0)
	fear_until.append(0)
	fear_x.append(0.0)
	fear_y.append(0.0)
	shell_until.append(0)
	inspire_until.append(0)
	inspire_amt.append(0.0)
	haste_until.append(0)
	haste_amt.append(0.0)
	corrode.append(0.0)
	phase_until.append(0)
	entomb_until.append(0)
	taunt_until.append(0)
	taunt_src.append(-1)
	alive_count[t] += 1
	start_count[t] += 1
	start_hp[t] += float(r["hp"])
	if cell_next.size() < n:
		cell_next.resize(n)
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
	if not _aura_units.is_empty() and tick % AURA_TICKS == 1:
		_apply_auras()
	if not _champions.is_empty():
		_champion_effects()
	for i in _resurrectors:
		if alive[i] == 1 and tick >= ab_used[i]:
			_try_resurrect(i)
	for i in _periodic:
		if alive[i] == 1 and tick >= ab_timer[i] and stun_until[i] <= tick:
			_periodic_ability(i)
	for i in n:
		prev_x[i] = px[i]
		prev_y[i] = py[i]
		if alive[i] == 0:
			continue
		if regen[i] > 0.0 and hp[i] < max_hp[i]:
			_healed(i, i, regen[i] * DT)
		if regen_until[i] > tick and hp[i] < max_hp[i]:
			_healed(regen_src[i], i, max_hp[i] * regen_pct[i] * DT)
		if burn_until[i] > tick:
			_dot(i, burn_dps[i] * DT, burn_src[i])
			hp[i] -= burn_dps[i] * DT
			if hp[i] <= 0.0:
				_kill(i, -1, burn_src[i])
				continue
		if poison_until[i] > tick:
			_dot(i, poison_dps[i] * float(poison_stacks[i]) * DT, poison_src[i])
			hp[i] -= poison_dps[i] * float(poison_stacks[i]) * DT
			if hp[i] <= 0.0:
				_kill(i, -1, poison_src[i])
				continue
		elif poison_stacks[i] > 0:
			poison_stacks[i] = 0
		if stun_until[i] > tick:
			continue   # stunned: no moving, no attacking, cooldown paused
		if fear_until[i] > tick:
			_flee(i)
			continue   # terrified: running away, not fighting
		cd_t[i] -= DT * _attack_speed(i)
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
	if taunt_until[i] > tick and taunt_src[i] >= 0 and alive[taunt_src[i]] == 1:
		# Taunted: it has to fight the taunter.
		target[i] = taunt_src[i]
		target_ally[i] = 0
		_approach_and_act(i, taunt_src[i], false)
		return
	if t < 0 or alive[t] == 0 or target_ally[i] == 1 or (tick + i) % RETARGET_TICKS == 0:
		t = _find_enemy(i)
		if t != target[i] and ab_id[i] == Ab.CHARGE:
			ab_used[i] = 0   # a new target: charge again
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
		if not healing and _leap(i, t, dx / d, dy / d, d, r):
			return
		if root_until[i] > tick:
			return   # rooted: can't move (but can fight whatever is in reach)
		var spd := speed[i] * (CHILL_MULT if chill_until[i] > tick else 1.0) * (1.0 + haste_amt[i] if haste_until[i] > tick else 1.0)
		_move(i, dx / d, dy / d, minf(spd * DT, d - r + 0.5))
		return
	if cd_t[i] > 0.0:
		return
	cd_t[i] = cooldown[i]
	attack_tick[i] = tick
	if healing:
		_healed(i, t, heal[i])
		events.append([Ev.HEAL, px[t], py[t], t])
		if ab_id[i] == Ab.PURIFY and _cleanse(t):
			events.append([Ev.ABILITY, px[t], py[t], Ab.PURIFY])
		return
	if proj[i] == 0:
		events.append([Ev.MELEE_HIT, px[t], py[t], i])
		var amount := dmg[i]
		if ab_id[i] == Ab.DETONATE:
			_detonate(i, t)
			return
		if ab_id[i] == Ab.BLINK and ab_used[i] == 1:
			amount *= ab_val[i]   # the ambush blow
			ab_used[i] = 2
		if ab_id[i] == Ab.RISING_STORM:
			# Each blow builds the storm: more damage, up to a cap.
			amount *= 1.0 + ab_val[i] * float(ab_used[i])
			ab_used[i] = mini(ab_used[i] + 1, STORM_MAX_STACKS)
		if ab_id[i] == Ab.CHARGE and ab_used[i] == 0:
			# Charge: the first blow against each new target hits much harder.
			amount *= ab_val[i]
			ab_used[i] = 1
			events.append([Ev.CHARGE, px[t], py[t], i])
		_deal_damage(i, team[i], dtype[i], amount, t, px[t], py[t], aoe[i], true)
		if ab_id[i] == Ab.DOUBLE_STRIKE:
			_double_strike(i, t)
		elif ab_id[i] == Ab.QUAKE:
			ab_used[i] += 1
			if ab_used[i] % QUAKE_EVERY == 0:
				_quake(i, px[t], py[t])
		elif ab_id[i] == Ab.TAUNT:
			_taunt(i)
	else:
		_spawn_projectile(i, t)
		events.append([Ev.SHOT, px[i], py[i], proj[i]])
		if ab_id[i] == Ab.VOLLEY:
			# Extra throws at the enemies next to the target.
			var hit := {t: true}
			for _k in int(ab_val[i]):
				var other := _nearest_enemy_near(px[t], py[t], 120.0, team[i], hit)
				if other < 0:
					break
				hit[other] = true
				_spawn_projectile(i, other)


## Attack speed multiplier: chill slows it, siren song and blood frenzy speed it up.
func _attack_speed(i: int) -> float:
	var s := CHILL_MULT if chill_until[i] > tick else 1.0
	if haste_until[i] > tick:
		s *= 1.0 + haste_amt[i]
	if ab_id[i] == Ab.FRENZY:
		s *= 1.0 + ab_val[i] * float(ab_used[i])
	return s


## Pounce and shadowstep: close the gap to the target in one leap.
func _leap(i: int, t: int, nx: float, ny: float, d: float, r: float) -> bool:
	var ok := false
	if ab_id[i] == Ab.POUNCE and tick >= ab_timer[i] and d <= ab_val[i]:
		ab_timer[i] = tick + int(POUNCE_COOLDOWN / DT)
		ok = true
	elif ab_id[i] == Ab.BLINK and ab_used[i] == 0:
		ab_used[i] = 1
		ok = true
	if not ok or root_until[i] > tick:
		return false
	px[i] = clampf(px[t] - nx * (r - 1.0), 8.0, map_w - 8.0)
	py[i] = clampf(py[t] - ny * (r - 1.0), 8.0, map_h - 8.0)
	events.append([Ev.ABILITY, px[i], py[i], ab_id[i]])
	return true


## Terrified units run from what scared them.
func _flee(i: int) -> void:
	var dx := px[i] - fear_x[i]
	var dy := py[i] - fear_y[i]
	var d := maxf(0.001, sqrt(dx * dx + dy * dy))
	_move(i, dx / d, dy / d, speed[i] * 0.8 * DT)


## Purify: wash every harmful effect off an ally. True if there was any.
func _cleanse(t: int) -> bool:
	var any := burn_until[t] > tick or poison_until[t] > tick or chill_until[t] > tick or curse_until[t] > tick \
		or weaken_until[t] > tick or root_until[t] > tick or fear_until[t] > tick
	burn_until[t] = 0
	poison_until[t] = 0
	poison_stacks[t] = 0
	chill_until[t] = 0
	curse_until[t] = 0
	weaken_until[t] = 0
	root_until[t] = 0
	fear_until[t] = 0
	return any


## Imp: blows itself up on its first blow.
func _detonate(i: int, t: int) -> void:
	events.append([Ev.BLAST, px[t], py[t], DETONATE_RADIUS])
	for k in _enemies_near(px[t], py[t], DETONATE_RADIUS, team[i], false, 5):
		_damage_unit(k, dmg[i] * ab_val[i], dtype[i], false, -1, i)
	if alive[i] == 1:
		_kill(i, -1)


## Guardian Serpent: the enemies around it have to attack it for a while.
func _taunt(i: int) -> void:
	for k in _enemies_near(px[i], py[i], ab_val[i], team[i], false, 8):
		if role[k] != Role.HEALER:
			taunt_until[k] = tick + int(2.0 / DT)
			taunt_src[k] = i


## Timed abilities: brood, hellfire, tidal wave, avalanche, phase shift, fortify.
func _periodic_ability(i: int) -> void:
	match ab_id[i]:
		Ab.FORTIFY:
			ab_used[i] = mini(ab_used[i] + 1, int(FORTIFY_MAX / maxf(0.001, ab_val[i])))
			ab_timer[i] = tick + int(1.0 / DT)
		Ab.SUMMON:
			ab_timer[i] = tick + int(SUMMON_EVERY / DT)
			if ab_used[i] < int(ab_val[i]) and ab_tpl[i] >= 0:
				ab_used[i] += 1
				var k := n
				var side := 18.0 if team[i] == 0 else -18.0
				_add_resolved(_raise_templates[ab_tpl[i]], team[i], clampf(px[i] + side, 8.0, map_w - 8.0), py[i] + rng.randf_range(-12.0, 12.0))
				raised[k] = 1
				cd_t[k] = cooldown[k]
				events.append([Ev.RAISE, px[k], py[k], k])
				events.append([Ev.ABILITY, px[k], py[k], Ab.SUMMON])
		Ab.THUNDERSTRIKE:
			ab_timer[i] = tick + int(ab_val[i] / DT)
			var foes: PackedInt32Array = team_lists[1 - team[i]]
			for _try in 6:
				if foes.is_empty():
					break
				var k := foes[rng.randi_range(0, foes.size() - 1)]
				if alive[k] == 1:
					events.append([Ev.STRIKE, px[k], py[k], i])
					_damage_unit(k, dmg[i] * STRIKE_MULT, dtype[i], false, i)
					break
		Ab.TIDAL_WAVE, Ab.AVALANCHE:
			var t := target[i]
			if t < 0 or alive[t] == 0 or target_ally[i] == 1:
				return   # waits for a target
			ab_timer[i] = tick + int(ab_val[i] / DT)
			var x := px[t]
			var y := py[t]
			events.append([Ev.WAVE, x, y, ab_id[i]])
			for k in _enemies_near(x, y, WAVE_RADIUS, team[i], false, 8):
				_damage_unit(k, dmg[i] * WAVE_MULT, dtype[i], false, i)
				if alive[k] == 0 or ab_id[k] == Ab.UNSTOPPABLE:
					continue
				if ab_id[i] == Ab.AVALANCHE:
					chill_until[k] = maxi(chill_until[k], tick + int(2.5 / DT))
				else:
					_push(k, px[i], py[i], 40.0)
		Ab.PHASE:
			ab_timer[i] = tick + int(ab_val[i] / DT)
			phase_until[i] = tick + int(PHASE_SECONDS / DT)
			events.append([Ev.ABILITY, px[i], py[i], Ab.PHASE])


## Push unit k directly away from (x, y).
func _push(k: int, x: float, y: float, dist: float) -> void:
	var dx := px[k] - x
	var dy := py[k] - y
	var d := maxf(0.001, sqrt(dx * dx + dy * dy))
	px[k] = clampf(px[k] + dx / d * dist, 8.0, map_w - 8.0)
	py[k] = clampf(py[k] + dy / d * dist, 8.0, map_h - 8.0)


## Hell Hound: other hounds of its kind close by.
func _pack_count(i: int) -> int:
	var c := 0
	for k in _enemies_near(px[i], py[i], PACK_RADIUS, team[i], true, PACK_MAX + 1):
		if k != i and kind[k] == kind[i]:
			c += 1
	return mini(c, PACK_MAX)


func _find_enemy(i: int) -> int:
	if tmode[i] != Target.NEAREST:
		var p := _find_priority_enemy(i, tmode[i])
		if p >= 0:
			return p
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


## The nearest enemy of the preferred kind anywhere on the field, or -1 if
## there is none left (then the unit attacks whatever is nearest).
func _find_priority_enemy(i: int, mode: int) -> int:
	var list: PackedInt32Array = team_lists[1 - team[i]]
	var x := px[i]
	var y := py[i]
	# Back line: how deep each enemy stands in its own formation. The right-hand
	# army (team 1) has its rear at large x, the left-hand one at small x.
	var cutoff := 0.0
	var rear_sign := 1.0 if team[i] == 0 else -1.0
	if mode == Target.BACKLINE:
		var lo := INF
		var hi := -INF
		for j in list:
			if alive[j] == 1:
				var depth := px[j] * rear_sign
				lo = minf(lo, depth)
				hi = maxf(hi, depth)
		if lo == INF:
			return -1
		cutoff = hi - (hi - lo) * BACKLINE_SHARE
	for pass_i in 2:
		var best := -1
		var best_d2 := INF
		for j in list:
			if alive[j] == 0:
				continue
			var ok := false
			match mode:
				Target.RANGED:
					ok = role[j] == Role.RANGED or role[j] == Role.CASTER
				Target.HEALERS:
					# No healers left: go for ranged units and casters instead.
					ok = role[j] == Role.HEALER if pass_i == 0 else (role[j] == Role.RANGED or role[j] == Role.CASTER)
				Target.BACKLINE:
					ok = px[j] * rear_sign >= cutoff
			if not ok:
				continue
			var dx := px[j] - x
			var dy := py[j] - y
			var d2 := dx * dx + dy * dy
			if d2 < best_d2:
				best_d2 = d2
				best = j
		if best >= 0 or mode != Target.HEALERS:
			return best
	return -1


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

## src: attacking unit index (or -1), used for lifesteal and thorns.
func _deal_damage(src: int, src_team: int, dt_idx: int, amount: float, primary: int, x: float, y: float, radius_aoe: float, melee: bool) -> void:
	if primary >= 0 and alive[primary] == 1:
		var dealt := _damage_unit(primary, amount, dt_idx, melee, src)
		if src >= 0 and ab_id[src] != Ab.NONE:
			_on_hit(src, src_team, primary, dealt, amount, dt_idx)
	if radius_aoe <= 0.0:
		return
	events.append([Ev.BLAST, x, y, radius_aoe])
	var splash := amount * (AOE_SPLASH_MULT if melee else RANGED_SPLASH_MULT)
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
						_damage_unit(j, splash, dt_idx, melee, src)
						hits += 1
						if hits >= MAX_SPLASH_TARGETS:
							return
				j = cell_next[j]


## Returns the damage dealt.
## credit: who the stats count it for when there's no src (explosions, auras).
func _damage_unit(j: int, amount: float, dt_idx: int, melee: bool, src: int = -1, credit: int = -1) -> float:
	if phase_until[j] > tick:
		return 0.0   # phased out of this world
	if src >= 0:
		if ab_id[j] == Ab.EVASION and rng.randf() < ab_val[j]:
			events.append([Ev.ABILITY, px[j], py[j], Ab.EVASION])
			return 0.0
		if melee and ab_id[j] == Ab.BLOCK and rng.randf() < ab_val[j]:
			events.append([Ev.ABILITY, px[j], py[j], Ab.BLOCK])
			return 0.0
	var m: float = _dmg_mult[dt_idx * _armor_count + armor[j]]
	match ab_id[j]:
		Ab.WARD:
			if dt_idx >= 2:   # magic, fire
				m *= 1.0 - ab_val[j]
		Ab.FORTIFY:
			m *= 1.0 - minf(FORTIFY_MAX, ab_val[j] * float(ab_used[j]))
	if shell_until[j] > tick:
		m *= SHELL_MULT
	if entomb_until[j] > tick:
		m *= ENTOMB_MULT
	m *= 1.0 + corrode[j]
	if src >= 0:
		if inspire_until[src] > tick:
			m *= 1.0 + inspire_amt[src]
		match ab_id[src]:
			Ab.PACK:
				m *= 1.0 + ab_val[src] * float(_pack_count(src))
			Ab.BERSERK:
				m *= 1.0 + ab_val[src] * clampf(1.0 - hp[src] / max_hp[src], 0.0, 1.0)
			Ab.EXECUTE:
				if hp[j] < max_hp[j] * EXECUTE_BELOW:
					m *= 1.0 + ab_val[src]
	if melee and flying[j] == 1:
		m *= _flying_mult
	if src >= 0 and weaken_until[src] > tick:
		m *= WEAKEN_MULT
	if curse_until[j] > tick:
		m *= CURSE_MULT
	if aegis_until[j] > tick:
		m *= AEGIS_MULT
	if src >= 0 and ab_id[src] == Ab.PREDATOR and (role[j] == Role.RANGED or role[j] == Role.CASTER or role[j] == Role.HEALER):
		m *= 1.0 + ab_val[src]
	if not melee and ab_id[j] == Ab.UNSTOPPABLE:
		m *= 1.0 - ab_val[j]
	var dealt := amount * m * rng.randf_range(0.9, 1.1)
	if src >= 0:
		credit = src
	_dot(j, dealt, credit)
	hp[j] -= dealt
	hit_tick[j] = tick
	if ab_id[j] == Ab.SHELL and ab_used[j] == 0 and hp[j] > 0.0 and hp[j] < max_hp[j] * 0.5:
		ab_used[j] = 1
		shell_until[j] = tick + int(ab_val[j] / DT)
		events.append([Ev.ABILITY, px[j], py[j], Ab.SHELL])
	if src >= 0 and alive[src] == 1:
		if not melee and ab_id[j] == Ab.REFLECT:
			_dot(src, dealt * ab_val[j], j)
			hp[src] -= dealt * ab_val[j]
			hit_tick[src] = tick
			events.append([Ev.ABILITY, px[j], py[j], Ab.REFLECT])
			if hp[src] <= 0.0:
				_kill(src, j)
		elif melee and ab_id[j] == Ab.FROST_ARMOR and ab_id[src] != Ab.UNSTOPPABLE:
			chill_until[src] = maxi(chill_until[src], tick + int(ab_val[j] / DT))
	if ab_id[j] == Ab.HEADS and hp[j] > 0.0:
		# Every quarter of its health lost grows another head: faster attacks.
		var heads := clampi(int((1.0 - hp[j] / max_hp[j]) * 4.0), 0, 3)
		if heads > ab_used[j]:
			ab_used[j] = heads
			cooldown[j] = ab_base[j] / (1.0 + ab_val[j] * float(heads))
	if src >= 0 and alive[src] == 1:
		if lifesteal[src] > 0.0:
			_healed(src, src, dealt * lifesteal[src])
		if melee and thorns[j] > 0.0:
			_dot(src, dealt * thorns[j], j)
			hp[src] -= dealt * thorns[j]
			hit_tick[src] = tick
			if hp[src] <= 0.0:
				_kill(src, j)
	if hp[j] <= 0.0 and alive[j] == 1:
		_kill(j, src, credit)
	return dealt


## Effects of an ability on the unit a src's attack hit (not on splash).
## amount: the attack's damage before armour, for chain lightning.
func _on_hit(src: int, src_team: int, j: int, dealt: float, amount: float, dt_idx: int) -> void:
	var secs_ticks := int(ab_val[src] / DT)
	match ab_id[src]:
		Ab.STUN:
			if alive[j] == 1 and ab_id[j] != Ab.UNSTOPPABLE:
				stun_until[j] = maxi(stun_until[j], tick + secs_ticks)
				events.append([Ev.STUN, px[j], py[j], j])
		Ab.CHILL:
			if alive[j] == 1 and ab_id[j] != Ab.UNSTOPPABLE:
				chill_until[j] = maxi(chill_until[j], tick + secs_ticks)
				events.append([Ev.ABILITY, px[j], py[j], Ab.CHILL])
		Ab.CURSE:
			curse_until[j] = maxi(curse_until[j], tick + secs_ticks)
			events.append([Ev.ABILITY, px[j], py[j], Ab.CURSE])
		Ab.WEAKEN:
			weaken_until[j] = maxi(weaken_until[j], tick + secs_ticks)
			events.append([Ev.ABILITY, px[j], py[j], Ab.WEAKEN])
		Ab.BURN:
			if alive[j] == 1:
				events.append([Ev.ABILITY, px[j], py[j], Ab.BURN])
				var dps := dealt * ab_val[src] / BURN_SECONDS
				burn_dps[j] = maxf(burn_dps[j] if burn_until[j] > tick else 0.0, dps)
				burn_until[j] = tick + int(BURN_SECONDS / DT)
				burn_src[j] = src
		Ab.VENOM:
			if alive[j] == 1:
				var active := poison_until[j] > tick
				poison_stacks[j] = mini((poison_stacks[j] if active else 0) + 1, POISON_MAX_STACKS)
				poison_dps[j] = maxf(poison_dps[j] if active else 0.0, dmg[src] * ab_val[src])
				poison_src[j] = src
				poison_until[j] = tick + int(POISON_SECONDS / DT)
				events.append([Ev.ABILITY, px[j], py[j], Ab.VENOM])
		Ab.ENSNARE:
			if alive[j] == 1 and ab_id[j] != Ab.UNSTOPPABLE:
				root_until[j] = maxi(root_until[j], tick + secs_ticks)
				events.append([Ev.ABILITY, px[j], py[j], Ab.ENSNARE])
		Ab.CORRODE:
			corrode[j] = minf(CORRODE_MAX, corrode[j] + ab_val[src])
			events.append([Ev.ABILITY, px[j], py[j], Ab.CORRODE])
		Ab.PULL:
			if alive[j] == 1 and ab_id[j] != Ab.UNSTOPPABLE:
				_push(j, px[src], py[src], -minf(ab_val[src], maxf(0.0, sqrt(pow(px[j] - px[src], 2) + pow(py[j] - py[src], 2)) - radius[src] - radius[j] - 2.0)))
				root_until[j] = maxi(root_until[j], tick + int(PULL_ROOT / DT))
				events.append([Ev.ABILITY, px[j], py[j], Ab.PULL])
		Ab.TERROR:
			events.append([Ev.ABILITY, px[j], py[j], Ab.TERROR])
			for k in _enemies_near(px[j], py[j], TERROR_RADIUS, src_team, false, 6):
				if ab_id[k] != Ab.UNSTOPPABLE:
					fear_until[k] = maxi(fear_until[k], tick + secs_ticks)
					fear_x[k] = px[src]
					fear_y[k] = py[src]
		Ab.ENTOMB:
			ab_used[src] += 1
			if ab_used[src] % ENTOMB_EVERY == 0 and alive[j] == 1:
				stun_until[j] = maxi(stun_until[j], tick + secs_ticks)
				entomb_until[j] = maxi(entomb_until[j], tick + secs_ticks)
				events.append([Ev.ABILITY, px[j], py[j], Ab.ENTOMB])
				for k in _enemies_near(px[j], py[j], 60.0, src_team, false, 8):
					if ab_id[k] != Ab.UNSTOPPABLE:
						chill_until[k] = maxi(chill_until[k], tick + int(2.0 / DT))
		Ab.UNDERTOW:
			ab_used[src] += 1
			if ab_used[src] % UNDERTOW_EVERY == 0:
				events.append([Ev.ABILITY, px[j], py[j], Ab.UNDERTOW])
				for k in _enemies_near(px[j], py[j], 70.0, src_team, false, 8):
					if ab_id[k] != Ab.UNSTOPPABLE:
						_push(k, px[src], py[src], ab_val[src])
		Ab.KNOCKBACK:
			if alive[j] == 1 and ab_id[j] != Ab.UNSTOPPABLE:
				var dx := px[j] - px[src]
				var dy := py[j] - py[src]
				var d := maxf(0.001, sqrt(dx * dx + dy * dy))
				px[j] = clampf(px[j] + dx / d * ab_val[src], 8.0, map_w - 8.0)
				py[j] = clampf(py[j] + dy / d * ab_val[src], 8.0, map_h - 8.0)
				stun_until[j] = maxi(stun_until[j], tick + 4)   # a moment to get back up
				events.append([Ev.ABILITY, px[j], py[j], Ab.KNOCKBACK])
		Ab.CHAIN:
			var hit := {j: true}
			var last := j
			var a := amount
			for _k in int(ab_val[src]):
				var nxt := _nearest_enemy_near(px[last], py[last], CHAIN_RANGE, src_team, hit)
				if nxt < 0:
					break
				a *= CHAIN_FALLOFF
				events.append([Ev.CHAIN, px[last], py[last], px[nxt], py[nxt]])
				hit[nxt] = true
				_damage_unit(nxt, a, dt_idx, false, src)
				last = nxt


## Ettin-style second blow: another enemy within reach takes a full hit.
func _double_strike(i: int, primary: int) -> void:
	var hit := {primary: true}
	for _k in int(ab_val[i]):
		var other := _nearest_enemy_near(px[i], py[i], reach[i] + radius[i] + 14.0, team[i], hit)
		if other < 0:
			return
		hit[other] = true
		events.append([Ev.MELEE_HIT, px[other], py[other], i])
		_damage_unit(other, dmg[i], dtype[i], true, i)


## Living units within r of (x, y): enemies of my_team (or allies when
## allies is true), nearest first is not guaranteed; at most MAX_AREA_TARGETS.
func _enemies_near(x: float, y: float, r: float, my_team: int, allies: bool = false, limit: int = MAX_AREA_TARGETS) -> PackedInt32Array:
	var out := PackedInt32Array()
	var rings := ceili(r / CELL)
	var cx := clampi(int(x / CELL), 0, gw - 1)
	var cy := clampi(int(y / CELL), 0, gh - 1)
	for gy in range(maxi(0, cy - rings), mini(gh, cy + rings + 1)):
		for gx in range(maxi(0, cx - rings), mini(gw, cx + rings + 1)):
			var j := cell_head[gy * gw + gx]
			while j != -1:
				if alive[j] == 1 and ((team[j] == my_team) == allies):
					var dx := px[j] - x
					var dy := py[j] - y
					var rr := r + radius[j]
					if dx * dx + dy * dy <= rr * rr:
						out.append(j)
						if out.size() >= limit:
							return out
				j = cell_next[j]
	return out


## Hill Giant: the ground shakes and everything around the target is stunned.
func _quake(i: int, x: float, y: float) -> void:
	events.append([Ev.QUAKE, x, y, QUAKE_RADIUS])
	for k in _enemies_near(x, y, QUAKE_RADIUS, team[i]):
		if ab_id[k] != Ab.UNSTOPPABLE:
			stun_until[k] = maxi(stun_until[k], tick + int(ab_val[i] / DT))


## Dread (enemies nearby deal less damage) and divine aegis (allies nearby
## take less), refreshed every AURA_TICKS.
func _apply_auras() -> void:
	for i in _aura_units:
		if alive[i] == 0:
			continue
		var until := tick + AURA_TICKS + 1
		# Champions lead from further away and reach many more (0.9.9).
		var reach_r := AURA_RADIUS * (CHAMPION_AURA_MULT if champ[i] == 1 else 1.0)
		var cap := CHAMPION_AURA_CAP if champ[i] == 1 else 40
		match ab_id[i]:
			Ab.DREAD:
				for k in _enemies_near(px[i], py[i], reach_r, team[i], false, cap):
					weaken_until[k] = maxi(weaken_until[k], until)
			Ab.AEGIS:
				for k in _enemies_near(px[i], py[i], reach_r, team[i], true, cap):
					aegis_until[k] = maxi(aegis_until[k], until)
			Ab.SONG:
				for k in _enemies_near(px[i], py[i], reach_r, team[i], true, cap):
					haste_until[k] = maxi(haste_until[k], until)
					haste_amt[k] = maxf(haste_amt[k], ab_val[i])
			Ab.INSPIRE:
				for k in _enemies_near(px[i], py[i], reach_r, team[i], true, cap):
					inspire_until[k] = maxi(inspire_until[k], until)
					inspire_amt[k] = maxf(inspire_amt[k], ab_val[i])
			Ab.IMMOLATE:
				for k in _enemies_near(px[i], py[i], 80.0, team[i], false, 8):
					_damage_unit(k, dmg[i] * ab_val[i] * float(AURA_TICKS) * DT, 3, false, -1, i)
			Ab.FROST_AURA:
				for k in _enemies_near(px[i], py[i], 110.0 * (CHAMPION_AURA_MULT if champ[i] == 1 else 1.0), team[i], false, CHAMPION_AURA_CAP if champ[i] == 1 else 30):
					if ab_id[k] != Ab.UNSTOPPABLE:
						chill_until[k] = maxi(chill_until[k], until)
		if tick % (AURA_TICKS * 4) == 1:
			events.append([Ev.AURA, px[i], py[i], i])


## Champion abilities (0.9.9): auras every AURA_TICKS, summons and meteors on
## their timers. See Champion.ABILITIES.
func _champion_effects() -> void:
	for ch in _champions:
		var i: int = ch["i"]
		if alive[i] == 0:
			continue
		var fxs: Array = ch["fx"]
		var nexts: Array = ch["next"]
		var aura_tick := tick % AURA_TICKS == 1
		for k in fxs.size():
			var fx: Dictionary = fxs[k]
			match str(fx["type"]):
				"summon":
					if tick >= int(nexts[k]) and fx.has("tpl"):
						nexts[k] = tick + int(float(fx["every"]) / DT)
						for c in int(fx["count"]):
							var u := n
							var side := 20.0 if team[i] == 0 else -20.0
							_add_resolved(_raise_templates[int(fx["tpl"])], team[i], clampf(px[i] + side + rng.randf_range(-8.0, 8.0), 8.0, map_w - 8.0),
								clampf(py[i] + rng.randf_range(-22.0, 22.0), 8.0, map_h - 8.0))
							raised[u] = 1
							cd_t[u] = cooldown[u]
							events.append([Ev.RAISE, px[u], py[u], u])
						events.append([Ev.ABILITY, px[i], py[i], Ab.SUMMON])
				"meteor":
					if tick >= int(nexts[k]):
						nexts[k] = tick + int(float(fx["every"]) / DT)
						var foes: PackedInt32Array = team_lists[1 - team[i]]
						for _try in 6:
							if foes.is_empty():
								break
							var e := foes[rng.randi_range(0, foes.size() - 1)]
							if alive[e] == 1:
								events.append([Ev.STRIKE, px[e], py[e], i])
								_damage_unit(e, dmg[i] * float(fx.get("mult", 3.0)), dtype[i], false, i)
								break
				_:
					if aura_tick:
						_champion_aura(i, fx)
		if aura_tick and tick % (AURA_TICKS * 4) == 1:
			events.append([Ev.AURA, px[i], py[i], i])


func _champion_aura(i: int, fx: Dictionary) -> void:
	var kind_s := str(fx["type"])
	var allies := kind_s in ["damage", "haste", "guard", "regen"]
	var r := float(fx.get("radius", 0.0))
	var until := tick + AURA_TICKS + 1
	var targets: PackedInt32Array
	if r <= 0.0:
		targets = team_lists[team[i] if allies else 1 - team[i]]
	else:
		targets = _enemies_near(px[i], py[i], r, team[i], allies, CHAMPION_FX_CAP)
	var only := str(fx.get("only", ""))
	var only_armor := GameData.ARMOR_TYPES.find(only)
	var only_role := GameData.ROLES.find(only)
	var amount := float(fx.get("amount", 0.0))
	for k in targets:
		if alive[k] == 0:
			continue
		if only_armor >= 0 and armor[k] != only_armor:
			continue
		if only_role >= 0 and role[k] != only_role:
			continue
		match kind_s:
			"damage":
				inspire_until[k] = maxi(inspire_until[k], until)
				inspire_amt[k] = maxf(inspire_amt[k], amount)
			"haste":
				haste_until[k] = maxi(haste_until[k], until)
				haste_amt[k] = maxf(haste_amt[k], amount)
			"guard":
				aegis_until[k] = maxi(aegis_until[k], until)
			"regen":
				regen_until[k] = maxi(regen_until[k], until)
				if amount >= regen_pct[k]:
					regen_src[k] = i
				regen_pct[k] = maxf(regen_pct[k], amount)
			"weaken":
				weaken_until[k] = maxi(weaken_until[k], until)
			"chill":
				if ab_id[k] != Ab.UNSTOPPABLE:
					chill_until[k] = maxi(chill_until[k], until)


## Seraph: brings back the most recently fallen ally nearby, every few seconds.
func _try_resurrect(i: int) -> void:
	if ab_used[i] == 0:
		ab_used[i] = int(ab_val[i] / DT)   # the first one comes after a full wait
		return
	var best := -1
	for k in n:
		if alive[k] == 0 and team[k] == team[i] and raised[k] != 2 and death_tick[k] >= 0:
			var dx := px[k] - px[i]
			var dy := py[k] - py[i]
			if dx * dx + dy * dy <= RESURRECT_RANGE * RESURRECT_RANGE and (best == -1 or death_tick[k] > death_tick[best]):
				best = k
	if best == -1:
		return   # nobody to bring back yet: try again next tick
	alive[best] = 1
	hp[best] = max_hp[best] * 0.5
	st_heal[i] += hp[best]
	raised[best] = 2      # brought back once already
	burn_until[best] = 0
	stun_until[best] = 0
	alive_count[team[best]] += 1
	ab_used[i] = tick + int(ab_val[i] / DT)
	events.append([Ev.RESURRECT, px[best], py[best], best])


## The nearest living enemy of `my_team` within r of (x, y), skipping `skip`.
func _nearest_enemy_near(x: float, y: float, r: float, my_team: int, skip: Dictionary) -> int:
	var best := -1
	var best_d2 := INF
	var rings := ceili(r / CELL)
	var cx := clampi(int(x / CELL), 0, gw - 1)
	var cy := clampi(int(y / CELL), 0, gh - 1)
	for gy in range(maxi(0, cy - rings), mini(gh, cy + rings + 1)):
		for gx in range(maxi(0, cx - rings), mini(gw, cx + rings + 1)):
			var j := cell_head[gy * gw + gx]
			while j != -1:
				if team[j] != my_team and alive[j] == 1 and not skip.has(j):
					var dx := px[j] - x
					var dy := py[j] - y
					var d2 := dx * dx + dy * dy
					var rr := r + radius[j]
					if d2 <= rr * rr and d2 < best_d2:
						best_d2 = d2
						best = j
				j = cell_next[j]
	return best


## killer: the unit that dealt the blow, or -1.
## credit: who the stats count the kill for when there's no killer (burns, blasts).
func _kill(j: int, killer: int = -1, credit: int = -1) -> void:
	if ab_id[j] == Ab.REBIRTH and ab_used[j] == 0:
		# Rises from the ashes once, with part of its health.
		ab_used[j] = 1
		hp[j] = max_hp[j] * ab_val[j]
		burn_until[j] = 0
		stun_until[j] = 0
		events.append([Ev.REBIRTH, px[j], py[j], j])
		return
	hp[j] = 0.0
	alive[j] = 0
	death_tick[j] = tick
	var by := killer if killer >= 0 else credit
	if by >= 0 and team[by] != team[j]:
		st_kills[by] += 1
	alive_count[team[j]] -= 1
	events.append([Ev.DIE, px[j], py[j], j])
	if ab_id[j] == Ab.SPLIT and raised[j] == 0 and ab_tpl[j] >= 0:
		# Splits into two smaller halves (which don't split again).
		events.append([Ev.ABILITY, px[j], py[j], Ab.SPLIT])
		for side in [-1.0, 1.0]:
			var k := n
			_add_resolved(_raise_templates[ab_tpl[j]], team[j], px[j], clampf(py[j] + side * 9.0, 8.0, map_h - 8.0))
			raised[k] = 1
			cd_t[k] = cooldown[k]
	if ab_id[j] == Ab.MARTYR:
		events.append([Ev.ABILITY, px[j], py[j], Ab.MARTYR])
		for k in _enemies_near(px[j], py[j], MARTYR_RADIUS, team[j], true, 12):
			inspire_until[k] = maxi(inspire_until[k], tick + int(ab_val[j] / DT))
			inspire_amt[k] = maxf(inspire_amt[k], MARTYR_RAGE)
	if killer >= 0 and ab_id[killer] == Ab.FRENZY and alive[killer] == 1:
		ab_used[killer] = mini(ab_used[killer] + 1, FRENZY_MAX)
	if ab_id[j] == Ab.DEATH_BLAST:
		# Explodes on death, burning everything around it.
		events.append([Ev.BLAST, px[j], py[j], DEATH_BLAST_RADIUS])
		var blast := max_hp[j] * ab_val[j]
		for k in _enemies_near(px[j], py[j], DEATH_BLAST_RADIUS, team[j]):
			if alive[k] == 1:
				_damage_unit(k, blast, dtype[j], false, -1, j)
	if killer >= 0 and ab_id[killer] == Ab.SOUL_HARVEST and alive[killer] == 1:
		_healed(killer, killer, max_hp[killer] * ab_val[killer])
		ab_used[killer] = mini(ab_used[killer] + 1, HARVEST_MAX_STACKS)
		dmg[killer] = ab_base[killer] * (1.0 + 0.1 * float(ab_used[killer]))
		events.append([Ev.HEAL, px[killer], py[killer], killer])
		events.append([Ev.ABILITY, px[killer], py[killer], Ab.SOUL_HARVEST])
	if killer >= 0 and ab_id[killer] == Ab.RAISE_DEAD and alive[killer] == 1 and raised[j] == 0 \
			and ab_used[killer] < int(ab_val[killer]) and ab_tpl[killer] >= 0:
		# The necromancer raises its victim as a skeleton on its own side.
		ab_used[killer] += 1
		var k := n
		_add_resolved(_raise_templates[ab_tpl[killer]], team[killer], px[j], py[j])
		raised[k] = 1
		cd_t[k] = cooldown[k]
		events.append([Ev.RAISE, px[k], py[k], k])


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
		pr_src.append(-1)
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
	pr_src[p] = i
	pr_x[p] = px[i]
	pr_y[p] = py[i] - radius[i] * 0.5
	pr_tx[p] = px[t]
	pr_ty[p] = py[t]
	pr_dmg[p] = dmg[i]
	pr_aoe[p] = aoe[i]
	pr_speed[p] = _proj_speed[proj[i]]
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
			_deal_damage(pr_src[p], pr_team[p], pr_dtype[p], pr_dmg[p], pr_target[p], pr_tx[p], pr_ty[p], pr_aoe[p], false)
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
		for off in _half_neighbours:
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
## Stats: damage dealt by `by` (-1: nobody) to j, counting only what j had
## left. Call before taking the health off.
func _dot(j: int, amount: float, by: int) -> void:
	var real := clampf(amount, 0.0, maxf(hp[j], 0.0))
	st_taken[j] += real
	if by >= 0 and team[by] != team[j]:
		st_dmg[by] += real


## Heals j by amount (up to its max health), counted for `by`.
func _healed(by: int, j: int, amount: float) -> void:
	var real := minf(amount, max_hp[j] - hp[j])
	hp[j] = minf(max_hp[j], hp[j] + amount)
	if by >= 0 and real > 0.0:
		st_heal[by] += real


## What each squad did, for the battle stats screen: one row per unit type
## and side (units summoned mid-battle get their own rows), best first.
## {team, unit, summoned, count, lost, damage, taken, healing, kills}
func battle_stats() -> Array:
	var rows := {}
	for i in n:
		var key := "%d|%d|%d" % [team[i], kind[i], st_summoned[i]]
		if not rows.has(key):
			rows[key] = {"team": team[i], "unit": unit_ids[kind[i]], "summoned": st_summoned[i] == 1,
				"count": 0, "lost": 0, "damage": 0.0, "taken": 0.0, "healing": 0.0, "kills": 0}
		var r: Dictionary = rows[key]
		r["count"] += 1
		if alive[i] == 0:
			r["lost"] += 1
		r["damage"] += st_dmg[i]
		r["taken"] += st_taken[i]
		r["healing"] += st_heal[i]
		r["kills"] += st_kills[i]
	var out: Array = rows.values()
	out.sort_custom(func(a, b): return a["damage"] + a["healing"] > b["damage"] + b["healing"])
	return out


func checksum() -> int:
	var h := 1469598103
	for i in n:
		h = (h * 31 + int(hp[i] * 10.0) + alive[i] * 7) & 0x7fffffff
	h = (h * 31 + tick) & 0x7fffffff
	h = (h * 31 + winner) & 0x7fffffff
	return h
