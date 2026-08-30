#!/usr/bin/env bash
# Builds the signed AAB for Google Play.
#
# The keystore credentials are requested here and passed to Godot only as
# environment variables. They are not stored in export_presets.cfg or the
# shell history. Godot reads these variables when the keystore/release*
# fields in the preset are empty.
set -euo pipefail

PRESET="Android Release (AAB)"
OUT="build/android/CoffeeHunter.aab"
KEYSTORE="${KEYSTORE:-$HOME/coffee-hunter-release.keystore}"

cd "$(dirname "$0")/.."

[[ -f "$KEYSTORE" ]] || { echo "Keystore not found: $KEYSTORE" >&2; exit 1; }

read -rp "Keystore alias: " ALIAS
read -rsp "Keystore password: " PW; echo

# Check early so the full Gradle build does not run before signing fails.
keytool -list -keystore "$KEYSTORE" -alias "$ALIAS" -storepass "$PW" >/dev/null \
  || { echo "Incorrect alias or password." >&2; exit 1; }

export GODOT_ANDROID_KEYSTORE_RELEASE_PATH="$KEYSTORE"
export GODOT_ANDROID_KEYSTORE_RELEASE_USER="$ALIAS"
export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD="$PW"

mkdir -p "$(dirname "$OUT")"
rm -f "$OUT"
godot --headless --path . --export-release "$PRESET" "$OUT"

[[ -f "$OUT" ]] || { echo "Export did not produce a file." >&2; exit 1; }
echo
echo "Done: $OUT ($(du -h "$OUT" | cut -f1))"
echo "versionCode: $(grep -A2 '^\[preset.5.options\]' -A99 export_presets.cfg | grep -m1 '^version/code=' | cut -d= -f2)"
