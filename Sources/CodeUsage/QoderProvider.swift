import Darwin
import Foundation

actor QoderProvider {
    enum PercentageRepresentation {
        /// Qoder IDE `credit/usage` emits ratios in the 0...1 range.
        case ratio
        /// The optional Agent SDK / CLI compatibility payload emits 0...100.
        case percent
    }

    private static let protocolTimeout: TimeInterval = 20
    private static let ideProtocolTimeout: TimeInterval = 10
    private static let sdkVersion = "1.0.25"
    private static let maximumBufferedOutput = 4 * 1_024 * 1_024
    private static let maximumHeaderSize = 16 * 1_024
    private static let maximumIDEFramesPerRequest = 32

    func fetch() async throws -> ProviderSnapshot {
        return try await Task.detached(priority: .utility) {
            // Prefer the dedicated CLI whenever it is installed. Besides
            // matching the user's selected client, this avoids requiring the
            // Qoder IDE to remain open merely to refresh menu-bar usage.
            var cliFailure: Error?
            if let binary = Self.findBinary() {
                do {
                    return try Self.fetchSynchronously(binary: binary)
                } catch {
                    cliFailure = error
                }
            }

            do {
                return try Self.fetchFromIDESynchronously()
            } catch {
                // When both sources fail, the CLI error is generally more
                // actionable because it reflects the explicitly installed
                // client and its login/protocol state.
                throw cliFailure ?? error
            }
        }.value
    }

    private static var ideSharedCacheDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Qoder/SharedClientCache", isDirectory: true)
    }

    private static func isIDEInstalled() -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            URL(fileURLWithPath: "/Applications/Qoder IDE.app"),
            URL(fileURLWithPath: "/Applications/Qoder.app"),
            home.appendingPathComponent("Applications/Qoder IDE.app"),
            home.appendingPathComponent("Applications/Qoder.app")
        ].contains { FileManager.default.fileExists(atPath: $0.path) }
    }

    private static func fetchFromIDESynchronously() throws -> ProviderSnapshot {
        let directory = ideSharedCacheDirectory
        let infoFile = directory.appendingPathComponent(".info.json", isDirectory: false)
        guard FileManager.default.fileExists(atPath: infoFile.path) else {
            if isIDEInstalled() {
                throw UsageError.notSignedIn("Qoder IDE 当前未运行，请打开 Qoder IDE 后重试")
            }
            throw UsageError.notInstalled("未找到 Qoder IDE")
        }

        let socketPath = try validatedIDESocketPath(
            infoFile: infoFile.path,
            expectedDirectory: directory.path
        )
        let descriptor = try connectToIDESocket(at: socketPath)
        defer { Darwin.close(descriptor) }

        let usage = try sendIDERequest(
            descriptor: descriptor,
            id: 1,
            method: "credit/usage",
            params: nil
        )
        // Older Qoder builds may expose credit/usage without user/plan. Usage
        // remains valid in that case and falls back to the response's userType.
        let plan = try? sendIDERequest(
            descriptor: descriptor,
            id: 2,
            method: "user/plan",
            params: [:]
        )
        return try map(
            usageObject: usage,
            planObject: plan,
            percentageRepresentation: .ratio
        )
    }

    /// Validates the small discovery file and its Unix socket without reading
    /// any Qoder credentials. Internal visibility is intentional for self-tests.
    static func validatedIDESocketPath(
        infoFile: String,
        expectedDirectory: String
    ) throws -> String {
        let standardizedDirectory = URL(fileURLWithPath: expectedDirectory, isDirectory: true)
            .standardizedFileURL.path
        let standardizedInfo = URL(fileURLWithPath: infoFile).standardizedFileURL.path
        guard URL(fileURLWithPath: standardizedInfo).deletingLastPathComponent().path == standardizedDirectory,
              URL(fileURLWithPath: standardizedInfo).lastPathComponent == ".info.json" else {
            throw UsageError.invalidResponse("Qoder IDE 连接信息路径不安全")
        }

        try validateOwnedFilesystemEntry(
            path: standardizedDirectory,
            expectedType: S_IFDIR,
            disallowedPermissions: 0o022,
            description: "Qoder IDE 数据目录"
        )
        let infoStat = try validateOwnedFilesystemEntry(
            path: standardizedInfo,
            expectedType: S_IFREG,
            disallowedPermissions: 0o022,
            description: "Qoder IDE 连接信息"
        )
        guard infoStat.st_size > 0, infoStat.st_size <= 64 * 1_024 else {
            throw UsageError.invalidResponse("Qoder IDE 连接信息大小异常")
        }

        let data: Data
        do {
            data = try Data(contentsOf: URL(fileURLWithPath: standardizedInfo), options: .mappedIfSafe)
        } catch {
            throw UsageError.requestFailed("无法读取 Qoder IDE 连接信息")
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawSocketPath = object["ipcServerPath"] as? String,
              !rawSocketPath.isEmpty else {
            throw UsageError.invalidResponse("Qoder IDE 未提供本机 Socket")
        }

        let socketPath = URL(fileURLWithPath: rawSocketPath).standardizedFileURL.path
        guard URL(fileURLWithPath: socketPath).deletingLastPathComponent().path == standardizedDirectory else {
            throw UsageError.invalidResponse("Qoder IDE Socket 路径不安全")
        }
        _ = try validateOwnedFilesystemEntry(
            path: socketPath,
            expectedType: S_IFSOCK,
            disallowedPermissions: 0o077,
            description: "Qoder IDE Socket"
        )
        return socketPath
    }

    @discardableResult
    private static func validateOwnedFilesystemEntry(
        path: String,
        expectedType: mode_t,
        disallowedPermissions: mode_t,
        description: String
    ) throws -> stat {
        var metadata = stat()
        guard lstat(path, &metadata) == 0 else {
            if errno == ENOENT || errno == ENOTDIR {
                throw UsageError.notSignedIn("Qoder IDE 当前未运行，请打开 Qoder IDE 后重试")
            }
            throw UsageError.requestFailed("无法检查\(description)")
        }
        guard (metadata.st_mode & S_IFMT) == expectedType else {
            throw UsageError.invalidResponse("\(description)类型不安全")
        }
        guard metadata.st_uid == getuid() else {
            throw UsageError.invalidResponse("\(description)不属于当前用户")
        }
        guard (metadata.st_mode & disallowedPermissions) == 0 else {
            throw UsageError.invalidResponse("\(description)权限过宽")
        }
        return metadata
    }

    private static func connectToIDESocket(at path: String) throws -> Int32 {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathCapacity = MemoryLayout.size(ofValue: address.sun_path)
        guard path.utf8.count < pathCapacity else {
            throw UsageError.invalidResponse("Qoder IDE Socket 路径过长")
        }
        path.withCString { source in
            withUnsafeMutablePointer(to: &address.sun_path) { destination in
                destination.withMemoryRebound(to: CChar.self, capacity: pathCapacity) {
                    _ = strlcpy($0, source, pathCapacity)
                }
            }
        }
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)

        let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            throw UsageError.requestFailed("无法创建 Qoder IDE 本机连接")
        }
        var noSigPipe: Int32 = 1
        let noSigPipeSize = socklen_t(MemoryLayout.size(ofValue: noSigPipe))
        _ = withUnsafePointer(to: &noSigPipe) {
            setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, $0, noSigPipeSize)
        }
        var timeout = timeval(tv_sec: Int(ideProtocolTimeout), tv_usec: 0)
        let timeoutSize = socklen_t(MemoryLayout.size(ofValue: timeout))
        _ = withUnsafePointer(to: &timeout) {
            setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, $0, timeoutSize)
        }
        _ = withUnsafePointer(to: &timeout) {
            setsockopt(descriptor, SOL_SOCKET, SO_SNDTIMEO, $0, timeoutSize)
        }

        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else {
            let connectionError = errno
            Darwin.close(descriptor)
            if connectionError == ECONNREFUSED || connectionError == ENOENT {
                throw UsageError.notSignedIn("Qoder IDE 当前未运行，请打开 Qoder IDE 后重试")
            }
            throw UsageError.requestFailed("无法连接 Qoder IDE 本机服务")
        }
        return descriptor
    }

    static func sendIDERequest(
        descriptor: Int32,
        id: Int,
        method: String,
        params: [String: Any]?
    ) throws -> [String: Any] {
        var request: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "method": method
        ]
        if let params { request["params"] = params }

        let body: Data
        do {
            body = try JSONSerialization.data(withJSONObject: request)
        } catch {
            throw UsageError.invalidResponse("无法编码 Qoder IDE 请求")
        }
        var frame = Data("Content-Length: \(body.count)\r\n\r\n".utf8)
        frame.append(body)
        let deadline = DispatchTime.now().uptimeNanoseconds +
            UInt64(ideProtocolTimeout * 1_000_000_000)
        try writeAll(frame, to: descriptor, deadline: deadline)

        var scannedFrames = 0
        while scannedFrames < maximumIDEFramesPerRequest {
            try ensureBeforeIDEDeadline(deadline)
            let envelope = try readIDEEnvelope(from: descriptor, deadline: deadline)
            scannedFrames += 1
            guard let responseID = (envelope["id"] as? NSNumber)?.intValue,
                  responseID == id else {
                // Ignore server notifications and unrelated in-flight responses.
                continue
            }
            if let error = envelope.dictionary("error") {
                let message = error["message"] as? String ?? "Qoder IDE 请求失败"
                let code = (error["code"] as? NSNumber).map(String.init(describing:))
                throw ideProtocolFailure(message: message, code: code)
            }
            guard let result = envelope.dictionary("result") else {
                throw UsageError.invalidResponse("Qoder IDE 返回了无效响应")
            }
            return result
        }
        throw UsageError.invalidResponse("Qoder IDE 返回了过多无关消息")
    }

    private static func writeAll(
        _ data: Data,
        to descriptor: Int32,
        deadline: UInt64
    ) throws {
        try data.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress else { return }
            var offset = 0
            while offset < rawBuffer.count {
                try updateSocketTimeout(
                    descriptor: descriptor,
                    option: SO_SNDTIMEO,
                    deadline: deadline
                )
                let sent = Darwin.send(descriptor, base.advanced(by: offset), rawBuffer.count - offset, 0)
                if sent > 0 {
                    offset += sent
                } else if sent < 0, errno == EINTR {
                    continue
                } else if errno == EAGAIN || errno == EWOULDBLOCK {
                    throw UsageError.timedOut("Qoder IDE 用量请求超时")
                } else {
                    throw UsageError.requestFailed("Qoder IDE 本机连接写入失败")
                }
            }
        }
    }

    private static func readIDEEnvelope(
        from descriptor: Int32,
        deadline: UInt64
    ) throws -> [String: Any] {
        var header = Data()
        let terminator: [UInt8] = [13, 10, 13, 10]
        while header.count < terminator.count ||
                !header.suffix(terminator.count).elementsEqual(terminator) {
            try ensureBeforeIDEDeadline(deadline)
            guard header.count < maximumHeaderSize else {
                throw UsageError.invalidResponse("Qoder IDE 响应头异常过大")
            }
            header.append(try readExactly(1, from: descriptor, deadline: deadline))
        }
        guard let headerText = String(data: header, encoding: .utf8) else {
            throw UsageError.invalidResponse("Qoder IDE 响应头编码无效")
        }
        var contentLength: Int?
        for line in headerText.components(separatedBy: "\r\n") {
            let pieces = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            if pieces.count == 2,
               pieces[0].trimmingCharacters(in: .whitespacesAndNewlines)
                .caseInsensitiveCompare("Content-Length") == .orderedSame {
                contentLength = Int(pieces[1].trimmingCharacters(in: .whitespacesAndNewlines))
                break
            }
        }
        guard let contentLength, contentLength > 0, contentLength <= maximumBufferedOutput else {
            throw UsageError.invalidResponse("Qoder IDE 响应长度无效")
        }
        let body = try readExactly(contentLength, from: descriptor, deadline: deadline)
        guard let envelope = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            throw UsageError.invalidResponse("Qoder IDE 返回了无效 JSON")
        }
        return envelope
    }

    private static func readExactly(
        _ count: Int,
        from descriptor: Int32,
        deadline: UInt64
    ) throws -> Data {
        var data = Data(count: count)
        var offset = 0
        try data.withUnsafeMutableBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress else { return }
            while offset < count {
                try updateSocketTimeout(
                    descriptor: descriptor,
                    option: SO_RCVTIMEO,
                    deadline: deadline
                )
                let received = Darwin.recv(descriptor, base.advanced(by: offset), count - offset, 0)
                if received > 0 {
                    offset += received
                } else if received == 0 {
                    throw UsageError.requestFailed("Qoder IDE 本机连接已关闭")
                } else if errno == EINTR {
                    continue
                } else if errno == EAGAIN || errno == EWOULDBLOCK {
                    throw UsageError.timedOut("Qoder IDE 用量响应超时")
                } else {
                    throw UsageError.requestFailed("Qoder IDE 本机连接读取失败")
                }
            }
        }
        return data
    }

    private static func ensureBeforeIDEDeadline(_ deadline: UInt64) throws {
        guard DispatchTime.now().uptimeNanoseconds < deadline else {
            throw UsageError.timedOut("Qoder IDE 用量请求超时")
        }
    }

    private static func updateSocketTimeout(
        descriptor: Int32,
        option: Int32,
        deadline: UInt64
    ) throws {
        let now = DispatchTime.now().uptimeNanoseconds
        guard now < deadline else {
            throw UsageError.timedOut("Qoder IDE 用量请求超时")
        }
        let remaining = deadline - now
        let seconds = Int(remaining / 1_000_000_000)
        let microseconds = max(1, Int((remaining % 1_000_000_000) / 1_000))
        var timeout = timeval(tv_sec: seconds, tv_usec: Int32(microseconds))
        let timeoutSize = socklen_t(MemoryLayout.size(ofValue: timeout))
        let result = withUnsafePointer(to: &timeout) {
            setsockopt(descriptor, SOL_SOCKET, option, $0, timeoutSize)
        }
        guard result == 0 else {
            throw UsageError.requestFailed("无法配置 Qoder IDE 本机连接超时")
        }
    }

    static func findBinary(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String? {
        var candidates: [String] = []

        if let override = environment["QODERCLI_PATH"], !override.isEmpty {
            candidates.append(override)
        }
        if let cliHome = environment["QODER_CLI_HOME"], !cliHome.isEmpty {
            candidates += [
                "\(cliHome)/.qoder/local/qodercli",
                "\(cliHome)/.qoder/local/qoder"
            ]
        }
        candidates += [
            "~/.qoder/local/qodercli",
            "~/.qoder/local/qoder",
            "~/.qoder/bin/qodercli",
            "~/.qoder/bin/qoder",
            "~/.local/bin/qodercli",
            "~/.local/bin/qoder",
            "/opt/homebrew/bin/qodercli",
            "/opt/homebrew/bin/qoder",
            "/usr/local/bin/qodercli",
            "/usr/local/bin/qoder",
            "/usr/bin/qodercli",
            "/usr/bin/qoder"
        ]
        if let searchPath = environment["PATH"] {
            for directory in searchPath.split(separator: ":") {
                candidates.append("\(directory)/qodercli")
                candidates.append("\(directory)/qoder")
            }
        }

        return firstExecutableBinary(in: candidates)
    }

    static func firstExecutableBinary(in candidates: [String]) -> String? {
        candidates.lazy
            .map(ProcessUtils.expandedHome)
            .first(where: { ProcessUtils.isExecutableRegularFile(atPath: $0) })
    }

    private struct AuthPayload {
        let directory: URL
        let file: URL
    }

    private final class ProtocolState: @unchecked Sendable {
        let finished = DispatchSemaphore(value: 0)
        let processExited = DispatchSemaphore(value: 0)

        private let lock = NSLock()
        private var buffer = Data()
        private var usageObject: [String: Any]?
        private var responseError: UsageError?
        private var didFinish = false
        private var didSendUsageRequest = false

        func finish(_ object: [String: Any]?, error: UsageError?) {
            lock.lock()
            defer { lock.unlock() }
            guard !didFinish else { return }
            didFinish = true
            usageObject = object
            responseError = error
            finished.signal()
        }

        func claimUsageRequest() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            guard !didFinish, !didSendUsageRequest else { return false }
            didSendUsageRequest = true
            return true
        }

        func consume(_ data: Data, maximumSize: Int) -> (lines: [Data], overflowed: Bool) {
            lock.lock()
            defer { lock.unlock() }

            buffer.append(data)
            var lines: [Data] = []
            var overflowed = false
            while let newline = buffer.firstIndex(of: 0x0A) {
                let line = Data(buffer.prefix(upTo: newline))
                buffer.removeSubrange(...newline)
                if line.count > maximumSize {
                    overflowed = true
                    break
                }
                if !line.isEmpty { lines.append(line) }
            }
            if buffer.count > maximumSize { overflowed = true }
            if overflowed { buffer.removeAll(keepingCapacity: false) }
            return (lines, overflowed)
        }

        func result() -> (usageObject: [String: Any]?, error: UsageError?) {
            lock.lock()
            defer { lock.unlock() }
            return (usageObject, responseError)
        }
    }

    private final class JSONLineWriter: @unchecked Sendable {
        private let lock = NSLock()
        private let handle: FileHandle

        init(_ handle: FileHandle) {
            self.handle = handle
        }

        func send(_ object: [String: Any]) throws {
            let data = try JSONSerialization.data(withJSONObject: object)
            var line = data
            line.append(0x0A)
            lock.lock()
            defer { lock.unlock() }
            try handle.write(contentsOf: line)
        }

        func close() {
            lock.lock()
            defer { lock.unlock() }
            try? handle.close()
        }
    }

    private static func makeCLIAuthPayload() throws -> AuthPayload {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("codeusage-qoder-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        let file = directory.appendingPathComponent("payload.json", isDirectory: false)
        do {
            try Data("{\"type\":\"qodercli\"}".utf8).write(to: file, options: .atomic)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: file.path
            )
            return AuthPayload(directory: directory, file: file)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    private static func fetchSynchronously(binary: String) throws -> ProviderSnapshot {
        let authPayload: AuthPayload
        do {
            authPayload = try makeCLIAuthPayload()
        } catch {
            throw UsageError.requestFailed("无法准备 Qoder CLI 登录状态：\(error.localizedDescription)")
        }
        defer { try? FileManager.default.removeItem(at: authPayload.directory) }

        let process = Process()
        let input = Pipe()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = [
            "--print",
            "--output-format", "stream-json",
            "--input-format", "stream-json",
            "--no-session-persistence",
            "--tools", "",
            "--disable-builtin-skills"
        ]
        process.currentDirectoryURL = FileManager.default.temporaryDirectory
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        var environment = ProcessInfo.processInfo.environment
        environment["QODER_AGENT_SDK_ENTRYPOINT"] = "sdk-ts"
        environment["QODER_AGENT_SDK_VERSION"] = sdkVersion
        environment["QODER_SDK_AUTH_PAYLOAD_FILE"] = authPayload.file.path
        environment.removeValue(forKey: "NODE_OPTIONS")
        process.environment = environment

        let state = ProtocolState()
        let writer = JSONLineWriter(input.fileHandleForWriting)

        output.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }

            let consumed = state.consume(data, maximumSize: maximumBufferedOutput)

            if consumed.overflowed {
                state.finish(nil, error: .invalidResponse("Qoder CLI 返回的数据异常过大"))
                return
            }
            for line in consumed.lines {
                guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any]
                else { continue }
                handleControlResponse(object, state: state, writer: writer)
            }
        }

        process.terminationHandler = { terminatedProcess in
            let status = terminatedProcess.terminationStatus
            if status == 41 {
                state.finish(nil, error: .notSignedIn("Qoder 登录已过期，请打开 Qoder 重新登录"))
            } else if status == 0 {
                state.finish(nil, error: .invalidResponse("Qoder CLI 已退出但未返回 Credits 用量"))
            } else {
                state.finish(nil, error: .requestFailed("Qoder CLI 异常退出（状态码 \(status)）"))
            }
            state.processExited.signal()
        }

        do {
            try process.run()
            try writer.send(controlRequest(
                id: "codeusage-init",
                requestType: "initialize",
                fields: [
                    "modelPolicyProvider": false,
                    "supportsCatalogReadyInitialize": true,
                    "initializeTimeoutMs": Int(protocolTimeout * 1_000)
                ]
            ))
        } catch {
            output.fileHandleForReading.readabilityHandler = nil
            writer.close()
            stop(process: process, processExited: state.processExited)
            process.terminationHandler = nil
            throw UsageError.requestFailed("无法启动 Qoder CLI：\(error.localizedDescription)")
        }

        let waitResult = state.finished.wait(timeout: .now() + protocolTimeout)
        if waitResult == .timedOut {
            try? writer.send(["type": "control_cancel_request", "request_id": "codeusage-init"])
            try? writer.send(["type": "control_cancel_request", "request_id": "codeusage-usage"])
        }

        output.fileHandleForReading.readabilityHandler = nil
        writer.close()
        stop(process: process, processExited: state.processExited)
        process.terminationHandler = nil
        try? output.fileHandleForReading.close()

        if waitResult == .timedOut {
            throw UsageError.timedOut("Qoder Credits 用量读取超时")
        }
        let result = state.result()
        if let responseError = result.error { throw responseError }
        guard let usageObject = result.usageObject else {
            throw UsageError.invalidResponse("Qoder 未返回可用的 Credits 配额")
        }
        return try map(usageObject: usageObject)
    }

    private static func handleControlResponse(
        _ object: [String: Any],
        state: ProtocolState,
        writer: JSONLineWriter
    ) {
        guard object["type"] as? String == "control_response",
              let envelope = object.dictionary("response"),
              let requestID = envelope["request_id"] as? String else {
            return
        }
        let subtype = envelope["subtype"] as? String
        if subtype == "error" {
            let message = envelope["error"] as? String ?? "Qoder CLI 控制请求失败"
            let code = envelope["code"] as? String
            state.finish(nil, error: protocolFailure(message: message, code: code))
            return
        }
        guard subtype == "success" else { return }

        if requestID == "codeusage-init" {
            guard state.claimUsageRequest() else { return }
            do {
                try writer.send(controlRequest(
                    id: "codeusage-usage",
                    requestType: "get_usage_info",
                    fields: [:]
                ))
            } catch {
                state.finish(nil, error: .requestFailed(
                    "无法向 Qoder CLI 请求用量：\(error.localizedDescription)"
                ))
            }
            return
        }
        guard requestID == "codeusage-usage" else { return }

        guard let payload = envelope.dictionary("response") else {
            state.finish(nil, error: .invalidResponse("Qoder CLI 未返回用量响应"))
            return
        }
        if let usage = payload.dictionary("usage") {
            state.finish(usage, error: nil)
            return
        }

        let serviceError = payload["usage_error"] as? String
        state.finish(nil, error: missingUsageFailure(serviceError))
    }

    private static func controlRequest(
        id: String,
        requestType: String,
        fields: [String: Any]
    ) -> [String: Any] {
        var request = fields
        // SDK 1.0.x emits both keys for compatibility with older CLI builds.
        request["type"] = requestType
        request["subtype"] = requestType
        return [
            "type": "control_request",
            "request_id": id,
            "request": request
        ]
    }

    private static func stop(process: Process, processExited: DispatchSemaphore) {
        guard process.isRunning else { return }
        // Closing stdin is the normal SDK shutdown signal. Give the CLI a
        // short grace period before escalating to TERM and finally KILL.
        if processExited.wait(timeout: .now() + 0.35) == .success { return }
        guard process.isRunning else { return }
        process.terminate()
        if processExited.wait(timeout: .now() + 0.75) == .timedOut,
           process.isRunning {
            _ = Darwin.kill(process.processIdentifier, SIGKILL)
            _ = processExited.wait(timeout: .now() + 0.25)
        }
    }

    private static func protocolFailure(message: String, code: String?) -> UsageError {
        let searchable = "\(code ?? "") \(message)".lowercased()
        if searchable.contains("auth") || searchable.contains("login") ||
            searchable.contains("signed in") || searchable.contains("credential") {
            return .notSignedIn("Qoder 登录状态不可用，请打开 Qoder 后重试")
        }
        return .requestFailed(message)
    }

    private static func ideProtocolFailure(message: String, code: String?) -> UsageError {
        let searchable = "\(code ?? "") \(message)".lowercased()
        if searchable.contains("auth") || searchable.contains("login") ||
            searchable.contains("signed in") || searchable.contains("credential") {
            return .notSignedIn("Qoder IDE 登录状态不可用，请重新登录后重试")
        }
        if searchable.contains("method not found") {
            return .invalidResponse("当前 Qoder IDE 版本不支持读取 Credits 用量")
        }
        // Do not surface arbitrary server text: diagnostics can contain internal
        // request details even though this code never reads Qoder credentials.
        return .requestFailed("Qoder IDE 用量请求失败")
    }

    private static func missingUsageFailure(_ message: String?) -> UsageError {
        guard let message, !message.isEmpty else {
            return .invalidResponse("Qoder CLI 未返回账号 Credits；请检查网络和登录状态，或升级 Qoder CLI")
        }
        return protocolFailure(message: message, code: nil)
    }

    private struct QuotaBucket {
        let used: Double?
        let limit: Double?
        let remaining: Double?
        let percentage: Double?
        let unit: String
        let available: Bool?
    }

    static func map(
        usageObject: [String: Any],
        planObject: [String: Any]? = nil,
        percentageRepresentation: PercentageRepresentation = .percent,
        now: Date = Date()
    ) throws -> ProviderSnapshot {
        let expiry = DateParsing.date(from: usageObject["expiresAt"])
        var metrics: [UsageMetric] = []
        var notes: [String] = []

        if let object = usageObject.dictionary("userQuota") {
            let bucket = quotaBucket(
                object,
                limitKey: "total",
                percentageRepresentation: percentageRepresentation
            )
            appendMetric(
                bucket,
                id: "included",
                title: "套餐 Credits",
                group: .included,
                deadlineAt: expiry,
                deadlineKind: .expiration,
                metrics: &metrics
            )
        }

        if let object = usageObject.dictionary("addOnQuota") {
            let bucket = quotaBucket(
                object,
                limitKey: "total",
                percentageRepresentation: percentageRepresentation
            )
            appendMetric(
                bucket,
                id: "add_on",
                title: "个人 Add-on",
                group: .personalAddOn,
                deadlineAt: nil,
                metrics: &metrics
            )
        }

        if let object = usageObject.dictionary("orgResourcePackage") {
            let bucket = quotaBucket(
                object,
                limitKey: "cap",
                percentageRepresentation: percentageRepresentation
            )
            appendMetric(
                bucket,
                id: "shared",
                title: "组织共享 Credits",
                group: .organizationShared,
                deadlineAt: nil,
                metrics: &metrics
            )
            if bucket.available == false {
                notes.append("组织共享 Credits 当前不可用")
            }
        }

        if let overall = usagePercentage(
            usageObject["totalUsagePercentage"],
            representation: percentageRepresentation
        ) {
            if metrics.isEmpty {
                metrics.append(UsageMetric(
                    id: "total",
                    title: "总 Credits",
                    usedPercent: overall,
                    deadlineAt: expiry,
                    deadlineKind: .expiration
                ))
            }
            notes.append("综合已用 \(formatNumber(overall))%")
        }
        if usageObject["isPlanQuotaProrated"] as? Bool == true {
            notes.append("本周期套餐额度按比例折算")
        }
        if usageObject["isQuotaExceeded"] as? Bool == true {
            notes.append("全部可用额度已耗尽")
        }

        guard !metrics.isEmpty else {
            throw UsageError.invalidResponse("Qoder 未返回可计算的 Credits 配额")
        }

        let planName = normalizedPlanName(planObject?["plan_tier_name"] as? String)
            ?? normalizedPlanName(usageObject["userType"] as? String)
        return ProviderSnapshot(
            provider: .qoder,
            planName: planName,
            metrics: metrics,
            fetchedAt: now,
            note: notes.isEmpty ? nil : notes.joined(separator: " · "),
            subscriptionCategory: .inferred(from: planName)
        )
    }

    private static func quotaBucket(
        _ object: [String: Any],
        limitKey: String,
        percentageRepresentation: PercentageRepresentation
    ) -> QuotaBucket {
        var used = nonnegativeDouble(object["used"])
        var limit = nonnegativeDouble(object[limitKey])
        var remaining = nonnegativeDouble(object["remaining"])

        if used == nil, let limit, let remaining, remaining <= limit {
            used = limit - remaining
        }
        if remaining == nil, let limit, let used, used <= limit {
            remaining = limit - used
        }
        if limit == nil, let used, let remaining {
            limit = used + remaining
        }

        var percentage = usagePercentage(
            object["percentage"],
            representation: percentageRepresentation
        )
        if percentage == nil, let used, let limit, limit > 0 {
            percentage = used / limit * 100
        }
        let unit = (object["unit"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)

        return QuotaBucket(
            used: used,
            limit: limit,
            remaining: remaining,
            percentage: percentage,
            unit: unit?.isEmpty == false ? unit! : "credits",
            available: object["available"] as? Bool
        )
    }

    private static func appendMetric(
        _ bucket: QuotaBucket,
        id: String,
        title: String,
        group: UsageMetric.Group,
        deadlineAt: Date?,
        deadlineKind: UsageMetric.DeadlineKind = .reset,
        metrics: inout [UsageMetric]
    ) {
        let hasValue = bucket.used != nil || bucket.limit != nil || bucket.remaining != nil
        guard bucket.percentage != nil || hasValue else { return }
        metrics.append(UsageMetric(
            id: id,
            title: title,
            usedPercent: bucket.percentage ?? 0,
            deadlineAt: deadlineAt,
            deadlineKind: deadlineKind,
            group: group,
            value: .quantity(
                used: bucket.used,
                limit: bucket.limit,
                remaining: bucket.remaining,
                unit: bucket.unit
            ),
            showsProgress: bucket.percentage != nil
        ))
    }

    private static func nonnegativeDouble(_ value: Any?) -> Double? {
        if value is Bool { return nil }
        let number: Double?
        if let value = value as? NSNumber {
            number = value.doubleValue
        } else if let value = value as? String {
            number = Double(value)
        } else {
            number = nil
        }
        guard let number, number.isFinite, number >= 0 else { return nil }
        return number
    }

    private static func usagePercentage(
        _ value: Any?,
        representation: PercentageRepresentation
    ) -> Double? {
        guard let number = nonnegativeDouble(value) else { return nil }
        switch representation {
        case .ratio: return number * 100
        case .percent: return number
        }
    }

    private static func normalizedPlanName(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { word in word.prefix(1).uppercased() + word.dropFirst().lowercased() }
            .joined(separator: " ")
    }

    private static func formatNumber(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
    }
}
