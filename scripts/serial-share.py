#!/usr/bin/env python3
"""Share one serial port between several programs.

Linux hands each byte arriving on a serial port to only one reader, so a
terminal and scripts/usb-flash.sh can't both read the U-Boot console. This
tool runs a small broker that owns the port and copies its output to every
connected client; anything a client types goes to the port. The broker starts
on demand and exits when its last client leaves or the board is unplugged.

Usage:
  scripts/serial-share.py console <port>     interactive terminal (exit: Ctrl-a Ctrl-x,
                                             Ctrl-a Ctrl-a sends a literal Ctrl-a)
  scripts/serial-share.py send <port> <text> write text (\\r for Enter) through the broker
                                             if one is running, else straight to the port
  scripts/serial-share.py sock <port>        if a broker is running: print its socket path and PID

Several consoles may be open at once, e.g. one in tmux and one in another SSH
session; all see the same output. 115200 8N1, no flow control.

Scripts can also take the control socket (control() below, one holder at a
time) to change the port's baud rate or turn on the FTDI 1 ms latency timer,
as scripts/usb-flash.sh does for YMODEM. The broker puts both back as soon as
that connection closes, even if the script crashed.
"""
import fcntl, os, select, signal, socket, struct, subprocess, sys, termios, time, tty

BAUD = termios.B115200
MAX_BACKLOG = 1 << 20      # drop a client that stops reading after 1 MiB
TIOCGSERIAL, TIOCSSERIAL, ASYNC_LOW_LATENCY = 0x541E, 0x541F, 1 << 13


def sock_path(port):
    # Keyed on the resolved ttyUSB name, so /dev/polarfire-uboot and its
    # /dev/serial/by-id/ alias find the same broker.
    run = os.environ.get("XDG_RUNTIME_DIR") or f"/tmp/serial-share-{os.getuid()}"
    d = os.path.join(run, "serial-share")
    os.makedirs(d, mode=0o700, exist_ok=True)
    return os.path.join(d, os.path.basename(os.path.realpath(port)) + ".sock")


def ctl_path(port):
    return sock_path(port)[:-len(".sock")] + ".ctl"


def connect(port):
    """Connected socket to a live broker for port, or None."""
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    try:
        s.connect(sock_path(port))
        return s
    except OSError:
        s.close()
        return None


