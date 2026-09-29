#!/bin/bash

# Build the rescue-only ISO inside the Arch build container. It is the Omarchy
# ISO's live system with the rescue layer and without the installer: no offline
# package mirror (4.8GB of the stock ISO), no configurator entries. The live
# root installs straight from the online repos of the chosen channel, which
# also keeps it under GitHub's 2GB release asset limit.
#
# Expects the same mounts as omarchy-iso's build-iso.sh: /archiso, /builder
# (omarchy-iso's builder), /configs (omarchy-iso's configs with the rescue
# layer applied), and /out.

set -euo pipefail

OMARCHY_MIRROR="${OMARCHY_MIRROR:-stable}"
case $OMARCHY_MIRROR in
edge) OMARCHY_SETTINGS_PACKAGE=omarchy-settings-dev ;;
*) OMARCHY_SETTINGS_PACKAGE=omarchy-settings ;;
esac
online_conf=pacman-online-$OMARCHY_MIRROR.conf

# Same container setup as build-iso.sh: a full upgrade so the tools match the
# mirror, and the Omarchy signing key trusted for the [omarchy] repo.
pacman-key --init
pacman --noconfirm -Sy archlinux-keyring
pacman --noconfirm -Syu archiso grub
pacman-key --add /builder/omarchy.gpg
pacman-key --lsign-key 40DFB630FF42BCFFB047046CF0134EE680CAC571
pacman --config "/configs/$online_conf" --noconfirm -Sy omarchy-keyring
pacman-key --populate omarchy

profile=/var/cache/rescue-profile
rm -rf "$profile"
mkdir -p "$profile"

# Arch's releng profile, then Omarchy's additions on top, as build-iso.sh does.
cp -r /archiso/configs/releng/* "$profile/"
rm "$profile/airootfs/etc/motd"
rm -rf "$profile/airootfs/etc/systemd/system/multi-user.target.wants/reflector.service"
rm -rf "$profile/airootfs/etc/systemd/system/reflector.service.d"
rm -rf "$profile/airootfs/etc/xdg/reflector"
cp -r /configs/* "$profile/"
echo "$OMARCHY_MIRROR" >"$profile/airootfs/root/omarchy_mirror"

# The live system's own packages: releng's, the ones build-iso.sh adds for the
# live environment (read from it so the two can't drift), and the rescue set.
eval "$(grep '^arch_packages=' /builder/build-iso.sh)"
{
  printf '%s\n' "${arch_packages[@]}"
  grep -hv '^#\|^$' /configs/rescue.packages
} >>"$profile/packages.x86_64"
# build-iso.sh's reasoning applies here too: the live ISO boots linux-t2, and
# broadcom-wl is the only thing that would pull stock linux back in.
sed -i -E '/^(linux|broadcom-wl)$/d' "$profile/packages.x86_64"
sort -u -o "$profile/packages.x86_64" "$profile/packages.x86_64"

# Install from the online repos, and leave the live system pointed at them.
# There's no offline mirror, and mkarchiso refuses a permissions entry for a
# path that doesn't exist, so drop that one.
sed -i \
  -e "s/^pacman_conf=.*/pacman_conf=\"$online_conf\"/" \
  -e '\|"/var/cache/omarchy/mirror/offline/"|d' \
  "$profile/profiledef.sh"
cp "$profile/$online_conf" "$profile/airootfs/etc/pacman.conf"

mkarchiso -v -w "$profile/work/" -o /out/ "$profile/"

if [[ -n ${HOST_UID:-} && -n ${HOST_GID:-} ]]; then
  chown -R "$HOST_UID:$HOST_GID" /out/
fi
