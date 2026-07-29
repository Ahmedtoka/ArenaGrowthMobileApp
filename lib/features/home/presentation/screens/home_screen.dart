import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_dimens.dart';
import '../../../../core/widgets/attendance_guard.dart';
import 'package:go_router/go_router.dart';

import '../../../attendance/presentation/controllers/ping_service.dart';
import '../../../attendance/presentation/widgets/attendance_card.dart';
import '../../../auth/data/models/user_model.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../../chat/presentation/controllers/groups_controller.dart';
import '../../../chat/presentation/controllers/realtime_bootstrap.dart';
import '../../../chat/presentation/screens/chats_list_tab.dart';
import '../../../dashboard/presentation/dashboard_screen.dart';
import '../../../inbox/presentation/controllers/action_center_providers.dart';
import '../../../chat/presentation/widgets/create_task_from_message_sheet.dart';
import '../../../tasks/presentation/controllers/tasks_providers.dart';
import '../../../tasks/presentation/screens/tasks_list_tab.dart';
import '../../../../core/push/pending_deep_link.dart';
import '../../../../core/widgets/inline_error_banner.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../../updates/data/version_check_service.dart';
import '../../../updates/presentation/app_update_sheet.dart';
import '../../../attendance/presentation/controllers/background_ping_bootstrap.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  // Footer order: Dashboard | Tasks | Chats | My Account
  int _index = 0; // open on Dashboard by default
  // Sprint L — only show the update sheet ONCE per app session.
  bool _versionSheetShown = false;

  static const _tabs = [
    _TabSpec('Dashboard', Icons.insights_outlined, Icons.insights),
    _TabSpec('Tasks', Icons.checklist_outlined, Icons.checklist),
    _TabSpec('Chats', Icons.chat_bubble_outline, Icons.chat_bubble),
    _TabSpec('Account', Icons.person_outline, Icons.person),
  ];

  // The "My Account" tab index (shows the signed-in person's first name).
  static const _accountIndex = 3;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).value;
    final inboxCount =
        ref.watch(actionCenterProvider).valueOrNull?.unread ?? 0;

    // Show the signed-in person's FIRST name on the "Me" tab + app bar so it's
    // obvious whose account this is (handy when juggling multiple emulators).
    final firstName = (user?.name ?? '').trim().split(' ').first;
    String labelFor(int i) =>
        (i == _accountIndex && firstName.isNotEmpty) ? firstName : _tabs[i].label;

    // Only managers may assign work to others — gate the header Add Task button
    // (the backend enforces this too).
    final canAssign = (user?.isOwner ?? false) ||
        (user?.isAccountManager ?? false) ||
        (user?.teamRole == 'department_manager');

    // Keep all groups subscribed to Reverb + listen for events to refresh the
    // chats list preview/timestamp live (without opening any chat).
    ref.watch(realtimeBootstrapProvider);

    // Sprint L — fire the version check once per session and show the
    // update bottom sheet if the server reports a newer release. Mandatory
    // updates pin the sheet (non-dismissible); soft updates can be
    // postponed via "Later".
    ref.listen(latestVersionInfoProvider, (_, next) {
      next.whenData((info) {
        if (_versionSheetShown || !info.updateAvailable || !mounted) return;
        _versionSheetShown = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          AppUpdateSheet.maybeShow(context, info);
        });
      });
    });

    // Start/stop location ping streaming as the attendance state changes.
    // The service itself is foreground-only for v1; Sprint E.3.D will add a
    // background service so it keeps streaming when the app is closed.
    ref.watch(bootstrapPingServiceProvider);

    // Consume a queued push-notification deep link the moment BOTH:
    //   - the pending route changes (so warm taps on /home still fire even
    //     though nothing else changed)
    //   - groups have a value (so the chat screen doesn't mount with a
    //     "Chat" placeholder before /me/groups returns)
    final pendingHolder = ref.watch(pendingDeepLinkProvider);
    final pendingRoute = pendingHolder.route;
    final groupsReady = ref.watch(groupsControllerProvider).hasValue;
    if (pendingRoute != null && groupsReady) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final taken = pendingHolder.consume();
        if (taken != null) {
          context.push(taken);
        }
      });
    }

    return AppLifecycleBackgroundPingBootstrap(
      // Root screen: pressing Back must MINIMIZE the app (like WhatsApp),
      // not destroy the activity — destroying it kills the realtime
      // connection and "disconnects" the user without them realizing.
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          // Ask Android to send us to the background (Home-button behavior).
          const MethodChannel('arena/app')
              .invokeMethod('moveToBackground')
              .catchError((_) => null);
        },
        child: Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text(labelFor(_index)),
        // ── Left: Add Task (managers) + My To-Do (everyone) ──
        leadingWidth: canAssign ? 104 : 56,
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(width: 4),
            if (canAssign)
              IconButton(
                tooltip: 'Add Task',
                icon: const Icon(Icons.add_box_outlined),
                onPressed: () async {
                  final ok = await CreateTaskFromMessageSheet.show(context);
                  if (ok == true) ref.invalidate(tasksListProvider);
                },
              ),
            IconButton(
              tooltip: 'My To-Do',
              icon: const Icon(Icons.add_task),
              onPressed: () async {
                // Work-gate: personal task only while checked-in + active.
                if (!await ref.ensureCheckedIn(context)) return;
                if (context.mounted) await _SelfTaskSheet.show(context);
              },
            ),
          ],
        ),
        // ── Right: Shoot Calendar + Notifications ──
        actions: [
          if (user != null)
            IconButton(
              tooltip: 'Shoot calendar',
              onPressed: () => context.push('/shoots'),
              icon: const Icon(Icons.camera_alt_outlined),
            ),
          IconButton(
            tooltip: 'Notifications',
            onPressed: () => context.push('/inbox'),
            icon: _BellWithBadge(unread: inboxCount),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: switch (_index) {
        0 => const DashboardScreen(embedded: true),
        1 => const TasksListTab(),
        2 => const ChatsListTab(),
        3 => _MeTab(user: user),
        _ => const SizedBox.shrink(),
      },
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          for (var i = 0; i < _tabs.length; i++)
            NavigationDestination(
              icon: Icon(_tabs[i].icon),
              selectedIcon: Icon(_tabs[i].activeIcon),
              label: labelFor(i),
            ),
        ],
      ),
        ),
      ),
    );
  }
}

