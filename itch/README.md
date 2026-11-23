# itch.io page kit

Everything for the Autobat Legions page on itch.io: the images, the description and every
setting, in the order the **Create new project** / **Edit game** form asks for them.

| File | What it's for |
|---|---|
| `cover.png` | Cover image (630 × 500, itch's recommended size). |
| `banner.png` | Banner at the top of the page (960 × 300), set under **Edit theme**. |
| `battle.gif` | Animated battle (3.3 MB). Upload it as the **first screenshot**. |
| `screenshots/*.png` | Screenshots (1920 × 1080), in the order to upload them. |
| `description.html` | The page description. Open it in a browser, select everything below the line and paste it into itch's description box. |

To refresh the images for a new version:

```
xvfb-run -a -s "-screen 0 1920x1080x24" godot --rendering-driver opengl3 --resolution 1920x1080 \
  --path . -s res://tools/itch_shots.gd -- --out=$PWD/itch/screenshots
python3 tools/itch_art.py            # cover.png and banner.png from the battle screenshot
```

The GIF: record with `tools/itch_gif.gd` (the command is at the top of that file), then

```
ffmpeg -framerate 20 -start_number 120 -i /tmp/frames/f%08d.png -t 6 -vf "fps=10,scale=480:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=96:stats_mode=diff[p];[b][p]paletteuse=dither=none:diff_mode=rectangle" itch/battle.gif
```

## 1. Create the project

| Field | Value |
|---|---|
| Title | `Autobat Legions` |
| Project URL | `autobat-legions` |
| Short description or tagline | `Raise a legion of 1,000+ units and watch them clash in fully automatic fantasy battles.` |
| Classification | Games |
| Kind of project | **HTML** (the web build is played on the page; downloads go alongside it) |
| Release status | In development |
| Pricing | No payments, or **Donate** if you'd like a tip jar |

## 2. Uploads

Build with `tools/export_all.sh`, then upload the four files from `export/legion-<version>/`:

| File | Settings |
|---|---|
| `legion-<version>-web.zip` | Tick **This file will be played in the browser**. |
| `legion-<version>-windows.zip` | Platform: Windows. |
| `legion-<version>-linux.zip` | Platform: Linux. |
| `legion-<version>-android.apk` | Platform: Android. |

Or upload them all from the command line with butler: `tools/itch_push.sh <your-itch-name>/autobat-legions`
(see the top of that script). Later versions: run it again, and butler sends only what changed.

## 3. Embed options (for the web build)

| Option | Value |
|---|---|
| Viewport dimensions | 1280 × 720 |
| Automatically start on page load | Off (players click **Run game**; music needs a click anyway) |
| Fullscreen button | On |
| Mobile friendly | On, orientation **Landscape** |
| SharedArrayBuffer support | **Off** (the game doesn't need it) |
| Scrollbars | Off |

The web build connects to `play.battleserver.tech` for accounts, ranked and Legion Draft, so it
works straight from the itch page.

## 4. Details

| Field | Value |
|---|---|
| Description | Paste from `description.html` (see above). |
| Genre | Strategy |
| Tags (up to 10) | `auto-battler`, `auto-chess`, `strategy`, `pvp`, `multiplayer`, `fantasy`, `pixel-art`, `army`, `medieval`, `godot` |
| AI generation disclosure | itch asks whether the project uses generative AI; answer it yourself. For reference: the art, sound and music are CC0 assets made by people (see CREDITS.md), while the game's code and writing were made with an AI coding assistant. |
| App store links | None |
| Custom noun | Leave blank |
| Community | Comments on, if you'd like feedback |
| Visibility | **Draft** while you set it up, then **Public** |

**Cover image:** `cover.png`.

**Screenshots,** in this order: `battle.gif`, `screenshots/01_battle.png`, `03_call_to_arms.png`,
`04_collection.png`, `05_scouts_report.png`, `08_legion_draft.png`, `02_battle_field.png`,
`06_army.png`, `07_challenges.png`.

**Trailer:** none yet (itch only takes YouTube or Vimeo links).

## 5. Edit theme (the page's look)

Open the page, click **Edit theme** at the top:

| Setting | Value |
|---|---|
| Banner | `banner.png`, aligned centre |
| Background | `#15171d` (dark stone) |
| Second background (description panel) | `#2b2119` (dark wood) |
| Text | `#e4cf9f` (parchment) |
| Links | `#d9b45a` (gold) |
| Buttons | `#7a1f1c` (wax-seal red) |
| Header font | Cinzel if it's in the list, otherwise a serif font |
| Body font | Lato or Open Sans |
| Layout | Embed game at the top, screenshots in the sidebar |

## 6. After publishing

- Point out-of-date games at the page from the server console: `update-url https://<your-itch-name>.itch.io/autobat-legions`.
  Their **Update required** prompt then gets a **Download update** button.
- Post the patch notes as a **devlog** with each release (the text is in `scripts/core/patch_notes.gd`).
- Each release: `tools/export_all.sh`, then `tools/itch_push.sh <your-itch-name>/autobat-legions`.
