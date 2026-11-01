import FarportCore

extension CitadelTerminalSession {
    func setDecorationColors(_ colors: TerminalDecorationColors) {
        decorationColors = colors
        scheduleDecorationUpdate()
    }

    func terminalOutputReceived() {
        receivedTerminalOutput = true
        scheduleDecorationUpdate()
    }

    private func scheduleDecorationUpdate() {
        guard !closed, receivedTerminalOutput, launch.requiresTmux,
              decorationTask == nil, decorationColors != appliedDecorationColors else { return }
        decorationTask = Task { [weak self] in await self?.applyDecorationColors() }
    }

    private func applyDecorationColors() async {
        defer { decorationTask = nil }
        while !closed, !Task.isCancelled, let colors = decorationColors, colors != appliedDecorationColors,
              let command = launch.decorationCommand(colors) {
            // Cosmetic control commands use another SSH channel, never the interactive input queue.
            // Failure must not terminate a working shell or retry on every output chunk.
            appliedDecorationColors = colors
            do {
                _ = try await client.executeCommand(command, maxResponseSize: 4096, mergeStreams: true)
            } catch { return }
        }
    }
}
