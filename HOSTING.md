# Hosting the Legion Draft server

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

It speaks ENet over **UDP port 24702**. That's all it needs: no database and no web server.

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
- **If the PC's address changes** after a reboot, give it a fixed address in your router
  ("DHCP reservation").
- **Other computers need the game too.** Either open the same project in Godot and press F5, or
  export a Windows build (Project → Export; Godot will offer to download export templates).
- **Playing outside the house** later needs a port forward of UDP 24702 on your router to this
  PC, and friends connect to your public IP.

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
sudo ufw allow 24702/udp
sudo ufw enable
```

Most providers also have a **cloud firewall** in their web dashboard (Hetzner "Firewalls",
DigitalOcean "Networking → Firewalls", Oracle "Security Lists"). Add an inbound rule there too:
**UDP, port 24702, from anywhere**.

---

## 4. Point players at it

1. **Optional:** give the server a name. At your domain registrar, add an **A record** such as
   `play.yourgame.com` → your VPS's IP address.
2. In `scripts/net/party.gd`, set
   ```gdscript
   const DEFAULT_SERVER := "play.yourgame.com"   # or the raw IP address
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

## Operating notes

- **Logs:** each join, room start, room finish and disconnect is printed with a timestamp.
  View them with `docker logs legion-draft-server` (or `journalctl` for systemd).
- **Limits** (set in `scripts/net/party.gd`):
  - `MAX_SERVER_PEERS` = 1000 connected players
  - `MAX_ROOMS` = 400 rooms
  - `REQUESTS_PER_SECOND` = 30 per player (extra requests are dropped)
- **Disconnects:** a player who drops out mid-match is replaced by a bot so the match finishes.
  Empty rooms close straight away; finished rooms close after 2 minutes.
- **Not included yet:** accounts, persistent rankings, or a web dashboard. Profiles and rewards
  are still saved on each player's computer.
- **Security:** ENet traffic is not encrypted. That's fine for game moves, but don't send
  anything private over it.
