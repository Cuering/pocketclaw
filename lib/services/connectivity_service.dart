import 'dart:io';

/// Small network probe used only for features that genuinely need internet:
/// first-run model downloads and optional web augmentation.
class ConnectivityService {
  ConnectivityService._();
  static final ConnectivityService instance = ConnectivityService._();

  Future<bool> hasInternet() async {
    // 1. First check against google.com for high-speed primary verification
    try {
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 5));
      if (result.isNotEmpty && result.first.rawAddress.isNotEmpty) {
        return true;
      }
    } catch (_) {}

    // 2. Fallback to huggingface.co check if primary is slow or delayed
    try {
      final result = await InternetAddress.lookup('huggingface.co')
          .timeout(const Duration(seconds: 5));
      return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }
}
