import 'package:finance_core/finance_core.dart';
import 'package:test/test.dart';

void main() {
  group('Rational', () {
    test('parses canonical decimals exactly', () {
      expect(Rational.parse('12000'), Rational.parse('12000.000'));
      expect(Rational.parse('0.05'), Rational.fromInt(1) / Rational.fromInt(20));
      expect(Rational.parse('-350.00'), Rational.fromInt(-350));
      expect(Rational.parse('0.001').toCanonicalString(), '0.001');
    });

    test('keeps raw precision until the display step', () {
      final cents = Rational.parse('0.004') + Rational.parse('0.004');
      expect(cents.toDisplayString(), '0.01');
      final whole = Rational.parse('6600') /
          Rational.fromInt(30) *
          Rational.fromInt(30);
      expect(whole, Rational.parse('6600'));
      expect(whole.toDisplayString(), '6600.00');
    });

    test('rounds half away from zero and never shows negative zero', () {
      expect(Rational.parse('0.005').toDisplayString(), '0.01');
      expect(Rational.parse('-0.005').toDisplayString(), '-0.01');
      expect(Rational.parse('-0.004').toDisplayString(), '0.00');
      expect(Rational.zero.toDisplayString(), '0.00');
    });

    test('rejects malformed decimal strings', () {
      expect(() => Rational.parse('1e3'), throwsFormatException);
      expect(() => Rational.parse('12,000'), throwsFormatException);
      expect(() => Rational.parse(''), throwsFormatException);
      expect(Rational.tryParse(null), isNull);
      expect(Rational.tryParse('abc'), isNull);
    });
  });

  group('LocalDate', () {
    test('parses, compares and moves across month boundaries', () {
      final date = LocalDate.parse('2026-11-04');
      expect(date.addDays(-4), LocalDate.parse('2026-10-31'));
      expect(date.addDays(26), LocalDate.parse('2026-11-30'));
      expect(date.addDays(27), LocalDate.parse('2026-12-01'));
      expect(date.firstOfMonth, LocalDate.parse('2026-11-01'));
      expect(date.daysInMonth, 30);
      expect(LocalDate(2028, 2, 1).daysInMonth, 29);
      expect(LocalDate(2026, 2, 1).daysInMonth, 28);
      expect(LocalDate(2026, 11, 4).weekday, DateTime.wednesday);
    });
  });

  group('BusinessCalendar', () {
    test('uses real day lengths from the tz database', () {
      final shanghai = BusinessCalendar.shanghai;
      expect(shanghai.dayLengthSeconds(LocalDate(2026, 11, 4)), 86400);
      expect(
        shanghai.dateOf(DateTime.utc(2026, 11, 4, 6, 36)),
        LocalDate(2026, 11, 4),
      );
      expect(
        shanghai.startOfDayUtc(LocalDate(2026, 11, 4)),
        DateTime.utc(2026, 11, 3, 16),
      );

      final newYork = BusinessCalendar.forZone('America/New_York');
      expect(newYork.dayLengthSeconds(LocalDate(2026, 3, 8)), 82800);
      expect(newYork.dayLengthSeconds(LocalDate(2026, 11, 1)), 90000);
    });
  });
}
