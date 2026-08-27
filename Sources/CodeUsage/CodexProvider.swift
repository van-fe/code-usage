import Foundation

actor CodexProvider {
    func fetch() async throws -> ProviderSnapshot {
        let binary = try Self.findBinary()
        return try await Task.detached(priority: .utility) {
            try Self.fetchSynchronously(binary: binary)
        }.value
    }

    private static func findBinary() throws -> String {
        var candidates: [String] = []
        if let override = ProcessInfo.processInfo.environment["CODEX_BINARY_PATH"], !override.isEmpty {
            candidates.append(override)
        }
        candidates += [
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            "~/.local/bin/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "/usr/bin/codex"
        ]
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            candidates += path.split(separator: ":").map { "\($0)/codex" }
        }
        for candidate in candidates {
            let expanded = ProcessUtils.expandedHome(candidate)
            if FileManager.default.isExecutableFile(atPath: expanded) { return expanded }
        }
        throw UsageError.notInstalled("未找到 Codex，请先安装并登录 Codex")
    }

    private static func fetchSynchronously(binary: String) throws -> ProviderSnapshot {
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = ["app-server", "--stdio"]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        let lock = NSLock()
        let finished = DispatchSemaphore(value: 0)
        var buffer = Data()
        var response: [String: Any]?
        var responseError: Error?
        var didFinish = false

        func finish(_ object: [String: Any]?, error: Error?) {
            lock.lock()
            defer { lock.unlock() }
            guard !didFinish else { return }
            didFinish = true
            response = object
            responseError = error
            finished.signal()
        }

        func send(_ object: [String: Any]) {
            guard let data = try? JSONSerialization.data(withJSONObject: object) else { return }
            var line = data
            line.append(0x0A)
            try? input.fileHandleForWriting.write(contentsOf: line)
        }

        output.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                finish(nil, error: UsageError.requestFailed("Codex 服务已退出"))
                return
            }
            lock.lock()
            buffer.append(data)
            var lines: [Data] = []
            while let newline = buffer.firstIndex(of: 0x0A) {
                lines.append(buffer.prefix(upTo: newline))
                buffer.removeSubrange(...newline)
            }
            lock.unlock()

            for line in lines {
                guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                      let id = object["id"] as? NSNumber else { continue }
                if id.intValue == 1 {
                    send(["method": "initialized"])
                    send(["id": 2, "method": "account/rateLimits/read"])
                } else if id.intValue == 2 {
                    if let error = object["error"] as? [String: Any] {
                        finish(nil, error: requestFailure(
                            message: error["message"] as? String ?? "Codex 用量请求失败"
                        ))
                    } else {
                        finish(object, error: nil)
                    }
                }
            }
        }

        do {
            try process.run()
        } catch {
            output.fileHandleForReading.readabilityHandler = nil
            throw UsageError.requestFailed("无法启动 Codex：\(error.localizedDescription)")
        }

        send([
            "id": 1,
            "method": "initialize",
            "params": [
                "clientInfo": [
                    "name": "code-usage-menubar",
                    "title": "CodeUsage",
                    "version": Bundle.main.object(
                        forInfoDictionaryKey: "CFBundleShortVersionString"
                    ) as? String ?? "development"
                ],
                "capabilities": ["experimentalApi": true]
            ]
        ])

        let waitResult = finished.wait(timeout: .now() + 20)
        output.fileHandleForReading.readabilityHandler = nil
        try? input.fileHandleForWriting.close()
        if process.isRunning { process.terminate() }

        if waitResult == .timedOut {
            throw UsageError.timedOut("Codex 用量读取超时")
        }
        if let responseError { throw responseError }
        guard let response else {
            throw UsageError.invalidResponse("Codex 没有返回可用数据")
        }
        return try map(response)
    }

    static func map(_ envelope: [String: Any], now: Date = Date()) throws -> ProviderSnapshot {
        guard let result = envelope["result"] as? [String: Any] else {
            throw UsageError.invalidResponse("Codex 响应格式不正确")
        }
        let buckets = result["rateLimitsByLimitId"] as? [String: Any]
        let rawBucket = (buckets?["codex"] as? [String: Any])
            ?? result.dictionary("rateLimits")
        guard let bucket = rawBucket else {
            throw UsageError.notSignedIn("Codex 当前登录方式不提供订阅额度")
        }

        let windows = [bucket.dictionary("primary"), bucket.dictionary("secondary")]
            .compactMap { $0 }
            .filter { $0.double("usedPercent") != nil }
            .sorted {
                ($0.double("windowDurationMins") ?? 0)
                    > ($1.double("windowDurationMins") ?? 0)
            }
        guard !windows.isEmpty else {
            throw UsageError.invalidResponse("Codex 未返回额度窗口")
        }

        var metrics = windows.enumerated().compactMap { index, window -> UsageMetric? in
            guard let percent = window.double("usedPercent") else { return nil }
            let minutes = window.double("windowDurationMins")
            return UsageMetric(
                id: windowID(minutes: minutes, index: index),
                title: windowTitle(minutes: minutes),
                usedPercent: percent,
                deadlineAt: DateParsing.date(from: window["resetsAt"]),
                windowDuration: minutes.map { $0 * 60 },
                group: .included
            )
        }

        if let individual = bucket.dictionary("individualLimit") {
            let limit = individual.double("limit")
            let used = individual.double("used")
            let usedPercent = individual.double("remainingPercent").map { 100 - $0 }
                ?? {
                    guard let used, let limit, limit > 0 else { return nil }
                    return used / limit * 100
                }()
            if usedPercent != nil || used != nil || limit != nil {
                metrics.append(UsageMetric(
                    id: "individual_limit",
                    title: "个人使用上限",
                    usedPercent: usedPercent ?? 0,
                    deadlineAt: DateParsing.date(from: individual["resetsAt"]),
                    group: .credits,
                    value: .quantity(
                        used: used,
                        limit: limit,
                        remaining: nil,
                        unit: "credits"
                    ),
                    showsProgress: usedPercent != nil
                ))
            }
        }

        var noteParts: [String] = []
        if let credits = bucket.dictionary("credits"),
           credits["hasCredits"] as? Bool == true {
            if credits["unlimited"] as? Bool == true {
                noteParts.append("工作区 Credits 不限量")
            } else if let balance = credits.double("balance") {
                metrics.append(UsageMetric(
                    id: "workspace_credits",
                    title: "工作区余额",
                    usedPercent: 0,
                    deadlineAt: nil,
                    group: .credits,
                    value: .quantity(
                        used: nil,
                        limit: nil,
                        remaining: balance,
                        unit: "credits"
                    ),
                    showsProgress: false
                ))
            }
        }
        if bucket["spendControlReached"] as? Bool == true {
            noteParts.append("已达到个人使用上限")
        } else if let reached = bucket["rateLimitReachedType"] as? String,
                  !reached.isEmpty {
            noteParts.append(rateLimitNote(reached))
        }

        let plan = normalizedPlanName(bucket["planType"] as? String)
        return ProviderSnapshot(
            provider: .codex,
            planName: plan,
            metrics: metrics,
            fetchedAt: now,
            note: noteParts.isEmpty ? nil : noteParts.joined(separator: " · "),
            subscriptionCategory: .inferred(from: plan)
        )
    }

    static func requestFailure(message: String) -> UsageError {
        let searchable = message.lowercased()
        if searchable.contains("not logged in") ||
            searchable.contains("not signed in") ||
            searchable.contains("login") ||
            searchable.contains("sign in") ||
            searchable.contains("unauthorized") ||
            searchable.contains("auth") ||
            searchable.contains("credential") {
            return .notSignedIn("Codex 尚未登录或登录已过期")
        }
        return .requestFailed(message)
    }

    private static func windowID(minutes: Double?, index: Int) -> String {
        guard let minutes else { return "window_\(index)" }
        if abs(minutes - 10_080) < 1 { return "weekly" }
        if abs(minutes - 300) < 1 { return "session" }
        return "window_\(Int(minutes.rounded()))"
    }

    private static func windowTitle(minutes: Double?) -> String {
        guard let minutes, minutes > 0 else { return "使用限额" }
        if abs(minutes - 10_080) < 1 { return "7 天额度" }
        if abs(minutes - 300) < 1 { return "5 小时额度" }
        if minutes >= 24 * 60, minutes.truncatingRemainder(dividingBy: 24 * 60) == 0 {
            return "\(Int(minutes / (24 * 60))) 天额度"
        }
        if minutes >= 60, minutes.truncatingRemainder(dividingBy: 60) == 0 {
            return "\(Int(minutes / 60)) 小时额度"
        }
        return "\(Int(minutes.rounded())) 分钟额度"
    }

    private static func normalizedPlanName(_ raw: String?) -> String? {
        guard let raw else { return nil }
        switch raw.lowercased() {
        case "team": return "Team"
        case "business", "self_serve_business_usage_based": return "Business"
        case "enterprise", "enterprise_cbp_usage_based": return "Enterprise"
        case "edu": return "Edu"
        default:
            return raw.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private static func rateLimitNote(_ raw: String) -> String {
        switch raw.lowercased() {
        case "credits_depleted": return "工作区 Credits 已用完"
        case "usage_limit_reached": return "已达到使用上限"
        default: return "额度受限：\(raw.replacingOccurrences(of: "_", with: " "))"
        }
    }
}
