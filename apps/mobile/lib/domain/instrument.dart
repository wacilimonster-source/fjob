/// Instrument identities: A-share codes, fund codes and fund eligibility.
library;

import 'package:finance_core/finance_core.dart';

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

/// A fund directory hit: name plus the evidence for whether this product may
/// be valued as an ordinary open-ended CNY fund.
final class FundInfo {
  const FundInfo({
    required this.code,
    required this.name,
    required this.eligibility,
    this.reason = '',
  });

  final String code;
  final String name;
  final FundEligibility eligibility;

  /// Machine-readable-ish reason shown to the user for unsupported/unknown.
  final String reason;

  String get instrumentId => fundInstrumentIdFor(code);

  bool get supported => eligibility == FundEligibility.supported;
}

/// Classifies a fund from the public directory's type/name fields.
///
/// The directory type cannot distinguish an on-exchange ETF from a feeder by
/// itself (both can read `指数型-股票`), so ambiguous products stay `unknown`
/// rather than being presented as supported.
FundInfo classifyFund({
  required String code,
  required String name,
  required String type,
}) {
  final text = name.trim();
  final kind = type.trim();
  if (kind.contains('货币') || kind.contains('理财')) {
    return FundInfo(
      code: code,
      name: text,
      eligibility: FundEligibility.unsupported,
      reason: '货币/理财基金不使用单位净值',
    );
  }
  if (text.contains('美元') || text.contains('现钞') || text.contains('现汇')) {
    return FundInfo(
      code: code,
      name: text,
      eligibility: FundEligibility.unsupported,
      reason: '外币计价份额暂不支持',
    );
  }
  if (kind.contains('QDII') || text.contains('QDII')) {
    return FundInfo(
      code: code,
      name: text,
      eligibility: FundEligibility.unknown,
      reason: 'QDII 的净值日期与币种待确认',
    );
  }
  final isFeeder = text.contains('联接');
  final looksOnExchange = text.contains('ETF') && !isFeeder;
  if (looksOnExchange || (code.startsWith('5') && !isFeeder)) {
    return FundInfo(
      code: code,
      name: text,
      eligibility: FundEligibility.unknown,
      reason: '无法确认场外持有口径（可能是场内 ETF/LOF）',
    );
  }
  // The live directory uses compound labels such as `混合型-灵活`,
  // `债券型-混合二级` and `指数型-股票`; match the asset-class prefix.
  const supportedPrefixes = ['股票型', '混合型', '债券型', '指数型'];
  if (supportedPrefixes.any(kind.startsWith)) {
    return FundInfo(
      code: code,
      name: text,
      eligibility: FundEligibility.supported,
    );
  }
  return FundInfo(
    code: code,
    name: text,
    eligibility: FundEligibility.unknown,
    reason: '基金类型待确认',
  );
}
