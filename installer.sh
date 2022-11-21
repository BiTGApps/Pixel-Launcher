# This file is part of The BiTGApps Project

# Handle installation of Additional Package
ZIPNAME="$(basename "$ZIPFILE" ".zip" | tr '[:upper:]' '[:lower:]')"

# Magisk Current Base Folder
MIRROR="$(magisk --path)/.magisk/mirror"

# Installation base is Bootmode script
if [[ "$(getprop "sys.bootmode")" = "1" ]]; then
  # System is writable
  if ! touch $SYSTEM/.rw >/dev/null 2>&1; then
    echo "! Read-only file system"
    exit 1
  fi
fi

# Allow mounting, when installation base is Magisk
if [[ "$(getprop "sys.bootmode")" = "2" ]]; then
  # Mount actual partitions
  mount -o remount,rw,errors=continue / > /dev/null 2>&1
  mount -o remount,rw,errors=continue /dev/root > /dev/null 2>&1
  mount -o remount,rw,errors=continue /dev/block/dm-0 > /dev/null 2>&1
  mount -o remount,rw,errors=continue /system > /dev/null 2>&1
  mount -o remount,rw,errors=continue /product > /dev/null 2>&1
  mount -o remount,rw,errors=continue /system_ext > /dev/null 2>&1
  # Mount mirror partitions
  mount -o remount,rw,errors=continue $MIRROR/system_root 2>/dev/null
  mount -o remount,rw,errors=continue $MIRROR/system 2>/dev/null
  mount -o remount,rw,errors=continue $MIRROR/product 2>/dev/null
  mount -o remount,rw,errors=continue $MIRROR/system_ext 2>/dev/null
  # Set installation layout
  SYSTEM="$MIRROR/system"
  # Backup installation layout
  SYSTEM_AS_SYSTEM="$SYSTEM"
  # System is writable
  if ! touch $SYSTEM/.rw >/dev/null 2>&1; then
    echo "! Read-only file system"
    exit 1
  fi
fi

# Product is a dedicated partition
if [[ "$(getprop "sys.bootmode")" = "2" ]]; then
  if grep -q " $(readlink -f /product) " /proc/mounts; then
    ln -sf /product /system
  fi
fi

# Detect whether in boot mode
[ -z $BOOTMODE ] && ps | grep zygote | grep -qv grep && BOOTMODE="true"
[ -z $BOOTMODE ] && ps -A 2>/dev/null | grep zygote | grep -qv grep && BOOTMODE="true"
[ -z $BOOTMODE ] && BOOTMODE="false"

# Strip leading directories
if [ "$BOOTMODE" = "false" ]; then
  DEST="-f5-"
else
  DEST="-f6-"
fi

# Extract utility script
if [ "$BOOTMODE" = "false" ]; then
  unzip -oq "$ZIPFILE" "util_functions.sh" -d "$TMP"
fi
# Allow unpack, when installation base is Magisk
if [[ "$(getprop "sys.bootmode")" = "2" ]]; then
  $(unzip -oq "$ZIPFILE" "util_functions.sh" -d "$TMP")
fi
chmod +x "$TMP/util_functions.sh"

# Load utility functions
. $TMP/util_functions.sh

ui_print() {
  if [ "$BOOTMODE" = "true" ]; then
    echo "$1"
  fi
  if [ "$BOOTMODE" = "false" ]; then
    echo -n -e "ui_print $1\n" >> /proc/self/fd/$OUTFD
    echo -n -e "ui_print\n" >> /proc/self/fd/$OUTFD
  fi
}

print_title "BiTGApps $version Installer"

recovery_actions() {
  if [ "$BOOTMODE" = "false" ]; then
    OLD_LD_LIB=$LD_LIBRARY_PATH
    OLD_LD_PRE=$LD_PRELOAD
    OLD_LD_CFG=$LD_CONFIG_FILE
    unset LD_LIBRARY_PATH
    unset LD_PRELOAD
    unset LD_CONFIG_FILE
  fi
}

recovery_cleanup() {
  if [ "$BOOTMODE" = "false" ]; then
    [ -z $OLD_LD_LIB ] || export LD_LIBRARY_PATH=$OLD_LD_LIB
    [ -z $OLD_LD_PRE ] || export LD_PRELOAD=$OLD_LD_PRE
    [ -z $OLD_LD_CFG ] || export LD_CONFIG_FILE=$OLD_LD_CFG
  fi
}

