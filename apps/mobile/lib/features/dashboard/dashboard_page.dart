/// HOME-01 求生现场 + M8-HOME 首页双核心指标。
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
import '../../domain/home_metrics.dart';
import '../../domain/ledger.dart';
import '../ledger/ledger_controller.dart';
import '../settings/settings_page.dart';
import '../shell/tabs.dart';
import 'home_metrics_controller.dart';
import 'home_metrics_model.dart';
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
  bool _metricsSettingsOpen = false;

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

  Future<void> _selectMetricsMode(HomeMetricsMode mode) async {
    final saved = await ref.read(homeMetricsModeProvider.notifier).select(mode);
    if (!saved && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('显示设置没存上，请重试')),
      );
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
    final metrics = ref.watch(homeMetricsModeProvider);
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
                        const SizedBox(height: 10),
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
                            metrics: metrics,
                            settingsOpen: _metricsSettingsOpen,
                            onToggleSettings: () => setState(
                              () => _metricsSettingsOpen =
                                  !_metricsSettingsOpen,
                            ),
                            onSelectMode: (mode) =>
                                unawaited(_selectMetricsMode(mode)),
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
      DayPhase.breakTime => '休息中暂停计薪',
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
    required this.metrics,
    required this.settingsOpen,
    required this.onToggleSettings,
    required this.onSelectMode,
  });

  final DashboardSnapshot snapshot;
  final LedgerState? ledger;
  final BusinessCalendar calendar;
  final bool reduceMotion;
  final SceneInteractionController controller;
  final Key sceneKey;
  final bool sceneVisible;
  final VoidCallback onRequestPat;
  final AsyncValue<HomeMetricsMode> metrics;
  final bool settingsOpen;
  final VoidCallback onToggleSettings;
  final ValueChanged<HomeMetricsMode> onSelectMode;

  @override
  Widget build(BuildContext context) {
    final settings = ledger?.settings;
    final tone = settings?.tone ?? AppTone.gentle;
    final housingConfigured = snapshot.housingDetail.configured;
    final carConfigured = snapshot.carDetail.configured;

    final mode = metrics.value;
    final loading = mode == null;
    final timeDisplay = buildHomeTimeDisplay(
      snapshot: snapshot,
      calendar: calendar,
    );
    final balanceDisplay = buildHomeBalanceDisplay(
      snapshot: snapshot,
      calendar: calendar,
      tone: tone,
    );
    final steadyFeedback = _steadyFeedbackLine(
      snapshot: snapshot,
      housingConfigured: housingConfigured,
      carConfigured: carConfigured,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _MetricsHeading(
          expanded: settingsOpen,
          onToggle: onToggleSettings,
        ),
        if (settingsOpen) ...[
          const SizedBox(height: 5),
          _MetricsSettingsPanel(
            mode: mode,
            onSelect: onSelectMode,
          ),
          const SizedBox(height: 11),
        ] else
          const SizedBox(height: 5),
        if (loading)
          const _MetricsPlaceholder()
        else ...[
          if (mode != HomeMetricsMode.balance)
            _TimeMetricCard(display: timeDisplay),
          if (mode == HomeMetricsMode.both) const _PaperLinks(),
          if (mode != HomeMetricsMode.time)
            _BalanceMetricCard(display: balanceDisplay),
        ],
        const SizedBox(height: 12),
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
        // PAT-02：固定预留的反馈区；拍肩入口放在场景附近，不再挤占时间卡。
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: _FeedbackArea(
                controller: controller,
                steadyText: steadyFeedback,
              ),
            ),
            const SizedBox(width: 8),
            _PatButton(
              controller: controller,
              onRequestPat: onRequestPat,
            ),
          ],
        ),
        if (housingConfigured || carConfigured) ...[
          const SizedBox(height: 14),
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
      DayPhase.breakTime => '休息中 · 固定支出继续分摊',
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
}

