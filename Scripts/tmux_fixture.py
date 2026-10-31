"""Real tmux/PTY bridge for the disposable SSH fixture, isolated from user sessions."""
import asyncio
import codecs
import contextlib
import fcntl
import os
import pathlib
import pty
import shlex
import shutil
import signal
import struct
import subprocess
import tempfile
import termios

import asyncssh


class TmuxFixture:
    def __init__(self, root):
        self.binary = shutil.which("tmux")
        if not self.binary:
            raise RuntimeError("Install tmux to run persistent-session tests: brew install tmux")
        self.temporary = tempfile.TemporaryDirectory(prefix="harbor-tmux-", dir="/private/tmp")
        self.directory = pathlib.Path(self.temporary.name)
        self.socket = self.directory / "server"
        self.root = root
        bindir = self.directory / "bin"
        bindir.mkdir()
        wrapper = bindir / "tmux"
        wrapper.write_text(
            "#!/bin/sh\nexec " + shlex.quote(self.binary) + " -S " + shlex.quote(str(self.socket))
            + ' -f /dev/null "$@"\n'
        )
        wrapper.chmod(0o700)
        self.environment = dict(
            os.environ, HOME=str(self.directory), SHELL="/bin/sh", ENV="", PS1="fixture$ ",
            PATH=str(bindir) + ":/usr/bin:/bin", LC_ALL="en_US.UTF-8",
        )
        self.environment.pop("TMUX", None)

    def close(self):
        # This socket belongs only to this fixture; never target the user's default server.
        subprocess.run([self.binary, "-S", str(self.socket), "kill-server"], capture_output=True, check=False)
        self.temporary.cleanup()

    async def run(self, process):
        # tmux owns line editing and echo through its real PTY, including Ctrl-B/Ctrl-C.
        if process.get_terminal_type():
            process.channel.set_line_mode(False)
            process.channel.set_echo(False)
        master, slave = pty.openpty()
        width, height, _, _ = process.get_terminal_size()
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", height or 30, width or 100, 0, 0))
        environment = dict(self.environment, TERM=process.get_terminal_type() or "xterm-256color")
        if process.get_extra_info("username") == "harbor-no-tmux":
            # Simulate a server with no binary, including standard fallback locations.
            # Never let this negative test launch the real user's default tmux server.
            os.close(master)
            os.close(slave)
            process.stderr.write("Farport: tmux is unavailable on this server.\r\n")
            process.exit(127)
            return

        def controlling_terminal():
            os.setsid()
            fcntl.ioctl(0, termios.TIOCSCTTY, 0)

        child = subprocess.Popen(
            ["/bin/sh", "-c", process.command], stdin=slave, stdout=slave, stderr=slave,
            env=environment, cwd=self.root, preexec_fn=controlling_terminal,
        )
        os.close(slave)
        os.set_blocking(master, False)
        loop = asyncio.get_running_loop()
        received = asyncio.Queue()

        def readable():
            try:
                data = os.read(master, 65536)
            except BlockingIOError:
                return
            except OSError:
                data = b""
            received.put_nowait(data)
            if not data:
                loop.remove_reader(master)

        async def remote_input():
            while True:
                try:
                    data = await process.stdin.read(8192)
                except asyncssh.TerminalSizeChanged as changed:
                    width, height, _, _ = changed.term_size
                    fcntl.ioctl(master, termios.TIOCSWINSZ, struct.pack("HHHH", height, width, 0, 0))
                    continue
                if not data:
                    return
                if data == "\x1dharbor-fixture-abort\x1d":
                    process.channel.get_connection().abort()
                    return
                pending = data.encode("utf-8")
                while pending:
                    try:
                        written = os.write(master, pending)
                        pending = pending[written:]
                    except BlockingIOError:
                        ready = loop.create_future()
                        loop.add_writer(master, lambda: None if ready.done() else ready.set_result(None))
                        try:
                            await ready
                        finally:
                            loop.remove_writer(master)

        async def local_output():
            decoder = codecs.getincrementaldecoder("utf-8")(errors="replace")
            while data := await received.get():
                process.stdout.write(decoder.decode(data))
                await process.stdout.drain()
            process.stdout.write(decoder.decode(b"", final=True))

        loop.add_reader(master, readable)
        upstream = asyncio.create_task(remote_input())
        downstream = asyncio.create_task(local_output())
        try:
            done, _ = await asyncio.wait([upstream, downstream], return_when=asyncio.FIRST_COMPLETED)
            for task in done:
                task.result()
        finally:
            loop.remove_reader(master)
            upstream.cancel()
            downstream.cancel()
            await asyncio.gather(upstream, downstream, return_exceptions=True)
            os.close(master)
            if child.poll() is None:
                with contextlib.suppress(ProcessLookupError):
                    os.killpg(child.pid, signal.SIGHUP)
            try:
                result = await asyncio.to_thread(child.wait, timeout=3)
            except subprocess.TimeoutExpired:
                child.kill()
                result = await asyncio.to_thread(child.wait)
            if not process.is_closing():
                process.exit(max(0, result))
