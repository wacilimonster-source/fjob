// Generates the Android large-widget office bitmaps with the shared painter:
// scene (working / break / empty) × housing/car visibility (00/01/10/11).
// Run manually, not as part of the regular test suite:
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
import 'package:fjob_ui/fjob_ui.dart';

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

const _scenes = <String, DayPhase>{
  'working': DayPhase.working,
  'break': DayPhase.breakTime,
  'empty': DayPhase.afterShift,
};

const _visibility = <String, (bool, bool)>{
  '00': (false, false),
  '01': (true, false),
  '10': (false, true),
  '11': (true, true),
};

void main() {
  testWidgets('render office scenes to png', (tester) async {
    await tester.runAsync(_loadFont);
    tester.view.physicalSize = const Size(1520, 952);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    final outputDir = Directory(
      'android/app/src/main/res/drawable-nodpi',
    )..createSync(recursive: true);

    for (final sceneEntry in _scenes.entries) {
      for (final visibilityEntry in _visibility.entries) {
        final (showHousing, showCar) = visibilityEntry.value;
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
                    child: OfficeScene(
                      phase: sceneEntry.value,
                      completeness: Completeness.complete,
                      total: Rational(BigInt.from(-5526), BigInt.from(100)),
                      reduceMotion: true,
                      showHousing: showHousing,
                      showCar: showCar,
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
        final name =
            'office_${sceneEntry.key}_${visibilityEntry.key}.png';
        final output = File('${outputDir.path}/$name');
        output.writeAsBytesSync(bytes!);
        // ignore: avoid_print
        print('wrote ${output.path} (${bytes.length} bytes)');
      }
    }
  });
}
