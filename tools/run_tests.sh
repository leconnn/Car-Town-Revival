#!/usr/bin/env sh
# Runs the gdUnit4 test suite headless.
# Uses $GODOT_BIN, or the portable Godot in _reference/tools/godot/.
# Usage: tools/run_tests.sh [res://tests/some_folder_or_file]
cd "$(dirname "$0")/.." || exit 1
GODOT="${GODOT_BIN:-_reference/tools/godot/Godot_v4.7.2-stable_win64_console.exe}"
TARGET="${1:-res://tests}"
"$GODOT" --headless --path . -s -d --remote-debug tcp://127.0.0.1:0 \
  res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a "$TARGET" --ignoreHeadlessMode 2>&1 \
  | sed 's/\x1b\[[0-9;]*m//g' | grep -v "Remote Debugger\|remote port" | grep -E "FAILED|Expecting|but was|at '|ERROR|SCRIPT ERROR|Parse Error|Overall Summary|Executed test"
