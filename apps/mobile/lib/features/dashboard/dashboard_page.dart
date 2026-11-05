/// HOME-01 求生现场。
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:finance_core/finance_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../domain/format.dart';
import '../../domain/ledger.dart';
import '../ledger/ledger_controller.dart';
import '../settings/settings_page.dart';
import '../shell/tabs.dart';
import 'office_scene.dart';
import 'scene_interaction_controller.dart';

class DashboardPage extends ConsumerStatefulWidget {
  const DashboardPage({super.key});

  @override
  ConsumerState<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends ConsumerState<DashboardPage>
    with TickerProviderStateMixin {
  late final SceneInteractionController _sceneController =
      SceneInteractionController(vsync: this);
  final GlobalKey _sceneKey = GlobalKey();
  bool _sceneInViewport = true;

  /// PAT-01：按钮与头肩触控共用一个入口。
  void _requestPat() {
    final snapshot = ref.read(dashboardProvider).value;
    final now = ref.read(tickProvider).value ??
        ref.read(clockProvider).nowUtc();
    final result = _sceneController.requestPat(
      workSession: snapshot?.workSession,
      nowUtc: now,
    );
    if (result == PatRequestResult.accepted) {
      // PAT-06：一次接受对应一次轻触觉，遵循系统触觉设置。
      unawaited(HapticFeedback.selectionClick());
    }
  }

  @override
  void dispose() {
    _sceneController.dispose();
    super.dispose();
  }

  /// §7.4：App 前台、首页被选中、无路由覆盖、场景在视口内。
  bool _resolveSceneVisibility(BuildContext context) {
    final appVisible = ref.watch(appVisibleProvider);
    final tabSelected = ref.watch(selectedTabProvider) == AppTab.dashboard;
    final route = ModalRoute.of(context);
    final routeCurrent = route == null || route.isCurrent;
    return appVisible && tabSelected && routeCurrent && _sceneInViewport;
  }

  void _measureScene() {
    final box = _sceneKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached || !box.hasSize) return;
    final topLeft = box.localToGlobal(Offset.zero);
    final screen = Offset.zero & MediaQuery.sizeOf(context);
    final visibleRect = topLeft & box.size;
    final intersection = visibleRect.intersect(screen);
    final fraction =
        box.size.height <= 0 ? 0.0 : intersection.height / box.size.height;
    final visible = fraction > 0.5;
    if (visible != _sceneInViewport) {
      setState(() => _sceneInViewport = visible);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final ledger = ref.watch(effectiveLedgerProvider).value;
    final snapshotAsync = ref.watch(dashboardProvider);
    final calendar = ref.watch(calendarProvider);
    final settings = ledger?.settings;
    final reduceMotion = settings?.motion == MotionSetting.reduced ||
        MediaQuery.of(context).disableAnimations;
    final now = ref.watch(tickProvider).value ??
        ref.read(clockProvider).nowUtc();
    final sceneVisible = _resolveSceneVisibility(context);
    final snapshot = snapshotAsync.value;

    // §7.3 reconcile：post-frame 调用，避免在 build 内 notifyListeners。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _measureScene();
      _sceneController.reconcile(
        workSession: snapshot?.workSession,
        nowUtc: now,
        visible: _resolveSceneVisibility(context),
        namespace: ref.read(sampleModeProvider)
            ? 'sample'
            : 'real-${settings?.ledgerRevision ?? 0}',
        scheduleStamp: settings?.ledgerRevision ?? 0,
        mood: snapshot == null
            ? SceneMood.unknown
            : sceneMoodOf(snapshot.completeness, snapshot.total),
        tone: settings?.tone ?? AppTone.gentle,
        reduceMotion: reduceMotion,
      );
    });

