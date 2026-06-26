class ContextSnapshot {
  final String? foregroundPackage;
  final String? foregroundAppName;
  final String? screenTree;
  final bool accessibilityAvailable;
  final DateTime capturedAt;

  const ContextSnapshot({
    this.foregroundPackage,
    this.foregroundAppName,
    this.screenTree,
    required this.accessibilityAvailable,
    required this.capturedAt,
  });

  bool get hasContext => foregroundPackage != null || screenTree != null;
}
