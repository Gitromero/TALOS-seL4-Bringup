"""Drive the board's U-Boot console: get to a prompt, load an image into RAM
(YMODEM over the serial port, or TFTP over Ethernet), verify it, boot it and
watch the console for a result.

Everything goes through a serial_share broker socket, so consoles opened with
`scripts/board.py console` see the whole run. RAM only: nothing here writes
the SD card, eMMC, QSPI or U-Boot's saved environment (no `saveenv`).
"""
import os
import re
import socket
import struct
import sys
import time
import zlib

from . import BOARD, HOST, IMAGE_FAILED, OK, TIMEOUT, Failure, serial_share, ymodem

LOAD = 0x8E000000    # staging address used by every procedure in docs/; bootm copies from here
PROMPT = rb"RISC-V # ?$"

# Timeouts, in seconds.
RESET_TO_AUTOBOOT = 90       # HSS RESET until U-Boot's autoboot countdown
MANUAL_RESET_WAIT = 300      # --no-reset: time for someone to reset or power on the board
COMMAND = 10                 # a quick U-Boot command back to its prompt
DHCP = 45                    # one dhcp attempt
TFTP_TRANSFER = 180          # one tftpboot attempt
BOOTM_START = 30             # bootm until "Starting kernel"

UIMAGE_MAGIC, FIT_MAGIC = 0x27051956, 0xD00DFEED
FAIL_PATTERNS = r"Test suite failed|Kernel panic|seL4 failed assertion"
SEL4TEST_RESULT = r"Test suite passed\. \d+ tests passed\. \d+ tests disabled\."


# --- Images ------------------------------------------------------------------

def read_image(path):
    """The image's bytes, after checking that bootm can boot it from LOAD."""
    try:
        with open(path, "rb") as f:
            data = f.read()
    except OSError as e:
        raise Failure(HOST, f"can't read the image: {e}") from None
    magic = struct.unpack(">I", data[:4])[0] if len(data) >= 4 else 0
    if magic == UIMAGE_MAGIC:
        size, load = struct.unpack(">II", data[12:20])
        if load <= LOAD < load + size:
            raise Failure(HOST, f"{path} loads at {load:#x} and is {size} bytes: it would overwrite "
                                f"itself at {LOAD:#x}")
    elif magic != FIT_MAGIC:
        raise Failure(HOST, f"{path} is not a U-Boot image (no uImage or FIT header). "
                            "bootm needs mkimage output.")
    return data


def default_expect(data):
    """Success pattern for images that announce one: sel4test's result line."""
    return SEL4TEST_RESULT if b"Test suite passed" in data else None


# --- The console -------------------------------------------------------------

class Console:
    """A broker connection to the U-Boot port, with everything received
    logged and (unless quiet) echoed."""

    def __init__(self, sock, log, out=None):
        self.sock, self.log = sock, log
        self.out = out if out is not None else sys.stdout.buffer
        self.buf = b""
        self.last_rx = time.time()
        self.quiet = False           # True during YMODEM: log, but don't echo ACK bytes

    def write(self, data):
        self.sock.sendall(data)

    def pump(self, secs):
        """Wait up to secs for output and take what arrives."""
        self.sock.settimeout(secs)
        try:
            data = self.sock.recv(4096)
        except socket.timeout:
            return
        except OSError:
            data = b""
        if not data:
            raise Failure(BOARD, "lost the console (board unplugged?)")
        self.buf += data
        self.last_rx = time.time()
        self.log.write(data)
        self.log.flush()
        if not self.quiet:
            self.out.write(data)
            self.out.flush()

    def wait_for(self, pattern, secs, fail_pattern=None):
        """Consume output until pattern matches (returns the match), until
        fail_pattern matches (returns None) or for at most secs (None)."""
        end = time.time() + secs
        while True:
            if fail_pattern:
                m = re.search(fail_pattern, self.buf, re.M)
                if m:
                    self.buf = self.buf[m.end():]
                    return None
            m = re.search(pattern, self.buf, re.M)
            if m:
                self.buf = self.buf[m.end():]
                return m
            if time.time() >= end:
                return None
            self.pump(min(0.2, max(0.01, end - time.time())))

    def wait_byte(self, choices, secs):
        """Next byte in choices, skipping others; keeps what follows it, since
        U-Boot sends ACK and 'C' back to back. (The ymodem link interface.)"""
        end = time.time() + secs
        while True:
            for i, byte in enumerate(self.buf):
                if byte in choices:
                    self.buf = self.buf[i + 1:]
                    return byte
            self.buf = b""
            if time.time() >= end:
                return None
            self.pump(0.05)

    def send(self, line):
        """Type a command line. U-Boot drops characters that arrive too fast."""
        self.buf = b""
        for ch in line.encode():
            self.sock.sendall(bytes([ch]))
            time.sleep(0.008)
        self.sock.sendall(b"\r")

    def command(self, line, secs=COMMAND):
        self.send(line)
        if not self.wait_for(PROMPT, secs):
            raise Failure(BOARD, f"no U-Boot prompt after '{line}'")

    def stop_autoboot(self, secs):
        if not self.wait_for(rb"Hit any key to stop autoboot", secs):
            return False
        for _ in range(10):
            self.write(b" ")
            if self.wait_for(PROMPT, 0.3):
                return True
        return bool(self.wait_for(PROMPT, 5))


