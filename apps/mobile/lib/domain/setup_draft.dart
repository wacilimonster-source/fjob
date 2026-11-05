/// Onboarding draft, per-field validation and the validated commit payload.
library;

import 'package:finance_core/finance_core.dart';

import 'ledger.dart';

const String goldInstrumentId = 'GOLD.CNY_GRAM.AU9999';
const String goldInstrumentName = '上金所 Au99.99 参考价';

enum StockMarket { sse, szse, bse }

extension StockMarketX on StockMarket {
  String get prefix => switch (this) {
        StockMarket.sse => 'CN.SH',
        StockMarket.szse => 'CN.SZ',
        StockMarket.bse => 'CN.BJ',
      };

  String get label => switch (this) {
        StockMarket.sse => '沪',
        StockMarket.szse => '深',
        StockMarket.bse => '京',
      };
}

final class HoldingDraft {
  const HoldingDraft({
    this.market = StockMarket.szse,
    this.code = '',
    this.name = '',
    this.quantityText = '',
    this.costText = '',
  });

  final StockMarket market;
  final String code;
  final String name;
  final String quantityText;
  final String costText;

  String get instrumentId => '${market.prefix}.$code';

  HoldingDraft copyWith({
    StockMarket? market,
    String? code,
    String? name,
    String? quantityText,
    String? costText,
  }) =>
      HoldingDraft(
        market: market ?? this.market,
        code: code ?? this.code,
        name: name ?? this.name,
        quantityText: quantityText ?? this.quantityText,
        costText: costText ?? this.costText,
      );

  Map<String, dynamic> toJson() => {
        'market': market.name,
        'code': code,
        'name': name,
        'quantity': quantityText,
        'cost': costText,
      };

  static HoldingDraft fromJson(Map<String, dynamic> json) => HoldingDraft(
        market: StockMarket.values.firstWhere(
          (value) => value.name == json['market'],
          orElse: () => StockMarket.szse,
        ),
        code: LedgerJson.asString(json['code']),
        name: LedgerJson.asString(json['name']),
        quantityText: LedgerJson.asString(json['quantity']),
        costText: LedgerJson.asString(json['cost']),
      );
}

enum ScheduleMode { fixed, bigSmall }

final class SetupDraft {
  SetupDraft({
    required this.setupSessionId,
    this.step = 0,
    this.salaryText = '',
    this.salaryEffectiveDate = '',
    List<bool>? workdays,
    this.shiftStart = '09:00',
    this.shiftEnd = '18:00',
    this.breakEnabled = true,
    this.breakStart = '12:00',
    this.breakEnd = '13:00',
    this.scheduleMode = ScheduleMode.fixed,
    this.extraSaturday = true,
    this.anchorIsBig = true,
    this.anchorMonday = '',
    List<HoldingDraft>? holdings,
    this.goldEnabled = false,
    this.goldQuantityText = '',
    this.goldCostText = '',
    this.housingMode = HousingMode.none,
    this.mortgageMonthlyText = '',
    this.mortgagePrincipalText = '',
    this.rentMonthlyText = '',
    this.rentNote = '',
    this.carEnabled = false,
    this.carMonthlyText = '',
    this.carPrincipalText = '',
    this.widgetPrivacy = false,
  })  : workdays = workdays ?? [true, true, true, true, true, false, false],
        holdings = holdings ?? <HoldingDraft>[];

  factory SetupDraft.fresh(String sessionId, {LocalDate? today}) {
    final date = today ?? LocalDate(2026, 1, 1);
    return SetupDraft(
      setupSessionId: sessionId,
      salaryEffectiveDate: date.firstOfMonth.toIsoString(),
      anchorMonday: date.mondayOfWeek.toIsoString(),
    );
  }

