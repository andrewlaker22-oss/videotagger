# ARCHITECTURE

## Scene tree (`main.tscn`)

`main.tscn` is intentionally tiny — almost everything is built in code.

```
Main (Node3D) — game_manager.gd
├── WorldEnvironment — dark fog + faint blue ambient (dimmed to ~0 on blackout)
├── Apartment (Node3D) — apartment_builder.gd (builds the two-story house in _ready)
├── Player (CharacterBody3D) — player.gd (spawns on the porch, facing the front door)
│   ├── CollisionShape3D (capsule r=0.35 h=1.7)
│   └── Head (Node3D, y=1.6)
│       └── Camera3D (fov 70)
│           └── InteractRay (RayCast3D, 2.6 m forward)
├── DialogueUI (CanvasLayer) — dialogue_ui.gd (builds all widgets in _ready)
├── PhoneUI (CanvasLayer) — phone_ui.gd (iPhone-style text UI: thread list,
│   conversation bubbles, unread badges, notification banner, status clock)
└── AudioManager (Node) — audio_manager.gd (stubbed)
```

## Script responsibilities

| Script | Owns | Does NOT own |
|---|---|---|
| `game_manager.gd` | State machine (EXPLORE/DIALOGUE/CHOICE/ENDING), flag table, beat flow, effects, input routing, restart | Story content, UI construction, level geometry |
| `story_data.gd` | All narrative content: beats, lines, choices, timers, flags, endings, interactable→beat map | Any behavior |
| `player.gd` | WASD + mouse look, crosshair focus detection, raw input signals, camera shake | Game state (it emits signals; the manager decides) |
| `dialogue_ui.gd` | Objective, prompt, dialogue box, timed choices + countdown, toasts, letterbox, ending screen, fade-in | Story data, state |
| `interactable.gd` | Hotspot node: `interact_id`, `prompt`, `enabled` | Its story meaning (that's in `story_data`) |
| `apartment_builder.gd` | Level geometry from `WALLS` data table, stairs (visual steps + collision ramps), props, lights + flicker, door tween, blackout, power stutter | Story |
| `phone_ui.gd` | iPhone UI: thread list / conversation views, unread badges, notification banner queue, status-bar clock; renders only, driven by the GameManager | Story data, input routing, game state |
| `chore_manager.gd` | Optional chore minigames (trash fetch-and-carry, dish wash mode): chore state, carried-bag visual, wash UI + scrub input, horror hooks (stalker texts, light flicker); emits `changed` | Story beats, input routing (GameManager forwards), level geometry |
| `audio_manager.gd` | `play_sfx` / `play_music` / `stop_music` hooks (currently print) | Anything else |

## The story state machine

```
EXPLORE ──E/click on Interactable──▶ DIALOGUE ──lines done──▶ CHOICE ──pick/timeout──▶ DIALOGUE (next beat)
   ▲                                    │                         │
   │                                    │ lines done, has "next"  │ has "ending"
   │                                    ▼                         ▼
   └──────────────────────── DIALOGUE (next beat)              ENDING ──R──▶ (reload scene)
   (lines done, no next/choices/ending)
```

- **EXPLORE**: player controls unlocked; crosshair ray highlights `Interactable`s;
  `E`/click starts the mapped beat (one-shot interactables disable themselves).
- **DIALOGUE**: controls locked, letterbox on; `E`/click advances; lines with
  unmet `"if"`/`"if_not"` conditions are skipped; `"sfx"` on a line plays a sound.
- **CHOICE**: mouse released for clicking; countdown bar drains; `1-4`/click picks;
  on timeout the `"default"` choice is auto-picked; `"set"` flags are applied and
  `"toast"` shown before the next beat starts.
- **ENDING**: ending beat's lines play as dialogue, then the ending screen
  (`ENDING: <TITLE>` + subtitle). `R` reloads the scene.

## Story data schema

Defined and documented in `scripts/story_data.gd` (the comment block at the top
is the canonical schema reference). Summary:

- **Beat**: `{ objective?, effects?, lines[], choices[]?, timer?, next?, ending? }`
- **Line**: `{ who, text, if?, if_not?, sfx? }` — `who: ""` = narration.
- **Choice**: `{ text, next, set?, toast?, default? }` — exactly one `default` per beat.
- **Effects**: `"open_door"` (swings the front door), `"blackout"` (kills lights,
  disables interactables except the breaker box, camera shake, sfx),
  `"power_stutter"` (lights flicker back for ~1.6 s, then die again),
  `"phone_ring"`.
- **Endings**: `{ id: { title, subtitle } }` — ESCAPE / HIDE / CONFRONT.

`get_trigger_beats()` maps `Interactable.interact_id` → beat id, so level
designers place hotspots and writers name beats without touching each other's files.

## Phone / text message system (`phone_ui.gd`)

- **UI**: dark-mode iPhone that slides up from the bottom-right. Thread list
  (Mom / Jess / Unknown) with avatar initials, previews, and unread badges;
  conversation view with gray incoming / blue outgoing bubbles and timestamps;
  status bar with Dynamic Island, signal glyph, and the phone clock.
  Mara never types — her outgoing messages are scripted by story data.
- **Clock**: starts at 11:46 PM; `GameManager.start_beat()` advances it +1 min
  per beat, so the intro beat reads 11:47 PM (matching the story).
- **Input**: `Tab` toggles the phone during EXPLORE only (releases the mouse
  for tapping; `Tab`/`Esc` closes and recaptures). Not allowed during DIALOGUE
  (E advances lines) or CHOICE (timer keeps running). While open, the player
  can't walk (`control_locked`), but the game keeps running — horror tension.
- **Notifications**: a banner slides down from the top for ~4 s whenever a text
  arrives (even mid-dialogue/choice); banners queue if several arrive at once.
  Unread badges accumulate per thread; opening a thread marks it read. Banner
  is display-only (mouse is usually captured). Incoming texts play the
  `text_buzz` sfx hook.
- **Data**: threads + starter messages live in `StoryData.get_phone_threads()`.
  Beat-triggered texts use the `"text"` effect — a Dictionary entry in a beat's
  `"effects"` array: `{"effect": "text", "from": <thread_id>, "text": ...}`
  for incoming, `{"effect": "text", "from": "mara", "to": <thread_id>, ...}`
  for Mara's scripted outgoing messages.

## Chore minigames (`chore_manager.gd`)

Optional filler, offered once after the intro (toast + checklist UI under the
objective). Never blocks story beats; persists across dialogue; blackout
doesn't disable chore hotspots (`disable_all_interactables()` skips
`trash_*` / `sink`).

