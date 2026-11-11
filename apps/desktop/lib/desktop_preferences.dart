import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'native_desktop.dart';

class DesktopPreferenceException implements Exception {
  const DesktopPreferenceException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Device-local display preferences only. No ledger values or ledgerRevision.
/// Position is a logical-pixel offset relative to the identified display's work
/// area. The card resolves displayId and handles disconnected-monitor fallback.
class DesktopPreferences {
  DesktopPreferences._(this._values);
  factory DesktopPreferences.defaults() => DesktopPreferences.fromJson({});

  static const defaultValues = <String, Object?>{
    'density': 'm',
    'metrics': 'both',
    'privacy': false,
    'topmost': true,
    'locked': false,
    'clickThrough': false,
    'opacity': 1.0,
    'showAtStartup': true,
    'fullscreenAutoHide': true,
    'reduceMotion': false,
    'position': null,
    'bossKey': 'H',
    'privacyKey': 'M',
    'clickThroughKey': 'L',
  };

  static const _booleans = {
    'privacy', 'topmost', 'locked', 'clickThrough', 'showAtStartup',
    'fullscreenAutoHide', 'reduceMotion',
  };
  static const _hotkeys = {'bossKey', 'privacyKey', 'clickThroughKey'};
  final Map<String, Object?> _values;

  factory DesktopPreferences.fromJson(Map<String, dynamic> json) {
    final values = Map<String, Object?>.from(defaultValues);
    for (final entry in json.entries) {
      values[entry.key] = validate(entry.key, entry.value);
    }
    if (_hotkeys.map((key) => values[key]).toSet().length != _hotkeys.length) {
      throw const DesktopPreferenceException('快捷键字母不能重复');
    }
    return DesktopPreferences._(Map.unmodifiable(values));
  }

  static Object? validate(String key, Object? value) {
    const invalid = DesktopPreferenceException('显示设置无效，请检查后重试');
    if (!defaultValues.containsKey(key)) throw invalid;
    if (_booleans.contains(key)) {
      if (value is! bool) throw invalid;
      return value;
    }
    if (_hotkeys.contains(key)) {
      if (value is! String || !RegExp(r'^[A-Z]$').hasMatch(value)) throw invalid;
      return value;
    }
    switch (key) {
      case 'density':
        if (!const {'s', 'm', 'l'}.contains(value)) throw invalid;
      case 'metrics':
        if (!const {'both', 'time', 'balance'}.contains(value)) throw invalid;
      case 'opacity':
        if (value is! num || !value.isFinite || value < .85 || value > 1) {
          throw invalid;
        }
        return value.toDouble();
      case 'position':
        if (value == null) return null;
        if (value is! Map ||
            value.length != 3 ||
            value['x'] is! num || value['y'] is! num ||
            !(value['x'] as num).isFinite ||
            !(value['y'] as num).isFinite ||
            value['displayId'] is! String ||
            (value['displayId'] as String).trim().isEmpty ||
            (value['displayId'] as String).length > 256) {
          throw invalid;
        }
        return Map<String, Object>.unmodifiable({
          'x': (value['x'] as num).toDouble(),
          'y': (value['y'] as num).toDouble(),
          'displayId': value['displayId'] as String,
        });
    }
    return value;
  }

  DesktopPreferences withValue(String key, Object? value) =>
      DesktopPreferences.fromJson({..._values, key: value});

  Object? operator [](String key) => _values[key];
  Map<String, dynamic> toJson() => Map<String, dynamic>.from(_values);
  String get density => _values['density'] as String;
  String get metrics => _values['metrics'] as String;
  bool get privacy => _values['privacy'] as bool;
  bool get topmost => _values['topmost'] as bool;
  bool get locked => _values['locked'] as bool;
  bool get clickThrough => _values['clickThrough'] as bool;
  double get opacity => _values['opacity'] as double;
  bool get showAtStartup => _values['showAtStartup'] as bool;
  bool get fullscreenAutoHide => _values['fullscreenAutoHide'] as bool;
  bool get reduceMotion => _values['reduceMotion'] as bool;
  Map<String, Object>? get position => _values['position'] as Map<String, Object>?;
  String get bossKey => _values['bossKey'] as String;
  String get privacyKey => _values['privacyKey'] as String;
  String get clickThroughKey => _values['clickThroughKey'] as String;
}

typedef DesktopPreferencesReader = Future<String?> Function(String path);
typedef DesktopPreferencesWriter = Future<void> Function(String path, String data);

/// One store owned by the main engine. Every operation is serialized; patches
/// are based on the last successful write, not an obsolete queued snapshot.
/// A failed write leaves [value] and the previous on-disk document unchanged.
class DesktopPreferencesStore {
  DesktopPreferencesStore(
    String directoryPath, {
    DesktopPreferencesReader? reader,
    DesktopPreferencesWriter? writer,
  }) : path = '${Directory(directoryPath).absolute.path}/pc_preferences.json',
       _reader = reader ?? _readFile,
       _writer = writer ?? _writeFile;