    return NotificationListener<ScrollNotification>(
      onNotification: (_) {
        scheduleMicrotask(_measureScene);
        return false;
      },
      child: RefreshIndicator(
        color: palette.ink,
        onRefresh: () =>
            ref.read(ledgerControllerProvider.notifier).refreshQuotes(),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _Header(
                          date: snapshot?.statisticsDate ??
                              calendar.dateOf(now),
                          phase: snapshot?.phase ?? DayPhase.unknown,
                          clock: formatClock(now, calendar),
                        ),
                        const SizedBox(height: 14),
                        snapshotAsync.when(
                          data: (snapshot) => _Body(
                            snapshot: snapshot,
                            ledger: ledger,
                            calendar: calendar,
                            reduceMotion: reduceMotion,
                            controller: _sceneController,
                            sceneKey: _sceneKey,
                            sceneVisible: sceneVisible,
                            onRequestPat: _requestPat,
                          ),
                          loading: () => const _LoadingCard(),
                          error: (error, _) => PaperCard(
                            child: Text('首页算不动了：$error'),
                          ),
                        ),
                        const SizedBox(height: 18),
                        _SourceNote(
                          fixture: ref.read(marketClientProvider).isFixture,
                          quotesAsOf: snapshotAsync.value?.quotesAsOf,
                          calendar: calendar,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.date,
    required this.phase,
    required this.clock,
  });

  final LocalDate date;
  final DayPhase phase;
  final String clock;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final stamp = switch (phase) {
      DayPhase.working => '在岗求生中',
      DayPhase.breakTime => '午休计费暂停',
      DayPhase.restDay => '休息也计费',
      DayPhase.beforeShift => '还没轮到上班',
      DayPhase.afterShift => '月供接班中',
      DayPhase.unknown => '状态待定',
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'ANOTHER DAY, ANOTHER DEBT.',
                style: Theme.of(context).textTheme.labelSmall,
              ),
              const SizedBox(height: 3),
              Text('今日又白干', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 2),
              Text(
                '${date.month}月${date.day.toString().padLeft(2, '0')}日 · '
                '${weekdayLabel(date.weekday)} · $clock',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            IconButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const SettingsPage()),
              ),
              icon: const Icon(Icons.tune, size: 21),
              tooltip: '设置',
            ),
            Transform.rotate(
              angle: 0.14,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  border: Border.all(color: palette.negative, width: 1.5),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  stamp,
                  style: TextStyle(
                    color: palette.negative,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.snapshot,
    required this.ledger,
    required this.calendar,
    required this.reduceMotion,
    required this.controller,
    required this.sceneKey,
    required this.sceneVisible,
    required this.onRequestPat,
  });

  final DashboardSnapshot snapshot;
  final LedgerState? ledger;
  final BusinessCalendar calendar;
  final bool reduceMotion;
  final SceneInteractionController controller;
  final Key sceneKey;
  final bool sceneVisible;
  final VoidCallback onRequestPat;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final settings = ledger?.settings;
    final total = snapshot.total;
    final known = total != null;
    final positive = known && !total.isNegative;
    final tone = settings?.tone ?? AppTone.gentle;
    final housingConfigured = snapshot.housingDetail.configured;
    final carConfigured = snapshot.carDetail.configured;

    final quote = _quoteLine(snapshot: snapshot, tone: tone);
    final steadyFeedback = _steadyFeedbackLine(
      snapshot: snapshot,
      housingConfigured: housingConfigured,
      carConfigured: carConfigured,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PaperCard(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(child: Text('今日生存结余')),
                  _Tag(
                    snapshot.completeness == Completeness.unavailable
                        ? '待配置'
                        : !known
                            ? '待更新'
                            : positive
                                ? '暂时领先'
                                : '努力回本',
                    background: snapshot.completeness == Completeness.complete
                        ? palette.yellow
                        : palette.line,
                  ),
                ],
              ),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: MoneyText(
                  formatMoney(total),
                  size: 42,
                  color: !known
                      ? palette.muted
                      : positive
                          ? palette.positive
                          : palette.negative,
                ),
              ),
              const SizedBox(height: 6),
              Container(
                decoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(color: palette.rose, width: 3),
                  ),
                ),
                padding: const EdgeInsets.only(left: 9),
                child: Text(quote, style: const TextStyle(fontSize: 13)),
              ),
              if (snapshot.completeness != Completeness.complete) ...[
                const SizedBox(height: 10),
                _CompletenessNote(snapshot: snapshot),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: OfficeScene(
            key: sceneKey,
            phase: snapshot.phase,
            completeness: snapshot.completeness,
            total: snapshot.total,
            reduceMotion: reduceMotion,
            controller: controller,
            active: sceneVisible,
            onRequestPat: onRequestPat,
            showHousing: housingConfigured,
            showCar: carConfigured,
            housingLabel: switch (snapshot.housingDetail.housingMode) {
              HousingMode.rent => '房租',
              HousingMode.mortgage => '房贷',
              _ => '住房',
            },
            carLabel: '车贷',
          ),
        ),
        const SizedBox(height: 6),
        // PAT-02：固定预留的反馈区，平常显示状态说明，拍肩时升级为对话气泡。
        _FeedbackArea(
          controller: controller,
          steadyText: steadyFeedback,
        ),
        const SizedBox(height: 10),
        _ClockRow(
          snapshot: snapshot,
          calendar: calendar,
          controller: controller,
          onRequestPat: onRequestPat,
        ),
        const SizedBox(height: 8),
        _ProgressBar(snapshot: snapshot),
        if (housingConfigured || carConfigured) ...[
          const SizedBox(height: 16),
          _ReceiptsRow(snapshot: snapshot),
        ],
        const SizedBox(height: 16),
        _Entries(snapshot: snapshot, calendar: calendar),
        const SizedBox(height: 8),
        _Explanation(snapshot: snapshot, calendar: calendar),
      ],
    );
  }

  /// OUT-04 空工位与各阶段的稳态说明。
  static String _steadyFeedbackLine({
    required DashboardSnapshot snapshot,
    required bool housingConfigured,
    required bool carConfigured,
  }) {
    if (snapshot.phase == DayPhase.afterShift) {
      final known =
          snapshot.housing != null && snapshot.car != null;
      final spend = (snapshot.housing ?? Rational.zero) +
          (snapshot.car ?? Rational.zero);
      if (known && spend.isPositive) {
        return '人下班了，固定支出还在全勤。';
      }
      if (known) return '人已下班，今天到此为止。';
      return '人下班了，账单明细待更新。';
    }
    return switch (snapshot.phase) {
      DayPhase.working => switch ((housingConfigured, carConfigured)) {
          (true, true) => '工位 0001 · 赚来的钱，流向房子和车',
          (true, false) => '工位 0001 · 赚来的钱，流向房子',
          (false, true) => '工位 0001 · 赚来的钱，流向车',
          _ => '工位 0001 · 赚来的钱都是自己的',
        },
      DayPhase.breakTime => '午休暂停计薪 · 固定支出继续分摊',
      DayPhase.restDay => switch ((housingConfigured, carConfigured)) {
          (true, true) => '工位空了 · 房子和车的账单还在',
          (true, false) => '工位空了 · 房子的账单还在',
          (false, true) => '工位空了 · 车的账单还在',
          _ => '工位空了 · 账单也放假了',
        },
      DayPhase.beforeShift => '人还没到 · 账单先到',
      DayPhase.afterShift => '人下班了 · 生活还在全勤',
      DayPhase.unknown => '排班还没准备好',
    };
  }

  static String _quoteLine({
    required DashboardSnapshot snapshot,
    required AppTone tone,
  }) {
    final harsh = tone == AppTone.harsh;
    if (snapshot.completeness == Completeness.unavailable) {
      return '配置还差一点，工资与账单暂时无法开工。';
    }
    if (snapshot.phase == DayPhase.restDay) {
      return harsh ? '你休息了，账单觉得你想多了。' : '今天不上班，生活照常扣费。';
    }
    if (snapshot.phase == DayPhase.breakTime) {
      return '午休不涨工资，账单倒是很准时。';
    }
    if (snapshot.phase == DayPhase.afterShift) {
      return '人下班了，生活还在全勤。';
    }
    if (snapshot.completeness == Completeness.partial) {
      return '投资待更新，当前合计不完整。';
    }
    final total = snapshot.total;
    if (total == null) return '数字还在路上。';
    if (total.isNegative) {
      return harsh ? '辛苦一天，成功把亏损补小了一点。' : '工资正在努力追赶上午的亏损。';
    }
    return harsh ? '难得赢一局，房贷已经在候场。' : '今天暂时领先，先小声开心一下。';
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text, {required this.background});

  final String text;
  final Color background;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(
          text,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        ),
      );
}

