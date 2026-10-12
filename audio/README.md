# Audio — placeholder (stubbed)

There are **no binary audio files** in the repo. `scripts/audio_manager.gd`
exposes `play_sfx(name)`, `play_music(name)`, and `stop_music()`; right now they
just `print()` so you can see every hook firing in the output log.

## sfx names the game currently requests

| Hook | When |
|---|---|
| `interact` | Player triggers any interactable |
| `ui_select` | A dialogue choice is picked (or auto-picked) |
| `phone_ring` | The unknown-number call (line-level `sfx` in the `note` beat) |
| `door_rattle` | The blackout beat (line-level `sfx`) |
| `power_cut` | The blackout beat (effect) |
| `sting` | Ending screen appears |

## Wiring real audio

1. Drop files in `audio/sfx/<name>.ogg` and `audio/music/<name>.ogg`
   (`.ogg` preferred; keep names exactly matching the hooks above).
2. Implement the `TODO(audio)` items in `scripts/audio_manager.gd`:
   a small `AudioStreamPlayer` pool for sfx + one dedicated music player,
   with a `Dictionary` cache keyed by hook name.
3. Suggested first sounds: phone ring, door rattle, power-cut thump, low
   ambient drone loop for exploration, sting for endings.

## Guidelines

- Psychological horror = restraint. Silence and near-silence are instruments;
  don't fill every second.
- Keep the mix quiet enough that dialogue (future voice acting) would sit on top.
