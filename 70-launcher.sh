#!/sbin/sh
#
# This file is part of The BiTGApps Project

# ADDOND_VERSION=3

if [ -z "$backuptool_ab" ]; then
  SYS="$S"
  TMP=/tmp
else
  SYS="/postinstall/system"
  TMP="/postinstall/tmp"
fi

# Dedicated V3 Partitions
P="/product /system_ext /postinstall/product /postinstall/system_ext"

# Create DPS Firmware
install -d $SYS/etc/firmware

. /tmp/backuptool.functions

list_files() {
cat <<EOF
priv-app/DPS/DPS.apk
priv-app/Launcher/Launcher.apk
priv-app/QAWallet/QAWallet.apk
priv-app/WallPicker/WallPicker.apk
etc/permissions/launcher.xml
product/overlay/Launcher.apk
product/overlay/PixelConfig.apk
product/overlay/PixelFont.apk
product/overlay/PixelRecent.apk
product/overlay/PixelUIGX.apk
product/overlay/IconPack.apk
etc/firmware/music_detector.descriptor
etc/firmware/music_detector.sound_model
EOF
}

case "$1" in
  backup)
    list_files | while read FILE DUMMY; do
      backup_file $S/"$FILE"
    done
  ;;
  restore)
    for f in $SYS $SYS/product $SYS/system_ext $P; do
      find $f -type d -name '*Launcher*' -exec rm -rf {} +
      find $f -type d -name '*QuickAcc*' -exec rm -rf {} +
    done
    list_files | while read FILE REPLACEMENT; do
      R=""
      [ -n "$REPLACEMENT" ] && R="$S/$REPLACEMENT"
      [ -f "$C/$S/$FILE" ] && restore_file $S/"$FILE" "$R"
    done
    for i in $(list_files); do
      chown root:root "$SYS/$i" 2>/dev/null
      chmod 644 "$SYS/$i" 2>/dev/null
      chmod 755 "$(dirname "$SYS/$i")" 2>/dev/null
    done
  ;;
esac
