import 'package:finance_core/finance_core.dart';
import 'package:ledger_model/ledger_model.dart';
import 'package:test/test.dart';

void main() {
  final calendar = BusinessCalendar.shanghai;
  final now = DateTime.utc(2026, 11, 12, 2);

  test('salary + schedule makes a ledger usable without onboarding provenance',
      () {
    final demo = buildDemoLedger(calendar, now);
    expect(demo.settings.hasCompletedOnboarding, isTrue);

    final manuallyConfigured = demo.copyWith(settings: const AppSettings());
    expect(manuallyConfigured.settings.hasCompletedOnboarding, isFalse);
    expect(manuallyConfigured.isConfigured, isTrue,
        reason: 'PC 手动配置不经过手机引导，也必须能直接使用');
    expect(manuallyConfigured.salaryVersions, isNotEmpty);
    expect(manuallyConfigured.schedules, isNotEmpty);
  });

  test('missing salary or schedule keeps the ledger unconfigured', () {
    final empty = LedgerState.empty();
    expect(empty.isConfigured, isFalse);
    final salaryOnly = empty.copyWith(
      salaryVersions: buildDemoLedger(calendar, now).salaryVersions,
    );
    expect(salaryOnly.isConfigured, isFalse);
    final scheduleOnly = empty.copyWith(
      schedules: buildDemoLedger(calendar, now).schedules,
    );
    expect(scheduleOnly.isConfigured, isFalse);
  });
}