class _TabSpec {
  final String label;
  final IconData icon;
  final IconData activeIcon;
  const _TabSpec(this.label, this.icon, this.activeIcon);
}

class _BellWithBadge extends StatelessWidget {
  final int unread;
  const _BellWithBadge({required this.unread});

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        const Icon(Icons.notifications_outlined),
        if (unread > 0)
          Positioned(
            right: -4,
            top: -4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
              decoration: BoxDecoration(
                color: AppColors.arenaRed,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              alignment: Alignment.center,
              child: Text(
                unread > 99 ? '99+' : '$unread',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  height: 1,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _PlaceholderTab extends StatelessWidget {
  final String label;
  const _PlaceholderTab({required this.label});

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.construction, size: 64, color: Colors.grey),
            const SizedBox(height: 12),
            Text(
              '$label — coming soon',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ),
      );
}

class _MeTab extends ConsumerWidget {
  final UserModel? user;
  const _MeTab({required this.user});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (user == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView(
      padding: AppSpacing.page,
      children: [
        // ── Profile header ─────────────────────────────────
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                UserAvatar(
                  name: user!.name,
                  avatarUrl: user!.avatarUrl,
                  size: 64,
                  backgroundColor: AppColors.arenaBlue,
                ),
                const SizedBox(width: AppSpacing.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.check_circle,
                              size: 13, color: AppColors.success,),
                          AppSpacing.hXs,
                          Text(
                            'Signed in as',
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(color: AppColors.success),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        user!.name,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      AppSpacing.vXs,
                      Text(
                        [user!.jobTitle, user!.department]
                            .whereType<String>()
                            .join(' · '),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      Text(
                        user!.email,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        AppSpacing.vLg,

        // ── Attendance (Sprint E.2): unified check-in/out + duty toggle ──
        // (the old standalone _DutyCard was merged into AttendanceCard
        //  — Away is now a sub-state of "checked in")
        const AttendanceCard(),
        AppSpacing.vSm,

        // ── My profile (avatar + password) ──
        Card(
          child: ListTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.arenaBlueLight,
                borderRadius: AppRadius.rSm,
              ),
              child: const Icon(
                Icons.person_outline,
                color: AppColors.arenaBlue,
              ),
            ),
            title: const Text('My profile'),
            subtitle: const Text('Change photo or password'),
            trailing: const Icon(Icons.chevron_left),
            onTap: () => context.push('/profile'),
          ),
        ),
        AppSpacing.vSm,

        // ── Calendar entry (moved from old Calendar tab) ──
        Card(
          child: ListTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.arenaBlueLight,
                borderRadius: AppRadius.rSm,
              ),
              child: const Icon(
                Icons.calendar_today,
                color: AppColors.arenaBlue,
              ),
            ),
            title: const Text('Calendar'),
            subtitle: const Text('Meetings and events'),
            trailing: const Icon(Icons.chevron_left),
            onTap: () => context.push('/calendar'),
          ),
        ),
        AppSpacing.vSm,

        // ── Quick links (real, working) ────────────────────
        Card(
          child: Column(
            children: [
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: AppRadius.rSm,
                  ),
                  child: const Icon(Icons.workspace_premium_outlined,
                      color: Color(0xFF92400E),),
                ),
                title: const Text('My scorecard'),
                subtitle: const Text('Points, rank & payslip'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/scorecard'),
              ),
              const Divider(height: 1),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDCFCE7),
                    borderRadius: AppRadius.rSm,
                  ),
                  child: const Icon(Icons.beach_access_outlined,
                      color: Color(0xFF16A34A),),
                ),
                title: const Text('My leave'),
                subtitle: const Text('Request & track vacation'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/leaves'),
              ),
              // Create group — managers only (custom brainstorming rooms).
              if (user?.isOwner == true ||
                  user?.isAccountManager == true ||
                  user?.teamRole == 'department_manager') ...[
                const Divider(height: 1),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.arenaBlueLight,
                      borderRadius: AppRadius.rSm,
                    ),
                    child: const Icon(Icons.group_add_outlined,
                        color: AppColors.arenaBlue,),
                  ),
                  title: const Text('Create group'),
                  subtitle: const Text('Custom brainstorming room'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/groups/new'),
                ),
              ],
              // Social tally — social-media people (and owners).
              if (user?.isOwner == true ||
                  (user?.department ?? '').toLowerCase().contains('social') ||
                  (user?.jobTitle ?? '').toLowerCase().contains('social')) ...[
                const Divider(height: 1),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.arenaBlueLight,
                      borderRadius: AppRadius.rSm,
                    ),
                    child: const Icon(Icons.touch_app_outlined,
                        color: AppColors.arenaBlue,),
                  ),
                  title: const Text('Social tally'),
                  subtitle: const Text('Post / story / reel counter'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/social'),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),

        // ── Logout ─────────────────────────────────────────
        OutlinedButton.icon(
          onPressed: () async {
            final confirm = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Log out'),
                content: const Text('Are you sure you want to log out?'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Confirm'),
                  ),
                ],
              ),
            );
            if (confirm == true) {
              await ref.read(authControllerProvider.notifier).logout();
            }
          },
          icon: const Icon(Icons.logout, color: AppColors.arenaRed),
          label: const Text(
            'Log out',
            style: TextStyle(color: AppColors.arenaRed),
          ),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            side: const BorderSide(color: AppColors.arenaRed),
          ),
        ),
      ],
    );
  }
}

