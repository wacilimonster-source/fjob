import 'dart:async';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fjob_ui/fjob_ui.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';
import 'package:windows_single_instance/windows_single_instance.dart';

import 'card_window.dart';
import 'desktop_controller.dart';
import 'desktop_preferences.dart';
import 'main_window.dart';
import 'state/database.dart';
import 'state/providers.dart';

final StreamController<void> _secondInstance =
    StreamController<void>.broadcast();

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  WindowController controller;
  try {
    controller = await WindowController.fromCurrentEngine();
  } catch (_) {
    controller = WindowController.fromWindowId('main');
  }

  final isCard = controller.arguments.contains('"role":"card"');
  if (isCard) {
    await runCardWindow(controller);
  } else {
    await runMainWindow(args, controller);
  }
}

Future<void> runMainWindow(
  List<String> args,
  WindowController controller,
) async {
  initDesktopDatabase();

  await WindowsSingleInstance.ensureSingleInstance(
    args,
    'fjob_todayagain_desktop',
    bringWindowToFront: false,
    onSecondWindow: (_) => _secondInstance.add(null),
  );

  await windowManager.ensureInitialized();
  await windowManager.setPreventClose(true);

  const options = WindowOptions(
    size: Size(1000, 680),
    minimumSize: Size(820, 560),
    center: true,
    title: '今日又白干 · 工位后台',
    titleBarStyle: TitleBarStyle.hidden,
    backgroundColor: Color(0xFFF7F2E9),
  );

  await windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  final desktop = DesktopController(mainWindow: controller);
  final preferences = DesktopPreferencesStore(
    DesktopPreferencesStore.defaultDirectory(),
  );

  runApp(
    ProviderScope(
      overrides: [
        desktopControllerProvider.overrideWithValue(desktop),
        // Single store instance: the card reports positions through the
        // controller's store, and the desktop page saves through the
        // provider's. Two instances would clobber each other's in-memory
        // snapshot and silently revert each other's keys.
        preferencesStoreProvider.overrideWithValue(preferences),
      ],
      child: FjobDesktopApp(desktop: desktop, preferences: preferences),
    ),
  );
}

class FjobDesktopApp extends ConsumerStatefulWidget {
  const FjobDesktopApp({
    super.key,
    required this.desktop,
    required this.preferences,
  });
  final DesktopController desktop;
  final DesktopPreferencesStore preferences;

  @override
  ConsumerState<FjobDesktopApp> createState() => _FjobDesktopAppState();
}

class _FjobDesktopAppState extends ConsumerState<FjobDesktopApp>
    with WindowListener {
  late final TrayService _tray;
  late final HotkeyService _hotkeys;
  StreamSubscription<void>? _secondInstanceSubscription;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _tray = TrayService(widget.desktop);
    _hotkeys = HotkeyService(widget.desktop);
    _secondInstanceSubscription = _secondInstance.stream.listen(
      (_) => widget.desktop.showMain(),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_bootstrap());
    });
  }

  Future<void> _bootstrap() async {
    await widget.desktop.initializePreferences(widget.preferences);
    DesktopPreferences prefs;
    try {
      prefs = await widget.preferences.load();
    } on Object {
      prefs = DesktopPreferences.defaults();
    }
    // The desktop page must show the PERSISTED state, not defaults: the card
    // already runs on the loaded config, and a stale provider would make the
    // density/metrics selectors lie (tapping the "selected" segment is a no-op
    // and nothing is saved).
    ref.read(preferencesProvider.notifier).state = prefs;
    await _tray.init();
    await _hotkeys.init(prefs);
    if (prefs.showAtStartup) {
      await widget.desktop.showCard();
    }
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _secondInstanceSubscription?.cancel();
    _tray.dispose();
    _hotkeys.dispose();
    widget.desktop.dispose();
    super.dispose();
  }

  @override
  void onWindowClose() {
    unawaited(widget.desktop.hideMain());
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '今日又白干 · 工位后台',
      theme: FjobTheme.light(),
      home: const MainWindow(),
    );
  }
}

