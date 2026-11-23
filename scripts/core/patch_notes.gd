class_name PatchNotes
extends RefCounted
## Balance changes and other notable changes, newest first (the Patch Notes tab).
## "version" matches the release version (Project Settings -> Application ->
## Config -> Version), which is also the "patch" the server's unit stats are
## kept under. Note kinds: "nerf", "buff", "change", "note".

const LIST := [
	{"version": "0.9.4", "date": "2026-11-23", "title": "Beasts of the Four Realms",
		"summary": "40 new units, every one with a battle ability of its own, from four new regions; regions listed in the order you unlock them; and a new soundtrack with a sound for every ability.",
		"sections": [
			{"name": "40 new units", "notes": [
				{"kind": "change", "text": "100 units now. The 40 new ones are open to everyone from the start, and every one of them has a battle ability, commons included: no two new commons share one."},
				{"kind": "change", "text": "Fungal Hollows (rating 600): Cave Spiders that poison, Sporelings whose healing cleanses, Oozes that split in two when they die, Giant Snails that hide in their shells, Trapdoor Spiders that root, pouncing Wolf Spiders, armour-eating Deathcaps, the thorny Acid Blob, the Spider Matriarch who hatches spiders and the Vine Stalker who steps out of the undergrowth beside its prey."},
				{"kind": "change", "text": "Tidewater Grotto (1400): Snapping Turtles that block blows, Merfolk Javelineers that throw two at once, dodging Giant Newts, Mermaids whose song quickens allies, Aquamancers that sweep foes back, Electric Eels, frenzied Sharks, the taunting Guardian Serpent, the Kraken that drags its prey in, and the Merfolk Avatar's tidal waves."},
				{"kind": "change", "text": "Abyssal Rift (2000): exploding Imps, Lemures whose deaths enrage their allies, Hell Hounds that hunt in packs, withering Quasits, the Rakshasa that reflects arrows and spells, the berserk Hairy Devil, the Hellion's hellfire from the sky, the Balrug's burning aura, the Executioner and the Pit Fiend, whose blows send whole ranks fleeing."},
				{"kind": "change", "text": "Frostfell Wastes (2800): fire-proof Yaks, howling Wargs that rally the pack, Ice Beasts, the frost-armoured Ice Devil, the Blizzard Demon, the Polar Bear, the Ice Fiend that freezes foes solid, the Crystal Golem that hardens as the battle drags on, the Spectral Dragon that fades out of reach and the Rime Lindwurm's avalanches."},
				{"kind": "note", "text": "Each new unit's ability is on its card in the Collection, and each has its own Legion Draft ability too."},
				{"kind": "note", "text": "Their Strength was tuned over thousands of simulated battles, so an army with new units is matched as fairly as one without."},
			]},
			{"name": "Regions", "notes": [
				{"kind": "change", "text": "Expeditions, trinket hunts and the Collection list regions in the order you unlock them, from the starting camps to the Celestial Spire."},
			]},
			{"name": "Music", "notes": [
				{"kind": "change", "text": "Three new lobby tracks join the Town Theme: The Old Tower Inn, The Bard's Tale and Market Day. The lobby now plays them as a playlist, one after another and never the same twice in a row, instead of looping one tune."},
			]},
			{"name": "Battle sounds", "notes": [
				{"kind": "change", "text": "Battles open to a roll of war drums instead of the harsh horn."},
				{"kind": "change", "text": "Every ability has its own sound: crackling chain lightning, ice for chill, flames for burn and Molten Core, shattering glass for Shatter, a dark rasp for Wither, a ringing clang for stuns, rumbling stone for Quake, a thud for charges and knockback, holy chimes for resurrection and rebirth, ghostly breath for Raise Dead, Dread and Soul Harvest, and a soft bell for Divine Aegis."},
				{"kind": "note", "text": "Ability sounds are spaced out, so huge battles stay pleasant to listen to."},
			]},
		]},
	{"version": "0.9.3", "date": "2026-11-23", "title": "Welcome, Commander",
		"summary": "A guided tutorial for new players, a fantasy look for the whole game and a round of interface improvements. No balance changes.",
		"sections": [
			{"name": "Tutorial", "notes": [
				{"kind": "change", "text": "New players are guided through the basics by doing them: a first battle, levelling up, recruiting on an expedition, building the army, a ranked fight and a challenge. A spotlight shows the one thing to press next, with a few words; nothing to read through."},
				{"kind": "change", "text": "Short tips the first time you open trinket hunts, Legion Draft and the leaderboard."},
				{"kind": "note", "text": "Skip it at any time, or replay it from Settings → Tutorial."},
			]},
			{"name": "Look and feel", "notes": [
				{"kind": "change", "text": "A fantasy look throughout: dark wood panels with gold trim, a stone backdrop, headings and tabs lettered in Cinzel, parchment tooltips and a sword for a mouse pointer."},
				{"kind": "change", "text": "Finding ranked opponents unrolls a scroll, a Call to Arms, with each opponent written in ink and a red wax-seal Attack button."},
				{"kind": "change", "text": "Patch notes are decrees on scrolls, and the tutorial guide speaks on parchment."},
				{"kind": "change", "text": "Challenges are quest notices on parchment, with wax-seal Fight buttons; cleared ones are stamped."},
				{"kind": "change", "text": "The leaderboard is a Hall of Heroes scroll, with gold, silver and bronze for the top three."},
				{"kind": "change", "text": "Expeditions and trinket hunts come back as a Scout's (or Hunter's) Report: the finds spin in framed portraits on parchment, and you recruit with a wax seal."},
			]},
			{"name": "Interface", "notes": [
				{"kind": "change", "text": "Red dots on tabs with something waiting: a squad upgrade you can afford, scouting maps piling up or a recruit to choose, a challenge your army can take, unread patch notes."},
				{"kind": "change", "text": "Short messages confirm what you did (level ups, squad upgrades, army built, codes copied), and incoming gold floats up from the gold counter."},
				{"kind": "change", "text": "Battle tab: a big Find Opponents button. Friend challenges and live duels fold away under Play with friends."},
				{"kind": "change", "text": "Army tab: your unused units wait on a Reserves bench; tap one to add it, or drag it into a column. Copy army code replaces the long code field."},
				{"kind": "change", "text": "Collection: how many units you've found, an Owned only switch, and a ★ on units in your army."},
				{"kind": "change", "text": "Phones: holding the browser version upright shows a prompt to turn the phone sideways instead of a tiny screen."},
			]},
		]},
	{"version": "0.9.2", "date": "2026-11-22", "title": "Abilities",
		"summary": "Splash is now rare, melee splash is nerfed, and 23 units have battle abilities of their own, including every epic and legendary.",
		"sections": [
			{"name": "Splash", "notes": [
				{"kind": "nerf", "text": "Melee splash: blows now splash nearby enemies for 45% of the damage, down from 60%. Ranged splash stays at 35%."},
				{"kind": "change", "text": "Only six units splash now: Orc Sorcerer, Hill Giant, Cyclops, Fire Giant, Golden Dragon and Grand Avatar. Every other former splasher has a battle ability instead (shown on its card in the Collection)."},
			]},
			{"name": "New abilities", "notes": [
				{"kind": "change", "text": "Stun: the Ogre Brute's club knocks its target senseless for 0.6s: it can't move or attack."},
				{"kind": "change", "text": "Chill: Ice Dragon's breath halves the target's speed, moving and attacking, for 3s."},
				{"kind": "change", "text": "Burn: Salamander Firebrand sets its target ablaze for 150% of the hit again over 4s."},
				{"kind": "change", "text": "Chain Lightning: Elven Mage (2 jumps) and Storm Dragon (5). Each attack jumps to more enemies nearby, 30% weaker each jump."},
				{"kind": "change", "text": "Shatter: Frost Giant's hits make the target take 30% more damage from everyone for 4s."},
				{"kind": "change", "text": "Wither: the Sphinx's spells make the target deal 35% less damage for 4s."},
				{"kind": "change", "text": "Charge: the Minotaur's first blow against each new target deals triple damage."},
				{"kind": "change", "text": "Double Strike: the Ettin's two clubs hit two enemies at once."},
				{"kind": "change", "text": "Rebirth: the Phoenix rises again at full health the first time it dies."},
				{"kind": "change", "text": "Unstoppable: the Juggernaut can't be stunned or chilled and takes 35% less damage from arrows, stones and spells."},
				{"kind": "change", "text": "Devour: the Shadow Dragon heals itself for 75% of the damage it deals."},
				{"kind": "change", "text": "Raise Dead: enemies the Lich kills rise as skeletons on its side, up to 8 per Lich."},
			]},
			{"name": "Epic and legendary", "notes": [
				{"kind": "change", "text": "Every epic and legendary now has an ability of its own. New: Quake (Hill Giant: every third blow stuns everything around the target), Predator (Griffon: double damage to ranged units, casters and healers), Knockback (Stone Giant), Molten Core (Fire Giant: erupts when it dies), Many Heads (Hydra: attacks faster as it's wounded), Soul Harvest (Bone Dragon: kills heal it and add damage), Dread (Golden Dragon: enemies nearby deal 35% less damage), Rising Storm (Storm Titan: each blow hits harder), Resurrection (Seraph: brings a fallen ally back every 4s) and Divine Aegis (Grand Avatar: allies nearby take 20% less damage)."},
				{"kind": "change", "text": "The Storm Titan's chain lightning, the Bone Dragon's rebirth and the Stone Giant's stun from earlier 0.9.2 builds became Rising Storm, Soul Harvest and Knockback, so no two epics or legendaries share an ability."},
				{"kind": "nerf", "text": "Epic and legendary squads grow more slowly: squad upgrades cost 1.75x (epic) and 2x (legendary) the shards."},
				{"kind": "change", "text": "Epic and legendary units counted for too much in army Strength (at equal Strength, armies with them won only 30-40% of the time). Their Strength is lowered to match how they actually fight (rarity multipliers: epic 1.3 -> 0.95, legendary 1.8 -> 1.1), so ranked opponents and challenge ratings are fairer. Healing also counted for too much and now counts for less."},
				{"kind": "buff", "text": "The weakest picks got stronger: Phoenix (2400 health, up from 1750), Griffon (1000 health, up from 730; Predator +150%), Hydra (60 damage, up from 50; +40% attack speed per head), Bone Dragon (1300 health, up from 1100), Stone Giant (1500 health, up from 1300; 110 damage, up from 80) and Seraph (2400 health, up from 2000)."},
			]},
			{"name": "Strength and challenges", "notes": [
				{"kind": "change", "text": "Abilities count toward army Strength, tuned with thousands of simulated battles so armies of equal Strength stay close fights."},
				{"kind": "change", "text": "Challenge bosses use their new abilities too: Vorlath raises the dead, Ashwing is reborn, the Colossus's storm builds with every blow, Aurathrax fills enemies with dread. Recommended power re-measured."},
			]},
		]},
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