/// Bottom sheet for the "Tasks I assign to myself" personal to-do flow.
/// Bare minimum form: title (required), description (optional), due date
/// (optional). Brand picker is intentionally omitted in v1 to keep the
/// flow one-tap — most personal todos aren't brand-scoped.
class _SelfTaskSheet extends ConsumerStatefulWidget {
  const _SelfTaskSheet();

  static Future<void> show(BuildContext context) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (_) => const _SelfTaskSheet(),
      );

  @override
  ConsumerState<_SelfTaskSheet> createState() => _SelfTaskSheetState();
}

class _SelfTaskSheetState extends ConsumerState<_SelfTaskSheet> {
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  DateTime? _dueAt;      // date only
  int? _dueHour;         // 0–23, picked separately
  String _priority = 'medium';
  bool _saving = false;
  String? _error;        // shown as a visible banner inside the sheet

  List<Map<String, dynamic>> _brands = const [];
  bool _loadingBrands = true;
  final Set<int> _selectedBrandIds = {};

  @override
  void initState() {
    super.initState();
    _loadBrands();
  }

  Future<void> _loadBrands() async {
    try {
      final repo = ref.read(tasksRepositoryProvider);
      final list = await repo.listMyBrands();
      if (!mounted) return;
      // Hide the "Direct Messages" sentinel brand — it's not a real client.
      final filtered = list
          .where((b) => (b['slug'] as String?) != 'direct-messages')
          .toList();
      setState(() {
        _brands = filtered;
        _loadingBrands = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingBrands = false);
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  static Color? _parseBrandColor(String? hex) {
    if (hex == null || hex.isEmpty) return null;
    var h = hex.replaceAll('#', '').trim();
    if (h.length == 6) h = 'FF$h';
    if (h.length != 8) return null;
    final value = int.tryParse(h, radix: 16);
    if (value == null) return null;
    return Color(value);
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueAt ?? now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _dueAt = picked);
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _dueHour ?? 18, minute: 0),
    );
    if (t != null) setState(() => _dueHour = t.hour);
  }

