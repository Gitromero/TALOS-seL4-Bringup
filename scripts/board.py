#!/usr/bin/env python3
"""Work with a PolarFire SoC Discovery Kit attached to this Linux host.

The board needs only USB-C #1 (its four serial channels). Ethernet in
connector #2 is optional and only used by `flash --lan`. Everything works
over SSH: nobody has to be at the board except to power-cycle it or swap the
SD card.

commands:
  status                 read-only health report: USB, channels, ports, HSS, TFTP, last flash
  ports                  the board's serial ports and who has them open
  flash [IMAGE]          load IMAGE into RAM and boot it, hands-off: reset via HSS, stop
                         autoboot, transfer, CRC check, bootm, watch for pass/fail.
                         Over USB (YMODEM) by default, --lan for Ethernet (TFTP).
                         IMAGE defaults to images/sel4test.uImage.
  console [--hss|--uart3]  shared console: U-Boot/Linux/seL4, HSS or UART3 (exit: Ctrl-a Ctrl-x)
  send TEXT [--hss]      type TEXT on a console (\\r for Enter), for scripts and agents
  reset [-y]             reboot the board through the HSS console's RESET command
  tftp [ACTION]          the TFTP server flash --lan uses: start, stop, status, logs
  install-udev           install host/udev/99-polarfire-discovery.rules (sudo)

Consoles are shared: keep `board.py console` open in one terminal and run
`board.py flash` in another to watch the whole run. A plain picocom or screen
on the same port can't share, so flash refuses to start while one is open.

RAM only: flash never writes the SD card, eMMC, QSPI, FPGA, HSS or U-Boot's
saved environment. A power cycle boots whatever is installed on the card.

exit codes: 0 passed or booted, 1 the image reported failure, 2 usage or host
problem, 3 board or U-Boot problem, 4 timed out, 130 interrupted.

Port overrides: UBOOT_PORT, HSS_PORT, UART3_PORT. See docs/flashing.md.
"""
import argparse
import glob
import os
import select
import subprocess
import sys
import termios
import time

sys.dont_write_bytecode = True       # keep __pycache__ out of the repository

from polarfire import (HOST, INTERRUPTED, OK, Failure,  # noqa: E402
                       ports, serial_share, tftp, uboot)

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_IMAGE = os.path.join(REPO, "images", "sel4test.uImage")
LOGS = os.path.join(REPO, "logs")
TFTP_ROOT = os.path.join(REPO, "tftp", "root")
SERVE = os.path.join(REPO, "tftp", "serve.sh")
UDEV_RULE = os.path.join(REPO, "host", "udev", "99-polarfire-discovery.rules")

if sys.stdout.isatty():
    GREEN, YELLOW, CYAN, RESET = "\033[32m", "\033[33m", "\033[1;36m", "\033[0m"
else:
    GREEN = YELLOW = CYAN = RESET = ""


def header(text):
    print(f"{CYAN}== {text} =={RESET}")


def ok(text):
    print(f"{GREEN}[ok]{RESET} {text}")


def warn(text):
    print(f"{YELLOW}[!!]{RESET} {text}")


# --- status, ports -----------------------------------------------------------

def hss_answers(port):
    """True if HSS answers Enter with its '>>' prompt. Opens the port directly,
    so only call it when nothing else (broker included) has the port."""
    fd = serial_share.open_serial(port)
    try:
        termios.tcflush(fd, termios.TCIFLUSH)
        os.write(fd, b"\r")
        out, end = b"", time.time() + 2
        while time.time() < end:
            if select.select([fd], [], [], 0.2)[0]:
                out += os.read(fd, 4096)
    finally:
        os.close(fd)
    return b">>" in out


