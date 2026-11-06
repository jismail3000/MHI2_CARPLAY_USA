#!/bin/ksh
# Save the setup immediately before the latest successful installation.
set -u
MODE="${1:-}"
case "$MODE" in backup|commit|abort|restore) ;; *) exit 64 ;; esac
if [ -n "${CPMAP_TEST_ROOT:-}" ] && [ -s "$CPMAP_TEST_ROOT/ifs/lsd.jxe" ]; then MMX="$CPMAP_TEST_ROOT"
elif [ -s /ifs/lsd.jxe ]; then MMX=""
elif [ -s /net/mmx/ifs/lsd.jxe ]; then MMX=/net/mmx
else echo "VCSETTINGS_FAIL=MMX_NOT_FOUND"; exit 1; fi
line=$(ls -ln "$MMX/ifs/lsd.jxe"); set -- $line
[ "${5:-0}" = 54248171 ] || { echo "VCSETTINGS_FAIL=MU1126_REQUIRED"; exit 1; }
[ ! -e "$MMX/dev/ipod0" ] || { echo "VCSETTINGS_FAIL=DISCONNECT_CARPLAY"; exit 1; }
APP="$MMX/mnt/app"
ROOT="$APP/carplaymaps"
SNAP="$APP/carplaymaps-vcsettings-before"
PENDING="$SNAP.pending"
IPOD="$APP/armle/usr/sbin/mm-ipod"
JARS="$APP/eso/hmi/lsd/jars"
LSD="$APP/eso/hmi/lsd/lsd.sh"
DIO="$APP/eso/bin/apps/dio_manager"
if [ -z "${CPMAP_TEST_ROOT:-}" ]; then
    if [ -n "$MMX" ]; then on -f mmx mount -uw /mnt/app || exit 1
    else mount -uw /mnt/app || exit 1; fi
fi
if [ "$MODE" = abort ]; then
    rm -rf "$PENDING" || exit 1
    exit 0
fi
if [ "$MODE" = commit ]; then
    [ -f "$PENDING/COMPLETE" ] && [ -f "$PENDING/LATEST_SCHEMA" ] || exit 1
    [ ! -e "$SNAP.previous" ] || { echo "VCSETTINGS_FAIL=SNAPSHOT_RECOVERY_PENDING"; exit 1; }
    if [ -d "$SNAP" ]; then mv "$SNAP" "$SNAP.previous" || exit 1; fi
    if ! mv "$PENDING" "$SNAP"; then
        [ ! -d "$SNAP.previous" ] || mv "$SNAP.previous" "$SNAP"
        exit 1
    fi
    rm -rf "$SNAP.previous" || exit 1
    echo "VCSETTINGS_BACKUP=LATEST_SUCCESSFUL_INSTALL_SAVED"
    exit 0
fi
if [ "$MODE" = backup ]; then
    [ ! -e "$PENDING" ] && [ ! -e "$SNAP.previous" ] || { echo "VCSETTINGS_FAIL=SNAPSHOT_RECOVERY_PENDING"; exit 1; }
    [ -s "$LSD" ] && [ -s "$DIO" ] || exit 1
    STAGE="$APP/.vcsettings-backup-$$"
    mkdir -p "$STAGE/jars" || exit 1
    cp -p "$LSD" "$STAGE/lsd.sh" && cp -p "$DIO" "$STAGE/dio_manager" || exit 1
    if [ -d "$ROOT" ]; then cp -R "$ROOT" "$STAGE/runtime" || exit 1
    else touch "$STAGE/RUNTIME_ABSENT" || exit 1; fi
    for name in CarPlayClusterControls.jar CarPlayNavigationPatch.jar VCMenu.jar VCMirrorRate.jar VCInformation.jar; do
        if [ -f "$JARS/$name" ]; then cp "$JARS/$name" "$STAGE/jars/$name" || exit 1
        else touch "$STAGE/jars/$name.absent" || exit 1; fi
    done
    if [ -f "$IPOD" ]; then cp -p "$IPOD" "$STAGE/mm-ipod" || exit 1
    else touch "$STAGE/IPOD_ABSENT" || exit 1; fi
    touch "$STAGE/LATEST_SCHEMA" "$STAGE/COMPLETE" && mv "$STAGE" "$PENDING" || exit 1
    echo "VCSETTINGS_BACKUP=COMPLETE"
    exit 0
fi
[ ! -e "$PENDING" ] && [ -f "$SNAP/LATEST_SCHEMA" ] && [ -f "$SNAP/COMPLETE" ] && [ -s "$SNAP/lsd.sh" ] && [ -s "$SNAP/dio_manager" ] || {
    echo "VCSETTINGS_FAIL=BACKUP_NOT_COMPLETE"; exit 1;
}
[ -f "$SNAP/mm-ipod" ] || [ -f "$SNAP/IPOD_ABSENT" ] || exit 1
for name in CarPlayClusterControls.jar CarPlayNavigationPatch.jar VCMenu.jar VCMirrorRate.jar VCInformation.jar; do
    [ -f "$SNAP/jars/$name" ] || [ -f "$SNAP/jars/$name.absent" ] || exit 1
done
if [ -z "${CPMAP_TEST_ROOT:-}" ]; then
    for process in carplay-cluster-supervisor altscreen-most-bridge cpvc-mirror-canvas carplay-pairing-helper; do
        if [ -n "$MMX" ]; then on -f mmx slay -f "$process" >/dev/null 2>&1 || true
        else slay -f "$process" >/dev/null 2>&1 || true; fi
    done
