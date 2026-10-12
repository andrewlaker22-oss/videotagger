# Assets — placeholder art

Everything visual in this prototype is **procedural placeholder**: boxes, quads,
and flat `StandardMaterial3D`s built in code by `scripts/apartment_builder.gd`.
There are intentionally **no binary art files** in the repo yet.

## Replacing placeholders with real art

1. Put models/textures under `assets/` (e.g. `assets/models/fridge.glb`,
   `assets/textures/wall_paper.png`). Keep paths stable — they're referenced by code.
2. In `apartment_builder.gd`, swap a `_add_box(...)` call for a `load()` of your
   asset. Keep the **same position/rotation** and, critically, keep the
   `Interactable` nodes where they are — the story triggers by `interact_id`
   (`fridge_note`, `bedroom_photo`, `bedroom_closet`, `bathroom_mirror`,
   `kitchen_knife`), not by meshes.
3. Collision: real meshes need a `StaticBody3D` + `CollisionShape3D` like the
   boxes have now (or use Godot's mesh → collision generation in the editor).

## Guidelines

- Keep the floor plan in `apartment_builder.gd`'s `WALLS` table unless you
  re-verify the player capsule (r=0.35) fits through every door gap.
- Horror lighting does the heavy lifting: dim, warm/cool contrast, fog.
  Don't "fix" the darkness — it's the art direction.
- `.glb` preferred for models; keep textures power-of-two.
