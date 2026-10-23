"""Disposable, forwarding-only SSH gateway. Private DNS aliases resolve only here."""
import asyncio
import json

import asyncssh
from blackhole_proxy import BlackholeProxy


class JumpFixture:
    def __init__(self, directory, target_port):
        self.directory = directory
        self.target_port = target_port
        self.connections = set()
        self.stalled = set()
        self.stats_path = directory / "jump-stats.json"
        self.stats = {"active": 0, "forwards": 0, "shells": 0, "destinations": []}
        self.key = asyncssh.generate_private_key("ssh-ed25519")
        self.key.write_private_key(str(directory / "jump-ed25519"))
        self.server = None
        self.stall_server = None
        self.proxy = None

    def publish(self):
        self.stats["active"] = len(self.connections)
        temporary = self.stats_path.with_suffix(".tmp")
        temporary.write_text(json.dumps(self.stats))
        temporary.replace(self.stats_path)

    async def start(self):
        fixture = self

        class Gateway(asyncssh.SSHServer):
            def connection_made(self, connection):
                self.connection = connection
                fixture.connections.add(connection)
                fixture.publish()

            def connection_lost(self, exc):
                fixture.connections.discard(self.connection)
                fixture.publish()

            def begin_auth(self, username):
                return True

            def password_auth_supported(self):
                return True

            def validate_password(self, username, password):
                return username in ("jump", "jump-denied", "jump-silent") and password == "jump-test"

            def public_key_auth_supported(self):
                return True

            def validate_public_key(self, username, key):
                return username == "jump" and key == fixture.key.convert_to_public()

            def session_requested(self):
                fixture.stats["shells"] += 1
                fixture.publish()
                return False

            async def connection_requested(self, dest_host, dest_port, orig_host, orig_port):
                fixture.stats["forwards"] += 1
                fixture.stats["destinations"].append(dest_host)
                fixture.publish()
                if self.connection.get_extra_info("username") == "jump-silent":
                    await self.connection.wait_closed()
                    return False
                if self.connection.get_extra_info("username") == "jump-denied":
                    raise asyncssh.ChannelOpenError(asyncssh.OPEN_ADMINISTRATIVELY_PROHIBITED,
                                                   "Fixture TCP forwarding prohibited")
                allowed = {"build.internal": fixture.target_port, "gateway.internal": fixture.port,
                           "stalled.internal": fixture.stall_port}
                if allowed.get(dest_host) != dest_port:
                    raise asyncssh.ChannelOpenError(asyncssh.OPEN_CONNECT_FAILED,
                                                   "Fixture destination unavailable")
                return await self.connection.forward_connection("127.0.0.1", dest_port)

        async def stall(reader, writer):
            self.stalled.add(writer)
            try:
                await reader.read()
            finally:
                self.stalled.discard(writer)
                writer.close()

        self.stall_server = await asyncio.start_server(stall, "127.0.0.1", 0)
        self.stall_port = self.stall_server.sockets[0].getsockname()[1]
        host_key = asyncssh.generate_private_key("ssh-ed25519")
        host_key.write_public_key(str(self.directory / "gateway-host.pub"))
        self.server = await asyncssh.create_server(
            Gateway, "127.0.0.1", 0, server_host_keys=[host_key],
        )
        self.port = self.server.get_port()
        self.blackhole = self.directory / "jump-blackhole"
        self.proxy = BlackholeProxy(self.port, self.blackhole)
        self.proxy_port = await self.proxy.start()
        self.publish()

    async def close(self):
        if self.proxy:
            await self.proxy.close()
        if self.server:
            self.server.close()
            await self.server.wait_closed()
        for connection in tuple(self.connections):
            connection.abort()
        await asyncio.gather(*(connection.wait_closed() for connection in tuple(self.connections)),
                             return_exceptions=True)
        if self.stall_server:
            self.stall_server.close()
            await self.stall_server.wait_closed()
        for writer in tuple(self.stalled):
            writer.close()