fi
STAGE="$APP/.vcsettings-restore-$$"
OLD="$APP/.vcsettings-current-$$"
# Save current files before replacing any active component.
CURRENT="$APP/.vcsettings-files-$$"
mkdir -p "$CURRENT/jars" || exit 1
cp -p "$LSD" "$CURRENT/lsd.sh" && cp -p "$DIO" "$CURRENT/dio_manager" || exit 1
for name in CarPlayClusterControls.jar CarPlayNavigationPatch.jar VCMenu.jar VCMirrorRate.jar VCInformation.jar; do
    if [ -f "$JARS/$name" ]; then cp -p "$JARS/$name" "$CURRENT/jars/$name" || exit 1
    else touch "$CURRENT/jars/$name.absent" || exit 1; fi
done
if [ -f "$IPOD" ]; then cp -p "$IPOD" "$CURRENT/mm-ipod" || exit 1
else touch "$CURRENT/IPOD_ABSENT" || exit 1; fi
restore_rollback_stop() {
    echo "VCSETTINGS_RESTORE_ROLLBACK=no"
    echo "VCSETTINGS_RESTORE_ROLLBACK_FAILED=$1"
    echo "Recovery retained: files=$CURRENT; original=$SNAP; previous runtime=$OLD; candidate=$ROOT or $STAGE"
    echo "Do not reboot until the saved setup has been recovered."
    sync 2>/dev/null || true
    exit 1
}
restore_failed() {
    echo "VCSETTINGS_FAIL=RESTORE_COMMIT_FAILED"
    # Stop at the first failed recovery operation and retain everything else.
    cp -p "$CURRENT/lsd.sh" "$LSD" || restore_rollback_stop LSD
    cp -p "$CURRENT/dio_manager" "$DIO" || restore_rollback_stop DIO
    for name in CarPlayClusterControls.jar CarPlayNavigationPatch.jar VCMenu.jar VCMirrorRate.jar VCInformation.jar; do
        if [ -f "$CURRENT/jars/$name" ]; then
            cp -p "$CURRENT/jars/$name" "$JARS/$name" || restore_rollback_stop "$name"
        else
            rm -f "$JARS/$name" || restore_rollback_stop "$name"
        fi
    done
    if [ -f "$CURRENT/mm-ipod" ]; then
        cp -p "$CURRENT/mm-ipod" "$IPOD" || restore_rollback_stop MM_IPOD
    else rm -f "$IPOD" || restore_rollback_stop MM_IPOD; fi
    # Keep the candidate instead of deleting a runtime needed for recovery.
    if [ -d "$ROOT" ]; then
        mv "$ROOT" "$STAGE" || restore_rollback_stop CANDIDATE_RUNTIME_MOVE
    fi
    if [ -d "$OLD" ]; then
        mv "$OLD" "$ROOT" || restore_rollback_stop PREVIOUS_RUNTIME_MOVE
    fi
    for name in CarPlayClusterControls.jar CarPlayNavigationPatch.jar VCMenu.jar VCMirrorRate.jar VCInformation.jar; do
        rm -f "$JARS/$name.vcsettings-restore" || restore_rollback_stop STAGED_FILE_CLEANUP
    done
    rm -f "$LSD.vcsettings-restore" "$DIO.vcsettings-restore" "$IPOD.vcsettings-restore" || restore_rollback_stop STAGED_STARTUP_CLEANUP
    sync 2>/dev/null || true
    echo "VCSETTINGS_RESTORE_ROLLBACK=yes"
    echo "Recovery files retained: $CURRENT; original snapshot: $SNAP; candidate runtime: $STAGE"
    exit 1
}

HAD_RUNTIME=no
[ ! -d "$ROOT" ] || HAD_RUNTIME=yes
if [ -d "$SNAP/runtime" ]; then cp -R "$SNAP/runtime" "$STAGE" || exit 1
elif [ ! -f "$SNAP/RUNTIME_ABSENT" ]; then exit 1; fi
cp -p "$SNAP/lsd.sh" "$LSD.vcsettings-restore" && cp -p "$SNAP/dio_manager" "$DIO.vcsettings-restore" || exit 1
for name in CarPlayClusterControls.jar CarPlayNavigationPatch.jar VCMenu.jar VCMirrorRate.jar VCInformation.jar; do
    if [ -f "$SNAP/jars/$name" ]; then
        cp "$SNAP/jars/$name" "$JARS/$name.vcsettings-restore" || exit 1
    fi
done
if [ -d "$ROOT" ]; then mv "$ROOT" "$OLD" || exit 1; fi
if [ -d "$STAGE" ]; then
    mv "$STAGE" "$ROOT" || { [ ! -d "$OLD" ] || mv "$OLD" "$ROOT"; exit 1; }
fi
for name in CarPlayClusterControls.jar CarPlayNavigationPatch.jar VCMenu.jar VCMirrorRate.jar VCInformation.jar; do
    if [ -f "$SNAP/jars/$name" ]; then mv "$JARS/$name.vcsettings-restore" "$JARS/$name" || restore_failed
    else rm -f "$JARS/$name" || restore_failed; fi
done
mv "$LSD.vcsettings-restore" "$LSD" && mv "$DIO.vcsettings-restore" "$DIO" || restore_failed
chmod 755 "$DIO" || restore_failed
if [ -f "$SNAP/mm-ipod" ]; then
    cp -p "$SNAP/mm-ipod" "$IPOD.vcsettings-restore" && mv "$IPOD.vcsettings-restore" "$IPOD" || restore_failed
else rm -f "$IPOD" || restore_failed; fi
# Keep the saved snapshot; the displaced runtime is disposable.
[ ! -d "$OLD" ] || rm -rf "$OLD"
rm -rf "$CURRENT"
sync 2>/dev/null || true
echo "VCSETTINGS_RESTORE_OK=PREVIOUS_SETUP_RESTORED"
echo "Reboot the unit before reconnecting CarPlay."