class _CompletenessNote extends StatelessWidget {
  const _CompletenessNote({required this.snapshot});

  final DashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final missing = <String>[
      if (snapshot.stockDaily == null) 'A股今日浮动',
      if (snapshot.goldDaily == null) '黄金今日浮动',
      if (snapshot.housing == null) '住房账单',
      if (snapshot.car == null) '车贷账单',
    ];
    final message = snapshot.completeness == Completeness.unavailable
        ? '核心配置无效，主数字暂不可用。'
        : '缺少：${missing.join('、')}。当前只展示可计算部分。';
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: context.palette.paper,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.palette.line),
      ),
      child: Text(message, style: Theme.of(context).textTheme.bodySmall),
    );
  }
}

/// PAT-02 反馈区：预留最小高度，交互开始时不推动布局跳动。
class _FeedbackArea extends StatelessWidget {
  const _FeedbackArea({
    required this.controller,
    required this.steadyText,
  });

  final SceneInteractionController controller;
  final String steadyText;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final speaking = controller.transient != TransientKind.idle;
        final line = controller.feedbackLine ?? steadyText;
        final textScale = MediaQuery.textScalerOf(context).scale(13);
        final minHeight = math.max(56.0, textScale * 1.5 * 2 + 16);
        final announcement =
            speaking ? (controller.announcement ?? line) : line;
        final bubble = Container(
          constraints: BoxConstraints(minHeight: minHeight),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: palette.panel,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            line,
            style: const TextStyle(fontSize: 13, height: 1.5),
          ),
        );
        return Semantics(
          liveRegion: speaking,
          label: announcement,
          excludeSemantics: true,
          child: speaking
              ? Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: palette.ink, width: 1.5),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.all(1.5),
                      child: bubble,
                    ),
                    Positioned(
                      top: -5,
                      left: 26,
                      child: Transform.rotate(
                        angle: math.pi / 4,
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: palette.panel,
                            border: Border(
                              top: BorderSide(color: palette.ink, width: 1.5),
                              left: BorderSide(color: palette.ink, width: 1.5),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                )
              : Container(
                  constraints: BoxConstraints(minHeight: minHeight),
                  decoration: BoxDecoration(
                    border: Border(
                      left: BorderSide(color: palette.rose, width: 3),
                    ),
                  ),
                  padding: const EdgeInsets.only(left: 9),
                  alignment: Alignment.centerLeft,
                  child: Text(
                    line,
                    style: const TextStyle(fontSize: 13, height: 1.5),
                  ),
                ),
        );
      },
    );
  }
}

