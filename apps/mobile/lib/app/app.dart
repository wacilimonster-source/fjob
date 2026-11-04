/// App root: theme, locale, onboarding gate and lifecycle-aware ticks.
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/ledger.dart';
import '../features/ledger/ledger_controller.dart';
import '../features/onboarding/onboarding_controller.dart';
import '../features/onboarding/onboarding_page.dart';
import '../features/shell/app_shell.dart';
import 'providers.dart';
import 'theme.dart';

class FjobApp extends ConsumerWidget {
  const FjobApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(effectiveLedgerProvider).value?.settings;
    final themeSetting = settings?.theme ?? ThemeSetting.system;
    return MaterialApp(
      title: '今日又白干',
      debugShowCheckedModeBanner: false,
      theme: FjobTheme.light(),
      darkTheme: FjobTheme.dark(),
      themeMode: switch (themeSetting) {
        ThemeSetting.light => ThemeMode.light,
        ThemeSetting.dark => ThemeMode.dark,
        ThemeSetting.system => ThemeMode.system,
      },
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const _Root(),
    );
  }
}

class _Root extends ConsumerStatefulWidget {
  const _Root();

  @override
  ConsumerState<_Root> createState() => _RootState();
}

class _RootState extends ConsumerState<_Root> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final visible = state == AppLifecycleState.resumed;
    ref.read(appVisibleProvider.notifier).state = visible;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sample = ref.watch(sampleModeProvider);
    if (sample) return const AppShell();

    final redo = ref.watch(onboardingRedoProvider);
    final ledgerAsync = ref.watch(ledgerControllerProvider);
    return ledgerAsync.when(
      loading: () => const _Splash(),
      error: (error, _) => _BootstrapError(message: '$error'),
      data: (ledger) => (!ledger.isConfigured || redo)
          ? OnboardingPage(redo: redo && ledger.isConfigured)
          : const AppShell(),
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      backgroundColor: palette.paper,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '今日又白干',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 6),
            Text(
              '正在办理入职…',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 18),
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ],
        ),
      ),
    );
  }
}

class _BootstrapError extends ConsumerWidget {
  const _BootstrapError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    return Scaffold(
      backgroundColor: palette.paper,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('本地账本打不开', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => ref.invalidate(ledgerControllerProvider),
                child: const Text('再试一次'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