class _MetricsHeading extends StatelessWidget {
  const _MetricsHeading({required this.expanded, required this.onToggle});

  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 38),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: const Color(0xFF9DA789),
              shape: BoxShape.circle,
              boxShadow: const [
                BoxShadow(
                  color: Color(0xFFD8BB88),
                  offset: Offset(4, 4),
                  blurRadius: 0,
                ),
              ],
            ),
          ),
          const SizedBox(width: 9),
          Text(
            '今日小记',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.6,
                ),
          ),
          const Spacer(),
          Semantics(
            button: true,
            label: '首页显示，${expanded ? '已展开' : '已收起'}',
            excludeSemantics: true,
            child: TextButton.icon(
              onPressed: onToggle,
              icon: const Icon(Icons.tune, size: 15),
              label: const Text('首页显示'),
              style: TextButton.styleFrom(
                minimumSize: const Size(44, 44),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                foregroundColor: palette.muted,
                textStyle: const TextStyle(fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricsSettingsPanel extends StatelessWidget {
  const _MetricsSettingsPanel({required this.mode, required this.onSelect});

  final HomeMetricsMode? mode;
  final ValueChanged<HomeMetricsMode> onSelect;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final enabled = mode != null;
    final textScale = MediaQuery.textScalerOf(context).scale(12);
    return Container(
      padding: const EdgeInsets.fromLTRB(13, 12, 13, 11),
      decoration: BoxDecoration(
        color: palette.panel,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: const Color(0xFFDAD6C6)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A323A32),
            offset: Offset(0, 2),
            blurRadius: 0,
          ),
        ],
      ),
      child: Semantics(
        container: true,
        label: '首页想看什么？',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ExcludeSemantics(
              child: Text(
                '首页想看什么？',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 8),
            LayoutBuilder(
              builder: (context, constraints) {
                final vertical = textScale > 16 || constraints.maxWidth < 300;
                final options = [
                  _MetricChoice(
                    label: '都显示',
                    selected: mode == HomeMetricsMode.both,
                    enabled: enabled,
                    onTap: () => onSelect(HomeMetricsMode.both),
                  ),
                  _MetricChoice(
                    label: '只看下班',
                    selected: mode == HomeMetricsMode.time,
                    enabled: enabled,
                    onTap: () => onSelect(HomeMetricsMode.time),
                  ),
                  _MetricChoice(
                    label: '只看结余',
                    selected: mode == HomeMetricsMode.balance,
                    enabled: enabled,
                    onTap: () => onSelect(HomeMetricsMode.balance),
                  ),
                ];
                if (vertical) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var index = 0; index < options.length; index++) ...[
                        if (index > 0) const SizedBox(height: 6),
                        options[index],
                      ],
                    ],
                  );
                }
                return Row(
                  children: [
                    for (var index = 0; index < options.length; index++) ...[
                      if (index > 0) const SizedBox(width: 6),
                      Expanded(child: options[index]),
                    ],
                  ],
                );
              },
            ),
            const SizedBox(height: 9),
            Text(
              '只调整首页主卡，不隐藏账单或小部件。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontSize: 11,
                    height: 1.5,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricChoice extends StatelessWidget {
  const _MetricChoice({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      enabled: enabled,
      button: true,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(9),
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? palette.soft : palette.paper,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: selected ? const Color(0xFF849279) : palette.line,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _RadioDot(selected: selected, enabled: enabled),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: enabled ? palette.ink : palette.muted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RadioDot extends StatelessWidget {
  const _RadioDot({required this.selected, required this.enabled});

  final bool selected;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? palette.positive : palette.paper,
        border: Border.all(
          color: enabled ? palette.muted : palette.line,
          width: 1.4,
        ),
      ),
      child: selected
          ? Center(
              child: Container(
                width: 5,
                height: 5,
                decoration: const BoxDecoration(
                  color: Color(0xFFFFFDF7),
                  shape: BoxShape.circle,
                ),
              ),
            )
          : null,
    );
  }
}

class _MetricsPlaceholder extends StatelessWidget {
  const _MetricsPlaceholder();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Semantics(
      label: '正在读取首页显示设置',
      child: Container(
        height: 132,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: palette.panel,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: palette.line),
        ),
        child: Text(
          '正在读取首页显示设置…',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
    );
  }
}

class _TimeMetricCard extends StatelessWidget {
  const _TimeMetricCard({required this.display});

  final HomeTimeDisplay display;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final semantics = display.showProgress
        ? '${display.semanticsLabel}。${display.progressSemantics}'
        : display.semanticsLabel;
    return Semantics(
      container: true,
      label: semantics,
      excludeSemantics: true,
      child: _MetricCard(
        background: const Color(0xFFF6E8BF),
        border: const Color(0xFFD5C69C),
        radius: 16,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const _HandDrawnClockIcon(),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    display.label,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
                _TimeTag(display.tag),
              ],
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                display.mainValue,
                key: const Key('home-countdown'),
                maxLines: 1,
                style: TextStyle(
                  fontFamily: 'Consolas',
                  fontFamilyFallback: const ['monospace'],
                  fontSize: 42,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -1.6,
                  height: 1.15,
                  color: palette.ink,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(height: 3),
            Text(
              display.detail,
              style: const TextStyle(fontSize: 12, height: 1.4),
            ),
            if (display.showProgress) ...[
              const SizedBox(height: 9),
              _MetricProgress(display: display),
            ],
          ],
        ),
      ),
    );
  }
}

