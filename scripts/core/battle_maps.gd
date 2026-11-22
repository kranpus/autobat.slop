class_name BattleMaps
extends RefCounted
## The 20 battlefields. Each map has a size, a floor tile and a list of
## circular obstacles that block ground units (flying units pass over them).
##
## Obstacles are written as [kind, x, y, radius], with x/y as fractions of
## the map size and radius in pixels. Every obstacle left of centre is
## mirrored onto the right half automatically, so both sides are always fair.

const DEFAULT_MAP := "open_arena"

## kind -> how it is drawn. "fill" textures are tiled inside the circle,
## "sprite" kinds draw one image, "grove" fills and scatters trees.
const OBSTACLE_KINDS := {
	"water":   {"name": "Deep water",  "style": "fill",   "texture": "water",   "color": "2a4f8a"},
	"swamp":   {"name": "Toxic bog",   "style": "fill",   "texture": "swamp",   "color": "2f7a2a"},
	"lava":    {"name": "Lava",        "style": "fill",   "texture": "lava",    "color": "c0401a"},
	"rock":    {"name": "Rock",        "style": "fill",   "texture": "rock",    "color": "7a5236"},
	"wall":    {"name": "Wall",        "style": "fill",   "texture": "wall",    "color": "8a5a2a"},
	"crystal": {"name": "Crystal",     "style": "fill",   "texture": "crystal", "color": "3a7ad8"},
	"grove":   {"name": "Trees",       "style": "grove",  "texture": "grove",   "color": "2d5a24"},
	"pillar":  {"name": "Pillar",      "style": "sprite", "texture": "column",  "color": "b0b0b0"},
	"statue":  {"name": "Statue",      "style": "sprite", "texture": "statue",  "color": "c0c0c0"},
}

