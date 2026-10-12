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
| `phone_ui.gd` | iPhone UI: thread list / conversation views, unread badges, notification banner queue, status-bar clock, Checklist tab (done/current/locked), scripted quick-reply button; renders only, driven by the GameManager | Story data, input routing, game state |
| `chore_manager.gd` | Optional chore minigames (trash fetch-and-carry, dish wash mode): chore state, carried-bag visual, wash UI + scrub input, horror hooks (stalker texts, light flicker); emits `changed` | Story beats, input routing (GameManager forwards), level geometry |
| `unpack_manager.gd` | Core opening gameplay: unpacking 12 items from 4 labeled boxes into glowing placement zones (+ unmarked box with the stalker note); carried-item visual, gating, horror payoff; emits `changed` / `completed` | Story beats, input routing (GameManager forwards), level geometry |
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
- **Checklist tab**: bottom tab bar switches between Messages and Checklist.
  `GameManager._refresh_checklist()` pushes items (`set_checklist()`) with
  states done (green dot) / current (blue dot) / locked (gray). The checklist
  drives the opening sequence: lock the front door → text Mom → unpack.
- **Quick-reply**: `set_quick_reply(thread_id, text)` arms a one-tap canned
  reply button inside that thread's conversation view; tapping emits
  `quick_reply_tapped(thread_id, text)` and the GameManager sends the text
  (`send_text`) and advances the checklist. Used for "Text Mom you're home"
  (`"home safe! love you"`); the old auto-sent entry-beat text was removed
  in favor of this manual tap.

## Chore minigames (`chore_manager.gd`)

Optional filler, offered once after unpacking completes (toast + checklist UI
under the objective). Never blocks story beats; persists across dialogue; blackout
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

## Unpacking — core opening gameplay (`unpack_manager.gd`)

The first thing the player does (3–5 min), gated by the phone checklist:
**lock the front door → text Mom → unpack the boxes**. Each checklist item
unlocks the next; the HUD objective tracks the current item.

- **Checklist items** (`GameManager.CHECKLIST_ORDER`, flags `door_locked` /
  `texted_mom` / `unpacking_done`): `GameManager._refresh_checklist()` rebuilds
  the phone UI, arms the Mom quick-reply while it's current, and starts the
  UnpackManager once (a) and (b) are done. After the intro the phone
  auto-opens on the Checklist tab (onboarding) with toast
  "Check your list — press Tab".
- **(a) Lock the front door**: `front_door_lock` hotspot by the front door
  (one-shot). E swings the door shut (`ApartmentBuilder.close_front_door()`)
  and locks it — refused with "Step away from the door first." if the player
  is within 1.6 m of the doorway. Toast "Front door locked." + `ding`.
- **(b) Text Mom you're home**: quick-reply button `Send: "home safe! love you"`
  inside the Mom thread (only while current). Tap → `send_text`, toast "Sent.",
  + `ding`. (Replaces the old auto-sent entry-beat text.)
- **(c) Unpack the boxes**: 5 cardboard boxes in the foyer/living room —
  4 labeled (KITCHEN, BOOKS, BEDROOM, BATH) with 3 items each, 1 unmarked,
  slightly apart. E takes the next item (box lid opens; item rides the camera
  bottom-right with a walk bob). While carrying, only that item's placement
  zone is enabled and its marker glows (pulsing emissive disc); E at the zone
  snaps the item in with a scale-pop + `ding`. 12 items across 10 zones
  (kitchen sill/stove, living-room shelf + 2 windowsills, bedroom
  nightstand/bed, bathroom tub/sink/toilet) — walking the whole house teaches
  the layout. Objective "Unpack the boxes (n/12)". No timers, no fail states;
  wrong zones simply aren't enabled while carrying.
- **The unmarked box** (`unpack_box_plain`) stays disabled until the other 4
  are empty, then enables with toast "One box left. That one wasn't on the
  truck." Inside: a note reading "welcome home, mara". Taking it fires the
  stalker text "i know you're home" + buzz, emits `completed`, and the
  GameManager clears the objective, marks the checklist done, and offers the
  optional chores (the pre-existing post-intro flow).
- **Routing**: `GameManager._try_interact()` sends `unpack_*` / `uzone_*` ids
  to `UnpackManager.interact()`; `front_door_lock` is handled by the manager
  directly. Box/zone hotspots start disabled; `disable_all_interactables()`
  skips `unpack_*` / `uzone_*` / `front_door_lock` so the opening survives
  the blackout like the chores do.
- **Props**: `ApartmentBuilder._build_unpack()` — open-top cardboard boxes
  (floor + 4 walls + dark interior + removable lid + Label3D tag), 10 zone
  markers, zone/box hotspots, a low living-room bookcase, and
  `make_unpack_item_mesh(kind)` which builds the 12 small item props
  (books, frame, plant, mug, bowl, pot, lamp, clock, clothes, towel, soap,
  toilet paper, note) for both the in-hand mesh and the placed prop.

## Hiding spots (for the future stalker room-check — no stalker AI yet)

