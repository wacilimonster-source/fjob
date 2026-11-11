/// EXPENSE-01 固定牵挂。
library;

import 'package:finance_core/finance_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import 'package:fjob_ui/fjob_ui.dart';
import 'package:ledger_model/ledger_model.dart';
import '../ledger/ledger_controller.dart';

class ExpensesPage extends ConsumerWidget {
  const ExpensesPage({super.key, this.focusCar = false});

  final bool focusCar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final snapshot = ref.watch(dashboardProvider).value;
    final ledger = ref.watch(effectiveLedgerProvider).value;
    final calendar = ref.watch(calendarProvider);
    final sample = ref.watch(sampleModeProvider);
    final busy = ref.watch(busyProvider);
    final now = ref.watch(clockProvider).nowUtc();
    final today = calendar.dateOf(now);
    final month = today.firstOfMonth;

    final housing = snapshot?.housingDetail;
    final car = snapshot?.carDetail;
    final daily = (housing?.dayShare ?? Rational.zero) +
        (car?.dayShare ?? Rational.zero);
    final housingPlanId = housing?.activePlanId;
    final housingBill = ledger == null || housingPlanId == null
        ? null
        : _billFor(ledger, housingPlanId, month);
    final carPlanId = car?.activePlanId;
    final carBill = ledger == null || carPlanId == null
        ? null
        : _billFor(ledger, carPlanId, month);

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
                    Text('生活的固定节目',
                        style: Theme.of(context).textTheme.headlineMedium),
                    const SizedBox(height: 4),
                    Text(
                      '自然日全天分摊 · 周末照常营业'
                      '${sample ? ' · 示例模式只读' : ''}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 16),
                    PaperCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('每天醒来的基础负担'),
                          const SizedBox(height: 4),
                          MoneyText(formatMoney(daily), size: 34),
                          const SizedBox(height: 4),
                          Text(
                            '本月 ${snapshot?.monthDays ?? 30} 天 · '
                            '每分钟约 ${formatMoney(daily / Rational.fromInt(1440))}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (snapshot == null || ledger == null)
                      const PaperCard(child: Text('账本还在加载…'))
                    else ...[
                      _HousingEditor(
                        key: ValueKey(
                          'housing-${ledger.settings.ledgerRevision}',
                        ),
                        mode: housing?.housingMode ?? HousingMode.none,
                        amountText:
                            housingBill?.monthlyAmountCny?.toCanonicalString() ?? '',
                        principalText:
                            housingBill?.principalCny?.toCanonicalString() ?? '',
                        billIsEstimate:
                            housingBill?.status == BillStatus.carriedForwardEstimate,
                        enabled: !sample && !busy,
                        onSave: (mode, amount, principal, fromMonthStart) async {
                          try {
                            await ref
                                .read(ledgerControllerProvider.notifier)
                                .saveHousing(
                                  mode: mode,
                                  monthlyAmount: amount,
                                  principal: principal,
                                  effectiveFrom:
                                      fromMonthStart ? month : today,
                                  billMonth: month,
                                );
                          } on LedgerActionException catch (error) {
                            if (context.mounted) _snack(context, error.message);
                          }
                          await ref
                              .read(ledgerControllerProvider.notifier)
                              .refreshQuotes();
                        },
                      ),
                      const SizedBox(height: 12),
                      _HousingFigures(breakdown: housing),
                      const SizedBox(height: 18),
                      _CarEditor(
                        key: ValueKey('car-${ledger.settings.ledgerRevision}'),
                        enabled: car?.configured ?? false,
                        amountText:
                            carBill?.monthlyAmountCny?.toCanonicalString() ?? '',
                        principalText:
                            carBill?.principalCny?.toCanonicalString() ?? '',
                        editable: !sample && !busy,
                        focus: focusCar,
                        onSave: (enabled, amount, principal, fromMonthStart) async {
                          try {
                            await ref
                                .read(ledgerControllerProvider.notifier)
                                .saveCar(
                                  enabled: enabled,
                                  monthlyAmount: amount,
                                  principal: principal,
                                  effectiveFrom:
                                      fromMonthStart ? month : today,
                                  billMonth: month,
                                );
                          } on LedgerActionException catch (error) {
                            if (context.mounted) _snack(context, error.message);
                          }
                          await ref
                              .read(ledgerControllerProvider.notifier)
                              .refreshQuotes();
                        },
                      ),
                      const SizedBox(height: 12),
                      _CarFigures(breakdown: car),
                    ],
                    const SizedBox(height: 20),
                    Text(
                      '贷款本金减少负债，但在压力视图中仍计入月供分摊。'
                      '本金未知时拆分显示待补充；填写 0 表示明确确认当月本金为 0。'
                      '房租独立标记为租金，不计为贷款利息。',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            height: 1.8,
                            color: palette.muted,
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

  static MonthlyBill? _billFor(
    LedgerState ledger,
    String planId,
    LocalDate month,
  ) {
    MonthlyBill? found;
    for (final bill in ledger.bills) {
      if (bill.expenseId == planId && bill.month == month) found = bill;
    }
    return found;
  }

  static void _snack(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

class _HousingEditor extends StatefulWidget {
  const _HousingEditor({
    super.key,
    required this.mode,
    required this.amountText,
    required this.principalText,
    required this.billIsEstimate,
    required this.enabled,
    required this.onSave,
  });

  final HousingMode mode;
  final String amountText;
  final String principalText;
  final bool billIsEstimate;
  final bool enabled;
  final Future<void> Function(
    HousingMode mode,
    Rational? amount,
    Rational? principal,
    bool fromMonthStart,
  ) onSave;

  @override
  State<_HousingEditor> createState() => _HousingEditorState();
}

class _HousingEditorState extends State<_HousingEditor> {
  late HousingMode _mode = widget.mode;
  late final TextEditingController _amount =
      TextEditingController(text: widget.amountText);
  late final TextEditingController _principal =
      TextEditingController(text: widget.principalText);
  bool _fromMonthStart = true;
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _amount.dispose();
    _principal.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_mode == HousingMode.none) {
      setState(() => _saving = true);
      await widget.onSave(HousingMode.none, null, null, _fromMonthStart);
      if (mounted) setState(() => _saving = false);
      return;
    }
    final amount = _parse(_amount.text);
    final principal = _principal.text.trim().isEmpty
        ? null
        : _parse(_principal.text);
    if (amount == null || amount.isNegative) {
      setState(() => _error = '请填写有效金额，最多两位小数。');
      return;
    }
    if (principal != null && principal.isNegative) {
      setState(() => _error = '本金需要是非负金额，或留空表示未知。');
      return;
    }
    if (principal != null && principal > amount) {
      setState(() => _error =
          '本金超过了本月月供，请核对账单。生活暂时还没学会这个算法。');
      return;
    }
    setState(() {
      _error = null;
      _saving = true;
    });
    await widget.onSave(_mode, amount, principal, _fromMonthStart);
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final editable = widget.enabled && !_saving;
    return PaperCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('住房', style: TextStyle(fontWeight: FontWeight.w600)),
              const Spacer(),
              Text(
                widget.billIsEstimate ? '沿用上期估算' : '本月账单',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Center(child: DebtArt(type: DebtArtType.house, height: 92)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final mode in HousingMode.values)
                ChoiceChip(
                  label: Text(switch (mode) {
                    HousingMode.mortgage => '房贷',
                    HousingMode.rent => '房租',
                    HousingMode.none => '暂无',
                  }),
                  selected: _mode == mode,
                  onSelected:
                      editable ? (_) => setState(() => _mode = mode) : null,
                ),
            ],
          ),
          if (_mode != HousingMode.none) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _amount,
                    enabled: editable,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                    ],
                    decoration: InputDecoration(
                      labelText: _mode == HousingMode.rent ? '本月租金 / 元' : '本月月供 / 元',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _principal,
                    enabled: editable && _mode == HousingMode.mortgage,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                    ],
                    decoration: InputDecoration(
                      labelText: _mode == HousingMode.mortgage
                          ? '其中本金 / 元'
                          : '本金不适用',
                      hintText: _mode == HousingMode.mortgage ? '未知可留空' : null,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _fromMonthStart ? '从本月首日重算' : '从今天生效',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                TextButton(
                  onPressed: editable
                      ? () => setState(() => _fromMonthStart = !_fromMonthStart)
                      : null,
                  child: Text(_fromMonthStart ? '改成今天生效' : '改成本月首日'),
                ),
              ],
            ),
          ],
          if (_error != null)
            Text(_error!, style: TextStyle(color: palette.negative, fontSize: 12)),
          const SizedBox(height: 10),
          FilledButton(
            onPressed: editable ? _save : null,
            child: Text(_saving ? '正在登记…' : '保存住房账单'),
          ),
        ],
      ),
    );
  }

  static Rational? _parse(String raw) {
    final text = raw.trim();
    if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(text)) return null;
    return Rational.parse(text);
  }
}

