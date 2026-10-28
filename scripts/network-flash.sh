#!/usr/bin/env bash
#
# Network-boot an image on the Discovery Kit with no hands on the board:
# stage it for TFTP, reset the board through the HSS console, stop U-Boot's
# autoboot, DHCP + TFTP the image into RAM, verify it, bootm it, and watch the
# console until it passes, fails, or goes quiet. `scripts/pf flash --lan` runs
# this; plain `scripts/pf flash` loads over USB instead (scripts/usb-flash.sh).
#
# RAM ONLY: nothing is written to the SD card, and U-Boot's saved environment is
# never touched (no saveenv). A power cycle boots whatever is on the card.
# This automates docs/NETBOOT.md; the manual procedure there is the reference.
#
# Usage:
#   scripts/network-flash.sh <image> [options]
#
#   <image>            legacy uImage or FIT, e.g. images/sel4test.uImage
#   --expect REGEX     success pattern (Python regex). Default: the sel4test result
#                      line if the image contains sel4test, else none (see --idle)
#   --fail REGEX       extra failure pattern (added to the built-in ones)
#   --idle SEC         with no success pattern: done after SEC s of silence (20)
#   --timeout SEC      give up SEC s after "Starting kernel" (600)
#   --console          after booting, stay attached to the U-Boot/seL4 console
#                      (without --expect, hands over right after "Starting kernel")
#   --no-reset         don't reset via HSS: use the U-Boot prompt if it is already
#                      there, else wait for you to reset/power on the board
#   --server-ip IP     address U-Boot downloads from (default: this host's address
#                      on the TFTP server's interface)
#   --log FILE         console log (default: logs/network-flash-<time>.log)
#   -h, --help         this text
#
# Environment: UBOOT_PORT, HSS_PORT override the serial ports. Defaults, in order:
#   /dev/polarfire-uboot, /dev/polarfire-hss (host/udev/99-polarfire-discovery.rules)
#   /dev/serial/by-id/*FlashPro5*-if02-port0, -if01-port0
#   IFACE is passed through to tftp/serve.sh.
#
# Watching along: the ports are shared through scripts/serial-share.py, so a
# console opened with `scripts/serial-share.py console <port>` shows the whole
# flash live, before, during and after. A plain picocom/screen on the same port
# can't share (it would take bytes this script waits for), so the script refuses
# to start while one is open. Don't type in the console until the result appears.
#
# Exit codes: 0 passed / booted, 1 the image reported failure, 2 usage or host
# setup problem, 3 board or U-Boot problem (no prompt, DHCP, TFTP, checksum),
# 4 timed out waiting for the result, 130 interrupted.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
TFTP_ROOT="$REPO/tftp/root"
SERVER_NAME=sel4-tftp   # container name used by tftp/serve.sh

die() { echo "ERROR: $*" >&2; exit 2; }
note() { echo "==> $*"; }

usage() {
    sed -n '/^# Usage:/,/^# Exit codes/p' "$0" | sed '$d; s/^# \{0,1\}//' >&2
    exit 2
}

IMAGE="" EXPECT="" FAIL="" IDLE=20 TIMEOUT=600 CONSOLE=0 RESET=1 SERVER_IP="" LOG=""
while (($#)); do
    case "$1" in
        --expect) EXPECT="${2:?}"; shift ;;
        --fail) FAIL="${2:?}"; shift ;;
        --idle) IDLE="${2:?}"; shift ;;
        --timeout) TIMEOUT="${2:?}"; shift ;;
        --console) CONSOLE=1 ;;
        --no-reset) RESET=0 ;;
        --server-ip) SERVER_IP="${2:?}"; shift ;;
        --log) LOG="${2:?}"; shift ;;
        -h|--help) usage ;;
        -*) echo "unknown option: $1" >&2; usage ;;
        *) [ -z "$IMAGE" ] || usage; IMAGE="$1" ;;
    esac
    shift
done
[ -n "$IMAGE" ] || usage
[ -f "$IMAGE" ] || die "image not found: $IMAGE"
[[ "$IDLE" =~ ^[0-9]+$ && "$TIMEOUT" =~ ^[0-9]+$ ]] || die "--idle and --timeout take whole seconds"

command -v python3 >/dev/null || die "python3 is required"
command -v docker >/dev/null || die "docker is required for the TFTP server (docs/NETBOOT.md)"
SHARE="$REPO/scripts/serial-share.py"

