class_name PatchNotes
extends RefCounted
## Balance changes and other notable changes, newest first (the Patch Notes tab).
## "version" matches the release version (Project Settings -> Application ->
## Config -> Version), which is also the "patch" the server's unit stats are
## kept under. Note kinds: "nerf", "buff", "change", "note".

const LIST := [
	{"version": "0.9.1", "date": "2026-11-22", "title": "Splash Down, Again",
		"summary": "Ranged splash takes a second nerf, and the server can now tune how hard ranked opponents and challenges are.",
		"sections": [
			{"name": "Balance", "notes": [
				{"kind": "nerf", "text": "Ranged splash damage again: projectiles now splash nearby enemies for 35% of the attack's damage, down from 45% in 0.9 (60% before that). The main target still takes full damage, and melee splash is unchanged at 60%."},
				{"kind": "note", "text": "Affects the same units as in 0.9: Orc Sorcerer, Lich, Elven Mage, Cyclops, Salamander Firebrand, Stone Giant, Fire Giant, Sphinx, Phoenix, the Golden, Ice, Shadow and Storm Dragons, and ranged units given splash by trinkets or Blast Powder."},
			]},
			{"name": "Difficulty", "notes": [
				{"kind": "change", "text": "The server can now adjust ranked training opponents (how strong Easy, Even and Hard are, and their rating) and the strength of challenge enemies. Any change applies to your game straight away, offline play included; challenge cards show the adjusted recommended power."},
			]},
			{"name": "Challenges", "notes": [
				{"kind": "change", "text": "Rise of the Phoenix's recommended power re-measured: 2200."},
			]},
		]},
	{"version": "0.9", "date": "2026-11-22", "title": "Splash Down",
		"summary": "The first balance patch: an across-the-board nerf to ranged splash damage, a fairer army Strength, harder ranked opponents and a slower climb up the ranks.",
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
				{"kind": "nerf", "text": "Ranked is harder. Training opponents are now 0.9x / 1.1x / 1.5x your Strength (Easy / Even / Hard), up from 0.9x / 1.05x / 1.3x. Against an ordinary army of your Strength, that's roughly a 55% / 21% / 5% chance to win: Hard opponents take a well-built army that counters them."},
				{"kind": "change", "text": "Training opponents are rated 40 below, 60 above and 150 above you. Beating a Hard opponent is worth clearly more rating than beating an Easy one, but no difficulty is a free climb. Saved player armies are searched right at your rating instead of slightly above."},
				{"kind": "nerf", "text": "Ranking up is slower. Rating changes by up to 24 per battle at 1200 and below, falling steadily to 12 at 3000 and above (it was 32 at every rating). An even win is now worth about +12 at the start and +6 near the top, instead of +16."},
			]},
			{"name": "Challenges", "notes": [
				{"kind": "change", "text": "Recommended power re-measured on the new Strength. Bosses with ranged splash got easier: Rise of the Phoenix is now 2250 and The Golden Wyrm 3800."},
			]},
		]},
]


static func latest() -> String:
	return str(LIST[0]["version"]) if not LIST.is_empty() else ""
