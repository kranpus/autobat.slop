class_name Army
extends RefCounted
## Pure helpers for army math: stats per level, squad sizes, power,
## shareable army codes and procedural opponent generation.
##
## A "squad" is a Dictionary: {"unit": String, "level": int, "tier": int, "row": String}
## plus optionally "trinkets": [ids] (main game), or "mods" + "count" (Legion Draft).

const CODE_PREFIX := "AB1:"


static func max_level_for_tier(tier: int) -> int:
	return GameData.BASE_MAX_LEVEL + GameData.LEVELS_PER_TIER * tier


static func level_mult(level: int) -> float:
	return 1.0 + 0.08 * float(level - 1)


static func squad_size(unit_id: String, tier: int) -> int:
	var r: Dictionary = GameData.RARITIES[GameData.UNITS[unit_id]["rarity"]]
	return int(r["squad_base"]) + int(r["squad_step"]) * tier


## Stats of a single unit at a given level, optionally changed by modifiers
## (Legion Draft buffs and trinkets). Supported mod keys:
##   hp_mult, dmg_mult, speed_mult, cooldown_mult, range_add (ranged only),
##   aoe_add, regen_pct (fraction of max HP per second), lifesteal, thorns,
##   flying (bool), armor (String), damage (String)
static func unit_stats(unit_id: String, level: int, mods: Dictionary = {}) -> Dictionary:
	var base: Dictionary = GameData.UNITS[unit_id]
	var m := level_mult(level)
	var s := base.duplicate()
	s["hp"] = float(base["hp"]) * m * float(mods.get("hp_mult", 1.0))
	s["dmg"] = float(base["dmg"]) * m * float(mods.get("dmg_mult", 1.0))
	s["heal"] = float(base["heal"]) * m * float(mods.get("dmg_mult", 1.0))
	s["regen"] = float(base["regen"]) * m + float(s["hp"]) * float(mods.get("regen_pct", 0.0))
	s["speed"] = float(base["speed"]) * float(mods.get("speed_mult", 1.0))
	s["cooldown"] = float(base["cooldown"]) * float(mods.get("cooldown_mult", 1.0))
	if float(base["range"]) >= 20.0:
		s["range"] = float(base["range"]) + float(mods.get("range_add", 0.0))
	s["aoe"] = float(base["aoe"]) + float(mods.get("aoe_add", 0.0))
	s["lifesteal"] = float(mods.get("lifesteal", 0.0))
	var ab = base.get("ability", {})
	if typeof(ab) == TYPE_DICTIONARY and str(ab.get("id", "")) == "devour":
		s["lifesteal"] = float(s["lifesteal"]) + float(ab.get("value", 0.0))
	s["thorns"] = float(mods.get("thorns", 0.0))
	if typeof(ab) == TYPE_DICTIONARY and str(ab.get("id", "")) == "spikes":
		s["thorns"] = float(s["thorns"]) + float(ab.get("value", 0.0))
	if bool(mods.get("flying", false)):
		s["flying"] = true
	if str(mods.get("armor", "")) in GameData.ARMOR_TYPES:
		s["armor"] = str(mods["armor"])
	if str(mods.get("damage", "")) in GameData.DAMAGE_TYPES:
		s["damage"] = str(mods["damage"])
	return s


## Battle modifiers of a squad: Legion Draft passes "mods" directly; main-game
## squads get theirs from their trinkets.
static func squad_mods(sq: Dictionary) -> Dictionary:
	if sq.has("mods"):
		return sq["mods"]
	if sq.has("trinkets"):
		return Trinkets.mods_for(sq["trinkets"])
	return {}


static func unit_power(unit_id: String, level: int, mods: Dictionary = {}) -> float:
	var s := unit_stats(unit_id, level, mods)
	var cd: float = s["cooldown"]
	var splash_share := BattleSim.AOE_SPLASH_MULT if str(s["projectile"]) == "none" else BattleSim.RANGED_SPLASH_MULT
	var splash_bonus := minf(float(s["aoe"]), 60.0) / 40.0 * splash_share / SPLASH_POWER_REF
	var dps: float = (float(s["dmg"]) * (1.0 + splash_bonus) + float(s["heal"]) * HEAL_POWER) / cd + float(s["regen"])
	var reach_bonus := 1.0 + minf(float(s["range"]), 260.0) / 520.0
	# Big units are worth more than raw stats suggest (they can't be swarmed
	# as efficiently), so rarer units carry a calibrated multiplier.
	var rarity_mult: float = GameData.RARITIES[s["rarity"]]["power_mult"]
	var ab := ability_power(s)
	return sqrt(float(s["hp"]) * ab.x * dps * ab.y * reach_bonus) * rarity_mult


