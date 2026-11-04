import 'package:finance_core/finance_core.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  FinanceTimeZones.ensureInitialized();
  runApp(const ProviderScope(child: FjobApp()));
}
