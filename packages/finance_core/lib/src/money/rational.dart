/// Exact rational arithmetic used for every money, quantity and rate value.
///
/// The contracts forbid accumulating money with binary floating point, and
/// require the raw precision to survive until the display rounding step. A
/// `BigInt` numerator over a `BigInt` denominator reproduces the reference
/// fixtures exactly (for example `6600 / 30 * 30 == 6600`).
library;

/// An immutable, always reduced, exactly representable rational number.
final class Rational implements Comparable<Rational> {
  Rational._(this.numerator, this.denominator);

  /// Builds `numerator / denominator`. The denominator must not be zero.
  factory Rational(BigInt numerator, [BigInt? denominator]) {
    final d = denominator ?? BigInt.one;
    if (d == BigInt.zero) {
      throw ArgumentError.value(d, 'denominator', 'must not be zero');
    }
    var n = numerator;
    var den = d;
    if (den.isNegative) {
      n = -n;
      den = -den;
    }
    if (n == BigInt.zero) {
      return Rational._(BigInt.zero, BigInt.one);
    }
    final gcd = n.gcd(den);
    return Rational._(n ~/ gcd, den ~/ gcd);
  }

  factory Rational.fromInt(int value) => Rational(BigInt.from(value));

  static final Rational zero = Rational._(BigInt.zero, BigInt.one);
  static final Rational one = Rational._(BigInt.one, BigInt.one);

  static final RegExp _decimalPattern = RegExp(r'^([+-]?)(\d+)(?:\.(\d+))?$');

  /// Parses a canonical decimal string such as `12000`, `0.05` or `-350.00`.
  ///
  /// Only plain decimal notation is accepted: JSON payloads and the database
  /// use that form, and silently accepting `1e3` would hide typos in stored
  /// ledger data.
  factory Rational.parse(String value) {
    final match = _decimalPattern.firstMatch(value.trim());
    if (match == null) {
      throw FormatException('Invalid decimal value', value);
    }
    final fraction = match.group(3) ?? '';
    final digits = BigInt.parse('${match.group(2)!}$fraction');
    final scaled =
        fraction.isEmpty ? BigInt.one : BigInt.from(10).pow(fraction.length);
    final signed = match.group(1) == '-' ? -digits : digits;
    return Rational(signed, scaled);
  }

  static Rational? tryParse(String? value) {
    if (value == null) return null;
    try {
      return Rational.parse(value);
    } on FormatException {
      return null;
    }
  }

  final BigInt numerator;
  final BigInt denominator;

  bool get isZero => numerator == BigInt.zero;
  bool get isNegative => numerator.isNegative;
  bool get isPositive => numerator > BigInt.zero;

  Rational operator +(Rational other) => Rational(
        numerator * other.denominator + other.numerator * denominator,
        denominator * other.denominator,
      );

  Rational operator -(Rational other) => Rational(
        numerator * other.denominator - other.numerator * denominator,
        denominator * other.denominator,
      );

  Rational operator *(Rational other) =>
      Rational(numerator * other.numerator, denominator * other.denominator);

  Rational operator /(Rational other) {
    if (other.isZero) {
      throw ArgumentError.value(other, 'other', 'division by zero');
    }
    return Rational(numerator * other.denominator, denominator * other.numerator);
  }

  Rational operator -() => Rational._(-numerator, denominator);

  Rational abs() => numerator.isNegative ? -this : this;

  Rational get reciprocal => Rational(denominator, numerator);

  /// Multiplies by an integer count (seconds, days, shares).
  Rational timesInt(int value) => this * Rational.fromInt(value);

  @override
  int compareTo(Rational other) =>
      (numerator * other.denominator).compareTo(other.numerator * denominator);

  bool operator >(Rational other) => compareTo(other) > 0;
  bool operator >=(Rational other) => compareTo(other) >= 0;
  bool operator <(Rational other) => compareTo(other) < 0;
  bool operator <=(Rational other) => compareTo(other) <= 0;

  /// Rounds half away from zero at [scale] decimal places.
  ///
  /// JSON amount strings and the fixtures use `ROUND_HALF_UP`; for negative
  /// values that means away from zero, matching Python's `Decimal` behaviour.
  BigInt roundHalfUp(int scale) {
    if (scale < 0) throw ArgumentError.value(scale, 'scale', 'must be >= 0');
    final factor = BigInt.from(10).pow(scale);
    final scaled = numerator * factor;
    final negative = scaled.isNegative;
    final magnitude = scaled.abs();
    // round(|n| * 10^scale / d) using floor((2*|n|*10^scale + d) / (2*d)).
    final rounded = (magnitude * BigInt.two + denominator) ~/ (denominator * BigInt.two);
    return negative ? -rounded : rounded;
  }

  /// Fixed-point string with [scale] decimals, `-0.00` normalised to `0.00`.
  String toFixed(int scale) {
    final rounded = roundHalfUp(scale);
    final factor = BigInt.from(10).pow(scale);
    final negative = rounded.isNegative;
    final magnitude = rounded.abs();
    final whole = magnitude ~/ factor;
    if (scale == 0) {
      return negative ? '-$whole' : '$whole';
    }
    final fraction = (magnitude % factor).toString().padLeft(scale, '0');
    final sign = negative ? '-' : '';
    return '$sign$whole.$fraction';
  }

  /// Display amount: always two decimals, never negative zero.
  String toDisplayString() => toFixed(2);

  /// Plain decimal string without the forced two decimals, used for storage of
  /// user-entered precision (three decimal share counts, for example).
  String toCanonicalString({int maxScale = 18}) {
    if (denominator == BigInt.one) return numerator.toString();
    final factor = BigInt.from(10);
    var power = factor;
    for (var scale = 1; scale <= maxScale; scale++) {
      if (denominator == power || power % denominator == BigInt.zero) {
        return toFixed(scale);
      }
      power *= factor;
    }
    return toFixed(maxScale);
  }

  @override
  String toString() => denominator == BigInt.one
      ? numerator.toString()
      : '${numerator.toString()}/${denominator.toString()}';

  @override
  bool operator ==(Object other) =>
      other is Rational &&
      other.numerator == numerator &&
      other.denominator == denominator;

  @override
  int get hashCode => Object.hash(numerator, denominator);
}