  /// Prefills the redo-onboarding flow from the committed ledger.
  factory SetupDraft.fromLedger(
    LedgerState ledger,
    String sessionId, {
    required LocalDate today,
    required DateTime nowUtc,
  }) {
    final salary = ledger.salaryVersions.isEmpty
        ? null
        : (ledger.salaryVersions.toList()
              ..sort((a, b) => b.effectiveFromUtc.compareTo(a.effectiveFromUtc)))
            .firstWhere(
              (version) => version.covers(nowUtc),
              orElse: () => ledger.salaryVersions.last,
            );
    final schedule = salary == null
        ? null
        : ledger.schedules[salary.scheduleVersionId];

    var shiftStart = '09:00';
    var shiftEnd = '18:00';
    var breakEnabled = true;
    var breakStart = '12:00';
    var breakEnd = '13:00';
    var scheduleMode = ScheduleMode.fixed;
    var extraSaturday = true;
    var anchorIsBig = true;
    final workdays = List<bool>.filled(7, false);
    ShiftTemplate? firstShift;
    if (schedule != null) {
      if (schedule.alternation != null) {
        scheduleMode = ScheduleMode.bigSmall;
        anchorIsBig = schedule.alternation!.isBigWeek(today);
        extraSaturday =
            schedule.alternation!.bigWeek.byWeekday[5].isNotEmpty;
      }
      for (var index = 0; index < 7; index++) {
        final shifts = schedule.week.byWeekday[index];
        workdays[index] = shifts.isNotEmpty;
        firstShift ??= shifts.isEmpty ? null : shifts.first;
      }
    }
    if (firstShift != null) {
      String clock(int minute) {
        final normalized = minute % 1440;
        return '${(normalized ~/ 60).toString().padLeft(2, '0')}:'
            '${(normalized % 60).toString().padLeft(2, '0')}';
      }

      shiftStart = clock(firstShift.startMinute);
      shiftEnd = clock(firstShift.endMinute);
      if (firstShift.breaks.isEmpty) {
        breakEnabled = false;
      } else {
        breakStart = clock(firstShift.breaks.first.startMinute);
        breakEnd = clock(firstShift.breaks.first.endMinute);
      }
    }

    final currentHoldings = <String, Holding>{};
    for (final holding in ledger.holdings) {
      if (!holding.covers(nowUtc)) continue;
      final existing = currentHoldings[holding.instrumentId];
      if (existing == null ||
          holding.effectiveFromUtc.isAfter(existing.effectiveFromUtc)) {
        currentHoldings[holding.instrumentId] = holding;
      }
    }
    final goldHolding = currentHoldings.remove(goldInstrumentId);

    HousingVersion? housing;
    for (final version in ledger.housingVersions) {
      if (!version.covers(nowUtc)) continue;
      if (housing == null ||
          version.effectiveFromUtc.isAfter(housing.effectiveFromUtc)) {
        housing = version;
      }
    }
    CarVersion? car;
    for (final version in ledger.carVersions) {
      if (!version.covers(nowUtc)) continue;
      if (car == null || version.effectiveFromUtc.isAfter(car.effectiveFromUtc)) {
        car = version;
      }
    }
    final month = today.firstOfMonth;
    MonthlyBill? housingBill;
    for (final bill in ledger.bills) {
      if (bill.expenseId == housing?.id && bill.month == month) {
        housingBill = bill;
      }
    }
    MonthlyBill? carBill;
    for (final bill in ledger.bills) {
      if (bill.expenseId == car?.id && bill.month == month) {
        carBill = bill;
      }
    }

    final drafts = <HoldingDraft>[];
    for (final entry in currentHoldings.values) {
      final id = entry.instrumentId;
      final parts = id.split('.');
      if (parts.length < 3) continue;
      final market = StockMarket.values.firstWhere(
        (value) => value.prefix == '${parts[0]}.${parts[1]}',
        orElse: () => StockMarket.szse,
      );
      drafts.add(
        HoldingDraft(
          market: market,
          code: parts[2],
          name: ledger.instrumentNames[id] ?? '',
          quantityText: entry.quantity.toCanonicalString(maxScale: 0),
          costText: entry.costPerUnit.toCanonicalString(maxScale: 3),
        ),
      );
    }

    return SetupDraft(
      setupSessionId: sessionId,
      salaryText: salary?.monthlyNetCny.toCanonicalString() ?? '',
      salaryEffectiveDate: today.mondayOfWeek.toIsoString(),
      workdays: workdays,
      scheduleMode: scheduleMode,
      extraSaturday: extraSaturday,
      anchorIsBig: anchorIsBig,
      anchorMonday: today.mondayOfWeek.toIsoString(),
      shiftStart: shiftStart,
      shiftEnd: shiftEnd,
      breakEnabled: breakEnabled,
      breakStart: breakStart,
      breakEnd: breakEnd,
      holdings: drafts,
      goldEnabled: goldHolding != null,
      goldQuantityText: goldHolding?.quantity.toCanonicalString(maxScale: 3) ?? '',
      goldCostText: goldHolding?.costPerUnit.toCanonicalString() ?? '',
      housingMode: housing?.mode ?? HousingMode.none,
      mortgageMonthlyText: housing?.mode == HousingMode.mortgage
          ? (housingBill?.monthlyAmountCny?.toCanonicalString() ?? '')
          : '',
      mortgagePrincipalText: housing?.mode == HousingMode.mortgage
          ? (housingBill?.principalCny?.toCanonicalString() ?? '')
          : '',
      rentMonthlyText: housing?.mode == HousingMode.rent
          ? (housingBill?.monthlyAmountCny?.toCanonicalString() ?? '')
          : '',
      rentNote: '',
      carEnabled: car?.enabled ?? false,
      carMonthlyText: carBill?.monthlyAmountCny?.toCanonicalString() ?? '',
      carPrincipalText: carBill?.principalCny?.toCanonicalString() ?? '',
      widgetPrivacy: ledger.settings.widgetPrivacy,
    );
  }

