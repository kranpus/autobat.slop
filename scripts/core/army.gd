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
	s["thorns"] = float(mods.get("thorns", 0.0))
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
	var splash_bonus := minf(float(s["aoe"]), 60.0) / 40.0 * splash_share / BattleSim.AOE_SPLASH_MULT
	var dps: float = (float(s["dmg"]) * (1.0 + splash_bonus) + float(s["heal"]) * 1.5) / cd + float(s["regen"])
	var reach_bonus := 1.0 + minf(float(s["range"]), 260.0) / 520.0
	# Big units are worth more than raw stats suggest (they can't be swarmed
	# as efficiently), so rarer units carry a calibrated multiplier.
	var rarity_mult: float = GameData.RARITIES[s["rarity"]]["power_mult"]
	return sqrt(float(s["hp"]) * dps * reach_bonus) * rarity_mult


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
## offset, label. On average a little stronger than you (about 1.08x).
const GHOST_TIERS := [[0.9, -30, "Easy"], [1.05, 20, "Even"], [1.3, 90, "Hard"]]
## Saved player armies are searched around your rating plus this, so real
## opponents also lean slightly stronger.
const RANKED_SEARCH_BIAS := 20


## Fill `offers` up to three opponents with generated ones, first covering any
## missing difficulty. Each gets "difficulty" and "player": false.
static func fill_ghosts(offers: Array, my_power: float, rating: int, rng: RandomNumberGenerator) -> void:
	for pass_i in 2:
		for t in GHOST_TIERS:
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


static func generate_opponent(target_power: float, rating: int, seed_value: int) -> Dictionary:
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


static func elo_delta(my_rating: int, opp_rating: int, score: float, k: float = 32.0) -> int:
	var expected := 1.0 / (1.0 + pow(10.0, float(opp_rating - my_rating) / 400.0))
	return roundi(k * (score - expected))