class _HousingFigures extends StatelessWidget {
  const _HousingFigures({required this.breakdown});

  final ExpenseBreakdown? breakdown;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final value = breakdown;
    if (value == null || !value.configured) {
      return Text('住房分项为 0，不暗示存在贷款。',
          style: Theme.of(context).textTheme.bodySmall);
    }
    return PaperCard(
      color: palette.soft,
      child: Column(
        children: [
          _FigureRow('本月对应', formatMoney(value.monthlyAmount)),
          _FigureRow('每日分摊', formatMoney(value.dayShare)),
          _FigureRow('今日已分摊', formatMoney(value.dayAmount)),
          _FigureRow('本月累计分摊', formatMoney(value.monthToDateAmount)),
          if (value.isRent)
            _FigureRow('租金（独立）', formatMoney(value.dayRent))
          else ...[
            _FigureRow('今日本金', formatMoney(value.dayPrincipal)),
            _FigureRow('今日利息', formatMoney(value.dayInterest)),
          ],
        ],
      ),
    );
  }
}

class _CarEditor extends StatefulWidget {
  const _CarEditor({
    super.key,
    required this.enabled,
    required this.amountText,
    required this.principalText,
    required this.editable,
    required this.focus,
    required this.onSave,
  });

  final bool enabled;
  final String amountText;
  final String principalText;
  final bool editable;
  final bool focus;
  final Future<void> Function(
    bool enabled,
    Rational? amount,
    Rational? principal,
    bool fromMonthStart,
  ) onSave;

