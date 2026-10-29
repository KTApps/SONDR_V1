import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// The one line that names the build, for feedback: "sondr 1.0 (98)" —
/// the app's name, its version to two parts, and the build number in
/// brackets, read from the bundle at runtime.

/// "sondr 1.0 (98)" from a version and a build number as the bundle has
/// them. The version is cut to its first two parts.
String versionLine(String version, String buildNumber) {
  final parts = version.split('.');
  final short = parts.length >= 2 ? '${parts[0]}.${parts[1]}' : version;
  return 'sondr $short ($buildNumber)';
}

/// The bundle's own figures, once.
final appVersionLineProvider = FutureProvider<String>((ref) async {
  final info = await PackageInfo.fromPlatform();
  return versionLine(info.version, info.buildNumber);
});
