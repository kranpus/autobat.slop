# Autobat Legions

An auto-battler PvP game for **Godot 4.3+**. You hunt down specific units, level them up,
grow their squad sizes, and send armies of **1000+ units** against other players'
armies in fully automatic battles across **20 battlefields**.

All art, sound and music are **CC0 open-source assets** (see [CREDITS.md](CREDITS.md)).

## Running it

1. Install [Godot 4.3 or newer](https://godotengine.org/download) (standard build; C# not needed).
2. Open Godot → **Import** → pick this folder's `project.godot`.
3. Press **F5** (Play).

The first time it opens, the editor imports the assets, which takes a few seconds.

## The gameplay loop

1. **Find units: Expeditions tab.** Spend *Scouting Maps* to search a region. Your scouts come
   back with **3 different units** from that region, each shown with its description, role,
   stats and strengths, and you **recruit one**. A new unit joins your collection; one you
   already own gives **shards** for that unit. Each region has its own drop table, so to hunt a
   specific unit you pick where to look (e.g. Golden Dragons only appear in Dragon Peaks); the
   region card shows each unit's chance to be offered. The choice is saved, so closing the game
   doesn't reroll it. Maps refill (1 per 10 minutes, max 10) and ranked wins award more.
2. **Level up: Collection tab.** Spend gold to raise a unit's level (+8% HP and damage per level).
3. **Increase quantity: Collection tab.** Spend shards and gold to raise the squad tier, which
   adds units to the squad. Each tier also raises the level cap by 4.

   | Rarity | Squad size at tier 0 → tier 10 |
   |---|---|
   | Common | 30 → 180 |
   | Uncommon | 15 → 95 |
   | Rare | 6 → 36 |
   | Epic | 2 → 12 |
   | Legendary | 1 → 11 |
4. **Build an army: Army tab.** Up to 8 squads. There is **no unit cap**: every squad fights at
   full size, so a maxed army of commons and uncommons is about 1,100 units per side. Put each
   squad in the front, middle or back row.
5. **Fight: Battle tab.**
   - **Ranked Arena:** choose one of three opponents (Easy / Even / Hard) matched to your army
     power, and win rating (Elo), gold and maps.
   - **Friend Challenge:** paste a friend's *army code* (Army tab → Copy) to fight their exact army.
   - **Live Duel:** one player hosts, the other joins by IP (LAN, or the internet with a forwarded
     UDP port, default 24680). Ranked.
   - **Battlefield picker:** choose one of the 20 maps (or Random) for friend challenges and duels
     you host. Each ranked opponent card shows the map you'll fight on.

### Battlefields

20 maps (`scripts/core/battle_maps.gd`), each with its own floor, size (2200–3000 px wide) and
terrain. The terrain is lakes, rivers with fords, lava, bogs, rocks, walls, crystals, tree groves,
pillars and statues. Obstacles block ground units, which steer around them; **flying units pass
over them**. Every map is mirrored left/right so neither side has an advantage.

| | | | |
|---|---|---|---|
| Open Arena | Goblin Warrens | Haunted Crypt | Whispering Forest |
| Dwarven Deeps | Dragon Peaks | Twin Fords | Frozen Lake |
| Sunken Swamp | Desert Dunes | Mossy Ruins | Mudflats |
| Glacier Pass | Marble Court | Crystal Caverns | The Hive |
| Tomb of Kings | Blood Plains | Infernal Gate | Serpent Bog |

To add a map, add an entry to `MAPS` with a floor tile and a list of `[kind, x, y, radius]`
obstacles (x/y as fractions of the map; anything left of centre is mirrored automatically).

### Combat

- 20 units in 5 rarities, each with a role (melee, ranged, caster, healer, tank).
- Damage types (physical / pierce / magic / fire) against armor classes (light / heavy / undead / beast)
  make for counters: arrows shred light infantry but bounce off heavy armor and skeletons, fire burns
  undead and treants, magic melts heavy armor.
- Splash damage (capped at 6 targets per hit), healers, regeneration, and flying units (melee hits
  them for only 60%).
- Battle controls: mouse wheel to zoom, drag to pan, 1x/2x/4x speed, skip to result.

## How the 1000+ unit battles work

- `scripts/battle/battle_sim.gd`: the simulation uses no physics or scene nodes. Unit state is
  stored in packed arrays (one array per stat), with a uniform spatial grid for target search,
  splash and separation. It runs at a fixed 20 ticks per second. Ground units walk around
  circular obstacles using a sticky detour direction (they follow a river until they find a
  ford, and turn back if they reach a dead end).
- `scripts/battle/battle_view.gd` draws all units with one `MultiMeshInstance2D` per unit type
  (about 20 draw calls for 2000 sprites), interpolating positions between ticks.
- **Deterministic:** the same armies plus the same seed always give the same battle. Live duels
  rely on this. Both players exchange army codes, the host picks a seed and map, each machine simulates
  the battle locally, and the two results are compared by checksum.

## PvP: what's real and what's next

What works now is **asynchronous PvP** (army codes) and **live 1v1** over ENet. Profiles are stored
locally (`user://profile.json`). Army codes are validated and clamped to legal values, but a
modified client could still claim units it doesn't own. A real ranked ladder needs a small server
that:

1. stores player profiles and expedition rolls (so progress can't be faked),
2. stores each player's defence army so ranked opponents are real people's armies (the "ghost"
   opponents are generated today), and
3. re-runs the deterministic `BattleSim` to confirm reported results.

`BattleSim` is a plain `RefCounted` with no scene dependencies, so it can run in a headless Godot
server as-is.

## Project layout

```
project.godot
scenes/main.tscn              Entry scene (UI is built in code)
scripts/core/game_data.gd     All units, rarities, regions, damage tables  ← tweak balance here
scripts/core/battle_maps.gd   The 20 battlefields and their obstacles
scripts/core/army.gd          Squad sizes, power, army codes, opponent generator, Elo
scripts/core/profile.gd       Save data, upgrades, expeditions, rewards (autoload "Profile")
scripts/core/audio.gd         Music + pooled/throttled SFX (autoload "Audio")
scripts/net/net.gd            ENet live duels (autoload "Net")
scripts/battle/battle_sim.gd  Deterministic simulation
scripts/battle/battle_view.gd MultiMesh renderer + camera
scripts/battle/battle_screen.gd  HUD, start and result screens
scripts/ui/*.gd               Menu tabs
tests/test_battle.gd          Headless tests
assets/                       CC0 sprites, sounds, music + licenses
```

### Adding a unit

1. Drop a 32×32 PNG into `assets/sprites/units/<id>.png`.
2. Add an entry to `UNITS` in `scripts/core/game_data.gd`.
3. Add it to one or more `REGIONS` drop tables so players can find it.

## Tests

```
godot --headless --import                       # once, registers class names
godot --headless -s res://tests/test_battle.gd
```

The tests check army-code round trips and cheat clamping, that squads deploy uncapped, that
every one of the 20 maps resolves a battle with no units stuck in terrain, a 1000+ vs 1000+
battle, determinism (same seed gives the same checksum), and opponent generation.

## Status

This is a first playable build. The scripts were written and syntax-checked without a Godot
binary available, and balance was tuned using a Python port of the battle sim. **The first run
in the Godot editor may show small errors to fix.** Open the Debugger panel if anything fails.
