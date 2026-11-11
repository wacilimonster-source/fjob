import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fjob_ui/fjob_ui.dart';
import 'package:ledger_model/ledger_model.dart';

import '../desktop_controller.dart';
import '../desktop_preferences.dart';
import '../state/providers.dart';
import '../widgets/fixed_card_view.dart';

class DesktopPage extends ConsumerWidget {
  const DesktopPage({super.key});

  Future<void> _set(WidgetRef ref, String key, Object? value) async {
    final store = ref.read(preferencesStoreProvider);
    final controller = ref.read(desktopControllerProvider);
    try {
      final next = await store.update(key, value);
      ref.read(preferencesProvider.notifier).state = next;
      await controller.applyPreferences(next);
    } on DesktopPreferenceException catch (e) {
      if (ref.context.mounted) {
        ScaffoldMessenger.of(ref.context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final prefs = ref.watch(preferencesProvider);
    final controller = ref.watch(desktopControllerProvider);
    final snapshot = ref.watch(dashboardProvider).value;
    final calendar = ref.watch(calendarProvider);
    final ledger = ref.watch(effectiveLedgerProvider).value;

    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 24),
      children: [
        Text(
          '桌面',
          style: Theme.of(context).textTheme.headlineMedium
              ?.copyWith(fontSize: 22),
        ),
        const SizedBox(height: 4),
        Text(
          '所有设置即时预览、即时保存；只写本机显示偏好，不提升账本修订、不触发行情。',
          style: TextStyle(fontSize: 12, color: palette.muted),
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final settings = PaperCard(
              child: Material(
                type: MaterialType.transparency,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SectionLabel('显示项'),
                    const SizedBox(height: 8),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'both', label: Text('都显示')),
                        ButtonSegment(value: 'time', label: Text('只看下班')),
                        ButtonSegment(value: 'balance', label: Text('只看结余')),
                      ],
                      selected: {prefs.metrics},
                      onSelectionChanged: (s) => _set(ref, 'metrics', s.first),
                    ),
                    const SizedBox(height: 16),
                    const SectionLabel('密度'),
                    const SizedBox(height: 8),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 's', label: Text('S 数字条')),
                        ButtonSegment(value: 'm', label: Text('M 便签卡')),
                        ButtonSegment(value: 'l', label: Text('L 工位窗')),
                      ],
                      selected: {prefs.density},
                      onSelectionChanged: (s) => _set(ref, 'density', s.first),
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('金额隐身'),
                      subtitle: const Text('遮蔽固定窗、预览、托盘与无障碍文案；主窗保持可见。'),
                      value: prefs.privacy,
                      onChanged: (v) => _set(ref, 'privacy', v),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('置顶'),
                      value: prefs.topmost,
                      onChanged: (v) => _set(ref, 'topmost', v),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('点击穿透'),
                      subtitle: const Text('开启后鼠标穿到下层；用热键或托盘解锁。'),
                      value: prefs.clickThrough,
                      onChanged: (v) => _set(ref, 'clickThrough', v),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('锁定位置'),
                      value: prefs.locked,
                      onChanged: (v) => _set(ref, 'locked', v),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('全屏应用时自动隐藏'),
                      value: prefs.fullscreenAutoHide,
                      onChanged: (v) => _set(ref, 'fullscreenAutoHide', v),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('减少动效'),
                      value: prefs.reduceMotion,
                      onChanged: (v) => _set(ref, 'reduceMotion', v),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('启动时显示固定窗'),
                      value: prefs.showAtStartup,
                      onChanged: (v) => _set(ref, 'showAtStartup', v),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const SizedBox(width: 96, child: Text('纸面透明度')),
                        Expanded(
                          child: Slider(
                            min: 0.85,
                            max: 1.0,
                            divisions: 15,
                            value: prefs.opacity,
                            label: '${(prefs.opacity * 100).round()}%',
                            onChanged: (v) => _set(
                              ref,
                              'opacity',
                              double.parse(v.toStringAsFixed(2)),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 48,
                          child: Text('${(prefs.opacity * 100).round()}%'),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    const SectionLabel('窗口控制'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () => controller.showCard(),
                          icon: const Icon(
                            Icons.picture_in_picture_alt,
                            size: 18,
                          ),
                          label: const Text('显示固定窗'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => controller.hideCard(),
                          icon: const Icon(
                            Icons.visibility_off_outlined,
                            size: 18,
                          ),
                          label: const Text('隐藏固定窗'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => controller.resetCardPosition(),
                          icon: const Icon(Icons.my_location, size: 18),
                          label: const Text('重置位置'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '老板键 Ctrl+Alt+${prefs.bossKey} · 金额隐身 Ctrl+Alt+${prefs.privacyKey} · '
                      '穿透 Ctrl+Alt+${prefs.clickThroughKey}（热键冲突时可在托盘操作）',
                      style: TextStyle(fontSize: 11, color: palette.muted),
                    ),
                  ],
                ),
              ),
            );
            final preview = PaperCard(
              color: palette.soft,
              child: Column(
                children: [
                  const SectionLabel('固定窗预览'),
                  const SizedBox(height: 12),
                  if (snapshot != null)
                    FittedBox(
                      fit: BoxFit.contain,
                      child: FixedCardView(
                        snapshot: snapshot,
                        calendar: calendar,
                        tone: ledger?.settings.tone ?? AppTone.gentle,
                        privacy: prefs.privacy,
                        density: densityFromName(prefs.density),
                        metricsMode: prefs.metrics,
                        reduceMotion: prefs.reduceMotion,
                      ),
                    )
                  else
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('配置账本后可预览'),
                    ),
                ],
              ),
            );
            if (constraints.maxWidth >= 860) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: settings),
                  const SizedBox(width: 14),
                  SizedBox(width: 320, child: preview),
                ],
              );
            }
            return Column(
              children: [settings, const SizedBox(height: 14), preview],
            );
          },
        ),
      ],
    );
  }
}
