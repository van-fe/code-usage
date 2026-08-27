import Foundation

struct ClaudeOAuth: Decodable, Sendable {
    let accessToken: String?
    let refreshToken: String?
    let expiresAt: Double?
    let subscriptionType: String?
    let rateLimitTier: String?
    let scopes: [String]?
}

struct ClaudeCredentials: Decodable, Sendable {
    let claudeAiOauth: ClaudeOAuth?
}

actor ClaudeCodeProvider {
    private var inMemoryAccessToken: String?

    func fetch() async throws -> ProviderSnapshot {
        let oauth = try await Task.detached(priority: .utility) {
            try Self.readCredentials()
        }.value

        if let scopes = oauth.scopes, !scopes.isEmpty, !scopes.contains("user:profile") {
            throw UsageError.notSignedIn("请在 Claude Code 中重新登录以读取用量")
        }

        var token = inMemoryAccessToken ?? oauth.accessToken
        if token == nil || Self.isExpired(oauth.expiresAt) {
            token = try await refreshedToken(using: oauth.refreshToken)
            inMemoryAccessToken = token
        }
        guard var accessToken = token, !accessToken.isEmpty else {
            throw UsageError.notSignedIn("Claude Code 尚未登录")
        }

        var response = try await requestUsage(accessToken: accessToken)
        if response.statusCode == 401 || response.statusCode == 403 {
            accessToken = try await refreshedToken(using: oauth.refreshToken)
            inMemoryAccessToken = accessToken
            response = try await requestUsage(accessToken: accessToken)
        }
        guard (200..<300).contains(response.statusCode) else {
            if response.statusCode == 401 || response.statusCode == 403 {
                throw UsageError.notSignedIn("Claude Code 登录已过期，请运行 claude 重新登录")
            }
            throw UsageError.requestFailed("Claude Code 用量请求失败（HTTP \(response.statusCode)）")
        }
        return try Self.map(usageData: response.data, oauth: oauth)
    }

    private struct HTTPResult: Sendable {
        let statusCode: Int
        let data: Data
    }

    private static func readCredentials() throws -> ClaudeOAuth {
        var documents: [String] = []
        if let keychain = try? ProcessUtils.run(
            executable: "/usr/bin/security",
            arguments: ["find-generic-password", "-s", "Claude Code-credentials", "-w"],
            timeout: 5
        ), keychain.status == 0 {
            documents.append(keychain.stdout)
        }

        let configDirectory = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"]
            .flatMap { $0.isEmpty ? nil : $0 } ?? "~/.claude"
        let credentialsPath = ProcessUtils.expandedHome(configDirectory)
            + "/.credentials.json"
        if let file = try? String(contentsOfFile: credentialsPath, encoding: .utf8) {
            documents.append(file)
        }

        for document in documents {
            if let decoded = decodeCredentials(document),
               let oauth = decoded.claudeAiOauth,
               oauth.accessToken?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                return oauth
            }
        }
        throw UsageError.notSignedIn("Claude Code 尚未登录，请运行 claude 完成登录")
    }

    private static func decodeCredentials(_ text: String) -> ClaudeCredentials? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = trimmed.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(ClaudeCredentials.self, from: data) {
            return decoded
        }
        guard trimmed.count.isMultiple(of: 2),
              trimmed.allSatisfy({ $0.isHexDigit }) else { return nil }
        var bytes = Data()
        var index = trimmed.startIndex
        while index < trimmed.endIndex {
            let next = trimmed.index(index, offsetBy: 2)
            guard let byte = UInt8(trimmed[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        return try? JSONDecoder().decode(ClaudeCredentials.self, from: bytes)
    }

    private static func isExpired(_ expiresAt: Double?) -> Bool {
        guard let expiresAt else { return false }
        return expiresAt - Date().timeIntervalSince1970 * 1_000 <= 5 * 60 * 1_000
    }

    private func requestUsage(accessToken: String) async throws -> HTTPResult {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("claude-code/2.1.69", forHTTPHeaderField: "User-Agent")
        return try await send(request)
    }

    private func refreshedToken(using refreshToken: String?) async throws -> String {
        guard let refreshToken, !refreshToken.isEmpty else {
            throw UsageError.notSignedIn("Claude Code 登录已过期，请运行 claude 重新登录")
        }
        var request = URLRequest(url: URL(string: "https://platform.claude.com/v1/oauth/token")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": "9d1c250a-e61b-44d9-88ed-5944d1962f5e",
            "scope": "user:profile user:inference user:sessions:claude_code user:mcp_servers user:file_upload"
        ])
        let response = try await send(request)
        guard (200..<300).contains(response.statusCode),
              let body = try? JSONSerialization.jsonObject(with: response.data) as? [String: Any],
              let token = body["access_token"] as? String,
              !token.isEmpty else {
            throw UsageError.notSignedIn("Claude Code 登录已过期，请运行 claude 重新登录")
        }
        return token
    }

    private func send(_ request: URLRequest) async throws -> HTTPResult {
        do {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.urlCache = nil
            configuration.httpCookieStorage = nil
            let (data, response) = try await URLSession(configuration: configuration).data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw UsageError.invalidResponse("Claude Code 返回了无效响应")
            }
            return HTTPResult(statusCode: http.statusCode, data: data)
        } catch let error as UsageError {
            throw error
        } catch {
            throw UsageError.requestFailed("无法连接 Claude Code：\(error.localizedDescription)")
        }
    }

    static func map(
        usageData: Data,
        oauth: ClaudeOAuth? = nil,
        now: Date = Date()
    ) throws -> ProviderSnapshot {
        guard let body = try? JSONSerialization.jsonObject(with: usageData) as? [String: Any] else {
            throw UsageError.invalidResponse("Claude Code 用量响应格式不正确")
        }
        var metrics: [UsageMetric] = []
        if let weekly = body.dictionary("seven_day"), let used = weekly.double("utilization") {
            metrics.append(UsageMetric(
                id: "weekly",
                title: "周额度",
                usedPercent: used,
                deadlineAt: DateParsing.date(from: weekly["resets_at"]),
                windowDuration: 7 * 24 * 60 * 60,
                group: .included
            ))
        }
        if let session = body.dictionary("five_hour"), let used = session.double("utilization") {
            metrics.append(UsageMetric(
                id: "session",
                title: "5 小时会话",
                usedPercent: used,
                deadlineAt: DateParsing.date(from: session["resets_at"]),
                windowDuration: 5 * 60 * 60,
                group: .included
            ))
        }
        guard !metrics.isEmpty else {
            throw UsageError.invalidResponse("Claude Code 未返回额度窗口")
        }

        var planName = oauth?.subscriptionType?
            .replacingOccurrences(of: "_", with: " ").capitalized
        if let tier = oauth?.rateLimitTier,
           let range = tier.range(of: #"\d+x"#, options: .regularExpression) {
            planName = [planName, String(tier[range])].compactMap { $0 }.joined(separator: " ")
        }
        return ProviderSnapshot(
            provider: .claude,
            planName: planName,
            metrics: metrics,
            fetchedAt: now,
            note: "来自 Claude Code 当前订阅额度",
            subscriptionCategory: .inferred(from: planName)
        )
    }
}
