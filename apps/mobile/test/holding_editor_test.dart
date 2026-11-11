import 'package:finance_core/finance_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todayagain/app/providers.dart';
import 'package:fjob_ui/fjob_ui.dart';
import 'package:market_data/market_data.dart';
import 'package:ledger_model/ledger_model.dart';
import 'package:todayagain/features/assets/holding_editor.dart';

void main() {
  Future<HoldingDraft? Function()> pumpEditor(
    WidgetTester tester, {
    HoldingKind kind = HoldingKind.stock,
  }) async {
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
                    result = await showHoldingEditor(context, kind: kind);
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

  Future<void> openFundEditor(WidgetTester tester) async {
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('添加基金持仓'), findsOneWidget);
  }

  testWidgets('fund lookup fills the name and keeps four-decimal shares',
      (tester) async {
    final result = await pumpEditor(tester, kind: HoldingKind.fund);
    await openFundEditor(tester);

    await tester.enterText(
      find.byKey(const ValueKey('holding-code')),
      '000001',
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.text('已识别：华夏成长混合'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('holding-name')))
          .controller!
          .text,
      '华夏成长混合',
    );

    await tester.enterText(
      find.byKey(const ValueKey('holding-quantity')),
      '1000.2500',
    );
    await tester.enterText(
      find.byKey(const ValueKey('holding-cost')),
      '1.2000',
    );
    await tester.tap(find.text('保存持仓'));
    await tester.pumpAndSettle();

    final draft = result();
    expect(draft, isNotNull);
    expect(draft!.kind, HoldingKind.fund);
    expect(draft.instrumentId, 'FUND.CN.000001');
    expect(draft.quantityText, '1000.2500');
    expect(draft.costText, '1.2000');
    expect(draft.pendingQuote, isFalse);
  });

  testWidgets('a late lookup never overwrites a name typed meanwhile',
      (tester) async {
    await pumpEditor(tester, kind: HoldingKind.fund);
    await openFundEditor(tester);

    await tester.enterText(
      find.byKey(const ValueKey('holding-code')),
      '000001',
    );
    // Type before the 350ms debounce fires; the lookup must leave it alone.
    await tester.enterText(
      find.byKey(const ValueKey('holding-name')),
      '我的基金',
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('holding-name')))
          .controller!
          .text,
      '我的基金',
    );
    expect(find.text('我的基金'), findsOneWidget);
  });

  testWidgets('changing the code invalidates the previous lookup',
      (tester) async {
    await pumpEditor(tester, kind: HoldingKind.fund);
    await openFundEditor(tester);

    await tester.enterText(
      find.byKey(const ValueKey('holding-code')),
      '000001',
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(
      find.byKey(const ValueKey('holding-code')),
      '000198',
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(find.textContaining('不支持按普通场外基金计算'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('holding-name')))
          .controller!
          .text,
      '天弘余额宝货币',
    );
  });

  testWidgets('a confirmed unsupported fund blocks saving', (tester) async {
    final result = await pumpEditor(tester, kind: HoldingKind.fund);
    await openFundEditor(tester);

    await tester.enterText(
      find.byKey(const ValueKey('holding-code')),
      '000198',
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('holding-quantity')),
      '100',
    );
    await tester.enterText(
      find.byKey(const ValueKey('holding-cost')),
      '1',
    );
    await tester.tap(find.text('保存持仓'));
    await tester.pump();

    expect(find.textContaining('该基金暂不支持'), findsOneWidget);
    expect(result(), isNull);
  });

  testWidgets('an offline fund still saves with a pending flag', (tester) async {
    final result = await pumpEditor(tester, kind: HoldingKind.fund);
    await openFundEditor(tester);

    await tester.enterText(
      find.byKey(const ValueKey('holding-code')),
      '999999',
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(find.textContaining('待联网确认'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('holding-quantity')),
      '10.5',
    );
    await tester.enterText(
      find.byKey(const ValueKey('holding-cost')),
      '1.25',
    );
    await tester.tap(find.text('保存持仓'));
    await tester.pumpAndSettle();

    final draft = result();
    expect(draft, isNotNull);
    expect(draft!.pendingQuote, isTrue);
    expect(draft.instrumentId, 'FUND.CN.999999');
  });

  testWidgets('fund shares reject more than four decimals', (tester) async {
    final result = await pumpEditor(tester, kind: HoldingKind.fund);
    await openFundEditor(tester);

    await tester.enterText(
      find.byKey(const ValueKey('holding-code')),
      '000001',
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('holding-quantity')),
      '1.23456',
    );
    await tester.enterText(
      find.byKey(const ValueKey('holding-cost')),
      '1.2',
    );
    await tester.tap(find.text('保存持仓'));
    await tester.pump();

    expect(
      find.text('份额需要是 0 到 10,000,000 之间的数字，最多四位小数。'),
      findsOneWidget,
    );
    expect(result(), isNull);
  });

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
