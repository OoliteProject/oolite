#!/usr/bin/env python3
"""Task 7 (audio+speech parity) speech probe: attach to the Oolite debug
console over TCP and trigger the espeak-ng speech path.

Uses the debug-flavor-only callObjC bridge (OOJSConsole.m, #if OO_DEBUG) to
invoke -[Universe startSpeakingString:] / -[Universe isSpeaking] directly,
bypassing the per-savegame speech_on gate (no JS/ObjC setter exists).

Protocol mirrors tests/launch_snapshot.py (Oolite debug console plist
framing). Real audio is used deliberately (no SDL dummy driver, no
ALSOFT_DRIVERS=null): espeak-ng outputs via pcaudiolib/CoreAudio and OpenAL
Soft opens the CoreAudio device directly.
"""

import os
import plistlib
import select
import socket
import struct
import subprocess
import sys
import time

PORT = 8563
HOST = "127.0.0.1"
REQUEST_CONNECTION = "Request Connection"
APPROVE_CONNECTION = "Approve Connection"
PERFORM_COMMAND = "Perform Command"
CONSOLE_OUTPUT = "Console Output"
PACKET_TYPE_KEY = "packet type"
MESSAGE_KEY = "message"
CONSOLE_IDENTITY_KEY = "console identity"


def send_plist_packet(sock, packet):
    data = plistlib.dumps(packet, fmt=plistlib.FMT_XML)
    sock.sendall(struct.pack(">I", len(data)) + data)


def receive_plist_packet(sock, timeout=5.0):
    sock.settimeout(timeout)
    header = b""
    while len(header) < 4:
        chunk = sock.recv(4 - len(header))
        if not chunk:
            return None
        header += chunk
    length = struct.unpack(">I", header)[0]
    data = b""
    while len(data) < length:
        chunk = sock.recv(length - len(data))
        if not chunk:
            break
        data += chunk
    return plistlib.loads(data)


def drain_console_output(sock, seconds):
    """Collect Console Output packets for a bounded window."""
    lines = []
    end = time.time() + seconds
    while time.time() < end:
        r, _, _ = select.select([sock], [], [], 0.5)
        if not r:
            continue
        try:
            pkt = receive_plist_packet(sock, timeout=1.0)
        except Exception:
            continue
        if pkt is None:
            break
        if pkt.get(PACKET_TYPE_KEY) == CONSOLE_OUTPUT:
            msg = pkt.get(MESSAGE_KEY, "")
            lines.append(msg if isinstance(msg, str) else str(msg))
    return lines


def main():
    binary = sys.argv[1]
    server_sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server_sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server_sock.bind((HOST, PORT))
    server_sock.listen(1)

    env = os.environ.copy()
    env["LIBGL_ALWAYS_SOFTWARE"] = "1"
    # Real audio: SDL audio + OpenAL Soft + espeak all hit CoreAudio. Real
    # video: the offscreen SDL driver cannot provide a GL context on macOS.
    env.pop("SDL_AUDIODRIVER", None)
    env.pop("ALSOFT_DRIVERS", None)

    print(f"[*] Launching {binary}")
    proc = subprocess.Popen(
        [binary, "--no-splash"], env=env, stdout=sys.stdout, stderr=sys.stderr
    )

    conn = None
    ok = False
    try:
        timeout = time.time() + 30
        while time.time() < timeout:
            readable, _, _ = select.select([server_sock], [], [], 1)
            if readable:
                conn, _ = server_sock.accept()
                conn.setblocking(True)
                break
        if not conn:
            print("[!] Oolite failed to connect to the console server.")
            return 1

        pkt = receive_plist_packet(conn)
        if not pkt or pkt.get(PACKET_TYPE_KEY) != REQUEST_CONNECTION:
            print("[!] Handshake failed.")
            return 1
        send_plist_packet(
            conn,
            {
                PACKET_TYPE_KEY: APPROVE_CONNECTION,
                CONSOLE_IDENTITY_KEY: "T7SpeechProbe",
            },
        )
        print("[+] Connected; waiting for universe init...")
        time.sleep(8)

        # Trigger the espeak path directly on the Universe object.
        speak_js = (
            "var _t7r = universe.callObjC('startSpeakingString:', "
            "'Oolite speech parity probe. Alpha one, two, three.'); "
            "console.log('T7_SPEAK_RETURN=' + _t7r);"
        )
        send_plist_packet(conn, {PACKET_TYPE_KEY: PERFORM_COMMAND, MESSAGE_KEY: speak_js})
        out1 = drain_console_output(conn, 4)
        for line in out1:
            print(f"[console] {line.strip()}")

        # While synthesis should still be playing, ask for the state.
        send_plist_packet(
            conn,
            {
                PACKET_TYPE_KEY: PERFORM_COMMAND,
                MESSAGE_KEY: "console.log('T7_IS_SPEAKING=' + universe.callObjC('isSpeaking'));",
            },
        )
        out2 = drain_console_output(conn, 6)
        for line in out2:
            print(f"[console] {line.strip()}")

        blob = "\n".join(out1 + out2)
        speak_seen = "T7_SPEAK_RETURN=" in blob
        speaking_seen = "T7_IS_SPEAKING=" in blob
        print(f"[*] speak call dispatched: {speak_seen}; isSpeaking probe: {speaking_seen}")
        ok = speak_seen and speaking_seen

        send_plist_packet(
            conn,
            {PACKET_TYPE_KEY: PERFORM_COMMAND, MESSAGE_KEY: "quit();"},
        )
        try:
            proc.wait(timeout=15)
        except subprocess.TimeoutExpired:
            proc.kill()
        return 0 if ok else 1
    finally:
        if conn:
            conn.close()
        server_sock.close()
        if proc.poll() is None:
            proc.kill()


if __name__ == "__main__":
    sys.exit(main())
