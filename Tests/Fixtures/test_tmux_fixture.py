"""Shutdown regression tests; no SSH listener, tmux server or real host data."""
import asyncio
import errno
import pathlib
import sys
import unittest
from unittest.mock import AsyncMock, Mock, patch

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[2] / "Scripts"))
from tmux_fixture import TmuxFixture


class TmuxShutdownTests(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        self.fixture = TmuxFixture.__new__(TmuxFixture)
        self.fixture.binary = "/fixture/tmux"
        self.fixture.socket = pathlib.Path("/fixture/private/server")
        self.fixture.temporary = Mock()
        self.fixture.closing = False
        self.fixture.process_tasks = set()
        self.kill = patch("tmux_fixture.subprocess.run").start()
        self.addCleanup(patch.stopall)

    async def test_joins_handlers_before_stopping_private_server_and_cleaning(self):
        events = []
        started = asyncio.Event()

        async def handler(process):
            started.set()
            try:
                await asyncio.Event().wait()
            finally:
                # Model asynchronous PTY/child cleanup in the cancelled handler.
                await asyncio.sleep(0)
                events.append("handler finished")

        self.fixture._run = handler
        task = asyncio.create_task(self.fixture.run(Mock()))
        await started.wait()
        self.kill.side_effect = lambda *args, **kwargs: events.append("server stopped")
        self.fixture.temporary.cleanup.side_effect = lambda: events.append("directory removed")
        await self.fixture.close()
        self.assertTrue(task.cancelled())
        self.assertEqual(self.fixture.process_tasks, set())
        self.assertEqual(events, ["handler finished", "server stopped", "directory removed"])
        self.assertEqual(self.kill.call_args.args[0],
                         ["/fixture/tmux", "-S", "/fixture/private/server", "kill-server"])

    async def test_shutdown_rejects_late_handlers(self):
        await self.fixture.close()
        self.fixture._run = AsyncMock()
        process = Mock()
        await self.fixture.run(process)
        process.exit.assert_called_once_with(1)
        self.fixture._run.assert_not_awaited()

    async def test_retries_transient_directory_writer_race(self):
        self.fixture.temporary.cleanup.side_effect = [OSError(errno.ENOTEMPTY, "writer still exiting"), None]
        with patch("tmux_fixture.asyncio.sleep", new_callable=AsyncMock) as sleep:
            await self.fixture.close()
        self.assertEqual(self.fixture.temporary.cleanup.call_count, 2)
        sleep.assert_awaited_once()

    async def test_permission_error_is_not_hidden_or_retried(self):
        self.fixture.temporary.cleanup.side_effect = PermissionError(errno.EACCES, "not permitted")
        with patch("tmux_fixture.asyncio.sleep", new_callable=AsyncMock) as sleep:
            with self.assertRaises(PermissionError):
                await self.fixture.close()
        self.fixture.temporary.cleanup.assert_called_once()
        sleep.assert_not_awaited()

    async def test_persistent_cleanup_failure_is_bounded_and_reported(self):
        self.fixture.temporary.cleanup.side_effect = OSError(errno.ENOTEMPTY, "persistent writer")
        with patch("tmux_fixture.asyncio.sleep", new_callable=AsyncMock):
            with self.assertRaises(OSError):
                await asyncio.wait_for(self.fixture.close(), timeout=1)
        self.assertGreater(self.fixture.temporary.cleanup.call_count, 1)