## What a point of healing is worth in power, against a point of damage.
## (1.5 before 0.9.2; the simulator showed healers were overrated.)
const HEAL_POWER := 0.7


## The share of a hit that splash damage was worth when the power formula was
## calibrated (splash used to deal 60% of the hit).
const SPLASH_POWER_REF := 0.6
## What each battle ability is worth in power: [toughness mult, damage mult]
## as a function of its value, measured with the balance simulator
## (tools/balance_sim.gd) so armies of equal power stay even fights.
## Tuned with the simulator (armies mode, rounds of ~1300-1500 battles across all 60 units):
## armies with each ability unit should win about as often as others of its
## rarity at equal power.
const ABILITY_TUNING := {
	"stun": 0.15,         # x (stun seconds / cooldown, up to 1), on toughness and damage
	"chill": 0.2,        # x (chill seconds / cooldown, up to 1), on toughness
	"curse": 0.12,         # x (seconds / cooldown, up to 1), on damage
	"weaken": 0.15,       # x (seconds / cooldown, up to 1), on toughness
	"burn": 0.05,          # x burn share, on damage
	"chain": 1.0,         # x chain damage share (later jumps rarely find targets: capped at CHAIN_POWER_CAP)
	"double_strike": 0.55, # x extra targets, on damage
	"charge": 0.25,       # x (multiplier - 1), on damage
	"rebirth": 0.2,       # x health share revived, on toughness
	"unstoppable": 3.0,   # x projectile resistance, on toughness
	"devour": 0.05,        # x lifesteal share, on toughness
	"raise_dead": 0.0,    # on toughness and damage
	"quake": 0.15,        # x (stun seconds / cooldown, up to 1), on toughness and damage
	"predator": 0.05,      # x bonus (share of targets that are ranged), on damage
	"knockback": 0.0,     # on toughness
	"death_blast": 2.0,   # x health share, on damage
	"heads": 0.2,         # x attack speed per head (about 1.5 heads on average), on damage
	"soul_harvest": 0.2,  # x heal share, on toughness; kills also add damage
	"dread": 0.45,         # on toughness
	"rising_storm": 0.3,  # on damage (the cap is reached after ~20 blows)
	"resurrect": 0.35,    # on toughness and damage
	"aegis": 1.2,        # on toughness
	# The 0.9.4 set (tuned with tools/balance_sim.gd).
	"venom": 1.1, "purify": 0.0, "split": 1.8, "shell": 0.8, "ensnare": 0.05, "pounce": 0.0,
	"corrode": 0.6, "spikes": 0.4, "summon": 0.15, "blink": 0.0, "block": 1.3, "volley": 1.3,
	"evasion": 1.4, "song": 1.4, "undertow": 0.17, "frenzy": 0.2, "taunt": 0.08, "pull": 0.1,
	"tidal_wave": 0.7, "avalanche": 0.8, "detonate": 0.6, "martyr": 0.3, "pack": 0.15, "reflect": 0.1,
	"berserk": 0.45, "thunderstrike": 1.2, "immolate": 1.0, "execute": 0.33, "terror": 0.38, "ward": 0.4,
	"inspire": 1.0, "frost_armor": 0.15, "frost_aura": 0.32, "entomb": 0.1, "fortify": 0.8, "phase": 0.0,
}
const CHAIN_POWER_CAP := 1.2