  final String path;
  final DesktopPreferencesReader _reader;
  final DesktopPreferencesWriter _writer;
  DesktopPreferences _value = DesktopPreferences.defaults();
  DesktopPreferences get value => _value;
  Future<void> _tail = Future<void>.value();

  /// The caller injects this directory into initializePreferences. Never fall
  /// back to the working directory when APPDATA is unavailable.
  static String defaultDirectory({Map<String, String>? environment}) {
    final appData = (environment ?? Platform.environment)['APPDATA'];
    if (appData == null || appData.trim().isEmpty) {
      throw const DesktopPreferenceException('无法定位本地显示设置目录');
    }
    return '$appData/FJOB';
  }

  Future<T> _serialize<T>(Future<T> Function() operation) {
    final task = _tail.then((_) => operation());
    _tail = task.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return task;
  }

  Future<DesktopPreferences> load() => _serialize(() async {
    try {
      final source = await _reader(path);
      if (source == null) return _value;
      final json = jsonDecode(source);
      if (json is! Map<String, dynamic> ||
          json['schemaVersion'] != 1 ||
          json['preferences'] is! Map<String, dynamic>) {
        throw const FormatException();
      }
      final loaded = DesktopPreferences.fromJson(
        json['preferences'] as Map<String, dynamic>,
      );
      _value = loaded;
      return loaded;
    } catch (_) {
      // No paths, values, OS errors, or financial data in user-facing errors.
      throw const DesktopPreferenceException('显示设置读取失败，请重试');
    }
  });

  Future<DesktopPreferences> update(String key, Object? value) {
    // Freeze mutable position maps before queueing.
    final frozen = DesktopPreferences.validate(key, value);
    return _serialize(() => _save(_value.withValue(key, frozen)));
  }

  Future<DesktopPreferences> save(DesktopPreferences value) =>
      _serialize(() => _save(value));

  Future<DesktopPreferences> _save(DesktopPreferences next) async {
    try {
      await _writer(path, jsonEncode({
        'schemaVersion': 1,
        'preferences': next.toJson(),
      }));
    } catch (_) {
      throw const DesktopPreferenceException('显示设置没存上，请重试');
    }
    _value = next;
    return next;
  }

  Future<void> flush() => _tail;

  static Future<String?> _readFile(String path) async {
    final file = File(path);
    if (!await file.exists()) return null;
    return file.readAsString();
  }

  static Future<void> _writeFile(String path, String data) async {
    final target = File(path);
    await target.parent.create(recursive: true);
    // Windows-only: callers build paths from strings like '\$appData/FJOB', so
    // separators can be mixed. Win32 MoveFileEx tolerates mixed input, but
    // Dart's createTemp does not (ERROR_PATH_NOT_FOUND), and staging creation
    // must not depend on the runner. Normalize once and use backslashes for
    // everything handed to native calls.
    final isWindows = Platform.isWindows;
    String native(String value) =>
        isWindows ? value.replaceAll('/', '\\') : value;
    final parent = native(target.parent.path);
    final targetPath = native(target.path);
    // Deterministic staging directory on the same volume, created with plain
    // Directory.create. The file inside is uniquely named so two racing
    // writers never stage into the same path; readers only ever consume the
    // committed target, and a crash can at worst leave staging data behind.
    final stagingPath =
        '$parent${isWindows ? '\\' : '/'}.pc-preferences';
    await Directory(stagingPath).create(recursive: true);
    try {
      final temporary = File('$stagingPath${isWindows ? '\\' : '/'}'
          '$pid-${DateTime.now().microsecondsSinceEpoch}.json');
      await temporary.writeAsString(data, flush: true);
      await replaceDesktopFile(native(temporary.path), targetPath);
    } finally {
      try {
        await Directory(stagingPath).delete(recursive: true);
      } catch (_) {
        // Cleanup failure must not report an already committed save as failed.
      }
    }
  }
}
