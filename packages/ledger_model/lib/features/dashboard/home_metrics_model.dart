/// HOME-DUAL-04/05/06/07: pure mapping from one dashboard snapshot to the two
/// headline cards. No widget, ledger or quote side effects live here.
library;

import 'package:finance_core/finance_core.dart';

import '../../domain/format.dart';
import '../../domain/ledger.dart';

enum HomeTimeState {
  working,
  breakTime,
  beforeShift,
  afterShift,
  restDay,
  unknown,
}

/// One rendered state of the countdown card.
final class HomeTimeDisplay {
  const HomeTimeDisplay({
    required this.state,
    required this.label,
    required this.tag,
    required this.mainValue,
    required this.detail,
    required this.showProgress,
    required this.progress,
    required this.progressLabel,
    required this.progressSemantics,
    required this.semanticsLabel,
  });

  final HomeTimeState state;

  /// 距离下班还有 / 距离上班还有 / 本班状态 / 今日排班 / 排班状态
  final String label;

  /// Small status chip next to the label.
  final String tag;

  /// Countdown or the equally prominent state word.
  final String mainValue;

  /// Expected end/start and the pay state.
  final String detail;

  final bool showProgress;

  /// 0..1, null whenever the progress is hidden or its denominator is zero.
  final double? progress;
  final String progressLabel;
  final String progressSemantics;

  /// Screen-reader sentence; never read automatically on each tick.
  final String semanticsLabel;
}

/// One rendered state of the balance card.
final class HomeBalanceDisplay {
  const HomeBalanceDisplay({
    required this.tag,
    required this.amountText,
    required this.known,
    required this.negative,
    required this.neutral,
    required this.flavorLine,
    required this.completenessNote,
    required this.sourceNote,
    required this.formula,
    required this.semanticsLabel,
  });

  final String tag;
  final String amountText;
  final bool known;
  final bool negative;

  /// Partial subtotals and unavailable values use the neutral ink color.
  final bool neutral;
  final String flavorLine;

  /// Missing-item explanation; also present for a stale cache.
  final String? completenessNote;
  final String? sourceNote;
  final String formula;
  final String semanticsLabel;
}

/// Ceil to whole seconds so the final second never shows 00:00:00 early.
int remainingCeilSeconds(DateTime targetUtc, DateTime nowUtc) {
  final micros = targetUtc.difference(nowUtc).inMicroseconds;
  if (micros <= 0) return 0;
  return (micros + Duration.microsecondsPerSecond - 1) ~/
      Duration.microsecondsPerSecond;
}

/// `HH:MM:SS` with an unbounded hour field (no modulo 24).
String formatCountdown(int totalSeconds) {
  final safe = totalSeconds < 0 ? 0 : totalSeconds;
  final hours = safe ~/ 3600;
  final minutes = (safe % 3600) ~/ 60;
  final seconds = safe % 60;
  return '${hours.toString().padLeft(2, '0')}:'
      '${minutes.toString().padLeft(2, '0')}:'
      '${seconds.toString().padLeft(2, '0')}';
}

/// Spoken countdown: `3 小时 24 分钟`; whole minutes, rounded up.
String spokenCountdown(int totalSeconds) {
  final minutes = (totalSeconds < 0 ? 0 : totalSeconds + 59) ~/ 60;
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  if (hours == 0) return '$rest 分钟';
  if (rest == 0) return '$hours 小时';
  return '$hours 小时 $rest 分钟';
}

/// `18:00` today, `次日 06:00` tomorrow, otherwise an explicit month/day.
String formatShiftMoment(
  DateTime instantUtc,
  BusinessCalendar calendar,
  LocalDate statisticsDate,
) {
  final local = calendar.localTimeOf(instantUtc);
  final date = calendar.dateOf(instantUtc);
  final clock = '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
  if (date == statisticsDate) return clock;
  if (date == statisticsDate.addDays(1)) return '次日 $clock';
  return '${date.month}月${date.day.toString().padLeft(2, '0')}日 $clock';
}

