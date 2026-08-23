# Coffee Hunter prototype

Godot 4.7.2 vertical slice of the original Java applet in `original/`.

## Run

```sh
godot --editor project.godot
godot --path .
```

Controls: WASD or arrow keys. Hold and drag the left mouse button to simulate device tilt. Press `R` to restart.

The level runs continuously: enemies and falling filters use independent realtime clocks instead of advancing only when the player moves.

On macOS the game opens at 1440x810 by default while retaining its 960x540 internal canvas.

## Verify

```sh
godot --headless --path . --script tests/run_tests.gd
godot --headless --path . --editor --quit
godot --headless --path . --export-release macOS "build/Coffee Hunter.app"
```

Generated project assets and their final prompts are documented in `docs/art/asset-prompts.md`.
The first macOS size measurement is recorded in `docs/build-baseline.md`.
