import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

/// An update points only to this app's public GitHub release page. Android still
/// requires the user to download and install the signed APK themselves.
class AppReleaseUpdate {
  final String tag;
  final int buildNumber;
  final Uri releasePage;

  const AppReleaseUpdate({
    required this.tag,
    required this.buildNumber,
    required this.releasePage,
  });
}

class AppUpdateService {
  static final Uri latestRelease = Uri.parse(
      'https://api.github.com/repos/02Adarsh/drivemate/releases/latest');
  static final RegExp _tagPattern =
      RegExp(r'^v(\d+)\.(\d+)\.(\d+)\+([1-9]\d*)$');

  /// Parse only trusted, published production releases with the standard APK.
  /// The Android version code is the build number following the plus sign.
  static AppReleaseUpdate? parseRelease(Object? input, int installedBuild) {
    if (input is! Map || installedBuild < 1) return null;
    if (input['draft'] != false || input['prerelease'] != false) return null;
    final tag = input['tag_name'];
    if (tag is! String) return null;
    final match = _tagPattern.firstMatch(tag);
    final build = match == null ? null : int.tryParse(match.group(4)!);
    if (build == null || build <= installedBuild || build > 2100000000) {
      return null;
    }
    final rawPage = input['html_url'];
    if (rawPage is! String) return null;
    final page = Uri.tryParse(rawPage);
    if (page == null ||
        page.scheme != 'https' ||
        page.host != 'github.com' ||
        page.hasPort ||
        page.userInfo.isNotEmpty ||
        page.hasQuery ||
        page.hasFragment) {
      return null;
    }
    final parts = page.pathSegments;
    if (parts.length != 5 ||
        parts[0] != '02Adarsh' ||
        parts[1] != 'drivemate' ||
        parts[2] != 'releases' ||
        parts[3] != 'tag' ||
        parts[4] != tag) {
      return null;
    }
    final assets = input['assets'];
    if (assets is! List ||
        !assets.any((asset) =>
            asset is Map &&
            asset['name'] == 'app-release.apk' &&
            asset['state'] == 'uploaded')) {
      return null;
    }
    return AppReleaseUpdate(tag: tag, buildNumber: build, releasePage: page);
  }

  /// Network errors, GitHub rate limits, old/malformed releases and unknown
  /// installed versions fail open; the next app opening retries the check.
  static Future<AppReleaseUpdate?> check({
    http.Client? client,
    Future<String> Function()? getInstalledBuild,
  }) async {
    final transport = client ?? http.Client();
    try {
      final buildText = getInstalledBuild != null
          ? await getInstalledBuild()
          : (await PackageInfo.fromPlatform()).buildNumber;
      final installedBuild = int.tryParse(buildText);
      if (installedBuild == null || installedBuild < 1) return null;
      final response = await transport.get(latestRelease, headers: const {
        'Accept': 'application/vnd.github+json',
        'User-Agent': 'DriveMate-Android',
      }).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200 || response.body.length > 512000) {
        return null;
      }
      return parseRelease(jsonDecode(response.body), installedBuild);
    } catch (_) {
      return null;
    } finally {
      if (client == null) transport.close();
    }
  }
}
