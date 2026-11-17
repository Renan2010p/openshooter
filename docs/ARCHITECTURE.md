# OpenShooter Architecture

OpenShooter is split into **scenes** (what appears and where) and **scripts**
(how it behaves). Almost everything can be tuned in the Godot editor without
touching code.

```
OpenShooter/
├── assets/
│   ├── fonts/                 Barlow and Barlow Condensed (SIL OFL)
│   ├── icons/                 desktop, Android and adaptive launcher icons
│   └── ui/
│       ├── icons/             original SVG line icons
│       └── cursors/           arrow and I-beam mouse cursors
├── scenes/
│   ├── main.tscn              root: switches between menu and match
│   ├── game/world.tscn        a match (map + players + systems + HUD)
│   ├── maps/                  neighborhood, harbor, desert, arctic
│   ├── props/                 houses, warehouse, trees, car, lamp post, fence...
│   ├── player/
│   │   ├── player.tscn        player (body, hitbox, camera, weapons, AI)
│   │   ├── avatar.tscn        articulated block character
│   │   └── view_arms.tscn     first-person arms
│   ├── weapons/               3D model of each weapon
│   ├── fx/                    tracer, impact, explosion, placed mine, clouds
│   └── ui/
│       ├── hud.tscn           in-match interface
│       ├── main_menu.tscn     menu (rotating map + screens)
│       ├── screens/           one scene per menu screen
│       ├── touch_controls.tscn  virtual joystick and touch buttons
│       └── hotbar_slot / server_row / pause_menu / vote_panel
├── resources/
│   ├── weapons/*.tres         data sheet for each weapon (WeaponData)
│   ├── modes/*.tres           rules for each game mode (GameModeData)
│   ├── ui/theme.tres          generated design system
│   ├── environments/          sky, ambient light and fog per map
│   └── materials/, textures/
├── scripts/
│   ├── autoload/              Config, Net (LAN), Sfx, Cursor, Touch
│   ├── core/                  Block, BlockBaker, BakedModel
│   ├── game/                  World, Combat, MineManager, MatchManager, MapDB...
│   ├── player/                Player, WeaponHolder, BotBrain, Avatar
│   ├── weapons/               WeaponData, WeaponDB
│   ├── fx/                    effect scripts
│   └── ui/                    Hud, Crosshair, Scoreboard, MainMenu, touch UI...
├── shaders/                   scope, UI vignette and UI gradient shaders
├── tools/build_theme.gd       generates resources/ui/theme.tres
├── native/                    optional Zig GDExtension (map mesher)
├── audio/                     sound effects (.wav)
├── docs/                      this document + screenshots
├── icon.svg                   project icon
└── LICENSE                    GNU GPL v3.0
```

## The `Block` node

All geometry (maps, props, weapons, characters) is built from **Block** nodes:
a box, cylinder or sphere with **size, color, metalness, roughness, emission
and collision** editable in the Inspector.

- **In the editor**, each block draws itself.
- **At runtime**, the map (`GameMap`), weapons (`BakedModel`) and character
  (`Avatar`) merge their blocks with `BlockBaker`. This produces **a single mesh
  and a single collider**, with very few draw calls and high FPS even with
  hundreds of blocks.
- A block outside those containers draws itself and creates its own collision.

To add a block in the editor: *Add Node → Block*.

## Recipes

**Change a map.** Open a scene in `scenes/maps/`.
- To add something, place Blocks or drag scenes from `scenes/props/` into
  `Geometry` (any subfolder).
- `Spawns`: each Marker3D is a spawn point.
- `Waypoints`: points the bots walk between.
- `Sun` and `WorldEnvironment` control light and sky.

**Create a prop.** Create a scene with a `Node3D` root, build it from Blocks,
save it in `scenes/props/` and drag it into a map.

**Change a weapon.** Open `resources/weapons/<weapon>.tres` in the Inspector:
damage, rate of fire, magazine, spread, recoil, scope, sound, model and
first-person position. To change the look, edit `scenes/weapons/<weapon>.tscn`.
The `Muzzle` Marker3D marks the tip of the barrel.

**Add a weapon.**
1. Create the model in `scenes/weapons/`, with a `BakedModel` root and a
   Marker3D named `Muzzle`.
