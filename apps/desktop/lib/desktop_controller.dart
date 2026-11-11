import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'desktop_preferences.dart';
import 'native_desktop.dart';

final desktopControllerProvider = Provider<DesktopController>(
  (ref) => throw UnimplementedError('override in main'),
);

/// Owns the main window and the ambient card window for PC0.
///
/// The card is a second Flutter engine created by desktop_multi_window. The
/// main engine controls it through a method channel; this is the fallback
/// architecture after Flutter's experimental windowing produced a blank
/// content view on the 3.47.9 stable engine.
class DesktopController extends ChangeNotifier {
  DesktopController({required this.mainWindow});

  final WindowController mainWindow;

  WindowController? _cardWindow;

  bool topmost = true;
  bool clickThrough = false;
  bool privacy = false;
  bool cardVisible = false;
  bool mainVisible = true;
  bool bossHidden = false;
  String density = 'm';
  String metricsMode = 'both';
  bool reduceMotion = false;
  double opacity = 1.0;
  bool locked = false;
  bool fullscreenAutoHide = true;
  Map<String, Object?>? position;

  bool _wasMainVisible = true;
  bool _wasCardVisible = false;
  bool _cardReady = false;
  bool _fullscreenHidden = false;
  bool _creatingCard = false;
  int _sequence = 0;
  Timer? _fullscreenTimer;
  DesktopPreferencesStore? _preferences;
  final NativeDesktop _native = const NativeDesktop();

  String lastAction = '等待主窗就绪';

  WindowController? get cardWindow => _cardWindow;

  bool get cardReady => _cardReady;

  Future<void> initializePreferences(DesktopPreferencesStore store) async {
    _preferences = store;
    try {
      final prefs = await store.load();
      await applyPreferences(prefs);
    } on Object {
      _log('显示设置读取失败，使用默认值');
    }
    mainWindow.setWindowMethodHandler(_handleCardCall);
    _fullscreenTimer =
        Timer.periodic(const Duration(seconds: 2), (_) => _checkFullscreen());
  }

  Future<void> applyPreferences(DesktopPreferences prefs) async {
    topmost = prefs.topmost;
    clickThrough = prefs.clickThrough;
    privacy = prefs.privacy;
    density = prefs.density;
    metricsMode = prefs.metrics;
    reduceMotion = prefs.reduceMotion;
    opacity = prefs.opacity;
    locked = prefs.locked;
    fullscreenAutoHide = prefs.fullscreenAutoHide;
    position = prefs.position;
    await _send('setTopmost', topmost);
    await _send('setClickThrough', clickThrough);
    await publishConfig();
    notifyListeners();
  }

  Future<void> publishConfig() async {
    await _send('setDisplay', {
      'sequence': ++_sequence,
      'privacy': privacy,
      'density': density,
      'metricsMode': metricsMode,
      'reduceMotion': reduceMotion,
      'opacity': opacity,
      'locked': locked,
      'position': position,
    });
  }

  Future<dynamic> _handleCardCall(MethodCall call) async {
    switch (call.method) {
      case 'openMain':
        await showMain();
      case 'hideCard':
        await hideCard();
      case 'savePosition':
        final args = call.arguments;
        if (args is Map) {
          await _updatePreference('position', Map<String, Object?>.from(args));
        }
      case 'togglePrivacy':
        await _updatePreference('privacy', !privacy);
      case 'toggleClickThrough':
        await _updatePreference('clickThrough', !clickThrough);
      case 'toggleTopmost':
        await _updatePreference('topmost', !topmost);
    }
    return true;
  }

  Future<void> _updatePreference(String key, Object? value) async {
    final store = _preferences;
    if (store == null) return;
    try {
      final prefs = await store.update(key, value);
      await applyPreferences(prefs);
    } on Object {
      _log('显示设置没存上，请重试');
    }
  }

  void _checkFullscreen() {
    if (!fullscreenAutoHide || _cardWindow == null || bossHidden) return;
    final fullscreen = _native.isForegroundFullscreen();
    if (fullscreen && cardVisible && !_fullscreenHidden) {
      _fullscreenHidden = true;
      unawaited(_cardWindow?.hide());
    } else if (!fullscreen && _fullscreenHidden) {
      _fullscreenHidden = false;
      if (_wasCardVisible || cardVisible) {
        unawaited(_cardWindow?.show());
      }
    }
  }

