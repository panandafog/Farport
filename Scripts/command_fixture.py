"""Non-PTY commands for the disposable loopback fixture; never uses a real SSH server."""
import asyncio
import codecs
import contextlib
import os
import signal


async def run_command(process, root, environment):
    if "farport-fixture-missing-status" in process.command:
        process.stdout.write("ran without confirmed status\n")
        process.channel.close()  # Deliberately omit SSH exit-status.
        return
    child = await asyncio.create_subprocess_exec(
        "/bin/sh", "-c", process.command, cwd=root, env=environment, start_new_session=True,
        stdin=asyncio.subprocess.PIPE, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE,
    )

    async def input_pump():
        try:
            while data := await process.stdin.read(65536):
                child.stdin.write(data.encode("utf-8"))
                await child.stdin.drain()
        except (BrokenPipeError, ConnectionResetError):
            pass
        finally:
            child.stdin.close()

    async def output_pump(source, destination):
        decoder = codecs.getincrementaldecoder("utf-8")(errors="replace")
        while data := await source.read(65536):
            destination.write(decoder.decode(data))
            await destination.drain()
        destination.write(decoder.decode(b"", final=True))

    upstream = asyncio.create_task(input_pump())
    stdout = asyncio.create_task(output_pump(child.stdout, process.stdout))
    stderr = asyncio.create_task(output_pump(child.stderr, process.stderr))
    finished = asyncio.create_task(child.wait())
    disconnected = asyncio.create_task(process.wait_closed())
    try:
        await asyncio.wait([finished, disconnected], return_when=asyncio.FIRST_COMPLETED)
        if finished.done() and not process.is_closing():
            await asyncio.gather(stdout, stderr)
            process.exit(max(0, child.returncode))
    finally:
        for task in (upstream, stdout, stderr, disconnected):
            task.cancel()
        await asyncio.gather(upstream, stdout, stderr, disconnected, return_exceptions=True)
        if child.returncode is None:
            with contextlib.suppress(ProcessLookupError):
                os.killpg(child.pid, signal.SIGTERM)
            try:
                await asyncio.wait_for(asyncio.shield(finished), timeout=3)
            except asyncio.TimeoutError:
                with contextlib.suppress(ProcessLookupError):
                    os.killpg(child.pid, signal.SIGKILL)
        await finished