class _ClockRow extends StatelessWidget {
  const _ClockRow({
    required this.snapshot,
    required this.calendar,
    required this.controller,
    required this.onRequestPat,
  });

  final DashboardSnapshot snapshot;
  final BusinessCalendar calendar;
  final SceneInteractionController controller;
  final VoidCallback onRequestPat;

  @override
  Widget build(BuildContext context) {
    final now = snapshot.computedAtUtc;
    final timeline = snapshot.timeline;
    final session = snapshot.workSession;
    String text;
    if (session.scheduleValid) {
      text = switch (snapshot.phase) {
        DayPhase.working => _countdown(
            '距离下班还有',
            session.activeSession?.endUtc,
            now,
            fallback: '计薪中',
          ),
        DayPhase.breakTime => '午休中 · 账单继续分摊',
        DayPhase.beforeShift => _countdown(
            '距离上班还有',
            session.nextSession?.startUtc,
            now,
            fallback: '还没上班',
          ),
        DayPhase.afterShift => _afterShiftText(session, calendar),
        _ => '排班还没准备好',
      };
    } else if (timeline == null || timeline.isRestDay) {
      text = '工资休息中 · 月供照常营业';
    } else if (snapshot.phase == DayPhase.working) {
      final end = timeline.shiftEndUtc;
      text = end == null
          ? '计薪中'
          : '距离下班还有 ${formatDuration(end.difference(now).inSeconds)}';
    } else if (snapshot.phase == DayPhase.breakTime) {
      text = '午休中 · 账单继续分摊';
    } else if (snapshot.phase == DayPhase.beforeShift) {
      final start = timeline.shiftStartUtc;
      text = start == null
          ? '还没上班'
          : '距离上班还有 ${formatDuration(start.difference(now).inSeconds)}';
    } else if (snapshot.phase == DayPhase.afterShift) {
      text = '今日排班已结束 · 月供继续营业';
    } else {
      text = '排班还没准备好';
    }
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final presentation = controller.presentation;
        final canPat = presentation.canPat;
        final (label, enabled) = _patButtonState(presentation);
        return Row(
          children: [
            Expanded(
              child: Text(text, style: Theme.of(context).textTheme.bodySmall),
            ),
            Semantics(
              label: '拍拍他，给正在工位上的他一点安慰',
              button: true,
              child: TextButton.icon(
                onPressed: enabled ? onRequestPat : null,
                icon: const Icon(Icons.back_hand_outlined, size: 16),
                label: Text(label),
                style: TextButton.styleFrom(
                  minimumSize: const Size(44, 44),
                  foregroundColor:
                      canPat ? context.palette.ink : context.palette.muted,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  static (String, bool) _patButtonState(ScenePresentation presentation) {
    if (presentation.transient == TransientKind.pat) {
      final elapsedMs =
          presentation.progress * SceneInteractionController.patDuration.inMilliseconds;
      return (elapsedMs < 520 ? '收到啦' : '他缓过来一点了', false);
    }
    if (presentation.transient == TransientKind.departure) {
      return ('他已下班', false);
    }
    return switch (presentation.phase) {
      DayPhase.working ||
      DayPhase.breakTime =>
        presentation.canPat ? ('拍拍他', true) : ('拍拍他', false),
      DayPhase.afterShift => ('他已下班', false),
      DayPhase.beforeShift => ('还没到工位', false),
      DayPhase.restDay => ('今天不在岗', false),
      DayPhase.unknown => ('排班待确认', false),
    };
  }

  static String _countdown(
    String prefix,
    DateTime? endUtc,
    DateTime now, {
    required String fallback,
  }) {
    if (endUtc == null) return fallback;
    return '$prefix ${formatDuration(endUtc.difference(now).inSeconds)}';
  }

  static String _afterShiftText(
    WorkSessionContext session,
    BusinessCalendar calendar,
  ) {
    final next = session.nextSession;
    final ended = session.lastEndedSession?.endUtc;
    if (next != null && ended != null && next.startUtc.isAfter(ended)) {
      return '已下班，下一班 ${formatClock(next.startUtc, calendar)}';
    }
    return '今日排班已结束 · 月供继续营业';
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.snapshot});

  final DashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final timeline = snapshot.timeline;
    final total = timeline?.paidSecondsTotal ?? 0;
    final elapsed = timeline?.paidSecondsElapsed(snapshot.computedAtUtc) ?? 0;
    final progress = total == 0 ? 0.0 : (elapsed / total).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 6,
            backgroundColor: context.palette.line,
            valueColor: AlwaysStoppedAnimation<Color>(context.palette.positive),
          ),
        ),
        const SizedBox(height: 4),
        Semantics(
          label: '今日排班完成 ${(progress * 100).round()}%',
          child: Align(
            alignment: Alignment.centerRight,
            child: Text(
              '今日计薪 ${formatHours(elapsed)} / ${formatHours(total)} 小时',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ),
      ],
    );
  }
}

class _ReceiptsRow extends ConsumerWidget {
  const _ReceiptsRow({required this.snapshot});

  final DashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final housing = snapshot.housingDetail;
    final car = snapshot.carDetail;
    final cards = <Widget>[
      if (housing.configured)
        Expanded(
          child: _ReceiptCard(
            title: switch (housing.housingMode) {
              HousingMode.rent => '房租',
              HousingMode.mortgage => '住房按揭',
              _ => '住房',
            },
            type: DebtArtType.house,
            monthly: housing.monthlyAmount,
            dailyShare: housing.dayShare,
            allocated: housing.dayAmount,
            onTap: () =>
                ref.read(selectedTabProvider.notifier).state = AppTab.expenses,
          ),
        ),
      if (car.configured)
        Expanded(
          child: _ReceiptCard(
            title: '车辆贷款',
            type: DebtArtType.car,
            monthly: car.monthlyAmount,
            dailyShare: car.dayShare,
            allocated: car.dayAmount,
            onTap: () =>
                ref.read(selectedTabProvider.notifier).state = AppTab.expenses,
          ),
        ),
    ];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        cards.first,
        if (cards.length > 1) ...[const SizedBox(width: 10), cards.last],
      ],
    );
  }
}