def note(message):
    print(f"==> {message}", flush=True)


# --- 1. Get to the prompt ----------------------------------------------------

def reset_via_hss(hss_port):
    """Send RESET to the HSS console (through its broker, so an open HSS
    console sees it). HSS then boots U-Boot again."""
    hss = serial_share.ensure_broker(hss_port)
    try:
        hss.sendall(b"\r")
        time.sleep(0.3)
        hss.sendall(b"RESET\r")
        time.sleep(0.2)
    finally:
        hss.close()


def get_prompt(console, hss_port=None):
    """Bring U-Boot to its prompt: reset through HSS if hss_port is given,
    else use a prompt that is already there or wait for a manual reset."""
    if hss_port:
        reset_via_hss(hss_port)
        note("board reset via HSS; waiting for U-Boot")
        if not console.stop_autoboot(RESET_TO_AUTOBOOT):
            raise Failure(BOARD, f"U-Boot's autoboot prompt didn't appear within {RESET_TO_AUTOBOOT} s "
                                 "of the reset. Check the HSS console (scripts/board.py console --hss: "
                                 "Enter should give '>>'), or power-cycle the board and retry.")
        return
    console.send("")
    if console.wait_for(PROMPT, 2):
        note("already at the U-Boot prompt")
        return
    note(f"reset or power on the board now (waiting up to {MANUAL_RESET_WAIT // 60} min)")
    if not console.stop_autoboot(MANUAL_RESET_WAIT):
        raise Failure(BOARD, "U-Boot's autoboot prompt didn't appear")


# --- 2. Load into RAM --------------------------------------------------------

def _loady(console, ctl, name, data, baud):
    """One `loady` attempt; returns the size U-Boot reports, or None. Leaves
    U-Boot at its prompt at 115200 unless the board stops answering."""
    ctl.cmd("lowlat 1")              # FTDI latency timer 16 ms -> 1 ms: one ACK round trip per block
    if baud != 115200:
        console.send(f"loady {LOAD:#x} {baud}")
        if not console.wait_for(rb"press ENTER", COMMAND):
            return None
        time.sleep(0.2)              # U-Boot switches speed 50 ms after the message
        ctl.cmd(f"baud {baud}")
        console.write(b"\r")
    else:
        console.send(f"loady {LOAD:#x}")
    console.quiet = True             # from here U-Boot also sends 'C' bytes
    ok = bool(console.wait_for(rb"Ready for binary \(ymodem\) download[^\n]*\n", COMMAND))
    if ok:
        print()
        note(f"U-Boot is receiving at {baud} baud; sending {len(data)} bytes")
        start = time.time()
        ok = ymodem.send(console, name, data, progress=lambda done, total, secs: note(
            f"{done:>9} / {total} bytes, {done / 1024 / max(secs, 1e-3):.0f} KiB/s"))
        if ok:
            note(f"sent in {time.time() - start:.1f} s")
    if not ok:
        console.write(bytes([ymodem.CAN]) * 5)      # make U-Boot give up
    console.quiet = False
    m = console.wait_for(rb"Total Size\s*=\s*0x[0-9a-fA-F]+\s*=\s*(\d+) Bytes", COMMAND, rb"aborted")
    if baud != 115200:
        console.wait_for(rb"press ESC", COMMAND)
        time.sleep(0.2)
        ctl.cmd("baud 115200")
        console.write(b"\x1b")
    console.wait_for(PROMPT, COMMAND)
    return int(m.group(1)) if ok and m else None


