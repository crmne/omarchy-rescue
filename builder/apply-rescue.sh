#!/bin/bash

# Layer Omarchy Rescue onto an omarchy-iso checkout: the rescue files, the
# extra packages, and the rescue boot entries. By default the stock installer
# stays exactly as it is, alongside rescue. With --rescue-only, its boot entries
# are dropped too, for the rescue-only ISO (builder/build-rescue-only.sh).
# Every edit is checked afterwards, so a change upstream that moves one of the
# anchors fails the build here instead of shipping an ISO with no rescue entry.
#
#   builder/apply-rescue.sh [--rescue-only] <omarchy-iso checkout>

set -euo pipefail

RESCUE_ONLY=
if [[ ${1:-} == --rescue-only ]]; then
  RESCUE_ONLY=1
  shift
fi

RESCUE_ROOT=$(realpath "${BASH_SOURCE[0]%/*}/..")
ISO=$(realpath "${1:?usage: apply-rescue.sh [--rescue-only] <omarchy-iso checkout>}")
CONFIGS=$ISO/configs

RESCUE_ARGS="omarchy.rescue=kms cow_spacesize=50%"
RESCUE_BASIC_ARGS="omarchy.rescue=tty cow_spacesize=50% nomodeset"

fail() {
  echo "apply-rescue: $*" >&2
  exit 1
}

expect() {
  local file=$1 pattern=$2
  grep -qF -- "$pattern" "$file" || fail "expected '$pattern' in ${file#"$ISO"/} after patching"
}

# Files and packages.
cp -a "$RESCUE_ROOT/configs/airootfs/." "$CONFIGS/airootfs/"
cp "$RESCUE_ROOT/configs/rescue.packages" "$CONFIGS/rescue.packages"
for mirror in stable rc edge; do
  cp "$CONFIGS/pacman-online-$mirror.conf" "$CONFIGS/airootfs/usr/share/omarchy-rescue/"
done

# Rescue packages join the live environment's package list, which also puts
# them in the offline mirror mkarchiso installs the live root from.
build=$ISO/builder/build-iso.sh
anchor='printf '"'"'%s\n'"'"' "${arch_packages[@]}" >> "$build_cache_dir/packages.x86_64"'
expect "$build" "$anchor"
ANCHOR=$anchor awk '
  { print }
  $0 == ENVIRON["ANCHOR"] {
    print "grep -hv '"'"'^#\\|^$'"'"' /configs/rescue.packages >> \"$build_cache_dir/packages.x86_64\""
    print "sort -u -o \"$build_cache_dir/packages.x86_64\" \"$build_cache_dir/packages.x86_64\""
  }
' "$build" >"$build.new"
mv "$build.new" "$build"
chmod +x "$build"
expect "$build" "/configs/rescue.packages"

# Until omacom/omarchy-iso#196 lands: arch-mact2 replaced apple-bcm-firmware
# with apple-bcm-firmware-fetcher, and the stock build fails resolving the old
# name. Same mapping as that PR; skipped once upstream carries it.
if ! grep -q 'apple-bcm-firmware-fetcher' "$build"; then
  sed -i "s|sed 's/^broadcom-wl\$/broadcom-wl-dkms/'|sed -e 's/^broadcom-wl\$/broadcom-wl-dkms/' -e 's/^apple-bcm-firmware\$/apple-bcm-firmware-fetcher/'|" "$build"
  expect "$build" "apple-bcm-firmware-fetcher"
fi

# The installer wizard must not start in a rescue boot, even on the fallback
# console where tty1 autologs in the way it does for an install.
script=$CONFIGS/airootfs/root/.automated_script.sh
anchor='[[ $(tty) == /dev/tty1 ]] || exit 0'
expect "$script" "$anchor"
ANCHOR=$anchor awk '
  { print }
  $0 == ENVIRON["ANCHOR"] { print "grep -qw omarchy.rescue /proc/cmdline && exit 0" }
' "$script" >"$script.new"
mv "$script.new" "$script"
expect "$script" "grep -qw omarchy.rescue /proc/cmdline && exit 0"

# ISO identity and file modes.
profile=$CONFIGS/profiledef.sh
if [[ -n $RESCUE_ONLY ]]; then
  iso_name=omarchy-rescue
  iso_application="Omarchy Rescue"
else
  iso_name=omarchy-with-rescue
  iso_application="Omarchy Installer and Rescue"
fi
sed -i \
  -e "s/^iso_name=.*/iso_name=\"$iso_name\"/" \
  -e "s/^iso_application=.*/iso_application=\"$iso_application\"/" \
  "$profile"
{
  echo
  echo "# Omarchy Rescue"
  echo "file_permissions+=("
  for bin in "$RESCUE_ROOT"/configs/airootfs/usr/local/bin/*; do
    echo "  [\"/usr/local/bin/${bin##*/}\"]=\"0:0:755\""
  done
  echo ")"
} >>"$profile"
expect "$profile" "iso_name=\"$iso_name\""
expect "$profile" '["/usr/local/bin/omarchy-rescue"]="0:0:755"'

