import 'package:finance_core/finance_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todayagain/app/providers.dart';
import 'package:todayagain/app/theme.dart';
import 'package:todayagain/data/market_client.dart';
import 'package:todayagain/domain/setup_draft.dart';
import 'package:todayagain/features/assets/holding_editor.dart';

void main() {
  Future<HoldingDraft? Function()> pumpEditor(WidgetTester tester) async {
    HoldingDraft? result;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          marketClientProvider.overrideWithValue(
            FixtureMarketClient(BusinessCalendar.shanghai),
          ),
        ],
        child: MaterialApp(
          theme: FjobTheme.light(),
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () async {
                    result = await showHoldingEditor(context);
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return () => result;
  }

  testWidgets('code lookup fills market and name, and name stays editable',
      (tester) async {
    final result = await pumpEditor(tester);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('holding-code')),
      '000001',
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.text('已识别：深市 · 平安银行'), findsOneWidget);
    final nameField = tester.widget<TextField>(
      find.byKey(const ValueKey('holding-name')),
    );
    expect(nameField.controller!.text, '平安银行');

    // The name field must accept manual edits even after auto-fill.
    await tester.enterText(
      find.byKey(const ValueKey('holding-name')),
      '我的银行',
    );
    await tester.pump();
    expect(find.text('我的银行'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('holding-quantity')),
      '100',
    );
    await tester.enterText(
      find.byKey(const ValueKey('holding-cost')),
      '12.5',
    );
    await tester.tap(find.text('保存持仓'));
    await tester.pumpAndSettle();

    final draft = result();
    expect(draft, isNotNull);
    expect(draft!.name, '我的银行');
    expect(draft.instrumentId, 'CN.SZ.000001');
    expect(draft.quantityText, '100');
    expect(draft.costText, '12.5');
  });

  testWidgets('an unknown but valid code still infers the market',
      (tester) async {
    await pumpEditor(tester);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('holding-code')),
      '601999',
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.text('沪市'), findsOneWidget);
    expect(
      find.textContaining('名称待联网确认'),
      findsOneWidget,
    );
  });

  testWidgets('an invalid code blocks saving with a readable error',
      (tester) async {
    await pumpEditor(tester);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('holding-code')),
      '12345',
    );
    await tester.tap(find.text('保存持仓'));
    await tester.pump();
    expect(find.textContaining('6 位数字'), findsOneWidget);
  });
}
