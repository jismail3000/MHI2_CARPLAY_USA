#!/bin/ksh

PAYLOAD="$1"
EXPECTED_MU="$2"
INSTRUMENT="$3"
VERSION="US-VCSETTINGS-2.0.1-LagFix1"

fail() {
    echo "CPMAP_INSTALL_FAIL=$1"
    exit 1
}

if [ -z "$PAYLOAD" ] || [ -z "$EXPECTED_MU" ] || [ -z "$INSTRUMENT" ]; then
    fail "INVALID_ARGUMENTS"
fi

case "$EXPECTED_MU:$INSTRUMENT" in
    MU1126:891) ;;
    *) fail "UNSUPPORTED_PROFILE" ;;
esac

if [ -n "${CPMAP_TEST_ROOT:-}" ] && [ -s "$CPMAP_TEST_ROOT/ifs/lsd.jxe" ] && [ -d "$CPMAP_TEST_ROOT/mnt/app" ]; then
    MMX="$CPMAP_TEST_ROOT"
elif [ -s /ifs/lsd.jxe ] && [ -d /mnt/app ]; then
    MMX=""
elif [ -s /net/mmx/ifs/lsd.jxe ] && [ -d /net/mmx/mnt/app ]; then
    MMX="/net/mmx"
else
    fail "MMX_FILESYSTEM_NOT_FOUND"
fi

APP="$MMX/mnt/app"
JXE="$MMX/ifs/lsd.jxe"
DIO="$APP/eso/bin/apps/dio_manager"
LSD="$APP/eso/hmi/lsd/lsd.sh"
JARS="$APP/eso/hmi/lsd/jars"
IPOD="$APP/armle/usr/sbin/mm-ipod"
ROOT="$APP/carplaymaps"
NEW="$APP/.carplaymaps-new-$$"
OLD="$APP/.carplaymaps-old-$$"
STAGE="$MMX/ramdisk/.cpmap-plaintext-stage-$$"
[ -n "$MMX" ] || STAGE="/ramdisk/.cpmap-plaintext-stage-$$"

if [ ! -s "$JXE" ] || [ ! -s "$DIO" ] || [ ! -s "$LSD" ]; then
    fail "REQUIRED_FACTORY_FILE_MISSING"
fi
if [ -z "${CPMAP_TEST_ROOT:-}" ] && [ ! -x "$DIO" ]; then
    fail "DIO_MANAGER_NOT_EXECUTABLE"
fi

line=`ls -ln "$JXE" 2>/dev/null` || fail "JXE_STAT_FAILED"
set -- $line
JXE_SIZE="$5"
case "$JXE_SIZE" in
    54248171) DETECTED_MU="MU1126" ;;
    55840541) DETECTED_MU="MU1367" ;;
    55840933) DETECTED_MU="MU1440" ;;
    *) fail "UNSUPPORTED_JXE_SIZE_$JXE_SIZE" ;;
esac

if [ "$DETECTED_MU" != "$EXPECTED_MU" ]; then
    fail "PROFILE_MISMATCH_${DETECTED_MU}_EXPECTED_${EXPECTED_MU}"
fi
if [ "$DETECTED_MU" = "MU1440" ] && [ "$INSTRUMENT" != "790" ]; then
    fail "MU1440_REQUIRES_790"
fi
if [ -e "$MMX/dev/ipod0" ]; then
    fail "DISCONNECT_CARPLAY_BEFORE_INSTALL"
fi

CORE="$PAYLOAD/profiles/$EXPECTED_MU/$INSTRUMENT/core.so"
WRAPPER="$PAYLOAD/common/dio_manager.wrapper.sh"
CONTROL_JAR="$PAYLOAD/common/CarPlayClusterControls.jar"
if [ -s "$PAYLOAD/profiles/$EXPECTED_MU/$INSTRUMENT/CarPlayClusterControls.jar" ]; then
    CONTROL_JAR="$PAYLOAD/profiles/$EXPECTED_MU/$INSTRUMENT/CarPlayClusterControls.jar"
