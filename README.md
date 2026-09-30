# Omarchy Rescue

A rescue USB for Omarchy: a live Omarchy console with the rescue tools you'd
reach for from SystemRescue, and Claude Code, Codex, and OpenCode ready to help
diagnose and fix a machine that won't boot.

![Omarchy Rescue's welcome screen](docs/screenshots/welcome.png)

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

`omarchy-rescue-mount` asks for your disk passphrase and mounts the whole
install the way it mounts itself, from its own fstab:

![omarchy-rescue-mount unlocking and mounting an encrypted Omarchy install](docs/screenshots/mount.png)

### Signing in without a browser

Every agent signs in from the terminal by printing a link to open on another
device. `omarchy-rescue-login` hands that link to your phone: as soon as the
agent prints it, a QR code pops up. Scan it and you get a page that opens the
sign-in link. What happens next depends on the agent:

- **Claude Code** wants a long code pasted back. The phone page has a box for
  it: send it, and the code is typed into the console; press Enter there to
  use it.
- **OpenCode** needs nothing more: its link carries the code, so approving it
  on the phone signs the console in. This is the sign-in for an OpenCode
  account (Zen); for another provider's API key, run `opencode auth login`.
- **Codex** works the other way round: the console shows a one-time code that
  you enter on the page the link opens. Press Enter to close the QR code and
  read it. Your ChatGPT account has to allow this first: turn on device code
  sign-in for Codex in ChatGPT's security settings, or the sign-in page
  refuses the code.

The page lives on this machine, on the local network, behind a random
address; it serves one paste and stops. Pasted text never includes a newline,
so nothing runs until you press Enter. **C-Space u** does the same for any
link on screen.

`omarchy-rescue-share` goes further and serves the whole tmux session to your
phone's browser with ttyd. It's a root shell behind a random address, so stop
it with `omarchy-rescue-share stop` when done.

| The QR code pops up by itself | The page it opens on your phone |
| --- | --- |
| ![A QR code for handing the sign-in link to a phone](docs/screenshots/sign-in-qr.png) | ![The phone page: open the link, paste the code back](docs/screenshots/sign-in-phone.png) |

| `omarchy-rescue-share` | `omarchy-rescue` |
| --- | --- |
| ![A QR code for driving the console from a phone](docs/screenshots/share.png) | ![The rescue menu](docs/screenshots/menu.png) |

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

To release, commit hand-written notes as `packaging/release-notes/vYYYY.MM.DD.md`,
then push a matching `v*` tag. GitHub Actions builds the rescue-only ISO and
publishes it with its checksum and those notes; without a notes file it stops
before building.

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
