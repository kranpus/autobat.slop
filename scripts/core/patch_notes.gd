class_name PatchNotes
extends RefCounted
## Balance changes and other notable changes, newest first (the Patch Notes tab).
## "version" matches the release version (Project Settings -> Application ->
## Config -> Version), which is also the "patch" the server's unit stats are
## kept under. Note kinds: "nerf", "buff", "change", "note".

const LIST := [
	{"version": "0.9", "date": "2026-11-22", "title": "Splash Down",
		"summary": "The first balance patch: an across-the-board nerf to ranged splash damage, a fairer army Strength, even ranked opponents and a slower climb up the ranks.",
		"sections": [
			{"name": "Balance", "notes": [
				{"kind": "nerf", "text": "Ranged splash damage, across the board: splash from projectiles (stones, magic bolts and fireballs) now hits nearby enemies for 45% of the attack's damage, down from 60% (25% less). The main target still takes full damage."},
				{"kind": "nerf", "text": "This affects Orc Sorcerer, Lich, Elven Mage, Cyclops, Salamander Firebrand, Stone Giant, Fire Giant, Sphinx, Phoenix and the Golden, Ice, Shadow and Storm Dragons, plus any ranged unit given splash by a trinket (Lantern, Orb of Flame, Sunfire Orb...) or by Blast Powder in Legion Draft."},
				{"kind": "note", "text": "Melee splash (Ogre, Minotaur, Ettin, the giants' clubs, Bone Dragon, Juggernaut, Titan, Grand Avatar) is unchanged."},
			]},
			{"name": "Army Strength", "notes": [
				{"kind": "change", "text": "The size of melee and tank squads counts for less: twice the units is about 1.8x the Strength, because only the front of a crowd can reach the enemy. Ranged units, casters and healers still count every unit."},
				{"kind": "change", "text": "Splash adds less to the Strength of ranged units, to match the nerf."},
				{"kind": "change", "text": "Ranked opponents are matched using the new Strength, so big melee armies now meet stronger opponents than before."},
			]},
			{"name": "Ranked", "notes": [
				{"kind": "change", "text": "Opponents are an even fight on average. Training opponents are now about 0.85x / 0.95x / 1.05x your Strength (Easy / Even / Hard), each around 62% / 50% / 41% to win; before, they averaged 8% stronger than you (up to 1.3x for Hard). Saved player armies are searched right at your rating instead of slightly above."},
				{"kind": "change", "text": "Training opponents are rated 75 below, level with and 75 above you, to match their odds: beating an Easy opponent is worth less rating, beating a Hard one more, and none of them is a free climb."},
				{"kind": "nerf", "text": "Ranking up is slower. Rating changes by up to 24 per battle at 1200 and below, falling steadily to 12 at 3000 and above (it was 32 at every rating). An even win is now worth about +12 at the start and +6 near the top, instead of +16."},
			]},
			{"name": "Challenges", "notes": [
				{"kind": "change", "text": "Recommended power re-measured on the new Strength. Bosses with ranged splash got easier: Rise of the Phoenix is now 2250 and The Golden Wyrm 3800."},
			]},
		]},
]


static func latest() -> String:
	return str(LIST[0]["version"]) if not LIST.is_empty() else ""
