"""Offline tests of the host-side helpers: port lookup and ownership checks,
the serial-share broker (on a pseudo-terminal standing in for the board), and
the TFTP staging and probe. Linux only, like the tools."""
import os
import socket
import subprocess
import sys
import tempfile
import threading
import time
import unittest
import warnings

import paths  # noqa: F401
from polarfire import HOST, Failure, ports, serial_share, tftp

# ensure_broker() starts the broker detached and never waits for it, by design.
warnings.filterwarnings("ignore", r"subprocess \d+ is still running", ResourceWarning)


class Ports(unittest.TestCase):
    def setUp(self):
        self.saved = {k: os.environ.pop(k, None) for k in ("UBOOT_PORT", "HSS_PORT")}
        self.addCleanup(self.restore)

    def restore(self):
        for k, v in self.saved.items():
            os.environ.pop(k, None)
            if v is not None:
                os.environ[k] = v

    def test_environment_override_wins(self):
        os.environ["UBOOT_PORT"] = "/dev/null"
        self.assertEqual(ports.find("uboot"), "/dev/null")
        self.assertEqual(ports.require("uboot"), "/dev/null")

    def test_missing_port_is_a_host_failure(self):
        os.environ["HSS_PORT"] = "/nonexistent/hss"
        with self.assertRaises(Failure) as e:
            ports.require("hss", " (needed for the reset; or use --no-reset)")
        self.assertEqual(e.exception.code, HOST)
        self.assertIn("--no-reset", str(e.exception))

    def test_holders_and_require_free(self):
        with tempfile.NamedTemporaryFile() as f:
            self.assertEqual(ports.holders(f.name), [])
            ports.require_free(f.name)
            holder = subprocess.Popen(["sh", "-c", f"exec 3<'{f.name}'; exec sleep 30"])
            self.addCleanup(holder.kill)
            for _ in range(50):
                if ports.holders(f.name):
                    break
                time.sleep(0.05)
            self.assertEqual(ports.holders(f.name), [f"{holder.pid}(sleep)"])
            with self.assertRaises(Failure) as e:
                ports.require_free(f.name)
            self.assertIn("doesn't share it", str(e.exception))


@unittest.skipUnless(sys.platform.startswith("linux"), "the broker is Linux only")
class SerialShare(unittest.TestCase):
    """A broker on a pty: the test holds the 'board' (master) end."""

    def setUp(self):
        self.runtime = tempfile.TemporaryDirectory()
        self.addCleanup(self.runtime.cleanup)
        old = os.environ.get("XDG_RUNTIME_DIR")
        os.environ["XDG_RUNTIME_DIR"] = self.runtime.name
        self.addCleanup(lambda: os.environ.__setitem__("XDG_RUNTIME_DIR", old) if old
                        else os.environ.pop("XDG_RUNTIME_DIR", None))
        self.board, slave = os.openpty()
        self.port = os.ttyname(slave)
        os.close(slave)
        self.addCleanup(os.close, self.board)

    def client(self):
        c = serial_share.ensure_broker(self.port)
        c.settimeout(5)
        self.addCleanup(c.close)
        return c

    def board_reads(self, n):
        out = b""
        end = time.time() + 5
        while len(out) < n and time.time() < end:
            out += os.read(self.board, 4096)
        return out

    def test_output_reaches_every_client(self):
        a, b = self.client(), self.client()
        self.assertIsNotNone(serial_share.broker_pid(self.port))
        time.sleep(0.2)
        os.write(self.board, b"Hit any key")
        self.assertEqual(a.recv(100), b"Hit any key")
        self.assertEqual(b.recv(100), b"Hit any key")

    def test_client_input_reaches_the_port_in_order(self):
        a, b = self.client(), self.client()
        a.sendall(b"one ")
        time.sleep(0.1)
        b.sendall(b"two")
        self.assertEqual(self.board_reads(7), b"one two")

    def test_control_socket_is_exclusive_and_reports_errors(self):
        self.client()
        ctl = serial_share.control(self.port)
        self.addCleanup(ctl.close)
        ctl.cmd("baud 115200")
        with self.assertRaises(OSError):
            ctl.cmd("baud 12345")                 # not a termios speed
        with self.assertRaises(OSError):
            ctl.cmd("lowlat 1")                   # a pty has no FTDI latency timer
        second = serial_share.control(self.port)
        self.addCleanup(second.close)
        with self.assertRaises(OSError) as e:
            second.cmd("baud 115200")
        self.assertIn("busy", str(e.exception))

    def test_broker_exits_and_cleans_up_after_last_client(self):
        c = serial_share.ensure_broker(self.port)
        socket_file = serial_share.sock_path(self.port)
        self.assertTrue(os.path.exists(socket_file))
        c.close()
        for _ in range(80):
            if not os.path.exists(socket_file):
                break
            time.sleep(0.1)
        self.assertFalse(os.path.exists(socket_file))
        self.assertIsNone(serial_share.broker_pid(self.port))

    def test_stale_socket_is_replaced(self):
        stale = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        stale.bind(serial_share.sock_path(self.port))
        stale.close()                             # file left behind, nobody listening
        c = self.client()
        time.sleep(0.2)                           # output before the broker accepts us goes nowhere
        os.write(self.board, b"ok")
        self.assertEqual(c.recv(10), b"ok")

    def test_send_without_a_broker_writes_directly(self):
        serial_share.send(self.port, "version\\r")
        self.assertEqual(self.board_reads(8), b"version\r")


class Tftp(unittest.TestCase):
    def test_stage_uses_a_safe_name_and_leaves_no_temp_file(self):
        with tempfile.TemporaryDirectory() as d:
            image = os.path.join(d, "my image (1).uImage")
            with open(image, "wb") as f:
                f.write(b"data")
            root = os.path.join(d, "root")
            name = tftp.stage(image, root)
            self.assertEqual(name, "my_image__1_.uImage")
            self.assertEqual(os.listdir(root), [name])
            self.assertEqual(os.stat(os.path.join(root, name)).st_mode & 0o777, 0o644)
            self.assertEqual(tftp.stage(os.path.join(root, name), root), name)   # already staged

    def serve_once(self, reply):
        server = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        server.bind(("127.0.0.1", 0))
        self.addCleanup(server.close)

        def answer():
            request, peer = server.recvfrom(1024)
            self.request = request
            server.sendto(reply, peer)
        threading.Thread(target=answer, daemon=True).start()
        return server.getsockname()[1]

    def test_probe_accepts_data(self):
        port = self.serve_once(b"\x00\x03\x00\x01" + b"x" * 512)
        tftp.probe("127.0.0.1", "image.uImage", port)
        self.assertEqual(self.request, b"\x00\x01image.uImage\x00octet\x00")

    def test_probe_reports_server_error(self):
        port = self.serve_once(b"\x00\x05\x00\x01File not found\x00")
        with self.assertRaises(Failure) as e:
            tftp.probe("127.0.0.1", "missing", port)
        self.assertIn("File not found", str(e.exception))


if __name__ == "__main__":
    unittest.main()
