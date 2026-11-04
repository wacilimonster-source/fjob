/// 四个底部标签与应用外壳。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/deep_links.dart';
import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../features/assets/assets_page.dart';
import '../../features/dashboard/dashboard_page.dart';
import '../../features/expenses/expenses_page.dart';
import '../../features/ledger/ledger_controller.dart';
import '../../features/widgets/widgets_page.dart';
import 'tabs.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell>
    with WidgetsBindingObserver {
  StreamSubscription<String>? _links;
  bool _publishedOnce = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bindDeepLinks();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || ref.read(sampleModeProvider)) return;
      final controller = ref.read(ledgerControllerProvider.notifier);
      unawaited(controller.retryPendingWidgetJobs());
      if (!_publishedOnce &&
          ref.read(ledgerControllerProvider).value?.isConfigured == true) {
        _publishedOnce = true;
        unawaited(controller.publishWidgets());
      }
    });
  }

  Future<void> _bindDeepLinks() async {
    if (!ref.read(deepLinksEnabledProvider)) return;
    final initial = await DeepLinkService.initialLink();
    if (initial != null && mounted) _applyLink(initial);
    _links = DeepLinkService.links().listen(
      _applyLink,
      onError: (Object _) {},
    );
  }

  void _applyLink(String link) {
    final tab = tabForDeepLink(link);
    if (tab == null || !mounted) return;
    ref.read(selectedTabProvider.notifier).state = AppTab.values[tab];
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !ref.read(sampleModeProvider)) {
      final controller = ref.read(ledgerControllerProvider.notifier);
      unawaited(controller.refreshQuotes());
      unawaited(controller.retryPendingWidgetJobs());
    }
  }

  @override
  void dispose() {
    _links?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final tab = ref.watch(selectedTabProvider);
    final sample = ref.watch(sampleModeProvider);
    return Scaffold(
      body: Column(
        children: [
          if (sample) const _SampleBanner(),
          Expanded(
            child: SafeArea(
              top: !sample,
              bottom: false,
              left: false,
              right: false,
              child: IndexedStack(
                index: tab.index,
                children: const [
                  DashboardPage(),
                  AssetsPage(),
                  ExpensesPage(),
                  WidgetsPage(),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab.index,
        onDestinationSelected: (index) {
          ref.read(selectedTabProvider.notifier).state = AppTab.values[index];
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.coffee_outlined),
            selectedIcon: Icon(Icons.coffee),
            label: '求生现场',
          ),
          NavigationDestination(
            icon: Icon(Icons.query_stats),
            label: '资产风浪',
          ),
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: '固定牵挂',
          ),
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: '桌面分身',
          ),
        ],
      ),
      backgroundColor: palette.paper,
    );
  }
}

class _SampleBanner extends ConsumerWidget {
  const _SampleBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    return Material(
      color: palette.yellow,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '示例模式 · 固定时钟 14:36 · 不写入正式账本',
                  style: TextStyle(fontSize: 11, color: palette.ink),
                ),
              ),
              TextButton(
                onPressed: () {
                  ref.read(sampleModeProvider.notifier).state = false;
                  ref.read(selectedTabProvider.notifier).state = AppTab.dashboard;
                },
                child: const Text('退出示例'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
