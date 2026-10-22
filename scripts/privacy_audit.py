#!/usr/bin/env python3
"""Scan build artifacts for personal or machine-specific data.

Usage: python3 -I scripts/privacy_audit.py FILE... [--json OUT]

Checks every printable string (length >= 4) and every embedded flattened
device tree in each file. The current user's name, home directory and the
host name are searched for but never written to the output: matches are
reported under the labels <user>, <home> and <hostname>.
"""
import getpass
import json
import os
import re
import socket
import struct
import subprocess
import sys
import tempfile

PATTERNS = {
    "absolute_path": re.compile(rb"(?<![\w.])/(?:home|root|Users|usr|opt|build|tmp|media|mnt|var|etc|srv|workspace)/[\w./+-]+"),
    "email": re.compile(rb"[\w.+-]+@[\w-]+\.[\w.-]+"),
    "ipv4": re.compile(rb"(?<![\d.])(?:\d{1,3}\.){3}\d{1,3}(?![\d.])"),
    "mac_text": re.compile(rb"(?i)(?<![0-9a-f:])(?:[0-9a-f]{2}:){5}[0-9a-f]{2}(?![0-9a-f:])"),
    "secret_like": re.compile(rb"(?i)(?:password|passwd|secret|api[_-]?key|token|BEGIN [A-Z ]*PRIVATE KEY|ghp_[0-9a-z]{20,}|AKIA[0-9A-Z]{16})"),
}
# Paths that come from the published toolchain itself, not from any build host.
TOOLCHAIN_PATH = re.compile(rb"^/build/reproducible-path/")


def strings(data, minlen=4):
    return re.findall(rb"[\x20-\x7e]{%d,}" % minlen, data)


def fdt_blobs(data):
    """Yield (offset, blob) for every plausible FDT inside data."""
    i = 0
    while True:
        i = data.find(b"\xd0\x0d\xfe\xed", i)
        if i < 0:
            return
        if i + 40 <= len(data):
            size = struct.unpack(">I", data[i + 4:i + 8])[0]
            if 64 < size <= len(data) - i:
                yield i, data[i:i + size]
        i += 4


def dtb_findings(blob):
    with tempfile.NamedTemporaryFile(suffix=".dtb") as f:
        f.write(blob)
        f.flush()
        res = subprocess.run(["dtc", "-q", "-I", "dtb", "-O", "dts", f.name],
                             capture_output=True, text=True)
    if res.returncode != 0:
        return {"valid": False}
    dts = res.stdout
    macs = re.findall(r"local-mac-address = \[([0-9a-f ]+)\]", dts)
    return {
        "valid": True,
        "model": (re.search(r'model = "([^"]*)"', dts) or [None, None])[1],
        "mac_addresses": macs,
        "nonzero_macs": [m for m in macs if m.replace(" ", "").strip("0")],
        "unique_id_properties": sorted(set(re.findall(
            r"\b(serial-number|kaslr-seed|rng-seed|mac-address|board-serial)\b", dts))),
    }


def audit(path, sensitive):
    data = open(path, "rb").read()
    strs = strings(data)
    result = {"file": os.path.basename(path), "size": len(data), "checks": {}}
    for name, pat in PATTERNS.items():
        hits = sorted({m.group(0).decode(errors="replace") for s in strs for m in pat.finditer(s)})
        if name == "absolute_path":
            toolchain = [h for h in hits if TOOLCHAIN_PATH.match(h.encode())]
            hits = [h for h in hits if not TOOLCHAIN_PATH.match(h.encode())]
            result["checks"]["toolchain_paths"] = {"count": len(toolchain), "examples": toolchain[:3]}
        result["checks"][name] = {"count": len(hits), "examples": hits[:5]}
    for label, value in sensitive.items():
        if value:
            n = sum(s.count(value.encode()) for s in strs)
            result["checks"][label] = {"count": n}
    result["fdts"] = [dict(offset=hex(o), size=len(b), **dtb_findings(b)) for o, b in fdt_blobs(data)]
    return result


def main(argv):
    out = None
    if "--json" in argv:
        k = argv.index("--json")
        out = argv[k + 1]
        argv = argv[:k] + argv[k + 2:]
    if not argv:
        sys.exit(__doc__)
    sensitive = {
        "<user>": getpass.getuser(),
        "<home>": os.path.expanduser("~"),
        "<hostname>": socket.gethostname(),
    }
    report = {"tool": "privacy_audit.py", "results": [audit(p, sensitive) for p in argv]}
    text = json.dumps(report, indent=2)
    # Never echo the sensitive values themselves (examples may contain them).
    for label, value in sorted(sensitive.items(), key=lambda kv: -len(kv[1] or "")):
        if value:
            text = text.replace(value, label)
    text = re.sub(r'<home>/[^"]*', "<home>/...", text)
    if out:
        open(out, "w").write(text + "\n")
    print(text)


if __name__ == "__main__":
    main(sys.argv[1:])
