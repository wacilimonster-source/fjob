import 'package:finance_core/finance_core.dart';
import 'package:test/test.dart';

void main() {
  final calendar = BusinessCalendar.shanghai;
  final calculator = ExpenseCalculator(calendar);

  HousingVersion housing(
    HousingMode mode, {
    String id = 'housing-1',
    DateTime? from,
    DateTime? to,
  }) =>
      HousingVersion(
        id: id,
        mode: mode,
        effectiveFromUtc: from ?? DateTime.utc(2026, 1, 1),
        effectiveToUtc: to,
      );

  CarVersion carVersion({
    String id = 'car-1',
    bool enabled = true,
    DateTime? from,
    DateTime? to,
  }) =>
      CarVersion(
        id: id,
        enabled: enabled,
        effectiveFromUtc: from ?? DateTime.utc(2026, 1, 1),
        effectiveToUtc: to,
      );

  MonthlyBill bill({
    String expenseId = 'housing-1',
    ExpenseKind kind = ExpenseKind.housing,
    LocalDate? month,
    String? amount = '4800',
    String? principal = '2800',
    BillStatus status = BillStatus.confirmed,
  }) =>
      MonthlyBill(
        expenseId: expenseId,
        kind: kind,
        month: month ?? LocalDate(2026, 11, 1),
        monthlyAmountCny: amount == null ? null : Rational.parse(amount),
        principalCny: principal == null ? null : Rational.parse(principal),
        status: status,
      );

  DateTime at(int day, int hour, [int minute = 0]) =>
      DateTime.utc(2026, 11, day, hour - 8, minute);

  group('CALC-EXPENSE', () {
    test('AC-CALC-04 a stable plan conserves the monthly amount', () {
      final plan = housing(HousingMode.mortgage);
      expect(
        calculator.housingMonthTotal(
          month: LocalDate(2026, 11, 1),
          versions: [plan],
          bills: [bill()],
        ),
        Rational.parse('4800'),
      );
      expect(
        calculator.carMonthTotal(
          month: LocalDate(2026, 11, 1),
          versions: [carVersion()],
          bills: [
            bill(expenseId: 'car-1', kind: ExpenseKind.car, amount: '1800', principal: '1500'),
          ],
        ),
        Rational.parse('1800'),
      );
    });

    test('AC-CALC-04 February uses the real number of days', () {
      final plan = housing(HousingMode.rent, id: 'rent');
      final total = calculator.housingMonthTotal(
        month: LocalDate(2028, 2, 1),
        versions: [plan],
        bills: [
          bill(expenseId: 'rent', month: LocalDate(2028, 2, 1), amount: '2900', principal: null),
        ],
      );
      expect(total, Rational.parse('2900'));
      final day = calculator.housing(
        asOfUtc: calendar.endOfDayUtc(LocalDate(2028, 2, 10)),
        versions: [plan],
        bills: [
          bill(expenseId: 'rent', month: LocalDate(2028, 2, 1), amount: '2900', principal: null),
        ],
      );
      expect(day.dayShare, Rational.parse('2900') / Rational.fromInt(29));
    });

    test('14:36 allocates 97.33 of a 4800 mortgage', () {
      final result = calculator.housing(
        asOfUtc: at(4, 14, 36),
        versions: [housing(HousingMode.mortgage)],
        bills: [bill()],
      );
      expect(result.dayAmount!.toDisplayString(), '97.33');
      expect(result.dayShare.toDisplayString(), '160.00');
      expect(result.monthToDateAmount!.toDisplayString(), '577.33');
      expect(result.dayPrincipal!.toDisplayString(), '56.78');
      expect(result.dayInterest!.toDisplayString(), '40.56');
      expect(result.housingMode, HousingMode.mortgage);
      expect(result.configured, isTrue);
    });

    test('AC-CALC-05 a mid-month housing switch is allocated per period', () {
      final mortgage = housing(
        HousingMode.mortgage,
        id: 'mortgage',
        to: DateTime.utc(2026, 11, 15, 16), // Nov 16 00:00 Shanghai
      );
      final rent = housing(
        HousingMode.rent,
        id: 'rent',
        from: DateTime.utc(2026, 11, 15, 16),
      );
      final bills = [
        bill(expenseId: 'mortgage', amount: '4800', principal: '2800'),
        bill(
          expenseId: 'rent',
          amount: '3000',
          principal: null,
          month: LocalDate(2026, 11, 1),
        ),
      ];
      expect(
        calculator.housingMonthTotal(
          month: LocalDate(2026, 11, 1),
          versions: [mortgage, rent],
          bills: bills,
        ),
        Rational.parse('3900'),
      );
      final before = calculator.housing(
        asOfUtc: at(10, 12),
        versions: [mortgage, rent],
        bills: bills,
      );
      expect(before.housingMode, HousingMode.mortgage);
      final after = calculator.housing(
        asOfUtc: at(20, 12),
        versions: [mortgage, rent],
        bills: bills,
      );
      expect(after.housingMode, HousingMode.rent);
      expect(after.isRent, isTrue);
    });

    test('AC-CALC-06 rent is reported as rent and never as loan interest', () {
      final result = calculator.housing(
        asOfUtc: at(4, 14, 36),
        versions: [housing(HousingMode.rent, id: 'rent')],
        bills: [
          bill(expenseId: 'rent', amount: '3000', principal: null),
        ],
      );
      expect(result.dayRent!.toDisplayString(), '60.83');
      expect(result.dayPrincipal, Rational.zero);
      expect(result.dayInterest, Rational.zero);
      expect(result.breakdownKnown, isTrue);

      final car = calculator.car(
        asOfUtc: at(4, 14, 36),
        versions: [carVersion()],
        bills: [
          bill(expenseId: 'car-1', kind: ExpenseKind.car, amount: '1800', principal: '1500'),
        ],
      );
      expect(car.dayAmount!.toDisplayString(), '36.50');
      expect(car.dayInterest!.toDisplayString(), '6.08');
    });

    test('AC-ONB-06 an unknown principal keeps the amount and drops the split', () {
      final result = calculator.housing(
        asOfUtc: at(4, 14, 36),
        versions: [housing(HousingMode.mortgage)],
        bills: [bill(principal: null)],
      );
      expect(result.amountKnown, isTrue);
      expect(result.dayAmount!.toDisplayString(), '97.33');
      expect(result.dayPrincipal, isNull);
      expect(result.dayInterest, isNull);
      expect(result.breakdownKnown, isFalse);
    });

    test('an explicit zero principal produces full interest', () {
      final result = calculator.housing(
        asOfUtc: at(4, 12),
        versions: [housing(HousingMode.mortgage)],
        bills: [bill(principal: '0')],
      );
      expect(result.dayAmount!.toDisplayString(), '80.00');
      expect(result.dayPrincipal, Rational.zero);
      expect(result.dayInterest!.toDisplayString(), '80.00');
    });

    test('a missing bill keeps the amount unknown', () {
      final result = calculator.housing(
        asOfUtc: at(4, 14, 36),
        versions: [housing(HousingMode.mortgage)],
        bills: const [],
      );
      expect(result.configured, isTrue);
      expect(result.amountKnown, isFalse);
      expect(result.dayAmount, isNull);
      expect(result.missingMonths, ['2026-11']);
    });

    test('a carried-forward bill is flagged as an estimate', () {
      final result = calculator.housing(
        asOfUtc: at(4, 14, 36),
        versions: [housing(HousingMode.mortgage)],
        bills: [bill(status: BillStatus.carriedForwardEstimate)],
      );
      expect(result.estimate, isTrue);
      expect(result.dayAmount!.toDisplayString(), '97.33');
    });

    test('housing mode none and a disabled car are configured zeros', () {
      final none = calculator.housing(
        asOfUtc: at(4, 14, 36),
        versions: [housing(HousingMode.none)],
        bills: const [],
      );
      expect(none.configured, isFalse);
      expect(none.dayAmount, Rational.zero);
      expect(none.amountKnown, isTrue);

      final disabled = calculator.car(
        asOfUtc: at(4, 14, 36),
        versions: [carVersion(enabled: false)],
        bills: const [],
      );
      expect(disabled.configured, isFalse);
      expect(disabled.dayAmount, Rational.zero);
    });

    test('month-to-date sums whole days plus today', () {
      final result = calculator.housing(
        asOfUtc: at(4, 14, 36),
        versions: [housing(HousingMode.mortgage)],
        bills: [bill()],
      );
      // Nov 1-3 full days (160 each) plus today's 97.333…
      expect(result.monthToDateAmount!.toDisplayString(), '577.33');
    });
  });
}