fi
NAV_JAR="$PAYLOAD/common/CarPlayNavigationPatch.jar"
NAV_TARGET="$JARS/CarPlayNavigationPatch.jar"
NAV_CHECK="$PAYLOAD/common/cpmap-nav-check"
BRIDGE="$PAYLOAD/common/altscreen-most-bridge"
SUPERVISOR="$PAYLOAD/common/carplay-cluster-supervisor"
SEC="$PAYLOAD/common/libcarplay-security-bridge.so"
PAIR_HELPER="$PAYLOAD/common/carplay-pairing-helper"
PAIR_CORE="$PAYLOAD/common/libCarPlayPairingCore.so"
MENU_JAR="$PAYLOAD/profiles/$EXPECTED_MU/$INSTRUMENT/VCMenu.jar"
RATE_JAR="$PAYLOAD/profiles/$EXPECTED_MU/$INSTRUMENT/VCMirrorRate.jar"
MIRROR="$PAYLOAD/common/cpvc-mirror-canvas-791"
TAP="$PAYLOAD/common/libcpvc-mirror-tap.so"
QUERY="$PAYLOAD/common/libcpvc-dmdt-query.so"
# Do not let the public installer dismantle a private encrypted installation.
if [ -s "$ROOT/cpmap-auth" ] || grep -q 'VCMenu-V73.jar' "$LSD"; then
    fail "ENCRYPTED_INSTALLATION_REQUIRES_ITS_OWN_MIGRATION_TOOL"
fi

NATIVE_ARTWORK_FETCH="$PAYLOAD/common/native-artwork-fetch.sh"
ARTWORK_PUBLISH="$PAYLOAD/common/cluster-artwork-publish.sh"
for required in "$NATIVE_ARTWORK_FETCH" "$ARTWORK_PUBLISH" "$CORE" "$WRAPPER" "$CONTROL_JAR" "$NAV_CHECK" "$BRIDGE" "$SUPERVISOR" "$SEC" "$PAIR_HELPER" "$PAIR_CORE" "$MENU_JAR" "$RATE_JAR" "$MIRROR" "$TAP" "$QUERY"; do
    [ -s "$required" ] || fail "PAYLOAD_MISSING_`basename "$required"`"
done

# The target may have neither cksum nor binary-safe text tools. Use our tiny
# read-only checker, on MMX when invoked from the other node. The test override
# is deliberately unavailable unless an explicit fixture filesystem is active.
run_nav_check() {
    if [ -n "${CPMAP_TEST_ROOT:-}" ] && [ -n "${CPMAP_TEST_NAV_CHECK:-}" ]; then
        "$CPMAP_TEST_NAV_CHECK" "$@"
    elif [ -n "$MMX" ]; then
        on -f mmx "$NAV_CHECK" "$@"
    else
        "$NAV_CHECK" "$@"
    fi
}
if [ ! -x "$NAV_CHECK" ]; then
    chmod 755 "$NAV_CHECK" 2>/dev/null || true
fi
run_nav_check --self-test || fail "NAVIGATION_CHECKER_UNAVAILABLE_REEXTRACT_SD"

navigation_payload_intact() {
    [ -s "$1" ] || return 1
    run_nav_check --same "$NAV_JAR" "$1"
}

# Inspect real ZIP central/local directory entries, not byte-string matches.
has_navigation_patch() {
    [ -s "$1" ] || return 1
    run_nav_check --has-patch "$1"
}
NAV_INSTALL=yes
NAV_USE_OWN=yes
NAV_EXISTING=""
[ -s "$NAV_JAR" ] || fail "PAYLOAD_MISSING_US_NAVIGNORE"
line=`ls -ln "$NAV_JAR"`; set -- $line
[ "${5:-0}" = "65536" ] || fail "NAVIGATION_PAYLOAD_SIZE_MISMATCH"
# Recover a 2.1 wrapper even after an older installer removed its backup.
IPOD_REPAIR=no
IPOD_REFERENCE="$PAYLOAD/profiles/$EXPECTED_MU/$INSTRUMENT/mm-ipod.stock"
if [ -s "$IPOD" ] && grep -q 'CPMAP_PUBLIC_V21_IPOD_WRAPPER' "$IPOD"; then
    [ -s "$IPOD_REFERENCE" ] || fail "FACTORY_IPOD_RECOVERY_PAYLOAD_MISSING"
    IPOD_STOCK="$IPOD_REFERENCE"
    if [ -s "$ROOT/stock_first/mm-ipod.real" ]; then
        run_nav_check --same "$IPOD_REFERENCE" "$ROOT/stock_first/mm-ipod.real" || fail "FACTORY_IPOD_BACKUP_MISMATCH"
        IPOD_STOCK="$ROOT/stock_first/mm-ipod.real"
    fi
    IPOD_REPAIR=yes
