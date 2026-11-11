import 'package:finance_core/finance_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fjob_ui/fjob_ui.dart';
import 'package:window_manager/window_manager.dart';

import 'desktop_controller.dart';
import 'pages/config_page.dart';
import 'pages/data_page.dart';
import 'pages/desktop_page.dart';
import 'pages/settings_page.dart';
import 'state/providers.dart';

class MainWindow extends ConsumerStatefulWidget {
  const MainWindow({super.key});

  @override
  ConsumerState<MainWindow> createState() => _MainWindowState();
}

class _MainWindowState extends ConsumerState<MainWindow> {
  int _index = 0;
  bool _welcomeDismissed = false;

  static const _destinations = <(IconData, String)>[
    (Icons.tune_outlined, '配置'),
    (Icons.desktop_windows_outlined, '桌面'),
    (Icons.storage_outlined, '数据'),
    (Icons.settings_outlined, '设置'),
  ];

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final desktop = ref.watch(desktopControllerProvider);
    final ledger = ref.watch(effectiveLedgerProvider).value;
    final sample = ref.watch(sampleModeProvider);
    final configured = ledger?.isConfigured ?? false;

    return Scaffold(
      backgroundColor: palette.paper,
      body: Column(
        children: [
          _titleBar(palette, desktop),
          Expanded(
            child: Row(
              children: [
                _rail(palette),
                Expanded(
                  child: AnimatedBuilder(
                    animation: desktop,
                    builder: (context, _) {
                      if (!configured &&
                          !sample &&
                          !_welcomeDismissed &&
                          _index == 0) {
                        return _WelcomePanel(
                          onImport: () => setState(() {
                            _welcomeDismissed = true;
                            _index = 2;
                          }),
                          onStart: () => setState(() {
                            _welcomeDismissed = true;
                            _index = 0;
                          }),
                        );
                      }
                      return switch (_index) {
                        0 => const ConfigPage(),
                        1 => const DesktopPage(),
                        2 => const DataPage(),
                        _ => const SettingsPage(),
                      };
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _titleBar(FjobPalette palette, DesktopController desktop) {
    final quoteStatus = ref.watch(quoteStatusProvider);
    final ledger = ref.watch(effectiveLedgerProvider).value;
    final revision = ledger?.settings.ledgerRevision ?? 0;
    return Container(
      height: 46,
      padding: const EdgeInsets.only(left: 12, right: 6),
      decoration: BoxDecoration(
        color: palette.panel,
        border: Border(bottom: BorderSide(color: palette.line)),
      ),
      child: DragToMoveArea(
        child: Row(
          children: [
            const BrandMark(size: 24),
            const SizedBox(width: 9),
            const Text(
              '今日又白干',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
            const SizedBox(width: 9),
            Container(
              padding: const EdgeInsets.only(left: 9),
              decoration: BoxDecoration(
                border: Border(left: BorderSide(color: palette.line)),
              ),
              child: Text(
                '工位后台',
                style: TextStyle(fontSize: 11, color: palette.muted),
              ),
            ),
            const Spacer(),
            Icon(Icons.circle, size: 7, color: palette.positive),
            const SizedBox(width: 5),
            Text(
              '账本 #$revision · ${quoteStatus.status == QuoteStatus.refreshing ? '刷新中' : '本机'}',
              style: TextStyle(fontSize: 11, color: palette.muted),
            ),
            const SizedBox(width: 10),
            _windowButton(Icons.remove, () => windowManager.minimize()),
            _windowButton(Icons.crop_square, () async {
              if (await windowManager.isMaximized()) {
                await windowManager.unmaximize();
              } else {
                await windowManager.maximize();
              }
            }),
            _windowButton(
              Icons.close,
              () => desktop.hideMain(),
              hoverColor: palette.negative,
            ),
          ],
        ),
      ),
    );
  }

  Widget _windowButton(IconData icon, VoidCallback onTap, {Color? hoverColor}) {
    return SizedBox(
      width: 34,
      height: 30,
      child: IconButton(
        iconSize: 16,
        padding: EdgeInsets.zero,
        onPressed: onTap,
        icon: Icon(icon),
        hoverColor: hoverColor?.withValues(alpha: 0.15),
      ),
    );
  }

  Widget _rail(FjobPalette palette) {
    return Container(
      width: 168,
      decoration: BoxDecoration(
        color: palette.paper,
        border: Border(right: BorderSide(color: palette.line)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < _destinations.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: _railItem(
                palette,
                i,
                _destinations[i].$1,
                _destinations[i].$2,
              ),
            ),
          const Spacer(),
          Text('账本只在本机', style: TextStyle(fontSize: 10, color: palette.muted)),
          const SizedBox(height: 2),
          Text(
            'v$desktopAppVersion',
            style: TextStyle(fontSize: 10, color: palette.muted),
          ),
        ],
      ),
    );
  }

  Widget _railItem(
    FjobPalette palette,
    int index,
    IconData icon,
    String label,
  ) {
    final selected = _index == index;
    return Material(
      color: selected ? palette.soft : Colors.transparent,
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: () => setState(() => _index = index),
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: selected ? palette.line : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 18,
                color: selected ? palette.ink : palette.muted,
              ),
              const SizedBox(width: 9),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                  color: selected ? palette.ink : palette.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WelcomePanel extends StatelessWidget {
  const _WelcomePanel({required this.onImport, required this.onStart});
  final VoidCallback onImport;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              '把工位也拉进这场求生。',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            Text(
              '从手机导入同一本账，或在电脑上从零开始。工资、排班、资产与房贷车贷'
              '都与手机同源；金额只存本机。',
              style: TextStyle(fontSize: 13, color: palette.muted, height: 1.7),
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: const OfficeScene(
                phase: DayPhase.working,
                completeness: Completeness.complete,
                total: null,
                reduceMotion: true,
                interactive: false,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onImport,
              icon: const Icon(Icons.file_download_outlined),
              label: const Text('从手机导入 .fjob（推荐）'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: onStart,
              icon: const Icon(Icons.edit_outlined),
              label: const Text('从零开始配置'),
            ),
          ],
        ),
      ),
    );
  }
}
