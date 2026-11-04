// Captures UI screenshots for the delivery report.
//
//   flutter test tool/capture_screens_test.dart
//
// The dashboard, assets, expenses and widget pages run on the isolated demo
// ledger with the fixed 2026-11-04 14:36 Shanghai clock. The onboarding shot
// uses an in-memory draft controller, so no database is touched.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:finance_core/finance_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todayagain/app/app.dart';
import 'package:todayagain/app/clock.dart';
import 'package:todayagain/app/providers.dart';
import 'package:todayagain/app/theme.dart';
import 'package:todayagain/domain/setup_draft.dart';
import 'package:todayagain/features/onboarding/onboarding_controller.dart';
import 'package:todayagain/features/onboarding/onboarding_page.dart';

Future<void> _loadFont() async {
  final file = File(r'C:\Windows\Fonts\Deng.ttf');
  final fallback = File(r'C:\Windows\Fonts\simhei.ttf');
  if (!file.existsSync() && !fallback.existsSync()) return;
  final bytes = (file.existsSync() ? file : fallback).readAsBytesSync();
  // Material styles request Roboto, MoneyText requests Consolas/monospace and
  // the painters request Microsoft YaHei. Register the same system font under
  // each family so the test renderer matches a device instead of drawing Ahem
  // blocks.
  final iconFont = File(
    'G:/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
  );
  if (iconFont.existsSync()) {
    final iconBytes = iconFont.readAsBytesSync();
    final iconLoader = FontLoader('MaterialIcons')
      ..addFont(Future<ByteData>.value(ByteData.sublistView(iconBytes)));
    await iconLoader.load();
  }
  for (final family in const [
    'Microsoft YaHei',
    'Roboto',
    'Consolas',
    'monospace',
    'sans-serif',
  ]) {
    final loader = FontLoader(family)
      ..addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
    await loader.load();
  }
}

final DateTime _now = DateTime.utc(2026, 11, 4, 6, 36);

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final bytes = await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  });
  final directory = Directory('build/screenshots')..createSync(recursive: true);
  File('${directory.path}/$name.png').writeAsBytesSync(bytes!);
}

class _DemoOnboardingController extends OnboardingController {
  @override
  Future<SetupDraft> build() async {
    return SetupDraft.fresh('demo-session', today: LocalDate(2026, 11, 4))
      ..salaryText = '12000'
      ..housingMode = HousingMode.mortgage
      ..mortgageMonthlyText = '4800'
      ..mortgagePrincipalText = '2800';
  }
}

void main() {
  testWidgets('capture app screens', (tester) async {
    await tester.runAsync(_loadFont);
    tester.view.physicalSize = const Size(780, 1688);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: ProviderScope(
          overrides: [
            sampleModeProvider.overrideWith((ref) => true),
            clockProvider.overrideWithValue(FixedClock(_now)),
            deepLinksEnabledProvider.overrideWithValue(false),
          ],
          child: const FjobApp(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    await _capture(tester, key, '01-dashboard-demo');

    await tester.tap(find.text('资产风浪'));
    await tester.pump(const Duration(milliseconds: 300));
    await _capture(tester, key, '02-assets-demo');

    await tester.tap(find.text('固定牵挂'));
    await tester.pump(const Duration(milliseconds: 300));
    await _capture(tester, key, '03-expenses-demo');

    await tester.tap(find.text('桌面分身'));
    await tester.pump(const Duration(milliseconds: 300));
    await _capture(tester, key, '04-widgets-demo');

    // Onboarding welcome, rendered with an in-memory draft.
    final onboardingKey = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: onboardingKey,
        child: ProviderScope(
          overrides: [
            onboardingControllerProvider.overrideWith(
              _DemoOnboardingController.new,
            ),
            clockProvider.overrideWithValue(FixedClock(_now)),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: FjobTheme.light(),
            home: const OnboardingPage(),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
    await _capture(tester, onboardingKey, '05-onboarding-welcome');
  });
}