def cmd_status(_):
    header("USB")
    device = ports.usb_device()
    if not device:
        warn("Discovery Kit not on USB (cable in USB-C #1? board powered?)")
    else:
        names = []
        for attr in ("manufacturer", "product"):
            try:
                with open(f"{device}/{attr}") as f:
                    names.append(f.read().strip())
            except OSError:
                pass
        ok(f"{' '.join(names)} at USB {os.path.basename(device)}")
        found = ports.interfaces(device)
        for number, driver, tty in found:
            print(f"  interface {number}  {driver or 'unbound':9} {tty or ''}")
        bound = sum(driver == "ftdi_sio" for _, driver, _ in found)
        if bound == 4:
            ok("all 4 channels bound")
        else:
            warn(f"{bound}/4 channels bound: scripts/board.py install-udev "
                 "(or docs/getting-started.md#serial-ports)")

    header("Serial ports")
    if os.path.exists("/etc/udev/rules.d/99-polarfire-discovery.rules"):
        ok("udev rule installed")
    else:
        warn("udev rule not installed (optional): scripts/board.py install-udev")
    list_ports()

    header("HSS")
    port = ports.find("hss")
    if not port:
        warn("port missing")
    elif serial_share.broker_pid(port):
        ok("a shared HSS console is open; skipped the probe")
    elif ports.holders(port):
        warn("skipped: the port is held by another program")
    elif hss_answers(port):
        ok("HSS answers Enter with '>>': remote reset works")
    else:
        warn("HSS did not answer Enter (board off, or HSS busy)")

    header("Network boot (flash --lan)")
    state = subprocess.run([SERVE, "status"], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                           text=True).stdout.strip()
    if state and not state.startswith("stopped"):
        ok(f"TFTP server: {state}")
    else:
        print("  TFTP server: stopped (flash --lan starts it)")
    staged = sorted(f for f in os.listdir(TFTP_ROOT) if not f.startswith(".")) if os.path.isdir(TFTP_ROOT) else []
    print(f"  staged in tftp/root/: {' '.join(staged) or 'nothing'}")

    header("Last flash")
    logs = sorted(glob.glob(os.path.join(LOGS, "*.log")), key=os.path.getmtime)
    if not logs:
        print("  none yet")
    else:
        with open(logs[-1], "rb") as f:
            results = [line for line in f.read().splitlines() if line.startswith(b"==> ")]
        result = results[-1][4:].decode(errors="replace") if results else "no result recorded"
        print(f"  logs/{os.path.basename(logs[-1])}: {result}")
    return OK


def list_ports():
    for role in ports.ROLES:
        port = ports.find(role)
        if not port:
            print(f"  {role:6} missing")
            continue
        notes = []
        if serial_share.broker_pid(port):
            notes.append(f"{GREEN}shared console open{RESET}")
        busy = ports.holders(port)
        if busy:
            notes.append(f"{YELLOW}held by: {' '.join(busy)} (blocks flash){RESET}")
        print(f"  {role:6} {port} -> {os.path.realpath(port)}  {'  '.join(notes)}".rstrip())


def cmd_ports(_):
    list_ports()
    return OK if ports.find("uboot") else HOST


# --- flash -------------------------------------------------------------------

