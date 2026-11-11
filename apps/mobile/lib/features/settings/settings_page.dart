/// SETTINGS-01 设置。
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import 'package:fjob_ui/fjob_ui.dart';
import 'package:market_data/market_data.dart';
import 'package:ledger_model/ledger_model.dart';
import '../ledger/ledger_controller.dart';
import '../onboarding/onboarding_controller.dart';
import 'update_controller.dart';
import 'ledger_transfer_page.dart';

const String appVersion = '0.1.2';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final ledger = ref.watch(effectiveLedgerProvider).value;
    final settings = ledger?.settings ?? const AppSettings();
    final sample = ref.watch(sampleModeProvider);
    final busy = ref.watch(busyProvider);
    final client = ref.read(marketClientProvider);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: palette.paper,
        surfaceTintColor: Colors.transparent,
        title: const Text('设置', style: TextStyle(fontSize: 18)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 28),
        children: [
          if (sample)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: PaperCard(
                color: palette.yellow,
                child: const Text('示例模式只读：设置会在退出示例后恢复生效。'),
              ),
            ),
          const SectionLabel('外观'),
          const SizedBox(height: 6),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('纸感浅色'),
            subtitle: const Text('固定使用奶油纸面与深灰绿轮廓，不再跟随系统深色。'),
            trailing: const Icon(Icons.palette_outlined, size: 20),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('减少动效'),
            subtitle: const Text('系统减少动态效果时自动停用循环动画。'),
            value: settings.motion == MotionSetting.reduced,
            onChanged: sample
                ? null
                : (value) => ref
                    .read(ledgerControllerProvider.notifier)
                    .updateMotion(
                      value ? MotionSetting.reduced : MotionSetting.full,
                    ),
          ),
          const Divider(height: 24),
          const SectionLabel('吐槽语气'),
          const SizedBox(height: 6),
          SegmentedButton<AppTone>(
            segments: const [
              ButtonSegment(value: AppTone.gentle, label: Text('温柔地丧')),
              ButtonSegment(value: AppTone.harsh, label: Text('再狠一点')),
            ],
            selected: {settings.tone},
            onSelectionChanged: sample
                ? null
                : (values) => ref
                    .read(ledgerControllerProvider.notifier)
                    .updateTone(values.first),
          ),
          const Divider(height: 24),
          const SectionLabel('小部件'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('桌面默认隐藏金额'),
            subtitle: const Text('隐私开关同时遮蔽快照、预览与可访问文案。'),
            value: settings.widgetPrivacy,
            onChanged: sample
                ? null
                : (value) => ref
                    .read(ledgerControllerProvider.notifier)
                    .updatePrivacy(value),
          ),
          const Divider(height: 24),
          const SectionLabel('数据'),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('手机与电脑交换账本'),
            subtitle: const Text('导入 / 导出 .fjob，导入前自动备份。'),
            trailing: const Icon(Icons.swap_horiz),
            enabled: !sample && !busy,
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute(builder: (_) => const LedgerTransferPage()),
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('重新走一遍入职引导'),
            subtitle: const Text('取消会回到原配置，最终确认才替换。'),
            trailing: const Icon(Icons.chevron_right),
            enabled: !sample && !busy,
            onTap: () {
              ref
                  .read(onboardingControllerProvider.notifier)
                  .startRedo();
              Navigator.of(context).pop();
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('清空本地账本', style: TextStyle(color: palette.negative)),
            subtitle: const Text('删除配置、草稿、行情缓存与桌面快照。'),
            trailing: const Icon(Icons.chevron_right),
            enabled: !sample && !busy,
            onTap: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('确认清空账本？'),
                  content: const Text(
                    '工资、持仓、账单、草稿、行情缓存与桌面快照都会失效，'
                    '这个操作不能撤销。',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('再想想'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('清空'),
                    ),
                  ],
                ),
              );
              if (confirmed != true) return;
              await ref.read(ledgerControllerProvider.notifier).clearLedger();
              if (context.mounted) Navigator.of(context).pop();
            },
          ),
          const Divider(height: 24),
          const SectionLabel('更新'),
          const SizedBox(height: 6),
          const _UpdateSection(),
          const Divider(height: 24),
          const SectionLabel('关于'),
          const SizedBox(height: 6),
          _AboutRow('统计时区', settings.salaryTimezone),
          _AboutRow(
            '行情来源',
            client is FixtureMarketClient
                ? '模拟适配器（fixture）· 未接入真实报价'
                : client is EastmoneyMarketClient
                    ? '东方财富公开接口 · developmentOnly（非官方授权）'
                    : '行情网关 · ${AppConfig.gatewayBaseUrl}',
          ),
          _AboutRow('账本修订', '${settings.ledgerRevision}'),
          _AboutRow('交易日历', '$cnMarketCalendarVersion · $cnMarketCalendarCoverage'),
          _AboutRow('版本', ref.watch(appVersionProvider).value ?? appVersion),
          const SizedBox(height: 14),
          Text(
            '个人账本保存在应用沙盒。行情请求只包含标的 ID，'
            '工资、持仓数量、成本、租金与贷款金额不上传。'
            '正式发布前需落实行情展示许可、包标识与签名资料。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.8),
          ),
        ],
      ),
    );
  }
}

