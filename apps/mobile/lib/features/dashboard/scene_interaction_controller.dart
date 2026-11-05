/// SCN-02/SCN-03: 统一拥有拍肩与下班离场两个一次性动画的瞬态控制器。
///
/// 控制器只读工作上下文与页面可见性，对外暴露不可变的 [ScenePresentation]。
/// 它不写数据库、不提升账本修订、不请求行情、不发布小部件快照；财务数值
/// 仍由 DashboardCalculator 从时钟与区间重算，动画帧从不累加账本金额。
library;

import 'package:finance_core/finance_core.dart';
import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';

import '../../domain/ledger.dart';

/// 场景情绪：独立于瞬态，由盈亏与完整性决定。
enum SceneMood { gain, loss, unknown }

/// 逻辑在场状态：working/breakTime 在场，其余为空位。
enum Presence { atDesk, emptyDesk }

enum TransientKind { idle, pat, departure }

/// 一次拍肩请求的结果。拒绝时所有计时与文案索引保持不变。
enum PatRequestResult { accepted, rejected }

/// 展示层当前应画什么。渲染器按它逐帧计算，同一次进度输入得到同一帧。
final class ScenePresentation {
  const ScenePresentation({
    required this.phase,
    required this.presence,
    required this.mood,
    required this.transient,
    required this.progress,
    required this.canPat,
    required this.reduceMotion,
    required this.ambientMs,
    required this.animateAmbient,
    this.responseId,
  });

  static const ScenePresentation empty = ScenePresentation(
    phase: DayPhase.unknown,
    presence: Presence.emptyDesk,
    mood: SceneMood.unknown,
    transient: TransientKind.idle,
    progress: 0,
    canPat: false,
    reduceMotion: false,
    ambientMs: 0,
    animateAmbient: false,
  );

  final DayPhase phase;
  final Presence presence;
  final SceneMood mood;

  /// 当前瞬态及 0..1 进度（对应该瞬态的完整时长）。
  final TransientKind transient;
  final double progress;

  final bool canPat;

  /// 本次被接受的回应标识；页面用它驱动文案与 live region。
  final String? responseId;

  final bool reduceMotion;

  /// 环境循环（雨、呼吸、敲键盘）使用的循环时间。
  final double ambientMs;
  final bool animateAmbient;
}

/// docs/09 §4 PAT-05 文案池：无随机数，按接受次序循环。
abstract final class PatResponses {
  static const Map<AppTone, List<String>> working = {
    AppTone.gentle: [
      '辛苦了。你又不是打印机。',
      '收到，肩膀先放下来一点。',
      '谢谢，刚才差点卡成工位配件。',
    ],
    AppTone.harsh: [
      '工资没加，倒是被当人看了一眼。',
      '老板没看见，先松口气。',
      '牛马收到一点人类关怀。',
    ],
  };

  static const Map<AppTone, List<String>> breakTime = {
    AppTone.gentle: [
      '先歇会儿，下午再慢慢来。',
      '这口气，总算顺下来了。',
      '有人在意，午休都松一点。',
    ],
    AppTone.harsh: [
      '午休被记得，也算公司福利之外了。',
      '人在充电，账单也在充电。',
      '打工暂停，做人继续。',
    ],
  };

  static String forContext({
    required AppTone tone,
    required bool onBreak,
    required int index,
  }) {
    final pool = (onBreak ? breakTime : working)[tone] ?? working[AppTone.gentle]!;
    return pool[index % pool.length];
  }
}

/// 拍肩与离场的互斥一次性控制器。
///
/// - 拍肩 3200ms（减少动效 2400ms 静态回应）；
/// - 离场 2200ms，仅在页面可见时跨过真实班次终点后播放一次；
/// - 隐藏、身份变化与时钟跳变一律取消瞬态并回到稳态。
final class SceneInteractionController extends ChangeNotifier {
  SceneInteractionController({required TickerProvider vsync})
      : _patController = AnimationController(
          vsync: vsync,
          duration: patDuration,
        ),
        _departureController = AnimationController(
          vsync: vsync,
          duration: departureDuration,
        ) {
    _patController.addListener(_notify);
    _patController.addStatusListener(_onPatStatus);
    _departureController.addListener(_notify);
    _departureController.addStatusListener(_onDepartureStatus);
  }

  /// PAT-03 拍肩总时长。
  static const Duration patDuration = Duration(milliseconds: 3200);

  /// MOTION-01 减少动效下的静态回应保留时长。
  static const Duration patReducedDuration = Duration(milliseconds: 2400);

  /// OUT-02 离场总时长。
  static const Duration departureDuration = Duration(milliseconds: 2200);

  /// OUT-01 首次观察到结束的容错窗口；只决定是否播放过渡。
  static const Duration departureWindow = Duration(milliseconds: 2000);

