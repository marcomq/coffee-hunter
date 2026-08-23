# Build baseline

Measured on 2026-08-22 with Godot 4.7.2 Standard and the Compatibility renderer.

| Artifact | Size |
| --- | ---: |
| macOS universal app bundle | 168 MB |
| Packed project data (`.pck`) | 5.7 MB |

The universal bundle contains both Apple Silicon and Intel engine binaries. The `.pck` increased after replacing the repeated ground tile with a full-board generated background, but remains small compared with the engine runtime.

Verification performed:

- Headless logic test suite passes.
- Main scene starts without runtime errors.
- Normal Compatibility-renderer capture completes at fixed 60 FPS.
- Exported app binary starts successfully.

Gameplay timing after the realtime pass:

- Player grid step: 0.42 s with eased visual interpolation.
- Enemy step: independent 0.95 s timer.
- Falling-filter step: independent 0.68 s timer.

This is a development baseline, not a signed/notarized distribution-size measurement. Store compression and an architecture-specific build will differ.
