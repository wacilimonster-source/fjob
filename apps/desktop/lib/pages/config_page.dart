/// M9-PC2 配置页：收入与排班 / 资产 / 住房与车贷 / 账单四个子页签。
///
/// 左侧表单 + 右侧固定窗实时预览。预览只做本地计算（消费当前账本并覆盖正在
/// 编辑的字段），不写库、不请求行情；保存统一走 [LedgerController]，由其处理
/// expectedRevision 与忙锁。金额、数量与盈亏全部来自 finance_core 快照。
library;

import 'package:finance_core/finance_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fjob_ui/fjob_ui.dart';
import 'package:ledger_model/ledger_model.dart';
import 'package:ledger_store/ledger_store.dart';
import 'package:market_data/market_data.dart';

import '../state/ledger_controller.dart';
import '../state/providers.dart';
import '../widgets/fixed_card_view.dart';

final Rational _maxMoney = Rational.parse('10000000');
final Rational _maxCost = Rational.parse('100000');
final Rational _maxGoldQuantity = Rational.parse('1000000');
final Rational _maxFundQuantity = Rational.parse('10000000');

class ConfigPage extends ConsumerStatefulWidget {
  const ConfigPage({super.key});

  @override
  ConsumerState<ConfigPage> createState() => _ConfigPageState();
}

