// Captures the docs/09 §11.1 key frames for the delivery report.
//
//   flutter test tool/capture_scene_frames_test.dart
//
// All frames use the isolated demo ledger, the 380×238 scene at phone size and
// a movable FixedClock, so every timestamp in the file name is exact.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todayagain/app/clock.dart';
import 'package:todayagain/app/providers.dart';
import 'package:fjob_ui/fjob_ui.dart';
import 'package:todayagain/features/dashboard/dashboard_page.dart';

Future<void> _loadFont() async {
  final candidates = [
    r'C:\Windows\Fonts\Deng.ttf',
    r'C:\Windows\Fonts\simhei.ttf',
    r'C:\Windows\Fonts\msyh.ttc',
  ];
  for (final path in candidates) {
    final file = File(path);
    if (!file.existsSync()) continue;
    final bytes = file.readAsBytesSync();
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
    final iconFont = File(
      'G:/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
    );
    if (iconFont.existsSync()) {
      final iconBytes = iconFont.readAsBytesSync();
      final iconLoader = FontLoader('MaterialIcons')
        ..addFont(Future<ByteData>.value(ByteData.sublistView(iconBytes)));
      await iconLoader.load();
    }
    return;
  }
}

DateTime _shanghai(int day, int hour, int minute, [int second = 0, int ms = 0]) =>
    DateTime.utc(2026, 11, day, hour - 8, minute, second, ms);

final _workingNow = _shanghai(4, 14, 36);
const _tick = Duration(milliseconds: 300);
const _settle = Duration(milliseconds: 20);

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final bytes = await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  });
  final directory = Directory('build/scene-frames')..createSync(recursive: true);
  File('${directory.path}/$name.png').writeAsBytesSync(bytes!);
  // ignore: avoid_print
  print('captured $name');
}

Future<FixedClock> _pump(
  WidgetTester tester, {
  required DateTime now,
  double textScale = 1.0,
  bool disableAnimations = false,
  Size logicalSize = const Size(380, 640),
}) async {
  tester.view.devicePixelRatio = 2;
  tester.view.physicalSize = Size(logicalSize.width * 2, logicalSize.height * 2);
  tester.view.platformDispatcher.textScaleFactorTestValue = textScale;
  tester.view.platformDispatcher.accessibilityFeaturesTestValue =
      FakeAccessibilityFeatures(disableAnimations: disableAnimations);
  addTearDown(() {
    tester.view.platformDispatcher.clearTextScaleFactorTestValue();
    tester.view.platformDispatcher.clearAccessibilityFeaturesTestValue();
    tester.view.reset();
  });
  final clock = FixedClock(now);
  await tester.pumpWidget(
    KeyedSubtree(
      key: UniqueKey(),
      child: ProviderScope(
        overrides: [
          sampleModeProvider.overrideWith((ref) => true),
          clockProvider.overrideWithValue(clock),
          deepLinksEnabledProvider.overrideWithValue(false),
          widgetTimelineEnabledProvider.overrideWithValue(false),
        ],
        child: RepaintBoundary(
          key: _pageKey,
          child: MaterialApp(
            theme: FjobTheme.light(),
            home: Scaffold(
              body: SafeArea(child: DashboardPage()),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 60));
  await tester.pump(const Duration(milliseconds: 60));
  await tester.pump(_settle);
  return clock;
}

Future<void> _patFrame(WidgetTester tester, int ms, String name) async {
  await tester.tap(find.widgetWithText(TextButton, '拍拍他'));
  await tester.pump(); // 锚定起始帧
  await tester.pump(Duration(milliseconds: ms));
  await tester.pump(_settle);
  await _capture(tester, _pageKey!, name);
  // 收尾本次拍肩，避免影响下一帧。
  await tester.pump(Duration(milliseconds: 3200 - ms));
  await tester.pump(const Duration(milliseconds: 16));
  await tester.pump(_settle);
}

GlobalKey? _pageKey;

void main() {
  testWidgets('capture scene key frames', (tester) async {
    await tester.runAsync(_loadFont);
    _pageKey = GlobalKey();

    // ---- PAT：working/亏损，完整 3.2 秒关键帧 ----
    await _pump(tester, now: _workingNow);
    await _capture(tester, _pageKey!, 'pat-0000');
    for (final ms in const [120, 210, 410, 720, 1200, 2600]) {
      await _patFrame(tester, ms, 'pat-${ms.toString().padLeft(4, '0')}');
    }
    await _patFrame(tester, 3200, 'pat-3200');

    // ---- OUT：17:59:59.800 起跨过 18:00 的 2.2 秒关键帧 ----
    final clock = await _pump(tester, now: _shanghai(4, 17, 59, 59, 800));
    clock.advance(const Duration(milliseconds: 400));
    await tester.pump(_tick);
    await tester.pump(_settle);
    await tester.pump(); // 锚定离场起始帧
    await _capture(tester, _pageKey!, 'departure-0000');
    // pump 时长为相邻关键帧的增量，保证毫秒标注精确。
    const deltas = <int, int>{560: 560, 860: 300, 1400: 540, 1900: 500};
    for (final entry in deltas.entries) {
      await tester.pump(Duration(milliseconds: entry.value));
      await tester.pump(_settle);
      await _capture(
        tester,
        _pageKey!,
        'departure-${entry.key.toString().padLeft(4, '0')}',
      );
    }
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 16)); // 完成状态落帧
    await tester.pump(_settle);
    await _capture(tester, _pageKey!, 'departure-2200');

    // ---- 附加帧：盈利初始、午休回应、冷启动、休息日、低动效、大字体 ----
    await _pump(tester, now: _shanghai(4, 17, 58, 0));
    await _capture(tester, _pageKey!, 'extra-gain-working');

    await _pump(tester, now: _shanghai(4, 12, 30, 0));
    await tester.tap(find.widgetWithText(TextButton, '拍拍他'));
    await tester.pump(); // 锚定起始帧
    await tester.pump(const Duration(milliseconds: 1000));
    await tester.pump(_settle);
    await _capture(tester, _pageKey!, 'extra-break-response');
    await tester.pump(const Duration(milliseconds: 2200));
    await tester.pump(const Duration(milliseconds: 16));

    await _pump(tester, now: _shanghai(4, 18, 30, 0));
    await _capture(tester, _pageKey!, 'extra-aftershift-empty');

    await _pump(tester, now: _shanghai(7, 12, 0, 0));
    await _capture(tester, _pageKey!, 'extra-restday-empty');

    await _pump(tester, now: _workingNow, disableAnimations: true);
    await tester.tap(find.widgetWithText(TextButton, '拍拍他'));
    await tester.pump(); // 锚定起始帧
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(_settle);
    await _capture(tester, _pageKey!, 'extra-reduced-motion');
    await tester.pump(const Duration(milliseconds: 2400));
    await tester.pump(const Duration(milliseconds: 16));

    await _pump(
      tester,
      now: _workingNow,
      textScale: 2.0,
      logicalSize: const Size(320, 1200),
    );
    await tester.tap(find.widgetWithText(TextButton, '拍拍他'));
    await tester.pump(); // 锚定起始帧
    await tester.pump(const Duration(milliseconds: 1000));
    await tester.pump(_settle);
    await _capture(tester, _pageKey!, 'extra-320dp-200pct');
    await tester.pump(const Duration(milliseconds: 2200));
    await tester.pump(const Duration(milliseconds: 16));

    expect(_pageKey!.currentContext, isNotNull);
  });
}
