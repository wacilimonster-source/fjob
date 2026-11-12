// 回归：资产/账单表格曾因横向滚动容器传无限宽度而整页布局作废
// （表头与空状态不可见、列塌缩粘连）。见 docs/22 §走查发现。
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

Future<ProviderContainer> _openConfigPage(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1250, 850);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(_app());
  final container = ProviderScope.containerOf(
    tester.element(find.byType(MainWindow)),
  );
  // 示例账本自带持仓与账单，不需要落库就能驱动两张表格。
  container.read(sampleModeProvider.notifier).state = true;
  await tester.pump(const Duration(seconds: 1));
  return container;
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  testWidgets('assets tab lays out header, empty state and columns', (
    tester,
  ) async {
    final container = await _openConfigPage(tester);
    addTearDown(container.dispose);

    await tester.tap(find.text('资产'));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(tester.takeException(), isNull, reason: '资产页布局不应抛异常');
    expect(find.text('资产持仓'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '添加持仓'), findsOneWidget);

    // 列不塌缩：名称列（flex 3）与持仓列（flex 2）之间应有实际列宽。
    final nameLeft = tester.getTopLeft(find.text('000001')).dx;
    final qtyLeft = tester.getTopLeft(find.text('1000 股')).dx;
    expect(qtyLeft - nameLeft, greaterThan(120), reason: '持仓列应左移到位');
  });

  testWidgets('bills tab lays out month card and bill columns', (
    tester,
  ) async {
    final container = await _openConfigPage(tester);
    addTearDown(container.dispose);

    await tester.tap(find.text('账单'));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(tester.takeException(), isNull, reason: '账单页布局不应抛异常');
    expect(find.text('账单月份'), findsOneWidget);
    expect(find.text('房贷'), findsOneWidget);

    final labelLeft = tester.getTopLeft(find.text('房贷')).dx;
    final amountLeft = tester.getTopLeft(find.text('¥4,800.00')).dx;
    expect(amountLeft - labelLeft, greaterThan(120), reason: '月额列应左移到位');
  });
}
