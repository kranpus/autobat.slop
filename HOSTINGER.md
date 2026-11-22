# Hosting on Hostinger

This puts the game online on a **Hostinger VPS** with your own domain:

- **The game server** for the downloadable game (Windows, Mac, Linux, Android, iOS).
- **The browser version** at `https://play.yourdomain.com`, with real HTTPS. Players sign in and
  play online there, and it can also be embedded on itch.io.

One script does the setup. It takes about 20 minutes, most of it waiting.

> **Why a VPS?** The game server is a program that runs all the time and uses UDP ports.
> Hostinger's *web hosting* plans only serve websites, so they can't run it. You need a **VPS**
> ("KVM" plans).

---

## 1. Buy the VPS

1. **Pick a plan:** in Hostinger, choose **VPS Hosting**.
   - **KVM 2** (2 CPU cores, 8 GB RAM) is comfortable. Big ranked battles are simulated on the
     server.
   - **KVM 1** works for a small group of friends.
2. **Server location:** the one closest to your players.
3. **Operating system:** choose **Ubuntu 24.04** (plain; the script installs everything else).
4. **Root password:** set one and keep it safe.
5. **Note the IP:** when it's ready, hPanel → **VPS** → your server shows its **IP address**
   (e.g. `123.45.67.89`).

## 2. Point a domain at it

You need a domain name for HTTPS. Browsers only allow encrypted game connections to a real
domain with a certificate. Any domain works; you can buy one from Hostinger.

