# Task completion
- Run `godot --headless --path . --script tests/run_tests.gd`; require exit 0 and PASS output.
- Run `godot --headless --path . --quit-after 10`; require no script/runtime errors.
- For visual changes, record a normal Compatibility-renderer frame and inspect at 960x540; headless movie rendering uses a dummy renderer and can crash on macOS.
- For release-affecting changes, export macOS and launch the exported binary headless for a smoke test.
- Keep build-size measurements in `docs/build-baseline.md` when dependencies or exported assets change.