  Future<void> toggleCard() async {
    if (cardVisible) {
      await hideCard();
    } else {
      await showCard();
    }
  }

  Future<void> ensureCard() async {
    if (_cardWindow != null || _creatingCard) return;
    _creatingCard = true;
    try {
      final controller = await WindowController.create(
        WindowConfiguration(
          arguments: jsonEncode({
            'role': 'card',
            'mainWindowId': mainWindow.windowId,
          }),
          hiddenAtLaunch: true,
        ),
      );
      _cardWindow = controller;
      final ready = await _waitForCard(controller);
      if (!ready) {
        _log('固定窗 engine 未在超时前就绪');
        return;
      }
      _cardReady = true;
      await _send('setTopmost', topmost);
      await _send('setClickThrough', clickThrough);
      await publishConfig();
      _log('固定窗已就绪（独立 engine）');
      notifyListeners();
    } catch (_) {
      _log('固定窗创建失败，请重试');
    } finally {
      _creatingCard = false;
    }
  }

  Future<bool> _waitForCard(WindowController controller) async {
    for (var attempt = 0; attempt < 30; attempt++) {
      try {
        final result = await controller.invokeMethod<bool>('ping');
        if (result == true) return true;
      } catch (_) {
        // The card engine may still be starting.
      }
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
    return false;
  }

  Future<void> _send(String method, [dynamic arguments]) async {
    final controller = _cardWindow;
    if (controller == null) return;
    try {
      await controller.invokeMethod<void>(method, arguments);
    } catch (_) {
      _log('固定窗暂不可用，请重试');
    }
  }

  Future<void> showCard() async {
    await ensureCard();
    final controller = _cardWindow;
    if (controller == null) return;
    try {
      await controller.show();
      cardVisible = true;
      _wasCardVisible = true;
      _log('固定窗已显示');
      notifyListeners();
    } catch (_) {
      _log('显示固定窗失败，请重试');
    }
  }

  Future<void> hideCard() async {
    final controller = _cardWindow;
    if (controller == null) return;
    try {
      await controller.hide();
      cardVisible = false;
      _wasCardVisible = false;
      _log('固定窗已隐藏');
      notifyListeners();
    } catch (_) {
      _log('隐藏固定窗失败，请重试');
    }
  }

  Future<void> resetCardPosition() async {
    await _send('resetPosition');
  }

  Future<void> showMain() async {
    await windowManager.show();
    await windowManager.focus();
    mainVisible = true;
    bossHidden = false;
    _log('主窗已显示');
    notifyListeners();
  }

  Future<void> hideMain() async {
    await windowManager.hide();
    mainVisible = false;
    _log('主窗已隐藏到托盘');
    notifyListeners();
  }

  Future<void> toggleTopmost() => _updatePreference('topmost', !topmost);
  Future<void> setTopmost(bool value) => _updatePreference('topmost', value);
  Future<void> toggleClickThrough() =>
      _updatePreference('clickThrough', !clickThrough);
  Future<void> setClickThrough(bool value) =>
      _updatePreference('clickThrough', value);
  Future<void> togglePrivacy() => _updatePreference('privacy', !privacy);

  Future<void> toggleBoss() async {
    if (!bossHidden) {
      _wasMainVisible = mainVisible;
      _wasCardVisible = cardVisible;
      bossHidden = true;
      await windowManager.hide();
      await _cardWindow?.hide();
      mainVisible = false;
      cardVisible = false;
      _log('老板键：主窗和固定窗已隐身');
    } else {
      bossHidden = false;
      if (_wasMainVisible) {
        await showMain();
      }
      if (_wasCardVisible) {
        await _cardWindow?.show();
        cardVisible = true;
      }
      _log('老板键：已恢复');
    }
    notifyListeners();
  }

  void quit() {
    _fullscreenTimer?.cancel();
    unawaited(_send('close'));
    exit(0);
  }

  void _log(String message) {
    lastAction = message;
    notifyListeners();
  }

  @override
  void dispose() {
    _fullscreenTimer?.cancel();
    unawaited(_send('close'));
    super.dispose();
  }
}
