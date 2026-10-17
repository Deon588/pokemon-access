#!/usr/bin/env python3
"""Development stand-in for the Pokemon Access helper app.

Listens on 127.0.0.1, logs every protocol line it receives (tabs kept as tabs),
answers HELLO with WELCOME, optionally sends scripted lines a few seconds after
HELLO and answers prompts with a fixed value.

Usage:
  fake_helper.py --port 48890 --log helper.log [--send 'KEY\\tDOWN\\tT' ...]
                 [--after 6] [--reply-ok Blue]
"""
import argparse
import datetime
import socket
import sys
import time


def expand(text):
    return text.replace("\\t", "\t").replace("\\n", "\n")


class Log:
    def __init__(self, path):
        self.handle = open(path, "a", encoding="utf-8")

    def write(self, text):
        stamp = datetime.datetime.now().strftime("%H:%M:%S.%f")[:-3]
        line = f"{stamp} {text}"
        print(line, flush=True)
        self.handle.write(line + "\n")
        self.handle.flush()


def serve(conn, args, log):
    conn.settimeout(0.2)
    buffer = b""
    hello_at = None
    scripted_sent = False
    while True:
        try:
            data = conn.recv(4096)
        except socket.timeout:
            data = None
        if data == b"":
            log.write("client disconnected")
            return
        if data:
            buffer += data
            while b"\n" in buffer:
                raw, buffer = buffer.split(b"\n", 1)
                line = raw.decode("utf-8", "replace").rstrip("\r")
                log.write("recv " + line)
                fields = line.split("\t")
                if fields[0] == "HELLO":
                    reply = "WELCOME\t0.0-dev\thelper"
                    conn.sendall((reply + "\n").encode("utf-8"))
                    log.write("sent " + reply)
                    hello_at = time.monotonic()
                elif fields[0].startswith("PROMPT_") and args.reply_ok is not None and len(fields) > 1:
                    reply = f"REPLY\t{fields[1]}\tOK\t{args.reply_ok}"
                    conn.sendall((reply + "\n").encode("utf-8"))
                    log.write("sent " + reply)
        if hello_at is not None and not scripted_sent and time.monotonic() - hello_at >= args.after:
            scripted_sent = True
            for item in args.send:
                line = expand(item)
                conn.sendall((line + "\n").encode("utf-8"))
                log.write("sent " + line)
                time.sleep(args.gap)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--log", required=True)
    parser.add_argument("--send", action="append", default=[], help="line to send after HELLO; \\t expands to a tab")
    parser.add_argument("--after", type=float, default=5.0, help="seconds after HELLO before --send lines go out")
    parser.add_argument("--gap", type=float, default=0.1, help="seconds between consecutive --send lines")
    parser.add_argument("--reply-ok", help="answer every PROMPT_* with REPLY <id> OK <value>")
    args = parser.parse_args()

    log = Log(args.log)
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(("127.0.0.1", args.port))
    server.listen(1)
    log.write(f"listening on {args.port}")
    while True:
        conn, _ = server.accept()
        log.write("client connected")
        try:
            serve(conn, args, log)
        except (ConnectionResetError, BrokenPipeError) as error:
            log.write(f"connection lost: {error}")
        finally:
            conn.close()


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(0)
