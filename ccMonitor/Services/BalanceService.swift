import Foundation
import JavaScriptCore

enum BalanceService {
    private static let pythonTimeoutSeconds: TimeInterval = 15
    private static let pythonValidationTimeoutSeconds: TimeInterval = 5
    private static let javascriptTimeoutSeconds: TimeInterval = 15

    static func fetch(rule: BalanceRule, model: String, dbPath: String) async -> ModelBalance {
        do {
            let value: (amount: Double, currency: String)
            switch rule.kind {
            case .deepseek:
                value = try await fetchDeepSeek(rule: rule, dbPath: dbPath)
            case .python:
                value = try await runPython(rule: rule)
            case .javascript:
                value = try await runJavaScript(rule: rule)
            }
            return ModelBalance(state: .value(value.amount, currency: value.currency),
                                updatedAt: Date())
        } catch let error as BalanceExecutionError {
            return ModelBalance(state: .failed(error.localizedDescription),
                                updatedAt: Date())
        } catch {
            return ModelBalance(state: .failed(error.localizedDescription),
                                updatedAt: Date())
        }
    }

    static func parseBalanceValue(_ output: [String: Any]) throws -> (Double, String) {
        let amountValue = output["remaining"] ?? output["amount"] ?? output["balance"]
        guard let amount = try optionalNumericField(amountValue) else {
            throw BalanceExecutionError.invalidAmount(String(describing: output))
        }

        let currency = (output["unit"] as? String) ?? (output["currency"] as? String) ?? "CNY"
        return (amount, currency)
    }

    static func parseAmount(_ output: String) throws -> Double {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if let value = Double(trimmed) {
            return value
        }

        if let data = trimmed.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let amount = json["amount"] ?? json["balance"] ?? json["remaining"] {
            if let value = amount as? NSNumber { return value.doubleValue }
            if let value = amount as? Double { return value }
            if let value = amount as? Int { return Double(value) }
            if let value = amount as? String, let parsed = Double(value.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return parsed
            }
        }

        throw BalanceExecutionError.invalidAmount(trimmed)
    }

