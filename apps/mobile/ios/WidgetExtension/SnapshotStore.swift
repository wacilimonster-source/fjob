import Foundation

/// Reads the timeline published by the Flutter app through the App Group.
enum SnapshotStore {
    static let appGroup = "group.cn.fjob.todayagain"
    static let fileName = "widget-timeline.json"

    static func load() -> WidgetTimeline? {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroup
        ) else { return nil }
        let url = container.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return WidgetTimeline.decode(data)
    }
}
