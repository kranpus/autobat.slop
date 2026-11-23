class_name Difficulty
extends RefCounted
## Fight difficulty, set by the server admin ('difficulty' console command)
## and sent to every player like the drop chances, so offline play follows
## the server too.
##
## - Ranked training opponents: for Easy / Even / Hard, their power relative
##   to the power expected at your rating (Army.rank_power) and their rating
##   relative to yours (see Army.GHOST_TIERS for
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
## Rating from battles against training bands: in full below slow_from, then
## divided by div (a quarter by default), and by div_late from slower_from.
## Defaults in Army (AI_RATING_*); the server's 'difficulty training' sets them.
static var train_slow_from: int = Army.AI_RATING_FULL_UNTIL
static var train_slower_from: int = Army.AI_RATING_FROM
static var train_div: float = Army.AI_RATING_DIV_LOW
static var train_div_late: float = Army.AI_RATING_DIV_HIGH
const MAX_TRAIN_RATING := 20000
const MAX_TRAIN_DIV := 100.0


static func reset() -> void:
	tiers = Army.GHOST_TIERS.duplicate(true)
	challenge_mult = 1.0
	set_training(Army.AI_RATING_FULL_UNTIL, Army.AI_RATING_FROM, Army.AI_RATING_DIV_LOW, Army.AI_RATING_DIV_HIGH)


static func set_training(slow_from: int, slower_from: int, div: float = -1.0, div_late: float = -1.0) -> void:
	train_slow_from = clampi(slow_from, 0, MAX_TRAIN_RATING)
	train_slower_from = clampi(slower_from, train_slow_from, MAX_TRAIN_RATING)
	if div > 0.0:
		train_div = clampf(div, 1.0, MAX_TRAIN_DIV)
	if div_late > 0.0:
		train_div_late = clampf(div_late, 1.0, MAX_TRAIN_DIV)


static func to_dict() -> Dictionary:
	var d := {"challenges": challenge_mult, "training": [train_slow_from, train_slower_from, train_div, train_div_late]}
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
	var t = d.get("training")
	if typeof(t) == TYPE_ARRAY and t.size() == 4:
		set_training(int(t[0]), int(t[1]), float(t[2]), float(t[3]))


static func set_tier(i: int, power: float, rating_offset: int) -> void:
	tiers[i] = [clampf(power, MIN_POWER, MAX_POWER), clampi(rating_offset, -MAX_RATING_OFFSET, MAX_RATING_OFFSET), TIER_NAMES[i]]


static func tier_index(name: String) -> int:
	for i in TIER_NAMES.size():
		if TIER_NAMES[i].to_lower() == name.to_lower():
			return i
	return -1


static func is_default() -> bool:
	return JSON.stringify(to_dict()) == JSON.stringify({"challenges": 1.0, "training": [Army.AI_RATING_FULL_UNTIL, Army.AI_RATING_FROM, Army.AI_RATING_DIV_LOW, Army.AI_RATING_DIV_HIGH],
		"easy": [float(Army.GHOST_TIERS[0][0]), int(Army.GHOST_TIERS[0][1])],
		"even": [float(Army.GHOST_TIERS[1][0]), int(Army.GHOST_TIERS[1][1])], "hard": [float(Army.GHOST_TIERS[2][0]), int(Army.GHOST_TIERS[2][1])]})


static func describe() -> String:
	var parts: Array = []
	for t in tiers:
		parts.append("%s %sx power, rating %+d" % [t[2], _num(float(t[0])), int(t[1])])
	return "Ranked training opponents: %s. Rating from them: in full below %d, 1/%s from %d, 1/%s from %d. Challenges: enemies x%s HP and damage.%s" % [
		"; ".join(PackedStringArray(parts)), train_slow_from, _num(train_div), train_slow_from, _num(train_div_late), train_slower_from,
		_num(challenge_mult), " (defaults)" if is_default() else ""]


## "a quarter", "a tenth"... of the rating, for a divisor.
static func share_text(div: float) -> String:
	var names := {2: "half", 3: "a third", 4: "a quarter", 5: "a fifth", 10: "a tenth"}
	if is_equal_approx(div, roundf(div)) and names.has(int(roundf(div))):
		return names[int(roundf(div))]
	return "1/%s" % _num(div)


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
