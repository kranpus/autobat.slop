# Hosting the Legion Draft server

> **On Hostinger** (or any Ubuntu VPS) with your own domain and HTTPS for the browser version:
> follow **[HOSTINGER.md](HOSTINGER.md)**. One script sets everything up.

The matchmaking server is this same Godot project running headless with `-- --server`.
A single server process:

- **Hosts many matches ("rooms") at once.** Players connect to it, so nobody has to forward
  ports.
- **Matchmaking:**
  - **Quick Match** joins an open room or opens one. These rooms start by themselves and fill
    empty seats with bots.
  - **Create Match** makes a public or private room with a 5-letter code to share.
  - **Browse** lists public rooms.
- **Runs the shops itself, so they're cheat-proof.** The server keeps every player's shop and
  board. Clients send only their actions, and the server replays them through the same rules
  code, so a modified game can't fake its army.
- **Decides every battle** on worker threads, then sends each player a replay of their fight.

- **Holds player accounts.** Each player's collection, army, gold and rating live on the
  server, and every change goes through the server's rules. Ranked battles are simulated and
  rewarded by the server. Passwords are stored only as salted PBKDF2-SHA256 hashes. See
  [Accounts and security](#accounts-and-security).

Ports:

| Port | Used by |
| --- | --- |
| **UDP 24702** | The downloadable game (ENet, encrypted with DTLS). |
| **UDP 24703** | A new player's game fetching the server's certificate once. |
| **TCP 24704** | The browser game (WebSocket). Encrypted (`wss://`) when you give the server a real certificate, see [WEB.md](WEB.md). |
| **TCP 24705** | The browser game's web page, served by the server itself if you've built it into `export/web/`. |

Browser and app players share accounts and meet in the same matches. No database or separate
web server is needed.

---

## 1. Try it on your own computer first

You need [Godot 4.3](https://godotengine.org/download/archive/4.3-stable/).

```bash
server/run_local.sh /path/to/godot          # starts the server on UDP 24702
```

Open the game, go to **Legion Draft → Online**, set **Server** to `localhost` and press
**Quick Match**. Open a second copy of the game and do the same; both join the same room,
which starts 30 seconds after the second player joins.

---

## Run it on your home Windows PC (players in the same house)

1. **Get the game files** onto the PC: on GitHub open the repository, switch to the branch with
   this code, then **Code → Download ZIP** and unzip it (or use `git clone`).
2. **Get Godot 4.3:** from <https://godotengine.org/download/archive/4.3-stable/> download
   *Windows 64-bit* and unzip it. Copy `Godot_v4.3-stable_win64_console.exe` into the game's
   `server` folder.
3. **Allow it through the firewall (once):** right-click `server\allow_firewall_windows.bat` and
   choose **Run as administrator**. Make sure your home network is set to **Private**
   (Settings → Network & internet → your Wi-Fi/Ethernet → Network profile type). If Windows
   later asks whether Godot may use the network, tick **Private networks** and allow it.
4. **Start the server:** double-click `server\start_server_windows.bat`. The first time, it
   imports the project (about a minute). It then shows this PC's address, for example
   `192.168.1.23`, and `Legion Draft server ... listening on UDP port 24702`. Keep the window open
   while people play; closing it stops the server.
5. **Play:**
   - **On the same PC:** open the game, go to **Legion Draft → Online**, keep Server set to
     `localhost`, and press **Quick Match**.
   - **On other computers in the house:** set Server to the address the start script showed,
     e.g. `192.168.1.23`.

   Players in the same Quick Match room are put together; empty seats get bots.

Tips:
- **After updating the game files,** just start the server again with
  `start_server_windows.bat`. It re-imports the project each time, which registers any new
  scripts and takes a few seconds after the first run.
- **Errors like `Identifier "ProfileLogic" not declared` or `Could not find type ...`** mean
  Godot's list of script classes is out of date (a server started without importing). Run
  `Godot_v4.3-stable_win64_console.exe --headless --path <game folder> --import` once, or use
  the start script. In the Godot editor, use **Project → Reload Current Project**.
- **If the PC's address changes** after a reboot, give it a fixed address in your router
  ("DHCP reservation").
- **Other computers need the game too.** Either open the same project in Godot and press F5, or
  export a Windows build (Project → Export; Godot will offer to download export templates).
- **Playing in a browser:** build the web version with `tools\build_web_windows.bat` (see
  [WEB.md](WEB.md)), then restart the server. Anyone in the house can open
  `http://<this PC's address>:24705` and play, online included.
- **Playing outside the house** later needs port forwards on your router to this PC: UDP 24702
  and 24703, plus TCP 24704 for browsers. Friends then connect to your public IP.
- **Back up player accounts** by copying the server's user data folder:
  `%APPDATA%\Godot\app_userdata\Autobat Legions` (the `accounts` folder, `ranked_armies.json`,
  `server_config.json` and `server_tls.*`).

## 2. Pick a host

Any Linux machine with a public IP that allows UDP works. A small VPS is the simplest:

| Provider | Plan that's enough to start | Rough price |
|---|---|---|
| Hetzner Cloud | CX22 (2 vCPU, 4 GB) | ~€4–5/month |
| DigitalOcean | Basic Droplet 2 GB | ~$12/month |
| Vultr / Linode | 2 GB shared CPU | ~$10–12/month |
| Oracle Cloud | Always Free Ampere A1 | free (ARM: see the note below) |

What uses CPU is battle simulation. Each round, every match simulates its battles (about 0.5–3
seconds of CPU each, in bursts roughly every 75 seconds). Two vCPUs comfortably handle a few
dozen matches at the same time. Memory use is small.

> Platforms that only route HTTP (Render, Railway, Heroku, Vercel…) won't work, because the
> game uses UDP. Fly.io supports UDP but needs extra setup; a plain VPS is easier.

> **ARM machines (Oracle Ampere, Raspberry Pi):** change the download in `server/Dockerfile` to
> `Godot_v4.3-stable_linux.arm64.zip` and the binary name to `Godot_v4.3-stable_linux.arm64`.

---

## 3. Set up the server (Ubuntu 24.04 VPS)

SSH into the new machine, then:

```bash
# Install Docker
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker $USER && newgrp docker

# Get the game code (or upload it with scp/rsync if the repo is private)
git clone https://github.com/kranpus/autobat.slop.git
cd autobat.slop

# Build and start the server; it restarts automatically after reboots/crashes
docker compose -f server/docker-compose.yml up -d --build

# Check it's running: you should see "listening on UDP port 24702"
docker logs -f legion-draft-server
```

### Open the firewall

```bash
sudo ufw allow 22/tcp        # keep SSH working
sudo ufw allow 24702:24703/udp
sudo ufw allow 24704/tcp     # browser players (WebSocket)
sudo ufw enable
```

Most providers also have a **cloud firewall** in their web dashboard (Hetzner "Firewalls",
DigitalOcean "Networking → Firewalls", Oracle "Security Lists"). Add an inbound rule there too:
**UDP, ports 24702-24703, from anywhere**, and **TCP 24704** for browser players.

---

## 4. Point players at it

1. **Optional:** give the server a name. At your domain registrar, add an **A record** such as
   `play.yourgame.com` → your VPS's IP address.
2. In `scripts/net/party.gd`, set
   ```gdscript
   const DEFAULT_SERVER := "play.yourgame.com"   # or the raw IP address (currently play.battleserver.tech)
   ```
   and export the game again. Players then just press **Quick Match**. Anyone can still type a
   different address in the Legion Draft tab (`host` or `host:port`).

### Check it from your computer

With Godot installed, from the project folder:

```bash
godot --headless -s res://tests/net_smoke_client.gd -- --server=play.yourgame.com --name=Test1 &
godot --headless -s res://tests/net_smoke_client.gd -- --server=play.yourgame.com --name=Test2
```

Each test player connects, plays a full Quick Match (bots fill the empty seats) and prints the
final standings. If they can't connect, check the firewall rules from step 3.

---

## 5. Updating

**Out-of-date games are told to update.**
- **The check:** when a game connects, it and the server (or LAN host) first compare versions,
  before anything else is sent. On a mismatch the game shows an **Update required** prompt with
  both version numbers.
- **The Update button:**
  - **Browser:** it reloads the page, which loads the new build.
  - **Downloadable game:** it opens the download page set with `update-url` on the server.
- **The other way round:** a game newer than the server is told the server needs updating.
- **The server log** records each game it turns away.


When you change the game rules or networking code, bump `GAME_VERSION` in
`scripts/net/party.gd`. The server rejects clients on a different version, because shop replay
only works when both sides run identical rules. Then:

```bash
cd autobat.slop
git pull
docker compose -f server/docker-compose.yml up -d --build
```

Matches in progress are lost when the server restarts, so update when it's quiet. Release the
new game build at the same time.

Also keep the **Godot version** the same on both sides: `GODOT_VERSION` in the Dockerfile
should match the version you export the game with.

---

## Without Docker (systemd)

```bash
sudo apt install -y unzip wget
wget https://github.com/godotengine/godot-builds/releases/download/4.3-stable/Godot_v4.3-stable_linux.x86_64.zip
unzip Godot_v4.3-stable_linux.x86_64.zip && sudo mv Godot_v4.3-stable_linux.x86_64 /usr/local/bin/godot
cd ~/autobat.slop && godot --headless --path . --import
sudo tee /etc/systemd/system/legion-draft.service >/dev/null <<EOF
[Unit]
Description=Legion Draft server
After=network-online.target

[Service]
User=$USER
WorkingDirectory=$HOME/autobat.slop
ExecStart=/usr/local/bin/godot --headless --path . -- --server --port=24702
Restart=always

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl enable --now legion-draft
journalctl -u legion-draft -f
```

---

## Admin commands (gold rewards, drop chances)

Type these into the server window (the console that `start_server_windows.bat` or
`run_local.sh` opens). For Docker, run `docker attach legion-draft-server` to type them; press
Ctrl+P then Ctrl+Q to detach again.

| Command | What it does |
|---|---|
| `help` | List all commands. |
| `status` | Players online, open rooms, current gold settings. |
| `rooms` | List rooms with their phase and player count. |
| `gold` | Show the gold settings. |
| `update-url https://yourname.itch.io/game` | Where out-of-date games download the new version. Their **Update required** prompt gets a **Download update** button that opens this link (browser players just reload). `update-url none` removes it. Can also be set with the `UPDATE_URL` environment variable. |
| `difficulty` | Show how hard fights are: each ranked training tier's power (relative to the power expected at the player's rating) and rating relative to the player, and the challenge multiplier. |
| `difficulty hard 1.5 150` | Set a ranked tier (`easy`, `even` or `hard`): its power relative to the player's army, and optionally its rating offset. Defaults: easy 0.9 −40, even 1.1 +60, hard 1.5 +150. |
| `difficulty ranked 1.2` | Scale the power of all three ranked tiers at once (1.2 = 20% stronger opponents). |
| `difficulty challenges 1.3` | Multiply challenge enemies' HP and damage (1 = as designed, 0.25–5). The recommended power on each card scales with it. |
| `difficulty training <slow from> <slower from> [divisor] [later divisor]` | When battles against training bands start counting for less rating: in full below the first rating, divided by the divisor from it (default a quarter from 1000), and by the later divisor from the second (default a tenth from 2500). E.g. `difficulty training 1500 3000`, or `difficulty training 1000 2500 4 10` for the defaults. `difficulty training` shows the current values. Players' games pick it up (their preview, offline play and the one-time message). |
| `quests` | When the quest log renews: daily quests at a time of day, weekly ones on a weekday at that time (UTC). |
| `quests reset 06:00 [monday]` | Set the daily reset time (UTC, HH:MM) and optionally the weekly reset day. Saved, and sent to players (offline play follows it too). Players get new quests from the next reset. |
| `difficulty reset` | Back to the default difficulty. |
| `drops` | Show the drop chance settings. |
| `drops unit legendary 0.25` | Scale how often units of a rarity are offered on expeditions, in every region. 1 = the normal table, 2 = twice as likely, 0 = never. Default (0.9.8): epic 0.6, legendary 0.3, everything else 1. A server whose saved settings still had the old defaults (epic 1, legendary 0.5, pity 15 / 60) moves to the new ones once; values you changed are kept. |
| `drops trinket epic 2` | Same for trinket hunts, at every site. Default: legendary 0.5. |
| `drops pity legendary 80` | Guarantee a rare / epic / legendary (or better) every N expeditions without one; 0 turns that guarantee off. Defaults: rare 5, epic 20, legendary 80 (15 / 60 before 0.9.8). |
| `drops reset` | Back to the default drop chances. |
| `gold battle 1.5` | Multiply the gold players earn at the end of every battle (1 = normal, 2 = double). |
| `gold draft 2` | Multiply the gold paid when a Legion Draft match ends. |
| `gold draft-table 500 300 200 100` | Base Legion Draft payout for 1st, 2nd, 3rd…; the last number applies to every lower place. |
| `gold reset` | Back to the defaults (x1, x1, 400/250/150/60). |
| `say Server restarting in 5 minutes` | Show a message to every connected player. |
| `ranked` | How many player armies are saved for ranked matchmaking, and their rating range. |
| `ranked clear` | Delete all saved ranked armies. |
| `ranked range 150` | Only match players against saved armies within this many rating points (default 200). Saved with the server settings. |
| `units` | List all 100 units and whether each is locked or open. |
| `lock Storm Dragon` / `lock goblin ogre` | Lock units by name or id. Locked units stop appearing in expeditions, draft shops and ranked opponents, are removed from army codes, and don't deploy in battles. Useful for emergency balance fixes. |
| `unlock storm_dragon` | Unlock units again. |
| `regions` | List all 17 expedition regions and whether each is locked (Badlands Camp is always open). |
| `lock region Bone Fields` / `unlock region marsh` | Lock or unlock expedition regions by name or id. Locked regions are hidden and can't be explored. |
| `unlock new` / `lock new` | Release (or re-lock) the unreleased content all at once: the 32 units **and** 7 regions locked by default. |
| `unlock all` | Unlock every unit and region. |
| `lock reset` | Back to the defaults: those 32 units and 7 regions locked, everything else open. |
| `unitstats` | Unit balance stats for the current patch: each unit's **use rate** (share of armies that include it) and **win rate** with W-L-D, in ranked and in Legion Draft side by side. Only units that have been used are listed. See below. |
| `unitstats draft win 20` | Options in any order: `ranked` / `draft` (sort by that mode only), `use` / `win` / `games` / `name` (sort key), `all` (also list unused units), a number (show only that many rows), a patch such as `0.9`. |
| `unitstats patches` | The patches that have stats, with how many armies each recorded. |
| `unitstats csv [patch]` | Save a spreadsheet (`unit_stats_<patch>.csv`) next to the server's settings. |
| `unitstats reset [patch]` | Delete a patch's stats (default: the current patch). |

Notes:
- **Drop chances** are saved with the other settings and sent to players like the unit locks.
  - **Online:** they reach signed-in players immediately, and the odds shown in the game update.
  - **Offline:** guests' games pick them up at the next background check-in.
- **Settings persist:** they're saved to `server_config.json` in the server's Godot user data
  folder and survive restarts.
- **Draft payouts** are calculated by the server and apply to matches still in progress.
- **The battle multiplier** is sent to players when they connect and whenever you change it.
  Their game remembers it, so it applies to all their battles.
- **Unlocking a unit also unlocks the expedition region(s) it drops in,** so it can actually be
  found. Those regions only ever offer unlocked units.
- **Players' games check in with the server by themselves,** at startup and every 5 minutes in
  the menus, to pick up locks and gold settings, so changes reach players even if they only
  play offline modes. The check-in is silent and isn't logged.
- **Unit locks** are saved with the gold settings and sent to players the same way. Legion Draft
  matches already running pick up a change at their next shop phase. Units already on a draft
  board stay for that match. Players who own a locked unit keep it, but it sits out of battles
  until it's unlocked.
- **Startup flags:** you can also set values when starting the server, e.g.
  `-- --server --battle-gold=1.5 --draft-gold=2`. These override the saved file for that run.

### Difficulty

`difficulty` settings are saved with the other server settings.
- **Who gets them:** they're sent to players like the drop chances: signed-in players at once,
  guests at their next check-in. Offline ranked and challenges follow them too.
- **Signed-in players:** the server generates their ranked opponents and runs their challenges,
  so changes apply to them straight away.
- **What they don't change:** saved armies of real players (matched by rating) and Legion Draft
  are unaffected.

### Balance simulator

`tools/balance_sim.gd` fights many battles with the real battle code and reports how each unit
does. It complements the live `unitstats`, which need players to play first.

- **On the Docker server:** run `server/balance.sh [options]` from the `autobat.slop` folder.
  - **CPU:** it runs inside the server container at low priority on half the CPU cores, so
    the live game keeps priority.
  - **Results:** the report is printed, and copied with CSV spreadsheets to `balance-results/`.
- **Anywhere with Godot 4.3:** run `godot --headless --path . -s res://tools/balance_sim.gd -- [options]`.

| Mode | What it measures |
|---|---|
| `--mode=armies` (default) | Random armies of **equal power** fight, each pairing from both sides. Each unit's win rate is how armies containing it did. Above 50% means it's stronger than its Strength says. |
| `--mode=duels` | Every unit against every other unit, one squad each at equal power: overall duel win rate, each unit's hardest counter, and a full matchup matrix (CSV). |
| `--mode=calibrate` | Armies of different power: how often the stronger army wins at each power ratio. 1.0× should be about 50%. It's useful when setting `difficulty`. |

Options:
- `--battles=N`: pairings to fight (default 400). Each is fought twice, from both sides.
- `--minutes=M`: stop after about M minutes instead.
- `--power=1500` or `--power=200-3000`: army power as shown in the game.
- `--rating=R`: unit pool by rarity, like ranked opponents. The default 3500 means every rarity.
- `--trinkets`: give armies trinkets, like ranked opponents.
- `--all-units`: include units the server has locked. By default it uses the server's unlocked
  units.
- `--units=goblin,elf_archer,...`: only these units.
- `--map=ID`: a single battlefield.
- `--threads=N`: how many battles to run at once.
- `--seed=N`: repeat a run exactly.

**Reading the results:** each win rate comes with a ±95% range. A unit only stands out if its
range clearly excludes 50%. About 2000 pairings narrow the ranges to roughly ±5%.

**Run time:** battles take about 0.3–1 s each per core, depending on army size.

### Unit stats

The server keeps balance statistics that only you can see. Players never receive them.

- **Ranked:** every server-run ranked battle counts the signed-in player's army. The opponent is
  a saved copy or a generated army, so it isn't counted again. Guests' offline battles aren't
  counted.
- **Legion Draft:** every battle on the server counts each human player's board. Bots' boards
  are left out, but a human's win or loss against a bot counts.
- **Counting:** a unit counts once per army, however many squads of it the army has.
  - **Use rate:** the armies that include it ÷ all armies recorded.
  - **Win rate:** how those armies did. Draws count as half a win.
  - **Small samples:** a `*` marks a rate from under 20 games.
- **Per patch:** stats are kept per release version (the patch number in the **Patch Notes** tab
  and on the sign-in screen). Every balance patch starts a fresh table, and older patches stay
  available for comparison, e.g. `unitstats 0.9`.
- **Storage:**
  - **File:** `unit_stats.json` in the server's user data folder (the `legion-data` Docker
    volume). It is saved every 10 seconds.
  - **Spreadsheet:** to copy one off a Docker server, run `server/admin.sh "unitstats csv"`,
    then
    `docker cp "legion-draft-server:/home/godot/.local/share/godot/app_userdata/Autobat Legions/unit_stats_0.9.csv" .`

