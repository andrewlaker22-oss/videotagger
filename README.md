# WATCHED

A Telltale-style **3D psychological-horror narrative prototype** (stalker theme) built in **Godot 4.7.2**.
~10 minutes of playtime. First-person exploration of a small apartment, timed dialogue choices
("Mara will remember that"), and three endings.

You play **Mara**, coming home late at night to find her apartment door ajar.

## Requirements

- **Godot 4.7.2 stable** (Forward+ renderer). Other 4.x versions will *probably* work,
  but 4.7.2 is the validated target.
- Windows 10/11 for the desktop build (the project itself is platform-agnostic).

## Open & run

1. Open Godot 4.7.2 → **Import** → select `project.godot` in this folder → **Import & Edit**.
2. Press **F5** (or the ▶ button) to run.

No setup, no assets to download, no autoloads — everything is procedural placeholder.

## Controls

| Input | Action |
|---|---|
| W A S D | Move |
| Mouse | Look (click once to capture the mouse) |
| E or left-click | Interact / advance dialogue |
| 1 – 4 or mouse | Pick a dialogue choice |
| Esc | Release the mouse |
| R | Restart (on the ending screen) |

**Reaching each ending (for testing):** E/click through the intro → walk to the
kitchen (east side) → read the fridge note → answer or ignore the phone → bedroom:
photo on the nightstand, closet → bathroom: mirror → kitchen: the knife on the
counter → after the blackout, choose **fire escape** (ESCAPE), **closet**
(HIDE), or **door** (CONFRONT).

## Project structure

```
watched/
├── project.godot          # Godot 4.7.2, Forward+, main scene = main.tscn
├── main.tscn              # Tiny scene: Main(GameManager) + WorldEnvironment +
│                          #   Apartment(builder) + Player + DialogueUI + AudioManager
├── scripts/
│   ├── game_manager.gd    # State machine: EXPLORE → DIALOGUE → CHOICE → ENDING
│   ├── story_data.gd      # ★ THE STORY. Beats, dialogue, choices, flags, endings.
│   ├── player.gd          # First-person controller (WASD + mouse, E/click)
│   ├── dialogue_ui.gd     # HUD, dialogue box, timed choices, toasts, ending screen
│   ├── interactable.gd    # Raycast hotspot (id + prompt); story meaning lives in story_data
│   ├── apartment_builder.gd # Builds the whole level from data tables (placeholder art)
│   └── audio_manager.gd   # Stubbed sfx/music hooks (prints for now)
├── assets/README.md       # Placeholder-art notes; where real art goes
├── audio/README.md        # Placeholder-audio notes; sfx hook list
└── docs/
    ├── ARCHITECTURE.md    # Scene tree, script responsibilities, state machine, schema
    ├── STORY.md           # The full script, verbatim
    ├── TASKS.md           # Prioritized backlog for future work
    └── AI_HANDOFF.md      # Conventions for the next (AI or human) contributor
```

## How to add a story beat

Everything narrative lives in `scripts/story_data.gd`. To add a beat:

1. Add an entry to `get_beats()`:
```gdscript
"my_beat": {
    "objective": "Find the basement.",   # optional HUD text
    "lines": [
        {"who": "", "text": "The stairs go down further than they should."},
        {"who": "MARA", "text": "Nope.", "sfx": "sting"},  # sfx optional
        {"who": "", "text": "The knife feels useless.", "if": "has_knife"},  # conditional
    ],
    "timer": 5.0,
    "choices": [
        {"text": "Go down", "next": "basement", "set": {"went_down": true},
         "toast": "Mara will remember that."},
        {"text": "Go back", "next": "entry", "default": true},
    ],
},
```
2. Reach it: point an existing beat's `"next"`/choice at `"my_beat"`, or map a new
   `Interactable` id to it in `get_trigger_beats()` and place that interactable in
   `apartment_builder.gd`.

Rules the state machine relies on: every `"next"` target must exist; a choice beat
needs **exactly one** `"default": true` choice (auto-picked on timeout); a beat's
lines are followed by *one* of `choices` / `ending` / `next`. See `docs/AI_HANDOFF.md`
for the full contributor checklist.

## Windows export notes

1. In the editor: **Project → Export…** → **Add…** → **Windows Desktop**.
2. First time only: download the **4.7.2 export templates**
   (the Export dialog offers this automatically, or grab them from the Godot site).
3. Recommended preset settings: 1280×720, runnable `.exe` + `.pck` in `build/`
   (already in `.gitignore`).

## Docs for contributors

Start with `docs/AI_HANDOFF.md` — it's written so any AI (or human) can pick this
project up and keep building without breaking the state machine.
