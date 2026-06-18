import Foundation

enum BalanceService {
    private static let pythonTimeoutSeconds: TimeInterval = 15
    private static let pythonValidationTimeoutSeconds: TimeInterval = 5

    static func fetch(rule: BalanceRule, model: String, dbPath: String) async -> ModelBalance {
        do {
            let value: (amount: Double, currency: String)
            switch rule.kind {
            case .deepseek:
                value = try await fetchDeepSeek(rule: rule, dbPath: dbPath)
            case .python:
                value = try await runPython(rule: rule)
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
}