# GRUB (UEFI, and loopback for Ventoy-style boots): add two rescue entries,
# cloned from the stock Omarchy entry so they boot the same kernel with the
# same arguments, make rescue the default, and show the menu. Rescue-only drops
# the installer's own entries.
add_grub_entries() {
  local cfg=$1
  expect "$cfg" 'menuentry "Omarchy (%ARCH%, ${archiso_platform})"'
  awk -v rescue="$RESCUE_ARGS" -v basic="$RESCUE_BASIC_ARGS" -v rescue_only="$RESCUE_ONLY" '
    function emit(title, id, args, drop_splash,   i, line) {
      for (i = 1; i <= n; i++) {
        line = block[i]
        if (i == 1) {
          sub(/menuentry "Omarchy \(/, "menuentry \"" title " (", line)
          sub(/--id .archlinux./, "--id '"'"'" id "'"'"'", line)
        }
        if (line ~ /^[[:space:]]*linux /) {
          if (drop_splash) gsub(/ quiet splash/, "", line)
          line = line " " args
        }
        print line
      }
      print ""
    }
    /^menuentry "Omarchy \(/ && !done { collecting = 1 }
    rescue_only && /^menuentry "Omarchy with speakup/ { skipping = 1 }
    skipping { if (/^}/) { skipping = 0; getline } next }
    collecting { block[++n] = $0 }
    !collecting { print }
    collecting && /^}/ {
      collecting = 0; done = 1
      emit("Omarchy Rescue", "omarchy-rescue", rescue, 0)
      emit("Omarchy Rescue, basic console", "omarchy-rescue-basic", basic, 1)
      if (!rescue_only) for (i = 1; i <= n; i++) print block[i]
    }
  ' "$cfg" >"$cfg.new"
  mv "$cfg.new" "$cfg"
  sed -i \
    -e 's/^default=archlinux$/default=omarchy-rescue/' \
    -e 's/^timeout=0$/timeout=10/' \
    -e 's/^timeout_style=hidden$/timeout_style=menu/' \
    "$cfg"
  expect "$cfg" "--id 'omarchy-rescue'"
  expect "$cfg" "--id 'omarchy-rescue-basic'"
  expect "$cfg" "$RESCUE_ARGS"
  expect "$cfg" "default=omarchy-rescue"
  expect "$cfg" "timeout=10"
  if [[ -n $RESCUE_ONLY ]] && grep -q -- "--id 'archlinux" "$cfg"; then
    fail "installer entries left in ${cfg#"$ISO"/} for a rescue-only ISO"
  fi
}
add_grub_entries "$CONFIGS/grub/grub.cfg"
add_grub_entries "$CONFIGS/grub/loopback.cfg"

# Syslinux (BIOS): the same two entries ahead of the installer (or alone, for
# rescue-only), rescue default.
syslinux=$CONFIGS/syslinux/archiso_sys-linux.cfg
append=$(awk '/^LABEL arch64$/ { found = 1 } found && /^APPEND / { sub(/^APPEND /, ""); print; exit }' "$syslinux")
[[ -n $append ]] || fail "no APPEND line for LABEL arch64 in ${syslinux#"$ISO"/}"
kernel_lines=$(awk '/^LABEL arch64$/ { found = 1 } found && /^(LINUX|INITRD) / { print } found && /^APPEND / { exit }' "$syslinux")
{
  cat <<CFG
LABEL omarchyrescue
TEXT HELP
Boot Omarchy Rescue: a live console with rescue tools and AI agents.
ENDTEXT
MENU LABEL Omarchy ^Rescue (x86_64, BIOS)
$kernel_lines
APPEND $append $RESCUE_ARGS

LABEL omarchyrescuebasic
TEXT HELP
Boot Omarchy Rescue on the plain text console, for displays kmscon can't drive.
ENDTEXT
MENU LABEL Omarchy Rescue, ^basic console (x86_64, BIOS)
$kernel_lines
APPEND ${append/ quiet splash/} $RESCUE_BASIC_ARGS

CFG
  [[ -n $RESCUE_ONLY ]] || cat "$syslinux"
} >"$syslinux.new"
mv "$syslinux.new" "$syslinux"
sed -i 's/^DEFAULT arch64$/DEFAULT omarchyrescue/' "$CONFIGS/syslinux/archiso_sys.cfg"
expect "$syslinux" "LABEL omarchyrescuebasic"
expect "$CONFIGS/syslinux/archiso_sys.cfg" "DEFAULT omarchyrescue"

echo "Applied Omarchy Rescue to $ISO"