const MAPS := {
	"open_arena": {
		"name": "Open Arena", "tile": "arena", "size": [2400, 1400],
		"desc": "No cover, no tricks. Pure army strength.",
		"obstacles": [],
	},
	"goblin_warrens": {
		"name": "Goblin Warrens", "tile": "warrens", "size": [2400, 1400],
		"desc": "Boulders split the charge into ragged lanes.",
		"obstacles": [["rock", 0.5, 0.5, 90], ["rock", 0.43, 0.2, 60], ["rock", 0.43, 0.8, 60], ["rock", 0.47, 0.35, 35]],
	},
	"haunted_crypt": {
		"name": "Haunted Crypt", "tile": "crypt", "size": [2200, 1400],
		"desc": "Rows of pillars and a sealed tomb at the heart.",
		"obstacles": [["pillar", 0.45, 0.2, 22], ["pillar", 0.45, 0.4, 22], ["pillar", 0.45, 0.6, 22], ["pillar", 0.45, 0.8, 22], ["wall", 0.5, 0.5, 70]],
	},
	"whispering_forest": {
		"name": "Whispering Forest", "tile": "forest", "size": [2600, 1500],
		"desc": "Dense groves funnel infantry. Flyers soar over the canopy.",
		"obstacles": [["grove", 0.5, 0.28, 150], ["grove", 0.5, 0.74, 130], ["grove", 0.41, 0.5, 70]],
	},
	"dwarven_deeps": {
		"name": "Dwarven Deeps", "tile": "deep", "size": [2400, 1400],
		"desc": "A collapsed hall wall with a single wide breach.",
		"obstacles": [["wall", 0.5, 0.08, 70], ["wall", 0.5, 0.2, 70], ["wall", 0.5, 0.32, 70], ["wall", 0.5, 0.68, 70], ["wall", 0.5, 0.8, 70], ["wall", 0.5, 0.92, 70], ["rock", 0.42, 0.5, 40]],
	},
	"dragon_peaks": {
		"name": "Dragon Peaks", "tile": "peaks", "size": [2600, 1600],
		"desc": "Volcanic vents scar the plateau.",
		"obstacles": [["lava", 0.5, 0.5, 170], ["lava", 0.44, 0.14, 90], ["lava", 0.44, 0.86, 90]],
	},
	"twin_fords": {
		"name": "Twin Fords", "tile": "dirt", "size": [2400, 1400],
		"desc": "A river crossed only at two narrow fords.",
		"obstacles": [
			["water", 0.5, 0.04, 62], ["water", 0.5, 0.12, 62], ["water", 0.5, 0.2, 62],
			["water", 0.5, 0.4, 62], ["water", 0.5, 0.5, 62], ["water", 0.5, 0.6, 62],
			["water", 0.5, 0.8, 62], ["water", 0.5, 0.88, 62], ["water", 0.5, 0.96, 62],
		],
	},
	"frozen_lake": {
		"name": "Frozen Lake", "tile": "frozen", "size": [2400, 1400],
		"desc": "The ice gave way in the middle. Fight around the shore.",
		"obstacles": [["water", 0.5, 0.5, 230], ["rock", 0.42, 0.15, 40], ["rock", 0.42, 0.85, 40]],
	},
	"sunken_swamp": {
		"name": "Sunken Swamp", "tile": "swamp", "size": [2400, 1400],
		"desc": "Bubbling bog pools break up formations.",
		"obstacles": [["swamp", 0.5, 0.3, 110], ["swamp", 0.5, 0.72, 120], ["swamp", 0.43, 0.52, 60], ["swamp", 0.4, 0.12, 45]],
	},
	"desert_dunes": {
		"name": "Desert Dunes", "tile": "sand", "size": [2800, 1400],
		"desc": "A long open approach dotted with sandstone outcrops.",
		"obstacles": [["rock", 0.5, 0.5, 50], ["rock", 0.45, 0.3, 40], ["rock", 0.45, 0.7, 40], ["rock", 0.4, 0.5, 30], ["rock", 0.48, 0.12, 35], ["rock", 0.48, 0.88, 35]],
	},
	"mossy_ruins": {
		"name": "Mossy Ruins", "tile": "moss", "size": [2400, 1400],
		"desc": "Broken walls and toppled columns of a forgotten keep.",
		"obstacles": [["pillar", 0.46, 0.25, 22], ["pillar", 0.46, 0.75, 22], ["wall", 0.5, 0.38, 55], ["wall", 0.5, 0.62, 55], ["pillar", 0.41, 0.5, 22]],
	},
	"mudflats": {
		"name": "Mudflats", "tile": "mud", "size": [2400, 1500],
		"desc": "Three deep sinkholes along the centre line.",
		"obstacles": [["swamp", 0.5, 0.15, 90], ["swamp", 0.5, 0.5, 90], ["swamp", 0.5, 0.85, 90], ["swamp", 0.44, 0.33, 40], ["swamp", 0.44, 0.67, 40]],
	},
	"glacier_pass": {
		"name": "Glacier Pass", "tile": "ice", "size": [2400, 1400],
		"desc": "Towering ice crystals squeeze both armies into one pass.",
		"obstacles": [["crystal", 0.5, 0.08, 260], ["crystal", 0.5, 0.92, 260], ["crystal", 0.42, 0.1, 120], ["crystal", 0.42, 0.9, 120]],
	},
	"marble_court": {
		"name": "Marble Court", "tile": "marble", "size": [2400, 1400],
		"desc": "A ring of columns around a hero's statue.",
		"obstacles": [["pillar", 0.375, 0.5, 26], ["pillar", 0.412, 0.349, 26], ["pillar", 0.412, 0.651, 26], ["pillar", 0.5, 0.286, 26], ["pillar", 0.5, 0.714, 26], ["statue", 0.5, 0.5, 30]],
	},
	"crystal_caverns": {
		"name": "Crystal Caverns", "tile": "crystal_floor", "size": [2400, 1400],
		"desc": "Glittering clusters jut from the cavern floor.",
		"obstacles": [["crystal", 0.5, 0.5, 80], ["crystal", 0.45, 0.22, 55], ["crystal", 0.45, 0.78, 55], ["crystal", 0.4, 0.4, 30], ["crystal", 0.4, 0.6, 30]],
	},
	"the_hive": {
		"name": "The Hive", "tile": "hive", "size": [2400, 1400],
		"desc": "A honeycomb of wax walls. Expect a brawl in the cells.",
		"obstacles": [["wall", 0.44, 0.29, 42], ["wall", 0.44, 0.5, 42], ["wall", 0.44, 0.71, 42], ["wall", 0.5, 0.18, 42], ["wall", 0.5, 0.39, 42], ["wall", 0.5, 0.61, 42], ["wall", 0.5, 0.82, 42]],
	},
	"tomb_of_kings": {
		"name": "Tomb of Kings", "tile": "tomb", "size": [2200, 1400],
		"desc": "Statues of dead kings watch over a great sarcophagus.",
		"obstacles": [["wall", 0.5, 0.5, 120], ["statue", 0.43, 0.3, 24], ["statue", 0.43, 0.7, 24], ["statue", 0.47, 0.12, 24], ["statue", 0.47, 0.88, 24]],
	},
	"blood_plains": {
		"name": "Blood Plains", "tile": "rough_red", "size": [3000, 1400],
		"desc": "A vast open killing field. Fast units shine here.",
		"obstacles": [["rock", 0.5, 0.5, 45]],
	},
	"infernal_gate": {
		"name": "Infernal Gate", "tile": "infernal", "size": [2400, 1400],
		"desc": "Lava pools guard a burning obelisk.",
		"obstacles": [["lava", 0.5, 0.2, 80], ["lava", 0.5, 0.8, 80], ["lava", 0.46, 0.33, 50], ["lava", 0.46, 0.67, 50], ["pillar", 0.5, 0.5, 40]],
	},
	"serpent_bog": {
		"name": "Serpent Bog", "tile": "bog", "size": [2400, 1500],
		"desc": "Winding channels of poisoned water.",
		"obstacles": [["swamp", 0.44, 0.22, 70], ["swamp", 0.5, 0.5, 75], ["swamp", 0.46, 0.78, 60], ["swamp", 0.4, 0.62, 40]],
	},
	# --- challenge-only battlefields (Challenges tab; never picked at random) ---
	"narrow_bridge": {
		"name": "The Narrow Bridge", "tile": "dirt", "size": [2400, 1400], "challenge": true,
		"desc": "A river cuts the field in two. The only way across is the old stone bridge.",
		"obstacles": [["water", 0.5, 0.04, 95], ["water", 0.5, 0.16, 95], ["water", 0.5, 0.28, 95],
			["water", 0.5, 0.72, 95], ["water", 0.5, 0.84, 95], ["water", 0.5, 0.96, 95]],
	},
	"fortress_gate": {
		"name": "Fortress Gate", "tile": "marble", "size": [2600, 1400], "challenge": true,
		"desc": "The defenders hold a walled line with a single gate. Archers fire from behind the walls.",
		# Overlapping wall sections (no gaps a unit could squeeze into), with
		# one gate in the middle.
		"obstacles": [["wall", 0.6, 0.04, 80], ["wall", 0.6, 0.14, 80], ["wall", 0.6, 0.24, 80], ["wall", 0.6, 0.34, 80],
			["wall", 0.6, 0.66, 80], ["wall", 0.6, 0.76, 80], ["wall", 0.6, 0.86, 80], ["wall", 0.6, 0.96, 80]],
	},
	"dragon_lair": {
		"name": "The Dragon's Lair", "tile": "infernal", "size": [2600, 1500], "challenge": true,
		"desc": "Lava rivers ring the wyrm's hoard. Only the bold cross the burning ground.",
		"obstacles": [["lava", 0.4, 0.15, 90], ["lava", 0.4, 0.85, 90], ["lava", 0.6, 0.15, 90], ["lava", 0.6, 0.85, 90],
			["lava", 0.5, 0.5, 70], ["statue", 0.75, 0.3, 30], ["statue", 0.75, 0.7, 30]],
	},
}


