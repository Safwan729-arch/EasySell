/// Compile-time feature flags via `--dart-define`. Default OFF so unfinished
/// features stay invisible in normal builds and releases.
class FeatureFlags {
  const FeatureFlags._();

  /// Enables the camera "Scan Product" flow. Turn on with
  /// `--dart-define=VISION_SCAN_ENABLED=true`.
  static const bool visionScanEnabled =
      bool.fromEnvironment('VISION_SCAN_ENABLED', defaultValue: false);
}
