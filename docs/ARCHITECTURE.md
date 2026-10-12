# ARCHITECTURE

## Scene tree (`main.tscn`)

`main.tscn` is intentionally tiny — almost everything is built in code.

```
Main (Node3D) — game_manager.gd
├── WorldEnvironment — dark fog + faint blue ambient (dimmed to ~0 on blackout)
├── Apartment (Node3D) — apartment_builder.gd (builds the level in _ready)
├── Player (CharacterBody3D) — player.gd
│   ├── CollisionShape3D (capsule r=0.35 h=1.7)
│   └── Head (Node3D, y=1.6)
│       └── Camera3D (fov 70)
│           └── InteractRay (RayCast3D, 2.6 m forward)
├── DialogueUI (CanvasLayer) — dialogue_ui.gd (builds all widgets in _ready)
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
| `apartment_builder.gd` | Level geometry from `WALLS` data table, props, lights + flicker, door tween, blackout | Story |
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
  disables interactables, camera shake, sfx), `"phone_ring"`.
- **Endings**: `{ id: { title, subtitle } }` — ESCAPE / HIDE / CONFRONT.

`get_trigger_beats()` maps `Interactable.interact_id` → beat id, so level
designers place hotspots and writers name beats without touching each other's files.

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