  String setupSessionId;
  int step;
  String salaryText;
  String salaryEffectiveDate;

  /// Monday-first workday selection.
  List<bool> workdays;
  String shiftStart;
  String shiftEnd;
  bool breakEnabled;
  String breakStart;
  String breakEnd;

  ScheduleMode scheduleMode;
  bool extraSaturday;
  bool anchorIsBig;
  String anchorMonday;

  List<HoldingDraft> holdings;
  bool goldEnabled;
  String goldQuantityText;
  String goldCostText;

  HousingMode housingMode;
  String mortgageMonthlyText;
  String mortgagePrincipalText;
  String rentMonthlyText;
  String rentNote;

  bool carEnabled;
  String carMonthlyText;
  String carPrincipalText;

  bool widgetPrivacy;

  static const int stepCount = 6;

  Map<String, dynamic> toJson() => {
        'setupSessionId': setupSessionId,
        'step': step,
        'salary': salaryText,
        'salaryEffectiveDate': salaryEffectiveDate,
        'workdays': workdays,
        'shiftStart': shiftStart,
        'shiftEnd': shiftEnd,
        'breakEnabled': breakEnabled,
        'breakStart': breakStart,
        'breakEnd': breakEnd,
        'scheduleMode': scheduleMode.name,
        'extraSaturday': extraSaturday,
        'anchorIsBig': anchorIsBig,
        'anchorMonday': anchorMonday,
        'holdings': [for (final holding in holdings) holding.toJson()],
        'goldEnabled': goldEnabled,
        'goldQuantity': goldQuantityText,
        'goldCost': goldCostText,
        'housingMode': housingMode.name,
        'mortgageMonthly': mortgageMonthlyText,
        'mortgagePrincipal': mortgagePrincipalText,
        'rentMonthly': rentMonthlyText,
        'rentNote': rentNote,
        'carEnabled': carEnabled,
        'carMonthly': carMonthlyText,
        'carPrincipal': carPrincipalText,
        'widgetPrivacy': widgetPrivacy,
      };