2. Create the data sheet `.tres` (New Resource → `WeaponData`).
3. Add it to the end of the `ALL` list in `scripts/weapons/weapon_db.gd`.

The hotbar and number keys adapt automatically (up to 9 keys; use the mouse
wheel after that).

**Change the character.** Edit `scenes/player/avatar.tscn`. Blocks with
`tint` = Shirt, Pants or Skin receive the Locker colors. The weapon is attached
to `ArmR/HandSocket`.

**Change the HUD or menu.** Open `scenes/ui/hud.tscn` or the screens in
`scenes/ui/screens/`. Nodes used by scripts have unique names (the `%` in the
editor), so they can be moved anywhere in the tree as long as the name stays the
same. Colors, fonts and styles live in `resources/ui/theme.tres` (variations:
TitleLabel, HudBig, Card, MenuBtn, BigButton, HotbarSlot...).

**Tune gameplay.** Values appear in the Inspector of each node:
- `Player`: speeds, jump and gravity
- `BotBrain`: reaction time, aim error and view distance
- `Combat`: respawn time
- `MineManager`: mine radius and damage
- `MatchManager`: kills needed to win a duel

## UI design system

All UI styling comes from `resources/ui/theme.tres`, generated by
`tools/build_theme.gd`. Changing the generator keeps every screen consistent.

```sh
godot --headless --path . --script tools/build_theme.gd
```

Design tokens live at the top of the generator:

- **Palette:** gunmetal surfaces, soft borders, off-white text, amber accent,
  red danger and green success.
- **Typography:** Barlow for body text and Barlow Condensed for titles and the
  HUD. Fonts are bundled in `assets/fonts/` under the SIL OFL.
- **Shape language:** 8–16 px rounded panels, 1 px borders and soft shadows.
- **States:** distinct normal, hover, pressed and disabled styles for buttons,
  inputs, sliders, checkboxes, popups and voting toggles.

Useful theme type variations:

| Variation | Used for |
|---|---|
| `MenuBtn`, `BigButton` | main menu navigation and mode cards |
| `PrimaryButton`, `DangerButton` | confirm and destructive actions |
| `GhostButton`, `SmallButton` | secondary actions and list rows |
| `Card`, `SubCard`, `ModalCard` | content panels and modal windows |
| `Row`, `ScoreRowPanel` | server list and scoreboard rows |
| `HotbarSlot`, `HotbarSlotActive` | weapon hotbar |
| `HeroLabel`, `TitleLabel`, `SectionLabel`, `Caption` | typographic hierarchy |
| `HudBig`, `HudLabel`, `HudSmall`, `HudAccent` | in-match HUD |
| `Gold`, `Silver`, `Bronze` | top-three leaderboard |
| `TouchButton`, `TouchButtonSmall`, `TouchButtonFire` | mobile action buttons |

Overlay shaders:

- `shaders/ui_gradient.gdshader` darkens one side of the menu for readability.
- `shaders/ui_vignette.gdshader` adds cinematic edge darkening.
- Both are plain `ColorRect` overlays, so they cost almost nothing on the
  Compatibility renderer.

Screens are independent `.tscn` files under `scenes/ui/screens/`. They share the
same header layout and talk to `MainMenu` through `MenuScreen`. Buttons and
fields used by scripts keep unique names (`%Name`), so the layout can be
rearranged freely in the editor.

Motion and custom controls:

- `UiMotion` centralizes screen slides, button hover/press scaling and modal
  pop-in. The menu camera also glides between the orbit view and the Locker,
  scaling the character preview in and out.
- `AnimatedIcon` gives icons a gentle pulse/tilt and a larger scale while their
  parent button is hovered.
- `AnimatedNumber` rolls numeric HUD values (timer, ammo, health) up or down and
  is also used by the stepper.
- `Stepper` is the animated minus/plus field used for bot and player counts in
  the Create Server screen.
- `StatsChart` draws the animated performance chart from `stats.history`.
- `TouchControls`, `TouchJoystick`, `TouchAimStick` and `TouchLookArea` form the
  mobile input layer; `MenuIconButton` builds the large home-menu buttons.
- `MenuIconButton` builds the large home-menu buttons with an animated icon and
  a label that follows the selected theme variation.
