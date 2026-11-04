/// SETTINGS-01 设置。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../data/market_client.dart';
import '../../domain/ledger.dart';
import '../ledger/ledger_controller.dart';
import '../onboarding/onboarding_controller.dart';

const String appVersion = '0.1.0 (M0–M4 开发版)';

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
          const SectionLabel('关于'),
          const SizedBox(height: 6),
          _AboutRow('统计时区', settings.salaryTimezone),
          _AboutRow(
            '行情来源',
            client is FixtureMarketClient
                ? '模拟适配器（fixture）· 未接入真实报价'
                : '行情网关 · ${AppConfig.gatewayBaseUrl}',
          ),
          _AboutRow('账本修订', '${settings.ledgerRevision}'),
          _AboutRow('版本', appVersion),
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
