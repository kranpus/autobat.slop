class_name ProfileLogic
extends RefCounted
## A player's progress and every rule that changes it: currencies, collection,
## upgrades, expeditions (with pity), army and battle rewards.
##
## Pure data + rules, no saving or networking: the server runs one of these
## per account (authoritative), and the game runs one for the offline profile.

const SAVE_VERSION := 1
const MAP_REGEN_SECONDS := 600
const MAX_MAPS := 10
## Rating a new commander starts at (1000 before 0.9.5). Rating never goes
## below 0.
const START_RATING := 0

var data: Dictionary = {}
## Gold multiplier for battle rewards (set by the server admin's `gold battle`).
var gold_mult := 1.0


func _init(initial: Dictionary = {}) -> void:
	load_from(initial)


static func default_profile() -> Dictionary:
	var units := {}
	for id in GameData.STARTER_UNITS:
		units[id] = {"level": 1, "tier": 0, "shards": 0}
	var army: Array = []
	for id in GameData.STARTER_UNITS:
		army.append({"unit": id, "row": GameData.default_row_for(id)})
	return {
		"version": SAVE_VERSION,
		"name": "Commander",
		"gold": 600,
		"maps": 5,
		"map_clock": int(Time.get_unix_time_from_system()),
		"rating": START_RATING,
		"wins": 0,
		"losses": 0,
		"units": units,
		"army": army,
		"trinkets": {},           # owned trinket id -> true
		"challenges": {},         # cleared challenge id -> true
		"pending_trinket": {},    # an open trinket hunt choice
		"levels_version": 2,      # 0.9.7 per-rarity levels
		"xp": 0,                  # commander XP (0.9.7)
		"level_rewarded": 1,      # commander levels whose reward has been paid
		"quests": {},             # the quest log (see Progression)
		"sigils": 0,              # champion Altar rolls (0.9.9)
	}


## Replace the data with `source` merged over the defaults, cleaned up.
func load_from(source: Dictionary) -> void:
	data = default_profile()
	for k in source:
		data[k] = source[k]
	if not source.is_empty() and not source.has("levels_version"):
		data["levels_version"] = 1   # saved before 0.9.7: old-style levels
	if not source.is_empty() and not source.has("xp"):
		_start_commander_level(source)
	_sanitize()
	_regen_maps()
	refresh_quests()


func reset() -> void:
	data = default_profile()
	_sanitize_quests()
	refresh_quests()


func _sanitize() -> void:
	# JSON turns ints into floats; normalise and drop unknown units.
	for k in ["gold", "maps", "map_clock", "rating", "wins", "losses"]:
		data[k] = int(data.get(k, 0))
	var units := {}
	# Before 0.9.7 every rarity used the same 50 levels; now rarer units have
	# fewer, starting further up (Army.RARITY_LEVELS). Old levels move to the
	# nearest new level that isn't weaker.
	var old_levels := int(data.get("levels_version", 1)) < 2
	for id in data.get("units", {}):
		if GameData.UNITS.has(id):
			var u: Dictionary = data["units"][id]
			var tier := clampi(int(u.get("tier", 0)), 0, GameData.MAX_TIER)
			var lvl := int(u.get("level", 1))
			lvl = Army.level_from_old(id, lvl, tier) if old_levels else clampi(lvl, 1, Army.max_level(id, tier))
			units[id] = {"level": lvl, "tier": tier, "shards": int(u.get("shards", 0))}
			if u.has("trinkets"):
				units[id]["trinkets"] = Trinkets.clean_list(u["trinkets"])
	data["units"] = units
	data["levels_version"] = 2
	# Trinkets: only known, owned ones, each held by at most one unit.
	var owned_t := {}
	var raw_t = data.get("trinkets", {})
	if typeof(raw_t) == TYPE_DICTIONARY:
		for t in raw_t:
			if Trinkets.exists(str(t)):
				owned_t[str(t)] = true
	data["trinkets"] = owned_t
	var held := {}
	for id in units:
		var keep: Array = []
		for t in units[id].get("trinkets", []):
			if owned_t.has(t) and not held.has(t):
				held[t] = true
				keep.append(t)
		units[id]["trinkets"] = keep
	var pt = data.get("pending_trinket", {})
	var clean_pt := {}
	if typeof(pt) == TYPE_DICTIONARY and Trinkets.SITES.has(str(pt.get("site", ""))):
		var opts := Trinkets.clean_list(pt.get("options", []))
		for o in pt.get("options", []):
			if Trinkets.exists(str(o)) and not opts.has(str(o)):
				opts.append(str(o))   # clean_list stops at 2; a hunt offers 3
		if not opts.is_empty():
			clean_pt = {"site": str(pt["site"]), "options": opts.slice(0, 3)}
	data["pending_trinket"] = clean_pt
	var cleared := {}
	var raw_c = data.get("challenges", {})
	if typeof(raw_c) == TYPE_DICTIONARY:
		for c in raw_c:
			if Challenges.index_of(str(c)) >= 0:
				cleared[str(c)] = true
	data["challenges"] = cleared
	var army: Array = []
	for sq in data.get("army", []):
		if typeof(sq) == TYPE_DICTIONARY and units.has(str(sq.get("unit", ""))):
			var row := str(sq.get("row", "front"))
			if row not in GameData.ROWS:
				row = "front"
			army.append({"unit": str(sq["unit"]), "row": row})
	data["army"] = army
	var pc = data.get("pending_choice", {})
	var clean_pc := {}
	if typeof(pc) == TYPE_DICTIONARY and pc.has("options") and typeof(pc["options"]) == TYPE_ARRAY:
		var opts: Array = []
		for o in pc["options"]:
			if typeof(o) == TYPE_DICTIONARY and GameData.UNITS.has(str(o.get("unit", ""))):
				opts.append({"unit": str(o["unit"]), "shards": int(o.get("shards", 1)), "guaranteed": bool(o.get("guaranteed", false))})
		if not opts.is_empty():
			clean_pc = {"region": str(pc.get("region", "")), "options": opts, "gold": int(pc.get("gold", 0))}
	data["pending_choice"] = clean_pc
	data["xp"] = clampi(int(data.get("xp", 0)), 0, Progression.xp_for_level(Progression.MAX_LEVEL))
	data["level_rewarded"] = clampi(int(data.get("level_rewarded", 1)), 1, Progression.MAX_LEVEL)
	_sanitize_quests()
	data["sigils"] = maxi(0, int(data.get("sigils", 0)))
	if data.has("champion"):
		data["champion"] = Champion.sanitize(data["champion"])
	_ensure_champion()


