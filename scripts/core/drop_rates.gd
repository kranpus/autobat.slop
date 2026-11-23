class_name DropRates
extends RefCounted
## Drop chance settings, set by the server admin (`drops` console command)
## and sent to every player like the unit locks, so expeditions, trinket hunts
## and the odds shown in the game all follow the server.
##
## - Unit multipliers scale every region's drop weight for units of a rarity
##   (0 = that rarity never drops; its guarantee then can't trigger either).
## - Trinket multipliers scale every hunting site's weight for a rarity.
## - Pity: "rarity X or better guaranteed every N expeditions" (0 = off).

const RARITIES := ["common", "uncommon", "rare", "epic", "legendary"]
## 0.9.8: epics and legendaries are rarer (epic 1.0 -> 0.6, legendary 0.5 -> 0.3,
## guaranteed every 20 / 80 expeditions instead of 15 / 60).
const DEFAULT_UNIT := {"common": 1.0, "uncommon": 1.0, "rare": 1.0, "epic": 0.6, "legendary": 0.3}
const DEFAULT_TRINKET := {"common": 1.0, "uncommon": 1.0, "rare": 1.0, "epic": 1.0, "legendary": 0.5}
const DEFAULT_PITY := {"rare": 5, "epic": 20, "legendary": 80}
## The defaults before 0.9.8: settings saved with exactly these move to the new
## defaults once (anything the admin changed is kept).
const OLD_UNIT := {"epic": 1.0, "legendary": 0.5}
const OLD_PITY := {"epic": 15, "legendary": 60}
const VERSION := 2
const PITY_RARITIES := ["rare", "epic", "legendary"]
const MAX_MULT := 100.0
const MAX_PITY := 1000

static var unit_mult: Dictionary = DEFAULT_UNIT.duplicate()
static var trinket_mult: Dictionary = DEFAULT_TRINKET.duplicate()
static var pity: Dictionary = DEFAULT_PITY.duplicate()


static func reset() -> void:
	unit_mult = DEFAULT_UNIT.duplicate()
	trinket_mult = DEFAULT_TRINKET.duplicate()
	pity = DEFAULT_PITY.duplicate()


static func to_dict() -> Dictionary:
	return {"version": VERSION, "unit": unit_mult.duplicate(), "trinket": trinket_mult.duplicate(), "pity": pity.duplicate()}


## Load settings from untrusted input (a save file or the server); anything
## missing or invalid falls back to the default.
static func apply(d) -> void:
	reset()
	if typeof(d) != TYPE_DICTIONARY:
		return
	for r in RARITIES:
		if typeof(d.get("unit")) == TYPE_DICTIONARY and d["unit"].has(r):
			unit_mult[r] = clampf(float(d["unit"][r]), 0.0, MAX_MULT)
		if typeof(d.get("trinket")) == TYPE_DICTIONARY and d["trinket"].has(r):
			trinket_mult[r] = clampf(float(d["trinket"][r]), 0.0, MAX_MULT)
	for r in PITY_RARITIES:
		if typeof(d.get("pity")) == TYPE_DICTIONARY and d["pity"].has(r):
			pity[r] = clampi(int(d["pity"][r]), 0, MAX_PITY)
	if int(d.get("version", 1)) < 2:
		for r in OLD_UNIT:
			if is_equal_approx(float(unit_mult[r]), float(OLD_UNIT[r])):
				unit_mult[r] = DEFAULT_UNIT[r]
		for r in OLD_PITY:
			if int(pity[r]) == int(OLD_PITY[r]):
				pity[r] = DEFAULT_PITY[r]


## Drop weight of a unit in a region after the server's multiplier.
static func unit_weight(unit_id: String, base_weight: float) -> float:
	return base_weight * float(unit_mult.get(str(GameData.UNITS[unit_id]["rarity"]), 1.0))


static func trinket_weight(rarity: String, base_weight: float) -> float:
	return base_weight * float(trinket_mult.get(rarity, 1.0))


## Active guarantees, rarest last: [{"rarity", "every"}].
static func pity_rules() -> Array:
	var out: Array = []
	for r in PITY_RARITIES:
		if int(pity.get(r, 0)) > 0:
			out.append({"rarity": r, "every": int(pity[r])})
	return out


## One line for the server console / admin.
static func describe() -> String:
	var u: Array = []
	var t: Array = []
	for r in RARITIES:
		u.append("%s x%s" % [r, _num(unit_mult[r])])
		t.append("%s x%s" % [r, _num(trinket_mult[r])])
	var p: Array = []
	for r in PITY_RARITIES:
		p.append("%s every %d" % [r, int(pity[r])] if int(pity[r]) > 0 else "%s off" % r)
	return "Unit drops: %s. Trinket drops: %s. Guarantees: %s." % [", ".join(PackedStringArray(u)), ", ".join(PackedStringArray(t)), ", ".join(PackedStringArray(p))]


static func _num(v: float) -> String:
	return str(snappedf(v, 0.001))
