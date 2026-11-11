import 'package:flutter_test/flutter_test.dart';
import 'package:todayagain_desktop/desktop_preferences.dart';

void main() {
  test('defaults match the design', () {
    final prefs = DesktopPreferences.defaults();
    expect(prefs.density, 'm');
    expect(prefs.metrics, 'both');
    expect(prefs.topmost, isTrue);
    expect(prefs.privacy, isFalse);
    expect(prefs.opacity, 1.0);
  });

  test('rejects out-of-range opacity and unknown keys', () {
    expect(() => DesktopPreferences.fromJson({'opacity': 0.5}),
        throwsA(isA<DesktopPreferenceException>()));
    expect(() => DesktopPreferences.fromJson({'density': 'xl'}),
        throwsA(isA<DesktopPreferenceException>()));
    expect(() => DesktopPreferences.fromJson({'ledgerRevision': 9}),
        throwsA(isA<DesktopPreferenceException>()));
  });

  test('rejects duplicate hotkey letters', () {
    expect(
        () => DesktopPreferences.fromJson({'bossKey': 'H', 'privacyKey': 'H'}),
        throwsA(isA<DesktopPreferenceException>()));
  });

  test('withValue updates immutably and validates position', () {
    final prefs = DesktopPreferences.defaults();
    final next = prefs.withValue('density', 'l');
    expect(next.density, 'l');
    expect(prefs.density, 'm');
    final positioned = next.withValue('position', {
      'x': 100.0,
      'y': 200.0,
      'displayId': r'\\.\DISPLAY1',
    });
    expect(positioned.position!['displayId'], r'\\.\DISPLAY1');
    expect(() => next.withValue('position', {'x': 1.0}),
        throwsA(isA<DesktopPreferenceException>()));
  });
}