HomeTimeDisplay buildHomeTimeDisplay({
  required DashboardSnapshot snapshot,
  required BusinessCalendar calendar,
}) {
  final now = snapshot.computedAtUtc;
  final session = snapshot.workSession;
  final statisticsDate = snapshot.statisticsDate;
  final progress = _progressFor(snapshot.timeline, now);

  if (!session.scheduleValid) {
    return _unknownTime(snapshot);
  }

  switch (snapshot.phase) {
    case DayPhase.working:
    case DayPhase.breakTime:
      final active = session.activeSession;
      if (active == null) return _unknownTime(snapshot);
      final endText = formatShiftMoment(
        active.endUtc,
        calendar,
        statisticsDate,
      );
      final remaining = remainingCeilSeconds(active.endUtc, now);
      final breakTime = snapshot.phase == DayPhase.breakTime;
      return HomeTimeDisplay(
        state: breakTime ? HomeTimeState.breakTime : HomeTimeState.working,
        label: '距离下班还有',
        tag: breakTime ? '休息中' : '在岗中',
        mainValue: formatCountdown(remaining),
        detail: '预计 $endText 下班 · '
            '${breakTime ? '休息中，工资暂停' : '按排班计薪'}',
        showProgress: progress != null,
        progress: progress?.fraction,
        progressLabel: progress?.label ?? '',
        progressSemantics: progress?.semantics ?? '',
        semanticsLabel: '距离下班还有 ${spokenCountdown(remaining)}，'
            '预计 $endText 下班'
            '${breakTime ? '，休息中工资暂停' : ''}',
      );

    case DayPhase.beforeShift:
      final next = session.nextSession;
      if (next == null || !next.startUtc.isAfter(now)) {
        return _unknownTime(snapshot);
      }
      final startText = formatShiftMoment(
        next.startUtc,
        calendar,
        statisticsDate,
      );
      final endText = formatShiftMoment(next.endUtc, calendar, statisticsDate);
      final remaining = remainingCeilSeconds(next.startUtc, now);
      return HomeTimeDisplay(
        state: HomeTimeState.beforeShift,
        label: '距离上班还有',
        tag: '未开始',
        mainValue: formatCountdown(remaining),
        detail: '$startText 上班 · 预计 $endText 下班',
        showProgress: progress != null,
        progress: progress?.fraction,
        progressLabel: progress?.label ?? '',
        progressSemantics: progress?.semantics ?? '',
        semanticsLabel: '距离上班还有 ${spokenCountdown(remaining)}，'
            '$startText 上班，预计 $endText 下班',
      );

    case DayPhase.afterShift:
      final ended = session.lastEndedSession;
      final end = ended?.endUtc ?? snapshot.timeline?.shiftEndUtc;
      final endText =
          end == null ? '本班已结束' : '${formatShiftMoment(end, calendar, statisticsDate)} 已下班';
      final next = session.nextSession;
      final nextText = next == null
          ? ''
          : ' · 下一班 ${formatShiftMoment(next.startUtc, calendar, statisticsDate)}';
      return HomeTimeDisplay(
        state: HomeTimeState.afterShift,
        label: '本班状态',
        tag: '已结束',
        mainValue: '已下班',
        detail: '$endText · 固定支出继续分摊$nextText',
        showProgress: progress != null,
        progress: progress?.fraction,
        progressLabel: progress?.label ?? '',
        progressSemantics: progress?.semantics ?? '',
        semanticsLabel: '$endText，固定支出继续分摊$nextText',
      );

    case DayPhase.restDay:
      final next = session.nextSession;
      final nextText = next == null
          ? ''
          : ' · 下一班 ${formatShiftMoment(next.startUtc, calendar, statisticsDate)}';
      return HomeTimeDisplay(
        state: HomeTimeState.restDay,
        label: '今日排班',
        tag: '休息日',
        mainValue: '今日休息',
        detail: '今天没有排班，好好休息$nextText',
        showProgress: false,
        progress: null,
        progressLabel: '',
        progressSemantics: '',
        semanticsLabel: '今日休息，今天没有排班$nextText',
      );

    case DayPhase.unknown:
      return _unknownTime(snapshot);
  }
}

