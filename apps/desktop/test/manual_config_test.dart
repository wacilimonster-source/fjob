// 回归：PC 端不导入手机账本、直接手动填写工资与排班后，主窗不能继续停在
// 欢迎面板，固定窗/预览也必须按已配置账本工作。见 docs/24。
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:finance_core/finance_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fjob_ui/fjob_ui.dart';
import 'package:ledger_model/ledger_model.dart';
import 'package:market_data/market_data.dart';
import 'package:todayagain_desktop/desktop_controller.dart';
import 'package:todayagain_desktop/main_window.dart';
import 'package:todayagain_desktop/state/providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('manually configured PC ledger leaves the welcome panel', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 680);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final calendar = BusinessCalendar.shanghai;
    final now = DateTime.utc(2026, 11, 12, 2);
    // 手动配置的结果：工资与排班齐全，但没有经过手机入职引导。
    final manuallyConfigured = buildDemoLedger(calendar, now)
        .copyWith(settings: const AppSettings());
    expect(manuallyConfigured.settings.hasCompletedOnboarding, isFalse);
    expect(manuallyConfigured.isConfigured, isTrue);

    final desktop = DesktopController(
      mainWindow: WindowController.fromWindowId('main'),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          desktopControllerProvider.overrideWithValue(desktop),
          calendarProvider.overrideWithValue(calendar),
          marketClientProvider.overrideWithValue(FixtureMarketClient(calendar)),
          effectiveLedgerProvider.overrideWithValue(
            AsyncData<LedgerState>(manuallyConfigured),
          ),
        ],
        child: MaterialApp(theme: FjobTheme.light(), home: const MainWindow()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('把工位也拉进这场求生。'), findsNothing,
        reason: '手动保存工资+排班后不应再显示导入欢迎面板');
    expect(find.text('收入与排班'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
