/// A-share instrument identity and code-prefix market inference.
library;

import 'setup_draft.dart';

final class InstrumentInfo {
  const InstrumentInfo({
    required this.instrumentId,
    required this.code,
    required this.name,
    required this.market,
    this.supported = true,
  });

  final String instrumentId;
  final String code;
  final String name;
  final StockMarket market;
  final bool supported;

  String get marketLabel => market.label;
}

/// Infers the exchange from a six-digit A-share code.
///
/// This is a routing heuristic only: 6xxxxx is Shanghai, 0/3xxxxx Shenzhen,
/// 4/8/92xxxx Beijing. The market gateway remains the authority when it is
/// configured; B shares and non-A-share codes return null.
StockMarket? marketForCode(String code) {
  if (!RegExp(r'^\d{6}$').hasMatch(code)) return null;
  if (code.startsWith('6')) return StockMarket.sse;
  if (code.startsWith('0') || code.startsWith('3')) return StockMarket.szse;
  if (code.startsWith('4') || code.startsWith('8')) return StockMarket.bse;
  if (code.startsWith('92')) return StockMarket.bse;
  return null;
}

String instrumentIdFor(String code, StockMarket market) =>
    '${market.prefix}.$code';
