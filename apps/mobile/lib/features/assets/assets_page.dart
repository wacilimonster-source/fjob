/// ASSET-01 资产风浪。
library;

import 'package:finance_core/finance_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../domain/format.dart';
import '../../domain/setup_draft.dart';
import '../ledger/ledger_controller.dart';
import 'holding_editor.dart';

class AssetsPage extends ConsumerStatefulWidget {
  const AssetsPage({super.key});

  @override
  ConsumerState<AssetsPage> createState() => _AssetsPageState();
}

class _AssetsPageState extends ConsumerState<AssetsPage> {
  String? _status;

  Future<void> _edit(AssetPosition position) async {
    if (ref.read(sampleModeProvider)) {
      _setStatus('示例模式不写入正式账本。');
      return;
    }
    final initial = HoldingDraft(
      market: _marketOf(position.instrumentId),
      code: position.instrumentId.split('.').last,
      name: ref.read(effectiveLedgerProvider).value?.instrumentNames[
              position.instrumentId] ??
          '',
      quantityText: position.holding.quantity.toCanonicalString(maxScale: 0),
      costText: position.holding.costPerUnit.toCanonicalString(maxScale: 3),
    );
    final edited = await showHoldingEditor(context, initial: initial);
    if (edited == null) return;
    try {
      final controller = ref.read(ledgerControllerProvider.notifier);
      if (edited.instrumentId != position.instrumentId) {
        await controller.deleteHolding(position.instrumentId);
      }
      await controller.upsertHolding(
        instrumentId: edited.instrumentId,
        quantity: Rational.parse(edited.quantityText),
        costPerUnit: Rational.parse(edited.costText),
        name: edited.name,
      );
      await controller.refreshQuotes();
      _setStatus('持仓已更新，今日估算按当前持仓重估。');
    } on Object catch (error) {
      _setStatus('$error');
    }
  }

  Future<void> _add() async {
    if (ref.read(sampleModeProvider)) {
      _setStatus('示例模式不写入正式账本。');
      return;
    }
    final created = await showHoldingEditor(context);
    if (created == null) return;
    try {
      final controller = ref.read(ledgerControllerProvider.notifier);
      final ledger = ref.read(ledgerControllerProvider).value;
      final exists = ledger?.holdings.any(
            (holding) =>
                holding.instrumentId == created.instrumentId &&
                (holding.effectiveToUtc == null),
          ) ??
          false;
      if (exists) {
        _setStatus('这个代码已经在账本里，请直接编辑已有持仓。');
        return;
      }
      await controller.upsertHolding(
        instrumentId: created.instrumentId,
        quantity: Rational.parse(created.quantityText),
        costPerUnit: Rational.parse(created.costText),
        name: created.name,
      );
      await controller.refreshQuotes();
      _setStatus('已添加 ${created.code}，报价待刷新。');
    } on Object catch (error) {
      _setStatus('$error');
    }
  }

  Future<void> _delete(AssetPosition position) async {
    if (ref.read(sampleModeProvider)) {
      _setStatus('示例模式不写入正式账本。');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除这笔持仓？'),
        content: Text(
          '${position.instrumentId} 将从当前账本移除，历史版本仍然保留。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('先留着'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref
          .read(ledgerControllerProvider.notifier)
          .deleteHolding(position.instrumentId);
      _setStatus('已删除持仓。');
    } on Object catch (error) {
      _setStatus('$error');
    }
  }

  void _setStatus(String message) {
    if (mounted) setState(() => _status = message);
  }

  static StockMarket _marketOf(String instrumentId) {
    if (instrumentId.startsWith('CN.SH.')) return StockMarket.sse;
    if (instrumentId.startsWith('CN.BJ.')) return StockMarket.bse;
    return StockMarket.szse;
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final snapshot = ref.watch(dashboardProvider).value;
    final ledger = ref.watch(effectiveLedgerProvider).value;
    final calendar = ref.watch(calendarProvider);
    final client = ref.read(marketClientProvider);
    final quoteStatus = ref.watch(quoteStatusProvider);
    final sample = ref.watch(sampleModeProvider);
    final positions = snapshot?.assets.positions ?? const <AssetPosition>[];

    return RefreshIndicator(
      color: palette.ink,
      onRefresh: () => ref.read(ledgerControllerProvider.notifier).refreshQuotes(),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
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
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('市场替你安排了',
                                    style: Theme.of(context).textTheme.headlineMedium),
                                const SizedBox(height: 4),
                                Text(
                                  'A股 + 按克黄金 · ${client.sourceLabel}'
                                  '${client.isFixture ? ' · 模拟数据' : ''}',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: '刷新报价',
                            onPressed: quoteStatus.status == QuoteStatus.refreshing
                                ? null
                                : () => ref
                                    .read(ledgerControllerProvider.notifier)
                                    .refreshQuotes(),
                            icon: quoteStatus.status == QuoteStatus.refreshing
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.refresh),
                          ),
                        ],
                      ),
                      if (_status != null) ...[
                        const SizedBox(height: 10),
                        PaperCard(
                          color: palette.soft,
                          child: Text(_status!,
                              style: Theme.of(context).textTheme.bodySmall),
                        ),
                      ],
                      const SizedBox(height: 14),
                      if (positions.isEmpty)
                        PaperCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('还没有任何资产'),
                              const SizedBox(height: 6),
                              Text(
                                '没有持仓时，今日浮动与持有盈亏都按已知 0 处理。'
                                '可以随时添加A股或按克黄金。',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      for (final position in positions) ...[
                        _PositionCard(
                          position: position,
                          displayName:
                              ledger?.instrumentNames[position.instrumentId],
                          calendar: calendar,
                          onEdit: sample ? null : () => _edit(position),
                          onDelete: sample ? null : () => _delete(position),
                        ),
                        const SizedBox(height: 10),
                      ],
                      const SizedBox(height: 4),
                      OutlinedButton.icon(
                        onPressed: sample ? null : _add,
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('添加持仓'),
                      ),
                      const SizedBox(height: 16),
                      PaperCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('数据来源与口径',
                                style: TextStyle(fontWeight: FontWeight.w600)),
                            const SizedBox(height: 6),
                            Text(
                              client.isFixture
                                  ? '当前报价来自模拟适配器，价格由标的与交易日确定，'
                                      '不会逐帧随机变化；正式发布前需接入已验证的行情网关。'
                                  : '报价来自网关；个人工资、持仓数量与成本不会上传。',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'A股今日浮动使用同一来源的前收参考价；休市自然日为 0，'
                              '跨交易日基准失效时显示待更新。黄金使用人民币每克参考价，'
                              '夜盘基准以来源返回的参考交易日为准。',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            if (ledger != null) ...[
                              const SizedBox(height: 6),
                              Text(
                                '账本修订 ${ledger.settings.ledgerRevision} · '
                                '时区 ${ledger.settings.salaryTimezone}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
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
      ),
    );
  }
}

class _PositionCard extends StatelessWidget {
  const _PositionCard({
    required this.position,
    required this.displayName,
    required this.calendar,
    this.onEdit,
    this.onDelete,
  });