func _regen_maps() -> void:
	var now := int(Time.get_unix_time_from_system())
	if int(data["maps"]) >= max_maps():
		data["map_clock"] = now
		return
	var elapsed := now - int(data["map_clock"])
	@warning_ignore("integer_division")
	var gained := elapsed / MAP_REGEN_SECONDS
	if gained > 0:
		data["maps"] = mini(max_maps(), int(data["maps"]) + gained)
		data["map_clock"] = int(data["map_clock"]) + gained * MAP_REGEN_SECONDS


## Seconds until the next free scouting map, or -1 when full.
func seconds_to_next_map() -> int:
	_regen_maps()
	if int(data["maps"]) >= max_maps():
		return -1
	return MAP_REGEN_SECONDS - (int(Time.get_unix_time_from_system()) - int(data["map_clock"]))


# --- accessors --------------------------------------------------------------

func gold() -> int:
	return int(data["gold"])


func maps() -> int:
	_regen_maps()
	return int(data["maps"])


func rating() -> int:
	return int(data["rating"])


## Anonymous id for this player's saved ranked army on the server.
func player_id() -> String:
	if str(data.get("player_id", "")).length() < 16:
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		var id := ""
		for i in 24:
			id += "0123456789abcdef"[rng.randi_range(0, 15)]
		data["player_id"] = id
	return str(data["player_id"])


func player_name() -> String:
	return str(data["name"])


func owns(id: String) -> bool:
	return data["units"].has(id)


func unit(id: String) -> Dictionary:
	return data["units"].get(id, {})


func level_cap(id: String) -> int:
	return Army.max_level(id, int(unit(id).get("tier", 0)))


func squad_size(id: String) -> int:
	return Army.squad_size(id, int(unit(id).get("tier", 0)))


# --- upgrades ---------------------------------------------------------------

func level_up_cost(id: String) -> int:
	# Priced by where the unit is on the stat scale (0.9.7): a rare's first
	# level costs what a common's 21st does, since it adds the same stats.
	var lvl := Army.stat_level(id, int(unit(id).get("level", 1)))
	var rarity := str(GameData.UNITS[id]["rarity"])
	if FIRST_LEVEL_COST.has(rarity):
		# Same curve, scaled so the first level-up costs FIRST_LEVEL_COST.
		var first := float(Army.stat_level(id, 1))
		return roundi(float(FIRST_LEVEL_COST[rarity]) * pow(float(lvl) / first, 1.6))
	var mult: float = GameData.RARITIES[rarity]["cost_mult"]
	return roundi(40.0 * pow(float(lvl), 1.6) * mult)


## 0.9.8: levels above common are much cheaper: the first level-up costs this
## much, later ones follow the usual curve from there.
const FIRST_LEVEL_COST := {"uncommon": 250, "rare": 700, "epic": 5000, "legendary": 10000}


func can_level_up(id: String) -> bool:
	return owns(id) and int(unit(id)["level"]) < level_cap(id) and gold() >= level_up_cost(id)


func level_up(id: String) -> bool:
	if not can_level_up(id):
		return false
	var cost := level_up_cost(id)
	data["gold"] = gold() - cost
	data["units"][id]["level"] = int(data["units"][id]["level"]) + 1
	_on("unit_level")
	quest_event("gold_spend", cost)
	return true


## {"gold": int, "shards": int} needed for the next squad-size tier.
func tier_up_cost(id: String) -> Dictionary:
	var tier := int(unit(id).get("tier", 0))
	var r: Dictionary = GameData.RARITIES[GameData.UNITS[id]["rarity"]]
	return {
		# Epic and legendary squads grow more slowly (tier_shard_mult, patch 0.9.2).
		"shards": ceili(float(r["shard_base"]) * float(tier + 1) * 0.75 * float(r.get("tier_shard_mult", 1.0))),
		"gold": roundi(100.0 * float(tier + 1) * float(r["cost_mult"])),
	}


func can_tier_up(id: String) -> bool:
	if not owns(id) or int(unit(id)["tier"]) >= GameData.MAX_TIER:
		return false
	var c := tier_up_cost(id)
	return gold() >= int(c["gold"]) and int(unit(id)["shards"]) >= int(c["shards"])


func tier_up(id: String) -> bool:
	if not can_tier_up(id):
		return false
	var c := tier_up_cost(id)
	data["gold"] = gold() - int(c["gold"])
	var u: Dictionary = data["units"][id]
	u["shards"] = int(u["shards"]) - int(c["shards"])
	u["tier"] = int(u["tier"]) + 1
	_on("tier_up")
	quest_event("gold_spend", int(c["gold"]))
	return true


# --- expeditions (finding units) ------------------------------------------

