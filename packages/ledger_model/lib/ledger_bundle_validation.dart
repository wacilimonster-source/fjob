part of 'ledger_bundle.dart';

Never _invalid(String path) => throw FormatException('invalid bundle: $path');

/// jsonDecode normally keeps the last duplicate key. Reject ambiguity before
/// decoding/checksumming, including equivalent escaped keys, and cap nesting.
void _checkJsonShape(String source) {
  final stack = <Set<String>?>[];
  for (var i = 0; i < source.length; i++) {
    final char = source.codeUnitAt(i);
    if (char == 123 || char == 91) {
      stack.add(char == 123 ? <String>{} : null);
      if (stack.length > 32) _invalid('JSON nesting');
    } else if (char == 125 || char == 93) {
      if (stack.isEmpty) _invalid('JSON structure');
      stack.removeLast();
    } else if (char == 34) {
      final start = i++;
      while (i < source.length && source.codeUnitAt(i) != 34) {
        if (source.codeUnitAt(i) == 92) i++;
        i++;
      }
      if (i >= source.length) _invalid('JSON string');
      var next = i + 1;
      while (next < source.length && const [32, 9, 10, 13].contains(source.codeUnitAt(next))) {
        next++;
      }
      if (next < source.length && source.codeUnitAt(next) == 58 && stack.isNotEmpty && stack.last != null) {
        final key = jsonDecode(source.substring(start, i + 1)) as String;
        if (!stack.last!.add(key)) _invalid('duplicate JSON key');
      }
    }
  }
}

Map<String, dynamic> _object(Object? value, List<String> keys, String path) {
  if (value is! Map<String, dynamic> || value.length != keys.length ||
      !keys.every(value.containsKey)) _invalid(path);
  return value;
}

String _text(Object? value, String path, {int max = 200, bool empty = false}) {
  if (value is! String || value.length > max || (!empty && value.trim().isEmpty) ||
      value.contains(RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f]'))) _invalid(path);
  return value;
}

String _id(Object? value, String path) {
  final id = _text(value, path);
  if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]*$').hasMatch(id)) _invalid(path);
  return id;
}

int _integer(Object? value, String path, {int min = 0, int max = LedgerBundle.maxRevision}) {
  if (value is! int || value < min || value > max) _invalid(path);
  return value;
}

void _boolean(Object? value, String path) {
  if (value is! bool) _invalid(path);
}

void _enum(Object? value, Iterable<String> names, String path) {
  if (value is! String || !names.contains(value)) _invalid(path);
}

LocalDate _date(Object? value, String path) {
  if (value is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) _invalid(path);
  final parsed = LocalDate.tryParse(value);
  if (parsed == null || parsed.year < 1 || parsed.toIsoString() != value) _invalid(path);
  return parsed;
}

DateTime _utc(Object? value, String path) {
  if (value is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,6})?Z$').hasMatch(value)) _invalid(path);
  _date(value.substring(0, 10), path);
  final parsed = DateTime.tryParse(value);
  if (parsed == null || parsed.hour != int.parse(value.substring(11, 13)) ||
      parsed.minute != int.parse(value.substring(14, 16)) ||
      parsed.second != int.parse(value.substring(17, 19))) _invalid(path);
  return parsed;
}

Rational? _decimalValue(Object? value, String path, {required int scale, required String max, bool nullable = false}) {
  if (nullable && value == null) return null;
  if (value is! String || value.length > 32 ||
      !RegExp(r'^(0|[1-9]\d*)(\.\d*[1-9])?$').hasMatch(value)) _invalid(path);
  final dot = value.indexOf('.');
  if (dot >= 0 && value.length - dot - 1 > scale) _invalid(path);
  final amount = Rational.parse(value);
  if (amount > Rational.parse(max)) _invalid(path);
  return amount;
}

const _periodKeys = ['id', 'effectiveFrom', 'effectiveTo'];

