// Renders the shared office illustration to a PNG for the Android large
// widget. Run manually, not as part of the regular test suite:
//
//   flutter test tool/generate_office_art_test.dart
//
// It uses the system SimHei font so the Chinese labels survive in the bitmap.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:finance_core/finance_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todayagain/app/theme.dart';
import 'package:todayagain/features/dashboard/office_scene.dart';

Future<void> _loadFont() async {
  final candidates = [
    r'C:\Windows\Fonts\simhei.ttf',
    r'C:\Windows\Fonts\Deng.ttf',
    r'C:\Windows\Fonts\msyh.ttc',
  ];
  for (final path in candidates) {
    final file = File(path);
    if (!file.existsSync()) continue;
    final bytes = file.readAsBytesSync();
    final loader = FontLoader('Microsoft YaHei')
      ..addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
    await loader.load();
    return;
  }
}

void main() {
  testWidgets('render office scene to png', (tester) async {
    await tester.runAsync(_loadFont);
    tester.view.physicalSize = const Size(1520, 952);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        theme: FjobTheme.light(),
        home: Scaffold(
          body: Center(
            child: RepaintBoundary(
              key: key,
              child: SizedBox(
                width: 760,
                height: 476,
                child: const OfficeScene(
                  phase: DayPhase.working,
                  completeness: Completeness.complete,
                  total: null,
                  reduceMotion: true,
                  housingLabel: '房贷',
                  carLabel: '车贷',
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));

    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final bytes = await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List();
    });
    expect(bytes, isNotNull);
    final output = File('android/app/src/main/res/drawable-nodpi/office_static.png');
    output.parent.createSync(recursive: true);
    output.writeAsBytesSync(bytes!);
    // ignore: avoid_print
    print('wrote ${output.path} (${bytes.length} bytes)');
  });
}
