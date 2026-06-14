import Foundation

func formatTokens(_ n: Int) -> String {
    let v = Double(n)
    if v >= 1_000_000 { return String(format: "%.1fM", v / 1_000_000) }
    if v >= 1_000 { return String(format: "%.1fK", v / 1_000) }
    return "\(n)"
}

func formatCost(_ usd: Double) -> String {
    return String(format: "$%.2f", usd)
}

func formatPercent(_ ratio: Double) -> String {
    return "\(Int((ratio * 100).rounded()))%"
}
