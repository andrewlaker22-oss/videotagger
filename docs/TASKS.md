# TASKS — AI-friendly backlog for WATCHED

Ordered by priority. Each item is sized so one contributor (AI or human) can
pick it up without reading the whole codebase — start at `docs/AI_HANDOFF.md`.

## P0 — makes the prototype shippable
- [ ] **Real art pass.** Replace primitive boxes with modeled assets (see
      `assets/README.md`). Keep the same `Interactable` positions/ids so the
      story keeps working. Suggested: block out in Blender, export `.glb`.
- [ ] **Real audio pass.** Implement `audio_manager.gd` TODOs (sfx pool + music
      player) and add files per `audio/README.md`. Priority sounds: phone ring,
      door rattle, power-cut thump, ending sting, ambient drone loop.
- [ ] **Exploration gating.** Right now beats can be triggered out of order
      (e.g. bathroom before the note). Add optional `"requires"` flag lists to
      beats / interactables so the story paces correctly.
- [ ] **Playtest the full 10 minutes.** Time a real playthrough; if it's under
      ~7 minutes, add 1–2 exploration beats (TASKS P1 has candidates).

## P1 — story & systems depth
- [ ] **More endings / variations.** The `CONFRONT` text already varies with
      `has_knife` — extend: `answered_phone` vs `ignored_phone` changes the
      blackout beat; `called_police` pays off in an ending.
- [ ] **Second story chapter.** New room (fire escape / hallway extension) via
      `apartment_builder.gd`; new beats in `story_data.gd`. No manager changes needed.
- [ ] **Save system.** Persist `flags` + current objective to disk; "Continue"
      from a minimal title screen.
- [ ] **Settings + pause menu.** Mouse sensitivity, volume sliders, Esc menu.
      (Esc currently just releases the mouse.)
- [ ] **Subtitles/accessibility.** Toggle for auto-advancing dialogue, larger text,
      high-contrast choice UI.

## P2 — polish
- [ ] **Character presence.** The stalker is never seen (by design) — but add
      *evidence*: a coat that wasn't there, a moved chair, breath fog. Cheap scares.
- [ ] **Camera work.** Subtle idle sway, scripted push-ins on key lines, shake on scares.
- [ ] **Main menu + title screen.** "WATCHED" logo, New Game / Continue, content note.
- [ ] **Windows installer / itch.io page.** Export preset + publishing checklist.
- [ ] **Localization.** All strings are in `story_data.gd` already — extract to
      translation files.

## P3 — nice-to-haves
- [ ] Voice acting hooks (line-level `voice` key next to `sfx`).
- [ ] Controller support.
- [ ] Photo mode / screenshot key for sharing endings.
- [ ] Analytics-free playtest logging (which choices players pick).

## Done
- [x] Prototype: two-story house + basement level, 17 story beats (incl. basement breaker), timed choices, 3 endings, docs, repo scaffold.
