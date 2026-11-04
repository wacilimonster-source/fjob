# iOS Widget Extension 接入说明（未在 Windows 上编译验证）

本目录提供 WidgetKit 扩展的 Swift 源码、Info.plist 与 App Group entitlement。
Flutter Runner 侧已实现 `WidgetBridge.swift` 与 `fjob://` URL scheme。

由于交付环境为 Windows，无法执行 Xcode 构建，以下接线必须在 macOS CI 上完成并记录证据：

1. 在 Xcode 中为 `Runner.xcodeproj` 新增 Widget Extension target：
   - 名称 `FjobWidget`，Bundle ID 占位 `cn.fjob.todayagain.widget`。
   - 平台 iOS 16.0+，类型 Widget Extension（不勾选 Include Configuration App Intent）。
   - 用本目录的 `FjobWidget.swift`、`SnapshotStore.swift` 替换模板源码。
2. 将 `ios/Shared/WidgetSnapshot.swift` 同时加入 `Runner` 与 `FjobWidget` 两个 target。
3. 两个 target 都开启 App Groups，并加入 `group.cn.fjob.todayagain`：
   - Runner 使用 `ios/Runner/Runner.entitlements`。
   - 扩展使用 `ios/WidgetExtension/FjobWidget.entitlements`。
4. 在 Runner target 的 Signing & Capabilities 中勾选 App Groups；在扩展中重复一次。
5. 确认 Runner 的 Info.plist 已包含 `fjob` URL scheme（本仓库已写入）。
6. 在 CI 的 `flutter build ipa` 前，用 `exportOptions.plist` 为两个 Bundle ID 分别映射 provisioning profile。
7. 模拟器验收项：小/中/大三种尺寸、隐私遮蔽、tombstone、过期时间显示、`fjob://` 深链。

扩展只读取 App Group 中的 `widget-timeline.json`，不计算工资或盈亏。
任何未加入 App Group 的运行都会导致发布失败并返回 false，App 主流程不受影响。
