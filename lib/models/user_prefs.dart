/// Stored user preferences: name, onboarding state, future personalisation
/// fields. Lives in a Hive box managed by PrefsService.
///
/// Single document, not a collection. Stored as a JSON string under the
/// fixed key 'prefs' in the 'user_prefs' box.
class UserPrefs {
  UserPrefs({
    this.name,
    this.onboardingCompleted = false,
    this.overlayEnabled = false,
    this.picovoiceAccessKey,
    this.continuousListening = false,
    this.keepScreenAwake = true,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  String? name;
  bool onboardingCompleted;
  bool overlayEnabled;
  String? picovoiceAccessKey;
  bool continuousListening;
  bool keepScreenAwake;
  final DateTime createdAt;

  /// Friendly name to use in greetings; falls back to "friend".
  String get displayName =>
      (name?.trim().isNotEmpty ?? false) ? name!.trim() : 'friend';

  Map<String, dynamic> toJson() => {
    'name': name,
    'onboardingCompleted': onboardingCompleted,
    'overlayEnabled': overlayEnabled,
    'picovoiceAccessKey': picovoiceAccessKey,
    'continuousListening': continuousListening,
    'keepScreenAwake': keepScreenAwake,
    'createdAt': createdAt.toIso8601String(),
  };

  factory UserPrefs.fromJson(Map<String, dynamic> json) => UserPrefs(
    name: json['name'] as String?,
    onboardingCompleted: json['onboardingCompleted'] as bool? ?? false,
    overlayEnabled: json['overlayEnabled'] as bool? ?? false,
    picovoiceAccessKey: json['picovoiceAccessKey'] as String?,
    continuousListening: json['continuousListening'] as bool? ?? false,
    keepScreenAwake: json['keepScreenAwake'] as bool? ?? true,
    createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
  );

  UserPrefs copyWith({
    String? name,
    bool? onboardingCompleted,
    bool? overlayEnabled,
    String? picovoiceAccessKey,
    bool? continuousListening,
    bool? keepScreenAwake,
  }) => UserPrefs(
    name: name ?? this.name,
    onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted,
    overlayEnabled: overlayEnabled ?? this.overlayEnabled,
    picovoiceAccessKey: picovoiceAccessKey ?? this.picovoiceAccessKey,
    continuousListening: continuousListening ?? this.continuousListening,
    keepScreenAwake: keepScreenAwake ?? this.keepScreenAwake,
    createdAt: createdAt,
  );
}
