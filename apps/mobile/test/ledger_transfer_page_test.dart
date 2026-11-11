import 'package:finance_core/finance_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fjob_ui/fjob_ui.dart';
import 'package:ledger_model/ledger_model.dart';
import 'package:ledger_store/ledger_store.dart';
import 'package:todayagain/app/providers.dart';
import 'package:todayagain/features/settings/ledger_transfer_page.dart';

void main() {
  final now = DateTime.utc(2026, 11, 4, 6, 36);
  final demo = buildDemoLedger(BusinessCalendar.shanghai, now);
  final bundle = LedgerBundle.fromLedger(
    demo.copyWith(settings: demo.settings.copyWith(sampleMode: false)),
    ledgerId: '0b6f1a2c-3d4e-5f60-7a8b-9c0d1e2f3a4b',
    exportedAt: now,
    appVersion: '0.1.10',
    platform: 'android',
  );

  testWidgets('import preview can be cancelled without touching the ledger', (tester) async {
    LedgerImportMode? result;
    await tester.pumpWidget(MaterialApp(
      theme: FjobTheme.light(),
      home: Builder(builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () async {
            result = await showDialog<LedgerImportMode>(
              context: context,
              builder: (_) => LedgerImportDialog(
                bundle: bundle,
                fileName: 'example.fjob',
                currentRevision: 8,
              ),
            );
          },
          child: const Text('打开摘要'),
        ),
      )),
    ));
    await tester.tap(find.text('打开摘要'));
    await tester.pumpAndSettle();
    expect(find.text('example.fjob'), findsOneWidget);
    expect(find.textContaining('本月排班'), findsOneWidget);
    expect(find.textContaining('本机 #8'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(result, isNull);
    expect(find.text('核对导入账本'), findsNothing);
  });

  testWidgets('sample mode disables both file actions', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [sampleModeProvider.overrideWith((ref) => true)],
      child: MaterialApp(theme: FjobTheme.light(), home: const LedgerTransferPage()),
    ));
    await tester.pump();
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
    expect(tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed, isNull);
    expect(find.text('示例模式不允许导入或导出正式账本。'), findsOneWidget);
  });

  testWidgets('import preview remains scrollable with large text', (tester) async {
    tester.view.physicalSize = const Size(640, 1280);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: FjobTheme.light(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(2)),
        child: child!,
      ),
      home: Scaffold(body: LedgerImportDialog(
        bundle: bundle,
        fileName: 'example.fjob',
        currentRevision: 8,
      )),
    ));
    expect(find.byType(SingleChildScrollView), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
