import SwiftUI
import WidgetKit

struct FjobEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct FjobProvider: TimelineProvider {
    func placeholder(in context: Context) -> FjobEntry {
        FjobEntry(date: Date(), snapshot: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (FjobEntry) -> Void) {
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FjobEntry>) -> Void) {
        guard let timeline = SnapshotStore.load() else {
            completion(Timeline(entries: [currentEntry()], policy: .after(nextRefresh())))
            return
        }
        let entries = timeline.entries.compactMap { snapshot -> FjobEntry? in
            guard let date = snapshot.computedDate else { return nil }
            return FjobEntry(date: date, snapshot: snapshot)
        }
        if entries.isEmpty {
            completion(Timeline(entries: [currentEntry()], policy: .after(nextRefresh())))
        } else {
            completion(Timeline(entries: entries, policy: .atEnd))
        }
    }

    private func currentEntry() -> FjobEntry {
        let now = Date()
        let snapshot = SnapshotStore.load()?.entry(for: now)
        return FjobEntry(date: now, snapshot: snapshot)
    }

    private func nextRefresh() -> Date {
        Date().addingTimeInterval(30 * 60)
    }
}

struct FjobWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: FjobEntry

    var body: some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Palette.panel)
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Palette.ink, lineWidth: 1.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .widgetURL(URL(string: entry.snapshot?.deepLink ?? "fjob://dashboard"))
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            Text(totalText)
                .font(.system(size: family == .systemSmall ? 24 : 30, weight: .bold, design: .monospaced))
                .foregroundStyle(entry.snapshot?.privacy == true ? Palette.muted : Palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if family != .systemSmall {
                HStack(spacing: 10) {
                    split("打工", masked(entry.snapshot?.wage))
                    split("A股", masked(entry.snapshot?.stockDaily))
                    split("住房", masked(entry.snapshot?.housing))
                }
            }
            if family == .systemLarge {
                OfficeDoodle()
                    .frame(height: 96)
                    .padding(.top, 2)
                HStack(spacing: 10) {
                    split(entry.snapshot?.housingMode == "rent" ? "房租" : "房贷", masked(entry.snapshot?.housing))
                    split("车贷", masked(entry.snapshot?.car))
                }
            }
            Spacer(minLength: 0)
            Text(captionText)
                .font(.system(size: 10))
                .foregroundStyle(Palette.muted)
                .lineLimit(1)
            Text(timeText)
                .font(.system(size: 9))
                .foregroundStyle(Palette.muted)
        }
    }

    private var header: some View {
        HStack {
            Text("今日又白干")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Palette.ink)
            Spacer()
            Text(face)
                .font(.system(size: 12))
                .foregroundStyle(Palette.ink)
        }
    }

    private func split(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(Palette.muted)
            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var face: String {
        guard let snapshot = entry.snapshot else { return "(・_・)" }
        if snapshot.privacy { return "(－_－)" }
        return snapshot.isNegative ? "(－_－)" : "( ˘ᴗ˘ )"
    }

    private var totalText: String {
        guard let snapshot = entry.snapshot else { return "—" }
        if snapshot.tombstone { return "待配置" }
        if snapshot.privacy { return "¥ ••••" }
        guard let total = snapshot.total else { return "待更新" }
        return money(total)
    }

    private func masked(_ value: String?) -> String {
        if entry.snapshot?.privacy == true { return "••••" }
        guard let value else { return "—" }
        return money(value, withSymbol: false)
    }

    private var captionText: String {
        guard let snapshot = entry.snapshot else { return "打开 App 完成登记" }
        if snapshot.tombstone { return "账本已清空，待重新配置" }
        return snapshot.caption
    }

    private var timeText: String {
        guard let snapshot = entry.snapshot, let date = snapshot.computedDate else {
            return "打开 App 更新"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = TimeZone(identifier: snapshot.timezone) ?? .current
        formatter.dateFormat = "HH:mm"
        let stale = snapshot.validDate.map { Date() > $0 } ?? false
        return "\(stale ? "上次更新" : "截至") \(formatter.string(from: date))"
    }

    private func money(_ value: String, withSymbol: Bool = true) -> String {
        let negative = value.hasPrefix("-")
        let digits = negative ? String(value.dropFirst()) : value
        return "\(negative ? "−" : "")\(withSymbol ? "¥" : "")\(digits)"
    }
}

struct OfficeDoodle: View {
    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Palette.soft)
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Palette.ink, lineWidth: 1.2)
                    .frame(width: width * 0.26, height: height * 0.42)
                    .position(x: width * 0.78, y: height * 0.28)
                RoundedRectangle(cornerRadius: 3)
                    .fill(Palette.rose)
                    .frame(width: width * 0.18, height: height * 0.42)
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(Palette.ink, lineWidth: 1.2))
                    .position(x: width * 0.2, y: height * 0.62)
                Circle()
                    .fill(Palette.panel)
                    .overlay(Circle().stroke(Palette.ink, lineWidth: 1.2))
                    .frame(width: width * 0.14)
                    .position(x: width * 0.5, y: height * 0.38)
                RoundedRectangle(cornerRadius: 2)
                    .fill(Palette.yellow)
                    .overlay(RoundedRectangle(cornerRadius: 2).stroke(Palette.ink, lineWidth: 1.2))
                    .frame(width: width * 0.52, height: height * 0.12)
                    .position(x: width * 0.52, y: height * 0.72)
                RoundedRectangle(cornerRadius: 2)
                    .fill(Palette.panel)
                    .overlay(RoundedRectangle(cornerRadius: 2).stroke(Palette.ink, lineWidth: 1.2))
                    .frame(width: width * 0.16, height: height * 0.2)
                    .position(x: width * 0.7, y: height * 0.58)
            }
        }
        .accessibilityLabel("手绘办公室，疲惫的打工人在工位前")
    }
}

enum Palette {
    static let paper = Color(red: 0.969, green: 0.949, blue: 0.914)
    static let panel = Color(red: 1.0, green: 0.992, blue: 0.969)
    static let ink = Color(red: 0.196, green: 0.227, blue: 0.196)
    static let muted = Color(red: 0.408, green: 0.431, blue: 0.380)
    static let soft = Color(red: 0.914, green: 0.929, blue: 0.874)
    static let yellow = Color(red: 0.949, green: 0.875, blue: 0.675)
    static let rose = Color(red: 0.941, green: 0.824, blue: 0.773)
}

@main
struct FjobWidget: Widget {
    let kind = "FjobWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FjobProvider()) { entry in
            FjobWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("今日又白干")
        .description("工资、行情与固定支出组成的今日生存结余。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