Three enterable closets, built as hollow carcasses with hinged doors that
swing **outward** (never through a hidden player). The GameManager owns the
hide/unhide state; the builder only makes the set dressing.

- **Spots** (`ApartmentBuilder.HIDE_CLOSETS`): `bedroom_closet` — the bedroom
  wardrobe, east wall (x≈6.35, z≈-0.5); `bathroom_closet` — linen cabinet on
  the bathroom south wall (-6.0, -1.5); `foyer_closet` — coat closet on the
  foyer east wall (1.85, 3.5). Interior ≈0.98 × 0.88 m fits the 0.7 m
  capsule. Each has a `hide_<spot>` hotspot ("Hide", reusable, never
  one-shot) in front of its door.
- **The bedroom wardrobe doubles as the "closet" story beat.** Its Hide
  hotspot is not created until that beat is consumed (then the story
  hotspot is fully retired, collision included, so the two prompts never
  compete for or occlude each other on the same door).
- **Hide** (`GameManager._hide`): E on the hotspot → player snaps just
  inside facing outward, the door tweens shut, movement locks
  (`PlayerController.movement_locked` — WASD only, look stays) with yaw
  clamped to a ±60° peek cone (`set_yaw_limits`), and a persistent
  "Hidden — E to come out" prompt shows. The spot's own hotspot disables
  while occupied; other prompts are suppressed.
- **Unhide** (`GameManager._unhide`): E → door tweens open, then the player
  steps back out to where they stood when they hid. Instant variant used
  when a story beat fires mid-hide (`start_beat` unhides first — beats never
  play while hidden). Phone still works while hidden; closing it keeps
  movement locked until exit. `disable_all_interactables()` skips `hide_*`
  so hiding stays available during the blackout.
- **Future-proof state** (no stalker code touches it yet):
  `GameManager.is_player_hidden() -> bool` and
  `GameManager.hidden_spot_id: String` (`""` when not hidden).
- **Builder API**: `set_hide_door(spot_id, open)` (tween),
  `set_hide_door_immediate(spot_id, open)` (snap), `add_hide_hotspot(spot_id)`
  (create/re-enable; safe for the future stalker sequence to call).

## Pause menu, save system, settings

**Pause menu** (`menu_ui.gd`, CanvasLayer layer 30, code-built like
`dialogue_ui.gd`). Esc priority in EXPLORE: phone open → close phone;
wash mode → exit wash; menu open → close menu; otherwise → open menu.
(Esc does nothing during DIALOGUE/CHOICE/ENDING.) While open the game keeps
rendering behind a dim overlay (no tree-pause, like the phone): input
locked, mouse released. Views: main (Resume / Save Game / Load Game /
Settings / Quit to Desktop), settings, and a 3-slot list. The GameManager
drives open/close and handles the signals; Tab and E are suppressed while
the menu is open.

**Settings** (`settings_manager.gd`, persisted in `user://settings.cfg`
via ConfigFile, applied at boot and on every change):
- Master Volume 0–100 → `AudioManager.volume` (0..1; audio is still
  stubbed, so this is stored/plumbed for the real implementation).
- Mouse Sensitivity 0.5x–2x → `PlayerController.mouse_sensitivity`
  (base 0.0024 × multiplier), applied live.
- Invert Y toggle → `PlayerController.invert_y`, applied in mouse look.

**Save system** (`save_manager.gd` + GameManager collect/apply). Three
manual slots at `user://save_slot_1..3.json` (versioned JSON). Slot buttons
show timestamp + current objective, or "Empty"/"Corrupted". Missing or
corrupt slots toast ("Empty slot." / "Save corrupted.") and never crash.

Save payload: flags dict, state (always EXPLORE — the menu only opens in
free roam), player position + yaw + pitch, checklist/chore/unpack progress,
phone threads (all messages + unread) and clock minutes, world state
(blackout, mechanical door open/closed, front door), and the list of
currently-disabled hotspot ids (consumed one-shots etc.).

Each manager owns its state via `serialize()`/`deserialize()`:
- `ChoreManager`: trash deposited, bags taken, first-deposit flag, dishes
  done (plates snap instantly to the rack on load). Carrying is never
  restored — the bag stays taken.
- `UnpackManager`: started/finished, items placed (props re-spawned),
  remaining per box, opened lids, box/zone hotspot states. A carried item
  goes back into its box.
- `PhoneUI`: messages per thread, unread counts, clock minutes (threads
  themselves are rebuilt from story data at boot).
- `ApartmentBuilder.serialize_world()/deserialize_world()`: blackout flag,
  door states (snapped, no tween), front door.

On load: flags → phone → world (blackout re-applies
`disable_all_interactables()` + dims ambient) → `_refresh_checklist()`
(rebuilds phone checklist UI, re-arms the Mom quick-reply, re-unlocks
unpacking) → chore/unpack deserializes → bedroom hide-hotspot gating via
the `closet_beat_done` flag → disabled hotspots → player transform. The
player always loads **unhidden**. HUD objective/checklist are rebuilt, then
the saved objective string is restored.

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
