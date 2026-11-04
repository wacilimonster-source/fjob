/// ONB-01 … ONB-07 六步首次引导。
library;

import 'package:finance_core/finance_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../domain/format.dart';
import '../../domain/setup_draft.dart';
import '../dashboard/office_scene.dart';
import 'onboarding_controller.dart';

class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key, this.redo = false});

  final bool redo;

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  String? _status;
  bool _attempted = false;
  bool _busy = false;

  static const List<String> _titles = <String>[
    '入职手续，生活替你准备好了。',
    '每个月，生活给你多少安慰费？',
    '你几点上线，又几点归还自己？',
    '除了上班，钱包还在哪几个战场？',
    '登记生活的固定嘉宾。',
    '这就是你的开局配置。',
  ];

  static const List<String> _leads = <String>[
    '花两分钟，让工资、行情和月供在同一间办公室相遇。',
    '填写到手月薪，我们把它拆成每个工作瞬间。',
    '工资按当月排班工时分摊，午休暂停计薪。',
    '有就填，没有就继续。生活的支线任务可以晚点接。',
    '住房三选一，车贷独立配置。固定支出按自然日分摊。',
    '填错也能回头改。人生至少在这里允许编辑。',
  ];

  static const List<String> _actions = <String>[
    '办理入职',
    '下一步，生活还在等',
    '给工资安排出场时间',
    '支线已登记，继续',
    '看看我的开局配置',
    '配置已阅，开始求生',
  ];

  void _edit(SetupDraft draft) {
    setState(() => _status = null);
    ref.read(onboardingControllerProvider.notifier).edit(draft);
  }

  Future<void> _advance() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _attempted = true;
    });
    try {
      final controller = ref.read(onboardingControllerProvider.notifier);
      final beforeStep =
          ref.read(onboardingControllerProvider).value?.step ?? 0;
      final error = await controller.next();
      if (!mounted) return;
      final afterStep = ref.read(onboardingControllerProvider).value?.step ?? 0;
      setState(() {
        _status = error;
        if (error == null && afterStep != beforeStep) _attempted = false;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _goBack() async {
    await ref.read(onboardingControllerProvider.notifier).back();
    setState(() {
      _status = null;
      _attempted = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final draftAsync = ref.watch(onboardingControllerProvider);
    return Scaffold(
      body: SafeArea(
        child: draftAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('草稿读不出来：$error'),
            ),
          ),
          data: (draft) {
            final step = draft.step.clamp(0, SetupDraft.stepCount - 1);
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(22, 18, 18, 0),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '欢迎加入人生有限公司',
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ),
                          if (widget.redo)
                            TextButton(
                              onPressed: _busy
                                  ? null
                                  : () async {
                                      await ref
                                          .read(onboardingControllerProvider
                                              .notifier)
                                          .cancelRedo();
                                    },
                              child: const Text('返回工位'),
                            ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 22),
                      child: Row(
                        children: [
                          for (var index = 0;
                              index < SetupDraft.stepCount;
                              index++) ...[
                            Expanded(
                              child: Container(
                                height: 5,
                                margin: const EdgeInsets.only(right: 6),
                                decoration: BoxDecoration(
                                  color: index <= step
                                      ? palette.positive
                                      : palette.line,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(22, 20, 22, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              _titles[step],
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineMedium
                                  ?.copyWith(fontSize: 25, height: 1.25),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              _leads[step],
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(height: 16),
                            _stepContent(draft, step),
                          ],
                        ),
                      ),
                    ),
                    if (_status != null && _status!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 22),
                        child: Text(
                          _status!,
                          style: TextStyle(
                            color: palette.negative,
                            fontSize: 12,
                            height: 1.5,
                          ),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(22, 10, 22, 18),
                      child: Row(
                        children: [
                          if (step > 0) ...[
                            OutlinedButton(
                              onPressed: _busy ? null : _goBack,
                              child: const Text('上一步'),
                            ),
                            const SizedBox(width: 10),
                          ],
                          Expanded(
                            child: FilledButton(
                              onPressed: _busy ? null : _advance,
                              child: Text(_busy ? '正在登记…' : _actions[step]),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _stepContent(SetupDraft draft, int step) => switch (step) {
        0 => _WelcomeStep(
            onDemo: () {
              ref.read(sampleModeProvider.notifier).state = true;
            },
          ),
        1 => _SalaryStep(
            draft: draft,
            attempted: _attempted,
            onChanged: _edit,
          ),
        2 => _ScheduleStep(
            draft: draft,
            attempted: _attempted,
            onChanged: _edit,
          ),
        3 => _AssetsStep(
            draft: draft,
            attempted: _attempted,
            onChanged: _edit,
          ),
        4 => _HousingStep(
            draft: draft,
            attempted: _attempted,
            onChanged: _edit,
          ),
        _ => _ReviewStep(
            draft: draft,
            onChanged: _edit,
            onJump: (target) => _edit(draft.copyWith(step: target)),
          ),
      };
}

class _WelcomeStep extends StatelessWidget {
  const _WelcomeStep({required this.onDemo});

  final VoidCallback onDemo;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: const OfficeScene(
            phase: DayPhase.working,
            completeness: Completeness.complete,
            total: null,
            reduceMotion: true,
          ),
        ),
        const SizedBox(height: 16),
        PaperCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('工资和排班必填，资产与固定支出按需添加。'),
              const SizedBox(height: 8),
              Text(
                '正式版默认把个人账本保存在设备本地。行情请求只发送标的 ID，'
                '不上传工资、持仓数量与成本。',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.8),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: onDemo,
          child: const Text('先替示例打工人焦虑一下'),
        ),
      ],
    );
  }
}

class _SalaryStep extends StatelessWidget {
  const _SalaryStep({
    required this.draft,
    required this.attempted,
    required this.onChanged,
  });

  final SetupDraft draft;
  final bool attempted;
  final ValueChanged<SetupDraft> onChanged;

  @override
  Widget build(BuildContext context) {
    final validation = draft.validate();
    final error = draft.salaryText.isEmpty && !attempted
        ? null
        : validation.errorFor('salary');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          initialValue: draft.salaryText,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
          ],
          decoration: InputDecoration(
            labelText: '到手月薪 / 元',
            hintText: '例如 12000',
            errorText: error,
          ),
          onChanged: (value) => onChanged(draft.copyWith(salaryText: value)),
        ),
        const SizedBox(height: 12),
        TextFormField(
          initialValue: draft.salaryEffectiveDate,
          keyboardType: TextInputType.datetime,
          decoration: InputDecoration(
            labelText: '生效日期',
            hintText: 'YYYY-MM-DD',
            errorText: attempted
                ? validation.errorFor('salaryEffectiveDate')
                : null,
          ),
          onChanged: (value) =>
              onChanged(draft.copyWith(salaryEffectiveDate: value)),
        ),
        const SizedBox(height: 12),
        Text(
          '可以填 0。人生偶尔缓冲，也值得被认真记录。生效日期默认当月首日，可修改。',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _ScheduleStep extends ConsumerStatefulWidget {
  const _ScheduleStep({
    required this.draft,
    required this.attempted,
    required this.onChanged,
  });

  final SetupDraft draft;
  final bool attempted;
  final ValueChanged<SetupDraft> onChanged;

  @override
  ConsumerState<_ScheduleStep> createState() => _ScheduleStepState();
}

class _ScheduleStepState extends ConsumerState<_ScheduleStep> {
  ({int days, int seconds})? _preview() {
    try {
      final calendar = ref.read(calendarProvider);
      final week = widget.draft.buildWeek();
      final schedule = ScheduleVersion(
        id: 'preview',
        timezone: calendar.timezoneName,
        week: week,
        effectiveFromUtc: DateTime.utc(2020),
      );
      final calculator = WageCalculator(calendar);
      final anchor = calendar.dateOf(ref.read(clockProvider).nowUtc());
      return (
        days: calculator.expander.monthlyPaidDays(
          version: schedule,
          overrides: const [],
          anchor: anchor,
        ),
        seconds: calculator.expander.monthlyPaidSeconds(
          version: schedule,
          overrides: const [],
          anchor: anchor,
        ),
      );
    } on Object {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final draft = widget.draft;
    final validation = draft.validate();
    final preview = _preview();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (var index = 0; index < 7; index++)
              _DayChip(
                label: weekdayLabel(index + 1),
                selected: draft.workdays[index],
                onTap: () {
                  final next = [...draft.workdays];
                  next[index] = !next[index];
                  widget.onChanged(draft.copyWith(workdays: next));
                },
              ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: _TimeField(
                label: '上班时间',
                initial: draft.shiftStart,
                onChanged: (value) =>
                    widget.onChanged(draft.copyWith(shiftStart: value)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _TimeField(
                label: '下班时间',
                initial: draft.shiftEnd,
                onChanged: (value) =>
                    widget.onChanged(draft.copyWith(shiftEnd: value)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          '下班时间不晚于上班时间时按次日下班处理，可录入跨夜班。',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('有午休，不计薪'),
          value: draft.breakEnabled,
          onChanged: (value) =>
              widget.onChanged(draft.copyWith(breakEnabled: value)),
        ),
        if (draft.breakEnabled)
          Row(
            children: [
              Expanded(
                child: _TimeField(
                  label: '午休开始',
                  initial: draft.breakStart,
                  onChanged: (value) =>
                      widget.onChanged(draft.copyWith(breakStart: value)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _TimeField(
                  label: '午休结束',
                  initial: draft.breakEnd,
                  onChanged: (value) =>
                      widget.onChanged(draft.copyWith(breakEnd: value)),
                ),
              ),
            ],
          ),
        const SizedBox(height: 12),
        PaperCard(
          color: palette.soft,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  preview == null
                      ? '排班还差一点，先检查上下班与午休时间。'
                      : '本月计薪 ${preview.days} 天 · '
                          '总计薪 ${formatHours(preview.seconds)} 小时',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ],
          ),
        ),
        if (widget.attempted && validation.errorFor('schedule') != null) ...[
          const SizedBox(height: 8),
          Text(
            validation.errorFor('schedule')!,
            style: TextStyle(color: palette.negative, fontSize: 12),
          ),
        ],
        const SizedBox(height: 8),
        Text(
          '工作日历与证券交易日历相互独立。法定节假日与调休可在正式版本按日历导入。',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _DayChip extends StatelessWidget {
  const _DayChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minWidth: 44, minHeight: 40),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? palette.soft : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? palette.line : palette.line.withValues(alpha: 0.4),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: selected ? palette.ink : palette.muted,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

class _TimeField extends StatelessWidget {
  const _TimeField({
    required this.label,
    required this.initial,
    required this.onChanged,
  });

  final String label;
  final String initial;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => TextFormField(
        initialValue: initial,
        keyboardType: TextInputType.datetime,
        decoration: InputDecoration(labelText: label, hintText: 'HH:mm'),
        onChanged: onChanged,
      );
}

class _AssetsStep extends StatelessWidget {
  const _AssetsStep({
    required this.draft,
    required this.attempted,
    required this.onChanged,
  });

  final SetupDraft draft;
  final bool attempted;
  final ValueChanged<SetupDraft> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final validation = draft.validate();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < draft.holdings.length; index++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: PaperCard(
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${draft.holdings[index].market.label} '
                          '${draft.holdings[index].code.isEmpty ? '未填写代码' : draft.holdings[index].code}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${draft.holdings[index].quantityText.isEmpty ? '—' : draft.holdings[index].quantityText} 股 · '
                          '成本 ${draft.holdings[index].costText.isEmpty ? '—' : draft.holdings[index].costText} 元',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: '编辑持仓',
                    onPressed: () async {
                      final edited = await showHoldingEditor(
                        context,
                        initial: draft.holdings[index],
                      );
                      if (edited == null) return;
                      final next = [...draft.holdings]..[index] = edited;
                      onChanged(draft.copyWith(holdings: next));
                    },
                    icon: const Icon(Icons.edit_outlined, size: 19),
                  ),
                  IconButton(
                    tooltip: '删除持仓',
                    onPressed: () {
                      final next = [...draft.holdings]..removeAt(index);
                      onChanged(draft.copyWith(holdings: next));
                    },
                    icon: Icon(Icons.close, size: 18, color: palette.muted),
                  ),
                ],
              ),
            ),
          ),
        OutlinedButton.icon(
          onPressed: () async {
            final created = await showHoldingEditor(context);
            if (created == null) return;
            onChanged(
              draft.copyWith(holdings: [...draft.holdings, created]),
            );
          },
          icon: const Icon(Icons.add, size: 18),
          label: const Text('添加一只A股'),
        ),
        if (attempted && validation.errorFor('holdings') != null) ...[
          const SizedBox(height: 8),
          Text(
            validation.errorFor('holdings')!,
            style: TextStyle(color: palette.negative, fontSize: 12),
          ),
        ],
        const SizedBox(height: 16),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('我有按克持有的黄金'),
          value: draft.goldEnabled,
          onChanged: (value) => onChanged(draft.copyWith(goldEnabled: value)),
        ),
        if (draft.goldEnabled)
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: draft.goldQuantityText,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: '克重 / 克',
                    hintText: '20',
                  ),
                  onChanged: (value) => onChanged(
                    draft.copyWith(goldQuantityText: value),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextFormField(
                  initialValue: draft.goldCostText,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: '成本 / 元每克',
                    hintText: '850',
                  ),
                  onChanged: (value) =>
                      onChanged(draft.copyWith(goldCostText: value)),
                ),
              ),
            ],
          ),
        if (attempted && validation.errorFor('gold') != null) ...[
          const SizedBox(height: 8),
          Text(
            validation.errorFor('gold')!,
            style: TextStyle(color: palette.negative, fontSize: 12),
          ),
        ],
        const SizedBox(height: 10),
        Text(
          '报价由模拟行情提供并标注来源。正式版自动获取同源前收参考价；'
          '网络失败时保留持仓，报价显示待更新。',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _HousingStep extends StatelessWidget {
  const _HousingStep({
    required this.draft,
    required this.attempted,
    required this.onChanged,
  });

  final SetupDraft draft;
  final bool attempted;
  final ValueChanged<SetupDraft> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final validation = draft.validate();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ChoiceChip(
          label: const Text('暂无，生活暂时放过这一项'),
          selected: draft.housingMode == HousingMode.none,
          onSelected: (_) =>
              onChanged(draft.copyWith(housingMode: HousingMode.none)),
        ),
        const SizedBox(height: 6),
        ChoiceChip(
          label: const Text('房贷，每月还一点自己的家'),
          selected: draft.housingMode == HousingMode.mortgage,
          onSelected: (_) =>
              onChanged(draft.copyWith(housingMode: HousingMode.mortgage)),
        ),
        const SizedBox(height: 6),
        ChoiceChip(
          label: const Text('房租，给疲惫的自己续个住'),
          selected: draft.housingMode == HousingMode.rent,
          onSelected: (_) =>
              onChanged(draft.copyWith(housingMode: HousingMode.rent)),
        ),
        const SizedBox(height: 14),
        if (draft.housingMode == HousingMode.mortgage)
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: draft.mortgageMonthlyText,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: '本月月供 / 元'),
                  onChanged: (value) =>
                      onChanged(draft.copyWith(mortgageMonthlyText: value)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextFormField(
                  initialValue: draft.mortgagePrincipalText,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: '其中本金 / 元（选填）',
                    hintText: '未知可留空',
                  ),
                  onChanged: (value) =>
                      onChanged(draft.copyWith(mortgagePrincipalText: value)),
                ),
              ),
            ],
          ),
        if (draft.housingMode == HousingMode.rent)
          TextFormField(
            initialValue: draft.rentMonthlyText,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: '本月租金 / 元',
              hintText: '季付或年付先换算成对应月金额',
            ),
            onChanged: (value) =>
                onChanged(draft.copyWith(rentMonthlyText: value)),
          ),
        if (attempted && validation.errorFor('housing') != null) ...[
          const SizedBox(height: 8),
          Text(
            validation.errorFor('housing')!,
            style: TextStyle(color: palette.negative, fontSize: 12),
          ),
        ],
        const SizedBox(height: 16),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('车贷也有固定席位'),
          value: draft.carEnabled,
          onChanged: (value) => onChanged(draft.copyWith(carEnabled: value)),
        ),
        if (draft.carEnabled)
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: draft.carMonthlyText,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: '本月车贷 / 元'),
                  onChanged: (value) =>
                      onChanged(draft.copyWith(carMonthlyText: value)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextFormField(
                  initialValue: draft.carPrincipalText,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: '其中本金 / 元（选填）',
                    hintText: '未知可留空',
                  ),
                  onChanged: (value) =>
                      onChanged(draft.copyWith(carPrincipalText: value)),
                ),
              ),
            ],
          ),
        if (attempted && validation.errorFor('car') != null) ...[
          const SizedBox(height: 8),
          Text(
            validation.errorFor('car')!,
            style: TextStyle(color: palette.negative, fontSize: 12),
          ),
        ],
        const SizedBox(height: 10),
        Text(
          '房贷、房租或暂无三选一；贷款本金未知时明细显示待补充，月供仍全额计入压力。'
          '填写 0 本金表示用户明确确认当月本金为 0。',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _ReviewStep extends StatelessWidget {
  const _ReviewStep({
    required this.draft,
    required this.onChanged,
    required this.onJump,
  });

  final SetupDraft draft;
  final ValueChanged<SetupDraft> onChanged;
  final ValueChanged<int> onJump;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final validation = draft.validate();
    final salary = Rational.tryParse(draft.salaryText.trim());
    final monthStats = _monthStats(context, draft);
    final holdingsText = draft.holdings.isEmpty
        ? '暂无A股'
        : '${draft.holdings.length} 只A股';
    final goldText = draft.goldEnabled
        ? '${draft.goldQuantityText.isEmpty ? '—' : draft.goldQuantityText} 克黄金'
        : '暂无黄金';
    final housingText = switch (draft.housingMode) {
      HousingMode.mortgage =>
        '房贷 ${formatMoney(Rational.tryParse(draft.mortgageMonthlyText))}',
      HousingMode.rent =>
        '房租 ${formatMoney(Rational.tryParse(draft.rentMonthlyText))}',
      HousingMode.none => '暂无住房支出',
    };
    final carText = draft.carEnabled
        ? '车贷 ${formatMoney(Rational.tryParse(draft.carMonthlyText))}'
        : '无车贷';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SummaryRow(
          label: '到手月薪',
          value: formatMoney(salary),
          onEdit: () => onJump(1),
        ),
        _SummaryRow(
          label: '生效日期',
          value: draft.salaryEffectiveDate,
          onEdit: () => onJump(1),
        ),
        _SummaryRow(
          label: '本月排班',
          value: monthStats == null
              ? '排班待补充'
              : '${monthStats.$1} 天 · ${formatHours(monthStats.$2)} 小时',
          onEdit: () => onJump(2),
        ),
        _SummaryRow(
          label: '计薪时区',
          value: 'Asia/Shanghai',
          onEdit: () => onJump(2),
        ),
        _SummaryRow(
          label: '资产支线',
          value: '$holdingsText / $goldText',
          onEdit: () => onJump(3),
        ),
        _SummaryRow(
          label: '住房方式',
          value: housingText,
          onEdit: () => onJump(4),
        ),
        _SummaryRow(
          label: '车贷',
          value: carText,
          onEdit: () => onJump(4),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('小部件默认隐藏金额'),
          subtitle: Text(
            '开启后快照金额、界面与可访问文案同时遮蔽。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          value: draft.widgetPrivacy,
          onChanged: (value) => onChanged(draft.copyWith(widgetPrivacy: value)),
        ),
        if (!validation.isValid && validation.firstError.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              validation.firstError,
              style: TextStyle(color: palette.negative, fontSize: 12),
            ),
          ),
        const SizedBox(height: 8),
        Text(
          '确认后会一次性写入配置、持仓与账单。之后仍可逐项修改，'
          '历史估算携带对应配置版本。',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  (int, int)? _monthStats(BuildContext context, SetupDraft draft) {
    try {
      final container = ProviderScope.containerOf(context);
      final calendar = container.read(calendarProvider);
      final clock = container.read(clockProvider);
      final week = draft.buildWeek();
      final schedule = ScheduleVersion(
        id: 'review',
        timezone: calendar.timezoneName,
        week: week,
        effectiveFromUtc: DateTime.utc(2020),
      );
      final calculator = WageCalculator(calendar);
      final anchor = calendar.dateOf(clock.nowUtc());
      return (
        calculator.expander.monthlyPaidDays(
          version: schedule,
          overrides: const [],
          anchor: anchor,
        ),
        calculator.expander.monthlyPaidSeconds(
          version: schedule,
          overrides: const [],
          anchor: anchor,
        ),
      );
    } on Object {
      return null;
    }
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.value,
    required this.onEdit,
  });

  final String label;
  final String value;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: palette.line)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 2),
                Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          TextButton(onPressed: onEdit, child: const Text('修改')),
        ],
      ),
    );
  }
}

