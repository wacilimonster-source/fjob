/// Deep links: `fjob://dashboard`, `fjob://expenses/housing`,
/// `fjob://expenses/car`, `fjob://widgets`. Only whitelisted paths navigate.
library;

import 'package:flutter/services.dart';

import '../features/shell/tabs.dart';

abstract final class DeepLinkService {
  static const MethodChannel _channel =
      MethodChannel('cn.fjob.todayagain/deeplinks');
  static const EventChannel _events =
      EventChannel('cn.fjob.todayagain/deeplinks/events');

  static Future<String?> initialLink() async {
    try {
      return await _channel.invokeMethod<String>('getInitialDeepLink');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  static Stream<String> links() => _events
      .receiveBroadcastStream()
      .map((event) => '$event')
      .where((link) => link.startsWith('fjob://'));
}

/// Returns the destination tab for a whitelisted link.
int? tabForDeepLink(String link) {
  final uri = Uri.tryParse(link);
  if (uri == null || uri.scheme != 'fjob') return null;
  return switch (uri.host) {
    'dashboard' => AppTab.dashboard.index,
    'expenses' => AppTab.expenses.index,
    'widgets' => AppTab.widgets.index,
    _ => null,
  };
}
