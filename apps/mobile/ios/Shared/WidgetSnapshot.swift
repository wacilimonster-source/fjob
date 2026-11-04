import Foundation

/// Mirrors `contracts/widget-snapshot.schema.json` for the app and the
/// WidgetKit extension. Both targets include this file; it only decodes and
/// validates pre-computed values, never recalculating them.
struct WidgetSnapshot: Decodable {
    let schemaVersion: Int
    let ledgerRevision: Int
    let createdAt: String
    let computedAt: String
    let quotesAsOf: String?
    let validUntil: String
    let timezone: String
    let privacy: Bool
    let tombstone: Bool
    let completeness: String
    let quoteQuality: String
    let amounts: [String: String?]
    let housingMode: String
    let scene: String
    let caption: String
    let deepLink: String

    static let allowedDeepLinks: Set<String> = [
        "fjob://dashboard",
        "fjob://expenses/housing",
        "fjob://expenses/car",
        "fjob://widgets",
    ]

    static let amountPattern = try! NSRegularExpression(
        pattern: "^-?(0|[1-9][0-9]*)\\.[0-9]{2}$"
    )

    var total: String? { amounts["total"] ?? nil }
    var wage: String? { amounts["wage"] ?? nil }
    var stockDaily: String? { amounts["stockDaily"] ?? nil }
    var goldDaily: String? { amounts["goldDaily"] ?? nil }
    var housing: String? { amounts["housing"] ?? nil }
    var car: String? { amounts["car"] ?? nil }
    var isNegative: Bool { total?.hasPrefix("-") ?? false }

    var computedDate: Date? { Self.formatter.date(from: computedAt) }
    var validDate: Date? { Self.formatter.date(from: validUntil) }

    var isSupported: Bool {
        guard schemaVersion == 1, !timezone.isEmpty, caption.count <= 100 else {
            return false
        }
        guard Self.allowedDeepLinks.contains(deepLink) else { return false }
        let expectedKeys: Set<String> = [
            "total", "wage", "stockDaily", "goldDaily",
            "housing", "car", "principal", "interest", "rent",
        ]
        guard Set(amounts.keys) == expectedKeys else { return false }
        for (_, value) in amounts {
            if let value {
                let range = NSRange(value.startIndex..<value.endIndex, in: value)
                if Self.amountPattern.firstMatch(in: value, range: range) == nil {
                    return false
                }
            }
        }
        if privacy && amounts.values.contains(where: { $0 != nil }) { return false }
        if tombstone && (completeness != "unavailable" || !privacy) { return false }
        return computedDate != nil && validDate != nil
    }

    static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

struct WidgetTimeline: Decodable {
    let timelineVersion: Int
    let ledgerRevision: Int
    let entries: [WidgetSnapshot]

    func entry(for date: Date) -> WidgetSnapshot? {
        var chosen: WidgetSnapshot?
        for entry in entries {
            guard let computed = entry.computedDate else { continue }
            if computed <= date { chosen = entry } else { break }
        }
        return chosen ?? entries.first
    }

    static func decode(_ data: Data) -> WidgetTimeline? {
        guard let timeline = try? JSONDecoder().decode(WidgetTimeline.self, from: data) else {
            return nil
        }
        guard timeline.timelineVersion == 1,
              !timeline.entries.isEmpty,
              timeline.entries.count <= 289,
              timeline.entries.allSatisfy({ $0.isSupported }),
              timeline.entries.allSatisfy({ $0.ledgerRevision <= timeline.ledgerRevision })
        else { return nil }
        return timeline
    }
}
