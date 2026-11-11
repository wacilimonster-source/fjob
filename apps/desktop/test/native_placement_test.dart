import 'package:flutter_test/flutter_test.dart';
import 'package:todayagain_desktop/native_desktop.dart';

void main() {
  group('resolveWorkAreaLogical reconciles ambiguous visibleSize reports', () {
    const native = (width: 2560, height: 1379); // physical work area @125%

    test('logical report (screen_retriever 0.2.x on this machine)', () {
      final area = resolveWorkAreaLogical(
        reported: (width: 2048, height: 1103.2),
        origin: (dx: 0, dy: 0),
        scale: 1.25,
        nativeWorkArea: native,
      );
      // Report × scale matches the native measurement → already logical.
      expect(area.width, closeTo(2048, 0.01));
      expect(area.height, closeTo(1103.2, 0.01));
      expect(area.left, 0);
      expect(area.top, 0);
    });

    test('physical report (docs/19 PC0 assumption)', () {
      final area = resolveWorkAreaLogical(
        reported: (width: 2560, height: 1379),
        origin: (dx: 0, dy: 0),
        scale: 1.25,
        nativeWorkArea: native,
      );
      // Report matches native directly → divide by scale once.
      expect(area.width, closeTo(2048, 0.01));
      expect(area.height, closeTo(1103.2, 0.01));
    });

    test('physical report with taskbar-origin offset', () {
      final area = resolveWorkAreaLogical(
        reported: (width: 2560, height: 1379),
        origin: (dx: 0, dy: 60),
        scale: 1.25,
        nativeWorkArea: native,
      );
      expect(area.top, closeTo(48, 0.01));
      expect(area.height, closeTo(1103.2, 0.01));
    });

    test('missing native probe falls back to divide-by-scale', () {
      final area = resolveWorkAreaLogical(
        reported: (width: 2560, height: 1379),
        origin: (dx: 0, dy: 0),
        scale: 1.25,
        nativeWorkArea: null,
      );
      expect(area.width, closeTo(2048, 0.01));
      expect(area.height, closeTo(1103.2, 0.01));
    });

    test('degenerate scale never divides by zero', () {
      final area = resolveWorkAreaLogical(
        reported: (width: 2560, height: 1379),
        origin: (dx: 0, dy: 0),
        scale: 0,
        nativeWorkArea: native,
      );
      expect(area.width.isFinite, isTrue);
      expect(area.height.isFinite, isTrue);
    });
  });
}
