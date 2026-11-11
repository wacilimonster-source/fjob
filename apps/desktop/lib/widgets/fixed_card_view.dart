import 'package:finance_core/finance_core.dart';
import 'package:flutter/material.dart';
import 'package:fjob_ui/fjob_ui.dart';
import 'package:ledger_model/ledger_model.dart';

import 'metric_cards.dart';

enum CardDensity { s, m, l }

CardDensity densityFromName(String name) => switch (name) {
      's' => CardDensity.s,
      'l' => CardDensity.l,
      _ => CardDensity.m,
    };

Size cardSize(CardDensity density) => switch (density) {
      CardDensity.s => const Size(220, 76),
      CardDensity.m => const Size(320, 220),
      CardDensity.l => const Size(420, 390),
    };

/// The ambient card surface. Pure presentation: amounts and time come from one
/// [DashboardSnapshot] via the shared display model; the compact scene reuses the
/// shared painter. Used by the card engine and the configuration live preview.
class FixedCardView extends StatelessWidget {
  const FixedCardView({
    super.key,
    required this.snapshot,
    required this.calendar,
    required this.tone,
    required this.privacy,
    this.density = CardDensity.m,
    this.metricsMode = 'both',
    this.reduceMotion = false,
    this.showHousing = true,
    this.showCar = true,
    this.housingLabel = '房贷',
    this.carLabel = '车贷',
  });

  final DashboardSnapshot snapshot;
  final BusinessCalendar calendar;
  final AppTone tone;
  final bool privacy;
  final CardDensity density;
  final String metricsMode;
  final bool reduceMotion;
  final bool showHousing;
  final bool showCar;
  final String housingLabel;
  final String carLabel;

  bool get _showTime => metricsMode != 'balance';
  bool get _showBalance => metricsMode != 'time';

  ScenePresentation get _presentation {
    final presence = snapshot.phase == DayPhase.working ||
            snapshot.phase == DayPhase.breakTime
        ? Presence.atDesk
        : Presence.emptyDesk;
    return ScenePresentation(
      phase: snapshot.phase,
      presence: presence,
      mood: sceneMoodOf(snapshot.completeness, snapshot.total),
      transient: TransientKind.idle,
      progress: 0,
      canPat: false,
      reduceMotion: reduceMotion,
      ambientMs: 0,
      animateAmbient: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final time = buildHomeTimeDisplay(snapshot: snapshot, calendar: calendar);
    final balance =
        buildHomeBalanceDisplay(snapshot: snapshot, calendar: calendar, tone: tone);
    final size = cardSize(density);

    final Widget content = switch (density) {
      CardDensity.s => _small(time, balance),
      CardDensity.m => _medium(time, balance),
      CardDensity.l => _large(time, balance, palette),
    };

    return SizedBox(
      width: size.width,
      height: size.height,
      child: Container(
        decoration: BoxDecoration(
          color: palette.panel,
          border: Border.all(color: palette.ink, width: 1.5),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(18),
            bottomLeft: Radius.circular(17),
            bottomRight: Radius.circular(14),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: content,
      ),
    );
  }

  Widget _small(HomeTimeDisplay time, HomeBalanceDisplay balance) {
    final palette = _palette;
    return ClipRect(
      child: OverflowBox(
        maxWidth: 220,
        maxHeight: 76,
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_showTime)
                Row(
                  children: [
                    Expanded(
                      child: Text(time.mainValue,
                          style: TextStyle(
                              fontFamily: 'Cascadia Mono',
                              fontSize: 21,
                              height: 1.1,
                              fontWeight: FontWeight.w800,
                              color: palette.ink)),
                    ),
                    Text(time.tag, style: TextStyle(fontSize: 10, color: palette.muted)),
                  ],
                ),
              if (_showBalance)
                Row(
                  children: [
                    Expanded(
                      child: Text(privacy ? privacyMask : balance.amountText,
                          style: TextStyle(
                              fontFamily: 'Cascadia Mono',
                              fontSize: 18,
                              height: 1.1,
                              fontWeight: FontWeight.w800,
                              color: privacy
                                  ? palette.muted
                                  : balance.neutral
                                      ? palette.ink
                                      : balance.negative
                                          ? palette.negative
                                          : palette.positive)),
                    ),
                    Text(privacy ? '金额隐身' : balance.tag,
                        style: TextStyle(fontSize: 10, color: palette.muted)),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _medium(HomeTimeDisplay time, HomeBalanceDisplay balance) {
    final palette = _palette;
    return SingleChildScrollView(
      physics: const ClampingScrollPhysics(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_showTime)
            Container(
              width: double.infinity,
              color: palette.yellow,
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
              child: TimeMetricCard(
                  display: time,
                  countdownSize: 40,
                  dense: true,
                  progressMode: CardProgressMode.mini),
            ),
          if (_showBalance)
            Container(
              width: double.infinity,
              color: palette.panel,
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 8),
              child: BalanceMetricCard(
                  display: balance,
                  privacy: privacy,
                  amountSize: 34,
                  showFlavor: false),
            ),
        ],
      ),
    );
  }

  Widget _large(HomeTimeDisplay time, HomeBalanceDisplay balance, FjobPalette palette) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_showTime)
            TimeMetricCard(
                display: time,
                countdownSize: 40,
                progressMode: CardProgressMode.none),
          if (_showTime && _showBalance) const Divider(height: 16),
          if (_showBalance)
            BalanceMetricCard(
                display: balance,
                privacy: privacy,
                amountSize: 34,
                showFlavor: false),
          const SizedBox(height: 8),
          CompactOfficeScene(
            presentation: _presentation,
            showHousing: showHousing,
            showCar: showCar,
            housingLabel: housingLabel,
            carLabel: carLabel,
          ),
          const SizedBox(height: 8),
          _breakdownRow(palette),
        ],
      ),
    );
  }

  Widget _breakdownRow(FjobPalette palette) {
    String money(Rational? value) =>
        privacy ? privacyMask : (value == null ? '待更新' : formatSigned(value));
    final investment = _knownInvestment();
    final expense = _knownExpense();
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _breakdown('工资', money(snapshot.wage), palette),
        _breakdown('投资', money(investment), palette),
        _breakdown('支出', money(expense), palette),
      ],
    );
  }

  Widget _breakdown(String label, String value, FjobPalette palette) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 10, color: palette.muted)),
          Text(value,
              style: TextStyle(
                  fontFamily: 'Cascadia Mono',
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: palette.ink)),
        ],
      );

  Rational? _knownInvestment() {
    final parts = [snapshot.stockDaily, snapshot.fundDaily, snapshot.goldDaily];
    if (parts.every((p) => p == null)) return null;
    Rational sum = Rational.zero;
    for (final p in parts) {
      if (p != null) sum = sum + p;
    }
    return sum;
  }

  Rational? _knownExpense() {
    final parts = [snapshot.housing, snapshot.car];
    if (parts.every((p) => p == null)) return null;
    Rational sum = Rational.zero;
    for (final p in parts) {
      if (p != null) sum = sum + p;
    }
    return -sum;
  }

  FjobPalette get _palette => FjobPalette.light;
}
