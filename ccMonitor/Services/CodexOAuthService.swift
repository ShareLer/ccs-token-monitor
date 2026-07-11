import AppKit
import CryptoKit
import Foundation
import Network
import Security

struct CodexOAuthCredentials: Codable, Equatable, Sendable {
    var idToken: String
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Int64?
    var email: String
    var accountId: String?
    var planType: String?

    var accountConfig: CodexAccountConfig {
        CodexAccountConfig(email: email, accountId: accountId, planType: planType)
    }
}

enum CodexOAuthService {
    private static let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"
    private static let authorizeURL = URL(string: "https://auth.openai.com/oauth/authorize")!
    private static let tokenURL = URL(string: "https://auth.openai.com/oauth/token")!
    private static let callbackPort: UInt16 = 1455
    private static let scopes = "openid profile email offline_access"
    private static let originator = "codex_vscode"
    private static let credentialCoordinator = CredentialCoordinator()

    static func storedAccount() -> CodexAccountConfig? {
        try? CodexCredentialStore.load()?.accountConfig
    }

    static func login() async throws -> CodexAccountConfig {
        let verifier = try randomBase64URL(byteCount: 32)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncodedString()
        let state = try randomBase64URL(byteCount: 24)
        let redirectURI = "http://localhost:\(callbackPort)/auth/callback"

        var components = URLComponents(url: authorizeURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: scopes),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "id_token_add_organizations", value: "true"),
            URLQueryItem(name: "codex_cli_simplified_flow", value: "true"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "originator", value: originator),
        ]
        guard let url = components?.url else {
            throw TokenPlanError.authentication("无法构建 Codex 登录地址")
        }

        let callbackServer = CodexOAuthCallbackServer(port: callbackPort)
        let code = try await withTaskCancellationHandler {
            try await callbackServer.authorize(url: url, expectedState: state)
        } onCancel: {
            callbackServer.cancel()
        }
        try Task.checkCancellation()
        let response = try await requestToken([
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI,
            "client_id": clientID,
            "code_verifier": verifier,
        ])
        let credentials = try credentials(from: response, previous: nil)
        try Task.checkCancellation()
        try await credentialCoordinator.save(credentials)
        return credentials.accountConfig
    }

    static func validCredentials(forceRefresh: Bool = false) async throws -> CodexOAuthCredentials {
        try await credentialCoordinator.validCredentials(forceRefresh: forceRefresh)
    }

    private static func requestToken(_ parameters: [String: String]) async throws -> OAuthTokenResponse {
        var request = URLRequest(url: tokenURL, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = formBody(parameters)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            if error is CancellationError || (error as? URLError)?.code == .cancelled {
                throw CancellationError()
            }
            throw TokenPlanError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw TokenPlanError.authentication("Token 响应格式异常")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw TokenPlanError.authentication("Token 请求失败 HTTP \(http.statusCode)")
        }
        do {
            return try JSONDecoder().decode(OAuthTokenResponse.self, from: data)
        } catch {
            throw TokenPlanError.parse("无法解析 Codex Token 响应")
        }
    }

    private static func credentials(from response: OAuthTokenResponse,
                                    previous: CodexOAuthCredentials?) throws -> CodexOAuthCredentials {
        guard let accessToken = nonEmpty(response.accessToken) ?? previous?.accessToken else {
            throw TokenPlanError.authentication("Token 响应缺少 access_token")
        }
        guard let idToken = nonEmpty(response.idToken) ?? previous?.idToken else {
            throw TokenPlanError.authentication("Token 响应缺少 id_token")
        }

        let accessClaims = decodeJWT(accessToken)
        let idClaims = decodeJWT(idToken)
        let email = nonEmpty(idClaims?.email)
            ?? nonEmpty(accessClaims?.email)
            ?? previous?.email
            ?? ""
        let accountId = nonEmpty(accessClaims?.auth?.chatgptAccountId)
            ?? nonEmpty(accessClaims?.auth?.accountId)
            ?? nonEmpty(idClaims?.auth?.chatgptAccountId)
            ?? nonEmpty(idClaims?.auth?.accountId)
            ?? previous?.accountId
        let planType = nonEmpty(accessClaims?.auth?.chatgptPlanType)
            ?? nonEmpty(idClaims?.auth?.chatgptPlanType)
            ?? previous?.planType

        return CodexOAuthCredentials(
            idToken: idToken,
            accessToken: accessToken,
            refreshToken: nonEmpty(response.refreshToken) ?? previous?.refreshToken,
            expiresAt: accessClaims?.exp ?? previous?.expiresAt,
            email: email,
            accountId: accountId,
            planType: planType
        )
    }

    private static func decodeJWT(_ token: String) -> JWTClaims? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2,
              let data = Data(base64URLEncoded: String(parts[1])) else {
            return nil
        }
        return try? JSONDecoder().decode(JWTClaims.self, from: data)
    }

    private static func formBody(_ parameters: [String: String]) -> Data {
        parameters
            .sorted { $0.key < $1.key }
            .map { "\(formEncode($0.key))=\(formEncode($0.value))" }
            .joined(separator: "&")
            .data(using: .utf8) ?? Data()
    }

    private static func formEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private static func randomBase64URL(byteCount: Int) throws -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = bytes.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, buffer.count, buffer.baseAddress!)
        }
        guard status == errSecSuccess else {
            throw TokenPlanError.authentication("无法生成安全的 Codex 登录参数")
        }
        return Data(bytes).base64URLEncodedString()
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }

    private actor CredentialCoordinator {
        func save(_ credentials: CodexOAuthCredentials) throws {
            try Task.checkCancellation()
            revision += 1
            refresh?.task.cancel()
            refresh = nil
            try CodexCredentialStore.save(credentials)
        }

        func validCredentials(forceRefresh: Bool) async throws -> CodexOAuthCredentials {
            guard let stored = try CodexCredentialStore.load() else {
                throw TokenPlanError.authentication("Codex 尚未登录")
            }
            let now = Int64(Date().timeIntervalSince1970)
            if !forceRefresh, stored.expiresAt.map({ $0 > now + 300 }) != false {
                return stored
            }
            guard let refreshToken = stored.refreshToken?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !refreshToken.isEmpty else {
                throw TokenPlanError.authentication("Codex 登录已过期，请重新登录")
            }

            if let refresh {
                return try await refresh.task.value
            }

            let refreshID = UUID()
            let baseRevision = revision
            let task = Task {
                let response = try await CodexOAuthService.requestToken([
                    "grant_type": "refresh_token",
                    "refresh_token": refreshToken,
                    "client_id": CodexOAuthService.clientID,
                ])
                return try CodexOAuthService.credentials(from: response, previous: stored)
            }
            refresh = (refreshID, task)

            do {
                let refreshed = try await task.value
                guard revision == baseRevision else {
                    throw CancellationError()
                }
                if refresh?.id == refreshID {
                    try CodexCredentialStore.save(refreshed)
                    refresh = nil
                    return refreshed
                }
                return try CodexCredentialStore.load() ?? refreshed
            } catch {
                if refresh?.id == refreshID {
                    refresh = nil
                }
                throw error
            }
        }

        private var revision = 0
        private var refresh: (id: UUID, task: Task<CodexOAuthCredentials, Error>)?
    }
}

