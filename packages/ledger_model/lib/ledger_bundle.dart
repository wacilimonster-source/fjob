/// Portable configuration only. No IO, quotes, directory cache or UI preferences.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:finance_core/finance_core.dart';

import 'domain/instrument.dart';
import 'domain/ledger.dart';
import 'domain/schedule_codec.dart';
import 'domain/setup_draft.dart';

part 'ledger_bundle_validation.dart';

/// Same identity with different content needs an explicit user decision.
final class LedgerMergeConflictException implements Exception {
  const LedgerMergeConflictException(this.collection, this.entityId);
  final String collection;
  final String entityId;
  @override
  String toString() => 'Ledger merge conflict in $collection';
}

/// Version 1 plaintext .fjob. Checksums detect corruption, not authenticity.
/// Password encryption is deliberately not provided.
///
/// Entity IDs accept existing mobile/legacy IDs. Only ledgerId must be a UUID.
/// MonthlyBill has no domain ID: its stable identity is expenseId + month.
/// Fund holdings contain identity, shares, cost and pendingQuote only. Eligibility
/// and NAV evidence belong to the local market cache, never to a portable file.
final class LedgerBundle {
  LedgerBundle._(this._encoded);

  static const format = 'fjob.ledger.bundle';
  static const formatVersion = 1;
  static const maxBytes = 16 * 1024 * 1024;
  static const maxRevision = 9007199254740991;
  final String _encoded;

  factory LedgerBundle.fromLedger(
    LedgerState ledger, {
    required String ledgerId,
    required DateTime exportedAt,
    required String appVersion,
    required String platform,
  }) {
    for (final entry in ledger.schedules.entries) {
      if (entry.key != entry.value.id) {
        throw const FormatException('schedule map identity mismatch');
      }
    }
    final body = <String, dynamic>{
      'format': format,
      'formatVersion': formatVersion,
      'exportedAt': exportedAt.toUtc().toIso8601String(),
      'ledgerId': ledgerId,
      'ledgerRevision': ledger.settings.ledgerRevision,
      'app': {'name': 'todayagain', 'version': appVersion, 'platform': platform},
      'timezone': ledger.settings.salaryTimezone,
      'salaryVersions': [
        for (final v in ledger.salaryVersions)
          {
            ..._period(v.id, v.effectiveFromUtc, v.effectiveToUtc),
            'monthlyNetCny': _money(v.monthlyNetCny),
            'scheduleVersionId': v.scheduleVersionId,
          },
      ],
      'scheduleVersions': [
        for (final v in ledger.schedules.values)
          {
            ..._period(v.id, v.effectiveFromUtc, v.effectiveToUtc),
            'timezone': v.timezone,
            'week': ScheduleCodec.encodeWeek(v.week),
            'alternation': v.alternation == null
                ? null : ScheduleCodec.encodeAlternation(v.alternation!),
            'calendarSourceVersion': v.calendarSourceVersion,
          },
      ],
      'scheduleOverrides': [
        for (final v in ledger.overrides)
          {
            'localDate': v.localDate.toIsoString(),
            'paidIntervals': [
              for (final i in v.paidIntervals)
                {'start': i.startMinute, 'end': i.endMinute},
            ],
            'reason': v.reason,
            'confirmed': v.confirmed,
          },
      ],
      'holdingVersions': [
        for (final v in ledger.holdings)
          {
            ..._period(v.id, v.effectiveFromUtc, v.effectiveToUtc),
            'instrumentId': v.instrumentId,
            'quantity': _money(v.quantity),
            'costPerUnit': _money(v.costPerUnit),
            'pendingQuote': v.pendingQuote,
          },
      ],
      'housingVersions': [
        for (final v in ledger.housingVersions)
          {..._period(v.id, v.effectiveFromUtc, v.effectiveToUtc), 'mode': v.mode.name},
      ],
      'carVersions': [
        for (final v in ledger.carVersions)
          {..._period(v.id, v.effectiveFromUtc, v.effectiveToUtc), 'enabled': v.enabled},
      ],
      'monthlyBills': [
        for (final v in ledger.bills)
          {
            'expenseId': v.expenseId,
            'kind': v.kind.name,
            'month': v.month.toIsoString(),
            'monthlyAmountCny': _money(v.monthlyAmountCny),
            'principalCny': _money(v.principalCny),
            'status': v.status.name,
            'revision': v.revision,
            'note': v.note,
          },
      ],
      'settings': {
        'onboardingCompletedAt': ledger.settings.onboardingCompletedAt?.toUtc().toIso8601String(),
      },
    };
    return _checked(body);
  }