## Accounts and security

When the game starts, players **sign in** or **create an account** on the server. They can also
choose **Play offline (guest)**, which keeps a separate local profile on that device and
works as before. While signed in:

- **The profile lives on the server.** Collection, army, gold, scouting maps and rating are
  stored in `accounts/<name>.json` in the server's user data folder. The game sends actions
  such as "level up the goblins", "explore the Warrens" or "recruit option 2". The server checks
  and applies them with the same rules code, then sends the profile back. Editing the game or
  its save file changes nothing.
- **Trinkets live on the server too:** hunts, picks and equipping are server actions, so
  trinkets can't be faked.
- **The leaderboard** (top 50 by rating) is built from the accounts on the server. It's sent to
  signed-in players on request and to guests with the background check-in.
- **Ranked battles run on the server.** Opponents come from the server; the player picks one;
  the server simulates the battle on a worker thread, pays the gold and rating, and sends the
  same seed so the player watches an identical replay.
- **Legion Draft rewards** are paid into the account by the server when a match ends.
- **Practice and live duels** still work but give no rewards while signed in, because their
  result can't be checked.
- **One device at a time:** signing in elsewhere signs the older session out. If the connection
  drops, the game reconnects by itself.

### Passwords

- **Never stored or logged.** The account file keeps only a random 16-byte salt and a
  **PBKDF2-HMAC-SHA256** hash with **600,000 iterations** (the OWASP recommendation). This is
  one-way hashing rather than reversible encryption: a stolen account folder can't be decrypted
  back into passwords, and each guess costs an attacker the full 600,000 rounds. Hashing takes
  about a second on a background thread, so the server keeps running. At most 8 run at once;
  further sign-ins are asked to retry.
