import 'package:fjob_ui/fjob_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('all ten palette tokens preserve the mobile/design values', () {
    const p = FjobPalette.light;
    expect([
      p.paper,
      p.panel,
      p.ink,
      p.muted,
      p.line,
      p.soft,
      p.yellow,
      p.rose,
      p.negative,
      p.positive,
    ], const [
      Color(0xFFF7F2E9),
      Color(0xFFFFFDF7),
      Color(0xFF323A32),
      Color(0xFF686E61),
      Color(0xFFD5D6C8),
      Color(0xFFE9EDDF),
      Color(0xFFF2DFAC),
      Color(0xFFF0D2C5),
      Color(0xFFAD4736),
      Color(0xFF46644E),
    ]);
    expect(p.copyWith().ink, p.ink);
    expect(p.lerp(p, 0.5).paper, p.paper);
  });

  test('theme and typography preserve mobile fonts, sizes and brightness', () {
    final theme = FjobTheme.light();
    expect(theme.brightness, Brightness.light);
    expect(theme.extension<FjobPalette>(), FjobPalette.light);
    expect(theme.textTheme.displayLarge!.fontSize, 42);
    expect(theme.textTheme.headlineMedium!.fontSize, 25);
    expect(theme.textTheme.bodyMedium!.fontSize, 14);
    expect(theme.textTheme.bodySmall!.fontSize, 12);
    expect(theme.textTheme.bodyMedium!.fontFamily, FjobTypography.bodyFamily);
    expect(FjobTypography.bodyFamily, 'Microsoft YaHei');
    expect(FjobTypography.moneyFamily, 'Consolas');
    expect(FjobTypography.moneyFeatures, const [FontFeature.tabularFigures()]);
  });

  testWidgets('public theme widgets, icons and code brand render',
      (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(MaterialApp(
        theme: FjobTheme.light(),
        home: Scaffold(
            body: PaperCard(
                child: Column(children: const [
          SectionLabel('今日生存结余'),
          MoneyText('0.00'),
          HandDrawnClockIcon(),
          HandDrawnBillIcon(),
          BrandMark(size: 16),
          BrandMark(size: 32),
          DebtArt(type: DebtArtType.house),
          DebtArt(type: DebtArtType.car),
        ]))),
      ));
      expect(tester.takeException(), isNull);
      expect(
          tester.getSize(find.byType(HandDrawnClockIcon)), const Size(17, 17));
      expect(
          tester.getSize(find.byType(HandDrawnBillIcon)), const Size(17, 17));
      expect(find.bySemanticsLabel('今日又白干'), findsNWidgets(2));
      final money = tester.widget<Text>(find.text('0.00'));
      expect(money.style!.fontFamily, FjobTypography.moneyFamily);
      expect(money.style!.fontFeatures, FjobTypography.moneyFeatures);
    } finally {
      semantics.dispose();
    }
  });
}
