import 'package:flutter/services.dart';

class DeviceActionResult {
  const DeviceActionResult({required this.ok, required this.message});

  final bool ok;
  final String message;
}

/// Thin wrapper over Android intents/capabilities. Every method returns a
/// user-safe message so chat never exposes platform exceptions directly.
class DeviceActionsService {
  DeviceActionsService._();
  static final DeviceActionsService instance = DeviceActionsService._();

  static const MethodChannel _channel = MethodChannel('pocketclaw/device');

  Future<DeviceActionResult> setTorch(bool enabled) =>
      _invoke('setTorch', {'enabled': enabled});

  Future<DeviceActionResult> openDialer(String phone) =>
      _invoke('openDialer', {'phone': phone});

  Future<DeviceActionResult> openSms(String phone, String body) =>
      _invoke('openSms', {'phone': phone, 'body': body});

  Future<DeviceActionResult> openCalendar({
    required String title,
    String? notes,
  }) => _invoke('openCalendar', {'title': title, 'notes': notes});

  Future<DeviceActionResult> openAlarm({
    required String label,
    int? hour,
    int? minute,
  }) => _invoke('openAlarm', {'label': label, 'hour': hour, 'minute': minute});

  Future<DeviceActionResult> openLocationSettings() =>
      _invoke('openLocationSettings');

  Future<DeviceActionResult> openWebSearch(String query) =>
      _invoke('openWebSearch', {'query': query});

  Future<DeviceActionResult> openApp() => _invoke('openApp');

  Future<DeviceActionResult> setWakeLock(bool enabled) =>
      _invoke('setWakeLock', {'enabled': enabled});

  Future<DeviceActionResult> openAppSettings() => _invoke('openAppSettings');

  Future<DeviceActionResult> sendNotification(String title, String body) =>
      _invoke('sendNotification', {'title': title, 'body': body});

  Future<void> requestNotificationPermission() async {
    try {
      await _channel.invokeMethod<void>('requestNotificationPermission');
    } catch (_) {}
  }

  Future<Map<String, bool>> checkAppPermissions() async {
    try {
      final raw = await _channel.invokeMapMethod<String, Object?>(
        'checkAppPermissions',
      );
      return {
        'mic': raw?['mic'] == true,
        'camera': raw?['camera'] == true,
        'notifications': raw?['notifications'] == true,
      };
    } catch (_) {
      return {'mic': false, 'camera': false, 'notifications': false};
    }
  }

  Future<void> requestAppPermissions() async {
    try {
      await _channel.invokeMethod<void>('requestAppPermissions');
    } catch (_) {}
  }

  Future<bool> getVoiceTrigger() async {
    try {
      return await _channel.invokeMethod<bool>('getVoiceTrigger') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<DeviceActionResult> _invoke(
    String method, [
    Map<String, Object?> args = const {},
  ]) async {
    try {
      final raw = await _channel.invokeMapMethod<String, Object?>(method, args);
      return DeviceActionResult(
        ok: raw?['ok'] == true,
        message: raw?['message'] as String? ?? 'Done.',
      );
    } on PlatformException catch (e) {
      return DeviceActionResult(
        ok: false,
        message: e.message ?? "That action isn't available on this device.",
      );
    } on Object {
      return const DeviceActionResult(
        ok: false,
        message: "That action isn't available right now.",
      );
    }
  }
}