# --- Serial ports -----------------------------------------------------------
find_port() {   # <udev-name> <interface>
    if [ -e "/dev/$1" ]; then echo "/dev/$1"; return; fi
    local p
    for p in /dev/serial/by-id/*FlashPro5*-if"$2"-port0; do
        [ -e "$p" ] && { echo "$p"; return; }
    done
}
UBOOT_PORT="${UBOOT_PORT:-$(find_port polarfire-uboot 02)}"
HSS_PORT="${HSS_PORT:-$(find_port polarfire-hss 01)}"
[ -n "$UBOOT_PORT" ] || die "U-Boot serial port not found. Is the board's USB-C #1 connected, and are all
       four FT4232H channels bound? See docs/SETUP.md#serial-console-on-a-linux-host"
[ -r "$UBOOT_PORT" ] && [ -w "$UBOOT_PORT" ] || die "no read/write access to $UBOOT_PORT (add yourself to 'dialout')"
if ((RESET)); then
    [ -n "$HSS_PORT" ] || die "HSS serial port not found (needed for the reset; or use --no-reset)"
    [ -w "$HSS_PORT" ] || die "no write access to $HSS_PORT"
fi

# Linux gives each byte to only one reader. The serial-share broker copies the
# output to everyone, but any other program holding a port open would steal the
# output this script waits for.
port_users() {   # <port> <pid to ignore>
    local real fd pids=""
    real="$(readlink -f "$1")"
    for fd in /proc/[0-9]*/fd/*; do
        [ "$(readlink "$fd" 2>/dev/null)" = "$real" ] || continue
        fd="${fd#/proc/}"; pids+="${fd%%/*} "
    done
    for p in $(tr ' ' '\n' <<<"$pids" | sort -u); do
        [ "$p" = "$2" ] && continue
        printf '%s(%s) ' "$p" "$(cat "/proc/$p/comm" 2>/dev/null)"
    done
}
check_ports=("$UBOOT_PORT")
((RESET)) && check_ports+=("$HSS_PORT")
for p in "${check_ports[@]}"; do
    broker="$(python3 -I "$SHARE" sock "$p" | awk '{print $2}')"
    users="$(port_users "$p" "$broker")"
    [ -z "$users" ] || die "$p is open in another program: $users
       Close it (picocom: Ctrl-a Ctrl-x). To watch while flashing, open the console with
       scripts/serial-share.py console $p   instead: it shares the port with this script."
done

# --- Image ------------------------------------------------------------------
case "$(od -An -tx1 -N4 "$IMAGE" | tr -d ' \n')" in
    27051956|d00dfeed) ;;   # legacy uImage, FIT
    *) die "$IMAGE is not a U-Boot image (no uImage or FIT header). bootm needs mkimage output." ;;
esac
# Stage under a TFTP-safe name. Copy, then rename, so the server never serves a
# half-written file.
NAME="$(basename "$IMAGE" | tr -c 'A-Za-z0-9._\n-' '_')"
mkdir -p "$TFTP_ROOT"
if [ "$(readlink -f "$IMAGE")" != "$(readlink -f "$TFTP_ROOT/$NAME")" ]; then
    cp "$IMAGE" "$TFTP_ROOT/.$NAME.tmp"
    mv -f "$TFTP_ROOT/.$NAME.tmp" "$TFTP_ROOT/$NAME"
fi
chmod a+r "$TFTP_ROOT/$NAME"
note "image: $IMAGE -> tftp/root/$NAME ($(stat -c %s "$TFTP_ROOT/$NAME") bytes)"

# --- TFTP server ------------------------------------------------------------
if [ -z "$(docker ps -q --filter "name=^${SERVER_NAME}$" 2>/dev/null)" ]; then
    note "starting TFTP server (tftp/serve.sh start)"
    "$REPO/tftp/serve.sh" start >/dev/null
fi
TFTP_IFACE="$(docker inspect -f '{{range .Args}}{{println .}}{{end}}' "$SERVER_NAME" \
    | sed -n 's/^--interface=//p')"
if [ -z "$SERVER_IP" ]; then
    SERVER_IP="$(ip -4 -br addr show "$TFTP_IFACE" 2>/dev/null | awk '{print $3}' | cut -d/ -f1)"
    [ -n "$SERVER_IP" ] || die "no IPv4 address on the TFTP interface '$TFTP_IFACE'; pass --server-ip"
fi
note "TFTP server: $SERVER_IP ($TFTP_IFACE)"
if systemctl is-active -q ufw 2>/dev/null; then
    echo "    note: ufw is active. If the transfer times out (T T T), allow UDP 69 (docs/NETBOOT.md step 3)."
fi

[ -n "$LOG" ] || { mkdir -p "$REPO/logs"; LOG="$REPO/logs/network-flash-$(date +%Y%m%d-%H%M%S).log"; }
note "console: $UBOOT_PORT$( ((RESET)) && echo ", reset via HSS on $HSS_PORT")"
note "log: $LOG"
echo

set +e
python3 -I - "$UBOOT_PORT" "${HSS_PORT:-}" "$SERVER_IP" "$NAME" "$TFTP_ROOT/$NAME" "$LOG" \
    "$RESET" "$CONSOLE" "$EXPECT" "$FAIL" "$IDLE" "$TIMEOUT" "$SHARE" <<'PY'
import importlib.util, os, re, select, signal, socket, struct, sys, time, zlib

(uboot_port, hss_port, server_ip, name, path, log_path,
 reset, console, expect, fail, idle, timeout, share_path) = sys.argv[1:]
reset, console, idle, timeout = int(reset), int(console), int(idle), int(timeout)
LOAD = 0x8E000000          # same staging address as docs/NETBOOT.md
PROMPT = rb"RISC-V # ?$"

def bye(code, msg):
    print(f"\n\n==> {msg}", flush=True)
    sys.exit(code)

# --- Host-side checks before touching the board ---
data = open(path, "rb").read()
magic = struct.unpack(">I", data[:4])[0]
if magic == 0x27051956:                       # legacy uImage
    size, load = struct.unpack(">II", data[12:20])
    if load <= LOAD < load + size:
        bye(2, f"image loads at {load:#x} and is {size} bytes: it would overwrite itself at {LOAD:#x}")
elif magic != 0xD00DFEED:                     # FIT
    bye(2, "not a U-Boot image (no uImage or FIT header). bootm needs mkimage output.")
crc = zlib.crc32(data) & 0xFFFFFFFF

if not expect and b"Test suite passed" in data:
    expect = r"Test suite passed\. \d+ tests passed\. \d+ tests disabled\."
fail_re = r"Test suite failed|Kernel panic|seL4 failed assertion"
if fail:
    fail_re += "|" + fail

# The server must hand out the file before we reset anything: one TFTP read
# request for block 1, from this host to its own LAN address.
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.settimeout(3)
try:
    s.sendto(b"\x00\x01" + name.encode() + b"\x00octet\x00", (server_ip, 69))
    pkt, _ = s.recvfrom(1024)
    if pkt[:2] != b"\x00\x03":
        reason = pkt[4:].split(b"\0")[0].decode(errors="replace")
        bye(2, f"TFTP server refused {name}: {reason}")
    s.sendto(b"\x00\x05\x00\x00done\x00", _)   # error packet ends the transfer
except socket.timeout:
    bye(2, f"no answer from the TFTP server at {server_ip}:69 (tftp/serve.sh status / logs)")
finally:
    s.close()

# --- Serial, through the serial-share broker so consoles can watch along ---
sys.dont_write_bytecode = True      # no __pycache__ in scripts/
spec = importlib.util.spec_from_file_location("serial_share", share_path)
share = importlib.util.module_from_spec(spec)
spec.loader.exec_module(share)

u = share.ensure_broker(uboot_port)
log = open(log_path, "wb")
buf = b""
last_rx = time.time()

def pump(t):
    global buf, last_rx
    if select.select([u], [], [], t)[0]:
        d = u.recv(4096)
        if not d:
            bye(3, f"lost the console: {uboot_port} closed (board unplugged?)")
        buf += d
        last_rx = time.time()
        log.write(d); log.flush()
        os.write(1, d)

def wait_for(pat, t, fail_pat=None):
    """Consume output until pat matches (returns the match), fail_pat matches
    (returns None) or t seconds pass (returns None)."""
    global buf
    end = time.time() + t
    while True:
        if fail_pat:
            m = re.search(fail_pat, buf, re.M)
            if m:
                buf = buf[m.end():]
                return None
        m = re.search(pat, buf, re.M)
        if m:
            buf = buf[m.end():]
            return m
        if time.time() >= end:
            return None
        pump(0.2)

def send(line):
    global buf
    buf = b""
    for ch in line.encode():           # U-Boot drops characters typed too fast
        u.sendall(bytes([ch])); time.sleep(0.008)
    u.sendall(b"\r")

def cmd(line, t, what):
    send(line)
    if not wait_for(PROMPT, t):
        bye(3, f"no U-Boot prompt after '{line}' ({what})")

def stop_autoboot(t):
    if not wait_for(rb"Hit any key to stop autoboot", t):
        return False
    for _ in range(10):
        u.sendall(b" ")
        if wait_for(PROMPT, 0.3):
            return True
    return bool(wait_for(PROMPT, 5))

signal.signal(signal.SIGINT, lambda *a: bye(130, "interrupted"))

# --- 1. Get to RISC-V # ---
if reset:
    h = share.ensure_broker(hss_port)
    h.sendall(b"\r"); time.sleep(0.3)
    h.sendall(b"RESET\r"); time.sleep(0.2)
    h.close()
    print("==> board reset via HSS; waiting for U-Boot", flush=True)
    if not stop_autoboot(90):
        bye(3, "U-Boot autoboot prompt not seen within 90 s of the reset. Check the HSS console\n"
               "    (it should answer Enter with '>>'), or power-cycle the board and retry.")
else:
    send("")
    if wait_for(PROMPT, 2):
        print("==> already at the U-Boot prompt", flush=True)
    else:
        print("==> reset or power on the board now (waiting up to 5 min)", flush=True)
        if not stop_autoboot(300):
            bye(3, "U-Boot autoboot prompt not seen")

# --- 2. Network + download, with retries for the flaky parts ---
cmd("setenv autoload no", 10, "setenv")
for attempt in range(3):
    send("dhcp")
    m = wait_for(rb"DHCP client bound to address (\S+)", 45)
    wait_for(PROMPT, 15)
    if m:
        break
    print(f"\n==> DHCP attempt {attempt + 1} failed", flush=True)
else:
    bye(3, "no DHCP lease. Is Ethernet in connector #2, on a network with a DHCP server?")

for attempt in range(2):
    send(f"tftpboot {LOAD:#x} {server_ip}:{name}")
    m = wait_for(rb"Bytes transferred = (\d+)", 180, rb"T T T T|TFTP error|Retry count exceeded")
    wait_for(PROMPT, 30)
    if m and int(m.group(1)) == len(data):
        break
    print(f"\n==> TFTP attempt {attempt + 1} failed", flush=True)
else:
    bye(3, f"TFTP download failed. If you saw 'T T T', a firewall on this host is dropping\n"
           f"    UDP 69 from the board (docs/NETBOOT.md step 3).")

send("crc32 ${fileaddr} ${filesize}")
m = wait_for(rb"==> ([0-9a-f]{8})", 20)
wait_for(PROMPT, 10)
if not m or int(m.group(1), 16) != crc:
    bye(3, f"CRC mismatch: board {m.group(1).decode() if m else '?'}, file {crc:08x}")
print(f"\n==> CRC32 {crc:08x} matches", flush=True)

send(f"iminfo {LOAD:#x}")
m = wait_for(rb"Verifying Checksum \.\.\. OK", 20, rb"Bad (Data|Header) CRC|Unknown image format")
wait_for(PROMPT, 10)
if not m:
    bye(3, "iminfo did not verify the image")

# --- 3. Boot and watch ---
send(f"bootm {LOAD:#x} - ${{fdtcontroladdr}}")
m = wait_for(rb"Starting kernel \.\.\.", 30, rb"ERROR|Wrong Image|Bad Data CRC|Unsupported")
if not m:
    bye(3, "bootm did not start the image")

if console and not expect:
    log.close(); u.close()
    print("\n==> booted; attaching console (exit: Ctrl-a Ctrl-x)", flush=True)
    sys.exit(0)

start = time.time()
exp_re = expect.encode() if expect else None
while True:
    m = re.search(fail_re.encode(), buf, re.M)
    if m:
        pump(1)
        bye(1, f"FAILED: {m.group(0).decode(errors='replace')}")
    if exp_re:
        m = re.search(exp_re, buf, re.M)
        if m:
            pump(1)
            bye(0, f"PASSED: {m.group(0).decode(errors='replace')}")
    elif time.time() - last_rx >= idle:
        bye(0, f"booted; no console output for {idle} s, so treating the run as finished")
    if time.time() - start >= timeout:
        bye(4, f"timed out after {timeout} s" + (f" waiting for /{expect}/" if expect else ""))
    pump(0.5)
PY
rc=$?
set -e

if ((CONSOLE)) && ((rc == 0)); then
    exec python3 -I "$SHARE" console "$UBOOT_PORT"
fi
exit $rc
