import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:finance_core/finance_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fjob_ui/fjob_ui.dart';
import 'package:ledger_store/ledger_store.dart';
import 'package:market_data/market_data.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:todayagain_desktop/desktop_controller.dart';
import 'package:todayagain_desktop/main_window.dart';
import 'package:todayagain_desktop/state/providers.dart';

Widget _app() {
  final desktop = DesktopController(
    mainWindow: WindowController.fromWindowId('main'),
  );
  final calendar = BusinessCalendar.shanghai;
  return ProviderScope(
    overrides: [
      desktopControllerProvider.overrideWithValue(desktop),
      calendarProvider.overrideWithValue(calendar),
      marketClientProvider.overrideWithValue(FixtureMarketClient(calendar)),
      ledgerRepositoryProvider.overrideWith((ref) async {
        final db = await AppDatabase.open(
          factory: databaseFactoryFfi,
          path: inMemoryDatabasePath,
          calendar: calendar,
        );
        ref.onDispose(db.close);
        return LedgerRepository(db, calendar);
      }),
    ],
    child: MaterialApp(theme: FjobTheme.light(), home: const MainWindow()),
  );
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  testWidgets('welcome import button opens the data page', (tester) async {
    tester.view.physicalSize = const Size(1000, 680);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    expect(find.text('把工位也拉进这场求生。'), findsOneWidget);

    await tester.tap(find.text('从手机导入 .fjob（推荐）'));
    await tester.pumpAndSettle();
    expect(find.text('把工位也拉进这场求生。'), findsNothing);
    expect(find.text('导入 / 导出'), findsOneWidget);
  });

  testWidgets('welcome start button opens the config page', (tester) async {
    tester.view.physicalSize = const Size(1000, 680);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('从零开始配置'));
    await tester.pumpAndSettle();
    expect(find.text('把工位也拉进这场求生。'), findsNothing);
    expect(find.text('收入与排班'), findsOneWidget);
  });
}
