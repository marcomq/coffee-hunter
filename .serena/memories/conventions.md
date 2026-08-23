# Conventions
- Keep gameplay rules in the pure RefCounted `GameState`; UI, TileMapLayer, sprites, tweens and input polling belong in `main.gd`.
- Represent logical positions and directions as `Vector2i`; index grid cells row-major.
- Normalize keyboard, virtual tilt and future gravity sensor input through `InputResolver`; preserve deadzone and hysteresis behavior.
- New level palettes should change visual theme data/assets, not grid rules.
- Use one calm continuous background per level, never a visibly repeated ground tile; tunnels remain runtime overlays.
- Do not couple world progress to player input: player, enemy, and falling hazards retain independent timers.
- Preserve `original/` unchanged. New art must not import legacy assets; record generated art prompts/provenance in `docs/art/`.
- Prefer explicit GDScript types when inference across typed arrays or Variant values is ambiguous.