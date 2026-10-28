"""Command-line contracts of every tool: --help works and exits 0, usage
errors exit 2, and flash refuses bad input before it touches the board."""
import os
import subprocess
import sys
import tempfile
import unittest

from fake_uboot import uimage
from paths import REPO

BOARD = [sys.executable, "-B", str(REPO / "scripts" / "board.py")]
SHELL_TOOLS = ["scripts/build-sel4test.sh", "scripts/install-to-boot.sh",
               "scripts/make-source-archive.sh", "tests/test-installer.sh", "tftp/serve.sh",
               "experiments/rust-root-task/build.sh"]
COMMANDS = ["status", "ports", "flash", "console", "send", "reset", "tftp", "install-udev"]


def run(cmd, env=None):
    return subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                          cwd=REPO, env=env, timeout=30)


class BoardCommandLine(unittest.TestCase):
    def test_help_lists_every_command(self):
        r = run(BOARD + ["--help"])
        self.assertEqual(r.returncode, 0)
        for command in COMMANDS:
            self.assertIn(command, r.stdout)

    def test_every_command_has_help(self):
        for command in COMMANDS:
            with self.subTest(command=command):
                self.assertEqual(run(BOARD + [command, "--help"]).returncode, 0)

    def test_usage_errors_exit_2(self):
        for args in ([], ["frobnicate"], ["flash", "--baud", "3000000"], ["tftp", "restart"],
                     ["console", "--hss", "--uart3"]):
            with self.subTest(args=args):
                self.assertEqual(run(BOARD + args).returncode, 2)


class FlashRefusesEarly(unittest.TestCase):
    """Each of these must fail on the host, before any port is opened."""

    def flash(self, *args, **env):
        environ = dict(os.environ, UBOOT_PORT="/nonexistent/uboot", HSS_PORT="/nonexistent/hss", **env)
        return run(BOARD + ["flash", *args], env=environ)

    def test_missing_image(self):
        r = self.flash("/nonexistent/image.uImage")
        self.assertEqual(r.returncode, 2)
        self.assertIn("can't read the image", r.stderr)

    def test_not_a_uboot_image(self):
        r = self.flash(str(REPO / "README.md"))
        self.assertEqual(r.returncode, 2)
        self.assertIn("not a U-Boot image", r.stderr)

    def test_missing_serial_port(self):
        with tempfile.NamedTemporaryFile(suffix=".uImage") as f:
            f.write(uimage())
            f.flush()
            r = self.flash(f.name)
        self.assertEqual(r.returncode, 2)
        self.assertIn("uboot serial port /nonexistent/uboot not found", r.stderr)


class OtherTools(unittest.TestCase):
    def test_shell_tools_print_help(self):
        for tool in SHELL_TOOLS:
            with self.subTest(tool=tool):
                r = run([str(REPO / tool), "--help"])
                self.assertEqual(r.returncode, 0, r.stderr)
                self.assertGreater(len(r.stdout.splitlines()), 3)

    def test_privacy_audit_help_and_usage(self):
        tool = [sys.executable, "-I", str(REPO / "scripts" / "privacy_audit.py")]
        self.assertEqual(run(tool + ["--help"]).returncode, 0)
        self.assertEqual(run(tool).returncode, 2)

    def test_tftp_server_rejects_unknown_action(self):
        self.assertEqual(run([str(REPO / "tftp" / "serve.sh"), "restart"]).returncode, 2)


if __name__ == "__main__":
    unittest.main()