class _BalanceMetricCard extends StatelessWidget {
  const _BalanceMetricCard({required this.display});

  final HomeBalanceDisplay display;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final amountColor = !display.known
        ? palette.muted
        : display.neutral
            ? palette.ink
            : display.negative
                ? palette.negative
                : palette.positive;
    final stale = display.sourceNote?.startsWith('缓存') ?? false;
    return Semantics(
      container: true,
      label: display.semanticsLabel,
      excludeSemantics: true,
      child: _MetricCard(
        background: palette.panel,
        border: const Color(0xFFD7D2C0),
        radius: 15,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const _HandDrawnBillIcon(),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    '今日生存结余',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
                Wrap(
                  spacing: 5,
                  runSpacing: 4,
                  alignment: WrapAlignment.end,
                  children: [
                    _StatusTag(
                      display.tag,
                      background: display.neutral
                          ? palette.line
                          : palette.yellow,
                      color: display.known ? palette.ink : palette.muted,
                    ),
                    if (stale)
                      _StatusTag(
                        '缓存/陈旧',
                        background: palette.rose,
                        color: palette.ink,
                      ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              display.amountText,
              key: const Key('home-balance-amount'),
              softWrap: true,
              style: TextStyle(
                fontFamily: 'Consolas',
                fontFamilyFallback: const ['monospace'],
                fontSize: _metricNumberSize(context),
                fontWeight: FontWeight.w700,
                letterSpacing: -1.2,
                height: 1.15,
                color: amountColor,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 5),
            Container(
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(color: palette.rose, width: 3),
                ),
              ),
              padding: const EdgeInsets.only(left: 9),
              child: Text(display.flavorLine, style: const TextStyle(fontSize: 13)),
            ),
            const SizedBox(height: 6),
            Text(
              display.formula,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontSize: 11,
                  ),
            ),
            if (display.completenessNote != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: palette.paper,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: palette.line),
                ),
                child: Text(
                  display.completenessNote!,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
            if (display.sourceNote != null) ...[
              const SizedBox(height: 6),
              Text(
                display.sourceNote!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontSize: 11,
                    ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static double _metricNumberSize(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(1);
    return scale > 1.5 ? 32 : 42;
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.background,
    required this.border,
    required this.radius,
    required this.child,
    required this.padding,
  });

  final Color background;
  final Color border;
  final double radius;
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: border),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0F323A32),
              offset: Offset(0, 3),
              blurRadius: 0,
            ),
          ],
        ),
        child: child,
      );
}

class _MetricProgress extends StatelessWidget {
  const _MetricProgress({required this.display});

  final HomeTimeDisplay display;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: display.progress,
            minHeight: 5,
            backgroundColor: const Color(0x33323A32),
            valueColor: AlwaysStoppedAnimation<Color>(palette.positive),
          ),
        ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            display.progressLabel,
            style: const TextStyle(fontSize: 11),
          ),
        ),
      ],
    );
  }
}

class _TimeTag extends StatelessWidget {
  const _TimeTag(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: const Color(0x80FFFDF7),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFFC9BC97)),
        ),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Color(0xFF5A604F),
          ),
        ),
      );
}

class _StatusTag extends StatelessWidget {
  const _StatusTag(
    this.text, {
    required this.background,
    required this.color,
  });

  final String text;
  final Color background;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      );
}

class _PaperLinks extends StatelessWidget {
  const _PaperLinks();

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: SizedBox(
          height: 10,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 26),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: const [_PaperLink(), _PaperLink()],
            ),
          ),
        ),
      );
}

class _PaperLink extends StatelessWidget {
  const _PaperLink();

  @override
  Widget build(BuildContext context) => Container(
        width: 5,
        height: 10,
        decoration: BoxDecoration(
          color: const Color(0xFFE8E5D6),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: const Color(0xFFA5A58F)),
        ),
      );
}

class _HandDrawnClockIcon extends StatelessWidget {
  const _HandDrawnClockIcon();

  @override
  Widget build(BuildContext context) => const CustomPaint(
        size: Size.square(17),
        painter: _ClockIconPainter(),
      );
}

