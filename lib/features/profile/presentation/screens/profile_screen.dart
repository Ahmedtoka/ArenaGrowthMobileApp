import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/errors/api_exception.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/authed_network_image.dart';
import '../../../attendance/presentation/widgets/attendance_card.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../data/repositories/profile_repository.dart';

/// Self-service profile screen: upload avatar + change password.
///
/// Mounts off the home shell's "Me" tab. Renders the user's identity card
/// at the top and two collapsible(ish) action sections below.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  bool _uploadingAvatar = false;

  Future<void> _pickAndUploadAvatar() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 88,
      maxWidth: 1024,
      maxHeight: 1024,
    );
    if (picked == null) return;

    setState(() => _uploadingAvatar = true);
    try {
      final repo = ref.read(profileRepositoryProvider);
      final updated = await repo.uploadAvatar(File(picked.path));
      // Push the refreshed user into auth state so other screens (sidebar
      // tile, mentions list) pick it up immediately without a restart.
      ref.read(authControllerProvider.notifier).setUser(updated);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✓ Avatar updated')),
      );
    } catch (e) {
      if (!mounted) return;
      final msg = switch (e) {
        ApiException(:final message) => message,
        _ => e.toString(),
      };
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: $msg'), backgroundColor: AppColors.arenaRed),
      );
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  Future<void> _openChangePasswordSheet() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const _ChangePasswordSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).valueOrNull;

    if (user == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.appBg,
      appBar: AppBar(
        title: const Text('My account'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _IdentityCard(
            user: user,
            uploading: _uploadingAvatar,
            onPickAvatar: _pickAndUploadAvatar,
          ),
          const SizedBox(height: 12),
          // Attendance — check in / out / break / away. Mounted here too so
          // the "Check in first" gate can deep-link straight to this screen.
          const AttendanceCard(),
          const SizedBox(height: 12),
          _ActionCard(
            icon: Icons.image,
            title: 'Change profile photo',
            subtitle: 'JPG, PNG or WebP — max 4 MB',
            color: AppColors.arenaBlue,
            onTap: _uploadingAvatar ? null : _pickAndUploadAvatar,
            trailing: _uploadingAvatar
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : null,
          ),
          const SizedBox(height: 8),
          _ActionCard(
            icon: Icons.lock_outline,
            title: 'Change password',
            subtitle: 'You will need your current password',
            color: const Color(0xFFB45309),
            onTap: _openChangePasswordSheet,
          ),
        ],
      ),
    );
  }
}

// ─── Identity hero card ────────────────────────────────────────────
class _IdentityCard extends StatelessWidget {
  final dynamic user; // UserModel — duck-typed to avoid an import cycle
  final bool uploading;
  final VoidCallback onPickAvatar;
  const _IdentityCard({
    required this.user,
    required this.uploading,
    required this.onPickAvatar,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
              color: Color(0x14000000),
              blurRadius: 3,
              offset: Offset(0, 1),),
        ],
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: uploading ? null : onPickAvatar,
            child: Stack(
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: _initialBg(user.name as String),
                    shape: BoxShape.circle,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: user.avatarUrl != null
                      ? AuthedNetworkImage(
                          url: user.avatarUrl as String,
                          fit: BoxFit.cover,
                          width: 80,
                          height: 80,
                        )
                      : Center(
                          child: Text(
                            _initials(user.name as String),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 26,
                            ),
                          ),
                        ),
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: AppColors.arenaBlue,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.camera_alt,
                      color: Colors.white,
                      size: 14,
                    ),
                  ),
                ),
                if (uploading)
                  const Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Color(0x66000000),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  user.name as String,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                if (user.jobTitle != null)
                  Text(
                    user.jobTitle as String,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.ink2,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                if (user.department != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    user.department as String,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.ink3,
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  user.email as String,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.ink3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static Color _initialBg(String name) {
    final hues = [
      AppColors.arenaBlue,
      const Color(0xFFEC4899),
      const Color(0xFF10B981),
      const Color(0xFF8B5CF6),
      const Color(0xFFF59E0B),
      const Color(0xFF06B6D4),
      AppColors.arenaRed,
    ];
    final hash = name.codeUnits.fold<int>(0, (a, c) => a + c);
    return hues[hash.abs() % hues.length];
  }

  static String _initials(String name) {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts.first.characters.first + parts.last.characters.first)
        .toUpperCase();
  }
}

// ─── Reusable action card ──────────────────────────────────────────
class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback? onTap;
  final Widget? trailing;
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.ink3,
                      ),
                    ),
                  ],
                ),
              ),
              trailing ??
                  const Icon(Icons.chevron_right,
                      color: AppColors.ink3, size: 22,),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Change password bottom sheet ──────────────────────────────────
class _ChangePasswordSheet extends ConsumerStatefulWidget {
  const _ChangePasswordSheet();

  @override
  ConsumerState<_ChangePasswordSheet> createState() =>
      _ChangePasswordSheetState();
}

class _ChangePasswordSheetState extends ConsumerState<_ChangePasswordSheet> {
  final _current = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();
  bool _saving = false;
  bool _showCurrent = false;
  bool _showNew = false;

  @override
  void dispose() {
    _current.dispose();
    _new.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_current.text.trim().isEmpty) {
      _toast('Enter your current password');
      return;
    }
    if (_new.text.length < 6) {
      _toast('New password must be at least 6 characters');
      return;
    }
    if (_new.text != _confirm.text) {
      _toast('Passwords do not match');
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(profileRepositoryProvider).changePassword(
            currentPassword: _current.text,
            newPassword: _new.text,
          );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✓ Password updated')),
      );
    } catch (e) {
      if (!mounted) return;
      final msg = switch (e) {
        ApiException(:final message) => message,
        _ => e.toString(),
      };
      _toast(msg);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _toast(String m) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
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
            const SizedBox(height: 14),
            const Row(
              children: [
                Icon(Icons.lock_outline, color: Color(0xFFB45309)),
                SizedBox(width: 8),
                Text('Change password',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,),),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _current,
              obscureText: !_showCurrent,
              decoration: InputDecoration(
                labelText: 'Current password',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(_showCurrent
                      ? Icons.visibility_off
                      : Icons.visibility,),
                  onPressed: () =>
                      setState(() => _showCurrent = !_showCurrent),
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _new,
              obscureText: !_showNew,
              decoration: InputDecoration(
                labelText: 'New password (min 6)',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(
                      _showNew ? Icons.visibility_off : Icons.visibility,),
                  onPressed: () => setState(() => _showNew = !_showNew),
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _confirm,
              obscureText: !_showNew,
              decoration: const InputDecoration(
                labelText: 'Confirm new password',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.arenaBlue,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: _saving ? null : _submit,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation(Colors.white),),)
                  : const Icon(Icons.check, color: Colors.white),
              label: const Text('Update password',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w700,),),
            ),
          ],
        ),
      ),
    );
  }
}
