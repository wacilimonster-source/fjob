import Flutter
import UIKit
import WidgetKit

/// Receives pre-computed widget timelines from Dart and stores them in the App
/// Group container. The extension only reads this file.
final class WidgetBridge: NSObject {
    static let appGroup = "group.cn.fjob.todayagain"
    static let timelineFile = "widget-timeline.json"
    static let widgetChannel = "cn.fjob.todayagain/widgets"
    static let deepLinkChannel = "cn.fjob.todayagain/deeplinks"
    static let deepLinkEvents = "cn.fjob.todayagain/deeplinks/events"

    private var linkSink: FlutterEventSink?
    private var initialLink: String?

    func register(messenger: FlutterBinaryMessenger, launchURL: URL?) {
        initialLink = launchURL?.absoluteString

        let channel = FlutterMethodChannel(name: Self.widgetChannel, binaryMessenger: messenger)
        channel.setMethodCallHandler { [weak self] call, result in
            switch call.method {
            case "publishTimeline":
                guard let json = call.arguments as? [String: Any],
                      let payload = json["json"] as? String
                else {
                    result(FlutterError(code: "bad_args", message: "json is required", details: nil))
                    return
                }
                result(self?.publish(payload, tombstoneOnly: false) ?? false)
            case "clear":
                guard let json = call.arguments as? [String: Any],
                      let payload = json["json"] as? String
                else {
                    result(FlutterError(code: "bad_args", message: "json is required", details: nil))
                    return
                }
                result(self?.publish(payload, tombstoneOnly: true) ?? false)
            default:
                result(FlutterMethodNotImplemented)
            }
        }

        let links = FlutterMethodChannel(name: Self.deepLinkChannel, binaryMessenger: messenger)
        links.setMethodCallHandler { [weak self] call, result in
            guard call.method == "getInitialDeepLink" else {
                result(FlutterMethodNotImplemented)
                return
            }
            result(self?.initialLink)
            self?.initialLink = nil
        }

        FlutterEventChannel(name: Self.deepLinkEvents, binaryMessenger: messenger)
            .setStreamHandler(self)
    }

    func handle(url: URL) {
        guard url.scheme == "fjob" else { return }
        if let sink = linkSink {
            sink(url.absoluteString)
        } else {
            initialLink = url.absoluteString
        }
    }

    private func publish(_ payload: String, tombstoneOnly: Bool) -> Bool {
        guard let data = payload.data(using: .utf8),
              let timeline = WidgetTimeline.decode(data),
              let first = timeline.entries.first
        else { return false }
        if tombstoneOnly && !first.tombstone { return false }
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: Self.appGroup
        ) else {
            // Without the App Group entitlement the app keeps working; the
            // widget simply keeps its previous snapshot.
            return false
        }
        let defaults = UserDefaults(suiteName: Self.appGroup)
        let stored = defaults?.integer(forKey: "ledgerRevision") ?? -1
        guard timeline.ledgerRevision >= stored else { return false }
        let url = container.appendingPathComponent(Self.timelineFile)
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            return false
        }
        defaults?.set(timeline.ledgerRevision, forKey: "ledgerRevision")
        defaults?.set(first.tombstone ? "tombstone" : "timeline", forKey: "payloadKind")
        WidgetCenter.shared.reloadAllTimelines()
        return true
    }
}

extension WidgetBridge: FlutterStreamHandler {
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        linkSink = events
        if let pending = initialLink {
            events(pending)
            initialLink = nil
        }
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        linkSink = nil
        return nil
    }
}