  /// PAT-03 420ms 起反馈区切换为完整回应。
  static const int responseAtMs = 420;

  final AnimationController _patController;
  final AnimationController _departureController;

  // ---- 输入状态（由 reconcile 更新） ----
  WorkSessionContext? _workSession;
  SceneMood _mood = SceneMood.unknown;
  AppTone _tone = AppTone.gentle;
  bool _reduceMotion = false;
  bool _visible = true;
  String _namespace = '';
  int _scheduleStamp = 0;
  DateTime? _lastReconcileNow;

  // ---- 瞬态状态 ----
  TransientKind _kind = TransientKind.idle;
  String? _responseId;
  int _acceptedCount = 0;
  AppTone? _responseTone;
  bool _responseOnBreak = false;
  int _responseIndex = 0;
  String? _announcement;
  String? _monitoredSessionKey;
  String? _lastDepartureSessionKey;
  double _patElapsedBaseMs = 0;

  /// 环境循环时间由外部（OfficeScene 的 8 秒控制器）供给，控制器仅透传，
  /// 保证 250ms 财务 tick 不会重启环境动画。
  double ambientMs = 0;
  bool ambientAnimating = false;

  // ---- 读取 ----
  DayPhase get phase => _workSession?.phase ?? DayPhase.unknown;

  Presence get presence =>
      phase == DayPhase.working || phase == DayPhase.breakTime
          ? Presence.atDesk
          : Presence.emptyDesk;

  SceneMood get mood => _mood;

  TransientKind get transient => _kind;

  double get progress => switch (_kind) {
        TransientKind.pat => _patController.value,
        TransientKind.departure => _departureController.value,
        _ => 0,
      };

  /// 拍肩已进行的毫秒数（含减少动效保留段）。
  double get patElapsedMs =>
      _patElapsedBaseMs + _patController.value * _patController.duration!.inMilliseconds;

  bool get canPat =>
      _visible && _kind == TransientKind.idle && presence == Presence.atDesk;

  String? get responseId => _responseId;

  String? get announcement => _announcement;

  int get acceptedPatCount => _acceptedCount;

  /// PAT-02 反馈区当前应显示的一行文案（仅瞬态期间有效）。
  String? get feedbackLine {
    switch (_kind) {
      case TransientKind.pat:
        if (!_reduceMotion && patElapsedMs < responseAtMs) {
          return '他抬头看了你一眼。';
        }
        return PatResponses.forContext(
          tone: _responseTone ?? _tone,
          onBreak: _responseOnBreak,
          index: _responseIndex,
        );
      case TransientKind.departure:
        if (_departureController.value * departureDuration.inMilliseconds <
            560) {
          return '他把手从键盘上拿开了。';
        }
        return '今日工位，暂停营业。';
      case TransientKind.idle:
        return null;
    }
  }

  ScenePresentation get presentation => ScenePresentation(
        phase: phase,
        presence: presence,
        mood: _mood,
        transient: _kind,
        progress: progress,
        canPat: canPat,
        reduceMotion: _reduceMotion,
        ambientMs: ambientMs,
        animateAmbient: ambientAnimating && !_reduceMotion,
        responseId: _responseId,
      );

  // ---- 交互入口 ----

  /// PAT-01：按钮与头肩触控共用。人不在工位、瞬态未结束或页面不可见时拒绝。
  PatRequestResult requestPat({
    required WorkSessionContext? workSession,
    required DateTime nowUtc,
  }) {
    if (workSession != null) _workSession = workSession;
    if (!canPat) return PatRequestResult.rejected;
    _acceptedCount += 1;
    _responseId = 'pat-$_acceptedCount';
    _responseTone = _tone;
    _responseOnBreak = phase == DayPhase.breakTime;
    _responseIndex = (_acceptedCount - 1) % 3;
    _kind = TransientKind.pat;
    _patElapsedBaseMs = 0;
    _patController.duration = _reduceMotion ? patReducedDuration : patDuration;
    _patController.forward(from: 0);
    // A11Y-01：live region 播报本次完整回应，不逐帧播报。
    _announcement = PatResponses.forContext(
      tone: _responseTone ?? _tone,
      onBreak: _responseOnBreak,
      index: _responseIndex,
    );
    _notify();
    return PatRequestResult.accepted;
  }