- **Brute force:** after 5 wrong passwords an account refuses logins for 5 minutes. Unknown
  usernames take as long to check as real ones, so timing doesn't reveal which names exist.
- **"Keep me signed in"** stores a random 256-bit token on the player's device. The server keeps
  only its SHA-256 hash, issues a fresh token at every sign-in (each works once), keeps at most
  5 per account, and expires them after 30 days. Logging out revokes it. Changing the password
  revokes every token and signs out other devices.
- **Forgotten passwords:** there's no email, so the admin resets them from the console (below).

### Encryption

All traffic between the game and the server is encrypted with **DTLS** (TLS for UDP),
including passwords, tokens and game moves. On first start the server creates a self-signed
certificate (`server_tls.crt` + `server_tls.key` in its user data folder). **Keep the key
private and back it up with the accounts.**

Players' games trust the server's certificate like SSH trusts a host key:
- **First connection:** the game fetches the certificate from UDP port 24703 and saves it.
- **After that:** it only talks to a server presenting that exact certificate.
- **If the certificate changes** (for example, you reinstalled the server without restoring
  `server_tls.*`), players see a warning. They can accept the new certificate with **Settings →
  Trust new server certificate**.

**Strongest option:** copy `server_tls.crt` into the project root as `server_cert.crt` before
exporting the game. Exported games then trust only that certificate from the very first
connection, so there is no first-use step to intercept, and the certificate service isn't
needed.

