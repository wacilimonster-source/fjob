/// Shared test wiring: FFI SQLite, a fixed clock and a recording widget bridge.
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:finance_core/finance_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqlite3/open.dart';
import 'package:todayagain/app/clock.dart';
import 'package:todayagain/app/providers.dart';
import 'package:todayagain/data/widget_bridge.dart';
import 'package:todayagain/domain/setup_draft.dart';

final DateTime fixedNow = DateTime.utc(2026, 11, 4, 6, 36);

bool _ffiReady = false;

/// Windows has no `sqlite3.dll`, but ships `winsqlite3.dll` with the same API.
void initSqliteFfi() {
  if (_ffiReady) return;
  if (Platform.isWindows) {
    open.overrideFor(
      OperatingSystem.windows,
      () => DynamicLibrary.open('winsqlite3.dll'),
    );
  }
  sqfliteFfiInit();
  _ffiReady = true;
}

/// Each test gets its own database file: the FFI factory shares a single
/// `:memory:` connection, which would leak rows between tests.
String newDatabasePath() {
  final directory = Directory.systemTemp.createTempSync('fjob_test');
  addTearDown(() {
    try {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    } on FileSystemException {
      // Windows may hold the sqlite journal briefly; the temp dir is disposable.
    }
  });
  return '${directory.path}/ledger.db';
}

List<Override> testOverrides({
  DateTime? now,
  RecordingWidgetBridge? bridge,
  String? databasePath,
}) {
  initSqliteFfi();
  final path = databasePath ?? newDatabasePath();
  return [
    databaseFactoryProvider.overrideWithValue(databaseFactoryFfiNoIsolate),
    databasePathProvider.overrideWith((ref) async => path),
    clockProvider.overrideWithValue(FixedClock(now ?? fixedNow)),
    widgetBridgeProvider.overrideWithValue(bridge ?? RecordingWidgetBridge()),
    widgetTimelineEnabledProvider.overrideWithValue(false),
    deepLinksEnabledProvider.overrideWithValue(false),
  ];
}

ProviderContainer makeContainer({
  DateTime? now,
  RecordingWidgetBridge? bridge,
}) {
  final container = ProviderContainer(
    overrides: testOverrides(now: now, bridge: bridge),
  );
  addTearDown(container.dispose);
  return container;
}

/// A draft that passes every step with a 12000 salary and no optional items.
SetupDraft validDraft(String sessionId) {
  return SetupDraft.fresh(sessionId, today: LocalDate(2026, 11, 4))
    ..salaryText = '12000';
}

/// A draft with a mortgage and a car loan, used by the commit tests.
SetupDraft housingDraft(String sessionId) {
  return validDraft(sessionId)
    ..housingMode = HousingMode.mortgage
    ..mortgageMonthlyText = '4800'
    ..mortgagePrincipalText = '2800'
    ..carEnabled = true
    ..carMonthlyText = '1800'
    ..carPrincipalText = '1500';
}

Map<String, dynamic> readWidgetSchema() {
  final file = File('../../contracts/widget-snapshot-v2.schema.json');
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

Map<String, dynamic> readWidgetSchemaV1() {
  final file = File('../../contracts/widget-snapshot.schema.json');
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

Map<String, dynamic> readWidgetFixtureV1() {
  final file = File('../../fixtures/widget-snapshot.json');
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}