void _validateBundle(Map<String, dynamic> j) {
  try {
    _object(j, ['format', 'formatVersion', 'exportedAt', 'ledgerId', 'ledgerRevision',
      'app', 'timezone', ..._collections, 'settings'], 'root fields');
    if (j['format'] != LedgerBundle.format || j['formatVersion'] is! int ||
        j['formatVersion'] != LedgerBundle.formatVersion) _invalid('format version');
    _utc(j['exportedAt'], 'exportedAt');
    final ledgerId = _text(j['ledgerId'], 'ledgerId');
    if (!RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$').hasMatch(ledgerId)) _invalid('ledgerId');
    _integer(j['ledgerRevision'], 'ledgerRevision');
    final app = _object(j['app'], ['name', 'version', 'platform'], 'app');
    if (app['name'] != 'todayagain') _invalid('app.name');
    _text(app['version'], 'app.version', max: 80);
    _enum(app['platform'], ['android', 'windows'], 'app.platform');
    final timezone = _text(j['timezone'], 'timezone');
    BusinessCalendar.forZone(timezone);
    final settings = _object(j['settings'], ['onboardingCompletedAt'], 'settings');
    if (settings['onboardingCompletedAt'] != null) _utc(settings['onboardingCompletedAt'], 'onboardingCompletedAt');

    final lists = <String, List<Map<String, dynamic>>>{};
    for (final key in _collections) {
      final raw = j[key];
      if (raw is! List || raw.length > 10000) _invalid(key);
      final entries = <Map<String, dynamic>>[];
      final ids = <String>{};
      for (final item in raw) {
        if (item is! Map<String, dynamic>) _invalid(key);
        entries.add(item);
        if (key != 'scheduleOverrides' && key != 'monthlyBills') {
          final id = _id(item['id'], '$key.id');
          if (!ids.add(id)) _invalid('$key duplicate id');
          final from = _utc(item['effectiveFrom'], '$key.effectiveFrom');
          final to = item['effectiveTo'] == null ? null : _utc(item['effectiveTo'], '$key.effectiveTo');
          if (to != null && !to.isAfter(from)) _invalid('$key empty period');
        }
      }
      lists[key] = entries;
    }

    final schedules = lists['scheduleVersions']!;
    for (final v in schedules) {
      _object(v, [..._periodKeys, 'timezone', 'week', 'alternation', 'calendarSourceVersion'], 'schedule');
      if (v['timezone'] != timezone) _invalid('schedule timezone mismatch');
      _text(v['calendarSourceVersion'], 'calendarSourceVersion');
      _week(v['week']);
      if (v['alternation'] != null) {
        final a = _object(v['alternation'], ['small', 'big', 'anchorMonday'], 'alternation');
        _week(a['small']);
        _week(a['big']);
        if (!_date(a['anchorMonday'], 'anchorMonday').isMonday) _invalid('anchorMonday');
        if (LedgerBundle.canonicalJson(v['week']) != LedgerBundle.canonicalJson(a['small'])) _invalid('alternation small week mismatch');
      }
    }
    final scheduleMap = {for (final v in schedules) v['id']: v};
    for (final v in lists['salaryVersions']!) {
      _object(v, [..._periodKeys, 'monthlyNetCny', 'scheduleVersionId'], 'salary');
      _decimalValue(v['monthlyNetCny'], 'monthlyNetCny', scale: 2, max: '10000000');
      _id(v['scheduleVersionId'], 'scheduleVersionId');
      final schedule = scheduleMap[v['scheduleVersionId']];
      if (schedule == null) _invalid('salary schedule reference');
      final from = _utc(v['effectiveFrom'], 'salary');
      final sf = _utc(schedule['effectiveFrom'], 'schedule');
      final st = schedule['effectiveTo'];
      if (from.isBefore(sf) || (st != null && (v['effectiveTo'] == null ||
          _utc(v['effectiveTo'], 'salary').isAfter(_utc(st, 'schedule'))))) _invalid('salary outside schedule period');
    }
    final dates = <LocalDate>{};
    for (final v in lists['scheduleOverrides']!) {
      _object(v, ['localDate', 'paidIntervals', 'reason', 'confirmed'], 'override');
      if (!dates.add(_date(v['localDate'], 'localDate'))) _invalid('duplicate override date');
      final raw = v['paidIntervals'];
      if (raw is! List || raw.length > 100) _invalid('paidIntervals');
      final intervals = <LocalInterval>[];
      for (final interval in raw) {
        final i = _object(interval, ['start', 'end'], 'paidInterval');
        final start = _integer(i['start'], 'start', max: 1439);
        final end = _integer(i['end'], 'end', min: start + 1, max: start + 1440);
        intervals.add(LocalInterval(startMinute: start, endMinute: end));
      }
      _noMinuteOverlap(intervals);
      _text(v['reason'], 'reason', max: 2000, empty: true);
      _boolean(v['confirmed'], 'confirmed');
    }
    for (final v in lists['holdingVersions']!) {
      _object(v, [..._periodKeys, 'instrumentId', 'quantity', 'costPerUnit', 'pendingQuote'], 'holding');
      final id = _text(v['instrumentId'], 'instrumentId');
      final isGold = id == goldInstrumentId;
      final isFund = RegExp(r'^FUND\.CN\.\d{6}$').hasMatch(id);
      if (!isGold && !isFund) {
        final parts = id.split('.');
        if (parts.length != 3 || marketForCode(parts.last)?.prefix != '${parts[0]}.${parts[1]}') _invalid('stock identity');
      }
      _decimalValue(v['quantity'], 'quantity', scale: isFund ? 4 : isGold ? 3 : 0,
        max: isFund ? '10000000' : isGold ? '1000000' : '9007199254740991');
      _decimalValue(v['costPerUnit'], 'costPerUnit', scale: isFund ? 4 : isGold ? 2 : 3, max: '100000');
      _boolean(v['pendingQuote'], 'pendingQuote');
    }
    final housing = <Object?, Map<String, dynamic>>{};
    for (final v in lists['housingVersions']!) {
      _object(v, [..._periodKeys, 'mode'], 'housing');
      _enum(v['mode'], HousingMode.values.map((v) => v.name), 'housing.mode');
      housing[v['id']] = v;
    }
    final cars = <Object?, Map<String, dynamic>>{};
    for (final v in lists['carVersions']!) {
      _object(v, [..._periodKeys, 'enabled'], 'car');
      _boolean(v['enabled'], 'car.enabled');
      if (housing.containsKey(v['id'])) _invalid('ambiguous expense id');
      cars[v['id']] = v;
    }
    final billKeys = <String>{};
    for (final v in lists['monthlyBills']!) {
      _object(v, ['expenseId', 'kind', 'month', 'monthlyAmountCny', 'principalCny', 'status', 'revision', 'note'], 'bill');
      final id = _id(v['expenseId'], 'expenseId');
      _enum(v['kind'], ExpenseKind.values.map((v) => v.name), 'bill.kind');
      final plan = v['kind'] == 'housing' ? housing[id] : cars[id];
      if (plan == null || plan['mode'] == 'none' || plan['enabled'] == false) _invalid('bill expense reference');
      if (_date(v['month'], 'bill.month').day != 1) _invalid('bill month must start on day 1');
      if (!billKeys.add('$id@${v['month']}')) _invalid('duplicate bill');
      final amount = _decimalValue(v['monthlyAmountCny'], 'monthlyAmountCny', scale: 2, max: '10000000', nullable: true);
      final principal = _decimalValue(v['principalCny'], 'principalCny', scale: 2, max: '10000000', nullable: true);
      if (principal != null && (amount == null || principal > amount || plan['mode'] == 'rent')) _invalid('bill principal');
      _enum(v['status'], BillStatus.values.map((v) => v.name), 'bill.status');
      if (v['status'] == 'missing' && (amount != null || principal != null)) _invalid('missing bill amount');
      _integer(v['revision'], 'bill.revision', min: 1);
      if (v['note'] != null) _text(v['note'], 'bill.note', max: 4000, empty: true);
    }
    for (final key in ['salaryVersions', 'scheduleVersions', 'housingVersions', 'carVersions']) {
      _noPeriodOverlap(lists[key]!);
    }
    final holdingsByInstrument = <Object?, List<Map<String, dynamic>>>{};
    for (final v in lists['holdingVersions']!) {
      holdingsByInstrument.putIfAbsent(v['instrumentId'], () => []).add(v);
    }
    for (final list in holdingsByInstrument.values) { _noPeriodOverlap(list); }

    final ledger = _decodeLedger(j);
    _validatePaidIntervals(ledger);
  } on FormatException { rethrow; }
    on Object { _invalid('configuration'); }
}

void _week(Object? value) {
  final week = _object(value, ['mondayFirst'], 'week');
  final days = week['mondayFirst'];
  if (days is! List || days.length != 7) _invalid('week days');
  for (final day in days) {
    if (day is! List || day.length > 100) _invalid('week day');
    for (final raw in day) {
      final shift = _object(raw, ['start', 'end', 'breaks'], 'shift');
      final start = _integer(shift['start'], 'shift.start', max: 1439);
      _integer(shift['end'], 'shift.end', min: start + 1, max: start + 1440);
      final breaks = shift['breaks'];
      if (breaks is! List || breaks.length > 100) _invalid('breaks');
      for (final rawBreak in breaks) {
        final pause = _object(rawBreak, ['start', 'end'], 'break');
        final start = _integer(pause['start'], 'break.start', max: 2879);
        _integer(pause['end'], 'break.end', min: start + 1, max: 2880);
      }
    }
  }
  ScheduleCodec.decodeWeek(week).validate();
}

void _noPeriodOverlap(List<Map<String, dynamic>> rows) {
  final sorted = [...rows]..sort((a, b) => _utc(a['effectiveFrom'], 'from').compareTo(_utc(b['effectiveFrom'], 'from')));
  for (var i = 1; i < sorted.length; i++) {
    final end = sorted[i - 1]['effectiveTo'];
    if (end == null || _utc(sorted[i]['effectiveFrom'], 'from').isBefore(_utc(end, 'to'))) _invalid('overlapping effective periods');
  }
}

void _noMinuteOverlap(List<LocalInterval> intervals) {
  final sorted = [...intervals]..sort((a, b) => a.startMinute.compareTo(b.startMinute));
  for (var i = 1; i < sorted.length; i++) {
    if (sorted[i].startMinute < sorted[i - 1].endMinute) _invalid('overlapping paid intervals');
  }
}

void _validatePaidIntervals(LedgerState ledger) {
  final overrides = {for (final o in ledger.overrides) if (o.confirmed) o.localDate: o.paidIntervals};
  final epoch = LocalDate(2000, 1, 1);
  _noMinuteOverlap([
    for (final entry in overrides.entries)
      for (final interval in entry.value)
        LocalInterval(
          startMinute: entry.key.differenceInDays(epoch) * 1440 + interval.startMinute,
          endMinute: entry.key.differenceInDays(epoch) * 1440 + interval.endMinute,
        ),
  ]);
  for (final schedule in ledger.schedules.values) {
    // Two full cycles catch cross-midnight collisions at all alternating-week
    // boundaries, including Sunday -> Monday. Core WeekTemplate checks one day.
    final anchor = schedule.alternation?.anchorMonday ?? LocalDate(2026, 1, 5);
    final cycle = <LocalInterval>[];
    for (var day = 0; day < 28; day++) {
      final date = anchor.addDays(day);
      for (final interval in schedule.templateFor(date).paidIntervalsForWeekday(date.weekday)) {
        cycle.add(LocalInterval(startMinute: day * 1440 + interval.startMinute,
          endMinute: day * 1440 + interval.endMinute));
      }
    }
    _noMinuteOverlap(cycle);
    // Overrides are global (also used for full-month denominators), so check
    // them against each immutable schedule template, not only today's version.
    for (final date in overrides.keys) {
      final nearby = <LocalInterval>[];
      for (var day = -1; day <= 1; day++) {
        final d = date.addDays(day);
        final intervals = overrides[d] ?? schedule.templateFor(d).paidIntervalsForWeekday(d.weekday);
        for (final i in intervals) {
          nearby.add(LocalInterval(startMinute: day * 1440 + i.startMinute, endMinute: day * 1440 + i.endMinute));
        }
      }
      _noMinuteOverlap(nearby);
    }
  }
  // Reject a positive salary whose initial or overridden month has no paid
  // time. This invokes the shared engine, never a second pay calculation.
  final expander = ScheduleExpander(BusinessCalendar.forZone);
  for (final salary in ledger.salaryVersions) {
    if (!salary.monthlyNetCny.isPositive) continue;
    final schedule = ledger.schedules[salary.scheduleVersionId]!;
    final calendar = BusinessCalendar.forZone(schedule.timezone);
    final months = <LocalDate>{calendar.dateOf(salary.effectiveFromUtc).firstOfMonth,
      for (final date in overrides.keys) date.firstOfMonth};
    for (final month in months) {
      if (!salary.overlaps(calendar.startOfMonthUtc(month), calendar.endOfMonthUtc(month))) continue;
      if (expander.monthlyPaidSeconds(version: schedule, overrides: ledger.overrides, anchor: month) == 0) _invalid('positive salary without paid time');
    }
  }
}