class TrayService with TrayListener {
  TrayService(this.desktop);
  final DesktopController desktop;
  bool _initialized = false;

  Future<void> init() async {
    try {
      trayManager.addListener(this);
      await trayManager.setIcon('assets/tray_icon.png', iconSize: 20);
      await trayManager.setToolTip('今日又白干 · 工位便签');
      await _refreshMenu();
      _initialized = true;
    } catch (_) {
      // Tray availability varies; the main window remains usable.
    }
  }

  Future<void> _refreshMenu() async {
    final menu = Menu(
      items: [
        MenuItem(key: 'show_main', label: '显示主窗'),
        MenuItem(
          key: 'toggle_card',
          label: desktop.cardVisible ? '隐藏固定窗' : '显示固定窗',
        ),
        MenuItem.checkbox(
          key: 'topmost',
          label: '置顶',
          checked: desktop.topmost,
        ),
        MenuItem.checkbox(
          key: 'privacy',
          label: '金额隐身',
          checked: desktop.privacy,
        ),
        MenuItem.checkbox(
          key: 'through',
          label: '点击穿透',
          checked: desktop.clickThrough,
        ),
        MenuItem.separator(),
        MenuItem(key: 'quit', label: '退出'),
      ],
    );
    await trayManager.setContextMenu(menu);
  }

  @override
  void onTrayIconMouseDown() {
    unawaited(desktop.showMain());
  }

  @override
  void onTrayIconRightMouseDown() {
    unawaited(trayManager.popUpContextMenu());
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show_main':
        unawaited(desktop.showMain());
      case 'toggle_card':
        unawaited(desktop.toggleCard().then((_) => _refreshMenu()));
      case 'topmost':
        unawaited(desktop.toggleTopmost().then((_) => _refreshMenu()));
      case 'privacy':
        unawaited(desktop.togglePrivacy().then((_) => _refreshMenu()));
      case 'through':
        unawaited(desktop.toggleClickThrough().then((_) => _refreshMenu()));
      case 'quit':
        unawaited(trayManager.destroy().whenComplete(() => desktop.quit()));
    }
  }

  void dispose() {
    if (_initialized) {
      trayManager.removeListener(this);
      unawaited(trayManager.destroy());
    }
  }
}

class HotkeyService {
  HotkeyService(this.desktop);
  final DesktopController desktop;
  final List<HotKey> _registered = [];
  final List<String> conflicts = [];

  Future<void> init(DesktopPreferences prefs) async {
    await _register('fjob.boss', prefs.bossKey, () => desktop.toggleBoss());
    await _register(
      'fjob.privacy',
      prefs.privacyKey,
      () => desktop.togglePrivacy(),
    );
    await _register(
      'fjob.through',
      prefs.clickThroughKey,
      () => desktop.toggleClickThrough(),
    );
  }

  PhysicalKeyboardKey? _keyFor(String letter) {
    final code = letter.toUpperCase().codeUnitAt(0);
    if (code < 65 || code > 90) return null;
    return PhysicalKeyboardKey(0x00070004 + (code - 65));
  }

  Future<void> _register(
    String identifier,
    String letter,
    Future<void> Function() action,
  ) async {
    final key = _keyFor(letter);
    if (key == null) return;
    final hotKey = HotKey(
      identifier: identifier,
      key: key,
      modifiers: [HotKeyModifier.control, HotKeyModifier.alt],
      scope: HotKeyScope.system,
    );
    try {
      await hotKeyManager.register(
        hotKey,
        keyDownHandler: (_) => unawaited(action()),
      );
      _registered.add(hotKey);
    } catch (_) {
      conflicts.add(letter);
    }
  }

  void dispose() {
    for (final hotKey in _registered) {
      unawaited(hotKeyManager.unregister(hotKey));
    }
    _registered.clear();
  }
}