  /// §7.3 reconcile：每次页面 rebuild 后（post-frame）调用。
  void reconcile({
    required WorkSessionContext? workSession,
    required DateTime nowUtc,
    required bool visible,
    required String namespace,
    required int scheduleStamp,
    required SceneMood mood,
    required AppTone tone,
    required bool reduceMotion,
  }) {
    var dirty = false;
    final identityChanged =
        namespace != _namespace || scheduleStamp != _scheduleStamp;
    final clockJump = _lastReconcileNow != null &&
        (nowUtc.isBefore(_lastReconcileNow!) ||
            nowUtc.difference(_lastReconcileNow!) >
                const Duration(seconds: 5));
    _lastReconcileNow = nowUtc;
    _namespace = namespace;
    _scheduleStamp = scheduleStamp;

    // MOTION-01：中途减少动效。拍肩保留静态回应至接受后 2400ms；离场直接完成。
    if (reduceMotion != _reduceMotion) {
      _reduceMotion = reduceMotion;
      dirty = true;
      if (_kind == TransientKind.pat) {
        final holdMs = patReducedDuration.inMilliseconds - patElapsedMs;
        if (holdMs <= 0) {
          _finishPat();
        } else {
          _patController.stop();
          _patElapsedBaseMs = patElapsedMs;
          _patController.duration = Duration(milliseconds: holdMs.round());
          _patController.forward(from: 0);
        }
      } else if (_kind == TransientKind.departure) {
        _finishDeparture();
      }
    }

    if (visible != _visible) {
      _visible = visible;
      dirty = true;
      if (!visible) {
        // §7.4：隐藏即取消瞬态并停止相关 ticker，不后台排队。
        _cancelTransient();
        _acceptedCount = 0;
        _monitoredSessionKey = null;
      }
      // 重新可见的第一帧只取稳态，不补播任何过渡（OUT-01/OUT-04）。
      _monitoredSessionKey = workSession?.activeSession?.key;
    }

    if (identityChanged || clockJump) {
      // 数据身份、排班修订或时钟跳变：取消瞬态并重新求稳态（§7.5）。
      _cancelTransient();
      _monitoredSessionKey = workSession?.activeSession?.key;
      dirty = true;
    }

    if (mood != _mood) {
      _mood = mood;
      dirty = true; // mood 为独立输入，不重置瞬态进度。
    }
    if (tone != _tone) {
      // PAT-05：当前一句读完，下一次采用新语气。
      _tone = tone;
    }
    _workSession = workSession;

    if (!visible) {
      if (dirty) _notify();
      return;
    }

    // OUT-01：前台可见且连续跨越同一班次终点 → 播放一次离场。
    final activeKey = workSession?.activeSession?.key;
    final monitored = _monitoredSessionKey;
    if (monitored != null && activeKey != monitored) {
      _monitoredSessionKey = activeKey;
      final ended = workSession?.lastEndedSession;
      final crossedTheMonitoredEnd = ended != null && ended.key == monitored;
      if (crossedTheMonitoredEnd &&
          nowUtc.difference(ended.endUtc) <= departureWindow) {
        _startDeparture(ended.key);
      }
      dirty = true;
    } else if (monitored == null && activeKey != null) {
      _monitoredSessionKey = activeKey;
    }

    if (dirty) _notify();
  }

  /// 供 OfficeScene 透传环境循环时间。
  void reportAmbient({required double timeMs, required bool animating}) {
    ambientMs = timeMs;
    ambientAnimating = animating;
  }

  // ---- 内部流转 ----

  void _startDeparture(String sessionKey) {
    if (_lastDepartureSessionKey == sessionKey) return;
    _lastDepartureSessionKey = sessionKey;
    if (_kind == TransientKind.pat) _patController.stop();
    _kind = TransientKind.departure;
    _responseId = null;
    _departureController.forward(from: 0);
    _announcement = '他已下班，工位已空';
  }

  void _onPatStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && _kind == TransientKind.pat) {
      _finishPat();
    }
  }

  void _onDepartureStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed &&
        _kind == TransientKind.departure) {
      _finishDeparture();
    }
  }

  void _finishPat() {
    _kind = TransientKind.idle;
    _patElapsedBaseMs = 0;
    _patController
      ..stop()
      ..reset();
    _notify();
  }

  void _finishDeparture() {
    _kind = TransientKind.idle;
    _departureController
      ..stop()
      ..reset();
    _notify();
  }

  void _cancelTransient() {
    if (_kind == TransientKind.idle) return;
    _kind = TransientKind.idle;
    _responseId = null;
    _patElapsedBaseMs = 0;
    _patController
      ..stop()
      ..reset();
    _departureController
      ..stop()
      ..reset();
  }

  void _notify() {
    notifyListeners();
  }

  @override
  void dispose() {
    _patController.removeListener(_notify);
    _patController.removeStatusListener(_onPatStatus);
    _departureController.removeListener(_notify);
    _departureController.removeStatusListener(_onDepartureStatus);
    _patController.dispose();
    _departureController.dispose();
    super.dispose();
  }
}

/// 盈亏/完整性 → 场景情绪。报价不完整只影响天气，不影响在场。
SceneMood sceneMoodOf(Completeness completeness, Rational? total) {
  if (completeness != Completeness.complete) return SceneMood.unknown;
  if (total == null) return SceneMood.unknown;
  return total.isNegative ? SceneMood.loss : SceneMood.gain;
}