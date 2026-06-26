import 'dart:io';
// import 'dart:ui';

import 'package:flutter/foundation.dart';
// import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:path_provider/path_provider.dart';

// import 'prefs_service.dart';

class OverlayControllerService {
  OverlayControllerService._();
  static final OverlayControllerService instance = OverlayControllerService._();

  Future<void> writeState(bool enabled) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/overlay_enabled.json');
      await file.writeAsString(enabled ? 'true' : 'false');
      debugPrint('🐾 OVERLAY: wrote cross-isolate state: $enabled');
    } catch (e, stack) {
      debugPrint('🐾 OVERLAY: failed to write state: $e\n$stack');
    }
  }

  Future<bool> readState() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/overlay_enabled.json');
      if (await file.exists()) {
        final content = await file.readAsString();
        return content.trim() == 'true';
      }
    } catch (e, stack) {
      debugPrint('🐾 OVERLAY: failed to read state: $e\n$stack');
    }
    return false;
  }

  Future<bool> ensurePermission() async {
    // final granted = await FlutterOverlayWindow.isPermissionGranted();
    // if (granted) return true;
    // await FlutterOverlayWindow.requestPermission();
    // return FlutterOverlayWindow.isPermissionGranted();
    return false;
  }

  Future<bool> setEnabled(bool enabled) async {
    // if (enabled) {
    //   final granted = await ensurePermission();
    //   if (!granted) return false;
    // } else {
    //   await hide();
    // }
    // await writeState(enabled);
    // final current = PrefsService.instance.current;
    // await PrefsService.instance.update(
    //   current.copyWith(overlayEnabled: enabled),
    // );
    // return enabled;
    return false;
  }

  Future<void> showIfEnabled() async {
    // final fileEnabled = await readState();
    // if (!fileEnabled) return;
    // try {
    //   if (await FlutterOverlayWindow.isActive()) return;
    //   // Start in collapsed mode (80x80) matching the 68x68 bubble exactly
    //   await FlutterOverlayWindow.showOverlay(
    //     enableDrag: true,
    //     height: 80,
    //     width: 80,
    //     alignment: OverlayAlignment.centerRight,
    //     overlayTitle: 'PocketClaw',
    //     overlayContent: 'Claw is ready',
    //     flag: OverlayFlag.focusPointer,
    //     positionGravity: PositionGravity.auto,
    //     visibility: NotificationVisibility.visibilityPublic,
    //   );
    //   debugPrint('🐾 OVERLAY: showed bubble in collapsed 80x80 mode');
    // } catch (e, stack) {
    //   debugPrint('🐾 OVERLAY: show failed: $e\n$stack');
    // }
  }

  Future<void> hide() async {
    // try {
    //   // Send collapse command to the overlay isolate so it shrinks before closing
    //   final port = IsolateNameServer.lookupPortByName('pocketclaw_overlay_port');
    //   port?.send({'command': 'collapse'});
    //
    //   if (await FlutterOverlayWindow.isActive()) {
    //     await FlutterOverlayWindow.closeOverlay();
    //   }
    // } catch (e, stack) {
    //   debugPrint('🐾 OVERLAY: hide failed: $e\n$stack');
    // }
  }

  Future<void> markDisabledFromOverlay() async {
    // await hide();
    // await writeState(false);
    // final current = PrefsService.instance.current;
    // await PrefsService.instance.update(current.copyWith(overlayEnabled: false));
  }
}