func region_unlocked(region_id: String) -> bool:
	return rating() >= int(GameData.REGIONS[region_id]["min_rating"]) and not UnitLocks.is_region_locked(region_id)


func can_explore(region_id: String) -> bool:
	return not has_pending_choice() and region_unlocked(region_id) and maps() >= int(GameData.REGIONS[region_id]["cost_maps"]) \
		and not GameData.region_drops(region_id).is_empty()


func has_pending_choice() -> bool:
	return not data.get("pending_choice", {}).is_empty()


## The open recruit choice: {"region": id, "options": [{unit, shards}], "gold": int}
func pending_choice() -> Dictionary:
	return data.get("pending_choice", {})


## Spend maps, find gold, and roll 3 different units for the player to choose
## from. The choice is saved, so closing the game doesn't reroll it.
func explore(region_id: String) -> Dictionary:
	if not can_explore(region_id):
		return {}
	var region: Dictionary = GameData.REGIONS[region_id]
	if int(data["maps"]) >= max_maps():
		data["map_clock"] = int(Time.get_unix_time_from_system())
	data["maps"] = int(data["maps"]) - int(region["cost_maps"])
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var pool: Dictionary = GameData.region_drops(region_id)
	var picks: Array = []
	for _i in mini(GameData.FINDS_PER_EXPEDITION, pool.size()):
		var picked := _weighted_pick(pool, rng)
		pool.erase(picked)
		picks.append(picked)
	var guaranteed := _apply_pity(region_id, picks, rng)
	# 0.9.9: the starters come from the Badlands Camp, so until a commander has
	# recruited anyone, an offer always holds at least one unit they don't own.
	if data["units"].size() <= GameData.STARTER_UNITS.size() and picks.all(func(u): return data["units"].has(u)):
		var fresh := {}
		var drops: Dictionary = GameData.region_drops(region_id)
		for u in drops:
			if not data["units"].has(u) and not picks.has(u):
				fresh[u] = drops[u]
		if not fresh.is_empty():
			var k := picks.size() - 1
			while k > 0 and str(picks[k]) == guaranteed:
				k -= 1
			picks[k] = _weighted_pick(fresh, rng)
	var options: Array = []
	for picked in picks:
		var range_: Array = GameData.RARITIES[GameData.UNITS[picked]["rarity"]]["find_shards"]
		var shards := rng.randi_range(int(range_[0]), int(range_[1])) * int(region["cost_maps"]) * GameData.CHOICE_SHARD_MULT
		options.append({"unit": picked, "shards": shards, "guaranteed": picked == guaranteed})
	var gold_found := rng.randi_range(15, 45) * int(region["cost_maps"])
	_on("explore")
	data["gold"] = gold() + gold_found
	data["pending_choice"] = {"region": region_id, "options": options, "gold": gold_found}
	return pending_choice()


func _rarity_order(unit_id: String) -> int:
	return int(GameData.RARITIES[GameData.UNITS[unit_id]["rarity"]]["order"])


## Expeditions since an offer last contained `rarity` or better.
func pity_count(rarity: String) -> int:
	return int(data.get("pity", {}).get(rarity, 0))


## How many more expeditions until `rarity`+ is guaranteed (1 = the next one).
func pity_remaining(rarity: String) -> int:
	for p in DropRates.pity_rules():
		if p["rarity"] == rarity:
			return maxi(1, int(p["every"]) - pity_count(rarity))
	return -1


## Force rarer units into the offer when a pity counter is due, then update
## the counters. Returns the unit that was guaranteed ("" if none).
func _apply_pity(region_id: String, picks: Array, rng: RandomNumberGenerator) -> String:
	var drops: Dictionary = GameData.region_drops(region_id)
	var pity: Dictionary = data.get("pity", {})
	var guaranteed := ""
	# Highest tier first, so one forced legendary also satisfies rare/epic.
	var rules := DropRates.pity_rules()
	for k in range(rules.size() - 1, -1, -1):
		var rule: Dictionary = rules[k]
		var need := int(GameData.RARITIES[rule["rarity"]]["order"])
		if int(pity.get(rule["rarity"], 0)) + 1 < int(rule["every"]):
			continue
		var has := false
		for u in picks:
			if _rarity_order(u) >= need:
				has = true
		if has:
			continue
		var candidates := {}
		for u in drops:
			if _rarity_order(u) >= need and u not in picks:
				candidates[u] = drops[u]
		if candidates.is_empty():
			continue  # this region has nothing that rare; keep the counter
		# Replace the most common unit in the offer.
		var worst := 0
		for i in picks.size():
			if _rarity_order(picks[i]) < _rarity_order(picks[worst]):
				worst = i
		picks[worst] = _weighted_pick(candidates, rng)
		if guaranteed == "":
			guaranteed = picks[worst]
	var best := 0
	for u in picks:
		best = maxi(best, _rarity_order(u))
	for rule in rules:
		var r: String = rule["rarity"]
		var region_has := false
		for u in drops:
			if _rarity_order(u) >= int(GameData.RARITIES[r]["order"]):
				region_has = true
		if best >= int(GameData.RARITIES[r]["order"]):
			pity[r] = 0
		elif region_has:
			pity[r] = int(pity.get(r, 0)) + 1
	data["pity"] = pity
	return guaranteed


## Take option `index` from the pending choice. Returns {unit, shards, new}.
func choose_recruit(index: int) -> Dictionary:
	var pc := pending_choice()
	if pc.is_empty() or index < 0 or index >= pc["options"].size():
		return {}
	var opt: Dictionary = pc["options"][index]
	var id: String = opt["unit"]
	var shards := int(opt["shards"])
	var is_new := not owns(id)
	if is_new:
		data["units"][id] = {"level": 1, "tier": 0, "shards": shards}
		quest_event("new_unit")
	else:
		data["units"][id]["shards"] = int(data["units"][id]["shards"]) + shards
	data["pending_choice"] = {}
	return {"unit": id, "shards": shards, "new": is_new}