## [toughness multiplier, damage multiplier] for a unit's battle ability.
static func ability_power(s: Dictionary) -> Vector2:
	var ab = s.get("ability", {})
	if typeof(ab) != TYPE_DICTIONARY or not ab.has("id"):
		return Vector2.ONE
	var v := float(ab.get("value", 0.0))
	var cd := maxf(0.2, float(s["cooldown"]))
	match str(ab["id"]):
		"stun":
			return Vector2(1.0 + ABILITY_TUNING["stun"] * minf(v / cd, 1.0), 1.0 + ABILITY_TUNING["stun"] * minf(v / cd, 1.0))
		"chill":
			return Vector2(1.0 + ABILITY_TUNING["chill"] * minf(v / cd, 1.0), 1.0)
		"curse":
			return Vector2(1.0, 1.0 + ABILITY_TUNING["curse"] * minf(v / cd, 1.0))
		"weaken":
			return Vector2(1.0 + ABILITY_TUNING["weaken"] * minf(v / cd, 1.0), 1.0)
		"burn":
			return Vector2(1.0, 1.0 + ABILITY_TUNING["burn"] * v)
		"chain":
			var sum := 0.0
			var f := 1.0
			for _k in int(v):
				f *= BattleSim.CHAIN_FALLOFF
				sum += f
			return Vector2(1.0, 1.0 + ABILITY_TUNING["chain"] * minf(sum, CHAIN_POWER_CAP))
		"double_strike":
			return Vector2(1.0, 1.0 + ABILITY_TUNING["double_strike"] * v)
		"charge":
			return Vector2(1.0, 1.0 + ABILITY_TUNING["charge"] * (v - 1.0))
		"rebirth":
			return Vector2(1.0 + ABILITY_TUNING["rebirth"] * v, 1.0)
		"unstoppable":
			return Vector2(1.0 + ABILITY_TUNING["unstoppable"] * v, 1.0)
		"devour":
			return Vector2(1.0 + ABILITY_TUNING["devour"] * v, 1.0)
		"raise_dead":
			return Vector2(1.0 + ABILITY_TUNING["raise_dead"], 1.0 + ABILITY_TUNING["raise_dead"])
		"quake":
			var q := 1.0 + ABILITY_TUNING["quake"] * minf(v / cd, 1.0)
			return Vector2(q, q)
		"predator":
			return Vector2(1.0, 1.0 + ABILITY_TUNING["predator"] * v)
		"knockback":
			return Vector2(1.0 + ABILITY_TUNING["knockback"], 1.0)
		"death_blast":
			return Vector2(1.0, 1.0 + ABILITY_TUNING["death_blast"] * v)
		"heads":
			return Vector2(1.0, 1.0 + ABILITY_TUNING["heads"] * v)
		"soul_harvest":
			return Vector2(1.0 + ABILITY_TUNING["soul_harvest"] * v, 1.0)
		"dread":
			return Vector2(1.0 + ABILITY_TUNING["dread"], 1.0)
		"rising_storm":
			return Vector2(1.0, 1.0 + ABILITY_TUNING["rising_storm"])
		"resurrect":
			return Vector2(1.0 + ABILITY_TUNING["resurrect"], 1.0 + ABILITY_TUNING["resurrect"])
		"aegis":
			return Vector2(1.0 + ABILITY_TUNING["aegis"], 1.0)
		# --- 0.9.4 ---
		"venom", "volley", "song", "berserk", "execute", "inspire":
			return Vector2(1.0, 1.0 + ABILITY_TUNING[ab["id"]] * v)
		"split", "spikes", "block", "evasion", "reflect", "ward":
			return Vector2(1.0 + ABILITY_TUNING[ab["id"]] * v, 1.0)
		"purify", "taunt", "martyr", "frost_aura", "undertow":
			return Vector2(1.0 + ABILITY_TUNING[ab["id"]], 1.0)
		"pounce":
			return Vector2(1.0, 1.0 + ABILITY_TUNING["pounce"])
		"pull", "summon":
			var q: float = 1.0 + float(ABILITY_TUNING[ab["id"]])
			return Vector2(q, q)
		"shell":
			return Vector2(1.0 + ABILITY_TUNING["shell"] * minf(v / 10.0, 1.0), 1.0)
		"ensnare", "terror", "frost_armor":
			return Vector2(1.0 + ABILITY_TUNING[ab["id"]] * minf(v / cd, 1.0), 1.0)
		"corrode":
			return Vector2(1.0, 1.0 + ABILITY_TUNING["corrode"] * minf(BattleSim.CORRODE_MAX, v * 4.0))
		"blink":
			return Vector2(1.0, 1.0 + ABILITY_TUNING["blink"] * (v - 1.0))
		"frenzy":
			return Vector2(1.0, 1.0 + ABILITY_TUNING["frenzy"] * v * float(BattleSim.FRENZY_MAX))
		"pack":
			return Vector2(1.0, 1.0 + ABILITY_TUNING["pack"] * v * float(BattleSim.PACK_MAX))
		"tidal_wave", "avalanche":
			return Vector2(1.0, 1.0 + ABILITY_TUNING[ab["id"]] * BattleSim.WAVE_MULT * 6.0 * cd / maxf(1.0, v))
		"thunderstrike":
			return Vector2(1.0, 1.0 + ABILITY_TUNING["thunderstrike"] * BattleSim.STRIKE_MULT * cd / maxf(1.0, v))
		"immolate":
			return Vector2(1.0, 1.0 + ABILITY_TUNING["immolate"] * v * cd * 4.0)
		"detonate":
			return Vector2(0.7, 1.0 + ABILITY_TUNING["detonate"] * v)
		"entomb":
			var e := 1.0 + ABILITY_TUNING["entomb"] * minf(v / (cd * float(BattleSim.ENTOMB_EVERY)), 1.0)
			return Vector2(e, e)
		"fortify":
			return Vector2(1.0 + ABILITY_TUNING["fortify"] * BattleSim.FORTIFY_MAX, 1.0)
		"phase":
			return Vector2(1.0 + ABILITY_TUNING["phase"] * BattleSim.PHASE_SECONDS / maxf(1.0, v), 1.0)
	return Vector2.ONE


