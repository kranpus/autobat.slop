# Autobat Legions

An auto-battler PvP game for **Godot 4.3+**. You hunt down specific units, level them up,
grow their squad sizes, and send armies of **1000+ units** against other players'
armies in fully automatic battles across **20 battlefields**.

All art, sound and music are **CC0 open-source assets** (see [CREDITS.md](CREDITS.md)).

| Battle (Twin Fords) | Legion Draft shop |
|---|---|
| ![Battle](docs/screenshots/battle.png) | ![Legion Draft](docs/screenshots/legion_draft.png) |
| **Collection** | **Battlefields** |
| ![Collection](docs/screenshots/collection.png) | ![Maps](docs/screenshots/maps.png) |

## Running it

1. Install [Godot 4.3 or newer](https://godotengine.org/download) (standard build; C# not needed).
2. Open Godot → **Import** → pick this folder's `project.godot`.
3. Press **F5** (Play).

The first time it opens, the editor imports the assets, which takes a few seconds.

**Phones and tablets:** the game also runs on Android and iOS, with scaled-up text and buttons,
touch controls and pinch-to-zoom. See **[MOBILE.md](MOBILE.md)** for how to build it.

## The gameplay loop

1. **Find units: Expeditions tab.** Spend *Scouting Maps* to search a region. Your scouts come
   back with **3 different units** from that region, each shown with its description, role,
   stats and strengths, and you **recruit one**. A new unit joins your collection; one you
   already own gives **shards** for that unit. Each region has its own drop table, so to hunt a
   specific unit you pick where to look (e.g. Golden Dragons only appear in Dragon Peaks); the
   region card shows each unit's chance to be offered. The choice is saved, so closing the game
   doesn't reroll it. Maps refill (1 per 10 minutes, max 10) and ranked wins award more.
   **Guaranteed pulls:** if 4 expeditions in a row offered nothing Rare or better, the 5th
   is guaranteed to include one. Epic or better is guaranteed every 15 expeditions, and
   Legendary every 40 (counting only regions that have legendaries). The tab shows the
   countdowns, and the guaranteed unit is marked on its card.
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
   full size, so a maxed army of commons and uncommons is about 1,100 units per side.
   - **Columns:** the tab has three columns, **Back line | Middle | Front line**, laid out like
     the battlefield, with the front line on the right facing the enemy.
   - **Moving squads:** drag a squad to another column (or use ◀ ▶); ▲ ▼ set the order within
     a column.
5. **Fight: Battle tab.**
   - **Ranked Arena:** **Find Opponents** saves your army on the server with your current rating
     and matches you against armies that **other players saved at a similar rating**: one close
     match, one slightly lower and one slightly higher. Win rating (Elo), gold and maps. Empty
     slots, or all three when offline, are filled with generated training opponents.
   - **Friend Challenge:** paste a friend's *army code* (Army tab → Copy) to fight their exact army.
   - **Live Duel:** one player hosts, the other joins by IP (LAN, or the internet with a forwarded
     UDP port, default 24680). Ranked.
   - **Battlefield picker:** choose one of the 20 maps (or Random) for friend challenges and duels
     you host. Each ranked opponent card shows the map you'll fight on.

## Locked units

There are **60 units**. The original 20 are open. **40 more are locked** until you release them:
- **Commons:** Jackals, Hobgoblins, Cave Bats, Goblin Archers and more.
- **Uncommons:** Knights, Hippogriffs, War Hounds, Elven Mages and more.
- **Rares:** Trolls, Cyclopes, Minotaurs, Vampire Knights and more.
- **Epics:** Giants, the Sphinx, an Ice Dragon, a Hydra, a Bone Dragon and a Juggernaut.
- **Legendaries:** the Shadow Dragon, Storm Dragon, Seraph and Grand Avatar.

Locked units don't appear anywhere: not in expeditions, draft shops or ranked opponents, and not
in army codes. Locked units you own sit out of battles.

The new units come from **8 new expedition regions**, which are locked too:
- **Opening regions (1 map, no rating needed):** Badlands Camp, Sunken Marsh, Hive Tunnels.
- **Mid regions (2 maps, rating 1000–1100):** Elven Glade, Bone Fields, Giant's Steps.
- **Top regions (3 maps, rating 1150–1200):** Dragon's Hoard, Celestial Spire.

The original 5 regions keep their original 20 units. A locked region is hidden from the
Expeditions tab, and a region can only be explored once some of its units are unlocked.

The Legion Draft server controls the locks (`units`, `regions`, `lock`, `unlock`,
`lock region`, `unlock region`, and `unlock new` to release everything new; see HOSTING.md). Any
unit, old or new, can be locked as an emergency balance fix. Players' games pick up the server's
locks when they connect. The defaults live in `scripts/core/game_data.gd` (`"locked": true`).

## Legion Draft (multiplayer game mode)

A separate mode for a group of players, picked from the **Legion Draft** tab. It uses no
collection: everyone drafts an army from scratch each match.

- **Shop rounds:** each round you get 10 gold. Units and trinkets cost 3, rerolling costs 1, and
  frozen items stay in the shop for the next round.
- **Drag and drop:** drag shop units and trinkets onto your board. Drag a unit to another slot
  to move or swap it, onto a matching unit to merge, or onto **Sell**. Valid slots light up
  green while you drag. Clicking an item and then a slot also works.
- **Board:** 4, 6 or 8 slots, chosen when the match is created.
  - 4 slots: 2 front line, 2 back row.
  - 6 slots: 2 front, 2 middle, 2 back.
  - 8 slots: 3 front, 2 middle, 3 back.
- **Duplicates level up:** drop a copy onto the same unit, or merge two board units. Lv2 needs 3
  copies and Lv3 needs 6. Each level makes the squad bigger (common: 16 → 32 → 48 units) and
  stronger (+40% per level).
- **Out-of-battle abilities:** each of the 20 units has its own, triggered when bought, sold or
  levelled up, at the start or end of a turn, when given a trinket, when an ally is sold, or
  after a win or loss. Examples: Rats breed +2 units each turn, the Golden Dragon earns gold, and
  the Lich grows stronger whenever you sell an ally.
- **Trinkets:** 18 across 6 tiers. Held trinkets change how a squad fights: lifesteal, thorns,
  splash, flying, magic damage, faster attacks, +50% units, and more. Consumables give permanent
  boosts or an extra copy toward the next level.
- **Shop tier:** rises every 3 battles, from 1 to 6. Tier 2 unlocks uncommon units, 3 rare, 4 epic
  and 5 legendary, and each tier adds stronger trinkets and more shop slots.
- **Matches:** after each shop phase, players are paired against each other; an odd player out
  fights a copy of another player's army. Play until you hit the win target (default 10) or run
  out of lives (default 5). Final placings award gold and scouting maps in the main game; the
  amounts are set by the server (see the admin commands in HOSTING.md).
- **Rule toggles:** when creating a match you can switch off the **win target**, the **lives**
  and the **turn timer**.
  - Without lives, nobody is knocked out and the match ends after a **round limit**, ranked by
    wins, then fewest losses.
  - Without a timer, each shop phase waits until everyone presses End Turn.
- **Online play:** this uses the matchmaking server; see **[HOSTING.md](HOSTING.md)** for how
  to run your own. On a home Windows PC, run `server\start_server_windows.bat`.
  - **Quick Match** joins an open room. Rooms start on their own and fill empty seats with bots.
  - **Create Match** makes a public room or a private one with a 5-letter code.
  - **Browse** lists public rooms, and you can join any room by its code.

  Nobody needs to forward ports.
- **Local network play** needs no server:
  - **Quick Match (LAN)** joins a match on your network, or hosts one if none is found.
  - **Host Match** lets you set wins, lives, max players (2–16) and turn time, and add bots.
  - **Find Matches** lists matches on your network.
  - **Join by IP**.
- **Disconnects:** a player who drops mid-match is replaced by a bot.
- **Cheat-proof:** whoever runs the match (the server, or the LAN host) keeps every player's
  shop and board. Clients send only their actions (buy, sell, move…). The authority replays
  them through the same rules code and random numbers, so a modified client can't fake its
  army. The authority also decides every battle, on worker threads, and players watch a replay
  of their own fight.

Rules and content live in `scripts/draft/draft_data.gd`, the shop and ability logic (plus the bot
player) in `scripts/draft/draft_run.gd`, a match's authoritative logic in
`scripts/net/match_room.gd`, and networking in `scripts/net/party.gd`. The dedicated server
is this same project run headless: `godot --headless -- --server` (Docker setup in `server/`).

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
scripts/net/party.gd          Legion Draft networking: server, LAN host, client (autoload "Party")
scripts/net/match_room.gd     One authoritative Legion Draft match (used by server and LAN host)
server/                       Dockerfile, docker-compose and run script for the online server
scripts/draft/draft_data.gd   Draft rules, unit abilities, trinkets
scripts/draft/draft_run.gd    A player's draft run: shop, merging, abilities, bot AI
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
battle, determinism (same seed gives the same checksum), and opponent generation. They also check the Legion Draft rules (merging, levels, trinkets, abilities,
selling, shop tiers, board sanitizing) and run a 15-round, 4-bot draft tournament through
real battles. Finally, they play a full server-side match with a scripted player and
three bots, and check that the server's replay of that player's actions always rebuilds
exactly the board the player sees.

### Network and visual checks

```
# Start a local server, then connect test players to it (each plays a full Quick Match):
server/run_local.sh /path/to/godot
godot --headless -s res://tests/net_smoke_client.gd -- --server=127.0.0.1 --name=A
godot --headless -s res://tests/net_smoke_client.gd -- --server=127.0.0.1 --name=B

# LAN modes:  -- --lan-host   /   -- --lan-join=127.0.0.1   /   -- --lan-quick

# Screenshots of every main screen (needs a display, or xvfb-run on Linux):
godot --rendering-driver opengl3 --resolution 1280x720 -s res://tests/screenshots.gd -- --out=/tmp/shots
```

## Status

The project has been run in **Godot 4.3** and checked in four ways:
- **Tests:** the headless test suite passes.
- **Online:** a dedicated server was tested with up to 6 real network clients at once, across
  concurrent rooms.
- **Local network:** hosting, joining by IP and network discovery all work end to end.
- **Visuals:** every main screen was rendered and checked. A 2,000-unit battle simulates at
  about 8 ms per tick in GDScript (roughly 16% of one CPU core at 1x speed).