- **Trash (fetch-and-carry)**: 3 bags (`trash_bag_kitchen/living/bedroom`) +
  porch bin (`trash_bin`). E picks up ONE bag at a time (bag prop hides, a
  small bag mesh rides the camera, `player.speed_factor` 0.85 while carrying);
  E at the bin tosses it in. Checklist "Trash n/3". First deposit (outside at
  night) triggers stalker text "i can see you". Completion toast:
  "All clean. For nothing." + `ding` hook.
- **Dishes (hold-to-scrub)**: `sink` hotspot at the kitchen sink enters wash
  mode (movement locked, mouse released, camera leans in; `Esc`/`Tab` exits).
  Hold LMB or E to scrub the active dish: per-dish progress ring, ~3 s each,
  plate wiggles while scrubbing, `ding` per dish, then it tweens upright into
  the drying rack. Completing dish 2 flickers the kitchen lights
  (`ApartmentBuilder.flicker_near()`) and texts "turn around". All 4 done:
  toast "Dishes done.", sink hotspot disables itself.
- **Routing**: `GameManager._try_interact()` sends `trash_*` / `sink` ids to
  `ChoreManager.interact()` (not story beats, not in `get_trigger_beats()`).
  Wash-mode input (LMB/E hold, Esc exit) is handled by the ChoreManager;
  the manager guards `primary_action` and `Tab` while washing.
- **Checklist UI**: `DialogueUI.set_chores()` — small line under the objective
  ("Trash 1/3 · Dishes 2/4"), shown once chores are offered.

## Floor plan (all dimensions in meters)