1. **Open the DNS settings:** in hPanel → **Domains** → your domain → **DNS / Nameservers**.
2. **Add a record:** add an **A record**:
   - **Name:** `play` (you'll get `play.yourdomain.com`; use `@` for the bare domain)
   - **Points to:** your VPS IP address
   - **TTL:** 300
3. **Wait:** it usually works within a few minutes. To check, run `ping play.yourdomain.com` on
   your PC; it should show the VPS IP.

> If the domain is registered elsewhere, add the same A record at that registrar.

## 3. Open a terminal on the VPS

Either:
- **In the browser:** hPanel → **VPS** → your server → **Browser terminal**.
- **From your PC:** in PowerShell or a terminal, run `ssh root@123.45.67.89` with your VPS IP,
  then enter the root password.

## 4. Get the game onto the VPS

```bash
apt-get update && apt-get install -y git
git clone https://github.com/kranpus/autobat.slop.git
cd autobat.slop
git checkout ccr-0588b58e-sbf731     # the branch with the latest code (or main once merged)
```

**If the repository is private,** GitHub asks for a username and password. For the password, use
a **personal access token**: GitHub → Settings → Developer settings → Fine-grained tokens →
Generate. Give it read-only *Contents* access to this repository, and paste the token as the
password.

## 5. Run the setup script

```bash
server/setup_vps.sh play.yourdomain.com
```

It:
- installs Docker;
- opens the firewall ports: SSH, 80 and 443 for the web page, 24704 for browser players, and UDP
  24702-24703 for the game app;
- saves your domain;
- builds and starts two containers:
  - **legion-draft-server:** the game server;
  - **legion-draft-web:** the browser version, served by Caddy. Caddy gets a free HTTPS
    certificate from Let's Encrypt and renews it by itself.

The first run takes about 5 minutes, because it downloads Godot and exports the browser build.

**Hostinger's own firewall:** if you've turned on the firewall in hPanel (**VPS → Security →
Firewall**), add the same rules there:
- TCP 22, 80, 443, 24704;
- UDP 24702-24703.

## 6. Play

- **Browser:** open **https://play.yourdomain.com**. The Server field is already filled in;
  create an account and play.
- **Downloadable game:** connects to the server built into it.
  - **This project's default:** `DEFAULT_SERVER` in `scripts/net/party.gd` is already
    `play.battleserver.tech`, so players don't type anything.
  - **A different domain:** change that line before exporting:
  ```gdscript
  const DEFAULT_SERVER := "play.yourdomain.com"
  ```
  Players can still type another server on the sign-in screen.
- **itch.io:** to use your own page, put a link to `https://play.yourdomain.com` on your itch
  page. To run it inside itch instead, set `DEFAULT_SERVER` as above, then build and upload the
  web zip (see [WEB.md](WEB.md)). It connects to your server over the encrypted `wss://`.

## Everyday tasks

All of these run on the VPS, in the `autobat.slop` folder:

| Task | Command |
|---|---|
| Admin console (gold, drops, locks, accounts...) | `server/admin.sh` (see below) |
| Server log | `docker compose -f server/docker-compose.vps.yml logs -f legion-draft` |
| Update to new code | `git pull && docker compose -f server/docker-compose.vps.yml up -d --build` |
| Restart | `docker compose -f server/docker-compose.vps.yml restart` |
| Stop | `docker compose -f server/docker-compose.vps.yml down` (accounts are kept) |
| Back up accounts and settings | `docker run --rm -v server_legion-data:/d -v "$PWD":/b debian tar czf /b/legion-backup.tgz -C /d .` |

The console commands are listed in [HOSTING.md](HOSTING.md#admin-commands-gold-rewards-drop-chances).

**After updating the game code,** players need the matching version of the downloadable game.
Out-of-date games show an **Update required** prompt when they connect:
- **Browser players** just press it to reload; the browser version updates when you run the
  update command.
- **Downloadable games:** to give their prompt a download button, add the page where players get
  the game to `server/.env`, then run the update command once:
  ```bash
  echo "UPDATE_URL=https://yourname.itch.io/autobat-legions" >> server/.env
  ```
  Or type `update-url https://...` in the admin console.

## The admin console

Connect to the VPS (hPanel → **VPS** → **Browser terminal**, or `ssh root@<IP>`), then:

```bash
cd autobat.slop
server/admin.sh
```

You get an `admin>` prompt. Type commands and press Enter; type `help` for the list and `exit`
to leave. For example:

```
admin> status
0 players online, 0 rooms. Gold: battles x1, draft x1, ...
admin> gold battle 1.5
Battle gold is now x1.5.
admin> drops unit legendary 0.25
admin> accounts reset-password SomePlayer
admin> unitstats draft win 20
admin> exit
```

To run a single command without the prompt: `server/admin.sh status` or
`server/admin.sh "gold battle 1.5"`.

Changes apply immediately and are saved (they survive restarts and updates). This is safe in the
browser terminal: there's nothing to detach from, and Ctrl+C only leaves the console, not the
server.

**The raw console:** `docker attach legion-draft-server` connects you to the server's own
console. Nothing is shown until you type, and it also prints the live log.
- **Leaving:** press **Ctrl+P then Ctrl+Q**.
- **Careful:** **Ctrl+C** stops the server. Docker restarts it, but matches in progress are lost.

## Troubleshooting

- **The browser page doesn't load or shows a certificate error:**
  - Check the domain points at the VPS (step 2), then run
    `docker compose -f server/docker-compose.vps.yml logs web`. Caddy explains why it couldn't
    get the certificate.
  - Let's Encrypt needs ports 80 and 443 open.
- **The page loads but you can't sign in:** check TCP port **24704** is open in both firewalls.
- **The downloadable game can't connect:** check UDP **24702** and **24703** are open.
- **"Your game is out of date":** the game and the server must come from the same code. Export
  the game again after updating the server.
- **The build sits on `fetch_export_templates.py web`:**
  - **Normally** it shows progress and takes under a minute.
  - **On a stalled connection to GitHub** it retries by itself and resumes where it stopped.
  - **If it gives up,** check that the VPS can reach github.com (`curl -I https://github.com`),
    then run the update command again.
  - **Updates** reuse the downloaded templates from Docker's cache, so this step only runs on
    the first build.
- **Out of disk space while building:** `docker system prune` removes old build layers.
