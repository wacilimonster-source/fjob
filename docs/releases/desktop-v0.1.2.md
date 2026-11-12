# desktop-v0.1.2 · PC 手动配置可用性修复

发布日期：2026-11-12 · Tag：`desktop-v0.1.2` · 版本 `0.1.2` · 平台：Windows 10 1809+ / 11 x64。

从 `desktop-v0.1.1` 可直接覆盖安装，账本与显示设置保留。

## 修复

- **不导入手机账本也能正常使用**：`isConfigured` 改为“工资 + 排班”数据驱动，不再要求手机入职完成时间戳。此前 PC 手动填写工资与排班后，主窗仍停在欢迎面板，固定窗显示“打开主窗配置账本”。
- **保存即记录完成**：`replaceCompensation` 在事务内补写 `onboarding_completed_at`（仅当为空），导出与后续引导判断一致。
- **跨端不再误触发入职**：从 PC 手动导出的 `.fjob`（onboarding 为 null）导入手机后，手机端直接进入主界面。
- 同步合入 `desktop-v0.1.1` 的托盘图标与小窗最小化修复。

## 验证

| 检查 | 结果 |
| --- | --- |
| `flutter analyze`（apps/desktop） | No issues found |
| `flutter test`（apps/desktop） | 36 通过（新增手动配置回归 1 项） |
| `flutter build windows --release` | 成功 |
| 临时 APPDATA 实跑 | 手动保存工资+排班后固定窗显示实时金额，不再显示配置占位 |

根因与方案见 [docs/24-pc-manual-config-and-mobile-export.md](../24-pc-manual-config-and-mobile-export.md)。

## 安装与卸载

- 安装：`FJOB-Setup-0.1.2.exe`，当前用户安装，无需管理员权限；可选桌面快捷方式。
- 便携版：解压 `fjob-desktop-0.1.2-win-x64.zip` 直接运行；数据目录同为 `%APPDATA%\FJOB`。
- 卸载：设置 → 应用 → 今日又白干 → 卸载，只移除程序文件，账本与显示设置保留。

## 已知边界

- 未配置代码签名 Secrets 时首次运行可能出现 SmartScreen 提示。
- Windows 11 托盘图标默认位于 `^` 溢出区。
- 手机导出的 Downloads 兜底随手机 `v0.1.12` 发布；PC 端 `desktop-v0.1.2` 不包含手机 APK。
- 真实行情来源展示许可、200% 缩放、多显示器、Narrator 未在本版重新验收。
- 局域网对码互传未实施，按 PC6/v0.2 单独评估。

## 校验

`SHA256SUMS` 随 Release 提供，包含安装包与便携 zip；设置页「检查更新」使用同一 SHA-256 校验安装包。
