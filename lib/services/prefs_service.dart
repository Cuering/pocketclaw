import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

import '../models/user_prefs.dart';
// import 'voice_service.dart';

/// Single-document Hive box for user preferences (name, onboarding state).
/// Singleton because there's one user per device.
///
/// Hive.initFlutter() is already called by ConversationStore.init() before
/// this runs; we just open our own box.
class PrefsService {
  PrefsService._();
  static final PrefsService instance = PrefsService._();

  static const String _boxName = 'user_prefs';
  static const String _key = 'prefs';

  Box<String>? _box;
  UserPrefs? _cached;

  Future<void> init() async {
    if (_box != null) return;
    _box = await Hive.openBox<String>(_boxName);
    _cached = _load();

    // Read the cross-isolate file state to sync
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/overlay_enabled.json');
      if (await file.exists()) {
        final content = await file.readAsString();
        final fileEnabled = content.trim() == 'true';
        if (fileEnabled != _cached!.overlayEnabled) {
          _cached = _cached!.copyWith(overlayEnabled: fileEnabled);
          await _box!.put(_key, jsonEncode(_cached!.toJson()));
        }
      } else {
        // If file doesn't exist, create it with the current Hive state
        await file.writeAsString(_cached!.overlayEnabled ? 'true' : 'false');
      }
    } catch (e) {
      debugPrint('🐾 PREFS: failed to sync with file state: $e');
    }

    // Initialize the background voice command service
    // try {
    //   await VoiceService.instance.init();
    //   await VoiceService.instance.syncContinuousState();
    // } catch (e) {
    //   debugPrint('🐾 PREFS: failed to init VoiceService: $e');
    // }

    debugPrint(
      '🐾 PREFS: loaded (onboardingCompleted=${_cached!.onboardingCompleted}, '
      'name=${_cached!.name})',
    );
  }

  UserPrefs _load() {
    final raw = _box!.get(_key);
    if (raw == null) return UserPrefs();
    try {
      return UserPrefs.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (e) {
      debugPrint('🐾 PREFS: failed to parse, starting fresh: $e');
      return UserPrefs();
    }
  }

  /// Current prefs. Always non-null after init().
  UserPrefs get current {
    final c = _cached;
    if (c == null) {
      throw StateError('PrefsService not initialized. Call init() first.');
    }
    return c;
  }

  Future<void> update(UserPrefs prefs) async {
    _cached = prefs;
    await _box!.put(_key, jsonEncode(prefs.toJson()));
    debugPrint('🐾 PREFS: saved (onboardingCompleted=${prefs.onboardingCompleted})');
    // Trigger voice background listening check dynamically
    // ignore: discarded_futures
    // VoiceService.instance.syncContinuousState();
  }

  bool get isOnboarded => _cached?.onboardingCompleted ?? false;
}
