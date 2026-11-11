import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:todayagain_desktop/desktop_preferences.dart';

/// Regression: a real save/load cycle against the real filesystem. The
/// production writer used Directory.createTemp over a mixed-separator prefix,
/// which fails with ERROR_PATH_NOT_FOUND on Windows runners (flutter test,
/// dart run, the release exe) — every display change surfaced
/// 「显示设置没存上，请重试」and %APPDATA%/FJOB/pc_preferences.json was never
/// created. The writer now stages in a plain, uniquely-named file inside a
/// deterministic directory and hands normalized paths to the native replace.
void main() {
  test('real io: update persists, load round-trips, staging is cleaned up',
      () async {
    final base = Directory.systemTemp.path;
    final unique = 'prefs_real_io_${DateTime.now().microsecondsSinceEpoch}';
    final dir = Directory('$base${Platform.pathSeparator}$unique');
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    final store = DesktopPreferencesStore(dir.path);
    final updated = await store.update('density', 's');
    expect(updated.density, 's');
    expect(File(store.path).existsSync(), isTrue);
    expect(jsonBody(store.path), contains('"density":"s"'));

    final reloaded = await DesktopPreferencesStore(dir.path).load();
    expect(reloaded.density, 's');
    expect(reloaded.metrics, 'both');

    // The staging directory must not survive a committed save.
    final leftovers = dir
        .listSync()
        .whereType<Directory>()
        .where((d) => d.path.contains('.pc-preferences'))
        .toList();
    expect(leftovers, isEmpty, reason: 'staging directory should be removed');

    // A second save must still succeed (staging dir recreated per write).
    final second = await store.update('metrics', 'time');
    expect(second.metrics, 'time');
    expect(jsonBody(store.path), contains('"metrics":"time"'));
  }, timeout: const Timeout(Duration(seconds: 30)));
}

String jsonBody(String path) => File(path).readAsStringSync();
