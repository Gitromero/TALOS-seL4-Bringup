"""Host side of network boot: stage an image, make sure the TFTP server
(tftp/serve.sh, dnsmasq in Docker) runs, find the address U-Boot should use,
and prove the server hands the file out before anything touches the board."""
import os
import re
import shutil
import socket
import subprocess

from . import HOST, Failure

CONTAINER = "sel4-tftp"     # container name used by tftp/serve.sh


def stage(image, root):
    """Copy image into the TFTP root under a TFTP-safe name; returns the name.
    Copy, then rename, so the server never serves a half-written file."""
    name = re.sub(r"[^A-Za-z0-9._-]", "_", os.path.basename(image))
    target = os.path.join(root, name)
    os.makedirs(root, exist_ok=True)
    if os.path.realpath(image) != os.path.realpath(target):
        tmp = os.path.join(root, f".{name}.tmp")
        shutil.copyfile(image, tmp)
        os.replace(tmp, target)
    os.chmod(target, 0o644)
    return name


def _run(*cmd):
    """Run a helper command; a missing program counts as failing with no output."""
    try:
        return subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
    except FileNotFoundError:
        return subprocess.CompletedProcess(cmd, 127, "", "")


def ensure_server(serve_script):
    """Start the server if it isn't running; returns the interface it serves on."""
    if not shutil.which("docker"):
        raise Failure(HOST, "docker is required for the TFTP server (docs/flashing.md#network-boot)")
    if not _run("docker", "ps", "-q", "--filter", f"name=^{CONTAINER}$").stdout.strip():
        print(f"==> starting the TFTP server ({os.path.relpath(serve_script)} start)", flush=True)
        if subprocess.run([serve_script, "start"], stdout=subprocess.DEVNULL).returncode:
            raise Failure(HOST, "the TFTP server did not start (tftp/serve.sh logs)")
    args = _run("docker", "inspect", "-f", "{{range .Args}}{{println .}}{{end}}", CONTAINER).stdout
    m = re.search(r"^--interface=(\S+)$", args, re.M)
    if not m:
        raise Failure(HOST, f"can't tell which interface the {CONTAINER} container serves on")
    return m.group(1)


def address(interface):
    """This host's IPv4 address on interface."""
    out = _run("ip", "-4", "-br", "addr", "show", interface).stdout.split()
    if len(out) < 3:
        raise Failure(HOST, f"no IPv4 address on the TFTP interface '{interface}'; pass --server-ip")
    return out[2].split("/")[0]


def probe(server_ip, name, port=69):
    """Ask the server for block 1 of name; raise Failure unless it sends it."""
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.settimeout(3)
    try:
        s.sendto(b"\x00\x01" + name.encode() + b"\x00octet\x00", (server_ip, port))   # read request
        packet, peer = s.recvfrom(1024)
        if packet[:2] != b"\x00\x03":                                             # not DATA
            reason = packet[4:].split(b"\0")[0].decode(errors="replace")
            raise Failure(HOST, f"the TFTP server refused {name}: {reason}")
        s.sendto(b"\x00\x05\x00\x00done\x00", peer)                                # error ends it
    except socket.timeout:
        raise Failure(HOST, f"no answer from the TFTP server at {server_ip}:{port} "
                            "(tftp/serve.sh status, tftp/serve.sh logs)") from None
    finally:
        s.close()


def firewall_note():
    """A hint when a host firewall is likely to drop the board's requests."""
    if _run("systemctl", "is-active", "ufw").stdout.strip() == "active":
        return ("ufw is active. If the transfer stalls (T T T), allow UDP 69 from the board "
                "(docs/flashing.md#network-boot).")
    return None
