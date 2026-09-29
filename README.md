# Omarchy Rescue

A rescue USB for Omarchy: a live Omarchy console with the rescue tools you'd
reach for from SystemRescue, and Claude Code, Codex, and OpenCode ready to help
diagnose and fix a machine that won't boot.

Download the ISO from [Releases](https://github.com/crmne/omarchy-rescue/releases),
check it against its `.sha256`, and write it to a USB stick. It boots into:

- **Omarchy Rescue** (default): a kmscon console on tty1 with JetBrains Mono,
  truecolor, and the Tokyo Night palette, no desktop needed.
- **Omarchy Rescue, basic console**: the plain kernel console with `nomodeset`,
  for GPUs kmscon can't drive.

It's built from the Omarchy ISO itself, so it boots the same kernel on the same
hardware. It can also be built as the full Omarchy ISO with rescue added in
front of the untouched installer; see [Building](#building).

## Using it

Boot the rescue entry and you land in a tmux session running Omarchy's shell.

```
impala                  connect to Wi-Fi (Ethernet just works)
omarchy-rescue-login    sign in to claude, codex, or opencode
omarchy-rescue-mount    unlock and mount your Omarchy install at /mnt
arch-chroot /mnt        run commands inside it
claude                  describe what's broken
omarchy-rescue          a menu of all of the above
```

### Signing in without a browser

Every agent signs in from the terminal by printing a link to open on another
device:

- `codex login --device-auth` shows a link and a short code; open it on your
  phone and you're done.
- `claude auth login` and `opencode auth login` also want a code pasted back.

Two ways to get links onto your phone:

- **C-Space u** shows the last link on screen as a QR code.
- **`omarchy-rescue-share`** serves this same tmux session to your phone's
  browser with ttyd and shows a QR code for it. Tap the sign-in link there and
  paste the code straight back. The address carries a random token and it's a
  root shell, so stop it with `omarchy-rescue-share stop` when done.

### What the agents know

Each agent reads `/usr/share/omarchy-rescue/AGENTS.md` (linked in as
`~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md`, and
`~/.config/opencode/AGENTS.md`). It tells them where they are, how an Omarchy
install is laid out (LUKS, Btrfs subvolumes, Limine, snapper), how to reach its
journal and chroot into it, and to diagnose read-only first and never run
anything destructive without a clear yes.

## Building

```bash
bin/omarchy-rescue-make                   # rescue-only ISO (~1.8GB), stable channel
bin/omarchy-rescue-make --with-installer  # the full Omarchy ISO plus rescue (~6.6GB)
bin/omarchy-rescue-boot                   # boot the newest ISO in QEMU (needs qemu-desktop, edk2-ovmf)
```

`--edge` and `--rc` pick the channel. The ISO lands in `release/`.

Both builds clone the pinned `omarchy-iso` submodule into `build/` and apply
the rescue layer with `builder/apply-rescue.sh`, in Docker. The rescue-only
build (`builder/build-rescue-only.sh`) makes the Omarchy ISO's live system
without the installer and its 4.8GB offline package mirror, installing from
the online repos instead. `--with-installer` runs omarchy-iso's own build with
the rescue entries added in front of the installer. Neither mounts the host's
pacman cache into the build, so neither needs sudo to wipe it the way upstream
does.

Pushing a `v*` tag builds the rescue-only ISO in GitHub Actions and publishes
it as a release with its checksum.

To track a newer Omarchy ISO, bump the submodule. `apply-rescue.sh` checks
every edit it makes and fails the build if an upstream change moved one of its
anchors.

## Layout

```
configs/rescue.packages      packages added to the live environment
configs/airootfs/            files added to the live root
  etc/systemd/system/        kmscon console, fallback getty, online pacman
  etc/profile.d/             lands every rescue login in the shared tmux session
  etc/kmscon/                font and palette
  usr/local/bin/             omarchy-rescue* helpers
  usr/share/omarchy-rescue/  AGENTS.md, tmux.conf, online pacman configs
builder/apply-rescue.sh      layers all of the above onto an omarchy-iso checkout
builder/build-rescue-only.sh builds the rescue-only ISO in the Arch container
```

## How rescue mode works

The rescue entries boot the same kernel and initramfs as the Omarchy installer, adding
`omarchy.rescue=kms` (or `=tty`) and `cow_spacesize=50%` so the live overlay
has room for pacman and agent state. That flag:

- starts kmscon on tty1 in place of the autologin getty, falling back to the
  getty if kmscon fails,
- stops the installer wizard from starting on tty1,
- points pacman at the online repos, so tools can be installed and agents
  updated (`omarchy-rescue update`).
