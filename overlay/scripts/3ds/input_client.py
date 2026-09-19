#!/usr/bin/env python3
"""Send button presses to a 3DS running Luma's InputRedirection (UDP 4950).

Rosalina menu -> "Input redirection: start" must be active on the console.
Packet layout (20 bytes, little-endian u32s), per Luma's input redirection
protocol (TuxSH's InputRedirectionClient):

  hidPad            HID button bits, ACTIVE bits = pressed
  touchState        0x2000000 | (y << 12) | x   when touching, else 0x2000000? no:
                    no-touch = 0x2000000 cleared -> use 0 when idle, flag|coords when touching
  circleState       neutral 0x7FF7FF   ((y+2048)<<12 | (x+2048)) roughly
  cStickState       neutral 0x80800081
  interfaceButtons  bit0 HOME, bit1 POWER

Usage:
  input_client.py <ip> press A                # tap a button ~100ms
  input_client.py <ip> hold DOWN 0.6          # hold a button for N seconds
  input_client.py <ip> combo L DOWN SELECT    # hold several together (1s)
  input_client.py <ip> touch 160 120          # tap the bottom screen
  input_client.py <ip> home                   # tap the HOME button

EXPERIMENTAL: written from protocol notes, not yet validated on the device.
"""
import socket
import struct
import sys
import time

PORT = 4950

HID = {
    "A": 1 << 0, "B": 1 << 1, "SELECT": 1 << 2, "START": 1 << 3,
    "RIGHT": 1 << 4, "LEFT": 1 << 5, "UP": 1 << 6, "DOWN": 1 << 7,
    "R": 1 << 8, "L": 1 << 9, "X": 1 << 10, "Y": 1 << 11,
}

CIRCLE_NEUTRAL = 0x7FF7FF
CSTICK_NEUTRAL = 0x80800081


def send(sock, ip, hid=0xFFF, touch=0x2000000, circle=CIRCLE_NEUTRAL,
         cstick=CSTICK_NEUTRAL, iface=0):
    sock.sendto(struct.pack("<5I", hid, touch, circle, cstick, iface),
                (ip, PORT))


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 1
    ip, cmd = sys.argv[1], sys.argv[2].lower()
    args = sys.argv[3:]
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)

    def pulse(hid_bits, seconds):
        # HID is ACTIVE-LOW on the wire: 0xFFF = nothing pressed, a cleared
        # bit = that button held.  (Getting this wrong holds every button at
        # once -- verified the hard way.)
        end = time.time() + seconds
        while time.time() < end:
            send(sock, ip, hid=(0xFFF & ~hid_bits))
            time.sleep(0.02)          # ~50Hz, the console samples at 60
        for _ in range(4):
            send(sock, ip, hid=0xFFF)
            time.sleep(0.02)

    if cmd == "press":
        pulse(HID[args[0].upper()], 0.1)
    elif cmd == "hold":
        pulse(HID[args[0].upper()], float(args[1]))
    elif cmd == "combo":
        bits = 0
        for name in args:
            bits |= HID[name.upper()]
        pulse(bits, 1.0)
    elif cmd == "touch":
        x, y = int(args[0]), int(args[1])
        state = (1 << 24) | ((y & 0xFFF) << 12) | (x & 0xFFF)
        end = time.time() + 0.15
        while time.time() < end:
            send(sock, ip, touch=state)
            time.sleep(0.02)
        for _ in range(4):
            send(sock, ip)
            time.sleep(0.02)
    elif cmd == "home":
        end = time.time() + 0.15
        while time.time() < end:
            send(sock, ip, iface=1)
            time.sleep(0.02)
        send(sock, ip)
    else:
        print("comando desconhecido:", cmd)
        return 1
    print("ok:", cmd, *args)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
