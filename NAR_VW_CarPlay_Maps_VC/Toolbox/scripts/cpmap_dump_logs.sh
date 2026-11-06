#!/bin/sh
# Export the VC settings runtime and installer diagnostics before power-off.
SCRIPTS=/mnt/app/eso/hmi/engdefs/scripts/mqb
[ -s "$SCRIPTS/util_mountsd.sh" ] || SCRIPTS=/net/mmx/mnt/app/eso/hmi/engdefs/scripts/mqb
# The shared helper calls exit, including exit 0 for missing media. Isolate it
# so it cannot terminate this exporter before the volume check.
find_export_volume() {
    unset VOLUME
    . "$SCRIPTS/util_mountsd.sh" >&2 || return 1
    # The target /bin/sh has no printf builtin or executable. Media paths are fixed.
    echo "${VOLUME:-}"
}
VOLUME=$(find_export_volume) || { echo "SD card setup failed"; exit 1; }
[ -n "$VOLUME" ] || { echo "No SD card found"; exit 1; }
MMX=""
[ -s /ifs/lsd.jxe ] || MMX=/net/mmx
DEST="$VOLUME/Log/carplaymaps"
mkdir -p "$DEST" || exit 1
RESULT=0
for name in rolex-daydate.log carplaymaps-launcher.log carplaymaps-video.log carplay-maps-session.log carplay-cluster-supervisor.log altscreen-most-bridge.log carplay-dio-manager.pid carplay-coverart.log carplay-native-artwork-java.log carplay-native-artwork-fetch.log carplay-cluster-artwork-trace.log; do
    source="$MMX/ramdisk/$name"
    [ ! -f "$source" ] || cp "$source" "$DEST/" || RESULT=1
done
# The installer can run on either node. Keep both captures when both exist.
for node in mmx rcc; do
    source="/net/$node/ramdisk/cpmap-vcsettings-install.txt"
    [ ! -f "$source" ] || cp "$source" "$DEST/cpmap-vcsettings-install-$node.txt" || RESULT=1
done
for source in /ramdisk/cpmap-vcsettings-install.txt "$MMX/ramdisk/cpmap-vcsettings-install.txt"; do
    [ ! -f "$source" ] || cp "$source" "$DEST/cpmap-vcsettings-install.txt" || RESULT=1
done
if [ -d "$MMX/ramdisk/carplaymaps-diagnostics" ]; then
    cp -R "$MMX/ramdisk/carplaymaps-diagnostics" "$DEST/" || RESULT=1
fi
for name in carplay-native-artwork carplay-cluster-artwork-fix1; do
    source="$MMX/ramdisk/$name"
    [ ! -d "$source" ] || cp -R "$source" "$DEST/" || RESULT=1
done
for image in /net/rcc/dev/shmem/carplay-cluster-artwork-fix3-cover-*.png; do
    [ ! -f "$image" ] || cp "$image" "$DEST/" || RESULT=1
done
for name in VERSION PROFILE; do
    source="$MMX/mnt/app/carplaymaps/$name"
    [ ! -f "$source" ] || cp "$source" "$DEST/carplaymaps-$name" || RESULT=1
done
sync
mount -ur "$VOLUME" || RESULT=1
if [ "$RESULT" = 0 ]; then echo "Logs saved to Log/carplaymaps"
else echo "Log export incomplete; check SD card write access"; fi
exit "$RESULT"