    static func validatePythonSyntax(_ script: String) async throws {
        let script = script.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !script.isEmpty else { throw BalanceExecutionError.missingScript }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ccMonitor-python-check-\(UUID().uuidString)", isDirectory: true)
        let scriptURL = tempDir.appendingPathComponent("balance_script.py")

        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        } catch {
            throw BalanceExecutionError.script(error.localizedDescription)
        }
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let result = try await runProcess(
            arguments: ["python3", "-m", "py_compile", scriptURL.path],
            timeout: pythonValidationTimeoutSeconds
        )
        guard result.status == 0 else {
            let message = (result.stderr.isEmpty ? "语法检查失败" : result.stderr)
                .replacingOccurrences(of: scriptURL.path, with: "Python 脚本")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw BalanceExecutionError.script(message)
        }
    }

    static func validateJavaScriptTemplate(_ script: String, baseUrl: String = "https://example.com", apiKey: String = "test") throws {
        let compiled = try JavaScriptBalanceTemplate.compile(script: script, baseUrl: baseUrl, apiKey: apiKey)
        let config = try compiled.request()
        try validateJavaScriptRequest(config, baseUrl: baseUrl)
    }

    private static func fetchDeepSeek(rule: BalanceRule, dbPath: String) async throws -> (Double, String) {
        let apiKey = resolveAPIKey(rule: rule, dbPath: dbPath).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else { throw BalanceExecutionError.missingAPIKey }

        guard let url = URL(string: "https://api.deepseek.com/user/balance") else {
            throw BalanceExecutionError.api("DeepSeek URL 无效")
        }

        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw BalanceExecutionError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw BalanceExecutionError.api("响应格式异常")
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw BalanceExecutionError.api("HTTP \(http.statusCode) \(body)")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw BalanceExecutionError.api("无法解析响应")
        }

        let infos = json["balance_infos"] as? [[String: Any]] ?? []
        let preferredCurrency = "CNY"
        let info = infos.first { item in
            guard let currency = item["currency"] as? String else { return false }
            return currency.caseInsensitiveCompare(preferredCurrency) == .orderedSame
        } ?? infos.first

        guard let info else {
            throw BalanceExecutionError.api("响应缺少 balance_infos")
        }

        let amount = try numericField(info["total_balance"])
        let currency = (info["currency"] as? String) ?? preferredCurrency
        return (amount, currency)
    }

    private static func resolveAPIKey(rule: BalanceRule, dbPath: String) -> String {
        let explicitKey = rule.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !explicitKey.isEmpty {
            return explicitKey
        }

        return (try? DeepSeekCredentialResolver(dbPath: dbPath).resolve()) ?? ""
    }

    private static func runPython(rule: BalanceRule) async throws -> (Double, String) {
        let script = rule.script.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !script.isEmpty else { throw BalanceExecutionError.missingScript }

        let result = try await runProcess(
            arguments: ["python3", "-c", script],
            environment: ["CCS_BALANCE_RULE_NAME": rule.name],
            timeout: pythonTimeoutSeconds
        )

        guard result.status == 0 else {
            throw BalanceExecutionError.script(result.stderr.isEmpty ? "退出码 \(result.status)" : result.stderr)
        }

        let amount = try parseAmount(result.stdout)
        return (amount, "CNY")
    }

    private static func runJavaScript(rule: BalanceRule) async throws -> (Double, String) {
        let script = rule.script.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !script.isEmpty else { throw BalanceExecutionError.missingScript }

        let apiKey = rule.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else { throw BalanceExecutionError.missingAPIKey }

        let baseUrl = rule.baseUrl.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !baseUrl.isEmpty else { throw BalanceExecutionError.missingBaseURL }

        let template = try JavaScriptBalanceTemplate.compile(script: script, baseUrl: baseUrl, apiKey: apiKey)
        let config = try template.request()
        let response = try await sendJavaScriptRequest(config, baseUrl: baseUrl)
        let extracted = try template.extract(response: response)
        return try parseBalanceValue(extracted)
    }

    private struct ProcessResult {
        let status: Int32
        let stdout: String
        let stderr: String
    }

    private final class ResumeGate: @unchecked Sendable {
        private let lock = NSLock()
        private var didResume = false

        func resume(_ body: () -> Void) {
            lock.lock()
            defer { lock.unlock() }
            guard !didResume else { return }
            didResume = true
            body()
        }
    }

    private static func runProcess(arguments: [String],
                                   environment: [String: String] = [:],
                                   timeout: TimeInterval) async throws -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = arguments
        if !environment.isEmpty {
            process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        }

        let output = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = output
        process.standardError = errorPipe

        let gate = ResumeGate()
        let deadline = DispatchTime.now() + timeout

        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { proc in
                let stdout = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let stderr = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

                gate.resume {
                    continuation.resume(returning: ProcessResult(status: proc.terminationStatus,
                                                                 stdout: stdout,
                                                                 stderr: stderr))
                }
            }

            do {
                try process.run()
            } catch {
                gate.resume {
                    continuation.resume(throwing: BalanceExecutionError.script(error.localizedDescription))
                }
                return
            }

            DispatchQueue.global(qos: .utility).asyncAfter(deadline: deadline) {
                guard process.isRunning else { return }
                process.terminate()
                gate.resume {
                    continuation.resume(throwing: BalanceExecutionError.script("执行超时（\(Int(timeout)) 秒）"))
                }
            }
        }
    }

    private static func numericField(_ value: Any?) throws -> Double {
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? String, let parsed = Double(value) { return parsed }
        throw BalanceExecutionError.api("金额字段格式异常")
    }

    private static func optionalNumericField(_ value: Any?) throws -> Double? {
        guard let value else { return nil }
        if value is NSNull { return nil }
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? String, let parsed = Double(value.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return parsed
        }
        return nil
    }

    private static func sendJavaScriptRequest(_ config: JavaScriptBalanceTemplate.RequestConfig, baseUrl: String) async throws -> [String: Any] {
        try validateJavaScriptRequest(config, baseUrl: baseUrl)

        var request = URLRequest(url: URL(string: config.url)!, timeoutInterval: javascriptTimeoutSeconds)
        request.httpMethod = config.method
        for (key, value) in config.headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        if let body = config.body {
            request.httpBody = body.data(using: .utf8)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw BalanceExecutionError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw BalanceExecutionError.api("响应格式异常")
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw BalanceExecutionError.api("HTTP \(http.statusCode) \(body)")
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw BalanceExecutionError.api("无法解析 JS 查询响应")
        }
        return json
    }

    private static func validateJavaScriptRequest(_ config: JavaScriptBalanceTemplate.RequestConfig, baseUrl: String) throws {
        guard let url = URL(string: config.url) else {
            throw BalanceExecutionError.api("JS 请求 URL 无效")
        }
        guard url.scheme == "https" || url.host == "localhost" || url.host == "127.0.0.1" else {
            throw BalanceExecutionError.api("JS 请求 URL 必须使用 HTTPS")
        }
        if let base = URL(string: baseUrl),
           url.host != base.host || url.port != base.port {
            throw BalanceExecutionError.api("JS 请求 URL 必须与 Base URL 同源")
        }
    }
}