class _ConfigPageState extends ConsumerState<ConfigPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  final TextEditingController _salary = TextEditingController();
  final TextEditingController _shiftStart = TextEditingController(
    text: '09:00',
  );
  final TextEditingController _shiftEnd = TextEditingController(text: '18:00');
  final TextEditingController _breakStart = TextEditingController(
    text: '12:00',
  );
  final TextEditingController _breakEnd = TextEditingController(text: '13:00');
  final TextEditingController _housingMonthly = TextEditingController();
  final TextEditingController _housingPrincipal = TextEditingController();
  final TextEditingController _carMonthly = TextEditingController();
  final TextEditingController _carPrincipal = TextEditingController();

  List<bool> _workdays = <bool>[true, true, true, true, true, false, false];
  bool _breakEnabled = true;
  bool _overnight = false;
  LocalDate? _salaryEffective;

  HousingMode _housingMode = HousingMode.none;
  LocalDate? _housingEffective;
  LocalDate? _housingBillMonth;

  bool _carEnabled = false;
  LocalDate? _carEffective;
  LocalDate? _carBillMonth;

  LocalDate _billMonth = const LocalDate(2026, 1, 1);

  bool _dirtyIncome = false;
  bool _dirtyHousing = false;
  bool _dirtyCar = false;
  bool _attemptedIncome = false;
  bool _attemptedHousing = false;
  bool _attemptedCar = false;
  int _seenRevision = -1;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    final LocalDate today = ref
        .read(calendarProvider)
        .dateOf(ref.read(clockProvider).nowUtc());
    _salaryEffective = today.firstOfMonth;
    _housingEffective = today.firstOfMonth;
    _housingBillMonth = today.firstOfMonth;
    _carEffective = today.firstOfMonth;
    _carBillMonth = today.firstOfMonth;
    _billMonth = today.firstOfMonth;
  }

  @override
  void dispose() {
    _tabs.dispose();
    _salary.dispose();
    _shiftStart.dispose();
    _shiftEnd.dispose();
    _breakStart.dispose();
    _breakEnd.dispose();
    _housingMonthly.dispose();
    _housingPrincipal.dispose();
    _carMonthly.dispose();
    _carPrincipal.dispose();
    super.dispose();
  }

  LocalDate _today() =>
      ref.read(calendarProvider).dateOf(ref.read(clockProvider).nowUtc());

  // ---------------------------------------------------------------------------
  // 账本 -> 表单同步（仅在对应分区没有未保存编辑时回填，避免覆盖用户输入）。
  // ---------------------------------------------------------------------------

  void _maybeSync(LedgerState? ledger) {
    if (ledger == null) return;
    final int revision = ledger.settings.ledgerRevision;
    if (revision == _seenRevision) return;
    _seenRevision = revision;
    final bool income = !_dirtyIncome;
    final bool housing = !_dirtyHousing;
    final bool car = !_dirtyCar;
    if (!income && !housing && !car) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        if (income) _syncIncome(ledger);
        if (housing) _syncHousing(ledger);
        if (car) _syncCar(ledger);
      });
    });
  }

  SalaryVersion? _activeSalary(LedgerState ledger, DateTime now) {
    SalaryVersion? active;
    for (final SalaryVersion version in ledger.salaryVersions) {
      if (!version.covers(now)) continue;
      if (active == null ||
          version.effectiveFromUtc.isAfter(active.effectiveFromUtc)) {
        active = version;
      }
    }
    return active ?? ledger.currentSalary;
  }

  void _syncIncome(LedgerState ledger) {
    final DateTime now = ref.read(clockProvider).nowUtc();
    final SalaryVersion? salary = _activeSalary(ledger, now);
    final ScheduleVersion? schedule = salary == null
        ? null
        : ledger.schedules[salary.scheduleVersionId];
    _salary.text = salary?.monthlyNetCny.toCanonicalString(maxScale: 2) ?? '';
    _salaryEffective = ref.read(calendarProvider).dateOf(now).firstOfMonth;
    final WeekTemplate? week =
        schedule?.alternation?.smallWeek ?? schedule?.week;
    _workdays = List<bool>.filled(7, false);
    _shiftStart.text = '09:00';
    _shiftEnd.text = '18:00';
    _breakStart.text = '12:00';
    _breakEnd.text = '13:00';
    _breakEnabled = true;
    _overnight = false;
    if (week == null) return;
    ShiftTemplate? first;
    for (int index = 0; index < 7; index++) {
      final List<ShiftTemplate> shifts = week.byWeekday[index];
      _workdays[index] = shifts.isNotEmpty;
      first ??= shifts.isEmpty ? null : shifts.first;
    }
    if (first == null) return;
    _shiftStart.text = _clockText(first.startMinute);
    _shiftEnd.text = _clockText(first.endMinute);
    _overnight = first.endMinute > 1440;
    if (first.breaks.isEmpty) {
      _breakEnabled = false;
    } else {
      _breakEnabled = true;
      _breakStart.text = _clockText(first.breaks.first.startMinute);
      _breakEnd.text = _clockText(first.breaks.first.endMinute);
    }
  }

  void _syncHousing(LedgerState ledger) {
    final DateTime now = ref.read(clockProvider).nowUtc();
    final LocalDate month = ref.read(calendarProvider).dateOf(now).firstOfMonth;
    HousingVersion? active;
    for (final HousingVersion version in ledger.housingVersions) {
      if (!version.covers(now)) continue;
      if (active == null ||
          version.effectiveFromUtc.isAfter(active.effectiveFromUtc)) {
        active = version;
      }
    }
    _housingMode = active?.mode ?? HousingMode.none;
    final MonthlyBill? bill = _billForPlan(ledger, active?.id, month);
    _housingMonthly.text = active != null && active.mode != HousingMode.none
        ? (bill?.monthlyAmountCny?.toCanonicalString(maxScale: 2) ?? '')
        : '';
    _housingPrincipal.text = active?.mode == HousingMode.mortgage
        ? (bill?.principalCny?.toCanonicalString(maxScale: 2) ?? '')
        : '';
    _housingEffective = month;
    _housingBillMonth = month;
  }

  void _syncCar(LedgerState ledger) {
    final DateTime now = ref.read(clockProvider).nowUtc();
    final LocalDate month = ref.read(calendarProvider).dateOf(now).firstOfMonth;
    CarVersion? active;
    for (final CarVersion version in ledger.carVersions) {
      if (!version.covers(now)) continue;
      if (active == null ||
          version.effectiveFromUtc.isAfter(active.effectiveFromUtc)) {
        active = version;
      }
    }
    _carEnabled = active?.enabled ?? false;
    final MonthlyBill? bill = _billForPlan(ledger, active?.id, month);
    _carMonthly.text = _carEnabled
        ? (bill?.monthlyAmountCny?.toCanonicalString(maxScale: 2) ?? '')
        : '';
    _carPrincipal.text = _carEnabled
        ? (bill?.principalCny?.toCanonicalString(maxScale: 2) ?? '')
        : '';
    _carEffective = month;
    _carBillMonth = month;
  }

  static String _clockText(int minute) {
    final int normalized = minute % 1440;
    return '${(normalized ~/ 60).toString().padLeft(2, '0')}:'
        '${(normalized % 60).toString().padLeft(2, '0')}';
  }

  // ---------------------------------------------------------------------------
  // 解析与校验。
  // ---------------------------------------------------------------------------

  static Rational? _parseDecimal(String raw, {required int maxScale}) {
    final String text = raw.trim();
    if (text.isEmpty) return null;
    final RegExp pattern = maxScale == 0
        ? RegExp(r'^\d+$')
        : RegExp('^\\d+(\\.\\d{1,$maxScale})?\$');
    if (!pattern.hasMatch(text)) return null;
    return Rational.parse(text);
  }

  static int? _parseMinutes(String raw) {
    final RegExpMatch? match = RegExp(r'^(\d{1,2}):(\d{2})$')
        .firstMatch(raw.trim());
    if (match == null) return null;
    final int hour = int.parse(match.group(1)!);
    final int minute = int.parse(match.group(2)!);
    if (hour > 23 || minute > 59) return null;
    return hour * 60 + minute;
  }

  ShiftTemplate _buildShift() {
    final int? start = _parseMinutes(_shiftStart.text);
    if (start == null) {
      throw const ScheduleValidationError('invalidInterval', '上班时间格式应为 HH:mm。');
    }
    final int? rawEnd = _parseMinutes(_shiftEnd.text);
    if (rawEnd == null) {
      throw const ScheduleValidationError('invalidInterval', '下班时间格式应为 HH:mm。');
    }
    int end = rawEnd;
    if (end <= start) {
      if (!_overnight) {
        throw const ScheduleValidationError(
          'overnight',
          '下班时间早于上班时间，请勾选「跨夜班」确认这是次日下班。',
        );
      }
      end += 1440;
    }
    final List<BreakTemplate> breaks = <BreakTemplate>[];
    if (_breakEnabled) {
      final int? breakFrom = _parseMinutes(_breakStart.text);
      final int? breakTo = _parseMinutes(_breakEnd.text);
      if (breakFrom == null || breakTo == null) {
        throw const ScheduleValidationError(
          'breakOutsideShift',
          '午休时间格式应为 HH:mm。',
        );
      }
      int from = breakFrom;
      int to = breakTo;
      if (from < start) {
        from += 1440;
        to += 1440;
      }
      breaks.add(BreakTemplate(startMinute: from, endMinute: to));
    }
    final ShiftTemplate shift = ShiftTemplate(
      startMinute: start,
      endMinute: end,
      breaks: breaks,
    );
    shift.validate();
    return shift;
  }

  WeekTemplate _buildWeek(ShiftTemplate shift) =>
      WeekTemplate(<List<ShiftTemplate>>[
        for (int index = 0; index < 7; index++)
          if (_workdays[index])
            <ShiftTemplate>[shift]
          else
            const <ShiftTemplate>[],
      ]);

  ({int days, int seconds})? _statsForWeek(
    WeekTemplate week,
    LedgerState? ledger,
  ) {
    try {
      final BusinessCalendar calendar = ref.read(calendarProvider);
      final LocalDate anchor = calendar
          .dateOf(ref.read(clockProvider).nowUtc())
          .firstOfMonth;
      final ScheduleVersion version = ScheduleVersion(
        id: 'config-stats',
        timezone: calendar.timezoneName,
        week: week,
        effectiveFromUtc: DateTime.utc(2020),
      );
      final WageCalculator calculator = WageCalculator(calendar);
      final List<ScheduleOverride> overrides =
          ledger?.overrides ?? const <ScheduleOverride>[];
      return (
        days: calculator.expander.monthlyPaidDays(
          version: version,
          overrides: overrides,
          anchor: anchor,
        ),
        seconds: calculator.expander.monthlyPaidSeconds(
          version: version,
          overrides: overrides,
          anchor: anchor,
        ),
      );
    } on Object {
      return null;
    }
  }

  ({int days, int seconds})? _currentMonthStats(LedgerState? ledger) {
    try {
      return _statsForWeek(_buildWeek(_buildShift()), ledger);
    } on Object {
      return null;
    }
  }

  String? _incomeSalaryError() {
    final String text = _salary.text.trim();
    if (text.isEmpty) return '请输入到手月薪，最多两位小数。';
    final Rational? value = _parseDecimal(text, maxScale: 2);
    if (value == null) return '月薪最多两位小数。';
    if (value.isNegative || value > _maxMoney) {
      return '月薪需要在 0 到 10,000,000 元之间。';
    }
    return null;
  }

  String? _incomeScheduleError(LedgerState? ledger) {
    try {
      final WeekTemplate week = _buildWeek(_buildShift());
      final Rational? salary = _parseDecimal(_salary.text.trim(), maxScale: 2);
      if (salary != null && salary.isPositive) {
        final ({int days, int seconds})? stats = _statsForWeek(week, ledger);
        if (stats == null) return '排班暂时无法计算，请检查时间设置。';
        if (stats.seconds == 0) {
          return '这个月没有计薪时段，先给工资安排一个出场时间。';
        }
      }
      return null;
    } on ScheduleValidationError catch (error) {
      return error.message;
    }
  }

  String? _housingError() {
    if (_housingEffective == null || _housingBillMonth == null) {
      return '请选择生效日期与账单月份。';
    }
    if (_housingMode == HousingMode.none) return null;
    final bool rent = _housingMode == HousingMode.rent;
    final Rational? monthly = _parseDecimal(
      _housingMonthly.text.trim(),
      maxScale: 2,
    );
    if (monthly == null || monthly.isNegative || monthly > _maxMoney) {
      return rent
          ? '本月租金需要是 0 到 10,000,000 元之间的金额。'
          : '本月月供需要是 0 到 10,000,000 元之间的金额。';
    }
    if (!rent && _housingPrincipal.text.trim().isNotEmpty) {
      final Rational? principal = _parseDecimal(
        _housingPrincipal.text.trim(),
        maxScale: 2,
      );
      if (principal == null || principal.isNegative) {
        return '本金需要是非负金额，或留空表示未知。';
      }
      if (principal > monthly) {
        return '本金超过了本月月供，请核对账单。生活暂时还没学会这个算法。';
      }
    }
    return null;
  }

  String? _carError() {
    if (!_carEnabled) return null;
    if (_carEffective == null || _carBillMonth == null) {
      return '请选择生效日期与账单月份。';
    }
    final Rational? monthly = _parseDecimal(
      _carMonthly.text.trim(),
      maxScale: 2,
    );
    if (monthly == null || monthly.isNegative || monthly > _maxMoney) {
      return '车贷月供需要是 0 到 10,000,000 元之间的金额。';
    }
    if (_carPrincipal.text.trim().isNotEmpty) {
      final Rational? principal = _parseDecimal(
        _carPrincipal.text.trim(),
        maxScale: 2,
      );
      if (principal == null || principal.isNegative) {
        return '车贷本金需要是非负金额，或留空表示未知。';
      }
      if (principal > monthly) {
        return '本金超过了本月月供，请核对账单。生活暂时还没学会这个算法。';
      }
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // 保存与错误处理。
  // ---------------------------------------------------------------------------

  void _snack(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? context.palette.negative : null,
      ),
    );
  }

  Future<void> _run(
    Future<void> Function() action, {
    String success = '已保存，今天已按新配置重算',
  }) async {
    if (ref.read(busyProvider)) return;
    try {
      await action();
      if (!mounted) return;
      _snack(success);
    } on LedgerActionException catch (error) {
      _snack(error.message, error: true);
    } on DuplicateHoldingException catch (error) {
      _snack('持仓已存在：${error.instrumentId}，请编辑已有记录。', error: true);
    } on ScheduleValidationError catch (error) {
      _snack(error.message, error: true);
    } on FormatException catch (error) {
      _snack('输入格式不正确：${error.message}', error: true);
    } on Object {
      _snack('操作未完成，账本未被部分写入；请重试。', error: true);
    }
  }

  Future<void> _saveIncome() async {
    setState(() => _attemptedIncome = true);
    final LedgerState? ledger = ref.read(effectiveLedgerProvider).value;
    if (_incomeSalaryError() != null ||
        _incomeScheduleError(ledger) != null ||
        _salaryEffective == null) {
      return;
    }
    final Rational salary = _parseDecimal(_salary.text.trim(), maxScale: 2)!;
    final WeekTemplate week = _buildWeek(_buildShift());
    final LocalDate effective = _salaryEffective!;
    await _run(() async {
      await ref
          .read(ledgerControllerProvider.notifier)
          .saveCompensation(
            monthlySalary: salary,
            week: week,
            effectiveFrom: effective,
          );
      _dirtyIncome = false;
    });
  }

  Future<void> _saveHousing() async {
    setState(() => _attemptedHousing = true);
    if (_housingError() != null) return;
    final HousingMode mode = _housingMode;
    final Rational? monthly = mode == HousingMode.none
        ? null
        : _parseDecimal(_housingMonthly.text.trim(), maxScale: 2);
    final Rational? principal = mode == HousingMode.mortgage
        ? _parseDecimal(_housingPrincipal.text.trim(), maxScale: 2)
        : null;
    final LocalDate effective = _housingEffective!;
    final LocalDate billMonth = _housingBillMonth!;
    await _run(() async {
      await ref
          .read(ledgerControllerProvider.notifier)
          .saveHousing(
            mode: mode,
            monthlyAmount: monthly,
            principal: principal,
            effectiveFrom: effective,
            billMonth: billMonth,
          );
      _dirtyHousing = false;
    });
  }

  Future<void> _saveCar() async {
    setState(() => _attemptedCar = true);
    if (_carError() != null) return;
    final bool enabled = _carEnabled;
    final Rational? monthly = enabled
        ? _parseDecimal(_carMonthly.text.trim(), maxScale: 2)
        : null;
    final Rational? principal = enabled
        ? _parseDecimal(_carPrincipal.text.trim(), maxScale: 2)
        : null;
    final LocalDate effective = _carEffective!;
    final LocalDate billMonth = _carBillMonth!;
    await _run(() async {
      await ref
          .read(ledgerControllerProvider.notifier)
          .saveCar(
            enabled: enabled,
            monthlyAmount: monthly,
            principal: principal,
            effectiveFrom: effective,
            billMonth: billMonth,
          );
      _dirtyCar = false;
    });
  }

  // ---------------------------------------------------------------------------
  // 实时预览：仅覆盖正在编辑且校验通过的分区，纯本地计算。
  // ---------------------------------------------------------------------------

  static DateTime? _closedEnd(DateTime? existingTo, DateTime instant) =>
      existingTo != null && existingTo.isBefore(instant) ? existingTo : instant;

  LedgerState _withCompensation(
    LedgerState ledger,
    Rational salary,
    WeekTemplate week,
    LocalDate effectiveFrom,
  ) {
    final BusinessCalendar calendar = ref.read(calendarProvider);
    final DateTime instant = calendar.startOfDayUtc(effectiveFrom);
    final ScheduleVersion schedule = ScheduleVersion(
      id: 'config-preview-schedule',
      timezone: calendar.timezoneName,
      week: week,
      effectiveFromUtc: instant,
    );
    final SalaryVersion salaryVersion = SalaryVersion(
      id: 'config-preview-salary',
      monthlyNetCny: salary,
      effectiveFromUtc: instant,
      scheduleVersionId: schedule.id,
    );
    final Map<String, ScheduleVersion> schedules = <String, ScheduleVersion>{};
    for (final MapEntry<String, ScheduleVersion> entry
        in ledger.schedules.entries) {
      final ScheduleVersion version = entry.value;
      if (!version.effectiveFromUtc.isBefore(instant)) continue;
      schedules[entry.key] = ScheduleVersion(
        id: version.id,
        timezone: version.timezone,
        week: version.week,
        alternation: version.alternation,
        effectiveFromUtc: version.effectiveFromUtc,
        effectiveToUtc: _closedEnd(version.effectiveToUtc, instant),
        calendarSourceVersion: version.calendarSourceVersion,
      );
    }
    schedules[schedule.id] = schedule;
    final List<SalaryVersion> salaries = <SalaryVersion>[
      for (final SalaryVersion version in ledger.salaryVersions)
        if (version.effectiveFromUtc.isBefore(instant))
          SalaryVersion(
            id: version.id,
            monthlyNetCny: version.monthlyNetCny,
            effectiveFromUtc: version.effectiveFromUtc,
            effectiveToUtc: _closedEnd(version.effectiveToUtc, instant),
            scheduleVersionId: version.scheduleVersionId,
          ),
      salaryVersion,
    ];
    return ledger.copyWith(salaryVersions: salaries, schedules: schedules);
  }

  LedgerState _withHousing(
    LedgerState ledger,
    HousingMode mode,
    Rational? monthly,
    Rational? principal,
    LocalDate effectiveFrom,
    LocalDate billMonth,
  ) {
    final DateTime instant = ref
        .read(calendarProvider)
        .startOfDayUtc(effectiveFrom);
    final HousingVersion plan = HousingVersion(
      id: 'config-preview-housing',
      mode: mode,
      effectiveFromUtc: instant,
    );
    final List<HousingVersion> versions = <HousingVersion>[
      for (final HousingVersion version in ledger.housingVersions)
        if (version.effectiveFromUtc.isBefore(instant))
          HousingVersion(
            id: version.id,
            mode: version.mode,
            effectiveFromUtc: version.effectiveFromUtc,
            effectiveToUtc: _closedEnd(version.effectiveToUtc, instant),
          ),
      plan,
    ];
    final List<MonthlyBill> bills = <MonthlyBill>[
      ...ledger.bills,
      if (mode != HousingMode.none && monthly != null)
        MonthlyBill(
          expenseId: plan.id,
          kind: ExpenseKind.housing,
          month: billMonth,
          monthlyAmountCny: monthly,
          principalCny: mode == HousingMode.rent ? null : principal,
          note: mode == HousingMode.rent ? 'rent' : null,
        ),
    ];
    return ledger.copyWith(housingVersions: versions, bills: bills);
  }

  LedgerState _withCar(
    LedgerState ledger,
    bool enabled,
    Rational? monthly,
    Rational? principal,
    LocalDate effectiveFrom,
    LocalDate billMonth,
  ) {
    final DateTime instant = ref
        .read(calendarProvider)
        .startOfDayUtc(effectiveFrom);
    final CarVersion plan = CarVersion(
      id: 'config-preview-car',
      enabled: enabled,
      effectiveFromUtc: instant,
    );
    final List<CarVersion> versions = <CarVersion>[
      for (final CarVersion version in ledger.carVersions)
        if (version.effectiveFromUtc.isBefore(instant))
          CarVersion(
            id: version.id,
            enabled: version.enabled,
            effectiveFromUtc: version.effectiveFromUtc,
            effectiveToUtc: _closedEnd(version.effectiveToUtc, instant),
          ),
      plan,
    ];
    final List<MonthlyBill> bills = <MonthlyBill>[
      ...ledger.bills,
      if (enabled && monthly != null)
        MonthlyBill(
          expenseId: plan.id,
          kind: ExpenseKind.car,
          month: billMonth,
          monthlyAmountCny: monthly,
          principalCny: principal,
        ),
    ];
    return ledger.copyWith(carVersions: versions, bills: bills);
  }

  DashboardSnapshot? _previewSnapshot(
    DashboardSnapshot? saved,
    LedgerState? ledger,
  ) {
    if (ledger == null) return null;
    final int index = _tabs.index;
    if (index == 1) return null;
    LedgerState base = ledger;
    bool changed = false;
    if (index == 0 && _dirtyIncome && _salaryEffective != null) {
      final Rational? salary = _parseDecimal(_salary.text.trim(), maxScale: 2);
      if (salary != null && !salary.isNegative && salary <= _maxMoney) {
        try {
          final WeekTemplate week = _buildWeek(_buildShift());
          base = _withCompensation(base, salary, week, _salaryEffective!);
          changed = true;
        } on ScheduleValidationError {
          changed = false;
        }
      }
    }
    if (index == 2) {
      if (_dirtyHousing &&
          _housingError() == null &&
          _housingEffective != null &&
          _housingBillMonth != null) {
        final Rational? monthly = _housingMode == HousingMode.none
            ? null
            : _parseDecimal(_housingMonthly.text.trim(), maxScale: 2);
        final Rational? principal = _housingMode == HousingMode.mortgage
            ? _parseDecimal(_housingPrincipal.text.trim(), maxScale: 2)
            : null;
        base = _withHousing(
          base,
          _housingMode,
          monthly,
          principal,
          _housingEffective!,
          _housingBillMonth!,
        );
        changed = true;
      }
      if (_dirtyCar &&
          _carError() == null &&
          _carEffective != null &&
          _carBillMonth != null) {
        final Rational? monthly = _carEnabled
            ? _parseDecimal(_carMonthly.text.trim(), maxScale: 2)
            : null;
        final Rational? principal = _carEnabled
            ? _parseDecimal(_carPrincipal.text.trim(), maxScale: 2)
            : null;
        base = _withCar(
          base,
          _carEnabled,
          monthly,
          principal,
          _carEffective!,
          _carBillMonth!,
        );
        changed = true;
      }
    }
    if (!changed) return saved;
    try {
      final BusinessCalendar calendar = ref.read(calendarProvider);
      final DashboardCalculator calculator = ref.read(
        dashboardCalculatorProvider,
      );
      final DateTime now = ref.read(clockProvider).nowUtc();
      return calculator.calculate(
        base
            .copyWith(quotes: applyQuoteFreshness(base.quotes, now))
            .toCalculationInput(calendar: calendar, nowUtc: now),
      );
    } on Object {
      return saved;
    }
  }

  // ---------------------------------------------------------------------------
  // 资产 helpers。
  // ---------------------------------------------------------------------------

  List<Holding> _currentHoldings(LedgerState? ledger) {
    if (ledger == null) return <Holding>[];
    final DateTime now = ref.read(clockProvider).nowUtc();
    final Map<String, Holding> latest = <String, Holding>{};
    for (final Holding holding in ledger.holdings) {
      if (!holding.covers(now)) continue;
      final Holding? existing = latest[holding.instrumentId];
      if (existing == null ||
          holding.effectiveFromUtc.isAfter(existing.effectiveFromUtc)) {
        latest[holding.instrumentId] = holding;
      }
    }
    return latest.values.toList()..sort(
      (Holding a, Holding b) => a.instrumentId.compareTo(b.instrumentId),
    );
  }

  AssetPosition? _positionOf(DashboardSnapshot? snapshot, String instrumentId) {
    if (snapshot == null) return null;
    for (final AssetPosition position in snapshot.assets.positions) {
      if (position.instrumentId == instrumentId) return position;
    }
    return null;
  }

  static (String, String) _instrumentLabel(String id) {
    final InstrumentKind kind = instrumentKindOf(id);
    if (kind == InstrumentKind.gold) return ('黄金', 'Au99.99');
    if (kind == InstrumentKind.fund) return ('基金', fundCodeOf(id) ?? id);
    final StockMarket market = StockMarket.values.firstWhere(
      (StockMarket value) => id.startsWith('${value.prefix}.'),
      orElse: () => StockMarket.szse,
    );
    return ('A股·${market.label}', id.split('.').last);
  }

  static String _qtyText(Holding holding) => switch (holding.kind) {
    InstrumentKind.stock => holding.quantity.toCanonicalString(maxScale: 0),
    InstrumentKind.fund => holding.quantity.toCanonicalString(maxScale: 4),
    InstrumentKind.gold => holding.quantity.toCanonicalString(maxScale: 3),
  };

  static String _costText(Holding holding) => switch (holding.kind) {
    InstrumentKind.stock => holding.costPerUnit.toCanonicalString(maxScale: 3),
    InstrumentKind.fund => holding.costPerUnit.toCanonicalString(maxScale: 4),
    InstrumentKind.gold => holding.costPerUnit.toCanonicalString(maxScale: 2),
  };

  static String _qtyUnit(InstrumentKind kind) => switch (kind) {
    InstrumentKind.stock => '股',
    InstrumentKind.fund => '份',
    InstrumentKind.gold => '克',
  };

  static String _costUnit(InstrumentKind kind) => switch (kind) {
    InstrumentKind.stock => '元/股',
    InstrumentKind.fund => '元/份',
    InstrumentKind.gold => '元/克',
  };

  static String _statusLabel(PositionStatus status) => switch (status) {
    PositionStatus.ok => '正常',
    PositionStatus.pendingQuote => '待报价',
    PositionStatus.zeroQuantity => '零持仓',
    PositionStatus.closedDay => '休市',
    PositionStatus.staleBaseline => '基准过期',
    PositionStatus.calendarUnknown => '日历未知',
    PositionStatus.missingBaseline => '缺基准',
    PositionStatus.awaitingReferenceSession => '待开盘参考',
    PositionStatus.pendingNav => '待净值',
    PositionStatus.fundUnsupported => '不支持',
    PositionStatus.fundEligibilityUnknown => '品种待确认',
    PositionStatus.fundNavFuture => '净值日期超前',
    PositionStatus.fundClosedDay => '基金休市',
    PositionStatus.fundCalendarUnknown => '基金日历未知',
    PositionStatus.fundNavPending => '净值待发布',
    PositionStatus.fundActionUnknown => '分红待确认',
    PositionStatus.fundActionDetected => '分红需复核',
    PositionStatus.fundBaselineUnknown => '缺前值',
  };

  Future<void> _openHoldingEditor(
    LedgerState? ledger, {
    _HoldingSeed? seed,
  }) async {
    final Set<String> existingIds = <String>{
      for (final Holding holding in _currentHoldings(ledger))
        holding.instrumentId,
    };
    if (seed?.instrumentId != null) existingIds.remove(seed!.instrumentId);
    final _HoldingEdit? result = await showDialog<_HoldingEdit>(
      context: context,
      builder: (_) => _HoldingDialog(seed: seed, existingIds: existingIds),
    );
    if (result == null || !mounted) return;
    await _run(
      () => ref
          .read(ledgerControllerProvider.notifier)
          .upsertHolding(
            instrumentId: result.instrumentId,
            quantity: result.quantity,
            costPerUnit: result.costPerUnit,
            name: result.name.isEmpty ? null : result.name,
            pendingQuote: result.pendingQuote,
            previousInstrumentId: seed?.instrumentId,
          ),
    );
  }

  Future<void> _deleteHolding(String instrumentId, String label) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text('删除 $label？'),
        content: const Text('删除后今天不再计入该持仓，历史版本保留。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _run(
      () => ref
          .read(ledgerControllerProvider.notifier)
          .deleteHolding(instrumentId),
      success: '已删除，今天已按新配置重算',
    );
  }

  // ---------------------------------------------------------------------------
  // 账单 helpers。
  // ---------------------------------------------------------------------------

  MonthlyBill? _billForPlan(
    LedgerState ledger,
    String? planId,
    LocalDate month,
  ) {
    if (planId == null) return null;
    MonthlyBill? selected;
    for (final MonthlyBill bill in ledger.bills) {
      if (bill.expenseId != planId || bill.month != month) continue;
      if (selected == null || bill.revision >= selected.revision) {
        selected = bill;
      }
    }
    return selected;
  }

  MonthlyBill? _previousBill(
    LedgerState ledger,
    ExpenseKind kind,
    LocalDate month,
  ) {
    MonthlyBill? best;
    for (final MonthlyBill bill in ledger.bills) {
      if (bill.kind != kind || !(bill.month < month)) continue;
      if (best == null ||
          bill.month > best.month ||
          (bill.month == best.month && bill.revision >= best.revision)) {
        best = bill;
      }
    }
    return best;
  }

  List<_PlanRow> _billRows(LedgerState? ledger, LocalDate month) {
    if (ledger == null) return <_PlanRow>[];
    final BusinessCalendar calendar = ref.read(calendarProvider);
    final DateTime start = calendar.startOfDayUtc(month);
    final DateTime end = calendar.startOfDayUtc(month.addMonths(1));
    bool overlaps(DateTime from, DateTime? to) =>
        from.isBefore(end) && (to ?? DateTime.utc(9999)).isAfter(start);
    final List<_PlanRow> rows = <_PlanRow>[];
    for (final HousingVersion version in ledger.housingVersions) {
      if (version.mode == HousingMode.none ||
          !overlaps(version.effectiveFromUtc, version.effectiveToUtc)) {
        continue;
      }
      rows.add(
        _PlanRow(
          kind: ExpenseKind.housing,
          planId: version.id,
          label: version.mode == HousingMode.rent ? '房租' : '房贷',
          isRent: version.mode == HousingMode.rent,
          month: month,
          bill: _billForPlan(ledger, version.id, month),
        ),
      );
    }
    for (final CarVersion version in ledger.carVersions) {
      if (!version.enabled ||
          !overlaps(version.effectiveFromUtc, version.effectiveToUtc)) {
        continue;
      }
      rows.add(
        _PlanRow(
          kind: ExpenseKind.car,
          planId: version.id,
          label: '车贷',
          isRent: false,
          month: month,
          bill: _billForPlan(ledger, version.id, month),
        ),
      );
    }
    rows.sort((_PlanRow a, _PlanRow b) => a.kind.index.compareTo(b.kind.index));
    return rows;
  }

  Future<void> _openBillEditor(_PlanRow row) async {
    final _BillDraft? draft = await showDialog<_BillDraft>(
      context: context,
      builder: (_) => _BillDialog(
        title: row.bill == null ? '填写账单' : '编辑账单',
        kindLabel: row.label,
        monthLabel: formatMonth(row.month),
        isRent: row.isRent,
        initialAmount:
            row.bill?.monthlyAmountCny?.toCanonicalString(maxScale: 2) ?? '',
        initialPrincipal:
            row.bill?.principalCny?.toCanonicalString(maxScale: 2) ?? '',
      ),
    );
    if (draft == null || !mounted) return;
    await _saveBillDraft(row, draft, null);
  }

  Future<void> _copyPreviousBill(LedgerState? ledger, _PlanRow row) async {
    if (ledger == null) return;
    final MonthlyBill? previous = _previousBill(ledger, row.kind, row.month);
    if (previous == null) {
      _snack('上个月没有可复制的账单。', error: true);
      return;
    }
    final _BillDraft? draft = await showDialog<_BillDraft>(
      context: context,
      builder: (_) => _BillDialog(
        title: '复制上月账单',
        kindLabel: row.label,
        monthLabel: formatMonth(row.month),
        isRent: row.isRent,
        confirmLabel: '确认保存',
        note: '金额沿用 ${formatMonth(previous.month)}，请核对后确认。',
        initialAmount:
            previous.monthlyAmountCny?.toCanonicalString(maxScale: 2) ?? '',
        initialPrincipal:
            previous.principalCny?.toCanonicalString(maxScale: 2) ?? '',
      ),
    );
    if (draft == null || !mounted) return;
    await _saveBillDraft(
      row,
      draft,
      '复制自 ${BusinessCalendar.monthKey(previous.month)}',
    );
  }

  Future<void> _saveBillDraft(
    _PlanRow row,
    _BillDraft draft,
    String? note,
  ) async {
    final MonthlyBill bill = MonthlyBill(
      expenseId: row.planId,
      kind: row.kind,
      month: row.month,
      monthlyAmountCny: draft.amount,
      principalCny: row.isRent ? null : draft.principal,
      revision: row.bill?.revision ?? 1,
      note: note,
    );
    await _run(
      () => ref.read(ledgerControllerProvider.notifier).saveBill(bill),
    );
  }

  // ---------------------------------------------------------------------------
  //  build。
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final FjobPalette palette = context.palette;
    final LedgerState? ledger = ref.watch(effectiveLedgerProvider).value;
    _maybeSync(ledger);
    final bool busy = ref.watch(busyProvider);
    final bool readOnly = ref.watch(sampleModeProvider);
    final DashboardSnapshot? saved = ref.watch(dashboardProvider).value;
    final bool canSave = !busy && !readOnly && ledger != null;
    final DashboardSnapshot? preview = _previewSnapshot(saved, ledger);

    return Scaffold(
      backgroundColor: palette.paper,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '配置',
                  style: Theme.of(context).textTheme.headlineMedium
                      ?.copyWith(fontSize: 22),
                ),
                const SizedBox(height: 4),
                Text(
                  '改完即时预览，保存后按新版本重算今天',
                  style: TextStyle(fontSize: 12, color: palette.muted),
                ),
                if (readOnly) ...<Widget>[
                  const SizedBox(height: 6),
                  Text(
                    '示例模式只读：切回正式账本后才能保存。',
                    style: TextStyle(fontSize: 12, color: palette.negative),
                  ),
                ],
              ],
            ),
          ),
          TabBar(
            controller: _tabs,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: const <Widget>[
              Tab(text: '收入与排班'),
              Tab(text: '资产'),
              Tab(text: '住房与车贷'),
              Tab(text: '账单'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: <Widget>[
                _tabWithPreview(_incomeForm(ledger, canSave), preview, ledger),
                _assetsTab(ledger, saved, canSave),
                _tabWithPreview(_housingForm(canSave), preview, ledger),
                _tabWithPreview(
                  _billsForm(ledger, saved, canSave),
                  preview,
                  ledger,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabWithPreview(
    Widget form,
    DashboardSnapshot? preview,
    LedgerState? ledger,
  ) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool wide = constraints.maxWidth >= 800;
        final Widget side = _previewPanel(preview, ledger);
        if (wide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(22, 16, 14, 24),
                  child: form,
                ),
              ),
              SizedBox(
                width: 300,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(0, 16, 22, 24),
                  child: side,
                ),
              ),
            ],
          );
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 16, 22, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[form, const SizedBox(height: 14), side],
          ),
        );
      },
    );
  }

  Widget _previewPanel(DashboardSnapshot? snapshot, LedgerState? ledger) {
    final FjobPalette palette = context.palette;
    final BusinessCalendar calendar = ref.watch(calendarProvider);
    final AppTone tone = ledger?.settings.tone ?? AppTone.gentle;
    final bool reduceMotion = ledger?.settings.motion == MotionSetting.reduced;
    return PaperCard(
      color: palette.soft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SectionLabel('固定窗预览'),
          const SizedBox(height: 10),
          Center(
            child: snapshot == null
                ? SizedBox(
                    width: 268,
                    height: 184,
                    child: Center(
                      child: Text(
                        '预览待生成…',
                        style: TextStyle(fontSize: 12, color: palette.muted),
                      ),
                    ),
                  )
                : FittedBox(
                    fit: BoxFit.scaleDown,
                    child: FixedCardView(
                      snapshot: snapshot,
                      calendar: calendar,
                      tone: tone,
                      privacy: false,
                      reduceMotion: reduceMotion,
                    ),
                  ),
          ),
          const SizedBox(height: 10),
          Text(
            '今天将按新配置重算 · 历史版本保留',
            style: TextStyle(fontSize: 11, color: palette.muted),
          ),
        ],
      ),
    );
  }

  // ----- 收入与排班 -----

  Widget _incomeForm(LedgerState? ledger, bool canSave) {
    final FjobPalette palette = context.palette;
    final String? salaryError = _incomeSalaryError();
    final String? scheduleError = _incomeScheduleError(ledger);
    final ({int days, int seconds})? stats = _currentMonthStats(ledger);
    final ScheduleVersion? schedule = _currentSchedule(ledger);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        PaperCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const SectionLabel('到手月薪'),
              const SizedBox(height: 10),
              TextField(
                controller: _salary,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: '到手月薪 / 元',
                  hintText: '例如 12000，可填 0',
                  errorText: _attemptedIncome ? salaryError : null,
                ),
                onChanged: (_) => setState(() => _dirtyIncome = true),
              ),
              const SizedBox(height: 12),
              _dateField(
                label: '生效日期',
                value: _salaryEffective,
                onPick: (LocalDate date) => setState(() {
                  _salaryEffective = date;
                  _dirtyIncome = true;
                }),
              ),
              const SizedBox(height: 8),
              Text(
                '生效日期默认当月首日。保存后从该日起按新版本计薪，历史版本保留。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        PaperCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const SectionLabel('每周排班'),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: <Widget>[
                  for (int index = 0; index < 7; index++)
                    FilterChip(
                      label: Text(weekdayLabel(index + 1)),
                      selected: _workdays[index],
                      onSelected: (bool value) => setState(() {
                        _workdays[index] = value;
                        _dirtyIncome = true;
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Expanded(child: _timeField(_shiftStart, '上班时间')),
                  const SizedBox(width: 10),
                  Expanded(child: _timeField(_shiftEnd, '下班时间')),
                ],
              ),
              Material(
                type: MaterialType.transparency,
                child: CheckboxListTile(
                  value: _overnight,
                  onChanged: (bool? value) => setState(() {
                    _overnight = value ?? false;
                    _dirtyIncome = true;
                  }),
                  title: const Text('跨夜班（下班时间为次日）'),
                  subtitle: const Text('下班早于上班时必须勾选。'),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              Material(
                type: MaterialType.transparency,
                child: SwitchListTile(
                  value: _breakEnabled,
                  onChanged: (bool value) => setState(() {
                    _breakEnabled = value;
                    _dirtyIncome = true;
                  }),
                  title: const Text('有午休，不计薪'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              if (_breakEnabled)
                Row(
                  children: <Widget>[
                    Expanded(child: _timeField(_breakStart, '午休开始')),
                    const SizedBox(width: 10),
                    Expanded(child: _timeField(_breakEnd, '午休结束')),
                  ],
                ),
              const SizedBox(height: 12),
              PaperCard(
                color: palette.soft,
                padding: const EdgeInsets.all(12),
                child: Text(
                  stats == null
                      ? '排班还差一点，先检查上下班与午休时间。'
                      : '本月计薪 ${stats.days} 天 · 总计薪 ${formatHours(stats.seconds)} 小时',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              if (_attemptedIncome && scheduleError != null) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  scheduleError,
                  style: TextStyle(fontSize: 12, color: palette.negative),
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  Icon(Icons.schedule, size: 16, color: palette.muted),
                  const SizedBox(width: 6),
                  Text(
                    '计薪时区 · Asia/Shanghai（只读）',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
              if (schedule?.alternation != null) ...<Widget>[
                const SizedBox(height: 6),
                Text(
                  '原配置为大小周；此页保存后将改为固定周模板。',
                  style: TextStyle(fontSize: 12, color: palette.negative),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        FilledButton(
          onPressed: canSave ? _saveIncome : null,
          child: const Text('保存收入与排班'),
        ),
      ],
    );
  }

  ScheduleVersion? _currentSchedule(LedgerState? ledger) {
    if (ledger == null) return null;
    final SalaryVersion? salary = _activeSalary(
      ledger,
      ref.read(clockProvider).nowUtc(),
    );
    return salary == null ? null : ledger.schedules[salary.scheduleVersionId];
  }

  Widget _timeField(TextEditingController controller, String label) =>
      TextField(
        controller: controller,
        keyboardType: TextInputType.datetime,
        textInputAction: TextInputAction.next,
        decoration: InputDecoration(labelText: label, hintText: 'HH:mm'),
        onChanged: (_) => setState(() => _dirtyIncome = true),
      );

  Widget _dateField({
    required String label,
    required LocalDate? value,
    required ValueChanged<LocalDate> onPick,
    bool monthOnly = false,
  }) {
    final FjobPalette palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 4),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () async {
              final LocalDate initial = value ?? _today();
              final DateTime? picked = await showDatePicker(
                context: context,
                initialDate: DateTime(initial.year, initial.month, initial.day),
                firstDate: DateTime(2020),
                lastDate: DateTime(2100),
                helpText: monthOnly ? '选择账单月份（任意一天均可）' : '选择日期',
              );
              if (picked == null || !mounted) return;
              onPick(
                monthOnly
                    ? LocalDate(picked.year, picked.month, 1)
                    : LocalDate(picked.year, picked.month, picked.day),
              );
            },
            icon: const Icon(Icons.event_outlined, size: 18),
            label: Text(
              value == null
                  ? '请选择'
                  : (monthOnly ? formatMonth(value) : value.toIsoString()),
            ),
          ),
        ),
        if (value == null)
          Text(
            '请选择$label。',
            style: TextStyle(fontSize: 12, color: palette.negative),
          ),
      ],
    );
  }

  // ----- 住房与车贷 -----

  Widget _housingForm(bool canSave) {
    final FjobPalette palette = context.palette;
    final String? housingError = _housingError();
    final String? carError = _carError();
    final bool rent = _housingMode == HousingMode.rent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        PaperCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const SectionLabel('住房方式（三选一）'),
              const SizedBox(height: 10),
              SegmentedButton<HousingMode>(
                segments: const <ButtonSegment<HousingMode>>[
                  ButtonSegment<HousingMode>(
                    value: HousingMode.mortgage,
                    label: Text('房贷'),
                  ),
                  ButtonSegment<HousingMode>(
                    value: HousingMode.rent,
                    label: Text('房租'),
                  ),
                  ButtonSegment<HousingMode>(
                    value: HousingMode.none,
                    label: Text('暂无'),
                  ),
                ],
                selected: <HousingMode>{_housingMode},
                onSelectionChanged: (Set<HousingMode> value) => setState(() {
                  _housingMode = value.first;
                  _dirtyHousing = true;
                }),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _housingMonthly,
                enabled: _housingMode != HousingMode.none,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                decoration: InputDecoration(
                  labelText: rent ? '本月租金 / 元' : '本月月供 / 元',
                ),
                onChanged: (_) => setState(() => _dirtyHousing = true),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _housingPrincipal,
                enabled: _housingMode == HousingMode.mortgage,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                decoration: const InputDecoration(
                  labelText: '其中本金 / 元（选填）',
                  hintText: '未知可留空，填 0 表示确认为 0',
                ),
                onChanged: (_) => setState(() => _dirtyHousing = true),
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: _dateField(
                      label: '生效日期',
                      value: _housingEffective,
                      onPick: (LocalDate date) => setState(() {
                        _housingEffective = date;
                        _dirtyHousing = true;
                      }),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _dateField(
                      label: '账单月份',
                      value: _housingBillMonth,
                      monthOnly: true,
                      onPick: (LocalDate date) => setState(() {
                        _housingBillMonth = date;
                        _dirtyHousing = true;
                      }),
                    ),
                  ),
                ],
              ),
              if (_attemptedHousing && housingError != null) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  housingError,
                  style: TextStyle(fontSize: 12, color: palette.negative),
                ),
              ],
              const SizedBox(height: 14),
              FilledButton(
                onPressed: canSave ? _saveHousing : null,
                child: const Text('保存住房'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        PaperCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const SectionLabel('车贷（独立配置）'),
              Material(
                type: MaterialType.transparency,
                child: SwitchListTile(
                  value: _carEnabled,
                  onChanged: (bool value) => setState(() {
                    _carEnabled = value;
                    _dirtyCar = true;
                  }),
                  title: const Text('车贷也有固定席位'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              if (_carEnabled) ...<Widget>[
                TextField(
                  controller: _carMonthly,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  decoration: const InputDecoration(labelText: '本月车贷 / 元'),
                  onChanged: (_) => setState(() => _dirtyCar = true),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _carPrincipal,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  decoration: const InputDecoration(
                    labelText: '其中本金 / 元（选填）',
                    hintText: '未知可留空，填 0 表示确认为 0',
                  ),
                  onChanged: (_) => setState(() => _dirtyCar = true),
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(
                      child: _dateField(
                        label: '生效日期',
                        value: _carEffective,
                        onPick: (LocalDate date) => setState(() {
                          _carEffective = date;
                          _dirtyCar = true;
                        }),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _dateField(
                        label: '账单月份',
                        value: _carBillMonth,
                        monthOnly: true,
                        onPick: (LocalDate date) => setState(() {
                          _carBillMonth = date;
                          _dirtyCar = true;
                        }),
                      ),
                    ),
                  ],
                ),
              ],
              if (_attemptedCar && carError != null) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  carError,
                  style: TextStyle(fontSize: 12, color: palette.negative),
                ),
              ],
              const SizedBox(height: 14),
              FilledButton(
                onPressed: canSave ? _saveCar : null,
                child: const Text('保存车贷'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Text(
          '本金未知时明细显示待补充，月供仍全额计入压力。填 0 表示明确确认本金为 0。',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  // ----- 资产 -----

  Widget _assetsTab(
    LedgerState? ledger,
    DashboardSnapshot? snapshot,
    bool canSave,
  ) {
    final FjobPalette palette = context.palette;
    final List<Holding> holdings = _currentHoldings(ledger);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(22, 16, 22, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // IntrinsicWidth 给按钮一个有界的紧宽度：无界宽的 FilledButton.icon
          // 在 TabBarView 页重排时会以无限宽参与伸缩计算，把同一行的
          // Expanded 拖成负数可用空间，整页布局作废（表头、空状态全部
          // 不可见）。收窄到按钮自身固有宽度后，视觉不变且不再发散。
          Row(
            children: <Widget>[
              const Expanded(child: SectionLabel('资产持仓')),
              IntrinsicWidth(
                child: FilledButton.icon(
                  onPressed: canSave ? () => _openHoldingEditor(ledger) : null,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('添加持仓'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (holdings.isEmpty)
            PaperCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const SizedBox(height: 8),
                  Center(
                    child: Text(
                      '钱包暂时没有战场',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: Text(
                      '添加 A 股、基金或黄金，工资之外再添一条战线。',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: canSave
                        ? () => _openHoldingEditor(ledger)
                        : null,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('添加持仓'),
                  ),
                ],
              ),
            )
          else
            _hScrollTable(
              // 780：默认窗口（1000 逻辑宽 - 导航 168 - 页边距 44 = 788）
              // 一屏放下全部列，操作列不再需要横向滚动；更窄时仍可滚动。
              minWidth: 780,
              children: <Widget>[
                _assetHeader(palette),
                for (final Holding holding in holdings) ...<Widget>[
                  const Divider(height: 1),
                  _assetRow(holding, ledger!, snapshot, canSave),
                ],
              ],
            ),
          const SizedBox(height: 10),
          Text(
            '今日与持有盈亏来自共享引擎快照；报价缺失时显示「—」，不自行重算。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _assetHeader(FjobPalette palette) {
    final TextStyle style = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: palette.muted,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: <Widget>[
          Expanded(flex: 3, child: Text('标的', style: style)),
          Expanded(flex: 2, child: Text('持仓', style: style)),
          Expanded(flex: 2, child: Text('成本', style: style)),
          Expanded(flex: 2, child: Text('今日', style: style)),
          Expanded(flex: 2, child: Text('持有', style: style)),
          Expanded(flex: 2, child: Text('状态', style: style)),
          SizedBox(width: 100, child: Text('操作', style: style)),
        ],
      ),
    );
  }

  Widget _assetRow(
    Holding holding,
    LedgerState ledger,
    DashboardSnapshot? snapshot,
    bool canSave,
  ) {
    final FjobPalette palette = context.palette;
    final AssetPosition? position = _positionOf(snapshot, holding.instrumentId);
    final (String kindLabel, String code) = _instrumentLabel(
      holding.instrumentId,
    );
    final String name =
        ledger.instrumentNames[holding.instrumentId] ??
        (holding.kind == InstrumentKind.gold ? goldInstrumentName : '');
    final TextStyle cell = const TextStyle(fontSize: 13);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: <Widget>[
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  name.isEmpty ? code : name,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '$kindLabel · $code',
                  style: TextStyle(fontSize: 11, color: palette.muted),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              '${_qtyText(holding)} ${_qtyUnit(holding.kind)}',
              style: cell,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              '${_costText(holding)} ${_costUnit(holding.kind)}',
              style: cell,
            ),
          ),
          Expanded(flex: 2, child: _pnlText(position?.dailyPnl)),
          Expanded(flex: 2, child: _pnlText(position?.heldPnl)),
          Expanded(
            flex: 2,
            child: Text(
              position == null ? '待更新' : _statusLabel(position.status),
              style: TextStyle(fontSize: 12, color: palette.muted),
            ),
          ),
          SizedBox(
            width: 100,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                IconButton(
                  tooltip: '编辑持仓',
                  iconSize: 19,
                  onPressed: canSave
                      ? () => _openHoldingEditor(
                          ledger,
                          seed: _seedOf(holding, ledger),
                        )
                      : null,
                  icon: const Icon(Icons.edit_outlined),
                ),
                IconButton(
                  tooltip: '删除持仓',
                  iconSize: 19,
                  onPressed: canSave
                      ? () => _deleteHolding(
                          holding.instrumentId,
                          name.isEmpty ? code : name,
                        )
                      : null,
                  icon: Icon(Icons.delete_outline, color: palette.negative),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  _HoldingSeed _seedOf(Holding holding, LedgerState ledger) {
    final InstrumentKind kind = holding.kind;
    String code = '';
    if (kind == InstrumentKind.stock) {
      code = holding.instrumentId.split('.').last;
    } else if (kind == InstrumentKind.fund) {
      code = fundCodeOf(holding.instrumentId) ?? '';
    }
    return _HoldingSeed(
      kind: kind,
      code: code,
      name:
          ledger.instrumentNames[holding.instrumentId] ??
          (kind == InstrumentKind.gold ? goldInstrumentName : ''),
      quantityText: _qtyText(holding),
      costText: _costText(holding),
      pendingQuote: holding.pendingQuote,
      instrumentId: holding.instrumentId,
    );
  }

  Widget _pnlText(Rational? value) {
    final FjobPalette palette = context.palette;
    if (value == null) {
      return Text('—', style: TextStyle(fontSize: 13, color: palette.muted));
    }
    return Text(
      formatSigned(value),
      style: TextStyle(
        fontFamily: 'Cascadia Mono',
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: value.isNegative
            ? palette.negative
            : value.isZero
            ? palette.ink
            : palette.positive,
      ),
    );
  }

  // ----- 账单 -----

  Widget _billsForm(
    LedgerState? ledger,
    DashboardSnapshot? snapshot,
    bool canSave,
  ) {
    final FjobPalette palette = context.palette;
    final List<_PlanRow> rows = _billRows(ledger, _billMonth);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        PaperCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const SectionLabel('账单月份'),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  IconButton(
                    tooltip: '上个月',
                    onPressed: () =>
                        setState(() => _billMonth = _billMonth.addMonths(-1)),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        formatMonth(_billMonth),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '下个月',
                    onPressed: () =>
                        setState(() => _billMonth = _billMonth.addMonths(1)),
                    icon: const Icon(Icons.chevron_right),
                  ),
                  TextButton(
                    onPressed: () =>
                        setState(() => _billMonth = _today().firstOfMonth),
                    child: const Text('本月'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (rows.isEmpty)
          PaperCard(
            child: Text(
              '本月没有需要登记的固定支出。住房与车贷在「住房与车贷」页签配置。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          )
        else
          _hScrollTable(
            minWidth: 840,
            children: <Widget>[
              _billHeader(palette),
              for (final _PlanRow row in rows) ...<Widget>[
                const Divider(height: 1),
                _billRow(row, snapshot, canSave),
              ],
            ],
          ),
        const SizedBox(height: 10),
        Text(
          '「今日已分摊」仅显示当前生效计划在今天的实时分摊，其他计划或月份显示「—」。'
          '本金留空为待补充，填 0 表示确认为 0；缺失账单不计入今日。',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _billHeader(FjobPalette palette) {
    final TextStyle style = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: palette.muted,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: <Widget>[
          Expanded(flex: 3, child: Text('项目', style: style)),
          Expanded(flex: 2, child: Text('标准月额', style: style)),
          Expanded(flex: 2, child: Text('今日已分摊', style: style)),
          Expanded(flex: 2, child: Text('本金', style: style)),
          Expanded(flex: 2, child: Text('利息', style: style)),
          Expanded(flex: 2, child: Text('状态', style: style)),
          SizedBox(width: 100, child: Text('操作', style: style)),
        ],
      ),
    );
  }

  Widget _billRow(_PlanRow row, DashboardSnapshot? snapshot, bool canSave) {
    final FjobPalette palette = context.palette;
    final MonthlyBill? bill = row.bill;
    final Rational? amount = bill?.monthlyAmountCny;
    Rational? allocated;
    if (snapshot != null &&
        bill != null &&
        bill.month == snapshot.statisticsDate.firstOfMonth) {
      final ExpenseBreakdown detail = row.kind == ExpenseKind.housing
          ? snapshot.housingDetail
          : snapshot.carDetail;
      if (detail.activePlanId == row.planId) allocated = detail.dayAmount;
    }
    final Rational? principal = bill?.principalCny;
    Rational? interest;
    if (bill != null && !row.isRent && amount != null && principal != null) {
      interest = amount - principal;
    }
    final String status = bill == null
        ? '缺失'
        : switch (bill.status) {
            BillStatus.confirmed => '已确认',
            BillStatus.carriedForwardEstimate => '沿用估算',
            BillStatus.missing => '缺失',
          };
    const TextStyle cell = TextStyle(fontSize: 13);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: <Widget>[
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  row.label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '${formatMonth(row.month)}${bill == null ? ' · 待登记' : ''}',
                  style: TextStyle(fontSize: 11, color: palette.muted),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              amount == null
                  ? (bill == null ? '—' : '缺失')
                  : formatMoney(amount),
              style: cell,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              allocated == null ? '—' : formatMoney(allocated),
              style: cell,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              principal == null
                  ? (bill == null ? '—' : '待补充')
                  : formatMoney(principal),
              style: cell,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              interest == null ? '—' : formatMoney(interest),
              style: cell,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              status,
              style: TextStyle(
                fontSize: 12,
                color: bill == null ? palette.negative : palette.muted,
              ),
            ),
          ),
          SizedBox(
            width: 100,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                IconButton(
                  tooltip: bill == null ? '填写账单' : '编辑账单',
                  iconSize: 19,
                  onPressed: canSave ? () => _openBillEditor(row) : null,
                  icon: const Icon(Icons.edit_outlined),
                ),
                IconButton(
                  tooltip: '复制上月',
                  iconSize: 19,
                  onPressed: canSave
                      ? () => _copyPreviousBill(
                          ref.read(effectiveLedgerProvider).value,
                          row,
                        )
                      : null,
                  icon: const Icon(Icons.copy_outlined),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _hScrollTable({
    required double minWidth,
    required List<Widget> children,
  }) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double width = constraints.maxWidth < minWidth
            ? minWidth
            : constraints.maxWidth;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          // SizedBox(而非 ConstrainedBox(minWidth)) 给出有界紧约束：横向滚动
          // 容器本身会传无限宽度，ConstrainedBox 只抬高下限，stretch 的列会
          // 塌缩成文字自然宽并互相粘连，整页布局直接作废。
          child: SizedBox(
            width: width,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        );
      },
    );
  }
}

// -----------------------------------------------------------------------------
// 持仓弹窗。
// -----------------------------------------------------------------------------

final class _HoldingSeed {
  const _HoldingSeed({
    required this.kind,
    required this.code,
    required this.name,
    required this.quantityText,
    required this.costText,
    required this.pendingQuote,
    required this.instrumentId,
  });

  final InstrumentKind kind;
  final String code;
  final String name;
  final String quantityText;
  final String costText;
  final bool pendingQuote;
  final String? instrumentId;
}

final class _HoldingEdit {
  const _HoldingEdit({
    required this.instrumentId,
    required this.quantity,
    required this.costPerUnit,
    required this.name,
    required this.pendingQuote,
  });

  final String instrumentId;
  final Rational quantity;
  final Rational costPerUnit;
  final String name;
  final bool pendingQuote;
}

class _HoldingDialog extends ConsumerStatefulWidget {
  const _HoldingDialog({this.seed, required this.existingIds});

  final _HoldingSeed? seed;
  final Set<String> existingIds;

  @override
  ConsumerState<_HoldingDialog> createState() => _HoldingDialogState();
}

class _HoldingDialogState extends ConsumerState<_HoldingDialog> {
  late InstrumentKind _kind = widget.seed?.kind ?? InstrumentKind.stock;
  late final TextEditingController _code = TextEditingController(
    text: widget.seed?.code ?? '',
  );
  late final TextEditingController _name = TextEditingController(
    text: widget.seed?.name ?? '',
  );
  late final TextEditingController _quantity = TextEditingController(
    text: widget.seed?.quantityText ?? '',
  );
  late final TextEditingController _cost = TextEditingController(
    text: widget.seed?.costText ?? '',
  );
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    _quantity.dispose();
    _cost.dispose();
    super.dispose();
  }

  void _submit() {
    final String code = _code.text.trim();
    String instrumentId;
    if (_kind == InstrumentKind.gold) {
      instrumentId = goldInstrumentId;
    } else {
      if (!RegExp(r'^\d{6}$').hasMatch(code)) {
        setState(
          () => _error = _kind == InstrumentKind.fund
              ? '基金代码是 6 位数字，请核对。'
              : '证券代码是 6 位数字，请核对。',
        );
        return;
      }
      if (_kind == InstrumentKind.fund) {
        instrumentId = fundInstrumentIdFor(code);
      } else {
        final StockMarket? market = marketForCode(code);
        if (market == null) {
          setState(() => _error = '暂不认识这个代码对应的市场，请核对。');
          return;
        }
        instrumentId = instrumentIdFor(code, market);
      }
    }
    if (widget.existingIds.contains(instrumentId)) {
      setState(() => _error = '同一标的只能保留一笔持仓，请编辑已有记录。');
      return;
    }
    final String quantityText = _quantity.text.trim();
    final String costText = _cost.text.trim();
    if (quantityText.isEmpty || costText.isEmpty) {
      setState(() => _error = '请填写持仓数量与成本。');
      return;
    }
    final Rational? quantity;
    final Rational? cost;
    switch (_kind) {
      case InstrumentKind.gold:
        quantity = _ConfigPageState._parseDecimal(quantityText, maxScale: 3);
        if (quantity == null ||
            quantity.isNegative ||
            quantity > _maxGoldQuantity) {
          setState(() => _error = '黄金克重需要是 0 到 1,000,000 之间的数字，最多三位小数。');
          return;
        }
        cost = _ConfigPageState._parseDecimal(costText, maxScale: 2);
        if (cost == null || cost.isNegative || cost > _maxCost) {
          setState(() => _error = '每克成本需要是 0 到 100,000 之间的数字，最多两位小数。');
          return;
        }
      case InstrumentKind.fund:
        quantity = _ConfigPageState._parseDecimal(quantityText, maxScale: 4);
        if (quantity == null ||
            quantity.isNegative ||
            quantity > _maxFundQuantity) {
          setState(() => _error = '基金份额需要是 0 到 10,000,000 之间的数字，最多四位小数。');
          return;
        }
        cost = _ConfigPageState._parseDecimal(costText, maxScale: 4);
        if (cost == null || cost.isNegative || cost > _maxCost) {
          setState(() => _error = '单位成本需要是 0 到 100,000 之间的数字，最多四位小数。');
          return;
        }
      case InstrumentKind.stock:
        quantity = _ConfigPageState._parseDecimal(quantityText, maxScale: 0);
        if (quantity == null || quantity.isNegative) {
          setState(() => _error = '股数需要是非负整数。');
          return;
        }
        cost = _ConfigPageState._parseDecimal(costText, maxScale: 3);
        if (cost == null || cost.isNegative || cost > _maxCost) {
          setState(() => _error = '每股成本需要是 0 到 100,000 之间的数字，最多三位小数。');
          return;
        }
    }
    final String name = _name.text.trim();
    Navigator.pop(
      context,
      _HoldingEdit(
        instrumentId: instrumentId,
        quantity: quantity,
        costPerUnit: cost,
        name: name,
        pendingQuote: _kind == InstrumentKind.gold ? false : name.isEmpty,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final FjobPalette palette = context.palette;
    final bool busy = ref.watch(busyProvider);
    final bool gold = _kind == InstrumentKind.gold;
    final bool fund = _kind == InstrumentKind.fund;
    final StockMarket? market = _kind == InstrumentKind.stock
        ? marketForCode(_code.text.trim())
        : null;
    return AlertDialog(
      title: Text(widget.seed == null ? '添加持仓' : '编辑持仓'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              SegmentedButton<InstrumentKind>(
                segments: const <ButtonSegment<InstrumentKind>>[
                  ButtonSegment<InstrumentKind>(
                    value: InstrumentKind.stock,
                    label: Text('A股'),
                  ),
                  ButtonSegment<InstrumentKind>(
                    value: InstrumentKind.fund,
                    label: Text('基金'),
                  ),
                  ButtonSegment<InstrumentKind>(
                    value: InstrumentKind.gold,
                    label: Text('黄金'),
                  ),
                ],
                selected: <InstrumentKind>{_kind},
                onSelectionChanged: (Set<InstrumentKind> value) => setState(() {
                  _kind = value.first;
                  _error = null;
                }),
              ),
              const SizedBox(height: 12),
              if (!gold) ...<Widget>[
                TextField(
                  controller: _code,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  decoration: InputDecoration(
                    labelText: fund ? '基金代码' : '证券代码',
                    hintText: '例如 000001',
                    counterText: '',
                  ),
                  onChanged: (_) => setState(() => _error = null),
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: palette.soft,
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(
                      fund
                          ? '场外基金'
                          : (market == null ? '市场待识别' : '${market.label}市'),
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              TextField(
                controller: _name,
                decoration: InputDecoration(
                  labelText: '名称（可修改）',
                  hintText: gold ? goldInstrumentName : '例如 平安银行',
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _quantity,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: <TextInputFormatter>[
                        _kind == InstrumentKind.stock
                            ? FilteringTextInputFormatter.digitsOnly
                            : FilteringTextInputFormatter.allow(
                                RegExp(r'[0-9.]'),
                              ),
                      ],
                      decoration: InputDecoration(
                        labelText: gold
                            ? '克重 / 克'
                            : fund
                            ? '持有份额 / 份'
                            : '持仓 / 股',
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _cost,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: <TextInputFormatter>[
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                      ],
                      decoration: InputDecoration(
                        labelText: gold
                            ? '成本 / 元每克'
                            : fund
                            ? '单位成本 / 元每份'
                            : '成本 / 元每股',
                      ),
                    ),
                  ),
                ],
              ),
              if (_error != null) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: TextStyle(fontSize: 12, color: palette.negative),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: busy ? null : _submit,
          child: const Text('保存持仓'),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// 账单弹窗。
// -----------------------------------------------------------------------------

final class _BillDraft {
  const _BillDraft({required this.amount, this.principal});
  final Rational amount;
  final Rational? principal;
}

final class _PlanRow {
  const _PlanRow({
    required this.kind,
    required this.planId,
    required this.label,
    required this.isRent,
    required this.month,
    required this.bill,
  });

  final ExpenseKind kind;
  final String planId;
  final String label;
  final bool isRent;
  final LocalDate month;
  final MonthlyBill? bill;
}

class _BillDialog extends ConsumerStatefulWidget {
  const _BillDialog({
    required this.title,
    required this.kindLabel,
    required this.monthLabel,
    required this.isRent,
    required this.initialAmount,
    required this.initialPrincipal,
    this.confirmLabel = '保存',
    this.note,
  });

  final String title;
  final String kindLabel;
  final String monthLabel;
  final bool isRent;
  final String initialAmount;
  final String initialPrincipal;
  final String confirmLabel;
  final String? note;

  @override
  ConsumerState<_BillDialog> createState() => _BillDialogState();
}

class _BillDialogState extends ConsumerState<_BillDialog> {
  late final TextEditingController _amount = TextEditingController(
    text: widget.initialAmount,
  );
  late final TextEditingController _principal = TextEditingController(
    text: widget.initialPrincipal,
  );
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _principal.dispose();
    super.dispose();
  }

  void _submit() {
    final Rational? amount = _ConfigPageState._parseDecimal(
      _amount.text.trim(),
      maxScale: 2,
    );
    if (amount == null || amount.isNegative || amount > _maxMoney) {
      setState(() => _error = '标准月额需要是 0 到 10,000,000 元之间的金额。');
      return;
    }
    Rational? principal;
    if (!widget.isRent && _principal.text.trim().isNotEmpty) {
      principal = _ConfigPageState._parseDecimal(
        _principal.text.trim(),
        maxScale: 2,
      );
      if (principal == null || principal.isNegative) {
        setState(() => _error = '本金需要是非负金额，或留空表示未知。');
        return;
      }
      if (principal > amount) {
        setState(() => _error = '本金超过了本月月供，请核对账单。生活暂时还没学会这个算法。');
        return;
      }
    }
    Navigator.pop(context, _BillDraft(amount: amount, principal: principal));
  }

  @override
  Widget build(BuildContext context) {
    final FjobPalette palette = context.palette;
    final bool busy = ref.watch(busyProvider);
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                '${widget.kindLabel} · ${widget.monthLabel}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              if (widget.note != null) ...<Widget>[
                const SizedBox(height: 6),
                Text(
                  widget.note!,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _amount,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                decoration: const InputDecoration(labelText: '标准月额 / 元'),
                onChanged: (_) => setState(() => _error = null),
              ),
              if (!widget.isRent) ...<Widget>[
                const SizedBox(height: 10),
                TextField(
                  controller: _principal,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  decoration: const InputDecoration(
                    labelText: '其中本金 / 元（选填）',
                    hintText: '未知可留空，填 0 表示确认为 0',
                  ),
                ),
              ],
              if (_error != null) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: TextStyle(fontSize: 12, color: palette.negative),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: busy ? null : _submit,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
