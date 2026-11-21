# Playing on phones and tablets

The game runs on **Android** and **iOS** from the same project. Mobile is handled like this:

- **Interface size:** text and buttons scale up automatically on phones, based on the screen's
  physical size. A phone shows roughly a 1000×450 layout and a tablet stays close to desktop.
  Players can override it in **Settings → Interface size** (Auto, 100–200%).
- **Compact layouts:** on short or narrow screens the menus tighten up.
  - **Draft:** smaller cards and a compact top bar.
  - **Collection:** fewer card columns.
  - **Army:** more room for the three columns.
  - **Battle tab:** the right-hand column scrolls.
- **Touch:**
  - Every tap and drag works with a finger, including drag-and-drop in Draft and the Army tab.
  - In battles, drag with one finger to pan and pinch with two to zoom.
- **Phone screens:** the game locks to landscape (either way round) and keeps content clear of
  notches and rounded corners.
- **Back button:** the Android back gesture closes a finished battle, returns to the first menu
  tab, and quits from there. It never drops you out of a Legion Draft match; use Leave for that.

## Build for Android

1. Open the project in **Godot 4.3**.
2. **Get the export templates:** **Editor → Manage Export Templates → Download and Install**.
3. **Point Godot at the Android tools:** in **Editor → Editor Settings → Export → Android**, set
   the **Java SDK path** (JDK 17) and the **Android SDK path**. The easiest way to get the
   Android SDK is to install Android Studio. Godot creates a debug keystore for you.
4. **Export:** **Project → Export → Android** (already configured: 64-bit ARM, internet and Wi-Fi
   permissions, immersive full screen) **→ Export Project** gives you an `.apk`.
   - **Install on a phone:** with USB debugging on, use the **Remote Debug** button (the
     Android icon) in the editor's top-right corner, or `adb install AutobatLegions.apk`.
5. **For the Play Store:** create a release keystore (Godot's docs walk through it), enter it
   under the preset's *Keystore → Release*, and export with **Export Project** with
   *Export With Debug* unticked.

## Build for iOS

You need a Mac with Xcode and an Apple developer account.

1. Install the export templates (step 2 above).
2. In **Project → Export → iOS**, fill in your **App Store Team ID**. The bundle ID is
   `com.autobat.legions`; change it to one you own.
3. Export, open the generated Xcode project, and run it on your device from Xcode.

## Mobile notes

- **Online and Join by IP** work on phones. **Find Matches (LAN)** relies on Wi-Fi broadcasts,
  which some Android phones filter, so if a match doesn't show up, join by the host's IP.
- **Battle speed:** large battles are the heaviest part of the game. A 2,000-unit battle uses
  about 8 ms per simulation step on a desktop CPU; phones are typically 2–4× slower. If the
  phone can't keep up, the battle plays in slow motion rather than stuttering. Smaller armies
  and **Skip to result** are always fast. If big battles feel slow on your phones, the battle
  simulation can be moved to C# or C++ for a large speed-up.
- **Test the phone layout on a PC:** run the game with a phone-sized UI using
  `godot -- --ui-scale=1.6` (with a wide window, e.g. `--resolution 1600x720`).