Godot prints a few `mbedtls` / `TLS handshake` lines to the log when players disconnect or a
connection is dropped mid-handshake. They are harmless.

### Account commands

| Command | What it does |
| --- | --- |
| `accounts` | Number of accounts and who is signed in right now. |
| `accounts reset-password <user>` | Sets a new temporary password, prints it once in the console, and signs that player out everywhere. Give it to them; they change it in **Settings → Account**. |

### Player commands

Look at and change one signed-in player's account (guests keep their progress on their own
device, so these don't reach them). Changes are saved straight away and, if the player is
online, sent to their game at once. Unit, trinket and challenge names can be ids
(`storm_dragon`) or names as shown in the game (`Storm Dragon`).

| Command | What it does |
|---|---|
| `player <user>` | Their rating (and leaderboard place), wins, losses, gold, maps, Legion Draft record, every unit they own with level and tier, their army, and how many trinkets and challenges they have. |
| `player <user> set <stat> <n>` | Set `rating`, `gold`, `maps`, `wins`, `losses`, `draft_wins` or `draft_played`, e.g. `player bob set rating 1200`. Never below 0. |
| `player <user> add <stat> <n>` | Add to one (a minus number takes away), e.g. `player bob add gold 500`. |
| `player <user> set xp <n>` / `add xp <n>` | Commander XP. Levels reached this way pay their usual rewards. |
| `player <user> set commander_level <n>` | Jump to the start of a commander level (1-30). The levels skipped pay no rewards. |
| `player <user> set sigils <n>` / `add sigils <n>` | Champion Altar sigils (0.9.9). The player summary also shows their champion: weapon class, abilities, stats and how many items and abilities they've found. |
| `player <user> name <new name>` | Change their commander name (shown on the leaderboard and to opponents). |
| `player <user> unit <unit> [level <n>] [tier <n>] [shards <n>]` | Give them a unit, or change one they own, e.g. `player bob unit Storm Dragon level 20 tier 4`. Levels are capped by the tier, like in the game. Works for locked units too (they sit out of battles until unlocked). |
| `player <user> unit <unit> remove` | Take a unit away (and out of their army). |
| `player <user> units all [level <n>] [tier <n>]` | Give them every open unit. |
| `player <user> units max` | Give them every unit in the game (all 100), fully upgraded: tier 10 and each unit's top level. Units the server has locked sit out of battles until unlocked. |
| `player <user> trinket <trinket> [remove]` | Give (or take away) a trinket. |
| `player <user> trinkets all` / `none` | Every trinket, or take them all away. |
| `player <user> challenge <id>\|all [remove]` | Mark one challenge (or all) as cleared, which also opens the ones after it; `remove` un-clears it. |
| `player <user> reset confirm` | Start their progress over (their account, password and commander name stay). Without `confirm` it only explains. |