private struct OAuthTokenResponse: Decodable {
    var accessToken: String?
    var idToken: String?
    var refreshToken: String?

    private enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case idToken = "id_token"
        case refreshToken = "refresh_token"
    }
}

private struct JWTClaims: Decodable {
    var email: String?
    var exp: Int64?
    var auth: JWTAuthClaims?

    private enum CodingKeys: String, CodingKey {
        case email
        case exp
        case auth = "https://api.openai.com/auth"
    }
}

private struct JWTAuthClaims: Decodable {
    var chatgptAccountId: String?
    var accountId: String?
    var chatgptPlanType: String?

    private enum CodingKeys: String, CodingKey {
        case chatgptAccountId = "chatgpt_account_id"
        case accountId = "account_id"
        case chatgptPlanType = "chatgpt_plan_type"
    }
}

private enum CodexCredentialStore {
    private static let service = "com.ccmonitor.app.token-plan"
    private static let account = "codex.oauth"

    static func save(_ credentials: CodexOAuthCredentials) throws {
        let data = try JSONEncoder().encode(credentials)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw TokenPlanError.authentication("无法保存 Codex 登录信息（\(updateStatus)）")
        }

        var item = query
        attributes.forEach { item[$0.key] = $0.value }
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw TokenPlanError.authentication("无法保存 Codex 登录信息（\(addStatus)）")
        }
    }

    static func load() throws -> CodexOAuthCredentials? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess, let data = result as? Data else {
            throw TokenPlanError.authentication("无法读取 Codex 登录信息（\(status)）")
        }
        do {
            return try JSONDecoder().decode(CodexOAuthCredentials.self, from: data)
        } catch {
            throw TokenPlanError.parse("Codex 登录信息已损坏，请重新登录")
        }
    }
}