func _weighted_pick(weights: Dictionary, rng: RandomNumberGenerator) -> String:
	var total := 0.0
	for id in weights:
		total += float(weights[id])
	var roll := rng.randf() * total
	for id in weights:
		roll -= float(weights[id])
		if roll < 0.0:
			return id
	return weights.keys()[weights.size() - 1]


## Probability that a unit is among the offered choices in a region.
func drop_chance(region_id: String, unit_id: String) -> float:
	var drops: Dictionary = GameData.region_drops(region_id)
	if not drops.has(unit_id):
		return 0.0
	return 1.0 - _miss_chance(drops, unit_id, mini(GameData.FINDS_PER_EXPEDITION, drops.size()))


## Chance that `unit_id` is NOT drawn in `draws` weighted draws without replacement.
func _miss_chance(weights: Dictionary, unit_id: String, draws: int) -> float:
	if draws <= 0:
		return 1.0
	var total := 0.0
	for id in weights:
		total += float(weights[id])
	var p := 0.0
	for id in weights:
		if id == unit_id:
			continue
		var rest := weights.duplicate()
		rest.erase(id)
		p += float(weights[id]) / total * _miss_chance(rest, unit_id, draws - 1)
	return p


# --- army -------------------------------------------------------------------

## Army entries in battle-ready form, with current levels and tiers.
func army_squads() -> Array:
	var out: Array = []
	for sq in data["army"]:
		var u := unit(sq["unit"])
		if u.is_empty():
			continue
		var entry := {"unit": sq["unit"], "level": int(u["level"]), "tier": int(u["tier"]), "row": sq["row"]}
		var ts: Array = u.get("trinkets", [])
		if not ts.is_empty():
			entry["trinkets"] = ts.duplicate()
		out.append(entry)
	return out


## Set the army, keeping only valid entries: owned units, no duplicates,
## known rows, at most MAX_SQUADS squads. (The server never trusts the client.)
func set_army(entries: Array) -> void:
	var army: Array = []
	var seen := {}
	for e in entries:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var id := str(e.get("unit", ""))
		var row := str(e.get("row", "front"))
		if not owns(id) or seen.has(id):
			continue
		if row not in GameData.ROWS:
			row = GameData.default_row_for(id)
		seen[id] = true
		army.append({"unit": id, "row": row})
		if army.size() >= GameData.MAX_SQUADS:
			break
	data["army"] = army


func army_code() -> String:
	return Army.encode(player_name(), rating(), battle_squads())


## The army as it actually deploys: squads of locked units stay out.
func battle_squads() -> Array:
	var out: Array = []
	for sq in army_squads():
		if not UnitLocks.is_locked(sq["unit"]):
			out.append(sq)
	if has_champion() and not out.is_empty():
		out.append(Champion.to_squad(Champion.battle_data(data["champion"], player_level())))
	return out


# --- trinkets ------------------------------------------------------------------

func owns_trinket(id: String) -> bool:
	return data.get("trinkets", {}).has(id)


func trinket_count() -> int:
	return data.get("trinkets", {}).size()


## Owned trinkets, rarest first, then by name.
func owned_trinkets() -> Array:
	var out: Array = data.get("trinkets", {}).keys()
	out.sort_custom(func(a, b):
		var ra := Trinkets.RARITY_ORDER.find(Trinkets.rarity_of(a))
		var rb := Trinkets.RARITY_ORDER.find(Trinkets.rarity_of(b))
		if ra != rb:
			return ra > rb
		return str(Trinkets.ALL[a]["name"]) < str(Trinkets.ALL[b]["name"]))
	return out


## The trinkets a unit holds (up to Trinkets.SLOTS).
func trinkets_of(unit_id: String) -> Array:
	return unit(unit_id).get("trinkets", [])


## The unit holding trinket `id`, or "".
func trinket_holder(id: String) -> String:
	for uid in data["units"]:
		if (data["units"][uid].get("trinkets", []) as Array).has(id):
			return uid
	return ""


## Put trinket `id` in a unit's slot (taking it off whoever held it).
func equip_trinket(unit_id: String, slot: int, id: String) -> bool:
	if not owns(unit_id) or not owns_trinket(id) or slot < 0 or slot >= trinket_slots():
		return false
	var holder := trinket_holder(id)
	if holder != "":
		(data["units"][holder]["trinkets"] as Array).erase(id)
	var ts: Array = data["units"][unit_id].get("trinkets", [])
	if slot < ts.size():
		ts[slot] = id
	else:
		ts.append(id)
	data["units"][unit_id]["trinkets"] = ts
	return true


func unequip_trinket(unit_id: String, slot: int) -> bool:
	var ts: Array = trinkets_of(unit_id)
	if slot < 0 or slot >= ts.size():
		return false
	ts.remove_at(slot)
	return true


func trinket_site_unlocked(site_id: String) -> bool:
	return Trinkets.SITES.has(site_id) and rating() >= int(Trinkets.SITES[site_id]["min_rating"]) and feature_unlocked("trinkets")


func can_hunt_trinkets(site_id: String) -> bool:
	return trinket_site_unlocked(site_id) and not has_pending_trinket() and maps() >= int(Trinkets.SITES[site_id]["cost_maps"])


func has_pending_trinket() -> bool:
	return not data.get("pending_trinket", {}).is_empty()


## The open trinket choice: {"site": id, "options": [trinket ids]}
func pending_trinket() -> Dictionary:
	return data.get("pending_trinket", {})


