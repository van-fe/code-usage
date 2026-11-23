import Foundation

/// Fixed first-party, read-only requests. Never surface response bodies or
/// forward credentials to a redirect target.
actor ProviderHTTPClient {
    private let session: URLSession

    init(session: URLSession? = nil) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 45
        self.session = session ?? URLSession(configuration: configuration, delegate: NoProviderRedirects(), delegateQueue: nil)
    }

    func read(_ request: URLRequest, provider: ProviderKind) async throws -> Data {
        try Self.validateDestination(request, provider: provider)
        let data: Data
        let response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch { throw UsageError.requestFailed("用量网络请求失败，请稍后重试") }
        guard let http = response as? HTTPURLResponse else { throw UsageError.invalidResponse("用量接口返回无效响应") }
        try Self.validateStatus(http.statusCode, provider: provider)
        guard data.count <= 8 * 1024 * 1024 else { throw UsageError.invalidResponse("用量接口响应过大") }
        return data
    }

    static func validateDestination(_ request: URLRequest, provider: ProviderKind) throws {
        guard let url = request.url, url.scheme == "https", url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil, url.port == nil || url.port == 443 else {
            throw UsageError.invalidResponse("用量接口地址不受支持")
        }
        let allowed: Bool
        switch provider {
        case .devin:
            allowed = url.host == "server.codeium.com" && url.path == "/exa.seat_management_pb.SeatManagementService/GetUserStatus" && request.httpMethod == "POST"
        case .deepseek:
            allowed = request.httpMethod == "GET" &&
                ((url.host == "api.deepseek.com" && url.path == "/user/balance") ||
                 (url.host == "platform.deepseek.com" && url.path == "/api/v0/users/get_user_summary"))
        default: allowed = false
        }
        guard allowed else { throw UsageError.invalidResponse("用量接口地址不受支持") }
    }

    static func validateStatus(_ status: Int, provider: ProviderKind) throws {
        switch status {
        case 200: return
        case 401: throw UsageError.notSignedIn("客户端登录已过期，请重新登录后刷新")
        case 403: throw UsageError.requestFailed("当前账号没有查询用量的权限")
        case 429: throw UsageError.requestFailed("用量请求过于频繁，请稍后重试")
        default: throw UsageError.requestFailed("\(provider.title) HTTP \(status)")
        }
    }
}

private final class NoProviderRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