private final class CodexOAuthCallbackServer: @unchecked Sendable {
    private let port: UInt16
    private let queue = DispatchQueue(label: "com.ccmonitor.codex-oauth-callback")
    private let lock = NSLock()
    private let log = AppLog("CodexOAuth")
    private var listener: NWListener?
    private var continuation: CheckedContinuation<String, Error>?
    private var expectedState = ""
    private var didOpenBrowser = false
    private var finished = false

    init(port: UInt16) {
        self.port = port
    }

    func authorize(url: URL, expectedState: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            guard !finished else {
                lock.unlock()
                continuation.resume(throwing: CancellationError())
                return
            }
            self.continuation = continuation
            self.expectedState = expectedState
            lock.unlock()

            do {
                let listener = try NWListener(
                    using: .tcp,
                    on: NWEndpoint.Port(rawValue: port)!
                )
                lock.lock()
                guard !finished else {
                    lock.unlock()
                    listener.cancel()
                    return
                }
                self.listener = listener
                lock.unlock()
                listener.stateUpdateHandler = { [weak self] state in
                    self?.handle(state: state, authorizationURL: url)
                }
                listener.newConnectionHandler = { [weak self] connection in
                    guard let self else { return }
                    guard self.isLoopback(connection.endpoint) else {
                        self.log.warning("rejected non-loopback OAuth connection endpoint=\(connection.endpoint)")
                        connection.cancel()
                        return
                    }
                    self.log.info("accepted OAuth callback connection endpoint=\(connection.endpoint)")
                    connection.start(queue: self.queue)
                    self.receiveRequest(on: connection, accumulated: Data())
                }
                listener.start(queue: queue)
            } catch {
                finish(.failure(TokenPlanError.authentication("无法启动 Codex 登录回调：\(error.localizedDescription)")))
            }

            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 300_000_000_000)
                self?.finish(.failure(TokenPlanError.authentication("Codex 登录超时")))
            }
        }
    }

    func cancel() {
        finish(.failure(CancellationError()))
    }

    private func handle(state: NWListener.State, authorizationURL: URL) {
        switch state {
        case .ready:
            log.info("OAuth callback listener ready port=\(port)")
            lock.lock()
            let shouldOpen = !didOpenBrowser && !finished
            didOpenBrowser = true
            lock.unlock()
            guard shouldOpen else { return }
            Task { @MainActor [weak self] in
                guard NSWorkspace.shared.open(authorizationURL) else {
                    self?.finish(.failure(TokenPlanError.authentication("无法打开 Codex 登录页面")))
                    return
                }
            }
        case .failed(let error):
            log.error("OAuth callback listener failed: \(error.localizedDescription)")
            finish(.failure(TokenPlanError.authentication("Codex 登录回调失败：\(error.localizedDescription)")))
        case .cancelled:
            log.info("OAuth callback listener cancelled")
        default:
            break
        }
    }

    private func receiveRequest(on connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var requestData = accumulated
            if let data {
                requestData.append(data)
            }
            if requestData.range(of: Data("\r\n\r\n".utf8)) != nil || isComplete {
                self.handle(requestData: requestData, connection: connection)
                return
            }
            if requestData.count >= 32_768 {
                self.respond(connection, success: false) {
                    self.finish(.failure(TokenPlanError.authentication("Codex 登录回调数据过大")))
                }
                return
            }
            if let error {
                self.finish(.failure(TokenPlanError.network(error.localizedDescription)))
                return
            }
            self.receiveRequest(on: connection, accumulated: requestData)
        }
    }

    private func handle(requestData: Data, connection: NWConnection) {
        guard let request = String(data: requestData, encoding: .utf8),
              let requestLine = request.components(separatedBy: "\r\n").first,
              requestLine.hasPrefix("GET "),
              let target = requestLine.split(separator: " ").dropFirst().first,
              let components = URLComponents(string: "http://localhost\(target)") else {
            respond(connection, success: false)
            return
        }
        guard components.path == "/auth/callback" else {
            log.warning("ignored OAuth callback path=\(components.path)")
            respond(connection, success: false)
            return
        }

        let queryItems = components.queryItems ?? []
        if let error = queryItems.first(where: { $0.name == "error" })?.value {
            respond(connection, success: false) {
                self.finish(.failure(TokenPlanError.authentication("Codex 登录被拒绝：\(error)")))
            }
            return
        }
        let returnedState = queryItems.first(where: { $0.name == "state" })?.value
        let code = queryItems.first(where: { $0.name == "code" })?.value
        guard returnedState == expectedState, let code, !code.isEmpty else {
            log.warning("rejected OAuth callback due to state/code validation")
            respond(connection, success: false)
            return
        }
        log.info("OAuth callback validated")
        respond(connection, success: true) {
            self.finish(.success(code))
        }
    }

    private func isLoopback(_ endpoint: NWEndpoint) -> Bool {
        guard case .hostPort(let host, _) = endpoint else {
            return false
        }
        let value = String(describing: host).lowercased()
        return value == "localhost"
            || value == "127.0.0.1"
            || value == "::1"
            || value.hasPrefix("::1%")
            || value.hasPrefix("::ffff:127.")
    }

    private func respond(_ connection: NWConnection,
                         success: Bool,
                         completion: (@Sendable () -> Void)? = nil) {
        let title = success ? "Codex 授权完成" : "Codex 登录失败"
        let message = success
            ? "正在返回 ccMonitor。如果此页面没有自动关闭，可以手动关闭。"
            : "请返回 ccMonitor 重试。"
        let closeScript = success
            ? "<script>window.setTimeout(function(){window.close();},800);</script>"
            : ""
        let html = """
        <!doctype html>
        <html lang="zh-CN">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width,initial-scale=1">
        <title>\(title)</title>
        <style>
        body{margin:0;background:#f5f5f7;color:#1d1d1f;font:16px -apple-system,BlinkMacSystemFont,sans-serif}
        main{max-width:480px;margin:18vh auto 0;padding:40px;text-align:center}
        h1{font-size:28px;margin:0 0 12px}
        p{color:#6e6e73;line-height:1.6;margin:0}
        </style>
        \(closeScript)
        </head>
        <body><main><h1>\(title)</h1><p>\(message)</p></main></body>
        </html>
        """
        let body = Data(html.utf8)
        let headers = """
        HTTP/1.1 \(success ? "200 OK" : "400 Bad Request")\r
        Content-Type: text/html; charset=utf-8\r
        Content-Length: \(body.count)\r
        Cache-Control: no-store\r
        Connection: close\r
        \r
        """
        var response = Data(headers.utf8)
        response.append(body)
        connection.send(content: response, completion: .contentProcessed { [weak self] error in
            if let error {
                self?.log.warning("OAuth callback response failed: \(error.localizedDescription)")
            }
            connection.cancel()
            completion?()
        })
    }

    private func finish(_ result: Result<String, Error>) {
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        finished = true
        let continuation = self.continuation
        self.continuation = nil
        let listener = self.listener
        self.listener = nil
        lock.unlock()

        listener?.cancel()
        continuation?.resume(with: result)
    }
}

private extension Data {
    init?(base64URLEncoded value: String) {
        var base64 = value.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder != 0 {
            base64.append(String(repeating: "=", count: 4 - remainder))
        }
        self.init(base64Encoded: base64)
    }

    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
