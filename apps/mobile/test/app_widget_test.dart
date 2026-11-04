import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todayagain/app/app.dart';
import 'package:todayagain/app/providers.dart';

import 'support/test_env.dart';

/// sqflite resolves its futures on the real event loop, so each pump also needs
/// a small real-time pause inside `runAsync`.
Future<void> settle(WidgetTester tester, {int rounds = 8}) async {
  for (var index = 0; index < rounds; index++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 120));
  }
}

void main() {
  testWidgets('onboarding commits and opens the dashboard', (tester) async {
    initSqliteFfi();
    tester.view.physicalSize = const Size(1080, 2200);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(overrides: testOverrides(), child: const FjobApp()),
    );
    await settle(tester);

    expect(find.text('办理入职'), findsOneWidget);
    await tester.tap(find.text('办理入职'));
    await tester.pump();

    expect(find.textContaining('生活给你多少安慰费'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).first, '12000');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('下一步，生活还在等'));
    await settle(tester, rounds: 3);

    expect(find.textContaining('几点上线'), findsOneWidget);
    await tester.tap(find.text('给工资安排出场时间'));
    await settle(tester, rounds: 3);

    expect(find.textContaining('钱包还在哪几个战场'), findsOneWidget);
    await tester.tap(find.text('支线已登记，继续'));
    await settle(tester, rounds: 3);

    expect(find.textContaining('登记生活的固定嘉宾'), findsOneWidget);
    await tester.tap(find.text('看看我的开局配置'));
    await settle(tester, rounds: 3);

    expect(find.textContaining('这就是你的开局配置'), findsOneWidget);
    await tester.tap(find.text('配置已阅，开始求生'));
    await settle(tester, rounds: 12);

    expect(find.text('今日生存结余'), findsOneWidget);
    expect(find.textContaining('328.57'), findsWidgets);
    expect(find.text('求生现场'), findsOneWidget);
    expect(find.text('固定牵挂'), findsOneWidget);
  });

  testWidgets('an empty salary blocks the step with a field message',
      (tester) async {
    initSqliteFfi();
    await tester.pumpWidget(
      ProviderScope(overrides: testOverrides(), child: const FjobApp()),
    );
    await settle(tester);
    await tester.tap(find.text('办理入职'));
    await tester.pump();
    await tester.tap(find.text('下一步，生活还在等'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('请输入到手月薪'), findsWidgets);
    expect(find.textContaining('生活给你多少安慰费'), findsOneWidget);
  });

  testWidgets('the interface stays paper-light when the system is dark',
      (tester) async {
    initSqliteFfi();
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...testOverrides(),
          sampleModeProvider.overrideWith((ref) => true),
        ],
        child: const FjobApp(),
      ),
    );
    for (var index = 0; index < 6; index++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
    expect(find.text('今日生存结余'), findsOneWidget);
    final context = tester.element(find.text('今日生存结余'));
    expect(Theme.of(context).brightness, Brightness.light);
    expect(Theme.of(context).scaffoldBackgroundColor, const Color(0xFFF7F2E9));
  });
}