  factory LedgerBundle.decode(String source) {
    if (source.length > maxBytes || utf8.encode(source).length > maxBytes) {
      throw const FormatException('bundle exceeds size limit');
    }
    _checkJsonShape(source);
    final raw = jsonDecode(source);
    if (raw is! Map<String, dynamic>) {
      throw const FormatException('bundle must be an object');
    }
    final body = Map<String, dynamic>.of(raw);
    final checksum = body.remove('checksum');
    if (checksum is! String || checksum != _checksum(body)) {
      throw const FormatException('bundle checksum mismatch');
    }
    return _checked(body);
  }

  static LedgerBundle _checked(Map<String, dynamic> body) {
    _validateBundle(body);
    final encoded = canonicalJson({...body, 'checksum': _checksum(body)});
    if (utf8.encode(encoded).length > maxBytes) {
      throw const FormatException('bundle exceeds size limit');
    }
    return LedgerBundle._(encoded);
  }

  String encode() => _encoded;

  /// Detached JSON; modifying this map cannot mutate the validated bundle.
  Map<String, dynamic> toJson() => jsonDecode(_encoded) as Map<String, dynamic>;
  String get ledgerId => toJson()['ledgerId'] as String;
  int get ledgerRevision => toJson()['ledgerRevision'] as int;
  DateTime get exportedAt => DateTime.parse(toJson()['exportedAt'] as String);
  String get checksum => toJson()['checksum'] as String;

  /// Fresh domain objects, with market data absent and local UI defaults.
  LedgerState get ledger => _decodeLedger(toJson());

  /// Unions non-conflicting identities, then validates the WHOLE result.
  /// Does not increment a revision; only the repository commits a new revision.
  LedgerBundle mergedWith(LedgerBundle other) {
    final a = toJson()..remove('checksum');
    final b = other.toJson();
    if (a['timezone'] != b['timezone']) {
      throw const LedgerMergeConflictException('settings', 'timezone');
    }
    for (final key in _collections) {
      String identity(Map<String, dynamic> item) => switch (key) {
        'scheduleOverrides' => item['localDate'] as String,
        'monthlyBills' => '${item['expenseId']}@${item['month']}',
        _ => item['id'] as String,
      };
      final rows = <String, Map<String, dynamic>>{};
      for (final row in [...a[key] as List, ...b[key] as List]) {
        final item = row as Map<String, dynamic>;
        final id = identity(item);
        if (rows.containsKey(id) && canonicalJson(rows[id]) != canonicalJson(item)) {
          throw LedgerMergeConflictException(key, id);
        }
        rows[id] = item;
      }
      a[key] = rows.values.toList();
    }
    // Completion is bookkeeping rather than a financial entity. Never turn a
    // configured ledger into an unconfigured one when merging an empty ledger.
    final localSettings = a['settings'] as Map<String, dynamic>;
    final incomingSettings = b['settings'] as Map<String, dynamic>;
    localSettings['onboardingCompletedAt'] ??= incomingSettings['onboardingCompletedAt'];
    if (other.ledgerRevision > ledgerRevision) {
      a['ledgerRevision'] = other.ledgerRevision;
    }
    return _checked(a);
  }

  /// Recursive lexicographic object-key ordering, UTF-8, no whitespace.
  /// Arrays retain order. Integers are restricted to the safe JSON range.
  static String canonicalJson(Object? value) {
    Object? sorted(Object? v) {
      if (v is Map) {
        final keys = v.keys.cast<String>().toList()..sort();
        return {for (final key in keys) key: sorted(v[key])};
      }
      if (v is List) return v.map(sorted).toList();
      return v;
    }
    return jsonEncode(sorted(value));
  }

  static String _checksum(Map<String, dynamic> body) =>
      'sha256:${sha256.convert(utf8.encode(canonicalJson(body)))}';
}

