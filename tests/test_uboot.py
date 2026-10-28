"""Offline tests of the flash sequence (scripts/polarfire/uboot.py, ymodem.py)
against a simulated U-Boot. No board, serial port or network needed."""
import io
import socket
import os
import tempfile
import unittest
import zlib

from fake_uboot import FakeControl, FakeUBoot, uimage

from polarfire import BOARD, HOST, IMAGE_FAILED, OK, TIMEOUT, Failure, uboot, ymodem

DATA = bytes(range(256)) * 13 + b"tail"     # 3332 bytes: 4 blocks, the last one partial


def console_for(fake):
    return uboot.Console(fake.theirs, io.BytesIO(), out=io.BytesIO())


class SimulatedBoard(unittest.TestCase):
    def fake(self, **options):
        fake = FakeUBoot(**options)
        self.addCleanup(fake.theirs.close)
        self.addCleanup(fake.ours.close)
        return fake

    def shorten(self, name, secs):
        self.addCleanup(setattr, uboot, name, getattr(uboot, name))
        setattr(uboot, name, secs)


class Images(unittest.TestCase):
    def write(self, data):
        f = tempfile.NamedTemporaryFile(delete=False)
        f.write(data)
        f.close()
        self.addCleanup(os.unlink, f.name)
        return f.name

    def test_uimage_and_fit_accepted(self):
        self.assertEqual(uboot.read_image(self.write(uimage())), uimage())
        fit = b"\xd0\x0d\xfe\xed" + b"\0" * 60
        self.assertEqual(uboot.read_image(self.write(fit)), fit)

    def test_rejects_non_uboot_images(self):
        for data in (b"", b"\x7fELF" + b"\0" * 60, b"plain text"):
            with self.assertRaises(Failure) as e:
                uboot.read_image(self.write(data))
            self.assertEqual(e.exception.code, HOST)
            self.assertIn("not a U-Boot image", str(e.exception))

    def test_rejects_image_that_would_overwrite_itself(self):
        with self.assertRaises(Failure) as e:
            uboot.read_image(self.write(uimage(b"x" * 64, load=uboot.LOAD - 16)))
        self.assertIn("overwrite itself", str(e.exception))

    def test_missing_file(self):
        with self.assertRaises(Failure) as e:
            uboot.read_image("/nonexistent/image.uImage")
        self.assertEqual(e.exception.code, HOST)

    def test_default_expect_only_for_sel4test(self):
        self.assertEqual(uboot.default_expect(b"..Test suite passed.."), uboot.SEL4TEST_RESULT)
        self.assertIsNone(uboot.default_expect(uimage()))


class Prompt(SimulatedBoard):
    def test_already_at_prompt(self):
        fake = self.fake()
        uboot.get_prompt(console_for(fake))
        self.assertEqual(fake.commands, [""])

    def test_reset_then_stop_autoboot(self):
        fake = self.fake(at_prompt=False)
        original = uboot.reset_via_hss
        uboot.reset_via_hss = lambda port: fake.reset_requested.set()
        self.addCleanup(setattr, uboot, "reset_via_hss", original)
        console = console_for(fake)
        uboot.get_prompt(console, hss_port="/dev/fake-hss")
        console.command("version")
        self.assertEqual(fake.commands, ["version"])

    def test_no_prompt_is_a_board_failure(self):
        fake = self.fake(at_prompt=False)
        self.shorten("RESET_TO_AUTOBOOT", 0.5)
        uboot.reset_via_hss, saved = (lambda port: None), uboot.reset_via_hss
        self.addCleanup(setattr, uboot, "reset_via_hss", saved)
        with self.assertRaises(Failure) as e:
            uboot.get_prompt(console_for(fake), hss_port="/dev/fake-hss")
        self.assertEqual(e.exception.code, BOARD)

    def test_lost_console(self):
        fake = self.fake()
        fake.ours.shutdown(socket.SHUT_RDWR)
        with self.assertRaises(Failure) as e:
            console_for(fake).wait_for(uboot.PROMPT, 2)
        self.assertEqual(e.exception.code, BOARD)


