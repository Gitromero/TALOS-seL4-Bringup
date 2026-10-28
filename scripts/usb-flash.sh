#!/usr/bin/env bash
#
# Load an image into the Discovery Kit's RAM over USB and boot it, with no
# hands on the board: reset the board through the HSS console, stop U-Boot's
# autoboot, send the image with U-Boot's `loady` (YMODEM over the U-Boot serial
# port on USB-C #1), verify it, bootm it, and watch the console until it
# passes, fails, or goes quiet. Needs only the USB-C cable: no Ethernet, no
# TFTP server, no SD card swaps. (scripts/network-flash.sh does the same over
# Ethernet and TFTP.)
#
# RAM ONLY: nothing is written to the SD card, and U-Boot's saved environment is
# never touched (no saveenv). A power cycle boots whatever is on the card.
# This automates docs/FLASHING.md; the manual procedure there is the reference.
#
# Usage:
#   scripts/usb-flash.sh <image> [options]
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
#   --baud RATE        serial speed for the transfer: 1500000 (default), 921600,
#                      460800 or 115200. The console goes back to 115200 afterwards.
#   --log FILE         console log (default: logs/usb-flash-<time>.log)
#   -h, --help         this text
#
# Environment: UBOOT_PORT, HSS_PORT override the serial ports. Defaults, in order:
#   /dev/polarfire-uboot, /dev/polarfire-hss (host/udev/99-polarfire-discovery.rules)
#   /dev/serial/by-id/*FlashPro5*-if02-port0, -if01-port0
#
# Watching along: the ports are shared through scripts/serial-share.py, so a
# console opened with `scripts/serial-share.py console <port>` (or `pf console`)
# shows the whole flash live (it stays quiet during the transfer itself: YMODEM
# replies are single control bytes). A plain picocom/screen on the same port
# can't share, so the script refuses to start while one is open. Don't type in
# the console until the result appears. See docs/SHARED_CONSOLE.md.
#
# Exit codes: 0 passed / booted, 1 the image reported failure, 2 usage or host
# setup problem, 3 board or U-Boot problem (no prompt, transfer, checksum),
# 4 timed out waiting for the result, 130 interrupted.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"

die() { echo "ERROR: $*" >&2; exit 2; }
note() { echo "==> $*"; }

usage() {
    sed -n '/^# Usage:/,/^# Exit codes/p' "$0" | sed '$d; s/^# \{0,1\}//' >&2
    exit 2
}

IMAGE="" EXPECT="" FAIL="" IDLE=20 TIMEOUT=600 CONSOLE=0 RESET=1 BAUD=1500000 LOG=""
while (($#)); do
    case "$1" in
        --expect) EXPECT="${2:?}"; shift ;;
        --fail) FAIL="${2:?}"; shift ;;
        --idle) IDLE="${2:?}"; shift ;;
        --timeout) TIMEOUT="${2:?}"; shift ;;
        --console) CONSOLE=1 ;;
        --no-reset) RESET=0 ;;
        --baud) BAUD="${2:?}"; shift ;;
        --log) LOG="${2:?}"; shift ;;
        --server-ip) die "--server-ip is a network-boot option: scripts/network-flash.sh (pf flash --lan)" ;;
        -h|--help) usage ;;
        -*) echo "unknown option: $1" >&2; usage ;;
        *) [ -z "$IMAGE" ] || usage; IMAGE="$1" ;;
    esac
    shift
done
[ -n "$IMAGE" ] || usage
[ -f "$IMAGE" ] || die "image not found: $IMAGE"
[[ "$IDLE" =~ ^[0-9]+$ && "$TIMEOUT" =~ ^[0-9]+$ ]] || die "--idle and --timeout take whole seconds"
case "$BAUD" in
    115200|460800|921600|1500000) ;;
    *) die "--baud must be 1500000, 921600, 460800 or 115200 (3000000 does not work on this board)" ;;
esac

command -v python3 >/dev/null || die "python3 is required"
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
# ACKs this script waits for.
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
note "image: $IMAGE ($(stat -c %s "$IMAGE") bytes)"

[ -n "$LOG" ] || { mkdir -p "$REPO/logs"; LOG="$REPO/logs/usb-flash-$(date +%Y%m%d-%H%M%S).log"; }
note "console: $UBOOT_PORT at $BAUD baud for the transfer$( ((RESET)) && echo ", reset via HSS on $HSS_PORT")"
note "log: $LOG"
echo

set +e
python3 -I - "$UBOOT_PORT" "${HSS_PORT:-}" "$IMAGE" "$LOG" "$BAUD" \
    "$RESET" "$CONSOLE" "$EXPECT" "$FAIL" "$IDLE" "$TIMEOUT" "$SHARE" <<'PY'
import binascii, importlib.util, os, re, select, signal, struct, sys, time, zlib

(uboot_port, hss_port, path, log_path, baud,
 reset, console, expect, fail, idle, timeout, share_path) = sys.argv[1:]
baud, reset, console, idle, timeout = int(baud), int(reset), int(console), int(idle), int(timeout)
LOAD = 0x8E000000          # same staging address as the SD and network procedures
PROMPT = rb"RISC-V # ?$"
SOH, STX, EOT, ACK, NAK, CAN, C = 0x01, 0x02, 0x04, 0x06, 0x15, 0x18, ord("C")

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

# --- Serial, through the serial-share broker so consoles can watch along ---
sys.dont_write_bytecode = True      # no __pycache__ in scripts/
spec = importlib.util.spec_from_file_location("serial_share", share_path)
share = importlib.util.module_from_spec(spec)
spec.loader.exec_module(share)

