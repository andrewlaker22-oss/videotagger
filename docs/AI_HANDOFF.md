# AI_HANDOFF — conventions for the next contributor

You're picking up **WATCHED**, a Godot 4.7.2 narrative-horror prototype. This file
tells you how to change things without breaking them. Read it before your first edit.

## The one rule

**Story content lives in `scripts/story_data.gd`. Behavior lives in the scripts.
Never mix them.** Writers edit dictionaries; programmers edit functions. If you
find yourself writing dialogue inside `game_manager.gd`, stop — you're in the
wrong file.

## Coding style

- **GDScript, typed.** `var x: int`, `func f() -> void`. Every script has
  `class_name`. Tabs for indentation (Godot convention).
- **Godot 4.x APIs only.** No Godot 3-isms (`yield`, `export var` without `@`, …).
- **No hand-written `load_steps`** in `.tscn` files (deprecated since 4.6).
  `main.tscn` is minimal on purpose — prefer building things in code from data
  tables (see `apartment_builder.gd`) over giant scene files.
- Signals are past-tense nouns (`choice_selected`, `focus_changed`,
  `primary_action`). The Player emits raw input; the GameManager routes it.
- Keep the architecture small. New feature? Prefer: data table → one function →
  docs update. Don't add autoloads or plugins for prototype-scale needs.

## Adding story content safely

1. New beat? Add it to `get_beats()` following the schema in the comment block
   at the top of `story_data.gd` (also in `docs/ARCHITECTURE.md`).
2. New choice? It needs `"text"`, `"next"`, and the beat needs **exactly one**
   `"default": true` (timeout auto-pick).
3. New flag? Name it clearly (`has_knife`, not `f1`), set it via choice `"set"`,
   read it via line `"if"`/`"if_not"`, and add the beat to `docs/STORY.md`.
4. New interactable? `interact_id` must match a key in `get_trigger_beats()`;
   place it in `_build_interactables()` in `apartment_builder.gd`.
5. New beat effect? Add the string to `_apply_effect()` in `game_manager.gd`
   AND document it in the `story_data.gd` schema comment.

## What not to touch (without a good reason)

- The state transitions in `game_manager.gd` (`EXPLORE → DIALOGUE → CHOICE → ENDING`).
  Everything — input routing, mouse capture, toasts — hangs off them.
- `main.tscn` node names/paths (`$Player`, `$DialogueUI`, `$Apartment`,
  `$AudioManager`, `$WorldEnvironment`) — scripts reference them via `@onready`.
- The `WALLS` table coordinates unless you re-check door gaps and the player
  capsule (r=0.35) still fits through them.

## How to validate (do this before you call anything "done")

```bash
# From this folder, with the Godot 4.7.2 headless binary:
/tmp/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --import   # run TWICE
/tmp/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --import   # (first run builds class cache)
```

- Fix **every** `SCRIPT ERROR` / `Parse Error` the import reports. A clean import
  prints no errors.
- Story-data integrity check: every `"next"`/choice target and every
  `get_trigger_beats()` value must exist in `get_beats()`; every choice beat
  needs exactly one default. (There's no automated checker yet — eyeball it, or
  write one; that'd be a nice TASKS.md contribution.)
- Play it: F5 in the editor, or export per README. Reach all three endings.

## Docs discipline

This project is *documentation-first* because the next contributor might be an AI
with no memory of your work. When you change behavior or content, update:

- `docs/STORY.md` — any dialogue/choice/ending change, verbatim.
- `docs/ARCHITECTURE.md` — any new script, state, effect, or data-flow change.
- `docs/TASKS.md` — check off what's done; add what you discovered.
- `README.md` — only if controls, setup, or structure changed.

If the docs and the code disagree, the docs are wrong — fix the docs.
