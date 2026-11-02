"""Disposable local PTY for shell-startup tests. No SSH, UI automation or real user home."""
import errno
import json
import os
import pathlib
import pty
import select
import signal
import sys
import time


def main():
    config = json.loads(pathlib.Path(sys.argv[1]).read_text())
    environment = dict(PATH=config.get("path", "/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin"),
                       HOME=config["home"], SHELL=config["shell"], TMPDIR=config["temporaryDirectory"],
                       TERM="xterm-256color", LC_ALL="C")
    environment.update(config.get("environment", {}))
    child, terminal = pty.fork()
    if child == 0:
        os.chdir(config["home"])
        os.execve("/bin/sh", ["sh", config["commandPath"]], environment)
    output = bytearray()
    sent = False
    status = None
    deadline = time.monotonic() + 15
    try:
        while time.monotonic() < deadline:
            if select.select([terminal], [], [], 0.1)[0]:
                try:
                    chunk = os.read(terminal, 65536)
                except OSError as error:
                    if error.errno == errno.EIO:
                        break
                    raise
                if not chunk:
                    break
                output.extend(chunk)
                if not sent and config.get("readyMarker", "\x1b[38;2;").encode() in output:
                    os.write(terminal, config["input"].encode())
                    sent = True
                if config.get("finishMarker") and config["finishMarker"].encode() in output:
                    break
            if len(output) > 1_048_576:
                raise RuntimeError("PTY output exceeded the fixture limit")
        else:
            raise RuntimeError("Shell did not finish: " + output.decode(errors="replace")[-3000:])
        os.close(terminal)
        terminal = None
        exit_deadline = time.monotonic() + 3
        while status is None and time.monotonic() < exit_deadline:
            waited, child_status = os.waitpid(child, os.WNOHANG)
            if waited:
                status = child_status
            else:
                time.sleep(0.05)
        if status is None:
            raise RuntimeError("PTY child did not exit after terminal close")
        print(json.dumps(dict(output=output.decode(errors="replace"), exitCode=os.waitstatus_to_exitcode(status))))
    finally:
        if status is None:
            os.kill(child, signal.SIGKILL)
            os.waitpid(child, 0)
        if terminal is not None:
            os.close(terminal)


if __name__ == "__main__":
    main()
