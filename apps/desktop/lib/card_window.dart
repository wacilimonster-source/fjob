import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:finance_core/finance_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fjob_ui/fjob_ui.dart';
import 'package:ledger_model/ledger_model.dart';
import 'package:ledger_store/ledger_store.dart';
import 'package:market_data/market_data.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:window_manager/window_manager.dart' as wm;

import 'native_desktop.dart';
import 'state/database.dart';
import 'widgets/fixed_card_view.dart';

/// Boots the card engine. Amounts come from the same local ledger and
/// finance_core as the main window; display configuration arrives from the main
/// engine over the method channel. The secondary engine registers
/// window_manager/screen_retriever in the Windows runner (see docs/17).
Future<void> runCardWindow(WindowController controller) async {
  initDesktopDatabase();
  await wm.windowManager.ensureInitialized();

  const options = wm.WindowOptions(
    size: Size(320, 220),
    center: false,
    alwaysOnTop: true,
    skipTaskbar: true,
    title: '今日又白干 · 工位便签',
    titleBarStyle: wm.TitleBarStyle.hidden,
    windowButtonVisibility: false,
    backgroundColor: Colors.transparent,
  );

  await wm.windowManager.waitUntilReadyToShow(options, () async {
    await wm.windowManager.setAsFrameless();
    await wm.windowManager.setResizable(false);
    await wm.windowManager.setAlwaysOnTop(true);
    await wm.windowManager.setSkipTaskbar(true);
    await _placeBottomRight(const Size(320, 220));
  });

  final args = controller.arguments;
  String? mainWindowId;
  try {
    final decoded = jsonDecode(args);
    if (decoded is Map) mainWindowId = decoded['mainWindowId'] as String?;
  } on Object {
    // Arguments may be empty in tests.
  }

  runApp(CardApp(controller: controller, mainWindowId: mainWindowId));
}

Future<void> _placeBottomRight(Size size) async {
  try {
    final display = await screenRetriever.getPrimaryDisplay();
    final originRaw = display.visiblePosition;
    final areaRaw = display.visibleSize ?? display.size;
    final scale = (display.scaleFactor ?? 1.0).toDouble();
    // screen_retriever's visibleSize has been physical on some builds and
    // logical on others; anchor on the native SPI work area (physical) and
    // reconcile before converting to the logical space window_manager wants.
    final nativeWorkArea = const NativeDesktop().primaryWorkArea();
    final area = resolveWorkAreaLogical(
      reported: (width: areaRaw.width, height: areaRaw.height),
      origin: (dx: originRaw?.dx ?? 0.0, dy: originRaw?.dy ?? 0.0),
      scale: scale,
      nativeWorkArea: nativeWorkArea,
    );
    final x = area.left + area.width - size.width - 28;
    final y = area.top + area.height - size.height - 22;
    await wm.windowManager.setPosition(Offset(x, y));
  } on Object {
    // Positioning failure must not block the card from showing.
  }
}

class CardApp extends StatefulWidget {
  const CardApp({super.key, required this.controller, this.mainWindowId});
  final WindowController controller;
  final String? mainWindowId;

  @override
  State<CardApp> createState() => _CardAppState();
}

class _CardAppState extends State<CardApp> with wm.WindowListener {
  AppDatabase? _database;
  LedgerRepository? _repository;
  LedgerState? _ledger;
  DashboardSnapshot? _snapshot;
  Timer? _timer;
  int _tick = 0;
  int _sequence = 0;

  bool _privacy = false;
  CardDensity _density = CardDensity.m;
  String _metricsMode = 'both';
  bool _reduceMotion = false;
  double _opacity = 1.0;
  bool _locked = false;
  bool _clickThrough = false;
  Map<String, Object?>? _position;
  bool _receivedConfig = false;

  final BusinessCalendar _calendar = BusinessCalendar.shanghai;

