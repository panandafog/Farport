"""Loopback-only SSH/SFTP fixture. All files live in a disposable temporary directory."""
import argparse
import asyncio
import json
import os
import pathlib
import signal
import tempfile
import uuid

import asyncssh
from blackhole_proxy import BlackholeProxy
from jump_fixture import JumpFixture
from tmux_fixture import TmuxFixture


async def main(port, run_tests, with_tmux):
    with tempfile.TemporaryDirectory(prefix="harbor-fixture-") as temporary:
        directory = pathlib.Path(temporary)
        root = directory / "files"
        root.mkdir()
        (root / "Documents").mkdir()
        (root / "hello.txt").write_text("Hello from Harbor's isolated SFTP fixture.\n")
        tmux = TmuxFixture(root) if with_tmux else None
        keys = {}
        for algorithm, name in [("ssh-ed25519", "ed25519"), ("ssh-rsa", "rsa")]:
            key = asyncssh.generate_private_key(algorithm)
            key.write_private_key(str(directory / name))
            keys[name] = key
        encrypted = directory / "ed25519-encrypted"
        keys["ed25519"].write_private_key(str(encrypted))
        encrypted.chmod(0o600)
        encryption = await asyncio.create_subprocess_exec(
            "/usr/bin/ssh-keygen", "-p", "-P", "", "-N", "harbor-passphrase", "-f", str(encrypted),
            stdout=asyncio.subprocess.DEVNULL,
        )
        if await encryption.wait() != 0:
            raise RuntimeError("Cannot prepare encrypted test key")

        class Server(asyncssh.SSHServer):
            def begin_auth(self, username):
                return True

            def password_auth_supported(self):
                return True

            def validate_password(self, username, password):
                return username in ("harbor", "harbor-no-tmux") and password == "harbor-test"

            def public_key_auth_supported(self):
                return True

            def validate_public_key(self, username, key):
                return username == "harbor" and any(key == value.convert_to_public() for value in keys.values())

        async def shell(process):
            if process.command:
                if tmux:
                    await tmux.run(process)
                else:
                    process.stderr.write("tmux is unavailable\r\n")
                    process.exit(127)
                return
            process.stdout.write("\x1b[32mHarbor SSH test server\x1b[0m\r\n")
            process.stdout.write("harbor@test ~ % ")
            try:
                while not process.stdin.at_eof():
                    try:
                        line = await process.stdin.readline()
                    except asyncssh.TerminalSizeChanged:
                        continue
                    if not line:
                        break
                    command = line.strip()
                    if command == "exit":
                        process.exit(0)
                        return
                    if command == "drop":
                        process.channel.get_connection().abort()
                        return
                    if command == "eof":
                        process.stdout.write_eof()
                        await process.channel.wait_closed()
                        return
                    if command == "stty size":
                        width, height, _, _ = process.get_terminal_size()
                        process.stdout.write(f"{height} {width}\r\n")
                    elif command.startswith("echo "):
                        process.stdout.write(command[5:] + "\r\n")
                    elif command == "pwd":
                        process.stdout.write("/\r\n")
                    elif command == "ls":
                        process.stdout.write("Documents  hello.txt\r\n")
                    elif command == "colors":
                        for prefix in (30, 90):
                            for index, label in enumerate(("Black", "Red", "Green", "Yellow", "Blue", "Magenta",
                                                           "Cyan", "White")):
                                process.stdout.write(f"\x1b[{prefix + index}m{label:10}\x1b[0m")
                            process.stdout.write("\r\n")
                        process.stdout.write("\x1b[1mBold\x1b[0m  \x1b[4mUnderline\x1b[0m  "
                                             "\x1b[7mInverse\x1b[0m  \x1b[41mBackground\x1b[0m\r\n")
                        process.stdout.write("\x1b[38;5;33m256 blue\x1b[0m  "
                                             "\x1b[38;2;180;90;150mTrue color\x1b[0m\r\n")
                    else:
                        process.stdout.write("fixture: echo, pwd, ls, colors, stty size, exit, drop, eof\r\n")
                    process.stdout.write("harbor@test ~ % ")
            except asyncssh.BreakReceived:
                process.exit(0)

        host_key = asyncssh.generate_private_key("ssh-ed25519")
        host_key.write_public_key(str(directory / "server-host.pub"))
        server = await asyncssh.create_server(
            Server, "127.0.0.1", port,
            server_host_keys=[host_key],
            process_factory=shell,
            sftp_factory=lambda channel: asyncssh.SFTPServer(channel, chroot=str(root)),
            allow_scp=False,
        )
        port = server.get_port()
        control_file = directory / "blackhole"
        proxy = BlackholeProxy(port, control_file)
        proxy_port = await proxy.start()
        jump = JumpFixture(directory, port)
        await jump.start()
        library = {"schemaVersion": 1, "hosts": [{
            "profile": {"id": str(uuid.uuid4()), "name": "Local test server", "hostname": "127.0.0.1",
                        "port": port, "username": "harbor", "authentication": "password",
                        "terminalProvider": "ssh", "fileProvider": "sftp", "initialDirectory": ".", "notes": ""},
            "credentials": {"password": "harbor-test", "privateKey": "", "passphrase": ""},
        }]}
        if tmux:
            persistent = json.loads(json.dumps(library["hosts"][0]))
            persistent["profile"].update(id=str(uuid.uuid4()), name="Persistent tmux server",
                                         terminalResumeStrategy="tmux")
            library["hosts"].append(persistent)
            unstable = json.loads(json.dumps(persistent))
            unstable["profile"].update(id=str(uuid.uuid4()), name="Reconnect test server", port=proxy_port)
            library["hosts"].append(unstable)
        gateway = json.loads(json.dumps(library["hosts"][0]))
        gateway["profile"].update(id=str(uuid.uuid4()), name="Local jump host", port=jump.port, username="jump")
        gateway["credentials"]["password"] = "jump-test"
        target = json.loads(json.dumps(library["hosts"][0]))
        target["profile"].update(id=str(uuid.uuid4()), name="Server via jump", hostname="build.internal",
                                  jumpHostIDs=[gateway["profile"]["id"]])
        library["hosts"].extend([gateway, target])
        library["schemaVersion"] = 3
        (directory / "hosts.json").write_text(json.dumps(library))
        print(json.dumps({"port": port, "directory": str(directory), "library": str(directory / "hosts.json"),
                          "proxyPort": proxy_port, "blackhole": str(control_file), "jumpPort": jump.port,
                          "jumpProxyPort": jump.proxy_port, "jumpBlackhole": str(jump.blackhole),
                          "jumpStats": str(jump.stats_path), "stallPort": jump.stall_port}), flush=True)
        try:
            async with server:
                if run_tests:
                    environment = dict(os.environ, HARBOR_TEST_PORT=str(port), HARBOR_TEST_KEYS=str(directory))
                    environment.update(HARBOR_TEST_PROXY_PORT=str(proxy_port), HARBOR_TEST_BLACKHOLE=str(control_file))
                    environment.update(HARBOR_TEST_JUMP_PORT=str(jump.port),
                                       HARBOR_TEST_STALL_PORT=str(jump.stall_port),
                                       HARBOR_TEST_JUMP_STATS=str(jump.stats_path))
                    if tmux:
                        environment.update(HARBOR_TEST_TMUX="1", HARBOR_TEST_ROOT=str(root))
                    test = await asyncio.create_subprocess_exec(
                        "swift", "test", env=environment, cwd=pathlib.Path(__file__).resolve().parent.parent,
                    )
                    result = await test.wait()
                    server.close()
                    await server.wait_closed()
                    if result:
                        raise SystemExit(result)
                else:
                    await server.wait_closed()
        finally:
            await jump.close()
            await proxy.close()
            if tmux:
                tmux.close()


if __name__ == "__main__":
    # XCTest-launched children can inherit ignored SIGINT; keep fixture shutdown reliable.
    signal.signal(signal.SIGINT, signal.default_int_handler)
    signal.signal(signal.SIGTERM, signal.default_int_handler)
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=0)
    parser.add_argument("--run-tests", action="store_true")
    parser.add_argument("--tmux", action="store_true")
    arguments = parser.parse_args()
    try:
        asyncio.run(main(arguments.port, arguments.run_tests, arguments.tmux))
    except KeyboardInterrupt:
        pass
