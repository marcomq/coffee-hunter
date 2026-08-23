# Suggested commands
- Run editor: `godot --editor project.godot`
- Run game: `godot --path .`
- Logic tests: `godot --headless --path . --script tests/run_tests.gd`
- Parse/runtime smoke test: `godot --headless --path . --quit-after 10`
- Export macOS: `godot --headless --path . --export-release macOS "build/Coffee Hunter.app"`
- On managed/sandboxed hosts, Godot needs permission to write its normal data/import cache under Library/Application Support.