const _collections = [
  'salaryVersions', 'scheduleVersions', 'scheduleOverrides', 'holdingVersions',
  'housingVersions', 'carVersions', 'monthlyBills',
];

Map<String, dynamic> _period(String id, DateTime from, DateTime? to) => {
  'id': id,
  'effectiveFrom': from.toUtc().toIso8601String(),
  'effectiveTo': to?.toUtc().toIso8601String(),
};

String? _money(Rational? value) {
  if (value == null) return null;
  final text = value.toCanonicalString();
  if (Rational.parse(text) != value) {
    throw const FormatException('configuration decimal would lose precision');
  }
  return text;
}

LedgerState _decodeLedger(Map<String, dynamic> j) {
  List<Map<String, dynamic>> rows(String key) => (j[key] as List).cast<Map<String, dynamic>>();
  DateTime from(Map<String, dynamic> v) => DateTime.parse(v['effectiveFrom'] as String);
  DateTime? to(Map<String, dynamic> v) => v['effectiveTo'] == null ? null : DateTime.parse(v['effectiveTo'] as String);
  Rational? money(Object? v) => v == null ? null : Rational.parse(v as String);
  return LedgerState.empty().copyWith(
    settings: AppSettings(
      ledgerRevision: j['ledgerRevision'] as int,
      salaryTimezone: j['timezone'] as String,
      onboardingCompletedAt: (j['settings'] as Map)['onboardingCompletedAt'] == null
          ? null : DateTime.parse((j['settings'] as Map)['onboardingCompletedAt'] as String),
    ),
    salaryVersions: [for (final v in rows('salaryVersions')) SalaryVersion(
      id: v['id'] as String, monthlyNetCny: money(v['monthlyNetCny'])!,
      effectiveFromUtc: from(v), effectiveToUtc: to(v),
      scheduleVersionId: v['scheduleVersionId'] as String,
    )],
    schedules: {for (final v in rows('scheduleVersions')) v['id'] as String: ScheduleVersion(
      id: v['id'] as String, timezone: v['timezone'] as String,
      week: ScheduleCodec.decodeWeek(v['week'] as Map<String, dynamic>),
      alternation: v['alternation'] == null ? null : ScheduleCodec.decodeAlternation(v['alternation'] as Map<String, dynamic>),
      effectiveFromUtc: from(v), effectiveToUtc: to(v),
      calendarSourceVersion: v['calendarSourceVersion'] as String,
    )},
    overrides: [for (final v in rows('scheduleOverrides')) ScheduleOverride(
      localDate: LocalDate.parse(v['localDate'] as String),
      paidIntervals: ScheduleCodec.decodeOverrides(jsonEncode(v['paidIntervals'])),
      reason: v['reason'] as String, confirmed: v['confirmed'] as bool,
    )],
    holdings: [for (final v in rows('holdingVersions')) Holding(
      id: v['id'] as String, instrumentId: v['instrumentId'] as String,
      quantity: money(v['quantity'])!, costPerUnit: money(v['costPerUnit'])!,
      effectiveFromUtc: from(v), effectiveToUtc: to(v), pendingQuote: v['pendingQuote'] as bool,
    )],
    housingVersions: [for (final v in rows('housingVersions')) HousingVersion(
      id: v['id'] as String, mode: HousingMode.values.byName(v['mode'] as String),
      effectiveFromUtc: from(v), effectiveToUtc: to(v),
    )],
    carVersions: [for (final v in rows('carVersions')) CarVersion(
      id: v['id'] as String, enabled: v['enabled'] as bool,
      effectiveFromUtc: from(v), effectiveToUtc: to(v),
    )],
    bills: [for (final v in rows('monthlyBills')) MonthlyBill(
      expenseId: v['expenseId'] as String, kind: ExpenseKind.values.byName(v['kind'] as String),
      month: LocalDate.parse(v['month'] as String), monthlyAmountCny: money(v['monthlyAmountCny']),
      principalCny: money(v['principalCny']), status: BillStatus.values.byName(v['status'] as String),
      revision: v['revision'] as int, note: v['note'] as String?,
    )],
  );
}