## Spend maps and roll three trinkets to choose one from.
func hunt_trinkets(site_id: String) -> Dictionary:
	if not can_hunt_trinkets(site_id):
		return {}
	if int(data["maps"]) >= max_maps():
		data["map_clock"] = int(Time.get_unix_time_from_system())
	data["maps"] = int(data["maps"]) - int(Trinkets.SITES[site_id]["cost_maps"])
	_on("trinket_hunt")
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	data["pending_trinket"] = {"site": site_id, "options": Trinkets.roll_hunt(site_id, data["trinkets"], rng)}
	return pending_trinket()


## Take option `index`: {"trinket": id, "new": bool, "gold": int}. A
## trinket already owned is turned into gold instead.
func choose_trinket(index: int) -> Dictionary:
	var pt := pending_trinket()
	if pt.is_empty() or index < 0 or index >= pt["options"].size():
		return {}
	var id: String = pt["options"][index]
	data["pending_trinket"] = {}
	if owns_trinket(id):
		var g: int = Trinkets.DUPLICATE_GOLD[Trinkets.rarity_of(id)]
		data["gold"] = gold() + g
		return {"trinket": id, "new": false, "gold": g}
	data["trinkets"][id] = true
	return {"trinket": id, "new": true, "gold": 0}


# --- challenges ------------------------------------------------------------------

func challenge_cleared(id: String) -> bool:
	return data.get("challenges", {}).has(id)


func challenges_cleared() -> int:
	return data.get("challenges", {}).size()


## Challenges open at 200 rating (0.9.9; anyone who already cleared one keeps
## them open).
const CHALLENGES_RATING := 200


func challenges_open() -> bool:
	return rating() >= CHALLENGES_RATING or challenges_cleared() > 0


## Challenges open one after another: the first, then each once the one
## before it is cleared.
func challenge_unlocked(id: String) -> bool:
	var i := Challenges.index_of(id)
	if i < 0 or not challenges_open():
		return false
	return i == 0 or challenge_cleared(Challenges.LIST[i - 1]["id"])


## Record a challenge battle. The reward is paid on the first win only:
## {won, first_clear, gold, maps, trinket, trinket_new, unit, unit_new, shards}.
func complete_challenge(id: String, won: bool) -> Dictionary:
	var out := {"challenge": id, "won": won, "first_clear": false, "gold": 0, "maps": 0,
		"trinket": "", "trinket_new": false, "unit": "", "unit_new": false, "shards": 0}
	if won and challenge_unlocked(id):
		_on("challenge_win")
	if not won or not challenge_unlocked(id) or challenge_cleared(id):
		return out
	add_xp(int(Progression.XP["challenge_first"]))
	var reward: Dictionary = Challenges.get_challenge(id)["reward"]
	data["challenges"][id] = true
	out["first_clear"] = true
	out["gold"] = int(reward.get("gold", 0))
	out["maps"] = int(reward.get("maps", 0))
	var t := str(reward.get("trinket", ""))
	if Trinkets.exists(t):
		out["trinket"] = t
		if owns_trinket(t):
			out["gold"] = int(out["gold"]) + int(Trinkets.DUPLICATE_GOLD[Trinkets.rarity_of(t)])
		else:
			data["trinkets"][t] = true
			out["trinket_new"] = true
	var u := str(reward.get("unit", ""))
	if GameData.UNITS.has(u):
		out["unit"] = u
		if owns(u):
			data["units"][u]["shards"] = int(data["units"][u]["shards"]) + Challenges.DUPLICATE_UNIT_SHARDS
			out["shards"] = Challenges.DUPLICATE_UNIT_SHARDS
		else:
			data["units"][u] = {"level": 1, "tier": 0, "shards": 0, "trinkets": []}
			out["unit_new"] = true
	data["gold"] = gold() + int(out["gold"])
	data["maps"] = int(data["maps"]) + int(out["maps"])
	return out


# --- battle results ---------------------------------------------------------

## mode: "ranked", "live" or "practice". score: 1 win, 0.5 draw, 0 loss.
## vs_ai: a ranked battle against a training band (moves rating less).
## Returns a summary dictionary for the result screen.
func apply_battle_result(mode: String, score: float, opp_rating: int, enemy_killed: int, vs_ai: bool = false) -> Dictionary:
	var summary := {"gold": 0, "maps": 0, "rating": 0}
	var g := 20 + enemy_killed / 5
	if mode == "ranked" or mode == "live":
		var rank_mult := Army.win_gold_mult(rating())   # your rating before this battle
		var delta := Army.ranked_delta(rating(), opp_rating, score, vs_ai and mode == "ranked")
		var before := rating()
		data["rating"] = maxi(0, rating() + delta)   # never below 0
		summary["rating"] = rating() - before
		if score >= 1.0:
			data["wins"] = int(data["wins"]) + 1
			g = roundi(float(g + 100 + maxi(0, (opp_rating - 900) / 4)) * rank_mult)
			summary["rank_mult"] = rank_mult
			summary["maps"] = 1
		elif score <= 0.0:
			data["losses"] = int(data["losses"]) + 1
			g += 30
		else:
			g += 60
	g = roundi(float(g) * gold_mult)
	data["gold"] = gold() + g
	data["maps"] = int(data["maps"]) + int(summary["maps"])
	summary["gold"] = g
	var level_before := player_level()
	_on("battle")
	quest_event("kills", maxi(0, enemy_killed))
	if (mode == "ranked" or mode == "live") and score >= 1.0:
		_on("ranked_win")
	summary["xp"] = int(Progression.XP["battle"]) + (int(Progression.XP["ranked_win"]) if (mode == "ranked" or mode == "live") and score >= 1.0 else 0)
	summary["level"] = player_level()
	summary["level_up"] = player_level() > level_before
	return summary


