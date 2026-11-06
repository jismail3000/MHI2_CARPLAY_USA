#!/bin/ksh
# Save all installer and snapshot output, including early failures, on the SD.
# The test override is restricted to an explicit fixture with the firmware file.
LOGFILE=""
if [ -n "${CPMAP_TEST_ROOT:-}" ] && [ -s "$CPMAP_TEST_ROOT/ifs/lsd.jxe" ]; then
    MEDIA="$CPMAP_TEST_ROOT/sd"
    mkdir -p "$MEDIA/Log" && LOGFILE="$MEDIA/Log/cpmap-vcsettings-install.txt"
else
    for medium in /fs/sda0 /fs/sdb0 /net/mmx/fs/sda0 /net/mmx/fs/sdb0 /media/mp000 /media/mp001 /media/mp002; do
        if [ -s "$medium/Custom/carplay_maps_vc/payload/common/install-carplay-maps.sh" ]; then
            # A failed redirection on the special builtin : can terminate QNX ksh.
            # Probe in a subshell so a read-only SD reaches the RAM fallback.
            if mkdir -p "$medium/Log" && ( : > "$medium/Log/.vcsettings-write-test" ) 2>/dev/null; then
                rm -f "$medium/Log/.vcsettings-write-test"
                LOGFILE="$medium/Log/cpmap-vcsettings-install.txt"
                break
            fi
        fi
    done
fi
if [ -z "$LOGFILE" ]; then
    LOGFILE=/ramdisk/cpmap-vcsettings-install.txt
    [ -d /ramdisk ] || LOGFILE=/net/mmx/ramdisk/cpmap-vcsettings-install.txt
fi
run_install() {
    echo "NAR VC settings + album art"
    SCRIPTS=/mnt/app/eso/hmi/engdefs/scripts/mqb
    [ -s "$SCRIPTS/cpmap_common.sh" ] || SCRIPTS=/net/mmx/mnt/app/eso/hmi/engdefs/scripts/mqb
    [ -s "$SCRIPTS/cpmap_common.sh" ] || { echo "VCSETTINGS_FAIL=TOOLBOX_COMMON_MISSING"; return 1; }
    . "$SCRIPTS/cpmap_common.sh" || return 1
    find_cpmap_payload || return 1
    detect_cpmap_mu || return 1
    echo "Payload: $CPMAP_PAYLOAD"
    echo "Detected firmware: $CPMAP_MU"
    [ "$CPMAP_MU" = MU1126 ] || { echo "FAIL: MU1126 US required"; return 1; }
    [ -s "$SCRIPTS/cpmap_vcsettings_snapshot.sh" ] || { echo "VCSETTINGS_FAIL=SNAPSHOT_SCRIPT_MISSING_UPDATE_TOOLBOX"; return 1; }
    echo "Step: save pre-installation setup"
    /bin/ksh "$SCRIPTS/cpmap_vcsettings_snapshot.sh" backup || return $?
    echo "Step: install VC settings + album art payload"
    /bin/ksh "$CPMAP_PAYLOAD/common/install-carplay-maps.sh" "$CPMAP_PAYLOAD" MU1126 891
    INSTALL_RESULT=$?
    if [ "$INSTALL_RESULT" -eq 0 ]; then
        /bin/ksh "$SCRIPTS/cpmap_vcsettings_snapshot.sh" commit || return 1
    else
        echo "VCSETTINGS_BACKUP=PENDING_RETAINED_FOR_RECOVERY"
        return "$INSTALL_RESULT"
    fi
}
echo "Running NAR Volkswagen CarPlay Maps VC installer; output is being saved to $LOGFILE"
if ! ( : >> "$LOGFILE" ); then
    echo "VCSETTINGS_FAIL=CANNOT_SAVE_INSTALL_LOG"
    exit 1
fi
# Append each attempt; runtime log export does not overwrite this file.
echo "===== NAR VOLKSWAGEN CARPLAY MAPS VC INSTALL ATTEMPT =====" >> "$LOGFILE"
(run_install) >> "$LOGFILE" 2>&1
RESULT=$?
echo "VCSETTINGS_INSTALL_EXIT=$RESULT" >> "$LOGFILE"
if [ "$RESULT" -eq 0 ]; then
    # Print the final success/reboot messages after the status and log path.
    sed '/^CPMAP_INSTALL_OK$/d; /^A full unit reboot is required\.$/d' "$LOGFILE"
    echo "Installer output saved: $LOGFILE"
    echo "CPMAP_INSTALL_OK"
    echo "A full unit reboot is required."
else
    cat "$LOGFILE"
    echo "Installer output saved: $LOGFILE"
fi
exit "$RESULT"