def cmd_flash(a):
    image = a.image or DEFAULT_IMAGE
    data = uboot.read_image(image)
    crc = uboot.crc32(data)
    expect = a.expect or uboot.default_expect(data)

    # Host-side checks, all before the board is touched.
    if a.lan:
        name = tftp.stage(image, TFTP_ROOT)
        interface = tftp.ensure_server(SERVE)
        server_ip = a.server_ip or tftp.address(interface)
        tftp.probe(server_ip, name)
    uboot_port = ports.require("uboot")
    hss_port = None if a.no_reset else ports.require("hss", " (needed for the reset; or use --no-reset)")
    for port in filter(None, (uboot_port, hss_port)):
        ports.require_free(port)

    log_file = a.log or uboot.log_path(LOGS, "lan" if a.lan else "usb")
    uboot.note(f"image: {os.path.relpath(image)} ({len(data)} bytes, CRC32 {crc:08x})")
    if a.lan:
        uboot.note(f"over Ethernet: TFTP from {server_ip} ({interface}), staged as tftp/root/{name}")
        hint = tftp.firewall_note()
        if hint:
            print(f"    note: {hint}")
    else:
        uboot.note(f"over USB: YMODEM at {a.baud} baud on {uboot_port}")
    uboot.note("reset via HSS on " + hss_port if hss_port else "no reset: using the board as it is")
    uboot.note(f"log: {os.path.relpath(log_file)}")
    print()

    try:
        sock = serial_share.ensure_broker(uboot_port)
    except OSError as e:
        raise Failure(HOST, str(e)) from None
    with open(log_file, "wb") as log:
        console = uboot.Console(sock, log)
        try:
            uboot.get_prompt(console, hss_port)
            if a.lan:
                uboot.load_tftp(console, server_ip, name, len(data))
            else:
                uboot.load_serial(console, uboot_port, os.path.basename(image), data, a.baud)
            uboot.verify(console, crc)
            uboot.boot(console)
            if a.console and not expect:
                code, message = OK, "booted; attaching the console"
            else:
                code, message = uboot.watch(console, expect, a.fail, a.idle, a.timeout)
        except Failure as e:
            code, message = e.code, str(e)
        except KeyboardInterrupt:
            if console.quiet:            # mid-transfer: make U-Boot's loady give up
                sock.sendall(b"\x18" * 5)
            code, message = INTERRUPTED, "interrupted" + (
                " (U-Boot may still be in loady: the next flash resets it)" if console.quiet else "")
        log.write(f"\n==> {message}\n".encode())
    sock.close()
    print(f"\n\n==> {message}", flush=True)
    if a.console and code == OK:
        serial_share.console(uboot_port)
    return code


# --- console, send, reset ----------------------------------------------------

def cmd_console(a):
    role = "hss" if a.hss else "uart3" if a.uart3 else "uboot"
    port = ports.require(role)
    ports.require_free(port)
    serial_share.console(port)
    return OK


def cmd_send(a):
    port = ports.require("hss" if a.hss else "uboot")
    serial_share.send(port, a.text)
    return OK


def cmd_reset(a):
    port = ports.require("hss")
    ports.require_free(port)
    if not a.yes:
        answer = input("Reset the PolarFire board? Whatever runs on it is lost. [y/N] ")
        if answer.strip().lower() != "y":
            return HOST
    serial_share.send(port, "\\rRESET\\r")        # through a shared HSS console if one is open
    ok(f"RESET sent to HSS on {port} (watch it boot: scripts/board.py console)")
    return OK


# --- tftp, install-udev ------------------------------------------------------

def cmd_tftp(a):
    return subprocess.run([SERVE, a.action]).returncode


def cmd_install_udev(_):
    def sudo(*cmd):
        subprocess.run(["sudo", *cmd], check=True)
    print(f"Installing {os.path.relpath(UDEV_RULE)} to /etc/udev/rules.d/ (asks for your password).")
    try:
        sudo("install", "-m", "0644", UDEV_RULE, "/etc/udev/rules.d/99-polarfire-discovery.rules")
        sudo("udevadm", "control", "--reload")
        device = ports.usb_device()
        if not device:
            print("Board not plugged in: the names appear when you plug it in.")
            return OK
        sudo("udevadm", "trigger", "--action=add", device)
        sudo("udevadm", "settle")
        for tty in glob.glob(f"{device}/*:1.*/ttyUSB*"):
            sudo("udevadm", "trigger", "--action=add", f"/sys/class/tty/{os.path.basename(tty)}")
        sudo("udevadm", "settle")
    except subprocess.CalledProcessError as e:
        raise Failure(HOST, f"{' '.join(e.cmd)} failed") from None
    names = sorted(glob.glob("/dev/polarfire-*"))
    if names:
        print("\n".join(f"  {n} -> {os.path.realpath(n)}" for n in names))
    else:
        warn("no /dev/polarfire-* yet: unplug and replug the board")
    return OK


