/// JSON encoding for the weekly template and day overrides.
library;

import 'dart:convert';

import 'package:finance_core/finance_core.dart';

abstract final class ScheduleCodec {
  static Map<String, dynamic> encodeWeek(WeekTemplate week) => {
        'mondayFirst': [
          for (final shifts in week.byWeekday)
            [
              for (final shift in shifts)
                {
                  'start': shift.startMinute,
                  'end': shift.endMinute,
                  'breaks': [
                    for (final pause in shift.breaks)
                      {'start': pause.startMinute, 'end': pause.endMinute},
                  ],
                },
            ],
        ],
      };

  static WeekTemplate decodeWeek(Map<String, dynamic> json) {
    final days = json['mondayFirst'];
    if (days is! List || days.length != 7) {
      throw const FormatException('week template needs 7 days');
    }
    return WeekTemplate([
      for (final day in days)
        if (day is List)
          [
            for (final shift in day)
              if (shift is Map)
                ShiftTemplate(
                  startMinute: shift['start'] as int,
                  endMinute: shift['end'] as int,
                  breaks: [
                    for (final pause in (shift['breaks'] as List? ?? const []))
                      if (pause is Map)
                        BreakTemplate(
                          startMinute: pause['start'] as int,
                          endMinute: pause['end'] as int,
                        ),
                  ],
                ),
          ]
        else
          const <ShiftTemplate>[],
    ]);
  }

  static String encodeOverrides(List<LocalInterval> intervals) => jsonEncode([
        for (final interval in intervals)
          {'start': interval.startMinute, 'end': interval.endMinute},
      ]);

  static List<LocalInterval> decodeOverrides(String encoded) {
    if (encoded.isEmpty) return const <LocalInterval>[];
    final raw = jsonDecode(encoded);
    if (raw is! List) return const <LocalInterval>[];
    return [
      for (final item in raw)
        if (item is Map)
          LocalInterval(
            startMinute: item['start'] as int,
            endMinute: item['end'] as int,
          ),
    ];
  }
}
