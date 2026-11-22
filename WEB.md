# Browser (HTML5) build

The game runs in a web browser, including online play through your server:

- **Online (signed in):** accounts, server-side progress, ranked battles against real players'
  armies, and online Legion Draft. Browser players and players on the downloadable game share
  the same accounts and meet in the same matches.
- **Offline (guest):** collection, army, expeditions, ranked against generated opponents, and
  **Legion Draft against bots** (Legion Draft → Solo → Play vs Bots). Guest progress is saved in
  the browser (IndexedDB) and survives reloads; clearing the site's data erases it.
- **Not in the browser:** LAN matches and live duels. They connect players directly over UDP,
  which browsers can't do.

The downloadable game talks to the server over encrypted UDP (ENet + DTLS). The browser game
uses a **WebSocket** connection to the same server (TCP port 24704) instead.

It's exported **without threads**, so it needs no special server headers
(`Cross-Origin-Opener-Policy` / `SharedArrayBuffer`). It works on itch.io, GitHub Pages, Netlify
or any static web host, in desktop and mobile browsers with WebGL 2.

## Build it

You need Godot 4.3 and its **export templates**. In the editor: **Editor → Manage Export
Templates → Download and Install**.

**From the editor:** **Project → Export → Web → Export Project**, into `export/web/index.html`.
The "Web" preset is already set up in `export_presets.cfg`.

**With a script** (imports, exports and zips):

```bash
tools/build_web.sh /path/to/godot          # Linux / macOS
```
On Windows, put `Godot_v4.3-stable_win64_console.exe` in `tools\` or `server\` and double-click
`tools\build_web_windows.bat`.

Both produce:
- `export/web/`: `index.html`, `index.js`, `index.wasm` (the engine, ~35 MB), `index.pck` (the
  game, ~6 MB) and icons.
- `export/AutobatLegions-web.zip`: the same files zipped (~13 MB), ready to upload.

## Play it at home (the server hosts the page)

Build the web version (above) in the same folder the server runs from, then start the server
as usual (`server\start_server_windows.bat`). The server finds `export/web/`, hosts the page
itself, and prints:

```
Browser version: open http://<this computer's address>:24705
```

On any phone, tablet or computer in the house, open `http://192.168.1.23:24705` (use your
server PC's address). The page's **Server** field fills in that address automatically, so you just
sign in or create an account. Firewall: run `server\allow_firewall_windows.bat` once; it opens
TCP 24704-24705 as well.

**Encryption at home:** a page served over plain `http://` connects with `ws://`, which is
**not encrypted**. The sign-in screen says so. That's fine on your own home network, but players
shouldn't reuse an important password. Passwords are still stored only as salted hashes on
the server. To encrypt browser connections, see "On the internet" below.

You can also try a build without the server's web host: `python3 -m http.server 8000 --directory
export/web`, then open <http://localhost:8000> (the Server field then defaults to `localhost`).
The Godot editor's **Run in Browser** button works too. Browsers won't run the game from a
`file://` path.

## On the internet (HTTPS and wss://)

A page on an HTTPS site (itch.io, GitHub Pages, your own domain) may only use **encrypted**
`wss://` connections, with a certificate the browser trusts. The game's self-signed certificate
won't do. You need:

1. **A domain name for the server,** e.g. `play.yourgame.com`, pointing at it, with TCP port 24704
   reachable.
2. **A real certificate for that name.** Let's Encrypt is free, e.g. with certbot:
   `sudo certbot certonly --standalone -d play.yourgame.com`.
3. **The certificate given to the server:**
   ```bash
   godot --headless --path . -- --server \
     --ws-cert=/etc/letsencrypt/live/play.yourgame.com/fullchain.pem \
     --ws-key=/etc/letsencrypt/live/play.yourgame.com/privkey.pem
   ```
   You can also copy them into the server's data folder as `ws_tls.crt` and `ws_tls.key`, or set
   the `WS_CERT` / `WS_KEY` environment variables. The server log then says `Browsers connect
   with wss:// on TCP port 24704 (encrypted)`.
4. **The address set in the web build:** set `DEFAULT_SERVER` in `scripts/net/party.gd` to the
   domain before exporting, or have players type it into the Server field. An HTTPS page uses
   `wss://` automatically. A full URL such as `wss://play.yourgame.com:443/legion` also works, for
   a server behind a reverse proxy.

Restart the server after renewing the certificate (Let's Encrypt renews every ~60 days).

## Publish on itch.io

1. Create a new project, **Kind of project: HTML**.
2. Upload `export/AutobatLegions-web.zip` and tick **This file will be played in the browser**.
3. **Embed options:**
   - Viewport size: 1280 × 720.
   - Tick **Fullscreen button**.
   - Leave **SharedArrayBuffer support** off (not needed).
   - For phones, tick **Mobile friendly** and choose landscape.

Any other static host works the same way: upload the contents of `export/web/` with
`index.html` at the root.

## If the page stays black

The page shows an error report when the game can't start: a red box saying what failed, plus
the browser details. Please send that text. If nothing appears at all:

- **itch.io settings:**
  - Kind of project: **HTML**.
  - The zip is ticked **This file will be played in the browser**.
  - **SharedArrayBuffer support** is off.
  - The zip has `index.html` at the top level: upload `export/AutobatLegions-web.zip` as built,
    not a folder that contains it.
- **The browser needs WebGL 2:** turn on hardware acceleration (Chrome: Settings → System) and
  update the browser. Very old phones and some locked-down work computers can't run it.
- **Reload once:** itch caches uploads, so a page can keep an older build for a few minutes.

## Notes

- **Size:** the first load downloads about 13 MB compressed (most hosts serve gzip). After that the
  browser caches it.
- **Sound:** browsers only allow audio after the first click or tap, so music starts then.
- **Symbols:** arrows, stars and triangles in the UI come from a bundled subset of DejaVu Sans
  (`assets/fonts/`), because browsers have no system fonts for Godot to fall back on.
- **Server ports for browsers:**
  - TCP 24704: WebSocket. Change it with `--ws-port=`, or turn it off with `--ws-port=0`.
  - TCP 24705: the web page. Change it with `--web-port=` and `--web-dir=`, or turn it off with
    `--web-port=0`.
- **Testing the browser connection without a browser:** `--websocket` makes a desktop build
  connect over WebSocket, e.g.
  `godot --headless -s res://tests/net_account_test.gd -- --server=localhost --websocket`.