Back up the server's user data folder (`accounts/`, `ranked_armies.json`, `server_config.json`,
`server_tls.*`) regularly. With Docker it's the `legion-data` volume:
`docker run --rm -v server_legion-data:/d -v "$PWD":/b debian tar czf /b/legion-backup.tgz -C /d .`

## Ranked matchmaking

When a player presses **Find Opponents** in the Battle tab, their game:
1. sends their current army and rating to the server, which saves it as that player's latest
   army (one per player, under an anonymous ID);
2. receives up to 3 armies saved by *other* players at a similar rating. The search starts
   within ±50 rating and widens until it finds enough, but never beyond the **ranked range**
   (±200 by default, `ranked range <n>` to change). It aims for one closest match, one slightly
   below and one slightly above.

Empty slots, or all three if the server can't be reached, are filled with generated training
opponents, sized by the player's rating (not their army) and worth a quarter of the rating (a
tenth from 2500) of a saved player army. Saved armies are kept for 30 days in `ranked_armies.json`, in the server's Godot user
data folder.

For signed-in players the server uses the army and rating from their account, simulates the
battle itself and pays the rewards, so nothing can be faked. Guests still send their army from
their own device. The server clamps levels and tiers to legal values and strips locked units,
but a guest's ranked results only count on that guest's own device.

## Operating notes

- **Logs:** each join, room start, room finish and disconnect is printed with a timestamp.
  View them with `docker logs legion-draft-server` (or `journalctl` for systemd).
- **Limits** (set in `scripts/net/party.gd`):
  - `MAX_SERVER_PEERS` = 1000 connected players
  - `MAX_ROOMS` = 400 rooms
  - `REQUESTS_PER_SECOND` = 30 per player (extra requests are dropped)
- **Disconnects:** a player who drops out mid-match is replaced by a bot so the match finishes.
  Empty rooms close straight away; finished rooms close after 2 minutes.
- **Not included yet:** a leaderboard, email password recovery or a web dashboard.
- **Security:** see [Accounts and security](#accounts-and-security).
  - LAN games hosted from inside the game (no server) are not encrypted and don't use accounts.
  - Browser connections are encrypted only with a real certificate (`wss://`, see
    [WEB.md](WEB.md)). Plain `ws://` is meant for home networks, and the sign-in screen warns
    about it.
- **`status`** also shows how many players are connected from the app and from browsers.
