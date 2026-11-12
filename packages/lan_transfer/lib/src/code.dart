import 'dart:math';

/// Crockford base32 without I/L/O/U: 12 symbols carry 60 bits, enough that a
/// captured ciphertext cannot be brute-forced offline, while still being
/// typeable on a PC keyboard.
const String _alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
const int lanCodeLength = 12;

final class LanTransferCode {
  LanTransferCode._();

  static final Random _random = Random.secure();

  static String generate() => List<String>.generate(
        lanCodeLength,
        (_) => _alphabet[_random.nextInt(_alphabet.length)],
      ).join();

  /// Uppercases, drops separators, and applies Crockford's ambiguous-character
  /// mapping (I/L -> 1, O -> 0).
  static String normalize(String input) {
    final upper = input.toUpperCase().replaceAll(RegExp(r'[^0-9A-Z]'), '');
    return upper.replaceAll('I', '1').replaceAll('L', '1').replaceAll('O', '0');
  }

  static bool isValid(String input) {
    final normalized = normalize(input);
    return normalized.length == lanCodeLength &&
        normalized.split('').every(_alphabet.contains);
  }

  /// Groups a normalized code as XXXX-XXXX-XXXX for display.
  static String format(String input) {
    final normalized = normalize(input);
    if (normalized.length != lanCodeLength) return normalized;
    return '${normalized.substring(0, 4)}-'
        '${normalized.substring(4, 8)}-'
        '${normalized.substring(8)}';
  }
}