def open_serial(port):
    fd = os.open(port, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
    a = termios.tcgetattr(fd)
    a[0] = a[1] = a[3] = 0
    a[2] = termios.CS8 | termios.CREAD | termios.CLOCAL
    a[4] = a[5] = BAUD
    a[6][termios.VMIN] = a[6][termios.VTIME] = 0
    termios.tcsetattr(fd, termios.TCSANOW, a)
    return fd


def serial_flags(fd, flags=None):
    """Read, or with flags set, the tty's serial_struct flags (offset 16)."""
    b = bytearray(fcntl.ioctl(fd, TIOCGSERIAL, bytes(128)))
    if flags is None:
        return struct.unpack_from("i", b, 16)[0]
    struct.pack_into("i", b, 16, flags)
    fcntl.ioctl(fd, TIOCSSERIAL, bytes(b))


def control_command(ser, line):
    """Apply one control-socket command to the port; returns the reply."""
    w = line.split()
    try:
        if len(w) == 2 and w[0] == "baud":
            speed = getattr(termios, f"B{int(w[1])}", None)
            if speed is None:
                return f"err no such baud rate: {w[1]}"
            termios.tcdrain(ser)
            a = termios.tcgetattr(ser)
            a[4] = a[5] = speed
            termios.tcsetattr(ser, termios.TCSANOW, a)
            return "ok"
        if len(w) == 2 and w[0] == "lowlat" and w[1] in ("0", "1"):
            f = serial_flags(ser)
            serial_flags(ser, f | ASYNC_LOW_LATENCY if w[1] == "1" else f & ~ASYNC_LOW_LATENCY)
            return "ok"
    except (OSError, ValueError) as e:
        return f"err {e}"
    return f"err unknown command: {line}"


def serve(port):
    path, cpath = sock_path(port), ctl_path(port)
    if connect(port):
        return                          # another broker won the race
    for f in (path, cpath):
        try:
            os.unlink(f)                # stale socket from a broker that died
        except FileNotFoundError:
            pass
    ser = open_serial(port)
    lst = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    lst.bind(path)
    lst.listen(8)
    ctl = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    ctl.bind(cpath)
    ctl.listen(2)
    with open(path + ".pid", "w") as f:
        f.write(f"{os.getpid()}\n")
    clients = {}                        # socket -> pending output
    to_port = b""                       # client input not yet written to the port
    owner, owner_in, saved = None, b"", None    # control connection, its input, settings to restore

    def drop(c):
        clients.pop(c, None)
        c.close()

    def release():
        nonlocal owner, owner_in, saved
        owner.close()
        owner, owner_in = None, b""
        try:
            termios.tcsetattr(ser, termios.TCSADRAIN, saved[0])
            serial_flags(ser, saved[1])
        except OSError:
            pass
        saved = None
    had_client, empty_since = False, time.time()
    try:
        while True:
            wants_write = [c for c, b in clients.items() if b]
            if to_port:
                wants_write.append(ser)
            rlist = [ser, lst, ctl, *clients] + ([owner] if owner else [])
            r, w, _ = select.select(rlist, wants_write, [], 0.5)
            if ser in r:
                try:
                    data = os.read(ser, 4096)
                except BlockingIOError:
                    data = None
                except OSError:
                    return              # board unplugged
                if data:
                    for c in clients:
                        clients[c] += data
            if ser in w:
                try:
                    n = os.write(ser, to_port)
                    to_port = to_port[n:]
                except BlockingIOError:
                    pass
                except OSError:
                    return
            if lst in r:
                c, _ = lst.accept()
                c.setblocking(False)
                clients[c] = b""
                had_client = True
            if ctl in r:
                c, _ = ctl.accept()
                if owner:
                    c.sendall(b"err busy: another program holds the control socket\n")
                    c.close()
                else:
                    owner, saved = c, (termios.tcgetattr(ser), serial_flags(ser))
            if owner and owner in r:
                try:
                    data = owner.recv(4096)
                except OSError:
                    data = b""
                if data:
                    owner_in += data
                else:
                    release()
            # Commands run once earlier client input has reached the port, so a
            # baud change never cuts off bytes typed before it.
            while owner and b"\n" in owner_in and not to_port:
                line, owner_in = owner_in.split(b"\n", 1)
                reply = control_command(ser, line.decode(errors="replace").strip())
                try:
                    owner.sendall(reply.encode() + b"\n")
                except OSError:
                    release()
            for c in [c for c in r if c in clients]:
                try:
                    data = c.recv(4096)
                except OSError:
                    data = b""
                if data:
                    to_port += data
                else:
                    drop(c)
            for c in [c for c in w if c in clients]:
                try:
                    n = c.send(clients[c])
                    clients[c] = clients[c][n:]
                except (BlockingIOError, InterruptedError):
                    pass
                except OSError:
                    drop(c)
            for c in [c for c, b in clients.items() if len(b) > MAX_BACKLOG]:
                drop(c)
            if clients or owner:
                empty_since = None
            elif empty_since is None:
                empty_since = time.time()
            # Linger briefly so a script can reconnect between steps.
            if empty_since and time.time() - empty_since > (3 if had_client else 10):
                return
    finally:
        if owner:
            release()
        lst.close()
        ctl.close()
        for f in (path, path + ".pid", cpath):
            try:
                os.unlink(f)
            except FileNotFoundError:
                pass
        os.close(ser)


def ensure_broker(port):
    s = connect(port)
    if s:
        return s
    subprocess.Popen([sys.executable, "-I", os.path.abspath(__file__), "serve", port],
                     stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                     stderr=subprocess.DEVNULL, start_new_session=True)
    for _ in range(50):
        time.sleep(0.1)
        s = connect(port)
        if s:
            return s
    sys.exit(f"serial-share: could not start a broker for {port}")


class control:
    """The broker's control socket for port (start the broker first with
    ensure_broker). cmd("baud 1500000"), cmd("lowlat 1"); raises OSError on
    an error reply. close() (or exiting) restores the port's settings."""

    def __init__(self, port):
        self.s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.s.connect(ctl_path(port))
        self.f = self.s.makefile("rb")

    def cmd(self, line, timeout=5):
        self.s.settimeout(timeout)
        self.s.sendall(line.encode() + b"\n")
        reply = self.f.readline().decode(errors="replace").strip()
        if reply != "ok":
            raise OSError(f"serial-share control '{line}': {reply or 'no reply'}")

    def close(self):
        self.f.close()
        self.s.close()


def console(port):
    s = ensure_broker(port)
    print(f"{port} via serial-share (exit: Ctrl-a Ctrl-x)\r", flush=True)
    fd = sys.stdin.fileno()
    old = termios.tcgetattr(fd) if os.isatty(fd) else None
    if old:
        tty.setraw(fd)
    escape = False
    try:
        while True:
            r, _, _ = select.select([fd, s], [], [])
            if s in r:
                data = s.recv(4096)
                if not data:
                    print("\r\nserial-share: port closed\r", flush=True)
                    return
                os.write(1, data)
            if fd in r:
                data = os.read(fd, 1024)
                if not data:
                    return
                out = b""
                for b in data:
                    if escape:
                        escape = False
                        if b == 0x18:           # Ctrl-x
                            return
                        if b != 0x01:
                            continue
                    elif b == 0x01:             # Ctrl-a
                        escape = True
                        continue
                    out += bytes([b])
                if out:
                    s.sendall(out)
    finally:
        if old:
            termios.tcsetattr(fd, termios.TCSADRAIN, old)
        print()


def send(port, text):
    data = text.encode().decode("unicode_escape").encode("latin-1")
    s = connect(port)
    if s:
        s.sendall(data)
        time.sleep(0.2)
        s.close()
    else:
        fd = open_serial(port)
        os.write(fd, data)
        termios.tcdrain(fd)
        os.close(fd)


def main():
    signal.signal(signal.SIGPIPE, signal.SIG_DFL)
    a = sys.argv[1:]
    if len(a) >= 2 and a[0] == "serve":
        serve(a[1])
    elif len(a) == 2 and a[0] == "console":
        console(a[1])
    elif len(a) == 3 and a[0] == "send":
        send(a[1], a[2])
    elif len(a) == 2 and a[0] == "sock":
        s = connect(a[1])
        if s:
            s.close()
            path = sock_path(a[1])
            try:
                pid = open(path + ".pid").read().strip()
            except OSError:
                pid = "?"
            print(path, pid)
    else:
        sys.exit(__doc__.split("Usage:")[1].split("\n\n")[0])


if __name__ == "__main__":
    main()