fi
echo "CPMAP_NAVIGATION_PATCH=INSTALL_NAR_NAVIGNORE_WITH_ALBUM_ART"

echo "CarPlay Maps VC"
echo "Free open-source project by omonob (QCDWJ)"
echo "Detected firmware: $DETECTED_MU (lsd.jxe $JXE_SIZE bytes)"
echo "Selected cluster: $INSTRUMENT"
echo "Scope: VC settings, CarPlay map video, native mirroring and navigation cards"
echo "Album artwork, navigation card and steering-wheel controls; no intro animation"

if [ -n "${CPMAP_TEST_ROOT:-}" ]; then
    :
elif [ -n "$MMX" ]; then
    on -f mmx mount -uw /mnt/app >/dev/null 2>&1 || fail "APP_REMOUNT_FAILED"
    on -f mmx slay -f cpmap-guard >/dev/null 2>&1 || true
    on -f mmx slay -f carplay-cluster-supervisor >/dev/null 2>&1 || true
    on -f mmx slay -f altscreen-most-bridge >/dev/null 2>&1 || true
    on -f mmx slay -f carplay-pairing-helper >/dev/null 2>&1 || true
else
    mount -uw /mnt/app >/dev/null 2>&1 || fail "APP_REMOUNT_FAILED"
    slay -f cpmap-guard >/dev/null 2>&1 || true
    slay -f carplay-cluster-supervisor >/dev/null 2>&1 || true
    slay -f altscreen-most-bridge >/dev/null 2>&1 || true
    slay -f carplay-pairing-helper >/dev/null 2>&1 || true
fi

rm -rf "$STAGE" "$NEW" "$OLD" 2>/dev/null
mkdir -p "$STAGE" "$NEW/stock_first" "$NEW/rollback" "$NEW/security_bridge" || fail "STAGE_CREATE_FAILED"
cp -p "$LSD" "$STAGE/lsd.sh.current" || fail "CURRENT_LSD_SNAPSHOT_FAILED"
cp -p "$DIO" "$STAGE/dio_manager.current" || fail "CURRENT_DIO_SNAPSHOT_FAILED"
if [ "$IPOD_REPAIR" = yes ]; then
    cp -p "$IPOD" "$STAGE/mm-ipod.current" || fail "CURRENT_IPOD_SNAPSHOT_FAILED"
    cp "$IPOD_STOCK" "$STAGE/mm-ipod.stock" || fail "FACTORY_IPOD_STAGE_FAILED"
    chmod 755 "$STAGE/mm-ipod.stock" || fail "FACTORY_IPOD_MODE_FAILED"
    run_nav_check --same "$IPOD_REFERENCE" "$STAGE/mm-ipod.stock" || fail "FACTORY_IPOD_STAGE_VERIFY_FAILED"
fi
if [ -s "$JARS/CarPlayClusterControls.jar" ]; then
    cp -p "$JARS/CarPlayClusterControls.jar" "$STAGE/control.current" || fail "CURRENT_CONTROL_SNAPSHOT_FAILED"
fi
if [ -s "$NAV_TARGET" ]; then
    cp -p "$NAV_TARGET" "$STAGE/nav.current" || fail "CURRENT_NAV_SNAPSHOT_FAILED"
fi
for name in VCMenu.jar VCMirrorRate.jar; do
    if [ -e "$JARS/$name" ]; then
        cp -p "$JARS/$name" "$STAGE/$name.current" || fail "CURRENT_MENU_SNAPSHOT_FAILED"
    fi
done

STOCK=""
for candidate in \
    "$ROOT/stock_first/dio_manager.real" \
    "$ROOT/rollback/dio_manager" \
    "$APP/carplaymaps-open/stock_first/dio_manager.real" \
    "$APP/carplaymaps-open/rollback/dio_manager" \
    "$APP/eso/bin/apps/dio_manager.stock"; do
    if [ -s "$candidate" ]; then
        size=`ls -ln "$candidate" 2>/dev/null`; set -- $size; size="$5"
        if [ "${size:-0}" -gt 500000 ] 2>/dev/null; then
            STOCK="$candidate"
            break
        fi
    fi