## Rewards for finishing a Legion Draft match. The amounts come from the
## match host / server (so the server admin controls them).
func add_draft_reward(gold_reward: int, maps_reward: int, place: int) -> Dictionary:
	gold_reward = maxi(0, gold_reward)
	maps_reward = clampi(maps_reward, 0, 5)
	data["gold"] = gold() + gold_reward
	data["maps"] = int(data["maps"]) + maps_reward
	data["draft_played"] = int(data.get("draft_played", 0)) + 1
	_on("draft_play")
	if place == 1:
		data["draft_wins"] = int(data.get("draft_wins", 0)) + 1
		_on("draft_win")
	return {"gold": gold_reward, "maps": maps_reward}



# --- commander level and quest log (0.9.7) ----------------------------------------------

func xp() -> int:
	return int(data.get("xp", 0))


func player_level() -> int:
	return Progression.level_for_xp(xp())


func feature_unlocked(key: String) -> bool:
	return player_level() >= Progression.unlock_level(key)


func max_maps() -> int:
	return MAX_MAPS + Progression.extra_maps(player_level())


func trinket_slots() -> int:
	return Progression.trinket_slots(player_level())


## Players from before 0.9.7 start with XP for what they've done, and at
## least level 8 (everything they could do before stays open). The levels
## they start at don't pay rewards.
func _start_commander_level(source: Dictionary) -> void:
	var units := (source.get("units", {}) as Dictionary).size() if typeof(source.get("units")) == TYPE_DICTIONARY else 0
	var played := int(source.get("wins", 0)) + int(source.get("losses", 0))
	var draft := int(source.get("draft_played", 0))
	var cleared := (source.get("challenges", {}) as Dictionary).size() if typeof(source.get("challenges")) == TYPE_DICTIONARY else 0
	var x := 30 * played + 80 * cleared + 40 * draft + 20 * maxi(0, units - GameData.STARTER_UNITS.size())
	if played + draft > 0 or units > GameData.STARTER_UNITS.size():
		x = maxi(x, Progression.xp_for_level(8))
	data["xp"] = mini(x, Progression.xp_for_level(Progression.MAX_LEVEL))
	data["level_rewarded"] = Progression.level_for_xp(int(data["xp"]))


## Add XP; pays the reward of every level reached. Returns the new levels.
func add_xp(amount: int) -> Array:
	if amount <= 0:
		return []
	data["xp"] = mini(xp() + amount, Progression.xp_for_level(Progression.MAX_LEVEL))
	var gained: Array = []
	while int(data.get("level_rewarded", 1)) < player_level():
		var lvl := int(data.get("level_rewarded", 1)) + 1
		data["level_rewarded"] = lvl
		_pay(Progression.level_reward(lvl))
		gained.append(lvl)
	if not gained.is_empty():
		refresh_quests()   # new quest slots may have opened
		_ensure_champion()
	return gained


## Gold, maps and a random trinket of a rarity (gold if you own them all).
func _pay(r: Dictionary) -> Dictionary:
	var out := {"gold": int(r.get("gold", 0)), "maps": int(r.get("maps", 0)), "trinket": ""}
	if r.has("trinket_rarity"):
		var rar := str(r["trinket_rarity"])
		var pool: Array = Trinkets.ids_by_rarity(rar).filter(func(t): return not owns_trinket(t))
		if pool.is_empty():
			out["gold"] = int(out["gold"]) + int(Trinkets.DUPLICATE_GOLD.get(rar, 100))
		else:
			var rng := RandomNumberGenerator.new()
			rng.randomize()
			var t: String = pool[rng.randi_range(0, pool.size() - 1)]
			data["trinkets"][t] = true
			out["trinket"] = t
	data["gold"] = gold() + int(out["gold"])
	data["maps"] = int(data["maps"]) + int(out["maps"])
	if int(r.get("sigils", 0)) > 0:
		data["sigils"] = int(data.get("sigils", 0)) + int(r["sigils"])
		out["sigils"] = int(r["sigils"])
	return out


## Something happened: quest progress plus its XP.
func _on(goal: String, amount: int = 1) -> void:
	quest_event(goal, amount)
	add_xp(int(Progression.XP.get(goal, 0)) * amount)


func quest_event(goal: String, amount: int = 1) -> void:
	if amount <= 0:
		return
	var q: Dictionary = data["quests"]
	for kind in ["daily", "weekly"]:
		for e in q[kind]["list"]:
			var d := Progression.quest_def(str(e["id"]))
			if not bool(e["claimed"]) and str(d.get("goal", "")) == goal:
				e["progress"] = mini(int(d["n"]), int(e["progress"]) + amount)
	var st := Progression.story(int(q["story"]["index"]))
	if not st.is_empty() and str(st["goal"]) == goal:
		q["story"]["progress"] = mini(int(st["n"]), int(q["story"]["progress"]) + amount)


func _sanitize_quests() -> void:
	var raw = data.get("quests", {})
	var q := {}
	for kind in ["daily", "weekly"]:
		var src = raw.get(kind, {}) if typeof(raw) == TYPE_DICTIONARY else {}
		var list: Array = []
		if typeof(src) == TYPE_DICTIONARY and typeof(src.get("list")) == TYPE_ARRAY:
			for e in src["list"]:
				if typeof(e) == TYPE_DICTIONARY and not Progression.quest_def(str(e.get("id", ""))).is_empty():
					list.append({"id": str(e["id"]), "progress": maxi(0, int(e.get("progress", 0))), "claimed": bool(e.get("claimed", false))})
		q[kind] = {"period": int(src.get("period", -1)) if typeof(src) == TYPE_DICTIONARY else -1, "list": list}
	var st = raw.get("story", {}) if typeof(raw) == TYPE_DICTIONARY else {}
	q["story"] = {"index": clampi(int(st.get("index", 0)) if typeof(st) == TYPE_DICTIONARY else 0, 0, Progression.STORY.size()),
		"progress": maxi(0, int(st.get("progress", 0)) if typeof(st) == TYPE_DICTIONARY else 0)}
	data["quests"] = q


