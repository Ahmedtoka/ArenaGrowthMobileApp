import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../core/network/dio_client.dart';
import '../../../core/providers/app_providers.dart';

/// Result of a version-check round-trip. See [VersionCheckService.check].
class VersionInfo {
  /// True when a newer version is available and the user SHOULD update.
  final bool updateAvailable;

  /// True when the installed version is BELOW the server's `min_required`
  /// — the sheet must be non-dismissible in this case.
  final bool mandatory;

  /// The version the user has installed (e.g. "1.2.0").
  final String installedVersion;

  /// The version the server advertises as latest (e.g. "1.3.0").
  final String latestVersion;

  /// Optional Play Store URL.
  final String? playUrl;

  /// Optional direct-APK URL for sideload installs.
  final String? apkUrl;

  /// Optional list of release-note bullet points.
  final List<String> releaseNotes;

  const VersionInfo({
    required this.updateAvailable,
    required this.mandatory,
    required this.installedVersion,
    required this.latestVersion,
    this.playUrl,
    this.apkUrl,
    this.releaseNotes = const [],
  });

  /// True if either Play Store or APK URL is set — i.e. we have something to
  /// link the user to. If false the sheet falls back to "please reach out".
  bool get hasInstallTarget =>
      (playUrl != null && playUrl!.isNotEmpty) ||
      (apkUrl != null && apkUrl!.isNotEmpty);
}

/// Compares semver strings. Returns negative when `a < b`, 0 when equal,
/// positive when `a > b`. Non-numeric segments are treated as 0. Designed
/// to be forgiving — a bad string never crashes the splash screen.
int compareVersions(String a, String b) {
  final pa = _parse(a);
  final pb = _parse(b);
  final n = pa.length > pb.length ? pa.length : pb.length;
  for (var i = 0; i < n; i++) {
    final av = i < pa.length ? pa[i] : 0;
    final bv = i < pb.length ? pb[i] : 0;
    if (av != bv) return av - bv;
  }
  return 0;
}

List<int> _parse(String v) {
  // Strip leading "v" if present; ignore "+buildmeta".
  final clean = v.replaceFirst(RegExp(r'^v'), '').split('+').first;
  return clean.split('.').map((s) => int.tryParse(s.split('-').first) ?? 0).toList();
}

class VersionCheckService {
  final DioClient _client;
  VersionCheckService(this._client);

  Future<VersionInfo> check() async {
    final pkg = await PackageInfo.fromPlatform();
    final installed = pkg.version; // "1.2.0"

    try {
      // Anonymous endpoint — works even before login.
      final res = await _client.get('/version/latest');
      final data = (res.data as Map).cast<String, dynamic>();
      final latest = (data['latest'] as String?) ?? installed;
      final minReq = (data['min_required'] as String?) ?? installed;
      final forced = data['mandatory'] == true;

      final isBehind = compareVersions(installed, latest) < 0;
      final belowMin = compareVersions(installed, minReq) < 0;
      final notes = (data['release_notes'] as List?)?.cast<String>() ?? const [];

      return VersionInfo(
        updateAvailable: isBehind,
        mandatory: forced || belowMin,
        installedVersion: installed,
        latestVersion: latest,
        playUrl: data['play_url'] as String?,
        apkUrl: data['apk_url'] as String?,
        releaseNotes: notes,
      );
    } catch (_) {
      // Network failure or 500 → treat as "no update available" so the user
      // can still use the app. The next launch will retry.
      return VersionInfo(
        updateAvailable: false,
        mandatory: false,
        installedVersion: installed,
        latestVersion: installed,
      );
    }
  }
}

final versionCheckServiceProvider = Provider<VersionCheckService>((ref) {
  return VersionCheckService(ref.watch(dioClientProvider));
});

final latestVersionInfoProvider = FutureProvider<VersionInfo>((ref) async {
  return ref.watch(versionCheckServiceProvider).check();
});