  final AssetPosition position;
  final String? displayName;
  final BusinessCalendar calendar;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final quote = position.quote;
    final gold = position.kind == InstrumentKind.gold;
    final price = quote?.priceCny;
    final daily = position.dailyPnl;
    final held = position.heldPnl;
    final isStock = !gold;
    return PaperCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (displayName?.isNotEmpty ?? false)
                          ? (gold
                              ? displayName!
                              : '$displayName · ${position.instrumentId}')
                          : (gold ? '黄金 · Au99.99' : position.instrumentId),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      gold
                          ? '${position.holding.quantity.toCanonicalString(maxScale: 3)} 克 · '
                              '成本 ${formatMoney(position.holding.costPerUnit)}/克'
                          : '${position.holding.quantity.toCanonicalString(maxScale: 0)} 股 · '
                              '成本 ${position.holding.costPerUnit.toFixed(3)} 元',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              _StatusChip(status: position.status),
              if (onEdit != null)
                IconButton(
                  tooltip: '编辑持仓',
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                ),
              if (onDelete != null)
                IconButton(
                  tooltip: '删除持仓',
                  onPressed: onDelete,
                  icon: Icon(Icons.delete_outline, size: 18, color: palette.muted),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('当前价', style: Theme.of(context).textTheme.bodySmall),
                    MoneyText(
                      price == null
                          ? '待报价'
                          : '¥${price.toFixed(isStock ? 3 : 2)}'
                              '${gold ? ' / 克' : ''}',
                      size: 22,
                      color: price == null ? palette.muted : palette.ink,
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('今日浮动', style: Theme.of(context).textTheme.bodySmall),
                  MoneyText(
                    formatMoney(daily, signed: true),
                    color: (daily?.isNegative ?? false)
                        ? palette.negative
                        : palette.positive,
                  ),
                  const SizedBox(height: 2),
                  Text('持有盈亏', style: Theme.of(context).textTheme.bodySmall),
                  MoneyText(
                    formatMoney(held, signed: true),
                    color: (held?.isNegative ?? false)
                        ? palette.negative
                        : palette.positive,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _note(),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  String _note() {
    final status = switch (position.status) {
      PositionStatus.pendingQuote => '还没有拿到报价，盈亏显示待更新。',
      PositionStatus.zeroQuantity => '数量为 0，盈亏是已知 0。',
      PositionStatus.closedDay => '今日休市或停牌，今日浮动为 0，持有估值保留最近有效价。',
      PositionStatus.staleBaseline => '报价属于另一个交易日，今日基准失效。',
      PositionStatus.calendarUnknown => '交易日历未知，不猜测今日涨跌。',
      PositionStatus.missingBaseline => '来源没有提供基准价，今日浮动待更新。',
      PositionStatus.awaitingReferenceSession => '参考交易日尚未落到今天，等待同源基准。',
      PositionStatus.ok => '按当前持仓重估，不还原当日交易与费用。',
    };
    final quality = position.quote?.quality;
    final time = formatClock(position.quote?.quoteAtUtc, calendar);
    final qualityText = switch (quality) {
      QuoteQuality.live => '实时',
      QuoteQuality.delayed => '延时',
      QuoteQuality.eod => '日终',
      QuoteQuality.stale => '缓存陈旧',
      QuoteQuality.fixture => '模拟',
      QuoteQuality.unavailable => '不可用',
      null => '无报价',
    };
    return '$status $qualityText · 报价 $time';
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final PositionStatus status;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final (label, color) = switch (status) {
      PositionStatus.ok => ('正常', palette.positive),
      PositionStatus.pendingQuote => ('待报价', palette.negative),
      PositionStatus.zeroQuantity => ('空仓', palette.muted),
      PositionStatus.closedDay => ('休市', palette.muted),
      PositionStatus.staleBaseline => ('基准失效', palette.negative),
      PositionStatus.calendarUnknown => ('日历未知', palette.negative),
      PositionStatus.missingBaseline => ('缺基准', palette.negative),
      PositionStatus.awaitingReferenceSession => ('待夜盘', palette.muted),
    };
    return Container(
      margin: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(label, style: TextStyle(fontSize: 10, color: color)),
    );
  }
}
