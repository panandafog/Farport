"""Loopback TCP proxy which silently drops packets while a control file exists."""
import asyncio
import contextlib


class BlackholeProxy:
    def __init__(self, backend_port, control_file):
        self.backend_port = backend_port
        self.control_file = control_file
        self.server = None
        self.connections = set()
        self.tasks = set()

    async def start(self):
        self.server = await asyncio.start_server(self.accept, "127.0.0.1", 0)
        return self.server.sockets[0].getsockname()[1]

    async def accept(self, reader, writer):
        task = asyncio.current_task()
        self.tasks.add(task)
        self.connections.add(writer)
        upstream = None
        try:
            remote, upstream = await asyncio.open_connection("127.0.0.1", self.backend_port)
            self.connections.add(upstream)

            async def relay(source, destination):
                while data := await source.read(65536):
                    if not self.control_file.exists():
                        destination.write(data)
                        await destination.drain()

            pipes = [asyncio.create_task(relay(reader, upstream)), asyncio.create_task(relay(remote, writer))]
            try:
                await asyncio.wait(pipes, return_when=asyncio.FIRST_COMPLETED)
            finally:
                for pipe in pipes:
                    pipe.cancel()
                await asyncio.gather(*pipes, return_exceptions=True)
        except (ConnectionError, OSError):
            pass
        finally:
            for stream in (writer, upstream):
                if stream:
                    self.connections.discard(stream)
                    stream.close()
                    with contextlib.suppress(ConnectionError, OSError):
                        await stream.wait_closed()
            self.tasks.discard(task)

    async def close(self):
        self.server.close()
        await self.server.wait_closed()
        for writer in tuple(self.connections):
            writer.close()
        for task in tuple(self.tasks):
            task.cancel()
        await asyncio.gather(*tuple(self.tasks), return_exceptions=True)
