#!/usr/bin/env sh
# Starts a headless LAN host and runs two guests against it:
# one on the same version (must join and play), one on another (must be refused).
cd "$(dirname "$0")/.." || exit 1
GODOT="${GODOT_BIN:-_reference/tools/godot/Godot_v4.7.2-stable_win64_console.exe}"
"$GODOT" --headless --path . res://scenes/dev/lan_smoke.tscn -- role=host dir=user://lan_smoke_$(date +%s) > /tmp/lan_host.log 2>&1 &
HOST=$!
sleep 4
"$GODOT" --headless --path . res://scenes/dev/lan_smoke.tscn -- role=guest 2>&1 | grep -E "PASS|FAIL|ERROR"
"$GODOT" --headless --path . res://scenes/dev/lan_smoke.tscn -- role=guest version=0.0.1 expect=reject 2>&1 | grep -E "PASS|FAIL|ERROR"
kill $HOST 2>/dev/null
grep -E "HOST|ERROR" /tmp/lan_host.log
