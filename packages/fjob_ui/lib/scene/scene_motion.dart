/// Shared scene timing. Consumers control visibility, not a second timeline.
abstract final class SceneMotion {
  static const Duration pat = Duration(milliseconds: 3200);
  static const Duration patReduced = Duration(milliseconds: 2400);
  static const Duration departure = Duration(milliseconds: 2200);
  static const Duration departureWindow = Duration(milliseconds: 2000);
  static const Duration ambient = Duration(milliseconds: 8000);

  static const int responseAtMs = 420;
  static const double patRecoveryAtMs = 2400;
  static const double departureCoinsFadeAtMs = 180;
  static const double departureStandAtMs = 560;
  static const double departureWalkAtMs = 860;
  static const double departureExitAtMs = 1900;
}
