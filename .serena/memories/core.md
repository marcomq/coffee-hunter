# Coffee Hunter 2
- Godot rewrite lives at repository root; immutable legacy reference is under `original/` and is never consumed by the new project.
- Main scene: `scenes/main.tscn`; presentation/orchestration: `scripts/main.gd`; pure grid rules: `scripts/game_state.gd`; input normalization: `scripts/input_resolver.gd`.
- 17x11 logical grid, 48 px cells, 960x540 internal landscape viewport; game state must remain independent of rendering.
- Generated visual direction/provenance is in `docs/art/`.
- Each level uses one continuous full-board background image; dug cells are a separate dark TileMapLayer overlay.
- Player, enemy, and falling-filter motion run on independent realtime clocks and are visually interpolated.
- Toolchain and pinned versions: `mem:tech_stack`. Project-specific coding patterns: `mem:conventions`. Commands: `mem:suggested_commands`. Completion checks: `mem:task_completion`.