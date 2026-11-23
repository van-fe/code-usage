import Darwin
import Foundation

actor DeepSeekProvider {
    private let http = ProviderHTTPClient()

    static var credentialsPath: String {
        let root = ProcessInfo.processInfo.environment["DSH_HOME"] ?? ProcessUtils.expandedHome("~/.dsh")
        return URL(fileURLWithPath: root).appendingPathComponent(".credentials.yaml").path
    }

    func fetch() async throws -> ProviderSnapshot {
        guard FileManager.default.fileExists(atPath: Self.credentialsPath) else {
            throw UsageError.notSignedIn("请在 DeepSeek Harness 登录或配置 DeepSeek API Key")
        }
        let attributes = try FileManager.default.attributesOfItem(atPath: Self.credentialsPath)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
              let permissions = attributes[.posixPermissions] as? NSNumber,
              permissions.intValue & 0o077 == 0,
              ((attributes[.size] as? NSNumber)?.intValue ?? Int.max) <= 1024 * 1024 else {
            throw UsageError.requestFailed("DeepSeek Harness 凭据文件权限或格式不安全")
        }
        let credentials = try Self.parse(document: String(contentsOfFile: Self.credentialsPath, encoding: .utf8))
        switch credentials {
        case .apiKey(let key):
            var request = URLRequest(url: URL(string: "https://api.deepseek.com/user/balance")!)
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            return try Self.mapAPI(data: await http.read(request, provider: .deepseek))
        case .accountToken(let token):
            var request = URLRequest(url: URL(string: "https://platform.deepseek.com/api/v0/users/get_user_summary")!)
            request.setValue(token, forHTTPHeaderField: "x-dsh-auth-token")
            let data = try await http.read(request, provider: .deepseek)
            return try Self.mapAccount(data: data)
        }
    }

    enum Credentials: Equatable { case apiKey(String), accountToken(String) }

    /// The Harness writes a versioned YAML mapping containing scalar keys and
    /// values. Accept that subset only; reject unsupported YAML instead of
    /// guessing credentials or executing an external parser.
    static func parse(document: String) throws -> Credentials {
        var path: [String] = []
        var values: [String: String] = [:]
        var paths = Set<String>()
        for line in document.components(separatedBy: .newlines) {
            let content = line.trimmingCharacters(in: .whitespaces)
            if content.isEmpty || content.hasPrefix("#") || content == "---" { continue }
            let indent = line.prefix(while: { $0 == " " }).count
            guard !line.contains("\t"), indent % 2 == 0, indent / 2 <= path.count,
                  let separator = content.firstIndex(of: ":") else { throw invalidCredentials }
            let key = try scalar(String(content[..<separator]))
            path = Array(path.prefix(indent / 2))
            path.append(key)
            let raw = String(content[content.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
            let name = path.joined(separator: ".")
            guard paths.insert(name).inserted else { throw invalidCredentials }
            if raw.isEmpty { continue }
            values[name] = try scalar(raw)
        }
        guard values["version"] == "1" else { throw invalidCredentials }
        let record = "records.deepseek-account-platform/default."
        if values[record + "kind"] == "grant" {
            guard values[record + "payload.version"] == "1",
                  values[record + "payload.issuer"] == "https://platform.deepseek.com",
                  let token = values[record + "payload.token"], validToken(token) else { throw invalidCredentials }
            return .accountToken(token)
        }
        if let key = values["refs.DEEPSEEK_API_KEY"], validToken(key) { return .apiKey(key) }
        throw UsageError.notSignedIn("请在 DeepSeek Harness 登录或配置 DeepSeek API Key")
    }

    static func mapAccount(data: Data, now: Date = Date()) throws -> ProviderSnapshot {
        guard let envelope = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let code = envelope["code"] as? Int else { throw invalidBalance }
        if code == 40003 { throw UsageError.notSignedIn("DeepSeek Harness 登录已过期，请重新登录") }
        guard code == 0, let business = envelope.dictionary("data"),
              let businessCode = business["biz_code"] as? Int else { throw invalidBalance }
        if businessCode == 40003 { throw UsageError.notSignedIn("DeepSeek Harness 登录已过期，请重新登录") }
        guard businessCode == 0, let detail = business.dictionary("biz_data"),
              let wallets = detail["normal_wallets"] as? [[String: Any]],
              let bonuses = detail["bonus_wallets"] as? [[String: Any]] else { throw invalidBalance }
        var metrics: [UsageMetric] = []
        for (id, title, items) in [("topped_up", "充值余额", wallets), ("granted", "赠金余额", bonuses)] {
            var seen = Set<String>()
            for item in items {
                guard let currency = item["currency"] as? String, ["CNY", "USD"].contains(currency),
                      seen.insert(currency).inserted, let raw = item["balance"] as? String,
                      let balance = Double(raw), balance.isFinite else { throw invalidBalance }
                metrics.append(UsageMetric(id: "\(id)_\(currency)", title: title, usedPercent: 0, deadlineAt: nil,
                                           value: .quantity(used: nil, limit: nil, remaining: balance, unit: currency), showsProgress: false))
            }
        }
        guard !metrics.isEmpty else { throw invalidBalance }
        return ProviderSnapshot(provider: .deepseek, planName: "Harness", metrics: metrics, fetchedAt: now, note: nil)
    }

    static func mapAPI(data: Data, now: Date = Date()) throws -> ProviderSnapshot {
        do {
                let response = try JSONDecoder().decode(DeepSeekBalance.self, from: data)
                guard !response.balance_infos.isEmpty else { throw UsageError.invalidResponse("DeepSeek 未返回余额") }
                var currencies = Set<String>()
                let metrics = try response.balance_infos.flatMap { balance -> [UsageMetric] in
                    guard ["CNY", "USD"].contains(balance.currency), currencies.insert(balance.currency).inserted else {
                        throw UsageError.invalidResponse("DeepSeek 余额币种无效")
                    }
                    return try [("balance", "可用余额", balance.total_balance),
                                ("granted", "赠金余额", balance.granted_balance),
                                ("topped_up", "充值余额", balance.topped_up_balance)].map { id, title, raw in
                        guard let value = Double(raw), value.isFinite else { throw UsageError.invalidResponse("DeepSeek 余额数值无效") }
                        return UsageMetric(id: "\(id)_\(balance.currency)", title: title, usedPercent: 0,
                                           deadlineAt: nil, value: .quantity(used: nil, limit: nil, remaining: value, unit: balance.currency), showsProgress: false)
                    }
                }
                return ProviderSnapshot(provider: .deepseek, planName: "API", metrics: metrics, fetchedAt: now,
                                        note: response.is_available ? nil : "DeepSeek 当前余额不足以调用 API")
        } catch let error as UsageError { throw error }
        catch { throw invalidBalance }
    }

    private struct DeepSeekBalance: Decodable {
        let is_available: Bool
        let balance_infos: [Balance]
        struct Balance: Decodable {
            let currency: String
            let total_balance: String
            let granted_balance: String
            let topped_up_balance: String
        }
    }

    private static func scalar(_ value: String) throws -> String {
        if value.hasPrefix("\"") {
            guard let data = value.data(using: .utf8), let decoded = try? JSONDecoder().decode(String.self, from: data) else { throw invalidCredentials }
            return decoded
        }
        if value.hasPrefix("'") {
            guard value.count >= 2, value.hasSuffix("'") else { throw invalidCredentials }
            return String(value.dropFirst().dropLast()).replacingOccurrences(of: "''", with: "'")
        }
        guard !value.isEmpty, !"&*!|>{[".contains(value.first!), !value.contains(" #") else { throw invalidCredentials }
        return value
    }
    private static func validToken(_ token: String) -> Bool {
        !token.isEmpty && token != "null" && token != "~" && token.unicodeScalars.allSatisfy { $0.value > 32 && $0.value < 127 }
    }
    private static var invalidCredentials: UsageError { .invalidResponse("DeepSeek Harness 凭据格式不受支持") }
    private static var invalidBalance: UsageError { .invalidResponse("DeepSeek Harness 余额数据格式无效") }
}