HomeBalanceDisplay buildHomeBalanceDisplay({
  required DashboardSnapshot snapshot,
  required BusinessCalendar calendar,
  required AppTone tone,
}) {
  final total = snapshot.total;
  final known = total != null;
  final unavailable = snapshot.completeness == Completeness.unavailable;
  final partial = snapshot.completeness == Completeness.partial;
  final positive = total != null && !total.isNegative;

  final tag = unavailable
      ? '不可计算'
      : partial
          ? '部分小计'
          : positive
              ? '暂时领先'
              : '努力回本';

  final amountText =
      unavailable ? '待配置' : _metricMoney(total, placeholder: '待配置');

  final missing = <String>[
    if (snapshot.stockDaily == null) 'A股今日浮动',
    if (snapshot.fundDaily == null) '基金今日浮动',
    if (snapshot.goldDaily == null) '黄金今日浮动',
    if (snapshot.housing == null) '住房账单',
    if (snapshot.car == null) '车贷账单',
  ];

  final String? completenessNote;
  if (unavailable) {
    completenessNote = '核心配置缺失或无效，请在设置中补齐工资与排班。';
  } else if (partial) {
    completenessNote = missing.isEmpty
        ? '部分数据待更新，当前仅显示已知小计，不代表最终盈亏。'
        : '缺少：${missing.join('、')}。当前仅显示已知小计，不代表最终盈亏。';
  } else {
    completenessNote = null;
  }

  final String? sourceNote;
  if (snapshot.quoteQuality == QuoteQuality.stale) {
    sourceNote = '缓存/陈旧 · 报价截至 '
        '${formatClock(snapshot.quotesAsOf, calendar)}';
  } else if (snapshot.quoteQuality == QuoteQuality.fixture) {
    sourceNote = '模拟报价 · 报价截至 '
        '${formatClock(snapshot.quotesAsOf, calendar)}';
  } else {
    sourceNote = null;
  }

  final flavor = _flavorLine(snapshot: snapshot, tone: tone, positive: positive);
  final semantics = unavailable
      ? '今日生存结余 待配置，不可计算。$completenessNote'
      : '今日生存结余 $amountText，$tag。'
          '${partial ? completenessNote ?? '' : ''}'
          '${sourceNote == null ? '' : '$sourceNote。'}';

  return HomeBalanceDisplay(
    tag: tag,
    amountText: amountText,
    known: known,
    negative: total != null && total.isNegative && !unavailable && !partial,
    neutral: unavailable || partial || total == null,
    flavorLine: flavor,
    completenessNote: completenessNote,
    sourceNote: sourceNote,
    formula: '工资估算 + 投资今日浮动 − 固定支出已分摊',
    semanticsLabel: semantics,
  );
}

final class _Progress {
  const _Progress({
    required this.fraction,
    required this.label,
    required this.semantics,
  });

  final double fraction;
  final String label;
  final String semantics;
}

_Progress? _progressFor(DayTimeline? timeline, DateTime nowUtc) {
  if (timeline == null) return null;
  final total = timeline.paidSecondsTotal;
  if (total <= 0) return null;
  final elapsed = timeline.paidSecondsElapsed(nowUtc).clamp(0, total).toInt();
  final fraction = (elapsed / total).clamp(0.0, 1.0);
  // Integer math avoids 57.5% rounding down to 57 from a binary fraction.
  final percent = (elapsed * 100 / total).round();
  return _Progress(
    fraction: fraction,
    label: '今日计薪 ${formatHours(elapsed)} / ${formatHours(total)} 小时',
    semantics: '今日计薪 ${formatHours(elapsed)} / ${formatHours(total)} 小时，'
        '完成 $percent%',
  );
}

HomeTimeDisplay _unknownTime(DashboardSnapshot snapshot) {
  final invalid = snapshot.notes.contains(DashboardNote.invalidSchedule);
  final missing = snapshot.notes.contains(DashboardNote.missingSchedule);
  final detail = invalid
      ? '排班配置有误，请到设置中的工资与排班检查。'
      : missing
          ? '还没有排班，请到设置中的工资与排班补齐。'
          : '当前班次无法确认，请到设置中的工资与排班检查。';
  return HomeTimeDisplay(
    state: HomeTimeState.unknown,
    label: '排班状态',
    tag: '待确认',
    mainValue: '排班待确认',
    detail: detail,
    showProgress: false,
    progress: null,
    progressLabel: '',
    progressSemantics: '',
    semanticsLabel: '排班待确认。$detail',
  );
}

String _flavorLine({
  required DashboardSnapshot snapshot,
  required AppTone tone,
  required bool positive,
}) {
  final harsh = tone == AppTone.harsh;
  if (snapshot.completeness == Completeness.unavailable) {
    return '核心配置还没准备好，结余暂时算不出来。';
  }
  if (snapshot.completeness == Completeness.partial) {
    return '有些数据还没到，先只看已知小计。';
  }
  if (snapshot.phase == DayPhase.restDay) {
    return harsh ? '你休息了，账单觉得你想多了。' : '今天不上班，生活照常扣费。';
  }
  if (snapshot.phase == DayPhase.breakTime) {
    return '休息不涨工资，账单倒是很准时。';
  }
  if (snapshot.phase == DayPhase.afterShift) {
    return '人下班了，生活还在全勤。';
  }
  if (positive) {
    return harsh ? '难得赢一局，房贷已经在候场。' : '今天暂时领先，先小声开心一下。';
  }
  return harsh ? '辛苦一天，成功把亏损补小了一点。' : '工资正在努力追赶上午的亏损。';
}

/// The main card uses the typographic minus sign from the design examples.
String _metricMoney(Rational? value, {String placeholder = '待更新'}) {
  final text = formatMoney(value, placeholder: placeholder);
  return text.startsWith('-') ? '−${text.substring(1)}' : text;
}
