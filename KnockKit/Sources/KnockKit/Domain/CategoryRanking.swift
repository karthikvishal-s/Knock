import Foundation

/// Orders categories so the likeliest pick comes first in the quick-entry grid and intent prompts.
public enum CategoryRanking {
    /// Frequency (log-damped) plus a boost for anything used in the last 48 hours plus a recency tail.
    public static func score(usageCount: Int, lastUsedAt: Date?, now: Date) -> Double {
        let frequency = 3 * log2(1 + Double(max(usageCount, 0)))
        guard let lastUsedAt else { return frequency }
        let days = max(now.timeIntervalSince(lastUsedAt), 0) / 86_400
        let recentBoost = days <= 2 ? 2.0 : 0
        return frequency + recentBoost + 1 / (1 + days)
    }

    public static func ranked(_ categories: [LedgerCategory], now: Date = .now) -> [LedgerCategory] {
        categories
            .map { (category: $0, score: score(usageCount: $0.usageCount, lastUsedAt: $0.lastUsedAt, now: now)) }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return lhs.category.sortOrder < rhs.category.sortOrder
            }
            .map(\.category)
    }
}
