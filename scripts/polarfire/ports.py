"""Find the Discovery Kit's serial ports and check that nothing else holds them.

The board's USB-C #1 is an FT4232H (USB ID 1514:2008) with four channels.
ttyUSB numbers depend on bind order, so never use them; look ports up by role:

  role    interface  udev name (host/udev rule)  by-id fallback
  jtag    00         /dev/polarfire-jtag         /dev/serial/by-id/*FlashPro5*-if00-port0
  hss     01         /dev/polarfire-hss          ...-if01-port0
  uboot   02         /dev/polarfire-uboot        ...-if02-port0  (U-Boot, Linux, seL4)
  uart3   03         /dev/polarfire-uart3        ...-if03-port0

UBOOT_PORT, HSS_PORT, UART3_PORT and JTAG_PORT override the lookup.
"""
import glob
import os

from . import HOST, Failure, serial_share

ROLES = {"jtag": "00", "hss": "01", "uboot": "02", "uart3": "03"}
USB_VENDOR = "1514"
BIND_HINT = ("all four FT4232H channels must be bound to ftdi_sio: scripts/board.py install-udev, "
             "or see docs/getting-started.md#serial-ports")


def find(role):
    """Device path for role, or None."""
    override = os.environ.get(f"{role.upper()}_PORT")
    if override:
        return override
    if os.path.exists(f"/dev/polarfire-{role}"):
        return f"/dev/polarfire-{role}"
    matches = sorted(glob.glob(f"/dev/serial/by-id/*FlashPro5*-if{ROLES[role]}-port0"))
    return matches[0] if matches else None


def require(role, purpose=""):
    """Device path for role, usable by this user; raises Failure otherwise."""
    port = find(role)
    if not port or not os.path.exists(port):
        raise Failure(HOST, f"{role} serial port {port or ''} not found{purpose}. Is USB-C #1 connected "
                            f"and the board powered? ({BIND_HINT}; or set {role.upper()}_PORT)")
    if not os.access(port, os.R_OK | os.W_OK):
        raise Failure(HOST, f"no read/write access to {port} (add yourself to the 'dialout' group, "
                            "then log in again)")
    return port


def holders(port):
    """'pid(command)' for every other process with port open, the
    serial-share broker excepted (it shares the port; nothing else does)."""
    real = os.path.realpath(port)
    skip = {os.getpid(), serial_share.broker_pid(port)}
    pids = set()
    for fd in glob.glob("/proc/[0-9]*/fd/*"):
        try:
            if os.readlink(fd) == real:
                pids.add(int(fd.split("/")[2]))
        except (OSError, ValueError):
            pass             # process exited, or not ours to inspect
    found = []
    for pid in sorted(pids - skip):
        try:
            with open(f"/proc/{pid}/comm") as f:
                found.append(f"{pid}({f.read().strip()})")
        except OSError:
            found.append(str(pid))
    return found


def require_free(port):
    """Raise Failure if a program that doesn't share the port has it open: it
    would take bytes (prompts, YMODEM ACKs) that a flash is waiting for."""
    busy = holders(port)
    if busy:
        raise Failure(HOST, f"{port} is open in a program that doesn't share it: {' '.join(busy)}. "
                            "Close it (picocom: Ctrl-a Ctrl-x). To watch a flash, use "
                            "scripts/board.py console, which shares the port.")


def usb_device():
    """sysfs directory of the board's USB device, or None."""
    for vendor in glob.glob("/sys/bus/usb/devices/*/idVendor"):
        try:
            with open(vendor) as f:
                if f.read().strip() == USB_VENDOR:
                    return os.path.dirname(vendor)
        except OSError:
            pass
    return None


def interfaces(device):
    """[(interface number, driver or None, ttyUSBn or None)] for a USB device."""
    result = []
    for path in sorted(glob.glob(f"{device}:1.*")):
        try:
            with open(f"{path}/bInterfaceNumber") as f:
                number = f.read().strip()
        except OSError:
            continue
        driver = os.path.basename(os.readlink(f"{path}/driver")) if os.path.islink(f"{path}/driver") else None
        ttys = sorted(glob.glob(f"{path}/ttyUSB*"))
        result.append((number, driver, os.path.basename(ttys[0]) if ttys else None))
    return result
