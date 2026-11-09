import 'package:finance_core/finance_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todayagain/app/providers.dart';
import 'package:todayagain/domain/setup_draft.dart';
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

  test('redo keeps a fund holding and its precision, and cancel is read-only',
      () async {
    final container = makeContainer();
    await container.read(ledgerControllerProvider.future);
    final repository = await container.read(ledgerRepositoryProvider.future);
    final draft = validDraft('setup-fund')
      ..holdings = [
        const HoldingDraft(
          kind: HoldingKind.fund,
          code: '000001',
          name: '华夏成长混合',
          quantityText: '1000.2500',
          costText: '1.2000',
          pendingQuote: true,
        ),
      ];
    final validation = draft.validate();
    expect(validation.isValid, isTrue);
    await repository.commitSetup(
      commit: validation.commit!,
      setupSessionId: 'setup-fund',
      nowUtc: fixedNow,
    );
    container.invalidate(ledgerControllerProvider);
    await container.read(ledgerControllerProvider.future);

    final controller = container.read(onboardingControllerProvider.notifier);
    controller.startRedo();
    final redraft = await container.read(onboardingControllerProvider.future);
    final fund = redraft.holdings.single;
    expect(fund.isFund, isTrue);
    expect(fund.instrumentId, 'FUND.CN.000001');
    expect(fund.name, '华夏成长混合');
    expect(fund.quantityText, '1000.25');
    expect(fund.costText, '1.2');
    expect(fund.pendingQuote, isTrue);

    await controller.cancelRedo();
    final ledger = container.read(ledgerControllerProvider).value!;
    expect(ledger.settings.ledgerRevision, 1);
    final holding = ledger.holdings.single;
    expect(holding.instrumentId, 'FUND.CN.000001');
    expect(holding.quantity, Rational.parse('1000.25'));
    expect(holding.pendingQuote, isTrue);
    expect(ledger.instrumentNames['FUND.CN.000001'], '华夏成长混合');
  });
}
