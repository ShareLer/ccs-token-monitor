import Foundation

func formatTokens(_ n: Int) -> String {
    let v = Double(n)
    if v >= 1_000_000 { return String(format: "%.1fM", v / 1_000_000) }
    if v >= 1_000 { return String(format: "%.1fK", v / 1_000) }
    return "\(n)"
}

func formatMenuBarTokens(_ n: Int) -> String {
    let v = Double(n)
    if v >= 1_000_000 { return "\(Int((v / 1_000_000).rounded()))M" }
    if v >= 1_000 { return "\(Int((v / 1_000).rounded()))k" }
    return "\(n)"
}

func formatCost(_ usd: Double) -> String {
    return String(format: "$%.2f", usd)
}

func formatBalance(_ amount: Double, currency: String) -> String {
    let symbol: String
    switch currency.uppercased() {
    case "USD": symbol = "$"
    case "CNY", "RMB": symbol = "¥"
    default: symbol = "\(currency.uppercased()) "
    }
    return "\(symbol)\(String(format: "%.2f", amount))"
}

func formatPercent(_ ratio: Double) -> String {
    return "\(Int((ratio * 100).rounded()))%"
}

/// 缓存率专用：保留 1 位小数，避免 99.92% 被四舍五入显示成误导性的 100%。
func formatCacheRate(_ ratio: Double) -> String {
    return String(format: "%.1f%%", ratio * 100)
}
