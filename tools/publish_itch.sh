#!/usr/bin/env sh
# Exports the Windows build and uploads it to itch.io with butler.
#
# One-time setup (see docs/release.md):
#   - install butler and run `butler login`, or set BUTLER_API_KEY in your
#     shell (never in a file in this repo)
#   - set ITCH_TARGET to "<itch user>/<game slug>", e.g. "someone/car-town-revival"
#
# Usage: ITCH_TARGET=user/game tools/publish_itch.sh
set -e
cd "$(dirname "$0")/.."
GODOT="${GODOT_BIN:-_reference/tools/godot/Godot_v4.7.2-stable_win64_console.exe}"
if [ -z "$ITCH_TARGET" ]; then
	echo "Set ITCH_TARGET to <itch user>/<game slug>." >&2
	exit 1
fi
VERSION=$(sed -n 's/^config\/version="\(.*\)"$/\1/p' project.godot)
echo "Testing..."
sh tools/run_tests.sh | grep -q "0 errors | 0 failures" || { echo "Tests failed." >&2; exit 1; }
echo "Exporting v$VERSION..."
rm -rf build/windows
mkdir -p build/windows
"$GODOT" --headless --path . --export-release "Windows Desktop" build/windows/CarTownRevival.exe
cp CREDITS.md build/windows/
echo "Uploading to $ITCH_TARGET:windows..."
butler push build/windows "$ITCH_TARGET:windows" --userversion "$VERSION"
butler status "$ITCH_TARGET:windows"