  static SetupDraft fromJson(Map<String, dynamic> json) {
    final rawWorkdays = json['workdays'];
    final rawHoldings = json['holdings'];
    return SetupDraft(
      setupSessionId: LedgerJson.asString(json['setupSessionId']),
      step: LedgerJson.asInt(json['step']),
      salaryText: LedgerJson.asString(json['salary']),
      salaryEffectiveDate: LedgerJson.asString(json['salaryEffectiveDate']),
      workdays: rawWorkdays is List
          ? [
              for (var index = 0; index < 7; index++)
                index < rawWorkdays.length &&
                    LedgerJson.asBool(rawWorkdays[index]),
            ]
          : null,
      shiftStart: LedgerJson.asString(json['shiftStart'], fallback: '09:00'),
      shiftEnd: LedgerJson.asString(json['shiftEnd'], fallback: '18:00'),
      breakEnabled: LedgerJson.asBool(json['breakEnabled'], fallback: true),
      breakStart: LedgerJson.asString(json['breakStart'], fallback: '12:00'),
      breakEnd: LedgerJson.asString(json['breakEnd'], fallback: '13:00'),
      scheduleMode: ScheduleMode.values.firstWhere(
        (value) => value.name == json['scheduleMode'],
        orElse: () => ScheduleMode.fixed,
      ),
      extraSaturday: LedgerJson.asBool(json['extraSaturday'], fallback: true),
      anchorIsBig: LedgerJson.asBool(json['anchorIsBig'], fallback: true),
      anchorMonday: LedgerJson.asString(json['anchorMonday']),
      holdings: rawHoldings is List
          ? [
              for (final item in rawHoldings)
                if (item is Map)
                  HoldingDraft.fromJson(item.cast<String, dynamic>()),
            ]
          : null,
      goldEnabled: LedgerJson.asBool(json['goldEnabled']),
      goldQuantityText: LedgerJson.asString(json['goldQuantity']),
      goldCostText: LedgerJson.asString(json['goldCost']),
      housingMode: HousingMode.values.firstWhere(
        (value) => value.name == json['housingMode'],
        orElse: () => HousingMode.none,
      ),
      mortgageMonthlyText: LedgerJson.asString(json['mortgageMonthly']),
      mortgagePrincipalText: LedgerJson.asString(json['mortgagePrincipal']),
      rentMonthlyText: LedgerJson.asString(json['rentMonthly']),
      rentNote: LedgerJson.asString(json['rentNote']),
      carEnabled: LedgerJson.asBool(json['carEnabled']),
      carMonthlyText: LedgerJson.asString(json['carMonthly']),
      carPrincipalText: LedgerJson.asString(json['carPrincipal']),
      widgetPrivacy: LedgerJson.asBool(json['widgetPrivacy']),
    );
  }

  SetupDraft copyWith({
    int? step,
    String? salaryText,
    String? salaryEffectiveDate,
    List<bool>? workdays,
    String? shiftStart,
    String? shiftEnd,
    bool? breakEnabled,
    String? breakStart,
    String? breakEnd,
    ScheduleMode? scheduleMode,
    bool? extraSaturday,
    bool? anchorIsBig,
    String? anchorMonday,
    List<HoldingDraft>? holdings,
    bool? goldEnabled,
    String? goldQuantityText,
    String? goldCostText,
    HousingMode? housingMode,
    String? mortgageMonthlyText,
    String? mortgagePrincipalText,
    String? rentMonthlyText,
    String? rentNote,
    bool? carEnabled,
    String? carMonthlyText,
    String? carPrincipalText,
    bool? widgetPrivacy,
  }) =>
      SetupDraft(
        setupSessionId: setupSessionId,
        step: step ?? this.step,
        salaryText: salaryText ?? this.salaryText,
        salaryEffectiveDate: salaryEffectiveDate ?? this.salaryEffectiveDate,
        workdays: workdays ?? this.workdays,
        shiftStart: shiftStart ?? this.shiftStart,
        shiftEnd: shiftEnd ?? this.shiftEnd,
        breakEnabled: breakEnabled ?? this.breakEnabled,
        breakStart: breakStart ?? this.breakStart,
        breakEnd: breakEnd ?? this.breakEnd,
        scheduleMode: scheduleMode ?? this.scheduleMode,
        extraSaturday: extraSaturday ?? this.extraSaturday,
        anchorIsBig: anchorIsBig ?? this.anchorIsBig,
        anchorMonday: anchorMonday ?? this.anchorMonday,
        holdings: holdings ?? this.holdings,
        goldEnabled: goldEnabled ?? this.goldEnabled,
        goldQuantityText: goldQuantityText ?? this.goldQuantityText,
        goldCostText: goldCostText ?? this.goldCostText,
        housingMode: housingMode ?? this.housingMode,
        mortgageMonthlyText:
            mortgageMonthlyText ?? this.mortgageMonthlyText,
        mortgagePrincipalText:
            mortgagePrincipalText ?? this.mortgagePrincipalText,
        rentMonthlyText: rentMonthlyText ?? this.rentMonthlyText,
        rentNote: rentNote ?? this.rentNote,
        carEnabled: carEnabled ?? this.carEnabled,
        carMonthlyText: carMonthlyText ?? this.carMonthlyText,
        carPrincipalText: carPrincipalText ?? this.carPrincipalText,
        widgetPrivacy: widgetPrivacy ?? this.widgetPrivacy,
      );

