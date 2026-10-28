"""Host-side helpers for the PolarFire SoC Discovery Kit, used by scripts/board.py.

  ports         find the board's four serial channels; check who holds a port
  serial_share  broker that lets several programs share one serial port
  uboot         drive the U-Boot console: get a prompt, load, verify, boot, watch
  ymodem        YMODEM sender (what U-Boot's `loady` receives)
  tftp          host side of network boot: stage the image, run and probe the server

Linux only (sysfs, /proc, termios, Unix sockets). Standard library only.
"""

# Exit codes shared by every board.py command.
OK = 0
IMAGE_FAILED = 1     # the image booted and reported failure
HOST = 2             # usage error, or a problem on this computer
BOARD = 3            # no prompt, transfer failed, checksum mismatch, ...
TIMEOUT = 4          # booted, but no result before --timeout
INTERRUPTED = 130


class Failure(Exception):
    """Stops a command with an exit code and a message for the user."""

    def __init__(self, code, message):
        super().__init__(message)
        self.code = code
