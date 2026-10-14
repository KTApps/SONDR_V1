import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// iOS's own switch for this app's permissions.
///
/// `app-settings:` is what UIApplication.openSettingsURLString resolves to,
/// and the only way an app can send someone to the row holding its camera
/// permission. There is nothing to fall back to if it fails — the person has
/// to find Settings themselves — so a failure is logged and swallowed rather
/// than raised onto a screen that could not act on it.
Future<void> openAppSettings() async {
  try {
    await launchUrl(Uri.parse('app-settings:'));
  } catch (e) {
    debugPrint('SONDR settings error: ${e.runtimeType} :: $e');
  }
}
