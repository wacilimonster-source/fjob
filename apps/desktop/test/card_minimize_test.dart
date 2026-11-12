// 回归：小窗最小化后必须能从托盘/桌面页恢复。WindowController.show() 只发
// SW_SHOW，不会还原最小化窗口；控制器因此改走固定窗 engine 的 window_manager
// show()（内部先 restore）。见 docs/23。
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todayagain_desktop/desktop_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const windowChannel = MethodChannel('mixin.one/desktop_multi_window');
  const engineChannel = MethodChannel('mixin.one/desktop_multi_window/channels');

  late List<MethodCall> windowCalls;
  late List<String> engineCalls;

  setUp(() {
    windowCalls = [];
    engineCalls = [];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(windowChannel, (call) async {
      windowCalls.add(call);
      if (call.method == 'createWindow') return 'card-1';
      return null;
    });
    messenger.setMockMethodCallHandler(engineChannel, (call) async {
      final args = call.arguments as Map;
      final method = args['method'] as String;
      engineCalls.add(method);
      if (method == 'ping') return true;
      return null;
    });
  });

  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(windowChannel, null);
    messenger.setMockMethodCallHandler(engineChannel, null);
  });

  test('card shows, minimizes through the engine, and restores again', () async {
    final controller = DesktopController(
      mainWindow: WindowController.fromWindowId('main'),
    );

    await controller.showCard();
    expect(engineCalls, contains('show'));
    expect(controller.cardVisible, isTrue);

    engineCalls.clear();
    await controller.minimizeCard();
    expect(engineCalls, contains('minimize'));
    expect(controller.cardVisible, isFalse,
        reason: '最小化后托盘菜单应切换为「显示固定窗」');

    engineCalls.clear();
    await controller.showCard();
    expect(engineCalls, contains('show'),
        reason: '恢复必须走 engine 的 window_manager.show()，先 restore 再 show');
    expect(controller.cardVisible, isTrue);

    // 原生通道的 window_show 不负责还原最小化状态；本次路径不应依赖它。
    final usedNativeShow =
        windowCalls.any((call) => call.method == 'window_show');
    expect(usedNativeShow, isFalse);
  });
}