private final class JavaScriptBalanceTemplate {
    struct RequestConfig {
        let url: String
        let method: String
        let headers: [String: String]
        let body: String?
    }

    private let context: JSContext
    private let config: JSValue

    private init(context: JSContext, config: JSValue) {
        self.context = context
        self.config = config
    }

    static func compile(script: String, baseUrl: String, apiKey: String) throws -> JavaScriptBalanceTemplate {
        let script = script.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !script.isEmpty else { throw BalanceExecutionError.missingScript }

        let context = JSContext()!
        var capturedException: JSValue?
        context.exceptionHandler = { _, exception in
            capturedException = exception
        }

        let preparedScript = script
            .replacingOccurrences(of: "{{baseUrl}}", with: baseUrl)
            .replacingOccurrences(of: "{{apiKey}}", with: apiKey)

        guard let config = context.evaluateScript(preparedScript), capturedException == nil else {
            throw BalanceExecutionError.script(capturedException?.toString() ?? "JS 模板解析失败")
        }
        guard config.hasProperty("request"), config.hasProperty("extractor") else {
            throw BalanceExecutionError.script("JS 模板必须包含 request 和 extractor")
        }
        guard !config.forProperty("extractor").isUndefined else {
            throw BalanceExecutionError.script("JS 模板缺少 extractor")
        }

        return JavaScriptBalanceTemplate(context: context, config: config)
    }

    func request() throws -> RequestConfig {
        guard let request = config.forProperty("request"), !request.isUndefined else {
            throw BalanceExecutionError.script("JS 模板缺少 request")
        }
        guard let url = request.forProperty("url")?.toString(), !url.isEmpty else {
            throw BalanceExecutionError.script("request.url 不能为空")
        }
        let method = request.forProperty("method")?.toString()?.uppercased() ?? "GET"
        guard ["GET", "POST", "PUT", "PATCH", "DELETE"].contains(method) else {
            throw BalanceExecutionError.script("不支持的请求方法：\(method)")
        }

        var headers: [String: String] = [:]
        if let headerObject = request.forProperty("headers"), !headerObject.isUndefined, !headerObject.isNull {
            guard let headerDict = headerObject.toDictionary() as? [String: Any] else {
                throw BalanceExecutionError.script("request.headers 必须是对象")
            }
            headers = headerDict.reduce(into: [String: String]()) { result, item in
                result[item.key] = String(describing: item.value)
            }
        }

        let bodyValue = request.forProperty("body")
        let body = bodyValue?.isUndefined == false && bodyValue?.isNull == false ? bodyValue?.toString() : nil
        return RequestConfig(url: url, method: method, headers: headers, body: body)
    }

    func extract(response: [String: Any]) throws -> [String: Any] {
        guard let extractor = config.forProperty("extractor"), !extractor.isUndefined else {
            throw BalanceExecutionError.script("JS 模板缺少 extractor")
        }
        let responseValue = JSValue(object: response, in: context)
        guard let result = extractor.call(withArguments: [responseValue as Any]), context.exception == nil else {
            throw BalanceExecutionError.script(context.exception?.toString() ?? "extractor 执行失败")
        }
        guard let dict = result.toDictionary() as? [String: Any] else {
            throw BalanceExecutionError.script("extractor 必须返回对象")
        }
        return dict
    }
}
