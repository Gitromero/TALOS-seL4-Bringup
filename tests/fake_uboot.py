"""A simulated U-Boot console for offline tests of scripts/polarfire.

FakeUBoot runs in a thread on one end of a socket pair; the code under test
gets the other end, exactly as it would get a serial_share broker socket. It
answers the commands the flash tooling types, receives YMODEM like `loady`,
and prints a configurable boot log after `bootm`.
"""
import binascii
import socket
import threading
import time
import zlib

import paths  # noqa: F401  (puts scripts/ on sys.path)
from polarfire import ymodem

PROMPT = b"\r\nRISC-V # "


class FakeUBoot(threading.Thread):
    def __init__(self, image=b"", boot_log=b"", at_prompt=True, corrupt=False,
                 nak_blocks=(), cancel_attempts=0, dhcp_failures=0):
        super().__init__(daemon=True)
        self.ours, self.theirs = socket.socketpair()
        self.image = image                    # what tftpboot "downloads"
        self.boot_log = boot_log              # printed after "Starting kernel ..."
        self.at_prompt = at_prompt            # else silent until autoboot() is called
        self.corrupt = corrupt                # flip a byte of whatever is loaded
        self.nak_blocks = set(nak_blocks)     # data blocks to NAK once each
        self.cancel_attempts = cancel_attempts  # loady attempts to abort with CAN
        self.dhcp_failures = dhcp_failures
        self.loaded = b""
        self.commands = []
        self.rx = b""
        self.done = False
        self.reset_requested = threading.Event()
        self.start()

    # --- plumbing ---
    def out(self, data):
        try:
            self.ours.sendall(data)
        except OSError:
            pass

    def read(self, secs=5):
        """Wait for more bytes and add them to rx."""
        self.ours.settimeout(secs)
        try:
            data = self.ours.recv(4096)
        except socket.timeout:
            raise TimeoutError("fake U-Boot: nothing received") from None
        if not data:
            raise EOFError
        self.rx += data

    def take(self, n, secs=5):
        while len(self.rx) < n:
            self.read(secs)
        data, self.rx = self.rx[:n], self.rx[n:]
        return data

    def line(self):
        """Next typed line, echoed like a terminal."""
        while b"\r" not in self.rx:
            self.read(60)
        line, self.rx = self.rx.split(b"\r", 1)
        line = line.lstrip(bytes([ymodem.CAN]))       # leftovers of an aborted transfer
        self.out(line)
        return line.decode()

    def autoboot(self):
        """Boot output after a reset, up to the countdown; waits for a key."""
        self.out(b"\r\nU-Boot 2025.07\r\nHit any key to stop autoboot:  3 ")
        while not self.rx:
            self.read(10)
        self.rx = b""
        self.out(PROMPT)

    # --- the console ---
    def run(self):
        try:
            if not self.at_prompt:
                return self._wait_for_reset()
            self._commands()
        except (EOFError, OSError, TimeoutError):
            pass
        finally:
            self.done = True

    def _wait_for_reset(self):
        self.reset_requested.wait(10)
        self.autoboot()
        self._commands()

    def _commands(self):
        while True:
            line = self.line()
            self.commands.append(line)
            words = line.split()
            if not words:
                self.out(PROMPT)
            elif words[0] == "setenv":
                self.out(PROMPT)
            elif words[0] == "dhcp":
                if self.dhcp_failures:
                    self.dhcp_failures -= 1
                    self.out(b"\r\nDHCP timeout" + PROMPT)
                else:
                    self.out(b"\r\nDHCP client bound to address 192.168.1.20 (5 ms)" + PROMPT)
            elif words[0] == "tftpboot":
                self.loaded = self._maybe_corrupt(self.image)
                self.out(f"\r\nBytes transferred = {len(self.loaded)} ({len(self.loaded):x} hex)".encode() + PROMPT)
            elif words[0] == "loady":
                self._loady(int(words[2]) if len(words) > 2 else 115200)
            elif words[0] == "crc32":
                crc = zlib.crc32(self.loaded) & 0xFFFFFFFF
                self.out(f"\r\ncrc32 for 8e000000 ... {crc:08x} ==> {crc:08x}".encode() + PROMPT)
            elif words[0] == "iminfo":
                self.out(b"\r\n   Verifying Checksum ... OK" + PROMPT)
            elif words[0] == "bootm":
                self.out(b"\r\n   Loading Kernel Image\r\nStarting kernel ...\r\n\r\n")
                self.out(self.boot_log)
                return
            else:
                self.out(f"\r\nUnknown command '{words[0]}'".encode() + PROMPT)

    def _maybe_corrupt(self, data):
        if self.corrupt and data:
            return bytes([data[0] ^ 0xFF]) + data[1:]
        return data

    def _loady(self, baud):
        if baud != 115200:
            self.out(f"\r\n## Switch baudrate to {baud} bps and press ENTER ...\r\n".encode())
            while b"\r" not in self.rx:
                self.read()
            self.rx = self.rx.split(b"\r", 1)[1]
        self.out(f"## Ready for binary (ymodem) download to 0x8E000000 at {baud} bps...\r\n".encode())
        size = self._receive()
        if size is None:
            self.out(b"\r\n## Binary (ymodem) download aborted\r\n")
        self.loaded = self._maybe_corrupt(self.loaded)
        self._end_loady(baud, size)

    def _end_loady(self, baud, size):
        if size is not None:
            self.out(f"## Total Size      = 0x{size:08x} = {size} Bytes\r\n".encode())
        if baud != 115200:
            self.out(f"## Switch baudrate to 115200 bps and press ESC ...\r\n".encode())
            while b"\x1b" not in self.rx:
                self.read()
            self.rx = self.rx.split(b"\x1b", 1)[1]
        self.out(PROMPT)

    def _block(self):
        """One received block: (seq, payload), or 'EOT'/'CAN'."""
        kind = self.take(1)[0]
        if kind == ymodem.EOT:
            return "EOT"
        if kind == ymodem.CAN:
            return "CAN"
        size = 128 if kind == ymodem.SOH else 1024
        seq, inverse = self.take(2)
        payload = self.take(size)
        crc = int.from_bytes(self.take(2), "big")
        assert seq + inverse == 0xFF, "bad block number"
        assert binascii.crc_hqx(payload, 0) == crc, "bad CRC"
        return seq, payload

    def _receive(self):
        self.out(b"C")
        seq, header = self._block()
        assert seq == 0
        size = int(header.split(b"\0")[1])
        self.out(bytes([ymodem.ACK, ord("C")]))
        data, expected = b"", 1
        while True:
            block = self._block()
            if block == "CAN":
                return None
            if self.cancel_attempts:                 # give up on this attempt
                self.cancel_attempts -= 1
                self.out(bytes([ymodem.CAN]) * 2)
                return None
            if block == "EOT":
                self.out(bytes([ymodem.ACK, ord("C")]))
                break
            seq, payload = block
            if expected in self.nak_blocks:
                self.nak_blocks.discard(expected)
                self.out(bytes([ymodem.NAK]))
                continue
            assert seq == expected & 0xFF
            data += payload
            expected += 1
            self.out(bytes([ymodem.ACK]))
        seq, end = self._block()                   # empty header: no more files
        assert seq == 0 and end.strip(b"\0") == b""
        self.out(bytes([ymodem.ACK]))
        self.loaded = data[:size]
        return size


class FakeControl:
    """Stands in for serial_share.control(port)."""

    def __init__(self, log):
        self.log = log

    def cmd(self, line, timeout=5):
        self.log.append(line)

    def close(self):
        self.log.append("closed")


def uimage(payload=b"payload", load=0x80640000):
    """A minimal legacy uImage header + payload (header CRCs not filled in)."""
    import struct
    return struct.pack(">7I4B32s", 0x27051956, 0, 0, len(payload), load, load,
                       zlib.crc32(payload) & 0xFFFFFFFF, 5, 26, 2, 0, b"") + payload