  /// Combine the picked date + hour into a single due timestamp.
  DateTime? _resolvedDue() {
    if (_dueAt == null) return null;
    final h = _dueHour ?? 18;
    return DateTime(_dueAt!.year, _dueAt!.month, _dueAt!.day, h, 0);
  }

  Future<void> _save() async {
    setState(() => _error = null);
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Please enter a task title.');
      return;
    }
    if (_selectedBrandIds.isEmpty) {
      setState(() => _error = 'Please pick at least one client.');
      return;
    }
    setState(() => _saving = true);
    try {
      final repo = ref.read(tasksRepositoryProvider);
      await repo.createSelfTask(
        title: title,
        description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
        brandIds: _selectedBrandIds.toList(),
        dueAt: _resolvedDue(),
        priority: _priority,
      );
      if (!mounted) return;
      ref.invalidate(tasksListProvider);
      Navigator.of(context).pop();
      final n = _selectedBrandIds.length;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('✓ ${n == 1 ? 'Task added' : '$n tasks added'}')),
      );
    } catch (e) {
      if (!mounted) return;
      final s = e.toString();
      setState(() => _error = s.contains('SocketException') ||
              s.contains('Connection')
          ? 'No connection. Check your internet and try again.'
          : 'Couldn’t add the task. Please try again.',);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    // Force LTR on this sheet so labels like "What is the task?" and
    // "Brand (pick one or more) *" render with the punctuation on the
    // right where it belongs (otherwise inherited RTL flips them).
    return Directionality(
      textDirection: TextDirection.ltr,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + viewInsets),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Icon(Icons.add_task, color: AppColors.arenaBlue),
              const SizedBox(width: 8),
              Text(
                'Add a personal task',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _titleCtrl,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'What is the task?',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _descCtrl,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Details (optional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 14),
          const Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              'Clients (pick one or more) *',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.ink2,
              ),
            ),
          ),
          const SizedBox(height: 6),
          if (_loadingBrands)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 8),
                  Text('Loading clients…',
                      style: TextStyle(fontSize: 12.5, color: AppColors.ink3),),
                ],
              ),
            )
          else if (_brands.isEmpty)
            const Text(
              'No clients available.',
              style: TextStyle(fontSize: 12, color: AppColors.ink3),
            )
          else
            SizedBox(
              height: 38,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _brands.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (ctx, i) {
                  final b = _brands[i];
                  final id = (b['id'] as num).toInt();
                  final name = b['name'] as String? ?? '?';
                  final color =
                      _parseBrandColor(b['primary_color'] as String?) ??
                          AppColors.arenaBlue;
                  final selected = _selectedBrandIds.contains(id);
                  final anySelected = _selectedBrandIds.isNotEmpty;
                  return GestureDetector(
                    onTap: () => setState(() {
                      if (selected) {
                        _selectedBrandIds.remove(id);
                      } else {
                        _selectedBrandIds.add(id);
                      }
                    }),
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 150),
                      // Dim the unselected pills once something is selected.
                      opacity: !anySelected || selected ? 1 : 0.4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 7,),
                        decoration: BoxDecoration(
                          color: selected
                              ? color.withValues(alpha: 0.15)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: selected ? color : Colors.grey.shade300,
                            width: selected ? 1.5 : 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircleAvatar(
                              radius: 9,
                              backgroundColor: color,
                              child: Text(
                                name.characters.first.toUpperCase(),
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              name,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: selected ? color : AppColors.ink2,
                              ),
                            ),
                            if (selected) ...[
                              const SizedBox(width: 5),
                              Icon(Icons.check_circle, size: 14, color: color),
                            ],
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickDate,
                  icon: const Icon(Icons.event, size: 18),
                  label: Text(
                    _dueAt == null
                        ? 'Date'
                        : '${_dueAt!.day}/${_dueAt!.month}/${_dueAt!.year}',
                    overflow: TextOverflow.ellipsis,
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _dueAt == null ? null : _pickTime,
                  icon: const Icon(Icons.schedule, size: 18),
                  label: Text(
                    _dueHour == null
                        ? 'Time'
                        : TimeOfDay(hour: _dueHour!, minute: 0)
                            .format(context),
                    overflow: TextOverflow.ellipsis,
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
          if (_dueAt != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () =>
                    setState(() {
                      _dueAt = null;
                      _dueHour = null;
                    }),
                child: const Text('Clear due date'),
              ),
            ),
          const SizedBox(height: 6),
          const Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              'Priority',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.ink2,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: const [
              ('low', 'Low', Color(0xFFD1FAE5), Color(0xFF065F46)),
              ('medium', 'Medium', Color(0xFFFEF3C7), Color(0xFF92400E)),
              ('high', 'High', Color(0xFFFFEDD5), Color(0xFF9A3412)),
              ('urgent', 'Urgent', Color(0xFFFEE2E2), Color(0xFFB91C1C)),
            ].map((t) {
              final value = t.$1;
              final label = t.$2;
              final bg = t.$3;
              final fg = t.$4;
              final selected = _priority == value;
              return GestureDetector(
                onTap: () => setState(() => _priority = value),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: selected ? bg : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: selected ? fg : Colors.grey.shade300,
                      width: selected ? 1.5 : 1,
                    ),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: selected ? fg : AppColors.ink3,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            InlineErrorBanner(message: _error!),
          ],
          const SizedBox(height: 16),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.arenaBlue,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(Colors.white),
                    ),
                  )
                : const Icon(Icons.check, color: Colors.white),
            label: const Text(
              'Add task',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
            ),
          ),
        ],
        ),
      ),
    );
  }
}