done
if [ -z "$STOCK" ]; then
    size=`ls -ln "$DIO" 2>/dev/null`; set -- $size; size="$5"
    if [ "${size:-0}" -gt 500000 ] 2>/dev/null; then
        STOCK="$DIO"
    fi
fi
[ -n "$STOCK" ] || fail "FACTORY_DIO_MANAGER_NOT_FOUND"

LSD_BASE="$LSD"
if [ -s "$ROOT/VERSION" ] && [ -s "$ROOT/rollback/lsd.sh" ]; then
    # A repeat install must retain our first saved startup byte-for-byte, even
    # if that original script contained comments or older classpath references.
    LSD_BASE="$ROOT/rollback/lsd.sh"
else
    for candidate in "$ROOT/map_control_rollback/lsd.sh" "$ROOT/rollback/lsd.sh" "$APP/carplaymaps-open/rollback/lsd.sh"; do
        if [ -s "$candidate" ] && ! grep -q 'CarPlayClusterControls.jar' "$candidate" 2>/dev/null; then
            LSD_BASE="$candidate"
            break
        fi
    done
fi

cp "$STOCK" "$NEW/stock_first/dio_manager.real" || fail "STOCK_COPY_FAILED"
cp "$LSD_BASE" "$NEW/rollback/lsd.sh" || fail "LSD_BACKUP_FAILED"
if [ -e "$ROOT/rollback/JAR_ABSENT" ]; then
    touch "$NEW/rollback/JAR_ABSENT" || fail "JAR_ABSENT_MARK_FAILED"
elif [ -s "$ROOT/rollback/CarPlayClusterControls.jar" ]; then
    cp "$ROOT/rollback/CarPlayClusterControls.jar" "$NEW/rollback/CarPlayClusterControls.jar" || fail "JAR_BACKUP_FAILED"
elif [ -s "$JARS/CarPlayClusterControls.jar" ]; then
    cp "$JARS/CarPlayClusterControls.jar" "$NEW/rollback/CarPlayClusterControls.jar" || fail "JAR_BACKUP_FAILED"
else
    touch "$NEW/rollback/JAR_ABSENT" || fail "JAR_ABSENT_MARK_FAILED"
fi

if [ -e "$ROOT/rollback/NAV_JAR_ABSENT" ]; then
    touch "$NEW/rollback/NAV_JAR_ABSENT" || fail "NAV_ABSENT_MARK_FAILED"
elif [ -s "$ROOT/rollback/CarPlayNavigationPatch.jar" ]; then
    cp "$ROOT/rollback/CarPlayNavigationPatch.jar" "$NEW/rollback/CarPlayNavigationPatch.jar" || fail "NAV_BACKUP_FAILED"
elif [ -s "$NAV_TARGET" ]; then
    cp "$NAV_TARGET" "$NEW/rollback/CarPlayNavigationPatch.jar" || fail "NAV_BACKUP_FAILED"
else
    touch "$NEW/rollback/NAV_JAR_ABSENT" || fail "NAV_ABSENT_MARK_FAILED"
fi

ADD_CLASSPATH='$BASE_DIR/lsd/jars/CarPlayClusterControls.jar'
ADD_CLASSPATH='$BASE_DIR/lsd/jars/VCMenu.jar:$BASE_DIR/lsd/jars/VCMirrorRate.jar:'"$ADD_CLASSPATH"
if [ "$NAV_USE_OWN" = yes ]; then
    [ -z "$ADD_CLASSPATH" ] || ADD_CLASSPATH="$ADD_CLASSPATH:"
    ADD_CLASSPATH="$ADD_CLASSPATH"'$BASE_DIR/lsd/jars/CarPlayNavigationPatch.jar'
fi
if [ -z "$ADD_CLASSPATH" ]; then
    cp -p "$LSD" "$STAGE/lsd.sh.patched" || fail "LSD_STAGE_FAILED"
