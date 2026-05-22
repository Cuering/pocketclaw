/// Stored user preferences: name, onboarding state, future personalisation
/// fields. Lives in a Hive box managed by PrefsService.
///
/// Single document, not a collection. Stored as a JSON string under the
/// fixed key 'prefs' in the 'user_prefs' box.
class UserPrefs {
  UserPrefs({
    this.name,
    this.onboardingCompleted = false,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  String? name;
  bool onboardingCompleted;
  final DateTime createdAt;

  /// Friendly name to use in greetings; falls back to "friend".
  String get displayName => (name?.trim().isNotEmpty ?? false) ? name!.trim() : 'friend';

  Map<String, dynamic> toJson() => {
        'name': name,
        'onboardingCompleted': onboardingCompleted,
        'createdAt': createdAt.toIso8601String(),
      };

  factory UserPrefs.fromJson(Map<String, dynamic> json) => UserPrefs(
        name: json['name'] as String?,
        onboardingCompleted: json['onboardingCompleted'] as bool? ?? false,
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
      );

  UserPrefs copyWith({String? name, bool? onboardingCompleted}) => UserPrefs(
        name: name ?? this.name,
        onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted,
        createdAt: createdAt,
      );
}
