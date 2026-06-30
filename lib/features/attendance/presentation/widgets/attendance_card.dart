import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../data/location_helper.dart';
import '../../data/models/attendance_snapshot.dart';
import '../controllers/attendance_controller.dart';

/// The single tile at the top of the Me tab that now drives the entire
/// attendance + availability lifecycle. Replaces the old standalone duty
/// toggle — Away is now a sub-state of "checked in".
///
/// States:
///   off    → primary [Check in]                              (gray)
///   active → primary [Check out] · secondary [Break] [Away]  (green)
///   break  → primary [End break] · secondary [Check out]     (orange)
///   away   → primary [I'm back]  · secondary [Check out]     (yellow)
class AttendanceCard extends ConsumerWidget {
  const AttendanceCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(attendanceControllerProvider);

    return async.when(
      loading: () => const _Skeleton(),
      error: (_, __) => const _Skeleton(
        message: 'Could not load attendance. Pull down to retry.',
      ),
      data: (snap) => _CardBody(snap: snap),
    );
  }
}

class _CardBody extends ConsumerStatefulWidget {
  final AttendanceSnapshot snap;
  const _CardBody({required this.snap});

  @override
  ConsumerState<_CardBody> createState() => _CardBodyState();
}

class _CardBodyState extends ConsumerState<_CardBody> {
  bool _busy = false;

  // ── Theme ────────────────────────────────────────────────
  Color _color() => switch (widget.snap.status) {
        AttendanceStatus.active => const Color(0xFF22C55E),
        AttendanceStatus.breakTime => const Color(0xFFF59E0B),
        AttendanceStatus.away => const Color(0xFFEAB308),
        AttendanceStatus.off => Colors.grey.shade400,
      };

  String _statusLabel() => switch (widget.snap.status) {
        AttendanceStatus.active => 'Active — ready to work',
        AttendanceStatus.breakTime => 'On break',
        AttendanceStatus.away => (widget.snap.awayReason?.trim().isNotEmpty ?? false)
            ? 'Away — ${widget.snap.awayReason!.trim()}'
            : 'Away — not taking tasks',
        AttendanceStatus.off => 'Checked out',
      };

  String _subline() {
    final s = widget.snap;
    if (!s.status.isAtWork) {
      return s.todayMinutes > 0
          ? 'Today: ${s.todayHoursLabel}'
          : 'Not checked in yet today';
    }
    final since = s.openSessionStartedAt;
    final timeStr = since != null
        ? DateFormat('h:mm a').format(since.toLocal())
        : '—';
    return 'Since $timeStr  ·  Today: ${s.todayHoursLabel}';
  }

  // ── Action wrappers ──────────────────────────────────────