## How much a squad's size counts toward its power, by role. Measured in the
## simulator: doubling a melee squad makes it about 1.8x as strong (only the
## front of a crowd can reach the enemy), so melee and tank squads grow with
## count^0.85. Ranged units, casters and healers all act at once, so their
## count stays fully counted.
const COUNT_EXPONENT := {"melee": 0.85, "tank": 0.85}


## Power of `count` units of a kind (the building block of army power).
static func squad_power(unit_id: String, level: int, count: int, mods: Dictionary = {}) -> float:
	var e := float(COUNT_EXPONENT.get(str(GameData.UNITS[unit_id]["role"]), 1.0))
	return unit_power(unit_id, level, mods) * pow(float(maxi(0, count)), e)


## Units deployed per squad. There is no army-wide cap: every squad fights at
## full size, so the army limit is MAX_SQUADS squads. A squad may carry an
## explicit "count" (used by Legion Draft) instead of a tier.
static func deploy_counts(squads: Array) -> Array:
	var out: Array = []
	for sq in squads:
		if sq.has("count"):
			out.append(maxi(1, int(sq["count"])))
		else:
			var n := squad_size(sq["unit"], int(sq.get("tier", 0)))
			if sq.has("trinkets"):
				n = maxi(1, roundi(float(n) * Trinkets.count_mult(sq["trinkets"])))
			out.append(n)
	return out


static func total_units(squads: Array) -> int:
	var t := 0
	for n in deploy_counts(squads):
		t += int(n)
	return t


static func army_power(squads: Array) -> float:
	var counts := deploy_counts(squads)
	var p := 0.0
	for i in squads.size():
		p += squad_power(squads[i]["unit"], int(squads[i]["level"]), int(counts[i]), squad_mods(squads[i]))
	return p


static func format_power(p: float) -> String:
	return str(roundi(p / 10.0))


# --- Army codes (shareable text for async PvP challenges) -------------------

static func encode(player_name: String, rating: int, squads: Array) -> String:
	var s: Array = []
	for sq in squads:
		var e: Array = [sq["unit"], int(sq["level"]), int(sq["tier"]), GameData.ROWS.find(sq["row"])]
		if not (sq.get("trinkets", []) as Array).is_empty():
			e.append(sq["trinkets"])
		s.append(e)
	var payload := {"n": player_name.left(24), "r": rating, "s": s}
	return CODE_PREFIX + Marshalls.utf8_to_base64(JSON.stringify(payload))


