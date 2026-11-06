#!/bin/sh
# Stage the normalized PNG on RCC before Java publishes its /net/rcc locator.
set -u
MODE="${1:-}"
if [ "$MODE" = --rcc ]; then TOKEN="${2:-}"; else TOKEN="$MODE"; fi
case "$TOKEN" in ''|*[!0-9-]*) exit 64 ;; esac
ROOT=""
LIMIT=8
if [ -n "${ART_TEST_ROOT:-}" ]; then
    [ -f "$ART_TEST_ROOT/.art-fixture" ] || exit 64
    ROOT="$ART_TEST_ROOT"
    LIMIT="${ART_TEST_TIMEOUT:-1}"
fi
if [ "$MODE" = --rcc ]; then
    BASE="$ROOT/dev/shmem"
    if [ -z "$ROOT" ]; then
        # Do not inherit MMX application paths into the RCC shell.
        export PATH=/bin:/usr/bin:/sbin:/usr/sbin:/proc/boot:/usr/apps
        unset LD_PRELOAD
        export LD_LIBRARY_PATH=/lib:/usr/lib:/opt/sys/lib
    fi
else
    BASE="$ROOT/ramdisk/carplay-cluster-artwork-fix1"
fi
umask 022
if [ "$MODE" = --rcc ]; then
    # QNX shared memory is flat: no mkdir or rename operations here.
    [ -d "$BASE" ] || exit 65
    LOG="$ROOT/net/mmx/ramdisk/carplay-cluster-artwork-fix1/publish-rcc.log"
else
    mkdir -p "$BASE" || exit 65
    chmod 755 "$BASE" || exit 72
    LOG="$BASE/publish.log"
fi
log() {
    if [ -f "$LOG" ]; then
        line=$(ls -ln "$LOG" 2>/dev/null); set -- $line
        [ "${5:-0}" -lt 65536 ] || return 0
    fi
    echo "token=$TOKEN mode=$MODE $MESSAGE" >> "$LOG"
}
CHILD=""
WATCH=""
TEMP=""
cleanup() {
    [ -z "$CHILD" ] || kill -KILL "$CHILD" 2>/dev/null || true
    [ -z "$WATCH" ] || kill "$WATCH" 2>/dev/null || true
    [ -z "$TEMP" ] || rm -f "$TEMP"
}
trap cleanup 0
trap 'exit 130' 1 2 15
bounded() {
    "$@" >> "$LOG" 2>&1 &
    CHILD=$!
    (
        TIMER=""
        trap '[ -z "$TIMER" ] || kill "$TIMER" 2>/dev/null; exit 0' 1 2 15
        sleep "$LIMIT" & TIMER=$!
        wait "$TIMER"; TIMER=""
        kill -TERM "$CHILD" 2>/dev/null || exit 0
        sleep 1
        kill -KILL "$CHILD" 2>/dev/null || true
    ) >/dev/null 2>&1 &
    WATCH=$!
    wait "$CHILD"
    result=$?
    CHILD=""
    kill "$WATCH" 2>/dev/null || true
    wait "$WATCH" 2>/dev/null || true
    WATCH=""
    return "$result"
}
if [ "$MODE" != --rcc ]; then
    [ -n "$ROOT" ] || [ -s /ifs/lsd.jxe ] || exit 64
    INPUT="$BASE/cover-$TOKEN.png"
    [ -s "$INPUT" ] || exit 66
    chmod 644 "$INPUT" || exit 66
    ON=$(command -v on 2>/dev/null) || exit 67
    unset LD_PRELOAD
    if [ -z "$ROOT" ]; then export LD_LIBRARY_PATH=/lib:/usr/lib:/opt/sys/lib; fi
    REMOTE="/net/mmx/mnt/app/carplaymaps/cluster-artwork-publish.sh"
    [ -z "$ROOT" ] || REMOTE="$ROOT/remote-publish.sh"
    if [ -z "$ROOT" ]; then LIMIT=14; else LIMIT="${ART_TEST_TIMEOUT:-1}"; fi
    bounded "$ON" -f rcc /bin/sh "$REMOTE" --rcc "$TOKEN"
    result=$?
    MESSAGE="dispatch_exit=$result"; log
    exit "$result"
fi
umask 022
# On RCC, this is a local /dev/shmem image. Native getPicture removes /net/rcc.
SOURCE="$ROOT/net/mmx/ramdisk/carplay-cluster-artwork-fix1/cover-$TOKEN.png"
TARGET="$BASE/carplay-cluster-artwork-fix3-cover-$TOKEN.png"
# The unique file is not advertised until its complete contents are verified.
# Avoid rename: /dev/shmem is not a normal filesystem.
TEMP="$TARGET"
[ -s "$SOURCE" ] || exit 66
line=$(ls -ln "$SOURCE" 2>/dev/null); set -- $line
[ "${5:-0}" -ge 80 ] && [ "${5:-0}" -le 43000 ] || exit 68
# Copy to an unpublished unique name. Remove partial files on any failure.
if ! bounded cp "$SOURCE" "$TEMP"; then MESSAGE="copy_failed"; log; exit 69; fi
source_sum=$(cksum "$SOURCE") || exit 69
set -- $source_sum
SOURCE_CRC="${1:-}"; SOURCE_SIZE="${2:-}"
local_sum=$(cksum "$TEMP") || exit 69
set -- $local_sum
[ "$SOURCE_CRC:$SOURCE_SIZE" = "${1:-}:${2:-}" ] || exit 70
chmod 644 "$TEMP" || exit 71
TEMP=""
# Keep the displayed cover even through several stale fetch completions.
RETAINED=""
PIN="$ROOT/net/mmx/ramdisk/carplay-native-artwork/retained-cover"
if [ -f "$PIN" ]; then read RETAINED < "$PIN" || RETAINED=""; fi
# Retain three recent images plus the currently displayed cover and blank marker.
count=0
for file in $(ls -t "$BASE"/carplay-cluster-artwork-fix3-cover-*.png 2>/dev/null); do
    [ "$file" != "$TARGET" ] || continue
    [ "$file" != "$BASE/carplay-cluster-artwork-fix3-cover-0-0-0.png" ] || continue
    [ "$file" != "$BASE/$RETAINED" ] || continue
    count=$((count + 1))
    [ "$count" -le 2 ] || rm -f "$file"
done
MESSAGE="published_local=$TARGET bytes=$SOURCE_SIZE crc=$SOURCE_CRC"; log
exit 0