class _ReceiptCard extends StatelessWidget {
  const _ReceiptCard({
    required this.title,
    required this.type,
    required this.monthly,
    required this.dailyShare,
    required this.allocated,
    required this.onTap,
  });

  final String title;
  final DebtArtType type;
  final Rational? monthly;
  final Rational dailyShare;
  final Rational? allocated;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return PaperCard(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      radius: 14,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: const TextStyle(fontSize: 12))),
              Text('本月', style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
          const SizedBox(height: 4),
          Center(child: DebtArt(type: type, height: 62)),
          const SizedBox(height: 6),
          Text(
            '本月账单',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          MoneyText(
            formatMoney(monthly, placeholder: '待补充'),
            size: 18,
            color: palette.ink,
          ),
          const SizedBox(height: 2),
          Text(
            '每日分摊 ${formatMoney(dailyShare)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          Text(
            '今日已分摊 ${formatMoney(allocated)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _Entries extends StatelessWidget {
  const _Entries({required this.snapshot, required this.calendar});

  final DashboardSnapshot snapshot;
  final BusinessCalendar calendar;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final wage = snapshot.wage;
    final stock = snapshot.stockDaily;
    final gold = snapshot.goldDaily;
    final expenses = snapshot.allocatedExpenses;
    final monthStats = snapshot.monthStats;
    final quotesAsOf = formatClock(snapshot.quotesAsOf, calendar);
    final debtLabel = [
      if (snapshot.housingDetail.configured) '住房',
      if (snapshot.carDetail.configured) '车贷',
    ].join(' + ');
    return Column(
      children: [
        _EntryRow(
          label: '打工 · 今日已挣',
          value: formatMoney(wage, signed: true),
          color: palette.positive,
          note: snapshot.wageSegmented
              ? '按分段配置估算 · 本月排班 '
                  '${formatHours(monthStats?.paidSeconds ?? 0)} 小时'
              : '到手月薪 ${formatMoney(monthStats?.monthlyCny)} · '
                  '本月排班 ${formatHours(monthStats?.paidSeconds ?? 0)} 小时',
        ),
        _EntryRow(
          label: 'A股 · 今日浮动',
          value: formatMoney(stock, signed: true),
          color: (stock?.isNegative ?? false) ? palette.negative : palette.positive,
          note: snapshot.assets.positions.isEmpty
              ? '没有A股持仓'
              : '${snapshot.assets.positions.where((p) => p.kind == InstrumentKind.stock).length} 只持仓 · '
                  '${snapshot.quoteQuality == QuoteQuality.fixture ? '模拟报价' : '报价截至 $quotesAsOf'}',
        ),
        _EntryRow(
          label: '黄金 · 今日浮动',
          value: formatMoney(gold, signed: true),
          color: (gold?.isNegative ?? false) ? palette.negative : palette.positive,
          note: snapshot.assets.positions.any((p) => p.kind == InstrumentKind.gold)
              ? '人民币每克参考价估值 · 参考交易日口径'
              : '没有黄金持仓',
        ),
        if (debtLabel.isNotEmpty)
          _EntryRow(
            label: '$debtLabel · 已分摊',
            value: formatMoney(expenses == null ? null : -expenses),
            color: palette.ink,
            note: '按自然日全天分摊 · 今日总压力 '
                '${formatMoney((snapshot.housingDetail.dayShare) + (snapshot.carDetail.dayShare))}',
          ),
      ],
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({
    required this.label,
    required this.value,
    required this.note,
    required this.color,
  });

  final String label;
  final String value;
  final String note;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: palette.line, width: 1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label)),
              MoneyText(value, color: color),
            ],
          ),
          const SizedBox(height: 2),
          Text(note, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _Explanation extends StatelessWidget {
  const _Explanation({required this.snapshot, required this.calendar});

  final DashboardSnapshot snapshot;
  final BusinessCalendar calendar;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final principal = snapshot.principal;
    final interest = snapshot.interest;
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 12),
        title: Text('展开统计口径', style: Theme.of(context).textTheme.bodySmall),
        children: [
          Text(
            '今日生存结余 = 今日工资估算 + 持仓今日浮动盈亏 − 今日已分摊固定支出。'
            '固定支出按本月自然日及今日已过时间连续分摊。'
            '该数值含未实现盈亏和本金还款分摊。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.8),
          ),
          const SizedBox(height: 8),
          Text(
            '细分精度：工资 ${_precision(snapshot.wage)}，A股 ${_precision(snapshot.stockDaily)}，'
            '黄金 ${_precision(snapshot.goldDaily)}，住房 ${_precision(snapshot.housing)}，'
            '车贷 ${_precision(snapshot.car)}。分项显示取整后合计使用完整精度。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Text(
            snapshot.breakdownComplete
                ? '今日已分摊本金 ${formatMoney(principal)} · 利息 ${formatMoney(interest)}'
                : '本金信息待补充，利息暂无法拆分。月供仍全额计入压力。',
            style: TextStyle(fontSize: 12, color: palette.muted),
          ),
          const SizedBox(height: 8),
          Text(
            '统计时区 ${snapshot.timezone} · 报价截至 '
            '${formatClock(snapshot.quotesAsOf, calendar)} · '
            '交易基准 ${snapshot.assets.positions.isEmpty ? '无持仓' : '按来源交易日'}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

String _precision(Rational? value) =>
    value == null ? '—' : value.toFixed(6);

class _SourceNote extends StatelessWidget {
  const _SourceNote({
    required this.fixture,
    required this.quotesAsOf,
    required this.calendar,
  });

  final bool fixture;
  final DateTime? quotesAsOf;
  final BusinessCalendar calendar;

  @override
  Widget build(BuildContext context) => Text(
        fixture
            ? '当前为模拟行情与模拟交易日历，仅用于界面与计算验收；真实行情接入前不会伪装成实时报价。'
                '报价时间 ${formatClock(quotesAsOf, calendar)}。'
            : '行情来自 ${fixture ? '网关' : '东方财富公开接口'}，'
                '报价截至 ${formatClock(quotesAsOf, calendar)}；'
                '公开参考数据非官方授权，个人账本不会离开本机。',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodySmall,
      );
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) => const PaperCard(
        child: SizedBox(
          height: 160,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
}
