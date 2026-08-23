# Tech stack
- Godot 4.7.2 Standard (not .NET), GDScript, Compatibility renderer.
- macOS is the validated prototype target; Android/iOS sensors are a later milestone.
- Runtime art is generated SNES-style PNG with nearest-neighbor canvas filtering; source art is under `assets/art/source/`, 48 px game tiles under `assets/art/game/`.
- macOS export uses official Godot 4.7.2 templates and `export_presets.cfg`.