  @override
  void initState() {
    super.initState();
    wm.windowManager.addListener(this);
    unawaited(widget.controller.setWindowMethodHandler(_handleMethod));
    unawaited(_openLedger());
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _refresh());
  }

  /// 位置记忆：拖拽/贴角结束后上报主窗，按显示器指纹持久化。x/y 为相对
  /// 工作区原点的逻辑像素；指纹不匹配（换显示器/改缩放）时主窗仍保存，
  /// 卡窗恢复时回退贴角。
  @override
  void onWindowMoved() {
    if (!mounted) return;
    unawaited(_reportPosition());
  }

  Future<void> _reportPosition() async {
    try {
      final offset = await wm.windowManager.getPosition();
      final fingerprint =
          const NativeDesktop().primaryWorkAreaFingerprint();
      if (fingerprint == null) return;
      final area = await _workAreaLogical();
      _position = {
        'x': offset.dx - area.left,
        'y': offset.dy - area.top,
        'displayId': fingerprint,
      };
      _callMain('savePosition', Map<String, Object>.from(_position!));
    } on Object {
      // Position memory must never break the card.
    }
  }

  Future<({double left, double top, double width, double height})>
      _workAreaLogical() async {
    final display = await screenRetriever.getPrimaryDisplay();
    final originRaw = display.visiblePosition;
    final areaRaw = display.visibleSize ?? display.size;
    final scale = (display.scaleFactor ?? 1.0).toDouble();
    return resolveWorkAreaLogical(
      reported: (width: areaRaw.width, height: areaRaw.height),
      origin: (dx: originRaw?.dx ?? 0.0, dy: originRaw?.dy ?? 0.0),
      scale: scale,
      nativeWorkArea: const NativeDesktop().primaryWorkArea(),
    );
  }

  Future<void> _openLedger() async {
    try {
      final appData = Platform.environment['APPDATA'];
      if (appData == null) return;
      final path =
          '$appData${Platform.pathSeparator}FJOB${Platform.pathSeparator}fjob_ledger.db';
      final database = await AppDatabase.open(
        factory: databaseFactoryFfi,
        path: path,
        calendar: _calendar,
      );
      _database = database;
      _repository = LedgerRepository(database, _calendar);
      await _refresh();
    } on Object {
      // The main engine may still be creating the database; retry on next tick.
    }
  }

  Future<void> _refresh() async {
    final repository = _repository;
    if (repository == null) {
      if (_database == null) await _openLedger();
      return;
    }
    try {
      final now = DateTime.now().toUtc();
      // Re-read the ledger periodically to pick up main-window edits; recalculate
      // the snapshot every second from the clock (never accumulate per tick).
      if (_tick % 3 == 0 || _ledger == null) {
        _ledger = await repository.read(nowUtc: now);
      }
      _tick++;
      final ledger = _ledger;
      if (ledger == null || !ledger.isConfigured) {
        if (mounted) setState(() => _snapshot = null);
        return;
      }
      final calculator = DashboardCalculator(_calendar);
      final snapshot = calculator.calculate(ledger
          .copyWith(quotes: applyQuoteFreshness(ledger.quotes, now))
          .toCalculationInput(calendar: _calendar, nowUtc: now));
      if (mounted) setState(() => _snapshot = snapshot);
    } on Object {
      // Keep the last good snapshot on a transient read error.
    }
  }

  Future<dynamic> _handleMethod(MethodCall call) async {
    switch (call.method) {
      case 'ping':
        return true;
      case 'setDisplay':
        final args = call.arguments;
        if (args is Map) {
          final seq = args['sequence'];
          if (seq is int && seq < _sequence) return true;
          if (seq is int) _sequence = seq;
          final previousDensity = _density;
          Map<String, Object?>? incomingPosition;
          final rawPosition = args['position'];
          if (rawPosition is Map) {
            incomingPosition = Map<String, Object?>.from(rawPosition);
          }
          setState(() {
            _privacy = args['privacy'] as bool? ?? _privacy;
            _density = densityFromName(args['density'] as String? ?? 'm');
            _metricsMode = args['metricsMode'] as String? ?? _metricsMode;
            _reduceMotion = args['reduceMotion'] as bool? ?? _reduceMotion;
            _opacity = (args['opacity'] as num?)?.toDouble() ?? _opacity;
            _locked = args['locked'] as bool? ?? _locked;
            _position = incomingPosition ?? _position;
          });
          final firstConfig = !_receivedConfig;
          _receivedConfig = true;
          await _applySize(
            densityChanged: previousDensity != _density,
            firstConfig: firstConfig,
          );
        }
        return true;
      case 'setTopmost':
        await wm.windowManager.setAlwaysOnTop(call.arguments as bool? ?? true);
        return true;
      case 'setClickThrough':
        _clickThrough = call.arguments as bool? ?? false;
        await wm.windowManager.setIgnoreMouseEvents(_clickThrough);
        return true;
      case 'resetPosition':
        await _placeBottomRight(cardSize(_density));
        return true;
      case 'show':
        await wm.windowManager.show();
        return true;
      case 'hide':
        await wm.windowManager.hide();
        return true;
      case 'close':
        await wm.windowManager.close();
        return true;
    }
    return null;
  }

  Future<void> _applySize({
    bool densityChanged = false,
    bool firstConfig = false,
  }) async {
    final size = cardSize(_density);
    await wm.windowManager.setSize(size);
    Offset? applied;
    if (firstConfig) {
      // A SetWindowPos issued immediately after the first resize can be
      // swallowed while the frame settles; let it settle, then restore and
      // verify by reading the position back, retrying once.
      await Future<void>.delayed(const Duration(milliseconds: 150));
      for (var attempt = 0; attempt < 2 && applied == null; attempt++) {
        applied = await _restoreSavedPosition();
        if (applied == null) break;
        final actual = await wm.windowManager.getPosition();
        if ((actual - applied).distance <= 1.0) break;
        await wm.windowManager.setPosition(applied);
        final again = await wm.windowManager.getPosition();
        if ((again - applied).distance <= 1.0) break;
        applied = null;
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }
    } else if (!densityChanged) {
      applied = await _restoreSavedPosition();
    }
    if (applied == null) {
      await _placeBottomRight(size);
      // Programmatic SetWindowPos never fires onWindowMoved; persist the new
      // anchor so the next launch restores what the user actually saw.
      await _reportPosition();
    }
  }

  /// 恢复已保存的位置：仅当指纹与当前显示器工作区一致时生效（换显示器、
  /// 改缩放、拔屏都会回到贴角兜底）。返回应用后的绝对逻辑坐标，null 表示
  /// 没有可恢复的位置。
  Future<Offset?> _restoreSavedPosition() async {
    final saved = _position;
    if (saved == null) return null;
    final fingerprint = const NativeDesktop().primaryWorkAreaFingerprint();
    if (fingerprint == null || saved['displayId'] != fingerprint) {
      return null;
    }
    final x = saved['x'];
    final y = saved['y'];
    if (x is! num || y is! num) return null;
    try {
      final area = await _workAreaLogical();
      return Offset(area.left + x.toDouble(), area.top + y.toDouble());
    } on Object {
      return null;
    }
  }

  void _callMain(String method, [dynamic arguments]) {
    final id = widget.mainWindowId;
    if (id == null) return;
    unawaited(WindowController.fromWindowId(id).invokeMethod(method, arguments));
  }

  @override
  void dispose() {
    wm.windowManager.removeListener(this);
    _timer?.cancel();
    unawaited(_database?.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    final ledger = _ledger;
    final housingMode = ledger?.housingMode ?? HousingMode.none;
    final body = snapshot == null
        ? _placeholder()
        : FixedCardView(
            snapshot: snapshot,
            calendar: _calendar,
            tone: ledger?.settings.tone ?? AppTone.gentle,
            privacy: _privacy,
            density: _density,
            metricsMode: _metricsMode,
            reduceMotion: _reduceMotion,
            showHousing: housingMode != HousingMode.none,
            showCar: _carEnabled(ledger),
            housingLabel: housingMode == HousingMode.rent ? '房租' : '房贷',
          );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: FjobTheme.light(),
      home: Scaffold(
        backgroundColor: Colors.transparent,
        body: Builder(
          // showMenu resolves MaterialLocalizations from this context; the
          // State's own context sits ABOVE MaterialApp and would crash it.
          builder: (menuContext) => GestureDetector(
            behavior: HitTestBehavior.translucent,
            onPanStart: _locked || _clickThrough
                ? null
                : (_) => wm.windowManager.startDragging(),
            onDoubleTap: _clickThrough ? null : () => _callMain('openMain'),
            onSecondaryTapUp: _clickThrough
                ? null
                : (details) => _showMenu(details.globalPosition, menuContext),
            child: Opacity(
              opacity: _opacity,
              child: FittedBox(fit: BoxFit.contain, child: body),
            ),
          ),
        ),
      ),
    );
  }

  bool _carEnabled(LedgerState? ledger) {
    if (ledger == null) return false;
    final now = DateTime.now().toUtc();
    for (final version in ledger.carVersions) {
      if (version.covers(now)) return version.enabled;
    }
    return false;
  }

  Widget _placeholder() {
    final palette = FjobPalette.light;
    return SizedBox(
      width: cardSize(_density).width,
      height: cardSize(_density).height,
      child: Container(
        decoration: BoxDecoration(
          color: palette.panel,
          border: Border.all(color: palette.ink, width: 1.5),
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.center,
        child: Text('打开主窗配置账本',
            style: TextStyle(fontSize: 13, color: palette.muted)),
      ),
    );
  }

  Future<void> _showMenu(Offset position, BuildContext menuContext) async {
    final selected = await showMenu<String>(
      context: menuContext,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx + 1, position.dy + 1),
      items: [
        const PopupMenuItem(value: 'open', child: Text('打开主窗')),
        PopupMenuItem(value: 'privacy', child: Text(_privacy ? '显示金额' : '金额隐身')),
        PopupMenuItem(value: 'through', child: Text(_clickThrough ? '关闭穿透' : '点击穿透')),
        const PopupMenuItem(value: 'hide', child: Text('隐藏到托盘')),
      ],
    );
    switch (selected) {
      case 'open':
        _callMain('openMain');
      case 'privacy':
        _callMain('togglePrivacy');
      case 'through':
        _callMain('toggleClickThrough');
      case 'hide':
        _callMain('hideCard');
    }
  }
}