  /// Geo-aware action: tries to get a GPS fix; on failure offers a
  /// "Continue anyway" prompt and sends with null coords. Used for
  /// the four attendance events that need a location for the report.
  Future<void> _geoAct({
    required Future<AttendanceActionResult> Function(
      ({double lat, double lng, int? accuracy})? fix,
    ) action,
    String? confirmTitle,
    String? confirmBody,
    String? confirmActionLabel,
    Color? confirmColor,
  }) async {
    if (confirmTitle != null) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(confirmTitle),
          content: confirmBody != null ? Text(confirmBody) : null,
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: confirmColor != null
                  ? FilledButton.styleFrom(backgroundColor: confirmColor)
                  : null,
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(confirmActionLabel ?? 'Confirm'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }

    if (!mounted) return;
    setState(() => _busy = true);

    ({double lat, double lng, int? accuracy})? fix;
    String? locationFailureMessage;
    try {
      fix = await LocationHelper.tryGetOneShot();
    } on LocationUnavailableException catch (e) {
      locationFailureMessage = e.userMessage;
    }

    if (!mounted) return;

    // GPS failed.
    if (fix == null) {
      // In DEBUG builds, surface a picker so the developer can exercise
      // each matching scenario (matched / unmatched / no-location) on an
      // emulator that won't return real GPS fixes. This is the path your
      // emulator takes — never reachable in release builds.
      if (kDebugMode) {
        setState(() => _busy = false);
        final choice = await _showDevPicker(locationFailureMessage);
        if (choice == null || !mounted) return;
        fix = choice.fix; // may still be null if the dev picked "No location"
        setState(() => _busy = true);
      } else {
        // RELEASE: respect the per-session "Continue anyway" opt-in so we
        // don't nag the user on every action.
        final alreadyAccepted = ref.read(acceptedNoLocationProvider);
        if (!alreadyAccepted) {
          setState(() => _busy = false);
          final goAhead = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.location_off_outlined,
                      color: Color(0xFFF59E0B), size: 22,),
                  SizedBox(width: 8),
                  Text('Location unavailable'),
                ],
              ),
              content: Text(
                '${locationFailureMessage ?? 'We could not read your location.'}'
                '\n\nWe will stop asking for the rest of this session. Your '
                'manager will see these entries as "Unmatched".',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFF59E0B),
                  ),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Continue anyway'),
                ),
              ],
            ),
          );
          if (goAhead != true || !mounted) return;
          ref.read(acceptedNoLocationProvider.notifier).state = true;
          setState(() => _busy = true);
        }
      }
    }

    final result = await action(fix);
    if (!mounted) return;
    setState(() => _busy = false);
    _showResult(result, hasFix: fix != null, devFakeLabel: _lastDevLabel);
    _lastDevLabel = null;
  }

  /// Set by [_showDevPicker] so the success snackbar can prefix "🛠 DEV:".
  String? _lastDevLabel;

  /// Debug-only fake-location picker. Returns the dev's choice or null if
  /// they cancelled.
  Future<_DevFix?> _showDevPicker(String? failureReason) async {
    return showDialog<_DevFix>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.bug_report_outlined, size: 22, color: Color(0xFF7C3AED)),
            SizedBox(width: 8),
            Text('DEV — fake location'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              failureReason ?? 'Emulator GPS not delivering fixes.',
              style: const TextStyle(fontSize: 12.5, color: AppColors.ink3),
            ),
            const SizedBox(height: 8),
            const Text(
              'Pick a test scenario:',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            _devOption(
              ctx,
              icon: '🏢',
              title: 'Arena HQ (will match)',
              subtitle: '29.973194, 31.286002',
              result: const _DevFix(
                fix: (
                  lat: LocationHelper.devArenaHqLat,
                  lng: LocationHelper.devArenaHqLng,
                  accuracy: null,
                ),
                label: 'Arena HQ',
              ),
            ),
            _devOption(
              ctx,
              icon: '🛍️',
              title: 'Downtown Cairo (no match)',
              subtitle: '${LocationHelper.devUnmatchedLat}, '
                  '${LocationHelper.devUnmatchedLng}',
              result: const _DevFix(
                fix: (
                  lat: LocationHelper.devUnmatchedLat,
                  lng: LocationHelper.devUnmatchedLng,
                  accuracy: null,
                ),
                label: 'Downtown Cairo',
              ),
            ),
            _devOption(
              ctx,
              icon: '❓',
              title: 'No location',
              subtitle: 'send null coords (offline scenario)',
              result: const _DevFix(fix: null, label: 'No location'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  Widget _devOption(
    BuildContext ctx, {
    required String icon,
    required String title,
    required String subtitle,
    required _DevFix result,
  }) {
    return InkWell(
      onTap: () {
        _lastDevLabel = result.label;
        Navigator.pop(ctx, result);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          children: [
            Text(icon, style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.ink3,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.ink3),
          ],
        ),
      ),
    );
  }

  /// Probes GPS once and reports the result to the user. If the fix succeeds
  /// we clear the "skip location" flag so subsequent actions run with coords.
  /// If it still fails, the flag stays set and we show the reason.
  Future<void> _testGpsAndReset() async {
    if (!mounted) return;
    setState(() => _busy = true);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      duration: Duration(seconds: 2),
      content: Text('Checking GPS…'),
    ),);

    ({double lat, double lng, int? accuracy})? fix;
    String? failure;
    try {
      fix = await LocationHelper.tryGetOneShot();
    } on LocationUnavailableException catch (e) {
      failure = e.userMessage;
    } catch (e) {
      failure = 'Unexpected error: $e';
    }

    if (!mounted) return;
    setState(() => _busy = false);

    if (fix != null) {
      // Got a real fix — wipe the silence flag so attendance actions use it.
      ref.read(acceptedNoLocationProvider.notifier).state = false;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: const Color(0xFF22C55E),
        content: Text(
          'GPS works ✓  lat ${fix.lat.toStringAsFixed(5)}, lng ${fix.lng.toStringAsFixed(5)}',
        ),
      ),);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.arenaRed,
        duration: const Duration(seconds: 4),
        content: Text(failure ?? 'GPS still unavailable'),
      ),);
    }
  }

  /// Ask WHY the employee is going away (required). Returns the chosen reason
  /// (a preset chip or free text), or null if cancelled.
  Future<String?> _pickAwayReason() async {
    const presets = <String>[
      'اجتماع / مقابلة',
      'مكالمة مهمة',
      'مشوار شغل برّه',
      'مع كلاينت',
      'ظرف شخصي',
      'ظرف طارئ',
    ];
    final controller = TextEditingController();

    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 18, right: 18, top: 16,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 18,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Why are you going away?',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            const Text('A reason is required and recorded.',
                style: TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final r in presets)
                  ActionChip(
                    label: Text(r, style: const TextStyle(fontSize: 13)),
                    backgroundColor: const Color(0xFFFFF7ED),
                    side: const BorderSide(color: Color(0xFFFED7AA)),
                    onPressed: () => Navigator.of(ctx).pop(r),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    maxLength: 255,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(
                      hintText: 'Other reason…',
                      counterText: '',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (v) {
                      if (v.trim().isNotEmpty) Navigator.of(ctx).pop(v.trim());
                    },
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFFC2410C)),
                  onPressed: () {
                    final v = controller.text.trim();
                    if (v.isNotEmpty) Navigator.of(ctx).pop(v);
                  },
                  child: const Text('Go'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Pure server-side action (no GPS needed) — for the Away / Back toggle.
  Future<void> _plainAct(
    Future<AttendanceActionResult> Function() action,
  ) async {
    if (!mounted) return;
    setState(() => _busy = true);
    final result = await action();
    if (!mounted) return;
    setState(() => _busy = false);
    _showResult(result, hasFix: true);
  }

  void _showResult(
    AttendanceActionResult result, {
    required bool hasFix,
    String? devFakeLabel,
  }) {
    if (!result.ok) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(result.errorMessage ?? 'Failed'),
        backgroundColor: AppColors.arenaRed,
      ),);
      return;
    }
    final s = result.snapshot!;
    final matched = s.lastEvent?.matchedLocationName;
    final prefix = devFakeLabel != null ? '🛠 DEV($devFakeLabel) · ' : '';
    final matchedLine = matched != null
        ? '  ·  matched: $matched'
        : (hasFix == false ? '  ·  unmatched (no coords)' : '  ·  unmatched');
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(seconds: 3),
      content: Text('$prefix${_actionPastTense(s)}$matchedLine'),
      backgroundColor: devFakeLabel != null
          ? const Color(0xFF7C3AED)
          : const Color(0xFF22C55E),
    ),);
  }

  String _actionPastTense(AttendanceSnapshot s) => switch (s.status) {
        AttendanceStatus.active => 'You are active.',
        AttendanceStatus.breakTime => 'Break started.',
        AttendanceStatus.away => 'You are now away.',
        AttendanceStatus.off => 'You are checked out.',
      };

  // ── Build ─────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final snap = widget.snap;
    final notifier = ref.read(attendanceControllerProvider.notifier);

    Future<void> onCheckIn() => _geoAct(
          action: (fix) => notifier.checkIn(fix: fix),
          confirmTitle: 'Check in?',
          confirmBody: 'Your location will be recorded and the clock starts.',
          confirmActionLabel: 'Check in',
          confirmColor: const Color(0xFF22C55E),
        );
    Future<void> onCheckOut() => _geoAct(
          action: (fix) => notifier.checkOut(fix: fix),
          confirmTitle: 'Check out?',
          confirmBody: 'You will leave work and the clock stops.',
          confirmActionLabel: 'Check out',
          confirmColor: AppColors.arenaRed,
        );
    Future<void> onBreakStart() => _geoAct(
          action: (fix) => notifier.breakStart(fix: fix),
        );
    Future<void> onBreakEnd() => _geoAct(
          action: (fix) => notifier.breakEnd(fix: fix),
        );
    Future<void> onGoAway() async {
      final reason = await _pickAwayReason();
      if (reason == null || reason.trim().isEmpty) return; // cancelled
      await _plainAct(() => notifier.setAvailability(false, reason: reason.trim()));
    }
    Future<void> onComeBack() => _plainAct(() => notifier.setAvailability(true));

    final gpsSilenced = ref.watch(acceptedNoLocationProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _StatusHeader(
              color: _color(),
              label: _statusLabel(),
              subline: _subline(),
              dotGlows: snap.status.isAtWork,
            ),
            if (gpsSilenced) ...[
              const SizedBox(height: 10),
              _NoLocationBanner(onReEnable: _testGpsAndReset),
            ],
            const SizedBox(height: 14),
            _ActionRow(
              snap: snap,
              busy: _busy,
              onCheckIn: onCheckIn,
              onCheckOut: onCheckOut,
              onBreakStart: onBreakStart,
              onBreakEnd: onBreakEnd,
              onGoAway: onGoAway,
              onComeBack: onComeBack,
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusHeader extends StatelessWidget {
  final Color color;
  final String label;
  final String subline;
  final bool dotGlows;
  const _StatusHeader({
    required this.color,
    required this.label,
    required this.subline,
    required this.dotGlows,
  });
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: dotGlows
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.45),
                      blurRadius: 8,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
              Text(
                subline,
                style: const TextStyle(fontSize: 12.5, color: AppColors.ink3),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ActionRow extends StatelessWidget {
  final AttendanceSnapshot snap;
  final bool busy;
  final VoidCallback onCheckIn;
  final VoidCallback onCheckOut;
  final VoidCallback onBreakStart;
  final VoidCallback onBreakEnd;
  final VoidCallback onGoAway;
  final VoidCallback onComeBack;

  const _ActionRow({
    required this.snap,
    required this.busy,
    required this.onCheckIn,
    required this.onCheckOut,
    required this.onBreakStart,
    required this.onBreakEnd,
    required this.onGoAway,
    required this.onComeBack,
  });

  @override
  Widget build(BuildContext context) {
    switch (snap.status) {
      case AttendanceStatus.off:
        return _bigButton(
          label: 'Check in',
          icon: Icons.login,
          color: const Color(0xFF22C55E),
          onTap: busy ? null : onCheckIn,
        );
      case AttendanceStatus.active:
        return Column(
          children: [
            _bigButton(
              label: 'Check out',
              icon: Icons.logout,
              color: AppColors.arenaRed,
              onTap: busy ? null : onCheckOut,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _outlinedAction(
                    label: 'Break',
                    icon: Icons.coffee_outlined,
                    onTap: busy ? null : onBreakStart,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _outlinedAction(
                    label: 'Away',
                    icon: Icons.do_not_disturb_alt_outlined,
                    onTap: busy ? null : onGoAway,
                  ),
                ),
              ],
            ),
          ],
        );
      case AttendanceStatus.breakTime:
        return Row(
          children: [
            Expanded(
              flex: 2,
              child: _bigButton(
                label: 'End break',
                icon: Icons.play_arrow,
                color: const Color(0xFF22C55E),
                onTap: busy ? null : onBreakEnd,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 1,
              child: _outlinedAction(
                label: 'Check out',
                icon: Icons.logout,
                onTap: busy ? null : onCheckOut,
              ),
            ),
          ],
        );
      case AttendanceStatus.away:
        return Row(
          children: [
            Expanded(
              flex: 2,
              child: _bigButton(
                label: "I'm back",
                icon: Icons.play_arrow,
                color: const Color(0xFF22C55E),
                onTap: busy ? null : onComeBack,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 1,
              child: _outlinedAction(
                label: 'Check out',
                icon: Icons.logout,
                onTap: busy ? null : onCheckOut,
              ),
            ),
          ],
        );
    }
  }

  Widget _bigButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback? onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        icon: busy
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(Colors.white),
                ),
              )
            : Icon(icon, size: 20),
        label: Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
    );
  }

  Widget _outlinedAction({
    required String label,
    required IconData icon,
    required VoidCallback? onTap,
  }) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      ),
    );
  }
}

/// Dev picker result — either a fake fix or null (offline simulation).
class _DevFix {
  final ({double lat, double lng, int? accuracy})? fix;
  final String label;
  const _DevFix({required this.fix, required this.label});
}

/// Tiny inline banner shown when the user has opted to skip location for
/// this session. Lets them re-enable in one tap if their GPS comes back.
class _NoLocationBanner extends StatelessWidget {
  final VoidCallback onReEnable;
  const _NoLocationBanner({required this.onReEnable});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF3C7),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFF59E0B), width: 1),
      ),
      child: Row(
        children: [
          const Icon(Icons.location_off_outlined,
              color: Color(0xFF92400E), size: 18,),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Location is off — events will be marked as Unmatched',
              style: TextStyle(
                fontSize: 12,
                color: Color(0xFF92400E),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          TextButton(
            onPressed: onReEnable,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              foregroundColor: const Color(0xFF92400E),
            ),
            child: const Text(
              'Try again',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _Skeleton extends StatelessWidget {
  final String? message;
  const _Skeleton({this.message});
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message ?? 'Loading attendance…',
                style: const TextStyle(color: AppColors.ink3),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
