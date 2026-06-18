import Foundation

enum BalanceService {
    private static let pythonTimeoutSeconds: TimeInterval = 15

    static func fetch(rule: BalanceRule, model: String, dbPath: String) async -> ModelBalance {
        do {
            let value: (amount: Double, currency: String)
            switch rule.kind {
            case .deepseek:
                value = try await fetchDeepSeek(rule: rule, dbPath: dbPath)
            case .python:
                value = try await runPython(rule: rule, model: model)
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

    private static func fetchDeepSeek(rule: BalanceRule, dbPath: String) async throws -> (Double, String) {
        let resolved = resolveCredentials(rule: rule, dbPath: dbPath)
        let apiKey = resolved.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
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
        let preferredCurrency = rule.currency.trimmingCharacters(in: .whitespacesAndNewlines)
        let info = infos.first { item in
            guard !preferredCurrency.isEmpty,
                  let currency = item["currency"] as? String else { return false }
            return currency.caseInsensitiveCompare(preferredCurrency) == .orderedSame
        } ?? infos.first

        guard let info else {
            throw BalanceExecutionError.api("响应缺少 balance_infos")
        }

        let amount = try numericField(info["total_balance"])
        let currency = (info["currency"] as? String) ?? (preferredCurrency.isEmpty ? "CNY" : preferredCurrency)
        return (amount, currency)
    }

    private static func resolveCredentials(rule: BalanceRule, dbPath: String) -> (baseURL: String, apiKey: String) {
        let explicitKey = rule.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !explicitKey.isEmpty {
            return (rule.baseURL, explicitKey)
        }

        guard let credentials = try? DeepSeekCredentialResolver(dbPath: dbPath).resolve() else {
            return (rule.baseURL, "")
        }
        return credentials
    }

    private static func runPython(rule: BalanceRule, model: String) async throws -> (Double, String) {
        let script = rule.script.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !script.isEmpty else { throw BalanceExecutionError.missingScript }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", "-c", script]
        process.environment = ProcessInfo.processInfo.environment.merging([
            "CCS_MODEL": model,
            "CCS_BALANCE_RULE_NAME": rule.name,
            "CCS_BALANCE_API_KEY": rule.apiKey,
            "CCS_BALANCE_CURRENCY": rule.currency
        ]) { _, new in new }

        let output = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = output
        process.standardError = errorPipe

        final class ResumeGate: @unchecked Sendable {
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

        let gate = ResumeGate()
        let deadline = DispatchTime.now() + pythonTimeoutSeconds

        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { proc in
                let stdout = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let stderr = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

                gate.resume {
                    if proc.terminationStatus != 0 {
                        continuation.resume(throwing: BalanceExecutionError.script(stderr.isEmpty ? "退出码 \(proc.terminationStatus)" : stderr))
                        return
                    }

                    do {
                        let amount = try parseAmount(stdout)
                        continuation.resume(returning: (amount, rule.currency.isEmpty ? "USD" : rule.currency))
                    } catch {
                        continuation.resume(throwing: error)
                    }
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
                    continuation.resume(throwing: BalanceExecutionError.script("执行超时（\(Int(pythonTimeoutSeconds)) 秒）"))
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
