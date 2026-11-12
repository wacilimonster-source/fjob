import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todayagain_desktop/widgets/lan_input_dialog.dart';

void main() {
  testWidgets('LAN dialog validates address and pairing code', (tester) async {
    LanInput? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await showDialog<LanInput>(
                  context: context,
                  builder: (_) => const LanInputDialog(
                    title: '从手机接收账本',
                    actionLabel: '连接并接收',
                    hint: '提示',
                  ),
                );
              },
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(find.text('从手机接收账本'), findsOneWidget);

    await tester.tap(find.text('连接并接收'));
    await tester.pumpAndSettle();
    expect(find.text('请填写手机屏幕上显示的地址。'), findsOneWidget);
    expect(find.text('配对码应为 12 位（可带 - 分隔）'), findsOneWidget);
    expect(result, isNull);

    await tester.enterText(
      find.byType(TextFormField).first,
      '192.168.1.5:54321',
    );
    await tester.enterText(find.byType(TextFormField).last, 'abcd-efgh-jkmn');
    await tester.tap(find.text('连接并接收'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.address.authority, '192.168.1.5:54321');
    expect(result!.code, 'ABCDEFGHJKMN');
  });
}