  /// Validates every step and returns either the commit payload or field
  /// errors. Raw text never reaches the domain objects.
  SetupValidation validate() {
    final errors = <String, String>{};

    final salary = _decimal(salaryText, maxScale: 2);
    if (salary == null) {
      errors['salary'] = '请输入到手月薪，最多两位小数。';
    } else if (salary.isNegative || salary > Rational.parse('10000000')) {
      errors['salary'] = '月薪需要在 0 到 10,000,000 元之间。';
    }

    final effectiveDate = LocalDate.tryParse(salaryEffectiveDate);
    if (effectiveDate == null) {
      errors['salaryEffectiveDate'] = '请选择生效日期。';
    }

    WeekTemplate? week;
    WeekAlternation? alternation;
    try {
      final schedule = buildSchedule();
      week = schedule.week;
      alternation = schedule.alternation;
      if (salary != null && salary.isPositive) {
        if (alternation != null && !week.hasAnyShift) {
          errors['schedule'] = '小周至少保留一个工作日，工资才有地方分摊。';
        } else if (!week.hasAnyShift) {
          errors['schedule'] = '这个月没有计薪时段，先给工资安排一个出场时间。';
        }
      }
    } on ScheduleValidationError catch (error) {
      errors['schedule'] = error.message;
    } on ArgumentError catch (error) {
      errors['schedule'] = '大小周配置有冲突：${error.message}';
    }

    final holdingCommits = <HoldingCommit>[];
    final seen = <String>{};
    for (var index = 0; index < holdings.length; index++) {
      final draft = holdings[index];
      if (draft.code.isEmpty && draft.quantityText.isEmpty) continue;
      if (!RegExp(r'^\d{6}$').hasMatch(draft.code)) {
        errors['holdings'] = '证券代码是 6 位数字，请核对。';
        break;
      }
      final quantity = _decimal(draft.quantityText, maxScale: 0);
      if (quantity == null || quantity.isNegative) {
        errors['holdings'] = '股票数量需要是非负整数。';
        break;
      }
      final cost = _decimal(draft.costText, maxScale: 3);
      if (cost == null || cost.isNegative || cost > Rational.parse('100000')) {
        errors['holdings'] = '每股成本需要是 0 到 100,000 之间的数字。';
        break;
      }
      if (!seen.add(draft.instrumentId)) {
        errors['holdings'] = '同一市场的同一代码只能保留一笔持仓，请编辑已有记录。';
        break;
      }
      holdingCommits.add(
        HoldingCommit(
          instrumentId: draft.instrumentId,
          name: draft.name.trim(),
          quantity: quantity,
          costPerUnit: cost,
        ),
      );
    }
    if (!errors.containsKey('holdings') && _hasIncompleteHolding()) {
      errors['holdings'] = '请补齐持仓的代码、数量与成本，或删除这一行。';
    }

    Rational? goldQuantity;
    Rational? goldCost;
    if (goldEnabled) {
      goldQuantity = _decimal(goldQuantityText, maxScale: 3);
      goldCost = _decimal(goldCostText, maxScale: 2);
      if (goldQuantity == null ||
          goldQuantity.isNegative ||
          goldQuantity > Rational.parse('1000000')) {
        errors['gold'] = '黄金克重需要是 0 到 1,000,000 之间的数字，最多三位小数。';
      }
      if (goldCost == null ||
          goldCost.isNegative ||
          goldCost > Rational.parse('100000')) {
        errors['gold'] = '每克成本需要是 0 到 100,000 之间的数字。';
      }
    }

    Rational? housingMonthly;
    Rational? housingPrincipal;
    switch (housingMode) {
      case HousingMode.mortgage:
        housingMonthly = _decimal(mortgageMonthlyText, maxScale: 2);
        if (housingMonthly == null ||
            housingMonthly.isNegative ||
            housingMonthly > Rational.parse('10000000')) {
          errors['housing'] = '本月月供需要是 0 到 10,000,000 元之间的金额。';
        }
        if (mortgagePrincipalText.trim().isNotEmpty) {
          housingPrincipal = _decimal(mortgagePrincipalText, maxScale: 2);
          if (housingPrincipal == null || housingPrincipal.isNegative) {
            errors['housing'] = '本金需要是非负金额，或留空表示未知。';
          } else if (housingMonthly != null &&
              housingPrincipal > housingMonthly) {
            errors['housing'] = '本金超过了本月月供，请核对账单。生活暂时还没学会这个算法。';
          }
        }
      case HousingMode.rent:
        housingMonthly = _decimal(rentMonthlyText, maxScale: 2);
        if (housingMonthly == null ||
            housingMonthly.isNegative ||
            housingMonthly > Rational.parse('10000000')) {
          errors['housing'] = '本月租金需要是 0 到 10,000,000 元之间的金额。';
        }
      case HousingMode.none:
        break;
    }

    Rational? carMonthly;
    Rational? carPrincipal;
    if (carEnabled) {
      carMonthly = _decimal(carMonthlyText, maxScale: 2);
      if (carMonthly == null ||
          carMonthly.isNegative ||
          carMonthly > Rational.parse('10000000')) {
        errors['car'] = '车贷月供需要是 0 到 10,000,000 元之间的金额。';
      }
      if (carPrincipalText.trim().isNotEmpty) {
        carPrincipal = _decimal(carPrincipalText, maxScale: 2);
        if (carPrincipal == null || carPrincipal.isNegative) {
          errors['car'] = '车贷本金需要是非负金额，或留空表示未知。';
        } else if (carMonthly != null && carPrincipal > carMonthly) {
          errors['car'] = '本金超过了本月车贷月供，请核对账单。';
        }
      }
    }

    if (errors.isNotEmpty) {
      return SetupValidation(errors: errors);
    }

    return SetupValidation(
      errors: const {},
      commit: SetupCommit(
        monthlySalary: salary!,
        effectiveDate: effectiveDate!,
        week: week!,
        alternation: alternation,
        holdings: holdingCommits,
        goldQuantity: goldEnabled ? goldQuantity : null,
        goldCost: goldEnabled ? goldCost : null,
        housingMode: housingMode,
        housingMonthly: housingMonthly,
        housingPrincipal: housingPrincipal,
        carEnabled: carEnabled,
        carMonthly: carEnabled ? carMonthly : null,
        carPrincipal: carPrincipal,
        widgetPrivacy: widgetPrivacy,
      ),
    );
  }

