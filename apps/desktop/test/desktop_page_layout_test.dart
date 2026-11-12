// 回归：桌面页的即时预览曾在默认窗口尺寸下被挤到折叠线以下
// （所有设置即时预览、却看不到预览）。见 docs/22 §走查发现。
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

  testWidgets('desktop page shows preview side by side at default size', (
    tester,
  ) async {
    // 主窗默认 1000×680 逻辑像素（125% DPI 下即 1250×850 物理）。
    tester.view.physicalSize = const Size(1000, 680);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app());
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MainWindow)),
    );
    container.read(sampleModeProvider.notifier).state = true;
    await tester.pump(const Duration(seconds: 1));

    await tester.tap(find.text('桌面'));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(tester.takeException(), isNull, reason: '桌面页布局不应抛异常');
    final settings = find.text('显示项');
    final preview = find.text('固定窗预览');
    expect(settings, findsOneWidget);
    expect(preview, findsOneWidget);

    // 左右分栏：预览应与设置卡同一行，且在视口内即可见。
    final settingsRect = tester.getRect(settings);
    final previewRect = tester.getRect(preview);
    expect(previewRect.left, greaterThan(settingsRect.right - 40));
    expect(previewRect.top, lessThan(settingsRect.bottom + 8));
  });
}
