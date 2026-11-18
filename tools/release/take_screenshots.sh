#!/usr/bin/env bash
# Takes the README screenshots (docs/screenshots/) from the running game,
# one Godot window per picture, using the game's own test options
# (--screen, --host, --shot; see scripts/main.gd).
#
#   tools/release/take_screenshots.sh [GODOT] [OUT_DIR]
#
# GODOT defaults to "godot" on the PATH, OUT_DIR to docs/screenshots.
# Close any running OpenShooter first: a hosted match needs the game port.
#
# Not covered (they need a moment that the options cannot reach, take them by
# hand): splash.png, credits.png, loading.png, scoreboard.png, vote.png.
set -euo pipefail

GODOT="${1:-godot}"
OUT="${2:-docs/screenshots}"
cd "$(dirname "$0")/../.."
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"

# Same player name in every picture.
COMMON=(--name=Player)

shot() {
	local file="$1"
	shift
	echo "  $file"
	"$GODOT" --path . -- "${COMMON[@]}" "$@" --shot="$OUT/$file" >/dev/null 2>&1 \
		|| echo "    failed (is another OpenShooter running?)"
}

echo "Menus"
shot home.png --wait=4
shot modes.png --screen=Modes --wait=3
shot browser.png --screen=Browser:normal --wait=3
shot create.png --screen=Create --wait=3
shot private.png --screen=Private --wait=3
shot locker.png --screen=Locker --wait=3
shot settings.png --screen=Settings --wait=3
shot stats.png --screen=Stats --wait=3

echo "Match"
shot hud.png --host=normal --bots=5 --map=1 --wait=12
shot mobile.png --host=normal --bots=5 --map=0 --touch --wait=7

echo "Saved in $OUT"
