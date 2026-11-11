import 'package:flutter/material.dart';
import 'package:fjob_ui/fjob_ui.dart';
import 'package:ledger_model/ledger_model.dart';

const String privacyMask = '¥••••';

/// 计薪进度条的形态：主窗今日页完整版、固定窗 M 档迷你版、L/S 档不显示。
enum CardProgressMode { full, mini, none }

TextStyle _mono(double size, Color color, {FontWeight weight = FontWeight.w800}) =>
    TextStyle(
      fontFamily: 'Cascadia Mono',
      fontFamilyFallback: const ['Consolas', 'Microsoft YaHei'],
      fontSize: size,
      height: 1.08,
      fontWeight: weight,
      letterSpacing: -0.4,
      color: color,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

class StatusChip extends StatelessWidget {
  const StatusChip(this.text, {super.key, this.color, this.background});
  final String text;
  final Color? color;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: background ?? palette.yellow,
        border: Border.all(color: palette.line),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(text,
          style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.w600, color: color ?? palette.ink)),
    );
  }
}

/// Countdown card shared by the main window and the fixed card. Presentation
/// only: every label/value comes from [HomeTimeDisplay].
class TimeMetricCard extends StatelessWidget {
  const TimeMetricCard({
    super.key,
    required this.display,
    this.countdownSize = 40,
    this.dense = false,
    this.progressMode = CardProgressMode.full,
  });

  final HomeTimeDisplay display;
  final double countdownSize;
  final bool dense;
  final CardProgressMode progressMode;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Semantics(
      label: display.semanticsLabel,
      container: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const HandDrawnClockIcon(),
              const SizedBox(width: 6),
              Expanded(
                child: Text(display.label,
                    style: TextStyle(
                        fontSize: dense ? 11 : 13, fontWeight: FontWeight.w700)),
              ),
              StatusChip(display.tag,
                  color: palette.positive, background: palette.panel),
            ],
          ),
          SizedBox(height: dense ? 2 : 6),
          Text(display.mainValue, style: _mono(countdownSize, palette.ink)),
          SizedBox(height: dense ? 2 : 4),
          Text(display.detail,
              maxLines: dense ? 1 : 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: dense ? 9 : 12, color: palette.muted)),
          if (display.showProgress && progressMode != CardProgressMode.none) ...[
            SizedBox(height: progressMode == CardProgressMode.mini ? 4 : 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: display.progress,
                minHeight: progressMode == CardProgressMode.mini ? 4 : 6,
                backgroundColor: palette.line,
                valueColor: AlwaysStoppedAnimation<Color>(palette.positive),
              ),
            ),
            SizedBox(height: progressMode == CardProgressMode.mini ? 2 : 4),
            Align(
              alignment: Alignment.centerRight,
              child: Text(display.progressLabel,
                  style: TextStyle(
                      fontSize: progressMode == CardProgressMode.mini ? 9 : 10,
                      color: palette.muted)),
            ),
          ],
        ],
      ),
    );
  }
}

/// Balance card. When [privacy] is true the amount and any monetary semantics
/// are masked; status and completeness text remain.
class BalanceMetricCard extends StatelessWidget {
  const BalanceMetricCard({
    super.key,
    required this.display,
    required this.privacy,
    this.amountSize = 34,
    this.dense = false,
    this.showFlavor = true,
  });

  final HomeBalanceDisplay display;
  final bool privacy;
  final double amountSize;
  final bool dense;

  /// 固定窗里结余是次核心：M/L 档收起语气句与完整性长说明（部分状态由
  /// 状态 chip 表达），只保留报价时间一行；主窗今日页保留全部说明。
  final bool showFlavor;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final color = privacy
        ? palette.muted
        : display.neutral
            ? palette.ink
            : display.negative
                ? palette.negative
                : palette.positive;
    final amount = privacy ? privacyMask : display.amountText;
    final semantics = privacy ? '今日生存结余 金额隐身' : display.semanticsLabel;
    return Semantics(
      label: semantics,
      container: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const HandDrawnBillIcon(),
              const SizedBox(width: 6),
              Expanded(
                child: Text('今日生存结余',
                    style: TextStyle(
                        fontSize: dense ? 10 : 13, fontWeight: FontWeight.w700)),
              ),
              StatusChip(privacy ? '金额隐身' : display.tag),
            ],
          ),
          SizedBox(height: dense ? 2 : 6),
          Text(amount, style: _mono(privacy ? amountSize - 6 : amountSize, color)),
          if (!dense && showFlavor) ...[
            const SizedBox(height: 4),
            Text(privacy ? '金额已隐身 · 可在桌面页恢复' : display.flavorLine,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: palette.muted)),
          ],
          if (!dense) ...[
            if (display.completenessNote != null && showFlavor) ...[
              const SizedBox(height: 4),
              Text(display.completenessNote!,
                  style: TextStyle(fontSize: 11, color: palette.muted)),
            ],
            if (display.sourceNote != null) ...[
              const SizedBox(height: 2),
              Text(display.sourceNote!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: palette.muted)),
            ],
          ],
        ],
      ),
    );
  }
}