## Returns {} when the code is invalid. Values are clamped to legal ranges.
static func decode(code: String) -> Dictionary:
	code = code.strip_edges()
	if not code.begins_with(CODE_PREFIX):
		return {}
	var text := Marshalls.base64_to_utf8(code.substr(CODE_PREFIX.length()))
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("s") or typeof(parsed["s"]) != TYPE_ARRAY:
		return {}
	var squads: Array = []
	for entry in parsed["s"]:
		if typeof(entry) != TYPE_ARRAY or entry.size() < 4:
			continue
		var uid := str(entry[0])
		if not GameData.UNITS.has(uid) or UnitLocks.is_locked(uid):
			continue
		var tier := clampi(int(entry[2]), 0, GameData.MAX_TIER)
		var level := clampi(int(entry[1]), 1, max_level_for_tier(tier))
		var row_i := clampi(int(entry[3]), 0, GameData.ROWS.size() - 1)
		var sq := {"unit": uid, "level": level, "tier": tier, "row": GameData.ROWS[row_i]}
		var trinkets := Trinkets.clean_list(entry[4]) if entry.size() > 4 else []
		# A trinket can only be on one squad.
		for other in squads:
			for t in other.get("trinkets", []):
				trinkets.erase(t)
		if not trinkets.is_empty():
			sq["trinkets"] = trinkets
		squads.append(sq)
		if squads.size() >= GameData.MAX_SQUADS:
			break
	if squads.is_empty():
		return {}
	return {
		"name": str(parsed.get("n", "Challenger")).left(24),
		"rating": int(parsed.get("r", 1000)),
		"squads": squads,
	}


# --- Opponent generation (ranked ghosts) ------------------------------------

const GHOST_NAMES := [
	"Warlord Grak", "Lady Vesper", "The Bone Duke", "Mira Swiftbow", "Old Thane Borin",
	"Sable Witch", "Captain Rook", "Iron Hilda", "Kael the Red", "Nyx", "Brother Ash",
	"Queen Morwen", "Zug Zug", "The Pale Rider", "Ser Galen", "Hexa", "Tuskbreaker",
]


## Generated ("training") ranked opponents: power relative to yours, rating
## offset, label. Measured in the simulator (each pairing fought from both
## sides) against a generated army of your power, you win about 55% at 0.9x,
## 21% at 1.1x and 5% at 1.5x: a hard ladder that rewards a well-built army.
## The rating offsets pay more for the harder fights but less than those
## odds would (Easy is about fair, Even and Hard lose rating on average for
## an ordinary army), so none of them is a free climb.
## These are the defaults; the server can change them (Difficulty).
const GHOST_TIERS := [[0.9, -40, "Easy"], [1.1, 60, "Even"], [1.5, 150, "Hard"]]
## Saved player armies are searched around your rating plus this.
const RANKED_SEARCH_BIAS := 0
## Real opponents more than this far from your rating are labelled Easy / Hard.
const RANKED_LABEL_GAP := 40


## Fill `offers` up to three opponents with generated ones, first covering any
## missing difficulty. Each gets "difficulty" and "player": false.
static func fill_ghosts(offers: Array, my_power: float, rating: int, rng: RandomNumberGenerator) -> void:
	for pass_i in 2:
		for t in Difficulty.tiers:   # GHOST_TIERS unless the server admin changed them
			if offers.size() >= 3:
				return
			var taken := false
			for o in offers:
				if o.get("difficulty", "") == t[2]:
					taken = true
			if taken and pass_i == 0:
				continue
			var opp := generate_opponent(maxf(500.0, my_power) * float(t[0]) * rng.randf_range(0.95, 1.05), maxi(0, rating + int(t[1]) + rng.randi_range(-15, 15)), rng.randi())
			opp["difficulty"] = t[2]
			opp["player"] = false
			opp["saved_at"] = 0
			offers.append(opp)


