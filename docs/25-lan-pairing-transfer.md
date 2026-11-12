# 同一 Wi-Fi 对码互传（手机 ↔ PC）

版本 1.0 · 2026-11-12 · 用途：记录局域网 `.fjob` 直传的协议、安全边界、实现与实测。关联 `docs/16` PC6、`docs/24`。

## 1. 目标

手机与电脑在同一 Wi-Fi 下，不经过互联网、不依赖系统文件选择器，通过一次性的**地址 + 配对码**交换同一本账：

- 手机开一次性会话，显示 `地址:端口` 与 12 位配对码；
- 电脑输入地址和配对码，选择「从手机接收」或「发送到手机」；
- 手机端可选择「发送到电脑」或「从电脑接收」；
- 传输完成后会话立即结束，不能重放或继续使用。

## 2. 角色与流程

手机始终是**会话宿主**，电脑是**加入方**。这样电脑只发起出站连接，不会触发 Windows 防火墙的入站提示；手机在局域网内监听一个随机端口。

```
手机（宿主）                          电脑（加入方）
发送到电脑   ── 显示地址/码 ──►  数据 → 同一 Wi-Fi →「从手机接收」
从电脑接收   ── 显示地址/码 ──►  数据 → 同一 Wi-Fi →「发送到手机」
```

- 手机端：设置 → 数据 →「手机与电脑交换账本」→「同一 Wi-Fi 直传」。
- PC 端：数据 →「同一 Wi-Fi 直传」→「从手机接收」/「发送到手机」。
- 手机收到电脑推送后，先显示现有导入预览；用户确认后才写入，导入前自动备份。

## 3. 协议与安全

| 项 | 设计 |
| --- | --- |
| 传输 | 手机 `HttpServer` 绑定 `0.0.0.0:随机端口`，仅 HTTP/1.1、仅 `/session` 与 `/transfer` |
| 配对码 | 12 位 Crockford base32（去除 I/L/O/U），60 bit；显示为 `XXXX-XXXX-XXXX` |
| 密钥 | `HKDF-SHA256(code, salt, info="fjob-lan-v1/key")` → 256 bit |
| 加密 | AES-256-GCM；每个请求/响应独立 12 字节 nonce；AAD 固定 `fjob-lan-v1/transfer` |
| 会话 | 每次开始生成新 salt、challenge 与配对码；成功传输一次后 400 ms 关闭 |
| 失败限制 | 连续 5 次解密失败立即结束会话 |
| 超时 | 默认 10 分钟自动结束；界面显示等待/传输状态 |
| 重放 | 一次性会话 + challenge；成功后的请求返回 410，服务端关闭 |
| 日志 | 配对码、账本内容、金额不写入日志；错误只返回 `auth/format/mode/too_large` 等通用码 |
| 大小 | 账本上限 16 MB（与 `.fjob` 导入一致）；编码后请求体上限约 21.4 MB |
| 隐私 | 内容只在本机与对方设备内存中；不经过任何第三方服务 |

配对码只有 60 bit，但攻击者即使抓到密文也只能离线枚举；服务端 5 次失败即销毁会话，实际窗口内不可行。主动中间人无法在不知道配对码的情况下伪造 AES-GCM 密文。

## 4. 实现

| 文件 | 内容 |
| --- | --- |
| `packages/lan_transfer/lib/src/code.dart` | 配对码生成、规范化、校验、格式化 |
| `packages/lan_transfer/lib/src/crypto.dart` | HKDF + AES-256-GCM 信封 |
| `packages/lan_transfer/lib/src/server.dart` | 手机宿主：LAN IPv4 选择、一次性会话、限流、超时、事件流 |
| `packages/lan_transfer/lib/src/client.dart` | 电脑加入方：探测、拉取、推送、错误映射 |
| `packages/lan_transfer/lib/src/address.dart` | `ip:port` 解析与校验 |
| `packages/lan_transfer/test/lan_transfer_test.dart` | 11 项：编码/地址/加密/回环收发/错码/模式/超限/TTL |
| `packages/lan_transfer/tool/lan_cli.dart`、`lan_server_cli.dart` | 端到端联调 CLI |
| `apps/mobile/lib/features/settings/ledger_transfer_page.dart` | 发送到电脑/从电脑接收、地址码展示、导入预览 |
| `apps/desktop/lib/pages/data_page.dart` | 从手机接收/发送到手机、导入预览 |
| `apps/desktop/lib/widgets/lan_input_dialog.dart` | 地址/配对码表单与校验 |

手机端只承载一次性会话，不持久化配对关系；PC 端每次输入地址与配对码，不保存历史。

## 5. 验证

| 检查 | 结果 |
| --- | --- |
| `packages/lan_transfer` `dart analyze` / `dart test` | 无问题；11 通过 |
| `apps/mobile` `flutter analyze` / `flutter test` | 无问题；182 通过 + 1 跳过 |
| `apps/desktop` `flutter analyze` / `flutter test` | 无问题；37 通过（新增 LAN 表单 1 项） |
| 手机→电脑（Android 16 模拟器 + adb forward） | 拉取 2,055 B `.fjob`，`parity_check` 解出月薪/房贷/车贷/结余；手机显示“已发送到电脑” |
| 电脑→手机（同一模拟器） | 推送 2,055 B；手机弹出导入预览并确认；显示“已从电脑接收并导入账本” |
| 错码/模式/TTL/超限 | 共享包回环测试覆盖；错码 5 次后会话结束 |

截图：`docs/screenshots/25-android-lan-imported.png`（手机接收并导入后的页面）、`25-pc-lan-data.png`（PC 数据页的同一 Wi-Fi 直传入口）。

## 6. 未验证 / 边界

- 真实双设备（手机 Wi-Fi + 电脑同一路由器）未在本轮复测；模拟器通过 `adb forward` 验证了协议与手机 UI。
- 部分路由器开启 AP 隔离/访客网络时设备无法互访；界面会提示“连不上手机”。
- 手机屏幕熄灭或系统杀后台会中断会话；传输期间需保持页面在前台。
- 完整局域网同步（配对持久化、双向合并、冲突 UI）仍按 PC6/v0.2 规划；本版仅一次性账本互传。
- 200% 缩放、多显示器、Narrator 未复测。