class _ClockIconPainter extends CustomPainter {
  const _ClockIconPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF586152)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.7
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width * 0.4;
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(-0.06);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset.zero,
        width: radius * 2.02,
        height: radius * 1.96,
      ),
      paint,
    );
    canvas.drawLine(Offset.zero, Offset(0, -radius * 0.55), paint);
    canvas.drawLine(
      Offset.zero,
      Offset(radius * 0.38, radius * 0.22),
      paint,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ClockIconPainter oldDelegate) => false;
}

class _HandDrawnBillIcon extends StatelessWidget {
  const _HandDrawnBillIcon();

  @override
  Widget build(BuildContext context) => const CustomPaint(
        size: Size.square(17),
        painter: _BillIconPainter(),
      );
}

class _BillIconPainter extends CustomPainter {
  const _BillIconPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF586152)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.7
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final left = size.width * 0.22;
    final right = size.width * 0.78;
    final top = size.height * 0.16;
    final bottom = size.height * 0.84;
    final path = Path()
      ..moveTo(left, top)
      ..lineTo(right, top + 0.4)
      ..lineTo(right - 0.4, bottom - 2.2)
      ..lineTo((left + right) / 2, bottom)
      ..lineTo(left + 0.4, bottom - 2.2)
      ..close();
    canvas.drawPath(path, paint);
    canvas.drawLine(
      Offset(left + 2.6, size.height * 0.36),
      Offset(right - 2.6, size.height * 0.36),
      paint,
    );
    canvas.drawLine(
      Offset(left + 2.6, size.height * 0.52),
      Offset(right - 2.6, size.height * 0.52),
      paint,
    );
    canvas.drawLine(
      Offset(left + 2.6, size.height * 0.68),
      Offset((left + right) / 2, size.height * 0.68),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _BillIconPainter oldDelegate) => false;
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

class _PatButton extends StatelessWidget {
  const _PatButton({
    required this.controller,
    required this.onRequestPat,
  });

  final SceneInteractionController controller;
  final VoidCallback onRequestPat;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final presentation = controller.presentation;
        final canPat = presentation.canPat;
        final (label, enabled) = _patButtonState(presentation);
        return Semantics(
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
    final fund = snapshot.fundDaily;
    final gold = snapshot.goldDaily;
    final fundPositions = snapshot.assets.positions
        .where((position) => position.kind == InstrumentKind.fund)
        .toList();
    final knownFundCount =
        fundPositions.where((position) => position.dailyPnl != null).length;
    final anyKnownFund = knownFundCount > 0;
    final fundIncomplete = fund == null && fundPositions.isNotEmpty;
    final fundValue = fundIncomplete
        ? (anyKnownFund ? snapshot.assets.knownFundDaily : null)
        : fund;
    final fundDates = fundPositions
        .map((position) => position.fundNav?.navDate)
        .whereType<LocalDate>()
        .map((date) => date.toIsoString())
        .toSet()
        .toList()
      ..sort();
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
                  '${snapshot.quoteQuality == QuoteQuality.fixture ? '模拟报价' : (snapshot.quotesAsOf == null ? '报价时间待更新' : '报价截至 $quotesAsOf')}',
        ),
        _EntryRow(
          label: fundIncomplete && anyKnownFund
              ? '基金 · 已知小计（不完整）'
              : '基金 · 今日浮动',
          value: formatMoney(fundValue, signed: true),
          color: (fundValue?.isNegative ?? false)
              ? palette.negative
              : palette.positive,
          note: fundPositions.isEmpty
              ? '没有基金持仓'
              : fundIncomplete
                  ? '$knownFundCount/${fundPositions.length} 只基金已知 · '
                      '${fundDates.isEmpty ? '净值待更新' : '净值日期 ${fundDates.join('、')}'}'
                  : '${fundPositions.length} 只基金 · '
                      '${fundDates.isEmpty ? '净值待更新' : '净值日期 ${fundDates.join('、')}'}',
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
            '基金 ${_precision(snapshot.fundDaily)}，黄金 ${_precision(snapshot.goldDaily)}，'
            '住房 ${_precision(snapshot.housing)}，车贷 ${_precision(snapshot.car)}。'
            '分项显示取整后合计使用完整精度；基金含已知小计，缺一只时整体标不完整。',
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
            '统计时区 ${snapshot.timezone} · '
            '${snapshot.quotesAsOf == null ? '报价时间待更新（基金只有净值日期）' : '报价截至 ${formatClock(snapshot.quotesAsOf, calendar)}'} · '
            '交易基准 ${snapshot.assets.positions.isEmpty ? '无持仓' : '按来源交易日'}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 4),
          Text(
            '基金使用已公布单位净值，不是盘中估值；净值日期早于今天时，'
            '今日浮动只在已确认休市时为 0，否则等待今天的净值。',
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