## New daily and weekly quests when their period has turned over (or a new
## quest slot has opened). Returns true when anything changed.
func refresh_quests(now: int = -1) -> bool:
	if now < 0:
		now = int(Time.get_unix_time_from_system())
	var changed := false
	var lvl := player_level()
	for kind in ["daily", "weekly"]:
		var period := Progression.day_index(now) if kind == "daily" else Progression.week_index(now)
		var want := Progression.daily_count(lvl) if kind == "daily" else Progression.weekly_count(lvl)
		var slot: Dictionary = data["quests"][kind]
		if int(slot["period"]) != period:
			slot["period"] = period
			slot["list"] = []
			changed = true
		if (slot["list"] as Array).size() < want:
			var pool: Array = (Progression.DAILY if kind == "daily" else Progression.WEEKLY).filter(func(d):
				return lvl >= int(d.get("min_level", 1)) and (d["goal"] != "challenge_win" or challenges_open()) \
					and not (slot["list"] as Array).any(func(e): return e["id"] == d["id"]))
			var rng := RandomNumberGenerator.new()
			rng.randomize()
			while (slot["list"] as Array).size() < want and not pool.is_empty():
				var d: Dictionary = pool[rng.randi_range(0, pool.size() - 1)]
				pool.erase(d)
				slot["list"].append({"id": d["id"], "progress": 0, "claimed": false})
				changed = true
	return changed


## Progress toward a quest: counters as recorded, milestones from the profile.
func quest_progress(def: Dictionary, recorded: int) -> int:
	var n := int(def.get("n", 1))
	match str(def.get("goal", "")):
		"rating":
			return mini(n, rating())
		"units_owned":
			return mini(n, data["units"].size())
		"max_tier":
			var t := 0
			for u in data["units"]:
				t = maxi(t, int(data["units"][u]["tier"]))
			return mini(n, t)
		"challenges_cleared":
			return mini(n, challenges_cleared())
		"army_power":
			return mini(n, roundi(Army.army_power(battle_squads()) / 10.0))
		"player_level":
			return mini(n, player_level())
		"trinkets_owned":
			return mini(n, data["trinkets"].size())
	return mini(n, recorded)


## The quest log for the UI: [{kind, index, id, text, n, progress, done,
## claimed, reward (text), def}].
func quest_log() -> Array:
	var out: Array = []
	var q: Dictionary = data["quests"]
	var si := int(q["story"]["index"])
	var st := Progression.story(si)
	if not st.is_empty():
		var p := quest_progress(st, int(q["story"]["progress"]))
		out.append({"kind": "story", "index": si, "id": st["id"], "text": st["text"], "n": int(st["n"]), "progress": p,
			"done": p >= int(st["n"]), "claimed": false, "reward": Progression.reward_text(st), "def": st})
	for kind in ["daily", "weekly"]:
		var list: Array = q[kind]["list"]
		for i in list.size():
			var d := Progression.quest_def(str(list[i]["id"]))
			var p := quest_progress(d, int(list[i]["progress"]))
			out.append({"kind": kind, "index": i, "id": d["id"], "text": d["text"], "n": int(d["n"]), "progress": p,
				"done": p >= int(d["n"]), "claimed": bool(list[i]["claimed"]), "reward": Progression.reward_text(d), "def": d})
	return out


func can_claim_quest(kind: String, index: int) -> bool:
	for e in quest_log():
		if e["kind"] == kind and int(e["index"]) == index:
			return bool(e["done"]) and not bool(e["claimed"])
	return false


## Claim a finished quest: pays its reward and XP. Story quests move on to the
## next. Returns {gold, maps, trinket, xp, levels} ({} if it can't be claimed).
func claim_quest(kind: String, index: int) -> Dictionary:
	refresh_quests()
	if not can_claim_quest(kind, index):
		return {}
	var def: Dictionary
	if kind == "story":
		def = Progression.story(index)
		data["quests"]["story"] = {"index": index + 1, "progress": 0}
	else:
		var e: Dictionary = data["quests"][kind]["list"][index]
		def = Progression.quest_def(str(e["id"]))
		e["claimed"] = true
	var out := _pay(def)
	out["xp"] = int(def.get("xp", 0))
	out["levels"] = add_xp(int(def.get("xp", 0)))
	out["quest"] = def.get("text", "")
	return out


func claimable_quests() -> int:
	var n := 0
	for e in quest_log():
		if bool(e["done"]) and not bool(e["claimed"]):
			n += 1
	return n



# --- champion (0.9.9) -------------------------------------------------------------------

func has_champion() -> bool:
	return data.has("champion") and feature_unlocked("champion")


func champion() -> Dictionary:
	return data.get("champion", {})


func sigils() -> int:
	return int(data.get("sigils", 0))


## The champion arrives at its commander level with the starter kit and a few sigils.
func _ensure_champion() -> void:
	if feature_unlocked("champion") and not data.has("champion"):
		data["champion"] = Champion.new_champion(Champion.clean_name("%s's Champion" % str(data.get("name", "Commander")).left(10)))
		data["sigils"] = sigils() + Champion.START_SIGILS