class _AboutRow extends StatelessWidget {
  const _AboutRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 84,
              child: Text(label, style: Theme.of(context).textTheme.bodySmall),
            ),
            Expanded(
              child: Text(value, style: const TextStyle(fontSize: 13)),
            ),
          ],
        ),
      );
}

class _UpdateSection extends ConsumerWidget {
  const _UpdateSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final state = ref.watch(updateControllerProvider);
    final versionAsync = ref.watch(appVersionProvider);
    final controller = ref.read(updateControllerProvider.notifier);
    final release = state.release;
    final currentVersion =
        state.currentVersion ?? versionAsync.value ?? appVersion;
    final isAndroid = defaultTargetPlatform == TargetPlatform.android;
    final canDownload = release != null &&
        (state.phase == UpdatePhase.available ||
            state.phase == UpdatePhase.downloading ||
            state.phase == UpdatePhase.installing ||
            state.phase == UpdatePhase.installed ||
            state.phase == UpdatePhase.error);

    return PaperCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('当前版本',
                        style: Theme.of(context).textTheme.bodySmall),
                    Text(currentVersion,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              if (state.phase == UpdatePhase.available)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: palette.yellow,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: const Text('有新版本',
                      style: TextStyle(fontSize: 11)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            state.message ??
                (isAndroid
                    ? '优先经国内中转检查 GitHub 更新，失败自动回退直连；下载后校验 SHA-256 再交给系统安装。'
                    : '从 GitHub Releases 检查版本；iOS 通过 TestFlight 更新。'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (release != null &&
              state.phase != UpdatePhase.upToDate &&
              state.phase != UpdatePhase.checking) ...[
            const SizedBox(height: 10),
            Text(release.title,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            Text(
              '${release.tag} · ${release.sizeLabel}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (release.notes.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                _excerpt(release.notes),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.6),
                maxLines: 6,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 4),
            SelectableText(
              '发布页：${release.pageUrl}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 10),
            ),
          ],
          if (state.phase == UpdatePhase.downloading) ...[
            const SizedBox(height: 10),
            LinearProgressIndicator(
              value: state.progress <= 0 ? null : state.progress,
              minHeight: 6,
              backgroundColor: palette.line,
              valueColor: AlwaysStoppedAnimation<Color>(palette.positive),
            ),
            const SizedBox(height: 4),
            Text(
              '${(state.progress * 100).toStringAsFixed(0)}% · '
              '${release?.sizeLabel ?? ''}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (state.needsInstallPermission) ...[
            const SizedBox(height: 8),
            Text(
              'Android 8 起需要允许本应用安装未知应用，授权后返回再试。',
              style: TextStyle(fontSize: 12, color: palette.negative),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: controller.openInstallPermissionSettings,
                child: const Text('前往授权'),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: state.isBusy ? null : controller.check,
                  child: Text(
                    state.phase == UpdatePhase.checking ? '检查中…' : '检查更新',
                  ),
                ),
              ),
              if (isAndroid && canDownload) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: state.phase == UpdatePhase.downloading
                        ? null
                        : controller.downloadAndInstall,
                    child: Text(
                      state.phase == UpdatePhase.downloading
                          ? '下载中…'
                          : '下载并安装',
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (state.phase == UpdatePhase.downloading)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: controller.cancelDownload,
                child: const Text('取消下载'),
              ),
            ),
          if (!isAndroid)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'iOS 版本通过 TestFlight 或 App Store 更新。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          const SizedBox(height: 6),
          Text(
            '更新检查只访问 GitHub Releases（优先经国内中转），不发送工资、持仓或账单数据。'
            '安装包必须与发布页提供的 SHA-256 一致才会打开安装器。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 10),
          ),
        ],
      ),
    );
  }

  static String _excerpt(String notes) {
    final compact = notes.replaceAll(RegExp(r'[#*`>\-]'), ' ').replaceAll(
          RegExp(r'\s+'),
          ' ',
        );
    final trimmed = compact.trim();
    return trimmed.length <= 280 ? trimmed : '${trimmed.substring(0, 280)}…';
  }
}
