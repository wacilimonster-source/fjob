/// WIDGET-01 桌面分身：三种信息密度、隐私与手动刷新。
library;

import 'package:finance_core/finance_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../domain/format.dart';
import '../dashboard/office_scene.dart';
import '../ledger/ledger_controller.dart';

enum WidgetPreviewSize { small, medium, large }

class WidgetsPage extends ConsumerStatefulWidget {
  const WidgetsPage({super.key});

  @override
  ConsumerState<WidgetsPage> createState() => _WidgetsPageState();
}

class _WidgetsPageState extends ConsumerState<WidgetsPage> {
  WidgetPreviewSize _size = WidgetPreviewSize.medium;
  bool _publishing = false;

  Future<void> _publish() async {
    if (_publishing) return;
    setState(() => _publishing = true);
    try {
      await ref.read(ledgerControllerProvider.notifier).publishWidgets();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已把最新快照交给桌面小部件。')),
      );
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final snapshot = ref.watch(dashboardProvider).value;
    final ledger = ref.watch(effectiveLedgerProvider).value;
    final calendar = ref.watch(calendarProvider);
    final privacy = ledger?.settings.widgetPrivacy ?? false;
    final sample = ref.watch(sampleModeProvider);
    final client = ref.read(marketClientProvider);

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('把无力感搬到桌面',
                        style: Theme.of(context).textTheme.headlineMedium),
                    const SizedBox(height: 4),
                    Text('小部件外观预览 · 与当前账本同步',
                        style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 6,
                      children: [
                        ChoiceChip(
                          label: const Text('小号 · 一眼破防'),
                          selected: _size == WidgetPreviewSize.small,
                          onSelected: (_) =>
                              setState(() => _size = WidgetPreviewSize.small),
                        ),
                        ChoiceChip(
                          label: const Text('中号 · 收支现场'),
                          selected: _size == WidgetPreviewSize.medium,
                          onSelected: (_) =>
                              setState(() => _size = WidgetPreviewSize.medium),
                        ),
                        ChoiceChip(
                          label: const Text('大号 · 带上工位'),
                          selected: _size == WidgetPreviewSize.large,
                          onSelected: (_) =>
                              setState(() => _size = WidgetPreviewSize.large),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 24,
                      ),
                      decoration: BoxDecoration(
                        color: palette.soft,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Center(
                        child: snapshot == null
                            ? const CircularProgressIndicator()
                            : _WidgetPreview(
                                snapshot: snapshot,
                                privacy: privacy,
                                size: _size,
                                calendar: calendar,
                              ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('隐藏金额，只让表情替你说话'),
                      subtitle: Text(
                        '隐私开启后快照金额为 null，原生无障碍文案也使用占位词。',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      value: privacy,
                      onChanged: sample
                          ? null
                          : (value) => ref
                              .read(ledgerControllerProvider.notifier)
                              .updatePrivacy(value),
                    ),
                    const SizedBox(height: 6),
                    FilledButton.icon(
                      onPressed: _publishing || snapshot == null ? null : _publish,
                      icon: const Icon(Icons.refresh, size: 18),
                      label: Text(_publishing ? '正在送到桌面…' : '手动刷新桌面快照'),
                    ),
                    const SizedBox(height: 16),
                    PaperCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('刷新与时间',
                              style: TextStyle(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 6),
                          Text(
                            '小部件显示“截至 ${formatClock(snapshot?.computedAtUtc, calendar)}”'
                            '的快照。App 前台每 250ms 重算一次；桌面由系统调度，'
                            'Android 目标 30 分钟。',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Android 使用 RemoteViews 与 WorkManager，'
                            '原生层只选择当前时点之前最近的预计算条目。',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '点击总额进入首页，点击住房账单进入固定牵挂；'
                            '深链仅接受白名单路径。',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '行情来源：${client.sourceLabel}'
                            '${client.isFixture ? '（模拟，不伪装实时）' : ''}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _WidgetPreview extends StatelessWidget {
  const _WidgetPreview({
    required this.snapshot,
    required this.privacy,
    required this.size,
    required this.calendar,
  });

  final DashboardSnapshot snapshot;
  final bool privacy;
  final WidgetPreviewSize size;
  final BusinessCalendar calendar;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final total = snapshot.total;
    final known = total != null && !privacy;
    final negative = total?.isNegative ?? false;
    final face = negative ? '(－_－)' : '( ˘ᴗ˘ )';
    final width = switch (size) {
      WidgetPreviewSize.small => 180.0,
      WidgetPreviewSize.medium => 320.0,
      WidgetPreviewSize.large => 360.0,
    };
    final masked = privacy ? '¥ ••••' : formatMoney(total);
    final invest = (snapshot.stockDaily ?? Rational.zero) +
        (snapshot.goldDaily ?? Rational.zero);
    return Container(
      width: width,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.panel,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: palette.ink, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: palette.ink.withValues(alpha: 0.12),
            offset: const Offset(3, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text('今日又白干',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: palette.ink,
                  )),
              const Spacer(),
              Semantics(
                label: '疲惫表情',
                child: Text(face, style: TextStyle(color: palette.ink)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          MoneyText(
            masked,
            size: size == WidgetPreviewSize.small ? 24 : 30,
            color: privacy
                ? palette.muted
                : negative
                    ? palette.negative
                    : palette.positive,
          ),
          if (size != WidgetPreviewSize.small) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                _SplitCell(
                  label: '打工',
                  value: privacy ? '••••' : formatSigned(snapshot.wage),
                  good: (snapshot.wage?.isNegative ?? false) == false,
                ),
                _SplitCell(
                  label: '投资',
                  value: privacy ? '••••' : formatSigned(invest),
                  good: !invest.isNegative,
                ),
                _SplitCell(
                  label: '固定支出',
                  value: privacy
                      ? '••••'
                      : formatMoney(snapshot.allocatedExpenses),
                  good: false,
                ),
              ],
            ),
          ],
          if (size == WidgetPreviewSize.large) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                height: 118,
                child: OfficeScene(
                  phase: snapshot.phase,
                  completeness: snapshot.completeness,
                  total: snapshot.total,
                  reduceMotion: true,
                  showHousing: snapshot.housingDetail.configured,
                  showCar: snapshot.carDetail.configured,
                  housingLabel: switch (snapshot.housingDetail.housingMode) {
                    HousingMode.rent => '房租',
                    HousingMode.mortgage => '房贷',
                    _ => '住房',
                  },
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            known ? '截至 ${formatClock(snapshot.computedAtUtc, calendar)}' : '金额已隐藏 · 打开 App 查看',
            style: TextStyle(fontSize: 10, color: palette.muted),
          ),
        ],
      ),
    );
  }
}

class _SplitCell extends StatelessWidget {
  const _SplitCell({
    required this.label,
    required this.value,
    required this.good,
  });

  final String label;
  final String value;
  final bool good;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 9, color: palette.muted)),
          Text(
            value,
            style: TextStyle(
              fontSize: 11,
              color: good ? palette.positive : palette.negative,
              fontFamily: 'Consolas',
            ),
          ),
        ],
      ),
    );
  }
}