## Buy a sigil with gold.
func buy_sigil() -> bool:
	if not has_champion() or gold() < Champion.SIGIL_GOLD:
		return false
	data["gold"] = gold() - Champion.SIGIL_GOLD
	data["sigils"] = sigils() + 1
	return true


## Spend a sigil at the Altar: a stat point, a piece of equipment, an
## appearance part or an ability, at random (Champion.ROLL_ODDS). Things you
## already own aren't rolled; when a kind has nothing left, it gives stat
## points instead. Returns {kind, id, part, stat, points, text} ({} if you can't).
func champion_roll(rng: RandomNumberGenerator = null) -> Dictionary:
	if not has_champion() or sigils() < 1:
		return {}
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	data["sigils"] = sigils() - 1
	var c: Dictionary = data["champion"]
	var kind := _weighted_pick(Champion.ROLL_ODDS, rng)
	var res := {"kind": kind}
	if kind == "ability":
		var pool: Array = Champion.ABILITIES.keys().filter(func(a): return not (c["abilities"] as Array).has(a))
		if pool.is_empty():
			kind = "stat"
			res["bonus"] = 3
		else:
			var a: String = pool[rng.randi_range(0, pool.size() - 1)]
			c["abilities"].append(a)
			res["id"] = a
			res["text"] = "New ability: %s" % Champion.ABILITIES[a]["name"]
	if kind == "look":
		var pool: Array = []
		for part in Champion.LOOKS:
			for v in Champion.LOOKS[part]:
				if not (c["looks"][part] as Array).has(v):
					pool.append([part, v])
		if pool.is_empty():
			kind = "stat"
			res["bonus"] = 2
		else:
			var pick: Array = pool[rng.randi_range(0, pool.size() - 1)]
			c["looks"][pick[0]].append(pick[1])
			res["part"] = pick[0]
			res["id"] = pick[1]
			res["text"] = "New look: %s %s" % [Champion.look_name(pick[0], pick[1]), Champion.LOOK_NAMES[pick[0]].to_lower()]
	if kind == "item":
		var rarity := _weighted_pick(Champion.ITEM_RARITY_ODDS, rng)
		var not_owned: Array = Champion.ITEMS.keys().filter(func(i): return not (c["items"] as Array).has(i))
		var pool: Array = not_owned.filter(func(i): return Champion.ITEMS[i]["rarity"] == rarity)
		if pool.is_empty():
			pool = not_owned
		if pool.is_empty():
			kind = "stat"
			res["bonus"] = 2
		else:
			var it: String = pool[rng.randi_range(0, pool.size() - 1)]
			c["items"].append(it)
			res["id"] = it
			res["text"] = "New %s %s: %s" % [Champion.ITEMS[it]["rarity"], Champion.SLOT_NAMES[Champion.ITEMS[it]["slot"]].to_lower(), Champion.ITEMS[it]["name"]]
	if kind == "stat":
		var points := int(res.get("bonus", 1))
		var gained := {}
		for _p in points:
			var open: Array = Champion.STAT_ORDER.filter(func(k): return int(c["stats"][k]) < Champion.MAX_STAT)
			if open.is_empty():
				data["gold"] = gold() + Champion.SIGIL_GOLD / 2   # everything maxed: half a sigil's price back
				break
			var k: String = open[rng.randi_range(0, open.size() - 1)]
			c["stats"][k] = int(c["stats"][k]) + 1
			gained[k] = int(gained.get(k, 0)) + 1
		res["kind"] = "stat"
		res["stats"] = gained
		var parts: Array = []
		for k in gained:
			parts.append("+%d %s" % [gained[k], Champion.STATS[k]["name"]])
		res["text"] = ", ".join(PackedStringArray(parts)) if not parts.is_empty() else "Your champion is already at its peak: %d gold instead." % (Champion.SIGIL_GOLD / 2)
	c["rolls"] = int(c.get("rolls", 0)) + 1
	c["last_roll"] = res
	quest_event("champion_roll")
	return res


func champion_equip(slot: String, id: String) -> bool:
	if not has_champion() or not slot in Champion.SLOTS:
		return false
	var c: Dictionary = data["champion"]
	if id == "":
		if slot == "weapon":
			return false   # a champion always holds a weapon
		c["equipped"].erase(slot)
		return true
	if not Champion.ITEMS.has(id) or Champion.ITEMS[id]["slot"] != slot or not (c["items"] as Array).has(id):
		return false
	c["equipped"][slot] = id
	return true


## Put an owned ability in slot 0-2 ("" empties it). An ability already in
## another slot moves here.
func champion_set_slot(slot: int, id: String) -> bool:
	if not has_champion() or slot < 0 or slot >= Champion.ABILITY_SLOTS:
		return false
	var slots: Array = data["champion"]["slots"]
	if id != "" and not (data["champion"]["abilities"] as Array).has(id):
		return false
	if id != "":
		var at := slots.find(id)
		if at >= 0:
			slots[at] = ""
	slots[slot] = id
	return true


func champion_set_look(part: String, v: String) -> bool:
	if not has_champion() or not Champion.LOOKS.has(part):
		return false
	if v == "" and part != "race":
		data["champion"]["look"][part] = ""
		return true
	if not (data["champion"]["looks"][part] as Array).has(v):
		return false
	data["champion"]["look"][part] = v
	return true


func champion_rename(n: String) -> bool:
	if not has_champion():
		return false
	data["champion"]["name"] = Champion.clean_name(n)
	return true


func champion_set_row(row: String) -> bool:
	if not has_champion() or not (row in GameData.ROWS or row == ""):
		return false
	data["champion"]["row"] = row
	return true
