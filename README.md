# Omarchy Rescue

The Omarchy ISO, plus a rescue mode: a live Omarchy console with the rescue
tools you'd reach for from SystemRescue, and Claude Code, Codex, and OpenCode
ready to help diagnose and fix a machine that won't boot.

The installer is untouched. The boot menu gains two entries in front of it:

- **Omarchy Rescue** (default): a kmscon console on tty1 with JetBrains Mono,
  truecolor, and the Tokyo Night palette, no desktop needed.
- **Omarchy Rescue, basic console**: the plain kernel console with `nomodeset`,
  for GPUs kmscon can't drive.
- **Omarchy**: the stock installer, exactly as shipped.

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
bin/omarchy-rescue-make          # stable channel; --edge, --rc, etc. pass through
bin/omarchy-rescue-boot          # boot the newest ISO in QEMU (needs qemu-desktop, edk2-ovmf)
```

`omarchy-rescue-make` clones the pinned `omarchy-iso` submodule into `build/`,
applies the rescue layer with `builder/apply-rescue.sh`, and runs omarchy-iso's
own build (Docker). The ISO lands in `release/`. Unlike upstream, it doesn't
mount the host's pacman cache into the build, so it never needs sudo to wipe it.

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
```

## How rescue mode works

The rescue entries boot the same kernel and initramfs as the installer, adding
`omarchy.rescue=kms` (or `=tty`) and `cow_spacesize=50%` so the live overlay
has room for pacman and agent state. That flag:

- starts kmscon on tty1 in place of the autologin getty, falling back to the
  getty if kmscon fails,
- stops the installer wizard from starting on tty1,
- switches pacman from the ISO's offline mirror to the online repos, so tools
  can be installed and agents updated (`omarchy-rescue update`).

The rescue packages go into the live root through the same offline mirror
mkarchiso builds the live root from, so they also sit in that mirror. Removing
that duplication would shave a few hundred MB.