else
    # Extend the existing prepend option if present. Do not emit a second
    # -Xbootclasspath/p option: some J9 builds keep only its last occurrence.
    # On a stock script, add one line immediately before J9 instead.
    awk -v prepend="$ADD_CLASSPATH" '
        {
            lines[NR]=$0
            if ($0 ~ /^[ \t]*#/) next
            if ($0 ~ /-Xbootclasspath\/p:/ && $0 !~ /^[ \t]*BOOTCLASSPATH="\$BOOTCLASSPATH -Xbootclasspath\/p:[^" \t]+"[ \t]*(#.*)?$/) unsupported=1
            if ($0 ~ /^[ \t]*BOOTCLASSPATH="\$BOOTCLASSPATH -Xbootclasspath\/p:[^" \t]+"[ \t]*(#.*)?$/) {
                remove[NR]=1
                if (!insert) insert=NR
                match($0, /-Xbootclasspath\/p:[^" \t]+/)
                value=substr($0,RSTART+18,RLENGTH-18)
                count=split(value,items,":")
                for(i=1;i<=count;i++) {
                    if(items[i] ~ /\/CarPlayClusterControls\.jar$/ || items[i] ~ /\/CarPlayNavigationPatch\.jar$/ || items[i] ~ /\/VCMenu\.jar$/ || items[i] ~ /\/VCMirrorRate\.jar$/ || items[i] ~ /\/VCInformation\.jar$/) continue
                    if(length(items[i]) && !seen[items[i]]++) kept=kept ":" items[i]
                }
            }
            if (!j9 && $0 ~ /^[ \t]*\$J9[ \t]/) j9=NR
        }
        END {
            if (!j9 || unsupported) exit 9
            if (!insert) insert=j9
            if (insert>j9) exit 9
            for(row=1;row<=NR;row++) {
                if(row==insert) print "BOOTCLASSPATH=\"$BOOTCLASSPATH -Xbootclasspath/p:" prepend kept "\""
                if(!remove[row]) print lines[row]
            }
        }
    ' "$LSD" > "$STAGE/lsd.sh.patched" || fail "BOOTCLASSPATH_STRUCTURE_UNSUPPORTED"
fi

if [ -n "${CPMAP_TEST_ROOT:-}" ]; then
    /bin/sh -n "$STAGE/lsd.sh.patched" >/dev/null 2>&1 || fail "PATCHED_LSD_SYNTAX_FAILED"
else
    /bin/ksh -n "$STAGE/lsd.sh.patched" >/dev/null 2>&1 || fail "PATCHED_LSD_SYNTAX_FAILED"
fi

cp "$NATIVE_ARTWORK_FETCH" "$NEW/native-artwork-fetch.sh" || fail "ARTWORK_FETCH_COPY_FAILED"
cp "$ARTWORK_PUBLISH" "$NEW/cluster-artwork-publish.sh" || fail "ARTWORK_PUBLISH_COPY_FAILED"
chmod 644 "$NEW/native-artwork-fetch.sh" "$NEW/cluster-artwork-publish.sh" || fail "ARTWORK_HELPER_PERMISSIONS_FAILED"
cp "$CORE" "$NEW/core.so" || fail "CORE_COPY_FAILED"
cp "$WRAPPER" "$NEW/dio_manager.wrapper.sh" || fail "WRAPPER_COPY_FAILED"
cp "$BRIDGE" "$NEW/altscreen-most-bridge" || fail "BRIDGE_COPY_FAILED"
cp "$SUPERVISOR" "$NEW/carplay-cluster-supervisor" || fail "SUPERVISOR_COPY_FAILED"
cp "$SEC" "$NEW/libcarplay-security-bridge.so" || fail "SESSION_BRIDGE_COPY_FAILED"
cp "$PAIR_HELPER" "$NEW/security_bridge/carplay-pairing-helper" || fail "PAIR_HELPER_COPY_FAILED"
cp "$PAIR_CORE" "$NEW/security_bridge/libCarPlayPairingCore.so" || fail "PAIR_CORE_COPY_FAILED"
cp "$MIRROR" "$NEW/cpvc-mirror-canvas" || fail "MIRROR_COPY_FAILED"
cp "$TAP" "$NEW/libcpvc-mirror-tap.so" || fail "TAP_COPY_FAILED"
cp "$QUERY" "$NEW/libcpvc-dmdt-query.so" || fail "QUERY_COPY_FAILED"
for name in VCMenu.jar VCMirrorRate.jar; do
    if [ -e "$ROOT/rollback/$name.absent" ]; then
        touch "$NEW/rollback/$name.absent" || fail "MENU_BACKUP_MARK_FAILED"
    elif [ -s "$ROOT/rollback/$name" ]; then
        cp "$ROOT/rollback/$name" "$NEW/rollback/$name" || fail "MENU_BACKUP_FAILED"
    elif [ -e "$JARS/$name" ]; then
        cp "$JARS/$name" "$NEW/rollback/$name" || fail "MENU_BACKUP_FAILED"
    else
        touch "$NEW/rollback/$name.absent" || fail "MENU_BACKUP_MARK_FAILED"
    fi
done
echo "$VERSION" > "$NEW/VERSION" || fail "VERSION_WRITE_FAILED"
echo "$DETECTED_MU/$INSTRUMENT+vc-settings" > "$NEW/PROFILE" || fail "PROFILE_WRITE_FAILED"
touch "$NEW/CLUSTER_AUTO_ENABLE" || fail "AUTO_ENABLE_WRITE_FAILED"
[ "$(cat "$NEW/VERSION")" = "$VERSION" ] || fail "VERSION_READBACK_FAILED"
[ "$(cat "$NEW/PROFILE")" = "$DETECTED_MU/$INSTRUMENT+vc-settings" ] || fail "PROFILE_READBACK_FAILED"

chmod 755 "$NEW/dio_manager.wrapper.sh" "$NEW/altscreen-most-bridge" "$NEW/carplay-cluster-supervisor" "$NEW/security_bridge/carplay-pairing-helper" "$NEW/stock_first/dio_manager.real" || fail "STAGED_PERMISSIONS_FAILED"
chmod 644 "$NEW/core.so" "$NEW/libcarplay-security-bridge.so" "$NEW/security_bridge/libCarPlayPairingCore.so" "$NEW/VERSION" "$NEW/PROFILE" "$NEW/CLUSTER_AUTO_ENABLE" || fail "STAGED_PERMISSIONS_FAILED"
chmod 755 "$NEW/cpvc-mirror-canvas" || fail "STAGED_PERMISSIONS_FAILED"
chmod 644 "$NEW/libcpvc-mirror-tap.so" "$NEW/libcpvc-dmdt-query.so" || fail "STAGED_PERMISSIONS_FAILED"

cp "$CONTROL_JAR" "$JARS/CarPlayClusterControls.jar.new" || fail "CONTROL_JAR_STAGE_FAILED"
cp "$MENU_JAR" "$JARS/VCMenu.jar.new" || fail "MENU_JAR_STAGE_FAILED"
cp "$RATE_JAR" "$JARS/VCMirrorRate.jar.new" || fail "RATE_JAR_STAGE_FAILED"
cp "$STAGE/lsd.sh.patched" "$LSD.cpmap-new" || fail "LSD_ACTIVATION_STAGE_FAILED"
chmod 644 "$JARS/CarPlayClusterControls.jar.new" || fail "STAGED_PERMISSIONS_FAILED"
chmod 644 "$JARS/VCMenu.jar.new" "$JARS/VCMirrorRate.jar.new" || fail "STAGED_PERMISSIONS_FAILED"
chmod 755 "$LSD.cpmap-new" || fail "STAGED_PERMISSIONS_FAILED"
if [ "$NAV_INSTALL" = yes ]; then
    cp "$NAV_JAR" "$NAV_TARGET.new" || fail "NAV_JAR_STAGE_FAILED"
    chmod 644 "$NAV_TARGET.new" || fail "STAGED_PERMISSIONS_FAILED"
fi

if [ -d "$ROOT" ]; then
    mv "$ROOT" "$OLD" || fail "OLD_ROOT_MOVE_FAILED"
fi
mv "$NEW" "$ROOT" || {
    [ -d "$OLD" ] && mv "$OLD" "$ROOT" 2>/dev/null
    fail "NEW_ROOT_ACTIVATION_FAILED"
}

rollback_incomplete() {
    echo "CPMAP_ROLLBACK_INCOMPLETE=$1"
    echo "Recovery files retained: $STAGE; previous runtime: $OLD; candidate runtime: $ROOT or $NEW"
    echo "Do not reboot until the saved setup has been recovered."
    sync 2>/dev/null || true
    return 1
}

rollback_commit() {
    # Stop on an unsuccessful restore; retain all remaining recovery material.
    if [ "$IPOD_REPAIR" = yes ]; then
        cp -p "$STAGE/mm-ipod.current" "$IPOD" || { rollback_incomplete MM_IPOD; return 1; }
    fi
    cp -p "$STAGE/dio_manager.current" "$DIO" || { rollback_incomplete DIO; return 1; }
    cp -p "$STAGE/lsd.sh.current" "$LSD" || { rollback_incomplete LSD; return 1; }
    for name in VCMenu.jar VCMirrorRate.jar; do
        if [ -e "$STAGE/$name.current" ]; then
            cp -p "$STAGE/$name.current" "$JARS/$name" || { rollback_incomplete "$name"; return 1; }
        else
            rm -f "$JARS/$name" || { rollback_incomplete "$name"; return 1; }
        fi
    done
    for pair in control:CarPlayClusterControls.jar nav:CarPlayNavigationPatch.jar; do
        saved=${pair%%:*}
        name=${pair#*:}
        if [ -s "$STAGE/$saved.current" ]; then
            cp -p "$STAGE/$saved.current" "$JARS/$name" || { rollback_incomplete "$name"; return 1; }
        else
            rm -f "$JARS/$name" || { rollback_incomplete "$name"; return 1; }
        fi
    done
    # Move the candidate aside rather than deleting the only available runtime.
    mv "$ROOT" "$NEW" || { rollback_incomplete CANDIDATE_MOVE; return 1; }
    if [ -d "$OLD" ]; then
        mv "$OLD" "$ROOT" || { rollback_incomplete PREVIOUS_RUNTIME_MOVE; return 1; }
    fi
    rm -f "$DIO.new" "$IPOD.cpmap-repair" "$LSD.cpmap-new" "$JARS/CarPlayClusterControls.jar.new" "$JARS/CarPlayNavigationPatch.jar.new" "$JARS/VCMenu.jar.new" "$JARS/VCMirrorRate.jar.new" || { rollback_incomplete STAGED_FILES; return 1; }
    sync 2>/dev/null || true
    echo "CPMAP_ROLLBACK_OK"
    return 0
}

mv "$JARS/CarPlayClusterControls.jar.new" "$JARS/CarPlayClusterControls.jar" || { rollback_commit; fail "CONTROL_JAR_ACTIVATION_FAILED"; }
mv "$JARS/VCMenu.jar.new" "$JARS/VCMenu.jar" || { rollback_commit; fail "MENU_JAR_ACTIVATION_FAILED"; }
mv "$JARS/VCMirrorRate.jar.new" "$JARS/VCMirrorRate.jar" || { rollback_commit; fail "RATE_JAR_ACTIVATION_FAILED"; }
if [ "$NAV_INSTALL" = yes ]; then
    mv "$NAV_TARGET.new" "$NAV_TARGET" || { rollback_commit; fail "NAV_JAR_ACTIVATION_FAILED"; }
fi
mv "$LSD.cpmap-new" "$LSD" || { rollback_commit; fail "LSD_ACTIVATION_FAILED"; }
if [ "$IPOD_REPAIR" = yes ]; then
    cp -p "$STAGE/mm-ipod.stock" "$IPOD.cpmap-repair" || { rollback_commit; fail "IPOD_REPAIR_COPY_FAILED"; }
    mv "$IPOD.cpmap-repair" "$IPOD" || { rollback_commit; fail "IPOD_REPAIR_ACTIVATION_FAILED"; }
    [ -x "$IPOD" ] && run_nav_check --same "$IPOD_REFERENCE" "$IPOD" || { rollback_commit; fail "IPOD_REPAIR_VERIFY_FAILED"; }
    echo "CPMAP_IPOD_REPAIR=FACTORY_RESTORED"
fi
cp "$ROOT/dio_manager.wrapper.sh" "$DIO.new" || { rollback_commit; fail "DIO_WRAPPER_STAGE_FAILED"; }
chmod 755 "$DIO.new" || { rollback_commit; fail "DIO_PERMISSIONS_FAILED"; }
mv "$DIO.new" "$DIO" || { rollback_commit; fail "DIO_WRAPPER_ACTIVATION_FAILED"; }

rm -f "$ROOT/cpmap-guard" "$ROOT/cpmap-auth" "$ROOT/cpmap-provision" "$ROOT/intro.eft" "$ROOT"/*.eft "$ROOT"/k1 "$ROOT"/k2 2>/dev/null

[ -s "$DIO" ] && [ -x "$DIO" ] || { rollback_commit; fail "DIO_WRAPPER_VERIFY_FAILED"; }
[ "$(cat "$ROOT/VERSION")" = "$VERSION" ] || { rollback_commit; fail "INSTALLED_VERSION_VERIFY_FAILED"; }
[ "$(cat "$ROOT/PROFILE")" = "$DETECTED_MU/$INSTRUMENT+vc-settings" ] || { rollback_commit; fail "INSTALLED_PROFILE_VERIFY_FAILED"; }
[ -f "$ROOT/CLUSTER_AUTO_ENABLE" ] || { rollback_commit; fail "AUTO_ENABLE_VERIFY_FAILED"; }
[ -s "$ROOT/core.so" ] || { rollback_commit; fail "CORE_VERIFY_FAILED"; }
[ -s "$ROOT/stock_first/dio_manager.real" ] || { rollback_commit; fail "STOCK_VERIFY_FAILED"; }
[ -s "$JARS/CarPlayClusterControls.jar" ] || { rollback_commit; fail "CONTROL_JAR_VERIFY_FAILED"; }
run_nav_check --same "$BRIDGE" "$ROOT/altscreen-most-bridge" || { rollback_commit; fail "BRIDGE_VERIFY_FAILED"; }
run_nav_check --same "$SUPERVISOR" "$ROOT/carplay-cluster-supervisor" || { rollback_commit; fail "SUPERVISOR_VERIFY_FAILED"; }
run_nav_check --same "$NATIVE_ARTWORK_FETCH" "$ROOT/native-artwork-fetch.sh" || { rollback_commit; fail "ARTWORK_FETCH_VERIFY_FAILED"; }
run_nav_check --same "$ARTWORK_PUBLISH" "$ROOT/cluster-artwork-publish.sh" || { rollback_commit; fail "ARTWORK_PUBLISH_VERIFY_FAILED"; }
run_nav_check --same "$MENU_JAR" "$JARS/VCMenu.jar" || { rollback_commit; fail "MENU_VERIFY_FAILED"; }
run_nav_check --same "$RATE_JAR" "$JARS/VCMirrorRate.jar" || { rollback_commit; fail "RATE_VERIFY_FAILED"; }
active_reference_count() {
    awk -v name="$1" '/^[ \t]*#/ {next} index($0,name) {n++} END {print n+0}' "$LSD"
}
[ `active_reference_count 'CarPlayClusterControls.jar'` -eq 1 ] || { rollback_commit; fail "BOOTCLASSPATH_VERIFY_FAILED"; }
[ `active_reference_count 'VCMenu.jar'` -eq 1 ] || { rollback_commit; fail "MENU_CLASSPATH_VERIFY_FAILED"; }
[ `active_reference_count 'VCMirrorRate.jar'` -eq 1 ] || { rollback_commit; fail "RATE_CLASSPATH_VERIFY_FAILED"; }
if [ "$NAV_INSTALL" = yes ]; then
    navigation_payload_intact "$NAV_TARGET" && run_nav_check --same "$NAV_JAR" "$NAV_TARGET" || { rollback_commit; fail "NAVIGATION_VERIFY_FAILED"; }
    [ `active_reference_count 'CarPlayNavigationPatch.jar'` -eq 1 ] || { rollback_commit; fail "NAVIGATION_CLASSPATH_VERIFY_FAILED"; }
fi
[ `active_reference_count 'VCInformation.jar'` -eq 0 ] || { rollback_commit; fail "INFORMATION_HOOK_STILL_ACTIVE"; }
rm -rf "$OLD" "$STAGE" 2>/dev/null

sync 2>/dev/null || true
echo "CPMAP_PROFILE=$DETECTED_MU/$INSTRUMENT"
echo "CPMAP_PLAINTEXT_ROOT=/mnt/app/carplaymaps"
echo "CPMAP_INSTALL_OK"
echo "A full unit reboot is required."
exit 0