build_defaults() {
  # Compressed Packages
  ZIP_FILE="$TMP/zip"
  # Extracted Packages
  mkdir $TMP/unzip
  # Initial link
  UNZIP_DIR="$TMP/unzip"
  # Create links
  TMP_SYS="$UNZIP_DIR/tmp_sys"
  TMP_PRIV="$UNZIP_DIR/tmp_priv"
  TMP_PERMISSION="$UNZIP_DIR/tmp_perm"
  TMP_FIRMWARE="$UNZIP_DIR/tmp_ware"
  TMP_OVERLAY="$UNZIP_DIR/tmp_overlay"
}

on_partition_check() {
  system_as_root=`getprop ro.build.system_root_image`
  slot_suffix=`getprop ro.boot.slot_suffix`
  AB_OTA_UPDATER=`getprop ro.build.ab_update`
  dynamic_partitions=`getprop ro.boot.dynamic_partitions`
}

ab_partition() {
  device_abpartition="false"
  if [ ! -z "$slot_suffix" ]; then
    device_abpartition="true"
  fi
  if [ "$AB_OTA_UPDATER" = "true" ]; then
    device_abpartition="true"
  fi
}

system_as_root() {
  SYSTEM_ROOT="false"
  if [ "$system_as_root" = "true" ]; then
    SYSTEM_ROOT="true"
  fi
}

super_partition() {
  SUPER_PARTITION="false"
  if [ "$dynamic_partitions" = "true" ]; then
    SUPER_PARTITION="true"
  fi
}

is_mounted() {
  grep -q " $(readlink -f $1) " /proc/mounts 2>/dev/null
  return $?
}

grep_cmdline() {
  local REGEX="s/^$1=//p"
  { echo $(cat /proc/cmdline)$(sed -e 's/[^"]//g' -e 's/""//g' /proc/cmdline) | xargs -n 1; \
    sed -e 's/ = /=/g' -e 's/, /,/g' -e 's/"//g' /proc/bootconfig; \
  } 2>/dev/null | sed -n "$REGEX"
}

setup_mountpoint() {
  test -L $1 && mv -f $1 ${1}_link
  if [ ! -d $1 ]; then
    rm -f $1
    mkdir $1
  fi
}

