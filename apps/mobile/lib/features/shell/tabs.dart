/// Bottom-navigation destinations shared by the shell, cards and deep links.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

enum AppTab { dashboard, assets, expenses, widgets }

final selectedTabProvider = StateProvider<AppTab>((ref) => AppTab.dashboard);
