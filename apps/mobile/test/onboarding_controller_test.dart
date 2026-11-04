import 'package:finance_core/finance_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todayagain/app/providers.dart';
import 'package:todayagain/features/ledger/ledger_controller.dart';
import 'package:todayagain/features/onboarding/onboarding_controller.dart';

import 'support/test_env.dart';

void main() {
  test('the six onboarding steps commit a configured ledger', () async {
    final container = makeContainer();
    await container.read(ledgerControllerProvider.future);
    final draft = await container.read(onboardingControllerProvider.future);
    expect(draft.step, 0);
    final controller = container.read(onboardingControllerProvider.notifier);

    controller.edit(draft.copyWith(salaryText: '12000'));
    expect(await controller.next(), isNull);
    expect(container.read(onboardingControllerProvider).value!.step, 1);

    expect(await controller.next(), isNull); // schedule
    expect(await controller.next(), isNull); // assets
    expect(await controller.next(), isNull); // housing
    expect(await controller.next(), isNull); // review
    expect(await controller.next(), isNull); // commit

    final ledger = container.read(ledgerControllerProvider).value!;
    expect(ledger.isConfigured, isTrue);
    expect(ledger.salaryVersions.single.monthlyNetCny, Rational.parse('12000'));
    expect(ledger.housingVersions.single.mode, HousingMode.none);
    expect(ledger.settings.ledgerRevision, 1);
  });

  test('an invalid salary keeps the step and surfaces the field error', () async {
    final container = makeContainer();
    await container.read(ledgerControllerProvider.future);
    final draft = await container.read(onboardingControllerProvider.future);
    final controller = container.read(onboardingControllerProvider.notifier);
    controller.edit(draft.copyWith(salaryText: '12000'));
    expect(await controller.next(), isNull);
    controller.edit(
      container.read(onboardingControllerProvider).value!.copyWith(
            salaryText: '',
          ),
    );
    expect(await controller.next(), contains('到手月薪'));
    expect(container.read(onboardingControllerProvider).value!.step, 1);
  });

  test('going back keeps the draft and a second confirm is idempotent', () async {
    final container = makeContainer();
    await container.read(ledgerControllerProvider.future);
    final draft = await container.read(onboardingControllerProvider.future);
    final controller = container.read(onboardingControllerProvider.notifier);
    controller.edit(draft.copyWith(salaryText: '12000'));
    await controller.next();
    await controller.next();
    await controller.back();
    expect(container.read(onboardingControllerProvider).value!.step, 1);

    while (container.read(onboardingControllerProvider).value!.step < 5) {
      expect(await controller.next(), isNull);
    }
    expect(await controller.next(), isNull);
    final sessionId =
        container.read(onboardingControllerProvider).value!.setupSessionId;
    expect(await controller.commit(), isNull);
    final ledger = container.read(ledgerControllerProvider).value!;
    expect(ledger.settings.ledgerRevision, 1);
    expect(sessionId, isNotEmpty);
  });

  test('redo prefill carries the committed values and cancel keeps the ledger',
      () async {
    final container = makeContainer();
    await container.read(ledgerControllerProvider.future);
    final repository = await container.read(ledgerRepositoryProvider.future);
    final validation = housingDraft('setup-once').validate();
    await repository.commitSetup(
      commit: validation.commit!,
      setupSessionId: 'setup-once',
      nowUtc: fixedNow,
    );
    container.invalidate(ledgerControllerProvider);
    await container.read(ledgerControllerProvider.future);

    final controller = container.read(onboardingControllerProvider.notifier);
    controller.startRedo();
    final redraft = await container.read(onboardingControllerProvider.future);
    expect(redraft.salaryText, '12000');
    expect(redraft.housingMode, HousingMode.mortgage);
    expect(redraft.mortgageMonthlyText, '4800');
    expect(redraft.carEnabled, isTrue);

    await controller.cancelRedo();
    final ledger = container.read(ledgerControllerProvider).value!;
    expect(ledger.settings.ledgerRevision, 1);
    expect(ledger.salaryVersions.single.monthlyNetCny, Rational.parse('12000'));
  });
}