  bool _hasIncompleteHolding() => holdings.any(
        (draft) =>
            draft.quantityText.isNotEmpty &&
            (draft.code.isEmpty || draft.costText.isEmpty),
      );

  /// Builds the shift template from the raw shift text.
  ShiftTemplate buildShift() {
    final start = _timeToMinutes(shiftStart);
    if (start == null) {
      throw const ScheduleValidationError('invalidInterval', '上班时间格式应为 HH:mm。');
    }
    final rawEnd = _timeToMinutes(shiftEnd);
    if (rawEnd == null) {
      throw const ScheduleValidationError('invalidInterval', '下班时间格式应为 HH:mm。');
    }
    var end = rawEnd;
    if (end <= start) end += 1440;

    final breaks = <BreakTemplate>[];
    if (breakEnabled) {
      final breakFrom = _timeToMinutes(breakStart);
      final breakTo = _timeToMinutes(breakEnd);
      if (breakFrom == null || breakTo == null) {
        throw const ScheduleValidationError(
          'breakOutsideShift',
          '午休时间格式应为 HH:mm。',
        );
      }
      var resolvedFrom = breakFrom;
      var resolvedTo = breakTo;
      if (resolvedFrom < start) {
        resolvedFrom += 1440;
        resolvedTo += 1440;
      }
      breaks.add(BreakTemplate(startMinute: resolvedFrom, endMinute: resolvedTo));
    }

    final shift = ShiftTemplate(
      startMinute: start,
      endMinute: end,
      breaks: breaks,
    );
    shift.validate();
    return shift;
  }

