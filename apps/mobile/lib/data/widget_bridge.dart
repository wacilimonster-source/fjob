/// Platform bridge for the Android and iOS home-screen widgets.
library;

import 'dart:convert';

import 'package:finance_core/finance_core.dart';
import 'package:flutter/services.dart';

import 'package:ledger_model/ledger_model.dart';
import 'package:ledger_store/ledger_store.dart';
import 'package:market_data/market_data.dart';
import 'widget_snapshot.dart';

abstract interface class WidgetBridge {
  Future<bool> publish(String payload);

  Future<bool> clear(String payload);
}

/// Production bridge: one MethodChannel into Kotlin and Swift.
final class MethodChannelWidgetBridge implements WidgetBridge {
  const MethodChannelWidgetBridge({this.channel = const MethodChannel(AppConfig.channelName)});

  final MethodChannel channel;

  @override
  Future<bool> publish(String payload) async {
    try {
      final result = await channel.invokeMethod<bool>(
        'publishTimeline',
        {'json': payload},
      );
      return result ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<bool> clear(String payload) async {
    try {
      final result = await channel.invokeMethod<bool>('clear', {'json': payload});
      return result ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}

/// Test and desktop double that records the last payload.
final class RecordingWidgetBridge implements WidgetBridge {
  String? lastPublished;
  String? lastCleared;

  @override
  Future<bool> publish(String payload) async {
    lastPublished = payload;
    return true;
  }

  @override
  Future<bool> clear(String payload) async {
    lastCleared = payload;
    return true;
  }
}

final class WidgetPublishResult {
  const WidgetPublishResult({required this.ok, this.message});

  final bool ok;
  final String? message;
}

/// Builds a timeline, enqueues it, then pushes it to the native store.
///
/// A failed native call leaves the job in SQLite so the next foreground pass or
/// manual refresh retries it; the native side keeps the previous snapshot.
final class WidgetPublisher {
  WidgetPublisher({
    required this.ledgerRepository,
    required this.calendar,
    required this.calculator,
    required this.bridge,
    this.timelineEnabled = true,
  });

  final LedgerRepository ledgerRepository;
  final BusinessCalendar calendar;
  final DashboardCalculator calculator;
  final WidgetBridge bridge;

  /// Disabled in widget tests so a full 289-entry timeline is not built.
  final bool timelineEnabled;

  Future<WidgetPublishResult> publish({
    required LedgerState ledger,
    required DateTime nowUtc,
    required bool privacy,
    required AppTone tone,
  }) async {
    if (!ledger.isConfigured) {
      return const WidgetPublishResult(ok: false, message: '账本尚未配置');
    }
    if (!timelineEnabled) {
      return const WidgetPublishResult(ok: true);
    }
    final timeline = WidgetSnapshotBuilder.timeline(
      ledger: ledger,
      calendar: calendar,
      calculator: calculator,
      nowUtc: nowUtc,
      privacy: privacy,
      tone: tone,
    );
    return _deliver(
      ledgerRevision: ledger.settings.ledgerRevision,
      kind: 'timeline',
      payload: _encode(timeline),
      nowUtc: nowUtc,
    );
  }

  Future<WidgetPublishResult> clearWidgets({
    required int ledgerRevision,
    required DateTime nowUtc,
  }) async {
    final payload = _encode(
      WidgetSnapshotBuilder.tombstone(
        ledgerRevision: ledgerRevision,
        nowUtc: nowUtc,
        timezone: calendar.timezoneName,
      ),
    );
    return _deliver(
      ledgerRevision: ledgerRevision,
      kind: 'tombstone',
      payload: payload,
      nowUtc: nowUtc,
    );
  }

  Future<void> flushPending({required DateTime nowUtc}) async {
    final jobs = await ledgerRepository.pendingWidgetJobs();
    for (final job in jobs) {
      final ok = job.kind == 'tombstone'
          ? await bridge.clear(job.payload)
          : await bridge.publish(job.payload);
      if (ok) {
        await ledgerRepository.completeWidgetJob(job.id);
      } else {
        await ledgerRepository.recordWidgetJobFailure(job.id);
      }
    }
  }

  Future<WidgetPublishResult> _deliver({
    required int ledgerRevision,
    required String kind,
    required String payload,
    required DateTime nowUtc,
  }) async {
    await ledgerRepository.enqueueWidgetJob(
      ledgerRevision: ledgerRevision,
      kind: kind,
      payload: payload,
      nowUtc: nowUtc,
    );
    final jobs = await ledgerRepository.pendingWidgetJobs();
    final latest = jobs.isEmpty ? null : jobs.last;
    final ok = kind == 'tombstone'
        ? await bridge.clear(payload)
        : await bridge.publish(payload);
    if (ok && latest != null) {
      await ledgerRepository.completeWidgetJob(latest.id);
    } else if (latest != null) {
      await ledgerRepository.recordWidgetJobFailure(latest.id);
    }
    return WidgetPublishResult(
      ok: ok,
      message: ok ? null : '桌面分身暂时没收到更新，稍后会重试。',
    );
  }

  static String _encode(Map<String, dynamic> payload) => jsonEncode(payload);
}