## Battlefields for normal play (random picks, the map picker). Challenge-
## only maps are left out; challenges name theirs directly.
static func map_ids() -> Array:
	return MAPS.keys().filter(func(id): return not bool(MAPS[id].get("challenge", false)))


static func random_map_id(rng: RandomNumberGenerator) -> String:
	var ids := map_ids()
	return ids[rng.randi_range(0, ids.size() - 1)]


static func get_map(id: String) -> Dictionary:
	return MAPS.get(id, MAPS[DEFAULT_MAP])


static func map_size(id: String) -> Vector2:
	var s: Array = get_map(id)["size"]
	return Vector2(float(s[0]), float(s[1]))


## Obstacles in pixel coordinates with mirroring applied: [[kind, x, y, r], ...]
static func obstacles(id: String) -> Array:
	var size := map_size(id)
	var out: Array = []
	for o in get_map(id)["obstacles"]:
		var fx: float = o[1]
		var fy: float = o[2]
		out.append([o[0], fx * size.x, fy * size.y, float(o[3])])
		if fx < 0.499:
			out.append([o[0], (1.0 - fx) * size.x, fy * size.y, float(o[3])])
	return out


static func terrain_texture(name: String) -> Texture2D:
	return load("res://assets/sprites/terrain/%s.png" % name)
