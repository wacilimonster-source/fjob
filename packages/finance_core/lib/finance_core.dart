/// FJOB pure-Dart domain and calculation engine.
///
/// Everything here is deterministic: no UI, database, HTTP or wall clock. The
/// caller injects instants, quotes, calendars and configuration.
library;

export 'src/asset/asset_calculator.dart';
export 'src/dashboard/dashboard_calculator.dart';
export 'src/expense/expense_calculator.dart';
export 'src/money/rational.dart';
export 'src/schedule/schedule_expander.dart';
export 'src/schedule/schedule_model.dart';
export 'src/time/business_calendar.dart';
export 'src/time/local_date.dart';
export 'src/wage/wage_calculator.dart';
