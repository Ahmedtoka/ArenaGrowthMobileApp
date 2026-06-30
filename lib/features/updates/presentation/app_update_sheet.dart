import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../data/version_check_service.dart';

/// Sprint L — non-dismissible bottom sheet shown on app launch when a new
/// version is available. For a `mandatory` update the sheet has no Cancel
/// button + the back-gesture is blocked. For a soft update the user can
/// postpone with "Later".
///
/// Two-phase UX:
///   1. Idle  → "Update" button. Tap launches the Play Store / APK URL.
///   2. After we hand the user off to the installer we swap the button to
///      "Restart" so they can re-launch after the install completes.
///
/// Pure UI — no install logic lives here; we delegate to the platform.
class AppUpdateSheet extends StatefulWidget {
  final VersionInfo info;

  const AppUpdateSheet({super.key, required this.info});

  /// Convenience launcher used by the app shell on cold start.
  /// Returns `true` if an update sheet was shown.
  static Future<bool> maybeShow(
    BuildContext context,
    VersionInfo info,
  ) async {
    if (!info.updateAvailable) return false;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: !info.mandatory,
      enableDrag: !info.mandatory,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => PopScope(
        // For a mandatory update we eat the back gesture too.
        canPop: !info.mandatory,
        child: AppUpdateSheet(info: info),
      ),
    );
    return true;
  }

  @override
  State<AppUpdateSheet> createState() => _AppUpdateSheetState();
}

class _AppUpdateSheetState extends State<AppUpdateSheet> {
  bool _launched = false;
  bool _launching = false;

  Future<void> _launchInstaller() async {
    final i = widget.info;
    final url = i.playUrl?.isNotEmpty == true ? i.playUrl! : i.apkUrl;
    if (url == null || url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('No install URL configured — please contact your admin.'),
      ),);
      return;
    }
    setState(() => _launching = true);
    try {
      final ok = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!mounted) return;
      setState(() {
        _launching = false;
        _launched = ok;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _launching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final i = widget.info;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            20, 12, 20, 20 + MediaQuery.of(context).viewInsets.bottom,),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Grab handle (purely decorative for mandatory sheets).
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: AppColors.arenaBlue.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.system_update_alt,
                    color: AppColors.arenaBlue, size: 24,),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      i.mandatory ? 'Update required' : 'Update available',
                      style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Latest: v${i.latestVersion} · You have v${i.installedVersion}',
                      style: const TextStyle(
                          fontSize: 12.5, color: AppColors.ink3,),
                    ),
                  ],
                ),
              ),
            ],),
            const SizedBox(height: 16),

            // Release notes (if provided)
            if (i.releaseNotes.isNotEmpty) ...[
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.arenaBlue.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "What's new",
                      style: TextStyle(
                        fontSize: 11.5, fontWeight: FontWeight.w700,
                        color: AppColors.arenaBlue,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    ...i.releaseNotes.map(
                      (note) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('•  ',
                                style: TextStyle(color: AppColors.ink2),),
                            Expanded(
                              child: Text(
                                note,
                                style: const TextStyle(
                                    fontSize: 13, color: AppColors.ink2,),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Primary action — Update / Restart / Loading
            if (_launching)
              const SizedBox(
                height: 48,
                child: Center(
                  child: SizedBox(
                    width: 24, height: 24,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5, color: AppColors.arenaBlue,),
                  ),
                ),
              )
            else if (_launched)
              FilledButton.icon(
                onPressed: () {
                  // The platform installer will replace the running app.
                  // Closing the sheet lets the user re-open the new build.
                  Navigator.of(context).maybePop();
                },
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.greenBorder,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                icon: const Icon(Icons.refresh, color: Colors.white),
                label: const Text(
                  'Restart Arena',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,),
                ),
              )
            else
              FilledButton.icon(
                onPressed: _launchInstaller,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.arenaBlue,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                icon: const Icon(Icons.download, color: Colors.white),
                label: const Text(
                  'Update now',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,),
                ),
              ),

            // "Later" only on soft updates
            if (!i.mandatory && !_launched)
              TextButton(
                onPressed: () => Navigator.of(context).maybePop(),
                child: const Text(
                  'Later',
                  style: TextStyle(color: AppColors.ink3),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