/// Add/edit sheet for one A-share holding.
Future<HoldingDraft?> showHoldingEditor(
  BuildContext context, {
  HoldingDraft? initial,
}) {
  return showModalBottomSheet<HoldingDraft>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.palette.panel,
    builder: (context) => _HoldingSheet(initial: initial),
  );
}

class _HoldingSheet extends StatefulWidget {
  const _HoldingSheet({this.initial});

  final HoldingDraft? initial;

  @override
  State<_HoldingSheet> createState() => _HoldingSheetState();
}

class _HoldingSheetState extends State<_HoldingSheet> {
  late StockMarket _market = widget.initial?.market ?? StockMarket.szse;
  late final TextEditingController _code =
      TextEditingController(text: widget.initial?.code ?? '');
  late final TextEditingController _name =
      TextEditingController(text: widget.initial?.name ?? '');
  late final TextEditingController _quantity =
      TextEditingController(text: widget.initial?.quantityText ?? '');
  late final TextEditingController _cost =
      TextEditingController(text: widget.initial?.costText ?? '');
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    _quantity.dispose();
    _cost.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                widget.initial == null ? '添加A股持仓' : '修改持仓',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Spacer(),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          DropdownButtonFormField<StockMarket>(
            initialValue: _market,
            decoration: const InputDecoration(labelText: '市场'),
            items: [
              for (final market in StockMarket.values)
                DropdownMenuItem(value: market, child: Text(market.label)),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _market = value);
            },
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _code,
            keyboardType: TextInputType.number,
            maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: '证券代码',
              hintText: '6 位数字，例如 000001',
              counterText: '',
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _name,
            decoration: const InputDecoration(
              labelText: '名称（选填）',
              hintText: '例如 平安银行',
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _quantity,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: '持仓 / 股'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _cost,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  decoration: const InputDecoration(labelText: '成本 / 元'),
                ),
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: palette.negative, fontSize: 12)),
          ],
          const SizedBox(height: 14),
          FilledButton(
            onPressed: () {
              if (!RegExp(r'^\d{6}$').hasMatch(_code.text.trim())) {
                setState(() => _error = '证券代码是 6 位数字，请核对。');
                return;
              }
              if (_quantity.text.trim().isEmpty || _cost.text.trim().isEmpty) {
                setState(() => _error = '请填写股数和每股成本。');
                return;
              }
              Navigator.of(context).pop(
                HoldingDraft(
                  market: _market,
                  code: _code.text.trim(),
                  name: _name.text.trim(),
                  quantityText: _quantity.text.trim(),
                  costText: _cost.text.trim(),
                ),
              );
            },
            child: const Text('保存持仓'),
          ),
        ],
      ),
    );
  }
}
