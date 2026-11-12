# PC 手动配置可用性与手机导出兜底

版本 1.0 · 2026-11-12 · 用途：记录本轮三项反馈的评估、根因、修复与实测。关联 `docs/06`、`docs/16`、`docs/22`、`docs/23`。

## 1. 反馈

1. 手机上导出 `.fjob` 文件失败。
2. 可考虑同局域网内通过对码互传。
3. PC 端不导入手机账本、手动填写配置后没有展示；需要支持脱离手机独立使用。

## 2. 方案评估

### 2.1 手机导出

`ledger_transfer_page` 原来只调用 `FilePicker.saveFile`（Android SAF 的 `ACTION_CREATE_DOCUMENT`）。该对话框由系统/厂商文件管理器实现：

- Android 16 模拟器实测可正常保存并写出 2,055 B 的 `.fjob`，说明代码主路径成立；
- 用户设备失败更可能来自厂商文件管理器不返回可写文档、无法启动选择器，或所选位置不支持 `openOutputStream`；
- 这类失败无法在 Flutter 侧预判，必须提供不依赖 SAF 的通道。

采用方案：**系统对话框优先 + 免权限 Downloads 兜底**。

- Android 10+ 通过 `MediaStore.Downloads` 写入公共 `下载/FJOB/`，不需要存储权限；
- Android 8/9 写入应用专属外部 `Download/FJOB/`，同样不需要权限；
- 页面新增「保存到下载目录」按钮；系统对话框抛错时也会自动走该通道；
- 错误信息区分“用户取消”和“写入失败”，取消不会偷偷改存。

### 2.2 局域网对码互传

本轮**不实施**，原因：

- 账本包含工资、房贷、车贷等敏感金额，局域网传输必须加密；仅 6 位对码可被离线暴力枚举，至少需要高熵会话密钥 + 认证密钥交换；
- 需要处理 Windows 防火墙入站提示、手机端前后台生命周期、路由器隔离（AP isolation）、发现/配对/一次性会话与导入确认；
- 项目已在 `docs/16` PC6 规划完整局域网同步（配对、manifest、双向合并、冲突 UI），一次性互传会与其重复设计。

结论：先用 Downloads 兜底把“导出一定拿得到文件”做扎实；局域网互传留到 PC6/v0.2，按加密配对方案单独交付。

### 2.3 PC 手动配置不展示

根因是模型把两件事绑在一起：

```dart
bool get isConfigured =>
    settings.hasCompletedOnboarding && salaryVersions.isNotEmpty && schedules.isNotEmpty;
```

`hasCompletedOnboarding` 只由手机入职 `commitSetup` 写入；PC 配置页走 `replaceCompensation`（工资 + 排班），从未写 `onboarding_completed_at`。因此：

- 主窗 `configured` 一直为 false，欢迎面板不消失；
- 固定窗 engine 读到 `!ledger.isConfigured`，显示“打开主窗配置账本”；
- 行情刷新、预览等按未配置账本处理。

修复为**数据驱动**：

- `isConfigured` 只看工资版本 + 排班是否存在，不再要求引导时间戳；
- `replaceCompensation` 在事务内补写 `onboarding_completed_at`（仅当为空），让导出/后续引导判断也准确；
- 手机端导入 PC 手动导出的 `.fjob`（onboarding 为 null）不会再被带回入职页。

## 3. 修改

| 文件 | 修改 |
| --- | --- |
| `packages/ledger_model/lib/domain/ledger.dart` | `isConfigured` 改为工资 + 排班数据驱动 |
| `packages/ledger_store/lib/data/ledger_repository.dart` | `replaceCompensation` 补写 `onboarding_completed_at` |
| `packages/ledger_model/test/ledger_test.dart`（新） | 无引导时间戳但工资/排班齐全时可配置；缺任一仍不可配置 |
| `packages/ledger_store/test/ledger_store_test.dart` | 空库手动保存工资+排班后 `isConfigured`/`hasCompletedOnboarding` 均为 true |
| `apps/desktop/test/manual_config_test.dart`（新） | 主窗在“工资+排班齐全、无引导时间戳”时不再显示导入欢迎面板 |
| `apps/mobile/android/.../files/LedgerFilesPlugin.kt`（新） | MediaStore/应用专属 Downloads 写入；文件名净化 |
| `apps/mobile/android/.../MainActivity.kt` | 注册 `cn.fjob.todayagain/files` 通道 |
| `apps/mobile/lib/data/ledger_files.dart`（新） | Dart 侧原生桥，错误不含账本内容 |
| `apps/mobile/lib/data/ledger_exporter.dart`（新） | 系统对话框优先、失败回退 Downloads、取消不兜底 |
| `apps/mobile/lib/features/settings/ledger_transfer_page.dart` | 新增“保存到下载目录”，导出错误文案区分取消/写入失败 |
| `apps/mobile/lib/app/providers.dart` | `ledgerExporterProvider` 便于测试覆盖 |
| `apps/mobile/test/ledger_exporter_test.dart`（新） | 选择器成功/取消/异常回退/下载失败/桥参数与错误映射 |
| `apps/mobile/android/app/src/test/.../LedgerFilesPluginTest.kt`（新） | 文件名净化（路径、保留字符、控制字符、空名、长度） |

## 4. 验证（实际执行）

| 命令/检查 | 结果 |
| --- | --- |
| `packages/ledger_model` `dart test` | 79 通过（新增 2） |
| `packages/ledger_store` `dart test` | 14 通过（新增 1） |
| `packages/finance_core` / `market_data` / `fjob_ui` | 110 / 65 / 35 通过 |
| `apps/desktop` `flutter analyze` + `flutter test` | 无问题；36 通过（新增 1） |
| `apps/mobile` `flutter analyze` + `flutter test` | 无问题；182 通过 + 1 跳过（新增 6） |
| `apps/mobile/android` `testDebugUnitTest` | `LedgerFilesPluginTest` 通过 |
| `flutter build windows --release` | 成功；修复后 exe 实跑 |
| Android 16 模拟器（release debug 构建） | 系统对话框导出成功；「保存到下载目录」成功写入 `/sdcard/Download/FJOB/fjob-2026-11-12.fjob`（2,055 B） |
| PC 实跑（临时 APPDATA，手动保存工资+排班） | 固定窗显示实时金额（`24-pc-manual-card.png`），不再显示“打开主窗配置账本” |

截图：`docs/screenshots/24-android-downloads-export.png`、`24-pc-manual-card.png`。

## 5. 发版

- 手机：`v0.1.12`，含导出兜底与共享 `isConfigured` 修正。
- PC：`desktop-v0.1.2`，含手动配置可用性修正。

## 6. 未验证 / 外部依赖

- 用户具体机型的系统文件选择器失败原因无法在本机复现；Downloads 兜底已覆盖“选择器不可用/不可写”的主路径。
- 局域网对码互传未实施，仍按 PC6/v0.2 的加密配对方案评估。
- `v0.1.12` APK 真机安装、覆盖升级与更新器复测未做（CI 产物下载后可补）。
- 200% 缩放、多显示器、Narrator 未复测。