mount_apex() {
  if "$BOOTMODE"; then
    return 255
  fi
  test -d "$SYSTEM/apex" || return 255
  ui_print "- Mounting /apex"
  local apex dest loop minorx num
  setup_mountpoint /apex
  test -e /dev/block/loop1 && minorx=$(ls -l /dev/block/loop1 | awk '{ print $6 }') || minorx="1"
  num="0"
  for apex in $SYSTEM/apex/*; do
    dest=/apex/$(basename $apex | sed -E -e 's;\.apex$|\.capex$;;')
    test "$dest" = /apex/com.android.runtime.release && dest=/apex/com.android.runtime
    mkdir -p $dest
    case $apex in
      *.apex|*.capex)
        # Handle CAPEX APKs
        unzip -oq $apex original_apex -d /apex
        if [ -f "/apex/original_apex" ]; then
          apex="/apex/original_apex"
        fi
        # Handle APEX APKs
        unzip -oq $apex apex_payload.img -d /apex
        mv -f /apex/apex_payload.img $dest.img
        mount -t ext4 -o ro,noatime $dest.img $dest 2>/dev/null
        if [ $? != 0 ]; then
          while [ $num -lt 64 ]; do
            loop=/dev/block/loop$num
            (mknod $loop b 7 $((num * minorx))
            losetup $loop $dest.img) 2>/dev/null
            num=$((num + 1))
            losetup $loop | grep -q $dest.img && break
          done
          mount -t ext4 -o ro,loop,noatime $loop $dest 2>/dev/null
          if [ $? != 0 ]; then
            losetup -d $loop 2>/dev/null
          fi
        fi
      ;;
      *) mount -o bind $apex $dest;;
    esac
  done
  export ANDROID_RUNTIME_ROOT="/apex/com.android.runtime"
  export ANDROID_TZDATA_ROOT="/apex/com.android.tzdata"
  export ANDROID_ART_ROOT="/apex/com.android.art"
  export ANDROID_I18N_ROOT="/apex/com.android.i18n"
  local APEXJARS=$(find /apex -name '*.jar' | sort | tr '\n' ':')
  local FWK=$SYSTEM/framework
  export BOOTCLASSPATH="${APEXJARS}\
  $FWK/framework.jar:\
  $FWK/framework-graphics.jar:\
  $FWK/ext.jar:\
  $FWK/telephony-common.jar:\
  $FWK/voip-common.jar:\
  $FWK/ims-common.jar:\
  $FWK/framework-atb-backward-compatibility.jar:\
  $FWK/android.test.base.jar"
}

umount_apex() {
  if "$BOOTMODE"; then
    return 255
  fi
  test -d /apex || return 255
  local dest loop
  for dest in $(find /apex -type d -mindepth 1 -maxdepth 1); do
    if [ -f $dest.img ]; then
      loop=$(mount | grep $dest | cut -d" " -f1)
    fi
    (umount -l $dest
    losetup -d $loop) 2>/dev/null
  done
  rm -rf /apex 2>/dev/null
  unset ANDROID_RUNTIME_ROOT
  unset ANDROID_TZDATA_ROOT
  unset ANDROID_ART_ROOT
  unset ANDROID_I18N_ROOT
  unset BOOTCLASSPATH
}

umount_all() {
  if [ "$BOOTMODE" = "false" ]; then
    umount -l /system > /dev/null 2>&1
    umount -l /system_root > /dev/null 2>&1
    umount -l /product > /dev/null 2>&1
    umount -l /system_ext > /dev/null 2>&1
  fi
}

mount_all() {
  if "$BOOTMODE"; then
    return 255
  fi
  $SYSTEM_ROOT && ui_print "- Device is system-as-root"
  $SUPER_PARTITION && ui_print "- Super partition detected"
  # Check A/B slot
  [ "$slot" ] || slot=$(getprop ro.boot.slot_suffix 2>/dev/null)
  [ "$slot" ] || slot=`grep_cmdline androidboot.slot_suffix`
  [ "$slot" ] || slot=`grep_cmdline androidboot.slot`
  [ "$slot" ] && ui_print "- Current boot slot: $slot"
  mount -o bind /dev/urandom /dev/random
  if ! is_mounted /cache; then
    mount /cache > /dev/null 2>&1
  fi
  if ! is_mounted /data; then
    mount /data > /dev/null 2>&1
    if [ -z "$(ls -A /sdcard)" ]; then
      mount -o bind /data/media/0 /sdcard
    fi
  fi
  mount -o ro -t auto /product > /dev/null 2>&1
  mount -o ro -t auto /system_ext > /dev/null 2>&1
  [ "$ANDROID_ROOT" ] || ANDROID_ROOT="/system"
  setup_mountpoint $ANDROID_ROOT
  if ! is_mounted $ANDROID_ROOT; then
    mount -o ro -t auto $ANDROID_ROOT > /dev/null 2>&1
  fi
  # Mount bind operation
  case $ANDROID_ROOT in
    /system_root) setup_mountpoint /system;;
    /system)
      if ! is_mounted /system && ! is_mounted /system_root; then
        setup_mountpoint /system_root
        mount -o ro -t auto /system_root
      elif [ -f "/system/system/build.prop" ]; then
        setup_mountpoint /system_root
        mount --move /system /system_root
        mount -o bind /system_root/system /system
      fi
      if [ $? != 0 ]; then
        umount -l /system > /dev/null 2>&1
      fi
    ;;
  esac
  case $ANDROID_ROOT in
    /system)
      if ! is_mounted $ANDROID_ROOT && [ -e /dev/block/mapper/system$slot ]; then
        mount -o ro -t auto /dev/block/mapper/system$slot /system_root > /dev/null 2>&1
        mount -o ro -t auto /dev/block/mapper/product$slot /product > /dev/null 2>&1
        mount -o ro -t auto /dev/block/mapper/system_ext$slot /system_ext > /dev/null 2>&1
      fi
      if ! is_mounted $ANDROID_ROOT && [ -e /dev/block/bootdevice/by-name/system$slot ]; then
        mount -o ro -t auto /dev/block/bootdevice/by-name/system$slot /system_root > /dev/null 2>&1
        mount -o ro -t auto /dev/block/bootdevice/by-name/product$slot /product > /dev/null 2>&1
        mount -o ro -t auto /dev/block/bootdevice/by-name/system_ext$slot /system_ext > /dev/null 2>&1
      fi
    ;;
  esac
  # Mount bind operation
  if is_mounted /system_root; then
    if [ -f "/system_root/build.prop" ]; then
      mount -o bind /system_root /system
    else
      mount -o bind /system_root/system /system
    fi
  fi
  for block in system product system_ext; do
    for slot in "" _a _b; do
      blockdev --setrw /dev/block/mapper/$block$slot > /dev/null 2>&1
    done
  done
  mount -o remount,rw -t auto / > /dev/null 2>&1
  ui_print "- Mounting /system"
  if [ "$(grep -w -o '/system' /proc/mounts)" ]; then
    mount -o remount,rw -t auto /system > /dev/null 2>&1
    is_mounted /system || on_abort "! Cannot mount /system"
  fi
  if [ "$(grep -w -o '/system_root' /proc/mounts)" ]; then
    mount -o remount,rw -t auto /system_root > /dev/null 2>&1
    is_mounted /system_root || on_abort "! Cannot mount /system_root"
  fi
  ui_print "- Mounting /product"
  mount -o remount,rw -t auto /product > /dev/null 2>&1
  ui_print "- Mounting /system_ext"
  mount -o remount,rw -t auto /system_ext > /dev/null 2>&1
  # Set installation layout
  SYSTEM="/system"
  # Backup installation layout
  SYSTEM_AS_SYSTEM="$SYSTEM"
  # System is writable
  if ! touch $SYSTEM/.rw >/dev/null 2>&1; then
    on_abort "! Read-only file system"
  fi
  # Product is a dedicated partition
  if is_mounted /product; then
    ln -sf /product /system
  fi
}

unmount_all() {
  if [ "$BOOTMODE" = "false" ]; then
    ui_print "- Unmounting partitions"
    umount -l /system > /dev/null 2>&1
    umount -l /system_root > /dev/null 2>&1
    umount -l /product > /dev/null 2>&1
    umount -l /system_ext > /dev/null 2>&1
    umount -l /dev/random > /dev/null 2>&1
  fi
}

f_cleanup() { (find .$TMP -mindepth 1 -maxdepth 1 -type f -not -name 'recovery.log' -not -name 'busybox-arm' -exec rm -rf '{}' \;); }

d_cleanup() { (find .$TMP -mindepth 1 -maxdepth 1 -type d -exec rm -rf '{}' \;); }

on_abort() {
  ui_print "$*"
  $BOOTMODE && exit 1
  umount_apex
  unmount_all
  recovery_cleanup
  f_cleanup
  d_cleanup
  ui_print "! Installation failed"
  ui_print " "
  true
  sync
  exit 1
}

on_installed() {
  umount_apex
  unmount_all
  recovery_cleanup
  f_cleanup
  d_cleanup
  ui_print "- Installation complete"
  ui_print " "
  true
  sync
  exit "$?"
}

mk_component() {
  for d in \
    $UNZIP_DIR/tmp_sys \
    $UNZIP_DIR/tmp_priv \
    $UNZIP_DIR/tmp_priv_setup \
    $UNZIP_DIR/tmp_framework \
    $UNZIP_DIR/tmp_config \
    $UNZIP_DIR/tmp_default \
    $UNZIP_DIR/tmp_perm \
    $UNZIP_DIR/tmp_pref \
    $UNZIP_DIR/tmp_ware \
    $UNZIP_DIR/tmp_overlay; do
    install -d "$d"
    chmod -R 0755 $TMP
  done
}

system_layout() {
  SYSTEM_ADDOND="$SYSTEM/addon.d"
  SYSTEM_APP="$SYSTEM/app"
  SYSTEM_PRIV_APP="$SYSTEM/priv-app"
  SYSTEM_ETC_CONFIG="$SYSTEM/etc/sysconfig"
  SYSTEM_ETC_DEFAULT="$SYSTEM/etc/default-permissions"
  SYSTEM_ETC_PERM="$SYSTEM/etc/permissions"
  SYSTEM_ETC_PREF="$SYSTEM/etc/preferred-apps"
  SYSTEM_FIRMWARE="$SYSTEM/etc/firmware"
  SYSTEM_FRAMEWORK="$SYSTEM/framework"
  SYSTEM_OVERLAY="$SYSTEM/product/overlay"
}

pkg_TMPPriv() {
  file_list="$(find "$TMP_PRIV/" -mindepth 1 -type f | cut -d/ ${DEST})"
  dir_list="$(find "$TMP_PRIV/" -mindepth 1 -type d | cut -d/ ${DEST})"
  for file in $file_list; do
    install -D "$TMP_PRIV/${file}" "$SYSTEM_PRIV_APP/${file}"
    chmod 0644 "$SYSTEM_PRIV_APP/${file}"
  done
  for dir in $dir_list; do
    chmod 0755 "$SYSTEM_PRIV_APP/${dir}"
  done
}

pkg_TMPPerm() {
  file_list="$(find "$TMP_PERMISSION/" -mindepth 1 -type f | cut -d/ ${DEST})"
  dir_list="$(find "$TMP_PERMISSION/" -mindepth 1 -type d | cut -d/ ${DEST})"
  for file in $file_list; do
    install -D "$TMP_PERMISSION/${file}" "$SYSTEM_ETC_PERM/${file}"
    chmod 0644 "$SYSTEM_ETC_PERM/${file}"
  done
  for dir in $dir_list; do
    chmod 0755 "$SYSTEM_ETC_PERM/${dir}"
  done
}

pkg_TMPWare() {
  file_list="$(find "$TMP_FIRMWARE/" -mindepth 1 -type f | cut -d/ ${DEST})"
  dir_list="$(find "$TMP_FIRMWARE/" -mindepth 1 -type d | cut -d/ ${DEST})"
  for file in $file_list; do
    install -D "$TMP_FIRMWARE/${file}" "$SYSTEM_FIRMWARE/${file}"
    chmod 0644 "$SYSTEM_FIRMWARE/${file}"
  done
  for dir in $dir_list; do
    chmod 0755 "$SYSTEM_FIRMWARE/${dir}"
  done
}

pkg_TMPOverlay() {
  file_list="$(find "$TMP_OVERLAY/" -mindepth 1 -type f | cut -d/ ${DEST})"
  dir_list="$(find "$TMP_OVERLAY/" -mindepth 1 -type d | cut -d/ ${DEST})"
  for file in $file_list; do
    install -D "$TMP_OVERLAY/${file}" "$SYSTEM_OVERLAY/${file}"
    chmod 0644 "$SYSTEM_OVERLAY/${file}"
  done
  for dir in $dir_list; do
    chmod 0755 "$SYSTEM_OVERLAY/${dir}"
  done
}

is_uninstaller() {
  rm -rf $SYSTEM_PRIV_APP/DPS
  rm -rf $SYSTEM_PRIV_APP/Launcher
  rm -rf $SYSTEM_PRIV_APP/QAWallet
  rm -rf $SYSTEM_PRIV_APP/WallPicker
  rm -rf $SYSTEM_ETC_PERM/launcher.xml
  rm -rf $SYSTEM_OVERLAY/Launcher.apk
  rm -rf $SYSTEM_OVERLAY/PixelConfig.apk
  rm -rf $SYSTEM_OVERLAY/PixelFont.apk
  rm -rf $SYSTEM_OVERLAY/PixelRecent.apk
  rm -rf $SYSTEM_OVERLAY/PixelUIGX.apk
  rm -rf $SYSTEM_OVERLAY/IconPack.apk
  # Create DPS Firmware
  install -d $SYSTEM_FIRMWARE
}

sdk_v25_install() {
  # Dedicated V3 Partitions
  P="/product /system_ext"
  # Remove Pixel Launcher
  for f in $SYSTEM $SYSTEM/product $SYSTEM/system_ext $P; do
    find $f -type d -name '*Launcher*' -exec rm -rf {} +
    find $f -type d -name '*QuickAcc*' -exec rm -rf {} +
  done
  ui_print "- Installing Pixel Launcher"
  ZIP="zip/core/DPS.tar.xz
       zip/core/Launcher.tar.xz
       zip/core/QAWallet.tar.xz
       zip/core/WallPicker.tar.xz
       zip/Permissions.tar.xz
       zip/Firmware.tar.xz
       zip/overlay/Launcher.tar.xz
       zip/overlay/PixelConfig.tar.xz
       zip/overlay/PixelFont.tar.xz
       zip/overlay/PixelRecent.tar.xz
       zip/overlay/PixelUIGX.tar.xz
       zip/overlay/IconPack.tar.xz"
  if [ "$BOOTMODE" = "false" ]; then
    for f in $ZIP; do unzip -oq "$ZIPFILE" "$f" -d "$TMP"; done
  fi
  # Allow unpack, when installation base is Magisk
  if [[ "$(getprop "sys.bootmode")" = "2" ]]; then
    for f in $ZIP; do $(unzip -oq "$ZIPFILE" "$f" -d "$TMP"); done
  fi
  tar -xf $ZIP_FILE/core/DPS.tar.xz -C $TMP_PRIV
  tar -xf $ZIP_FILE/core/Launcher.tar.xz -C $TMP_PRIV
  tar -xf $ZIP_FILE/core/QAWallet.tar.xz -C $TMP_PRIV
  tar -xf $ZIP_FILE/core/WallPicker.tar.xz -C $TMP_PRIV
  tar -xf $ZIP_FILE/Permissions.tar.xz -C $TMP_PERMISSION
  tar -xf $ZIP_FILE/Firmware.tar.xz -C $TMP_FIRMWARE
  tar -xf $ZIP_FILE/overlay/Launcher.tar.xz -C $TMP_OVERLAY
  tar -xf $ZIP_FILE/overlay/PixelConfig.tar.xz -C $TMP_OVERLAY 2>/dev/null
  tar -xf $ZIP_FILE/overlay/PixelFont.tar.xz -C $TMP_OVERLAY 2>/dev/null
  tar -xf $ZIP_FILE/overlay/PixelRecent.tar.xz -C $TMP_OVERLAY 2>/dev/null
  tar -xf $ZIP_FILE/overlay/PixelUIGX.tar.xz -C $TMP_OVERLAY 2>/dev/null
  tar -xf $ZIP_FILE/overlay/IconPack.tar.xz -C $TMP_OVERLAY 2>/dev/null
  pkg_TMPPriv
  pkg_TMPPerm
  pkg_TMPWare
  pkg_TMPOverlay
  # Purge runtime permissions
  rm -rf $(find /data -iname "runtime-permissions.xml")
}

backup_script() {
  if [ -d "$SYSTEM_ADDOND" ]; then
    ui_print "- Installing OTA survival script"
    ADDOND="70-launcher.sh"
    if [ "$BOOTMODE" = "false" ]; then
      unzip -oq "$ZIPFILE" "$ADDOND" -d "$TMP"
    fi
    # Allow unpack, when installation base is Magisk
    if [[ "$(getprop "sys.bootmode")" = "2" ]]; then
      $(unzip -oq "$ZIPFILE" "$ADDOND" -d "$TMP")
    fi
    # Install OTA survival script
    rm -rf $SYSTEM_ADDOND/$ADDOND
    cp -f $TMP/$ADDOND $SYSTEM_ADDOND/$ADDOND
    chmod 0755 $SYSTEM_ADDOND/$ADDOND
    ch_con system "$SYSTEM_ADDOND/$ADDOND"
  fi
}

pre_install() {
  umount_all
  recovery_actions
  on_partition_check
  ab_partition
  system_as_root
  super_partition
  mount_all
  mount_apex
}

df_partition() {
  # Get the available space left on the device
  size=`df -k /system | tail -n 1 | tr -s ' ' | cut -d' ' -f4`
  # Disk space in human readable format (k=1024)
  ds_hr=`df -h /system | tail -n 1 | tr -s ' ' | cut -d' ' -f4`
  # Common target
  CAPACITY="$CAPACITY"
  # Print partition type
  partition="System"
}

df_checker() {
  if [ "$ZIPNAME" = "uninstall" ]; then
    return 255
  fi
  if [ "$size" -gt "$CAPACITY" ]; then
    ui_print "- ${partition} Space: $ds_hr"
  else
    ui_print "! Insufficient partition size"
    on_abort "! Current space: $ds_hr"
  fi
}

post_install() {
  df_partition
  df_checker
  build_defaults
  mk_component
  system_layout
  is_uninstaller
  sdk_v25_install
  backup_script
  on_installed
}

# Begin installation
{
  pre_install
  post_install
}
# End installation

# End method
