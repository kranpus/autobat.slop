# Browser (HTML5) build

The game runs in a web browser as a single-player build. It plays offline:

- **Works in the browser:** collection, army, expeditions, ranked battles against generated
  opponents, practice battles, and **Legion Draft against bots** (Legion Draft → Solo → Play vs
  Bots).
- **Saving:** progress is saved in the browser (IndexedDB) and survives reloads. Clearing the
  site's data in the browser erases it.
- **Not in the browser:** signing in, online and LAN Legion Draft, live duels, and real players'
  armies in ranked. All of these use UDP networking (ENet), and browsers can't send UDP. The game
  hides those options and explains why. Players who want them use the downloadable version.

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

## Try it locally

Browsers won't run it from a `file://` path, so serve the folder:

```bash
python3 -m http.server 8000 --directory export/web
```

Then open <http://localhost:8000>. In the Godot editor you can also press the **Run in Browser**
button (top right, HTML5 icon) instead, which exports and serves it for you.

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

## Notes

- **Size:** the first load downloads about 13 MB compressed (most hosts serve gzip). After that the
  browser caches it.
- **Sound:** browsers only allow audio after the first click or tap, so music starts then.
- **Symbols:** arrows, stars and triangles in the UI come from a bundled subset of DejaVu Sans
  (`assets/fonts/`), because browsers have no system fonts for Godot to fall back on.
- **Online play in the browser later:** this would need the server to also accept WebSocket
  connections (`WebSocketMultiplayerPeer`). On an HTTPS host it would also need a real TLS
  certificate for the server's domain (e.g. from Let's Encrypt), because browsers refuse
  self-signed certificates.
