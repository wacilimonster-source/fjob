// Dumps sample widget timelines to build/contracts/ so the Python contract
// check can validate them against contracts/widget-snapshot.schema.json.
//
//   flutter test tool/dump_widget_timeline_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:finance_core/finance_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todayagain/data/widget_snapshot.dart';
import 'package:ledger_model/ledger_model.dart';

void main() {
  test('dump widget payloads', () {
    final calendar = BusinessCalendar.shanghai;
    final now = DateTime.utc(2026, 11, 4, 6, 36);
    final ledger = buildDemoLedger(calendar, now);
    final calculator = DashboardCalculator(calendar);
    final directory = Directory('build/contracts')..createSync(recursive: true);

    void write(String name, Map<String, dynamic> payload) {
      File('${directory.path}/$name').writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(payload),
      );
    }

    write(
      'widget-timeline.json',
      WidgetSnapshotBuilder.timeline(
        ledger: ledger,
        calendar: calendar,
        calculator: calculator,
        nowUtc: now,
        privacy: false,
        tone: AppTone.gentle,
        stepMinutes: 30,
        horizonHours: 2,
      ),
    );
    write(
      'widget-timeline-private.json',
      WidgetSnapshotBuilder.timeline(
        ledger: ledger,
        calendar: calendar,
        calculator: calculator,
        nowUtc: now,
        privacy: true,
        tone: AppTone.harsh,
        stepMinutes: 60,
        horizonHours: 1,
      ),
    );
    write(
      'widget-tombstone.json',
      WidgetSnapshotBuilder.tombstone(
        ledgerRevision: 9,
        nowUtc: now,
        timezone: calendar.timezoneName,
      ),
    );
  });
}