- The `Cursor` autoload installs the custom arrow and I-beam textures and makes
  text fields request the matching cursor shape.

Startup and loading:

- `scenes/ui/splash.tscn` is the main scene. `Splash` fades in **RL PROJECTS**,
  cross-fades to the author credit, then calls
  `change_scene_to_file.call_deferred("res://scenes/main.tscn")`. Any key,
  click or tap skips it; test runs with command-line user args skip it too, so
  screenshots and automated matches are not delayed. Godot's own boot splash is
  disabled in `project.godot` (`boot_splash/show_image=false`).
- `main.tscn` owns a `LoadingScreen` (`scripts/ui/loading_screen.gd`) above the
  match. `_start_world()` loads `world.tscn` and the map scene with
  `ResourceLoader.load_threaded_request()`, feeding the bar with
  `load_threaded_get_status()` and a generation token so a cancelled load cannot
  overwrite a newer screen.
- `World.preloaded_map` / `preloaded_map_idx` let `_load_map()` instantiate the
  already loaded map instead of loading it a second time.

## Settings and statistics

`Config` (`scripts/autoload/config.gd`) stores input, display and graphics
preferences in `user://config.cfg`. Besides the quality preset, the Advanced
settings expose VSync, an FPS limit, a render-scale multiplier, a scene
brightness control and the screen shake toggle.

The statistics dictionary also contains a short match history:

```gdscript
stats = {
    "kills": 0, "deaths": 0, "matches": 0, "wins": 0,
    "headshots": 0,
    "history": [{"kills": 7, "deaths": 2, "won": true}, ...]
}
```

`MatchManager.match_over()` calls `Config.record_match()`, which appends the
local player's result, keeps the last 12 entries and saves the file. The
Statistics screen reads this history to draw the performance chart.

## Mobile / Android

The Android build uses the same `World`, `Player` and `HUD` scenes as desktop.
The differences are limited to input and layout:

- `Touch` (autoload) holds the shared touch state: movement vector, look delta,
  fire/aim hold, crouch toggle, pending jump/reload/weapon changes and the
  scoreboard toggle.
- `TouchControls` (`scenes/ui/touch_controls.tscn`) contains the full-screen
  look area, a relative-drag movement joystick, a right aim/shoot stick,
  jump/reload/crouch buttons, weapon prev/next, pause and scoreboard.
- `TouchAimStick` writes `Touch.look_rate` (rate-based aim) and `Touch.aim_auto`.
  Touching it enters ADS automatically; pushing past `fire_threshold` holds the
  fire button, so automatic weapons keep shooting and semi-automatic weapons
  fire once per push.
- `Player._assist_level()` returns Off/Light/Standard for touch players when
  `Config.aim_assist` is enabled and the host allowed it
  (`Net.server_info.aim_assist`). `_aim_target()` uses a narrow cone, a range
  limit, line of sight and a chest aim point; `_apply_aim_assist()` pulls
  gently, with less strength while moving or scoped. `_apply_touch_look()`
  slows look input near a target. There is **no auto-fire**.
- The joystick and look area handle both `InputEventScreenTouch`/`Drag` and the
  emulated mouse events, so desktop testing with `--touch` and real multi-touch
  both work. Screen events take priority to avoid double input.
- `Player._touch_input()` consumes `Touch`; `_apply_touch_look()` applies the
  accumulated look delta. Desktop keyboard/mouse input is bypassed while
  `Touch.active` is true.
- `Config.touch_joystick_size` (80–200%) and `Config.touch_opacity` (40–100%)
  are edited in Settings → Advanced → Mobile and applied by
  `TouchControls._apply_config()`.
- `Hud._layout_mobile()` moves health to the top-left, ammo to the top-right,
  hides the hotbar and kill feed, and leaves the corners free for the touch
  clusters. Informational HUD nodes are set to `MOUSE_FILTER_IGNORE` so they do
  not steal touches from the look area.
- The custom mouse cursor is disabled on mobile; the custom I-beam is only for
  desktop text fields.

Android packaging lives in `export_presets.cfg`:

- `platform="Android"`, prebuilt APK template, embedded PCK.
- Custom launcher/adaptive icons under `assets/icons/`.
- Permissions: INTERNET, ACCESS_NETWORK_STATE, ACCESS_WIFI_STATE and
  CHANGE_WIFI_MULTICAST_STATE.