u = share.ensure_broker(uboot_port)
log = open(log_path, "wb")
buf = b""
last_rx = time.time()
quiet = False                       # during YMODEM: log, but don't echo ACK bytes

def pump(t):
    global buf, last_rx
    if select.select([u], [], [], t)[0]:
        d = u.recv(4096)
        if not d:
            bye(3, f"lost the console: {uboot_port} closed (board unplugged?)")
        buf += d
        last_rx = time.time()
        log.write(d); log.flush()
        if not quiet:
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

# --- YMODEM sender (1K blocks, CRC-16) ---
def wait_byte(choices, t):
    """Next byte from choices, skipping others; keeps the rest of buf, since
    U-Boot sends ACK and 'C' back to back."""
    global buf
    end = time.time() + t
    while True:
        for i, x in enumerate(buf):
            if x in choices:
                buf = buf[i + 1:]
                return x
        buf = b""
        if time.time() >= end:
            return None
        pump(0.05)

def block(seq, payload, size):
    payload = payload.ljust(size, b"\x1a" if seq else b"\x00")
    head = bytes([SOH if size == 128 else STX, seq & 0xFF, 0xFF - (seq & 0xFF)])
    return head + payload + binascii.crc_hqx(payload, 0).to_bytes(2, "big")

def send_block(pkt):
    for _ in range(10):
        u.sendall(pkt)
        r = wait_byte({ACK, NAK, CAN}, 10)
        if r == ACK:
            return True
        if r == CAN:
            return False
    return False

def ymodem(name):
    """Send data; True when U-Boot has acknowledged everything."""
    if wait_byte({C}, 15) is None:
        return False
    header = name.encode()[:100] + b"\0" + str(len(data)).encode() + b"\0"
    if not send_block(block(0, header, 128)) or wait_byte({C}, 10) is None:
        return False
    t0, step = time.time(), max(1, len(data) // 1024 // 4)
    for n, i in enumerate(range(0, len(data), 1024), 1):
        if not send_block(block(n, data[i:i + 1024], 1024)):
            return False
        if n % step == 0:
            print(f"==> {i + 1024:>9} / {len(data)} bytes, {(i + 1024) / 1024 / (time.time() - t0):.0f} KiB/s",
                  flush=True)
    for _ in range(10):
        u.sendall(bytes([EOT]))
        if wait_byte({ACK, NAK}, 5) == ACK:
            break
    else:
        return False
    if wait_byte({C}, 5) is None:              # U-Boot asks for the next file
        return False
    ok = send_block(block(0, b"", 128))         # empty header: no more files
    print(f"==> sent in {time.time() - t0:.1f} s", flush=True)
    return ok

ctl = None
def transfer(name):
    """One loady attempt; returns the size U-Boot reports, or None. Always
    leaves U-Boot at its prompt at 115200 (unless the board stops answering)."""
    global ctl, quiet
    ctl = share.control(uboot_port)            # baud and latency revert when this closes
    try:
        return loady(name)
    finally:
        ctl.close(); ctl = None

def loady(name):
    global quiet
    ctl.cmd("lowlat 1")                        # FTDI latency timer 16 ms -> 1 ms per ACK
    if baud != 115200:
        send(f"loady {LOAD:#x} {baud}")
        if not wait_for(rb"press ENTER", 10):
            return None
        time.sleep(0.2)                         # U-Boot switches 50 ms after the message
        ctl.cmd(f"baud {baud}")
        u.sendall(b"\r")
    else:
        send(f"loady {LOAD:#x}")
    quiet = True                               # from here U-Boot also sends 'C' bytes
    ok = bool(wait_for(rb"Ready for binary \(ymodem\) download[^\n]*\n", 10))
    if ok:
        print(f"\n==> U-Boot is receiving at {baud} baud; sending {len(data)} bytes", flush=True)
    ok = ok and ymodem(os.path.basename(path))
    if not ok:
        u.sendall(bytes([CAN]) * 5)             # make U-Boot give up
    quiet = False
    m = wait_for(rb"Total Size\s*=\s*0x[0-9a-fA-F]+\s*=\s*(\d+) Bytes", 10, rb"aborted")
    if baud != 115200:
        wait_for(rb"press ESC", 10)
        time.sleep(0.2)
        ctl.cmd("baud 115200")
        u.sendall(b"\x1b")
    wait_for(PROMPT, 10)
    return int(m.group(1)) if ok and m else None

def interrupted(*_):
    if quiet:                                  # mid-transfer: stop U-Boot's loady
        u.sendall(bytes([CAN]) * 5)
    bye(130, "interrupted" + (" (U-Boot may still be in loady: the next flash resets it)" if quiet else ""))
signal.signal(signal.SIGINT, interrupted)

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

# --- 2. YMODEM into RAM, with one retry ---
for attempt in range(2):
    try:
        got = transfer(os.path.basename(path))
    except OSError as e:                      # control socket busy or refused a setting
        bye(3, str(e))
    if got == len(data):
        break
    print(f"\n==> USB transfer attempt {attempt + 1} failed"
          + (f" (U-Boot received {got} of {len(data)} bytes)" if got else ""), flush=True)
else:
    bye(3, f"USB (YMODEM) transfer failed. Try a lower --baud (921600, or 115200), and check\n"
           f"    that nothing else types on the U-Boot console during the flash.")

send(f"crc32 {LOAD:#x} ${{filesize}}")         # loady sets filesize but not fileaddr
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