def load_serial(console, port, name, data, baud, control=serial_share.control):
    """YMODEM the image to LOAD over the U-Boot serial port, with one retry.
    control(port) gives the broker's control socket (baud, latency timer);
    the broker restores both when it closes."""
    for attempt in (1, 2):
        try:
            ctl = control(port)
        except OSError as e:
            raise Failure(BOARD, f"can't take the serial port's control socket: {e}") from None
        try:
            got = _loady(console, ctl, name, data, baud)
        except OSError as e:          # the broker refused a setting
            raise Failure(BOARD, str(e)) from None
        finally:
            ctl.close()
        if got == len(data):
            return
        print()
        note(f"serial transfer attempt {attempt} failed"
             + (f" (U-Boot received {got} of {len(data)} bytes)" if got else ""))
    raise Failure(BOARD, "the serial (YMODEM) transfer failed. Try a lower --baud (921600, or 115200), "
                         "and check that nothing else types on the U-Boot console during the flash.")


def load_tftp(console, server_ip, name, size):
    """DHCP, then tftpboot the image to LOAD; retries the parts that are flaky."""
    console.command("setenv autoload no")
    for attempt in (1, 2, 3):
        console.send("dhcp")
        m = console.wait_for(rb"DHCP client bound to address (\S+)", DHCP)
        console.wait_for(PROMPT, 15)
        if m:
            break
        print()
        note(f"DHCP attempt {attempt} failed")
    else:
        raise Failure(BOARD, "no DHCP lease. Is Ethernet in connector #2, on a network with a DHCP server?")
    for attempt in (1, 2):
        console.send(f"tftpboot {LOAD:#x} {server_ip}:{name}")
        m = console.wait_for(rb"Bytes transferred = (\d+)", TFTP_TRANSFER,
                             rb"T T T T|TFTP error|Retry count exceeded")
        console.wait_for(PROMPT, 30)
        if m and int(m.group(1)) == size:
            return
        print()
        note(f"TFTP attempt {attempt} failed")
    raise Failure(BOARD, "the TFTP download failed. If you saw 'T T T', a firewall on this host is "
                         "dropping UDP 69 from the board (docs/flashing.md#network-boot).")


# --- 3. Verify, boot, watch --------------------------------------------------

def verify(console, crc):
    """Compare U-Boot's CRC-32 of the loaded bytes with crc; check the header."""
    console.send(f"crc32 {LOAD:#x} ${{filesize}}")    # loady sets filesize but not fileaddr
    m = console.wait_for(rb"==> ([0-9a-f]{8})", 20)
    console.wait_for(PROMPT, COMMAND)
    if not m or int(m.group(1), 16) != crc:
        raise Failure(BOARD, f"CRC mismatch: board {m.group(1).decode() if m else '?'}, file {crc:08x}")
    print()
    note(f"CRC32 {crc:08x} matches")
    console.send(f"iminfo {LOAD:#x}")
    m = console.wait_for(rb"Verifying Checksum \.\.\. OK", 20, rb"Bad (Data|Header) CRC|Unknown image format")
    console.wait_for(PROMPT, COMMAND)
    if not m:
        raise Failure(BOARD, "iminfo did not verify the image")


def boot(console):
    """bootm with the device tree U-Boot itself runs on."""
    console.send(f"bootm {LOAD:#x} - ${{fdtcontroladdr}}")
    if not console.wait_for(rb"Starting kernel \.\.\.", BOOTM_START,
                            rb"ERROR|Wrong Image|Bad Data CRC|Unsupported"):
        raise Failure(BOARD, "bootm did not start the image")


def watch(console, expect, fail, idle, timeout):
    """Watch the booted image; returns (exit code, message). Fails on
    fail or the built-in failure patterns; passes on expect, or, without
    expect, after idle seconds of silence."""
    fail_re = (FAIL_PATTERNS + ("|" + fail if fail else "")).encode()
    expect_re = expect.encode() if expect else None
    start = time.time()
    while True:
        m = re.search(fail_re, console.buf, re.M)
        if m:
            console.pump(1)
            return IMAGE_FAILED, f"FAILED: {m.group(0).decode(errors='replace')}"
        if expect_re:
            m = re.search(expect_re, console.buf, re.M)
            if m:
                console.pump(1)
                return OK, f"PASSED: {m.group(0).decode(errors='replace')}"
        elif time.time() - console.last_rx >= idle:
            return OK, f"booted; no console output for {idle} s, so treating the run as finished"
        if time.time() - start >= timeout:
            return TIMEOUT, f"timed out after {timeout} s" + (f" waiting for /{expect}/" if expect else "")
        console.pump(0.5)


def crc32(data):
    return zlib.crc32(data) & 0xFFFFFFFF


def log_path(directory, transport):
    os.makedirs(directory, exist_ok=True)
    return os.path.join(directory, time.strftime(f"flash-{transport}-%Y%m%d-%H%M%S.log"))