Footprint x in [-7, 7], z in [-5, 5]. Three stories, 2.7 m each: basement floor
at y=-2.7, ground at y=0, upper at y=2.7, roof slab at y=5.4. Floor slabs have
stairwell holes; guard walls (1 m) ring the holes on each floor.

- **Porch** (outside, south): stoop x in [-0.4, 2.0], z in [5.0, 6.4] with
  railings. Player spawns here facing the front door (south wall gap x in
  [0.2, 1.4], swings inward).
- **Ground**: foyer (x in [-1, 2.5], z in [1, 5]), living room (west, x in
  [-7, -1]: couch, TV + screen, two floor lamps), kitchen (east, x in
  [2.5, 7]: counter, stove, fridge + note, knife), stair hall (x in [-1, 2.5],
  z in [-5, 1]).
- **Stairs** (in the stair hall, z from 0.9 down to -4.0, ~29°):
  - Up-run x in [-0.7, 0.5] → upper hall. Down-run x in [0.9, 2.1] → basement.
  - Visual steps are solid boxes with closed risers, NO collision; each run
    has ONE sloped ramp StaticBody3D the player walks on. Wood fascia trim
    frames each slab hole; a dim light sits over the basement stair base.
  - Slab holes fit the runs snugly (0.05 m clearance/side); 1 m guard walls
    ring the holes on each floor (open only at stair entry/exit).
- **Mechanical doors** (E toggles open/close, not story beats; work during
  blackout): `door_bedroom` (upper x=2.5 wall), `door_basement` (stair hall
  frame at down-run top), `door_back` (north wall x in [4.0, 5.2], swings out),
  `door_outhouse` (outhouse south face). Front door keeps story-driven behavior.
- **Windows** (fixed, night-dark glass): living west wall x2, kitchen east x1,
  south wall x2 flanking front door, bedroom east x1, bathroom north x1 frosted.
- **Upper**: hall (x in [-1, 2.5], z in [-5, 1]), bedroom (east, x in [2.5, 7]:
  bed, nightstand + photo, closet), bathroom (north-west, x in [-7, -3.5],
  z in [-5, -1]: sink + mirror, toilet, tub), open landing (south).
- **Basement**: open dim space, support columns, storage boxes, breaker box on
  the east wall (x≈6.8, z=-1.0) with a red LED so it can be found in the dark.
- **Backyard** (outside, north): dirt yard x in [-7, 9], z in [-12, -5],
  perimeter fence, worn path from the back door to a wooden outhouse
  (x in [5, 7], z in [-11.4, -9], slanted roof, bench inside, working door).

Interactable positions: `fridge_note` (5.725, 1.35, -3.95), `kitchen_knife`
(3.2, 1.1, -4.25), `bedroom_photo` (4.3, 3.55, -4.5), `bedroom_closet` (6.35,
3.8, -4.15), `bathroom_mirror` (-6.3, 4.3, -4.1), `breaker_box` (6.4, -1.35,
-1.0). The blackout disables every interactable EXCEPT `breaker_box` (which
the `breaker` beat needs afterwards) and the mechanical `door_*` doors.

## Data flow example (the knife)

1. `apartment_builder` places `Interactable(interact_id="kitchen_knife")` on the counter.
2. Player aims + presses `E` → `player` emits `primary_action` → manager
   (`EXPLORE`) looks up `"kitchen_knife"` → `"knife"` beat → `start_beat`.
3. `"knife"` beat: lines shown → `CHOICE` with 6 s timer → pick "Take the knife":
   sets `has_knife`, toast "Mara will remember that." → beat `"blackout"`.
4. `"blackout"`: effect kills lights; the conditional line
   (`"if": "has_knife"`) shows only if the knife was taken → final choice →
   `"end_confront"` etc. → `"ending"` → ending screen.

## Placeholders

- **Art**: all primitives built in `apartment_builder.gd`; materials are flat
  `StandardMaterial3D`s. Replace per `assets/README.md`.
- **Audio**: `audio_manager.gd` prints hook names; real files go in `audio/`
  per `audio/README.md`.
- **No save system, no settings, no main menu** — prototype scope. See `docs/TASKS.md`.
