#!/usr/bin/env python3
"""Boot an Omarchy Rescue ISO in QEMU, headless, and check that the rescue
console comes up and the agents start.

  test/boot-smoke.py [release/omarchy-rescue-*.iso]

It waits for the boot, then types one command into the console over QMP: the
agents' versions, the console service's state and the rescue helpers, written
to the VM's serial port, which QEMU saves to a file this reads. Keys typed
before the console is up are lost, so it types again until the answer arrives.
Exits non-zero, with the serial output, if anything is missing.
"""
import glob
import json
import os
import re
import socket
import subprocess
import sys
import tempfile
import time

KEYS = {
    " ": "spc", "-": "minus", "/": "slash", ".": "dot", "_": "shift-minus", "|": "shift-backslash",
    "=": "equal", ":": "shift-semicolon", ">": "shift-dot", "<": "shift-comma", ";": "semicolon",
    "&": "shift-7", "$": "shift-4", ",": "comma", "{": "shift-bracket_left", "}": "shift-bracket_right",
    "\n": "ret",
}

FIRMWARE = [
    ("/usr/share/edk2/x64/OVMF_CODE.4m.fd", "/usr/share/edk2/x64/OVMF_VARS.4m.fd"),  # Arch
    ("/usr/share/OVMF/OVMF_CODE_4M.fd", "/usr/share/OVMF/OVMF_VARS_4M.fd"),  # Debian, Ubuntu
]

HELPERS = "omarchy-rescue omarchy-rescue-login omarchy-rescue-mount omarchy-rescue-qr omarchy-rescue-share omarchy-rescue-keyboard"
COMMAND = (
    "clear; { claude --version; codex --version; opencode --version; "
    "systemctl is-active omarchy-rescue-console; "
    f"for h in {HELPERS}; do command -v $h || echo missing $h; done; "
    "echo SMOKE-END; } >/dev/ttyS0 2>&1\n"
)


class QMP:
    def __init__(self, path):
        for _ in range(100):
            try:
                self.sock = socket.socket(socket.AF_UNIX)
                self.sock.connect(path)
                break
            except OSError:
                time.sleep(0.2)
        else:
            sys.exit("QEMU's monitor never came up")
        self.file = self.sock.makefile("rw")
        self.file.readline()
        self.call("qmp_capabilities")

    def call(self, execute, **arguments):
        self.file.write(json.dumps({"execute": execute, "arguments": arguments}) + "\n")
        self.file.flush()
        while True:
            reply = json.loads(self.file.readline())
            if "return" in reply or "error" in reply:
                return reply

    def key(self, name):
        self.call("human-monitor-command", **{"command-line": f"sendkey {name}"})
        time.sleep(0.03)

    def type(self, text):
        for ch in text:
            self.key(KEYS.get(ch) or (f"shift-{ch.lower()}" if ch.isupper() else ch))


def main():
    isos = sys.argv[1:] or sorted(glob.glob("release/omarchy-rescue-*.iso"), key=os.path.getmtime)[-1:]
    if not isos:
        sys.exit("No ISO given and none in release/")
    iso = isos[0]
    code, vars_template = next(((c, v) for c, v in FIRMWARE if os.path.exists(c)), (None, None))
    if not code:
        sys.exit("No OVMF firmware found (edk2-ovmf on Arch, ovmf on Debian and Ubuntu)")
    kvm = os.access("/dev/kvm", os.R_OK | os.W_OK)

    work = tempfile.mkdtemp(prefix="rescue-smoke-")
    vars_file, monitor, serial = (os.path.join(work, n) for n in ("vars.fd", "qmp.sock", "serial.log"))
    with open(vars_template, "rb") as src, open(vars_file, "wb") as dst:
        dst.write(src.read())

    qemu = subprocess.Popen([
        "qemu-system-x86_64", "-machine", "q35", "-m", "6144", "-smp", "4",
        *(["-enable-kvm", "-cpu", "host"] if kvm else []),
        "-drive", f"if=pflash,format=raw,readonly=on,file={code}",
        "-drive", f"if=pflash,format=raw,file={vars_file}",
        "-drive", f"file={iso},media=cdrom,format=raw,readonly=on",
        "-device", "virtio-vga", "-display", "none",
        "-netdev", "user,id=n0", "-device", "virtio-net-pci,netdev=n0",
        "-serial", f"file:{serial}", "-qmp", f"unix:{monitor},server,nowait",
    ])
    try:
        qmp = QMP(monitor)
        print(f"Booting {iso} ({'KVM' if kvm else 'no KVM, slow'})", flush=True)
        # Let the boot menu count down before typing anything into it.
        time.sleep(60 if kvm else 180)
        for attempt in range(1, 16):
            qmp.key("ctrl-c")
            qmp.type(COMMAND)
            for _ in range(30):
                time.sleep(1)
                text = open(serial, errors="replace").read()
                if "SMOKE-END" in text:
                    return check(text)
            print(f"No answer yet (attempt {attempt}); typing again", flush=True)
        sys.exit("The rescue console never answered.\n" + open(serial, errors="replace").read()[-3000:])
    finally:
        qemu.kill()


def check(text):
    # The answer to the last command that arrived; an earlier, cut-off attempt
    # may have left output before it.
    out = text.split("SMOKE-END")[-2]
    print(out, flush=True)
    problems = []
    if not re.search(r"\(Claude Code\)", out):
        problems.append("claude --version")
    if not re.search(r"^codex-cli \S+", out, re.M):
        problems.append("codex --version")
    if not re.search(r"^\d+\.\d+\.\d+\s*$", out, re.M):
        problems.append("opencode --version")
    if not re.search(r"^active\s*$", out, re.M):
        problems.append("the rescue console service is not active")
    problems += re.findall(r"^missing (\S+)", out, re.M)
    if problems:
        sys.exit("Smoke test failed: " + ", ".join(problems))
    print("Smoke test passed")


if __name__ == "__main__":
    main()
