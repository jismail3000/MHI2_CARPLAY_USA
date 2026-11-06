#!/bin/sh
# One request from the Java worker. Uses only the stock native artwork query.
set -u
TOKEN="${1:-}"
case "$TOKEN" in ''|*[!0-9-]*) exit 64 ;; esac
FSROOT=""
LIMIT=6
if [ -n "${NATIVEART_TEST_ROOT:-}" ]; then
    [ -f "$NATIVEART_TEST_ROOT/.nativeart-test-fixture" ] || exit 64
    FSROOT="$NATIVEART_TEST_ROOT"
    LIMIT="${NATIVEART_TEST_TIMEOUT:-1}"
else
    [ -s /ifs/lsd.jxe ] || exit 64
fi
BASE="$FSROOT/ramdisk/carplay-native-artwork"
LOG="$FSROOT/ramdisk/carplay-native-artwork-fetch.log"
mkdir -p "$BASE" || exit 64
RESULT="$BASE/fetch-$TOKEN.bin"
RAW="$BASE/last-native-command.txt"
CHILD=""
WATCH=""
cleanup() {
    [ -z "$CHILD" ] || kill -KILL "$CHILD" 2>/dev/null || true
    [ -z "$WATCH" ] || kill "$WATCH" 2>/dev/null || true
}
trap cleanup 0
trap 'exit 130' 1 2 15
log() {
    message="$*"
    if [ -f "$LOG" ]; then
        line=$(ls -ln "$LOG" 2>/dev/null); set -- $line
        [ "${5:-0}" -lt 262144 ] || return 0
    fi
    echo "token=$TOKEN $message" >> "$LOG"
}
unset LD_PRELOAD
if [ -z "$FSROOT" ]; then
    export LD_LIBRARY_PATH=/mnt/app/armle/lib:/mnt/app/armle/usr/lib:/mnt/app/armle/lib/dll:/armle/usr/lib:/eso/lib:/mnt/app/eso/lib
fi
CLI=""
for candidate in "$FSROOT/armle/usr/bin/iap2cli" "$FSROOT/mnt/app/armle/usr/bin/iap2cli"; do
    if [ -x "$candidate" ]; then CLI="$candidate"; break; fi
done
[ -n "$CLI" ] || { log "result=missing-cli"; exit 65; }
devices=0
failure=66
for device in "$FSROOT"/dev/ipod*; do
    [ -e "$device" ] || continue
    [ "$devices" -lt 2 ] || break
    devices=$((devices + 1))
    rm -f "$RESULT" "$BASE/timeout-$TOKEN"
    (
        ulimit -f 8192 2>/dev/null || true
        exec "$CLI" -m "$device" artwork "$RESULT"
    ) > "$RAW" 2>&1 &
    CHILD=$!
    (
        TIMER=""
        trap '[ -z "$TIMER" ] || kill "$TIMER" 2>/dev/null; exit 0' 1 2 15
        sleep "$LIMIT" &
        TIMER=$!
        wait "$TIMER"
        TIMER=""
        if kill -0 "$CHILD" 2>/dev/null; then
            echo timeout > "$BASE/timeout-$TOKEN"
            kill -TERM "$CHILD" 2>/dev/null || true
            sleep 1
            kill -KILL "$CHILD" 2>/dev/null || true
        fi
    ) >/dev/null 2>&1 &
    WATCH=$!
    wait "$CHILD"
    rc=$?
    CHILD=""
    kill "$WATCH" 2>/dev/null || true
    wait "$WATCH" 2>/dev/null || true
    WATCH=""
    log "device=$device native_exit=$rc"
    # Keep command details bounded independently of track/session frequency.
    if [ -f "$LOG" ]; then
        line=$(ls -ln "$LOG" 2>/dev/null); set -- $line
        [ "${5:-0}" -ge 262144 ] || dd "if=$RAW" bs=1024 count=4 >> "$LOG" 2>/dev/null
    fi
    if [ -f "$BASE/timeout-$TOKEN" ]; then
        failure=68
        log "result=timeout"
        rm -f "$BASE/timeout-$TOKEN" "$RESULT"
        continue
    fi
    if [ "$rc" -ne 0 ]; then
        failure=67
        log "result=native-error"
        rm -f "$RESULT"
        continue
    fi
    if [ -s "$RESULT" ]; then
        line=$(ls -ln "$RESULT" 2>/dev/null); set -- $line
        if [ "${5:-0}" -le 2097152 ]; then
            log "result=bytes-retrieved bytes=${5:-0}"
            exit 0
        fi
        failure=69
        log "result=oversize"
        rm -f "$RESULT"
    else
        log "result=empty"
    fi
done
[ "$devices" -ne 0 ] || log "result=no-ipod-endpoint"
exit "$failure"