  @override
  State<_CarEditor> createState() => _CarEditorState();
}

class _CarEditorState extends State<_CarEditor> {
  late bool _enabled = widget.enabled;
  late final TextEditingController _amount =
      TextEditingController(text: widget.amountText);
  late final TextEditingController _principal =
      TextEditingController(text: widget.principalText);
  bool _fromMonthStart = true;
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _amount.dispose();
    _principal.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!_enabled) {
      setState(() => _saving = true);
      await widget.onSave(false, null, null, _fromMonthStart);
      if (mounted) setState(() => _saving = false);
      return;
    }
    final amount = _parse(_amount.text);
    final principal = _principal.text.trim().isEmpty
        ? null
        : _parse(_principal.text);
    if (amount == null || amount.isNegative) {
      setState(() => _error = '请填写有效车贷金额，最多两位小数。');
      return;
    }
    if (principal != null && (principal.isNegative || principal > amount)) {
      setState(() => _error = '本金必须在 0 与月供之间，或留空表示未知。');
      return;
    }
    setState(() {
      _error = null;
      _saving = true;
    });
    await widget.onSave(true, amount, principal, _fromMonthStart);
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final editable = widget.editable && !_saving;
    return PaperCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('车辆贷款', style: TextStyle(fontWeight: FontWeight.w600)),
              const Spacer(),
              Switch(
                value: _enabled,
                onChanged: editable
                    ? (value) => setState(() => _enabled = value)
                    : null,
              ),
            ],
          ),
          Center(child: DebtArt(type: DebtArtType.car, height: 82)),
          if (_enabled) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _amount,
                    enabled: editable,
                    autofocus: widget.focus,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                    ],
                    decoration:
                        const InputDecoration(labelText: '本月车贷 / 元'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _principal,
                    enabled: editable,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                    ],
                    decoration: const InputDecoration(
                      labelText: '其中本金 / 元',
                      hintText: '未知可留空',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _fromMonthStart ? '从本月首日重算' : '从今天生效',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                TextButton(
                  onPressed: editable
                      ? () => setState(() => _fromMonthStart = !_fromMonthStart)
                      : null,
                  child: Text(_fromMonthStart ? '改成今天生效' : '改成本月首日'),
                ),
              ],
            ),
          ],
          if (_error != null)
            Text(_error!, style: TextStyle(color: palette.negative, fontSize: 12)),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: editable ? _save : null,
            child: Text(_saving ? '正在登记…' : '保存车贷账单'),
          ),
        ],
      ),
    );
  }

  static Rational? _parse(String raw) {
    final text = raw.trim();
    if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(text)) return null;
    return Rational.parse(text);
  }
}

class _CarFigures extends StatelessWidget {
  const _CarFigures({required this.breakdown});

  final ExpenseBreakdown? breakdown;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final value = breakdown;
    if (value == null || !value.configured) {
      return Text('车贷未配置，分项为 0。',
          style: Theme.of(context).textTheme.bodySmall);
    }
    return PaperCard(
      color: palette.soft,
      child: Column(
        children: [
          _FigureRow('本月对应', formatMoney(value.monthlyAmount)),
          _FigureRow('每日分摊', formatMoney(value.dayShare)),
          _FigureRow('今日已分摊', formatMoney(value.dayAmount)),
          _FigureRow('本月累计分摊', formatMoney(value.monthToDateAmount)),
          _FigureRow('今日本金', formatMoney(value.dayPrincipal)),
          _FigureRow('今日利息', formatMoney(value.dayInterest)),
        ],
      ),
    );
  }
}

class _FigureRow extends StatelessWidget {
  const _FigureRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Expanded(
              child: Text(label, style: Theme.of(context).textTheme.bodySmall),
            ),
            Text(value, style: const TextStyle(fontSize: 13)),
          ],
        ),
      );
}