  /// Fixed week, or the small week when 大小周 is selected.
  WeekTemplate buildWeek() => buildSchedule().week;

  /// Expands the draft into a fixed template or an alternating pattern.
  ({WeekTemplate week, WeekAlternation? alternation}) buildSchedule() {
    final shift = buildShift();
    final effectiveWorkdays = scheduleMode == ScheduleMode.fixed
        ? workdays
        : <bool>[for (var i = 0; i < 5; i++) workdays[i], false, false];
    final small = WeekTemplate([
      for (var index = 0; index < 7; index++)
        if (effectiveWorkdays[index])
          <ShiftTemplate>[shift]
        else
          const <ShiftTemplate>[],
    ]);
    if (scheduleMode == ScheduleMode.fixed) {
      return (week: small, alternation: null);
    }
    final anchor = LocalDate.tryParse(anchorMonday);
    if (anchor == null || !anchor.isMonday) {
      throw const ScheduleValidationError(
        'anchor',
        '大小周需要从周一开始生效，请把生效日期改成周一。',
      );
    }
    final bigAnchor = anchorIsBig ? anchor : anchor.addDays(-7);
    final bigDays = [
      for (final day in small.byWeekday) List<ShiftTemplate>.from(day),
    ];
    bigDays[extraSaturday ? 5 : 6] = <ShiftTemplate>[shift];
    final big = WeekTemplate(bigDays);
    return (
      week: small,
      alternation: WeekAlternation(
        smallWeek: small,
        bigWeek: big,
        anchorMonday: bigAnchor,
      ),
    );
  }
}

final class SetupValidation {
  const SetupValidation({required this.errors, this.commit});

  final Map<String, String> errors;
  final SetupCommit? commit;

  bool get isValid => commit != null && errors.isEmpty;

  String? errorFor(String key) => errors[key];

  String get firstError => errors.values.isEmpty ? '' : errors.values.first;
}

final class HoldingCommit {
  const HoldingCommit({
    required this.instrumentId,
    required this.name,
    required this.quantity,
    required this.costPerUnit,
  });

  final String instrumentId;
  final String name;
  final Rational quantity;
  final Rational costPerUnit;
}

/// Validated onboarding output, ready for a single database transaction.
final class SetupCommit {
  const SetupCommit({
    required this.monthlySalary,
    required this.effectiveDate,
    required this.week,
    required this.alternation,
    required this.holdings,
    required this.goldQuantity,
    required this.goldCost,
    required this.housingMode,
    required this.housingMonthly,
    required this.housingPrincipal,
    required this.carEnabled,
    required this.carMonthly,
    required this.carPrincipal,
    required this.widgetPrivacy,
  });

  final Rational monthlySalary;
  final LocalDate effectiveDate;
  final WeekTemplate week;
  final WeekAlternation? alternation;
  final List<HoldingCommit> holdings;
  final Rational? goldQuantity;
  final Rational? goldCost;
  final HousingMode housingMode;
  final Rational? housingMonthly;
  final Rational? housingPrincipal;
  final bool carEnabled;
  final Rational? carMonthly;
  final Rational? carPrincipal;
  final bool widgetPrivacy;

  bool get hasGold =>
      goldQuantity != null && goldCost != null && !goldQuantity!.isZero;
}

Rational? _decimal(String raw, {required int maxScale}) {
  final text = raw.trim();
  if (text.isEmpty) return null;
  final pattern = maxScale == 0
      ? RegExp(r'^\d+$')
      : RegExp('^\\d+(\\.\\d{1,$maxScale})?\$');
  if (!pattern.hasMatch(text)) return null;
  return Rational.parse(text);
}

int? _timeToMinutes(String value) {
  final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(value.trim());
  if (match == null) return null;
  final hour = int.parse(match.group(1)!);
  final minute = int.parse(match.group(2)!);
  if (hour > 23 || minute > 59) return null;
  return hour * 60 + minute;
}
