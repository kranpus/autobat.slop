class_name Difficulty
extends RefCounted
## Fight difficulty, set by the server admin ('difficulty' console command)
## and sent to every player like the drop chances, so offline play follows
## the server too.
##
## - Ranked training opponents: for Easy / Even / Hard, their power relative
##   to yours and their rating relative to yours (see Army.GHOST_TIERS for
##   the defaults and what they mean).
## - Challenges: enemy HP and damage multiplier (1 = as designed). The
##   recommended power shown on each card scales with it.

const TIER_NAMES := ["Easy", "Even", "Hard"]
const MIN_POWER := 0.3
const MAX_POWER := 5.0
const MAX_RATING_OFFSET := 1000
const MIN_CHALLENGE := 0.25
const MAX_CHALLENGE := 5.0

## [[power mult, rating offset, label], ...] in TIER_NAMES order.
static var tiers: Array = Army.GHOST_TIERS.duplicate(true)
static var challenge_mult := 1.0


static func reset() -> void:
	tiers = Army.GHOST_TIERS.duplicate(true)
	challenge_mult = 1.0


static func to_dict() -> Dictionary:
	var d := {"challenges": challenge_mult}
	for t in tiers:
		d[str(t[2]).to_lower()] = [float(t[0]), int(t[1])]
	return d


## Load settings from untrusted input (a save file or the server); anything
## missing or invalid falls back to the default.
static func apply(d) -> void:
	reset()
	if typeof(d) != TYPE_DICTIONARY:
		return
	for i in TIER_NAMES.size():
		var v = d.get(TIER_NAMES[i].to_lower())
		if typeof(v) == TYPE_ARRAY and v.size() == 2:
			set_tier(i, float(v[0]), int(v[1]))
	if d.has("challenges"):
		challenge_mult = clampf(float(d["challenges"]), MIN_CHALLENGE, MAX_CHALLENGE)


static func set_tier(i: int, power: float, rating_offset: int) -> void:
	tiers[i] = [clampf(power, MIN_POWER, MAX_POWER), clampi(rating_offset, -MAX_RATING_OFFSET, MAX_RATING_OFFSET), TIER_NAMES[i]]


static func tier_index(name: String) -> int:
	for i in TIER_NAMES.size():
		if TIER_NAMES[i].to_lower() == name.to_lower():
			return i
	return -1


static func is_default() -> bool:
	return JSON.stringify(to_dict()) == JSON.stringify({"challenges": 1.0, "easy": [float(Army.GHOST_TIERS[0][0]), int(Army.GHOST_TIERS[0][1])],
		"even": [float(Army.GHOST_TIERS[1][0]), int(Army.GHOST_TIERS[1][1])], "hard": [float(Army.GHOST_TIERS[2][0]), int(Army.GHOST_TIERS[2][1])]})


static func describe() -> String:
	var parts: Array = []
	for t in tiers:
		parts.append("%s %sx power, rating %+d" % [t[2], _num(float(t[0])), int(t[1])])
	return "Ranked training opponents: %s. Challenges: enemies x%s HP and damage.%s" % [
		"; ".join(PackedStringArray(parts)), _num(challenge_mult), " (defaults)" if is_default() else ""]


static func _num(v: float) -> String:
	return str(snappedf(v, 0.01))


## A challenge enemy squad with the server's challenge multiplier applied.
static func scale_challenge_squad(sq: Dictionary) -> Dictionary:
	if is_equal_approx(challenge_mult, 1.0):
		return sq
	var mods: Dictionary = sq.get("mods", {}).duplicate()
	mods["hp_mult"] = float(mods.get("hp_mult", 1.0)) * challenge_mult
	mods["dmg_mult"] = float(mods.get("dmg_mult", 1.0)) * challenge_mult
	sq["mods"] = mods
	return sq