class SerialLoad(SimulatedBoard):
    def load(self, fake, baud):
        controls = []
        console = console_for(fake)
        uboot.get_prompt(console)
        uboot.load_serial(console, "/dev/fake", "image", DATA, baud,
                          control=lambda port: FakeControl(controls))
        return console, controls

    def test_115200(self):
        fake = self.fake()
        console, controls = self.load(fake, 115200)
        self.assertEqual(fake.loaded, DATA)
        self.assertEqual(controls, ["lowlat 1", "closed"])
        uboot.verify(console, uboot.crc32(DATA))

    def test_fast_baud_switches_and_restores(self):
        fake = self.fake()
        console, controls = self.load(fake, 1500000)
        self.assertEqual(fake.loaded, DATA)
        self.assertEqual(controls, ["lowlat 1", "baud 1500000", "baud 115200", "closed"])
        self.assertFalse(console.quiet)

    def test_nak_resends_the_block(self):
        fake = self.fake(nak_blocks={2})
        self.load(fake, 115200)
        self.assertEqual(fake.loaded, DATA)

    def test_aborted_transfer_is_retried_once(self):
        fake = self.fake(cancel_attempts=1)
        _, controls = self.load(fake, 115200)
        self.assertEqual(fake.loaded, DATA)
        self.assertEqual(controls.count("lowlat 1"), 2)

    def test_two_aborted_transfers_fail(self):
        fake = self.fake(cancel_attempts=2)
        with self.assertRaises(Failure) as e:
            self.load(fake, 115200)
        self.assertEqual(e.exception.code, BOARD)

    def test_crc_mismatch(self):
        fake = self.fake(corrupt=True)
        console, _ = self.load(fake, 115200)
        with self.assertRaises(Failure) as e:
            uboot.verify(console, uboot.crc32(DATA))
        self.assertIn("CRC mismatch", str(e.exception))


class NetworkLoad(SimulatedBoard):
    def test_dhcp_retry_then_tftp(self):
        self.shorten("DHCP", 1)            # a failed attempt waits out the whole DHCP timeout
        fake = self.fake(image=DATA, dhcp_failures=1)
        console = console_for(fake)
        uboot.get_prompt(console)
        uboot.load_tftp(console, "192.168.1.10", "image", len(DATA))
        self.assertEqual(fake.commands[1:], ["setenv autoload no", "dhcp", "dhcp",
                                             f"tftpboot {uboot.LOAD:#x} 192.168.1.10:image"])
        uboot.verify(console, uboot.crc32(DATA))

    def test_size_mismatch_fails(self):
        fake = self.fake(image=DATA)
        console = console_for(fake)
        uboot.get_prompt(console)
        with self.assertRaises(Failure):
            uboot.load_tftp(console, "192.168.1.10", "image", len(DATA) + 1)


class BootAndWatch(SimulatedBoard):
    def run_boot(self, log, expect=None, fail=None, idle=20, timeout=5):
        fake = self.fake(image=DATA, boot_log=log)
        console = console_for(fake)
        uboot.get_prompt(console)
        uboot.load_tftp(console, "192.168.1.10", "image", len(DATA))
        uboot.verify(console, zlib.crc32(DATA) & 0xFFFFFFFF)
        uboot.boot(console)
        return uboot.watch(console, expect, fail, idle, timeout)

    def test_pass(self):
        code, message = self.run_boot(b"Test suite passed. 3 tests passed. 0 tests disabled.\r\n",
                                      expect=uboot.SEL4TEST_RESULT)
        self.assertEqual(code, OK)
        self.assertIn("PASSED", message)

    def test_builtin_failure_pattern(self):
        code, message = self.run_boot(b"seL4 failed assertion 'x' at y\r\n", expect="never")
        self.assertEqual(code, IMAGE_FAILED)

    def test_extra_failure_pattern(self):
        code, _ = self.run_boot(b"TALOS_IO FAIL\r\n", expect="never", fail=r"TALOS_\w+ FAIL")
        self.assertEqual(code, IMAGE_FAILED)

    def test_timeout(self):
        code, message = self.run_boot(b"still running\r\n", expect="never", timeout=1)
        self.assertEqual(code, TIMEOUT)

    def test_idle_without_pattern(self):
        code, message = self.run_boot(b"hello\r\n", idle=1)
        self.assertEqual(code, OK)
        self.assertIn("no console output", message)


class YModemFraming(unittest.TestCase):
    def test_block_layout_and_crc(self):
        packet = ymodem.block(1, b"abc", 1024)
        self.assertEqual(packet[:3], bytes([ymodem.STX, 1, 0xFE]))
        self.assertEqual(len(packet), 3 + 1024 + 2)
        self.assertEqual(packet[6:8], b"\x1a\x1a")               # data blocks pad with SUB
        self.assertEqual(ymodem.block(0, b"", 128)[3:131], b"\0" * 128)

    def test_crc16_xmodem_check_value(self):
        # CRC-16/XMODEM of "123456789" is 0x31C3 by definition.
        packet = ymodem.block(1, b"123456789", 9)
        self.assertEqual(packet[-2:], b"\x31\xc3")


if __name__ == "__main__":
    unittest.main()
