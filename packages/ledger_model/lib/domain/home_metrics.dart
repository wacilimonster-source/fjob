/// HOME-DUAL-10: which core metrics the dashboard shows.
///
/// This is a local presentation preference, not a privacy switch. It never
/// changes the ledger, quotes, widget snapshot or any financial amount.
library;

enum HomeMetricsMode {
  both('both'),
  time('time'),
  balance('balance');

  const HomeMetricsMode(this.storageValue);

  /// Stable value written to the local preference table.
  final String storageValue;

  /// Unknown or legacy values safely fall back to showing both cards.
  static HomeMetricsMode fromStorage(Object? value) {
    for (final mode in values) {
      if (mode.storageValue == value) return mode;
    }
    return HomeMetricsMode.both;
  }
}
