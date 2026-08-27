import Darwin
import Foundation

struct ProcessResult: Sendable {
    let status: Int32
    let stdout: String
}

enum ProcessUtils {
    /// `FileManager.isExecutableFile` also returns true for searchable
    /// directories. Process can only launch an executable regular file, so
    /// follow symlinks and reject directories before selecting a CLI binary.
    static func isExecutableRegularFile(atPath path: String) -> Bool {
        var metadata = stat()
        guard stat(path, &metadata) == 0,
              (metadata.st_mode & S_IFMT) == S_IFREG else {
            return false
        }
        return access(path, X_OK) == 0
    }

    static func run(
        executable: String,
        arguments: [String],
        timeout: TimeInterval = 8
    ) throws -> ProcessResult {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        try process.run()
        let semaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in semaphore.signal() }
        if semaphore.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            throw UsageError.timedOut("本机命令响应超时")
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        return ProcessResult(
            status: process.terminationStatus,
            stdout: String(decoding: data, as: UTF8.self)
        )
    }

    static func expandedHome(_ path: String) -> String {
        guard path.hasPrefix("~/") else { return path }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(String(path.dropFirst(2))).path
    }
}
