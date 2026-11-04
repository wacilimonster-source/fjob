/// Injectable clock so every calculation test is reproducible.
library;

abstract interface class Clock {
  DateTime nowUtc();
}

final class SystemClock implements Clock {
  const SystemClock();

  @override
  DateTime nowUtc() => DateTime.now().toUtc();
}

final class FixedClock implements Clock {
  FixedClock(this.instantUtc);

  DateTime instantUtc;

  @override
  DateTime nowUtc() => instantUtc;

  void advance(Duration duration) {
    instantUtc = instantUtc.add(duration);
  }
}