# --- command line --------------------------------------------------------------

def parser():
    p = argparse.ArgumentParser(prog="scripts/board.py", description=__doc__.split("\n\n")[0],
                                epilog="\n\n".join(__doc__.split("\n\n")[1:]),
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="command", metavar="command")
    sub.required = True

    sub.add_parser("status", help="read-only health report").set_defaults(func=cmd_status)
    sub.add_parser("ports", help="the board's serial ports").set_defaults(func=cmd_ports)

    f = sub.add_parser("flash", help="load an image into RAM and boot it",
                       description="Load IMAGE (default images/sel4test.uImage) into RAM at "
                                   f"{uboot.LOAD:#x} and boot it. Nothing persistent is written.")
    f.add_argument("image", nargs="?", help="legacy uImage or FIT image")
    f.add_argument("--lan", action="store_true", help="over Ethernet (DHCP + TFTP) instead of USB")
    f.add_argument("--expect", metavar="REGEX",
                   help="success pattern (Python regex). Default: the sel4test result line for "
                        "sel4test images, else none (see --idle)")
    f.add_argument("--fail", metavar="REGEX", help="extra failure pattern, added to the built-in ones")
    f.add_argument("--idle", type=int, default=20, metavar="SEC",
                   help="with no success pattern: done after SEC s of silence (default 20)")
    f.add_argument("--timeout", type=int, default=600, metavar="SEC",
                   help="give up SEC s after the image starts (default 600)")
    f.add_argument("--console", action="store_true",
                   help="after booting, stay on the console (without --expect: right after bootm)")
    f.add_argument("--no-reset", action="store_true",
                   help="don't reset via HSS: use the U-Boot prompt if it is there, else wait for "
                        "someone to reset or power on the board")
    f.add_argument("--baud", type=int, default=1500000, choices=[1500000, 921600, 460800, 115200],
                   help="USB transfer speed (default 1500000; 3000000 does not work on this board)")
    f.add_argument("--server-ip", metavar="IP",
                   help="with --lan: address U-Boot downloads from (default: this host's address "
                        "on the TFTP server's interface)")
    f.add_argument("--log", metavar="FILE", help="console log (default logs/flash-<usb|lan>-<time>.log)")
    f.set_defaults(func=cmd_flash)

    c = sub.add_parser("console", help="shared serial console (exit: Ctrl-a Ctrl-x)")
    which = c.add_mutually_exclusive_group()
    which.add_argument("--hss", action="store_true", help="the HSS firmware console")
    which.add_argument("--uart3", action="store_true", help="the third UART")
    c.set_defaults(func=cmd_console)

    s = sub.add_parser("send", help="type text on a console")
    s.add_argument("text", help=r"what to type; \r is Enter, e.g. 'version\r'")
    s.add_argument("--hss", action="store_true", help="type on the HSS console instead of U-Boot")
    s.set_defaults(func=cmd_send)

    r = sub.add_parser("reset", help="reboot the board through HSS")
    r.add_argument("-y", "--yes", action="store_true", help="don't ask for confirmation")
    r.set_defaults(func=cmd_reset)

    t = sub.add_parser("tftp", help="the TFTP server for flash --lan")
    t.add_argument("action", nargs="?", default="status", choices=["start", "stop", "status", "logs"])
    t.set_defaults(func=cmd_tftp)

    sub.add_parser("install-udev", help="install the udev rule (sudo)").set_defaults(func=cmd_install_udev)
    return p


def main(argv=None):
    args = parser().parse_args(argv)
    try:
        return args.func(args)
    except Failure as e:
        if e.code == HOST:
            print(f"error: {e}", file=sys.stderr)
        else:
            print(f"\n==> {e}", flush=True)
        return e.code
    except KeyboardInterrupt:
        return INTERRUPTED


if __name__ == "__main__":
    sys.exit(main())
