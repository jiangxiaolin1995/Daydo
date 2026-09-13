import Foundation
import MCP
import Logging
import DaydoCore

actor CompatibleStdioTransport: Transport {
    private let base = StdioTransport()
    nonisolated var logger: Logger { base.logger }

    func connect() async throws { try await base.connect() }
    func disconnect() async { await base.disconnect() }
    func send(_ data: Data) async throws { try await base.send(data) }
    func receive() -> AsyncThrowingStream<Data, any Error> {
        AsyncThrowingStream { continuation in
            let pump = Task {
                do {
                    for try await message in await base.receive() {
                        continuation.yield(MCPCompatibility.normalizeInitialization(message))
                    }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in pump.cancel() }
        }
    }
}
