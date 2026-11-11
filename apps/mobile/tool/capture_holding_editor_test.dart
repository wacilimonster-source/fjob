// Renders the holding editor after automatic code lookup for screenshots.
//
//   flutter test tool/capture_holding_editor_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:finance_core/finance_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todayagain/app/providers.dart';
import 'package:fjob_ui/fjob_ui.dart';
import 'package:market_data/market_data.dart';
import 'package:todayagain/features/assets/holding_editor.dart';

Future<void> _loadFonts() async {
  final files = <String, String>{
    'Microsoft YaHei': r'C:\Windows\Fonts\Deng.ttf',
    'Roboto': r'C:\Windows\Fonts\Deng.ttf',
    'Consolas': r'C:\Windows\Fonts\Deng.ttf',
    'monospace': r'C:\Windows\Fonts\Deng.ttf',
  };
  for (final entry in files.entries) {
    final file = File(entry.value);
    if (!file.existsSync()) continue;
    final bytes = file.readAsBytesSync();
    final loader = FontLoader(entry.key)
      ..addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
    await loader.load();
  }
  final icons = File(
    'G:/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
  );
  if (icons.existsSync()) {
    final bytes = icons.readAsBytesSync();
    final loader = FontLoader('MaterialIcons')
      ..addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
    await loader.load();
  }
}

void main() {
  testWidgets('capture holding editor', (tester) async {
    await tester.runAsync(_loadFonts);
    tester.view.physicalSize = const Size(780, 1688);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: ProviderScope(
          overrides: [
            marketClientProvider.overrideWithValue(
              FixtureMarketClient(BusinessCalendar.shanghai),
            ),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: FjobTheme.light(),
            home: Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: ElevatedButton(
                    onPressed: () => showHoldingEditor(context),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('holding-code')),
      '000001',
    );
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('holding-quantity')),
      '1000',
    );
    await tester.enterText(
      find.byKey(const ValueKey('holding-cost')),
      '13.000',
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final bytes = await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List();
    });
    final directory = Directory('build/screenshots')..createSync(recursive: true);
    File('${directory.path}/06-holding-editor.png').writeAsBytesSync(bytes!);
  });
}
