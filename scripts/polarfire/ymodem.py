"""YMODEM sender: 1 KiB data blocks, CRC-16, one file per session.

The link object needs two methods:
  write(data)                send bytes to the receiver
  wait_byte(choices, secs)   next received byte that is in choices (others are
                             skipped), or None after secs

U-Boot's `loady` is the receiver this was written for: it starts each file with
'C', ACKs every block, and asks for the next file with another 'C', which the
empty block 0 answers ("no more files").
"""
import binascii
import time

SOH, STX, EOT, ACK, NAK, CAN, C = 0x01, 0x02, 0x04, 0x06, 0x15, 0x18, ord("C")
BLOCK = 1024
RETRIES = 10           # sends of one block before giving up
ACK_TIMEOUT = 10       # seconds per block


def block(seq, payload, size):
    """One framed block: header, payload padded to size, CRC-16 (XMODEM)."""
    payload = payload.ljust(size, b"\x1a" if seq else b"\x00")
    head = bytes([SOH if size == 128 else STX, seq & 0xFF, 0xFF - (seq & 0xFF)])
    return head + payload + binascii.crc_hqx(payload, 0).to_bytes(2, "big")


def send_block(link, packet):
    for _ in range(RETRIES):
        link.write(packet)
        reply = link.wait_byte({ACK, NAK, CAN}, ACK_TIMEOUT)
        if reply == ACK:
            return True
        if reply == CAN:
            return False
    return False


def send(link, name, data, progress=None):
    """Send one file; True once the receiver has acknowledged all of it.
    progress(bytes_sent, total, seconds) is called about four times."""
    if link.wait_byte({C}, 15) is None:
        return False
    header = name.encode()[:100] + b"\0" + str(len(data)).encode() + b"\0"
    if not send_block(link, block(0, header, 128)) or link.wait_byte({C}, 10) is None:
        return False
    start, step = time.time(), max(1, len(data) // BLOCK // 4)
    for n, offset in enumerate(range(0, len(data), BLOCK), 1):
        if not send_block(link, block(n, data[offset:offset + BLOCK], BLOCK)):
            return False
        if progress and n % step == 0:
            progress(min(offset + BLOCK, len(data)), len(data), time.time() - start)
    for _ in range(RETRIES):
        link.write(bytes([EOT]))
        if link.wait_byte({ACK, NAK}, 5) == ACK:
            break
    else:
        return False
    if link.wait_byte({C}, 5) is None:
        return False
    return send_block(link, block(0, b"", 128))