## trinkets: false leaves them out (the balance simulator measures bare units).
static func generate_opponent(target_power: float, rating: int, seed_value: int, trinkets: bool = true) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	# Higher ratings unlock rarer units for ghosts.
	# Rarer units appear as rating rises, roughly with the expedition ladder.
	var max_rarity := 1
	if rating >= 1200:
		max_rarity = 2
	if rating >= 1700:
		max_rarity = 3
	if rating >= 2500:
		max_rarity = 4
	var pool: Array = []
	for id in UnitLocks.unlocked_ids():
		if int(GameData.RARITIES[GameData.UNITS[id]["rarity"]]["order"]) <= max_rarity:
			pool.append(id)
	var squad_count := rng.randi_range(3, GameData.MAX_SQUADS)
	var squads: Array = []
	var used := {}
	for i in squad_count:
		var id: String = pool[rng.randi_range(0, pool.size() - 1)]
		if used.has(id):
			continue
		used[id] = true
		squads.append({"unit": id, "level": 1, "tier": 0, "row": GameData.default_row_for(id)})
	if trinkets:
		_give_ghost_trinkets(squads, rating, rng)
	# Upgrade random squads until we reach the target power.
	var guard := 0
	while army_power(squads) < target_power and guard < 2000:
		guard += 1
		var sq: Dictionary = squads[rng.randi_range(0, squads.size() - 1)]
		if rng.randf() < 0.55 and int(sq["level"]) < max_level_for_tier(int(sq["tier"])):
			sq["level"] = int(sq["level"]) + 1
		elif int(sq["tier"]) < GameData.MAX_TIER:
			sq["tier"] = int(sq["tier"]) + 1
		elif int(sq["level"]) < max_level_for_tier(int(sq["tier"])):
			sq["level"] = int(sq["level"]) + 1
		elif squads.size() < GameData.MAX_SQUADS and squads.all(func(q): return int(q["tier"]) >= GameData.MAX_TIER and int(q["level"]) >= max_level_for_tier(int(q["tier"]))):
			# Everything is maxed: very strong targets get extra squads.
			var spare: Array = pool.filter(func(u): return not used.has(u))
			if spare.is_empty():
				break
			var extra: String = spare[rng.randi_range(0, spare.size() - 1)]
			used[extra] = true
			squads.append({"unit": extra, "level": 1, "tier": 0, "row": GameData.default_row_for(extra)})
	return {
		"name": GHOST_NAMES[rng.randi_range(0, GHOST_NAMES.size() - 1)],
		"rating": rating,
		"squads": squads,
	}


## Higher-rated ghosts carry trinkets (more, and rarer, as rating rises).
static func _give_ghost_trinkets(squads: Array, rating: int, rng: RandomNumberGenerator) -> void:
	var chance := clampf(float(rating - 950) / 700.0, 0.0, 0.85)
	if chance <= 0.0:
		return
	var max_order := 1 if rating < 1200 else (2 if rating < 1700 else (3 if rating < 2500 else 4))
	var used := {}
	for sq in squads:
		if rng.randf() >= chance:
			continue
		var ts: Array = []
		for _k in (2 if rng.randf() < chance * 0.6 else 1):
			# Lower rarities are likelier: weight = max_order - order + 1.
			var total := 0
			for o in max_order + 1:
				total += max_order - o + 1
			var roll := rng.randi_range(1, total)
			var order := 0
			for o in max_order + 1:
				roll -= max_order - o + 1
				if roll <= 0:
					order = o
					break
			var pool: Array = []
			for id in Trinkets.ids_by_rarity(Trinkets.RARITY_ORDER[order]):
				if not used.has(id):
					pool.append(id)
			if pool.is_empty():
				continue
			var pick: String = pool[rng.randi_range(0, pool.size() - 1)]
			used[pick] = true
			ts.append(pick)
		if not ts.is_empty():
			sq["trinkets"] = ts


## Ranked/live win gold multiplier for your rating: x1 up to 1000, then
## +100% for every 1000 rating above it (x2 at 2000, x3.5 at 3500).
static func win_gold_mult(rating: int) -> float:
	return 1.0 + maxf(0.0, float(rating - 1000)) / 1000.0


## How fast rating moves (Elo K-factor): 24 up to 1200 rating, falling to 12
## at 3000 and above, so the top of the ladder takes longer to climb.
## (Before 0.9 it was 32 at every rating.)
const RATING_K_LOW := 24.0
const RATING_K_HIGH := 12.0
const RATING_K_FROM := 1200
const RATING_K_TO := 3000


static func rating_k(rating: int) -> float:
	var t := clampf(float(rating - RATING_K_FROM) / float(RATING_K_TO - RATING_K_FROM), 0.0, 1.0)
	return lerpf(RATING_K_LOW, RATING_K_HIGH, t)


## k < 0: the K-factor for my_rating (rating_k).
static func elo_delta(my_rating: int, opp_rating: int, score: float, k: float = -1.0) -> int:
	if k < 0.0:
		k = rating_k(my_rating)
	var expected := 1.0 / (1.0 + pow(10.0, float(opp_rating - my_rating) / 400.0))
	return roundi(k * (score - expected))
