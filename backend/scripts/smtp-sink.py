#!/usr/bin/env python3
"""A tiny SMTP sink for local checks: accepts every message and writes it to a directory.

Each message becomes <dir>/<n>.eml with an X-Sink-Envelope header block first:
    X-Sink-Mail-From: <sender>
    X-Sink-Rcpt-To: <recipient>   (one line per RCPT TO, so a BCC shows up here and nowhere else)
Plain SMTP only (no TLS, no auth), which is exactly what SMTP_URL=smtp://127.0.0.1:1025?starttls=no sends.

    python3 scripts/smtp-sink.py 127.0.0.1 1025 /tmp/sink
"""
import os
import socket
import sys
import threading

host, port, out = sys.argv[1], int(sys.argv[2]), sys.argv[3]
os.makedirs(out, exist_ok=True)
counter = [0]
lock = threading.Lock()


def handle(conn):
    f = conn.makefile("rb")
    conn.sendall(b"220 sink ready\r\n")
    mail_from, rcpts = None, []
    while True:
        line = f.readline()
        if not line:
            break
        cmd = line.decode("utf-8", "replace").rstrip("\r\n")
        up = cmd.upper()
        if up.startswith("EHLO") or up.startswith("HELO"):
            conn.sendall(b"250-sink\r\n250-8BITMIME\r\n250 SIZE 26214400\r\n")
        elif up.startswith("MAIL FROM:"):
            mail_from = cmd[10:].strip()
            conn.sendall(b"250 ok\r\n")
        elif up.startswith("RCPT TO:"):
            rcpts.append(cmd[8:].strip())
            conn.sendall(b"250 ok\r\n")
        elif up == "DATA":
            conn.sendall(b"354 go\r\n")
            body = bytearray()
            while True:
                l = f.readline()
                if not l or l == b".\r\n":
                    break
                if l.startswith(b".."):
                    l = l[1:]
                body += l
            with lock:
                counter[0] += 1
                path = os.path.join(out, f"{counter[0]}.eml")
            with open(path, "wb") as fh:
                fh.write(f"X-Sink-Mail-From: {mail_from}\r\n".encode())
                for r in rcpts:
                    fh.write(f"X-Sink-Rcpt-To: {r}\r\n".encode())
                fh.write(body)
            print(f"stored {path} from {mail_from} to {rcpts}", flush=True)
            mail_from, rcpts = None, []
            conn.sendall(b"250 queued\r\n")
        elif up == "RSET":
            mail_from, rcpts = None, []
            conn.sendall(b"250 ok\r\n")
        elif up == "NOOP":
            conn.sendall(b"250 ok\r\n")
        elif up == "QUIT":
            conn.sendall(b"221 bye\r\n")
            break
        else:
            conn.sendall(b"250 ok\r\n")
    conn.close()


srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
srv.bind((host, port))
srv.listen(5)
print(f"smtp sink on {host}:{port}, writing to {out}", flush=True)
while True:
    c, _ = srv.accept()
    threading.Thread(target=handle, args=(c,), daemon=True).start()