- The local build is signed with the standard Android debug keystore; replace
  `keystore/release*` with a private release key before publishing.

LAN discovery on Android can be limited by the OS or Wi-Fi network. Direct IP
is the supported fallback, and hosting on a PC is recommended.

## Maps

Maps live in `scenes/maps/` and are listed in `scripts/game/map_db.gd`:
Neighborhood, Harbor, Desert Village and Arctic Base. The server host picks the
map, and the index is sent to clients in `Net.server_info.map`. `World` loads
the map when a match starts, and the menu picks one at random for the
background.

To create a map:
1. Duplicate a `.tscn` from `scenes/maps/` (root with the `GameMap` script).
2. Build it with Blocks and props inside `Geometry`.
3. Adjust `Spawns` and `Waypoints`.
4. Add the map to `MapDB.MAPS`.

Keep the area near x=-2, z=18 clear; that is where the Locker shows the
character.

## Performance: only draw what matters

- **Chunked maps:** `GameMap` merges blocks into cells of `chunk_size` meters
  (24 by default). Off-screen chunks are not drawn, and neither are chunks
  beyond the **draw distance**.

  | Quality | Draw distance | Details up to |
  |---|---|---|
  | Low | 65 m | 26 m |
  | Medium | 95 m | 46 m |
  | High | 140 m | 72 m |

- **Depth fog:** reaches 100% exactly at the draw distance, so anything that
  stops being drawn is hidden inside it.
- **Native Zig mesher:** `native/` (GDExtension, written in Zig) receives the visible blocks as a
  flat `PackedFloat32Array` (24 floats each) and returns chunk buffers. Each
  chunk is built as **one surface** with `resources/materials/map_surface.gdshader`,
  which reads metallic and emission from `UV2` and roughness from the vertex
  color alpha. Fewer surfaces per chunk means fewer draw calls; the extension
  also bakes a map about 2.5 times faster than GDScript (see
  `tests/bake_bench.gd`).
  Box faces fully covered by a neighbouring solid box are skipped (internal
  walls, floors and buried props), and collision is generated in the same pass:
  one `ConcavePolygonShape3D` per chunk on a single `StaticBody3D` (roughly
  64 shapes instead of one box per block).
  `BlockBaker.native_available()` checks `ClassDB` and falls back to the
  GDScript mesher and per-block collision (`--no-native` forces the fallback).
- **Details (fallback path):** small blocks without collision (stripes, frames,
  ribs, leaves) go into a details mesh that disappears earlier and casts no
  shadows. This can be forced in the Block Inspector with `lod` (Auto, Always,
  Detail). The native path merges details into the chunk to keep one draw call;
  it relies on the draw distance instead.
- **Players:**
  - the character is not drawn beyond the draw distance;
  - the name tag disappears at 40 m;
  - animation only runs for visible players, and less often for distant ones
    (30×/s from 20 m, 15×/s from 40 m).
- **Camera:** the far plane (`far`) matches the draw distance.
- **Occlusion:** disabled by default (`GameMap.use_occluders`). On an Intel HD
  4400 it did not improve FPS and caused hitches.

## Networking

- The host is the **server** (ENet, port 24540/UDP).
- The match always lives at `/root/Main/World` and has the same path on every
  computer. RPCs depend on this.
- **Movement:** each player sends their own position (`Player.sync_state`,
  30×/s).
- **Shots and damage:** the server validates them in `Combat._server_fire`
  (a ray against the `Body` and `Head` hitboxes) and broadcasts the result with
  `fx_shot`, `on_hit`, `on_kill` and `on_respawn`.
- **Bots:** they run on the server only.
- **Discovery:** the server announces the match over UDP broadcast on port
  24541 (`Net`). Private matches only send a hash of the code.

**Physics layers:**

| Layer | Use |
|---|---|
| 1 | world |
| 2 | player bodies (only collide with the world) |
| 3 | hitboxes (shot rays only) |

**Visual layers:**

| Layer | Use |
|---|---|
| 1 | normal |
| 2 | the local player's own body (hidden from their camera) |
| 3 | first-person weapon |
