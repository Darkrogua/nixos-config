"""Касание Microarray MAFP (3274:8012) -> команда. Не распознаёт отпечаток.

Сенсор не отдаёт координаты, только палец есть/нет:
  короткий тап       — on-press.sh
  длинное удержание  — on-hold.sh
"""

from __future__ import annotations

import os
import subprocess
import sys
import time

import usb.core
import usb.util

VID, PID = 0x3274, 0x8012
EP_OUT, EP_IN = 0x03, 0x83
TIMEOUT = 800
LONG_MS = 0.45
POLL_S = 0.08

HANDSHAKE = bytes(
    [0xEF, 0x01, 0xFF, 0xFF, 0xFF, 0xFF, 0x01, 0x00, 0x02, 0x23, 0xA2]
)


class UsbGone(Exception):
    pass


def build_cmd(payload: bytes) -> bytes:
    length = len(payload) + 2
    pkt = bytearray([0xEF, 0x01, 0xFF, 0xFF, 0xFF, 0xFF, 0x01, length >> 8, length & 0xFF])
    pkt.extend(payload)
    csum = sum(pkt[6:]) & 0xFFFF
    pkt.extend([(csum >> 8) & 0xFF, csum & 0xFF])
    return bytes(pkt)


def parse_ack(buf: bytes) -> bytes | None:
    if len(buf) < 11 or buf[0] != 0xEF or buf[1] != 0x01 or buf[6] != 0x07:
        return None
    length = (buf[7] << 8) | buf[8]
    expected = 9 + length
    if len(buf) < expected:
        return None
    return buf[9 : expected - 2]


def open_dev():
    dev = usb.core.find(idVendor=VID, idProduct=PID)
    if dev is None:
        raise UsbGone("MAFP 3274:8012 не найден")
    try:
        if dev.is_kernel_driver_active(0):
            dev.detach_kernel_driver(0)
    except (usb.core.USBError, NotImplementedError):
        pass
    try:
        dev.set_configuration()
        usb.util.claim_interface(dev, 0)
    except usb.core.USBError as e:
        raise UsbGone(str(e)) from e
    return dev


def close_dev(dev) -> None:
    if dev is None:
        return
    try:
        usb.util.dispose_resources(dev)
    except usb.core.USBError:
        pass


def send_recv(dev, pkt: bytes, read_len: int = 64) -> bytes:
    try:
        dev.write(EP_OUT, pkt, timeout=TIMEOUT)
        return bytes(dev.read(EP_IN, read_len, timeout=TIMEOUT))
    except usb.core.USBError as e:
        raise UsbGone(str(e)) from e


def finger_present(dev) -> bool:
    raw = send_recv(dev, build_cmd(bytes([0x01])))
    data = parse_ack(raw)
    return bool(data) and data[0] == 0


def handshake(dev) -> None:
    try:
        send_recv(dev, HANDSHAKE, 12)
    except UsbGone as e:
        print(f"handshake: {e}", file=sys.stderr)
        raise


def fire(kind: str) -> None:
    env_key = "MA_TOUCH_HOLD" if kind == "hold" else "MA_TOUCH_CMD"
    hook_name = "on-hold.sh" if kind == "hold" else "on-press.sh"
    cmd = os.environ.get(env_key)
    if cmd:
        subprocess.Popen(["sh", "-c", cmd], start_new_session=True)
        return
    hook = os.path.expanduser(f"~/.config/ma-touch/{hook_name}")
    if os.path.isfile(hook) and os.access(hook, os.X_OK):
        subprocess.Popen([hook], start_new_session=True)
        return
    label = "Удержание" if kind == "hold" else "Касание"
    subprocess.Popen(["notify-send", "Сканер", label], start_new_session=True)


def main() -> int:
    dev = None
    down = False
    t_press = 0.0
    print("slushayu kasaniya MAFP (tap / hold)...", flush=True)
    while True:
        if dev is None:
            try:
                dev = open_dev()
                handshake(dev)
                print("usb ok", flush=True)
            except UsbGone as e:
                print(f"usb wait: {e}", flush=True)
                close_dev(dev)
                dev = None
                time.sleep(1)
                continue
        try:
            present = finger_present(dev)
        except UsbGone as e:
            print(f"usb lost: {e}", flush=True)
            close_dev(dev)
            dev = None
            down = False
            time.sleep(0.5)
            continue
        if present and not down:
            down = True
            t_press = time.monotonic()
            print("press", flush=True)
        elif not present and down:
            down = False
            dur = time.monotonic() - t_press
            kind = "hold" if dur >= LONG_MS else "tap"
            print(f"lift {dur:.2f}s {kind}", flush=True)
            time.sleep(0.12)
            fire(kind)
        else:
            time.sleep(POLL_S)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        raise SystemExit(0)
