#!/bin/sh
# Records and edits the OpenShooter trailer.
#
#   tools/trailer/make_trailer.sh [OUTPUT.mp4] [SEGMENTS...]
#
# Each segment is a real match with bots, filmed by TrailerDirector
# (scripts/trailer/trailer_director.gd) through Godot's Movie Maker at a fixed
# 30 fps in 1920x1080, so the result does not depend on the speed of the PC.
# The segments are trimmed, joined with fades, mixed with the original score
# from music.py (game sounds stay underneath) and encoded as H.264 + AAC.
#
# Needs: godot (GODOT env var, default "godot"), ffmpeg, python3 + numpy.
# A game window opens while each segment records; let it finish.
set -eu

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
OUT=${1:-"$ROOT/trailer.mp4"}
shift 2>/dev/null || true
SEGMENTS=${*:-"0 1 2 3 4"}
GODOT=${GODOT:-godot}
WORK=${WORK:-$(mktemp -d)}
FPS=30
XFADE=0.5

# Map recorded by each segment (see SEGMENTS in trailer_director.gd).
map_of() {
	case $1 in
		0) echo 0 ;; 1) echo 1 ;; 2) echo 2 ;; 3) echo 3 ;; *) echo 1 ;;
	esac
}

cleanup() { rm -f "$ROOT/override.cfg"; }
trap cleanup EXIT INT TERM

# Render at 1080p whatever the window size, with high MJPEG quality.
cat > "$ROOT/override.cfg" <<'EOF'
[display]
window/size/viewport_width=1920
window/size/viewport_height=1080
window/stretch/mode="viewport"
[editor]
movie_writer/mjpeg_quality=0.95
EOF

echo "Working directory: $WORK"
for seg in $SEGMENTS; do
	echo "== Recording segment $seg"
	"$GODOT" --path "$ROOT" --write-movie "$WORK/raw_$seg.avi" --fixed-fps $FPS -- \
		--host=normal --map="$(map_of "$seg")" --bots=8 --autoplay --quality=2 \
		--trailer="$seg" > "$WORK/log_$seg.txt" 2>&1 || true
	start=$(sed -n 's/^TRAILER_START_FRAME=//p' "$WORK/log_$seg.txt" | head -1)
	end=$(sed -n 's/^TRAILER_END_FRAME=//p' "$WORK/log_$seg.txt" | head -1)
	if [ -z "$start" ] || [ -z "$end" ]; then
		echo "Segment $seg did not finish; see $WORK/log_$seg.txt" >&2
		exit 1
	fi
	ss=$(echo "$start $FPS" | awk '{printf "%.3f", $1 / $2}')
	dur=$(echo "$start $end $FPS" | awk '{printf "%.3f", ($2 - $1) / $3}')
	ffmpeg -v error -y -ss "$ss" -t "$dur" -i "$WORK/raw_$seg.avi" \
		-vf "fps=$FPS,format=yuv420p" -c:v libx264 -preset slow -crf 14 \
		-af "aresample=48000" -ac 2 -c:a pcm_s16le "$WORK/seg_$seg.mkv"
	rm -f "$WORK/raw_$seg.avi"
done

echo "== Editing"
inputs=""
filter=""
n=0
offset=0
prev_v="0:v"
prev_a="0:a"
for seg in $SEGMENTS; do
	inputs="$inputs -i $WORK/seg_$seg.mkv"
	len=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$WORK/seg_$seg.mkv")
	if [ $n -gt 0 ]; then
		offset=$(echo "$offset $prev_len $XFADE" | awk '{printf "%.3f", $1 + $2 - $3}')
		filter="$filter[$prev_v][$n:v]xfade=transition=fadeblack:duration=$XFADE:offset=$offset[v$n];"
		filter="$filter[$prev_a][$n:a]acrossfade=d=$XFADE[a$n];"
		prev_v="v$n"
		prev_a="a$n"
	else
		offset=0
	fi
	prev_len=$len
	n=$((n + 1))
done
total=$(echo "$offset $prev_len" | awk '{printf "%.3f", $1 + $2}')
echo "Trailer length: ${total}s"

# The opening segment starts with title cards; the score follows them.
INTRO=${INTRO:-7.2}
case " $SEGMENTS " in *" 0 "*) ;; *) INTRO=0 ;; esac
python3 "$ROOT/tools/trailer/music.py" "$WORK/music.wav" --length "$total" --intro "$INTRO" --cards 3

# Game sounds under the score; the score ducks nothing (it leads).
# shellcheck disable=SC2086
ffmpeg -v error -y $inputs -i "$WORK/music.wav" -filter_complex \
	"${filter}[$prev_v]null[vout];[$prev_a]volume=0.38,highpass=f=60[game];[$n:a]volume=1.0[score];[score][game]amix=inputs=2:normalize=0,alimiter=limit=0.95[mix]" \
	-map "[vout]" -map "[mix]" -c:v libx264 -preset slow -crf 17 -pix_fmt yuv420p \
	-movflags +faststart -c:a aac -b:a 256k -t "$total" "$OUT"
echo "Trailer written to $OUT"
