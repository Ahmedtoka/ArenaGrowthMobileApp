import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/providers/app_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimens.dart';
import '../../../core/utils/text_direction_util.dart';
import '../../../core/widgets/authed_network_image.dart';
import '../../../core/widgets/status_pill.dart';
import '../data/shoot_models.dart';
import 'add_shoot_sheet.dart';

/// Read-only shoot detail — everyone on the team can open a shoot to see the
/// brief, crew and attachments. Managers get an Edit button.
class ShootDetailSheet extends ConsumerWidget {
  final Shoot shoot;
  final bool canManage;
  const ShootDetailSheet({super.key, required this.shoot, required this.canManage});

  static Future<void> show(BuildContext context,
          {required Shoot shoot, required bool canManage,}) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: AppRadius.sheetTop,
        ),
        builder: (_) => ShootDetailSheet(shoot: shoot, canManage: canManage),
      );

  Color get _brandColor => _parseHex(shoot.brandColor) ?? AppColors.arenaBlue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final types = shoot.type.split(',').where((t) => t.trim().isNotEmpty).toList();
    final images = shoot.attachments.where((a) => a.isImage).toList();
    final files = shoot.attachments.where((a) => !a.isImage && !a.isLink).toList();
    final links = shoot.attachments.where((a) => a.isLink).toList();

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.xl,),
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: AppSpacing.md),
              decoration: BoxDecoration(
                  color: AppColors.divider,
                  borderRadius: BorderRadius.circular(4),),
            ),
          ),
          // ── Header ──
          Row(
            children: [
              Container(width: 10, height: 10, decoration: BoxDecoration(color: _brandColor, shape: BoxShape.circle)),
              AppSpacing.hSm,
              Expanded(
                child: Text(shoot.brandName ?? 'Shoot',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: _brandColor),),
              ),
              _statusPill(shoot.status),
            ],
          ),
          const SizedBox(height: 6),
          Text(shoot.title,
              textDirection: detectBidiDirection(shoot.title),
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),),
          if (types.isNotEmpty) ...[
            AppSpacing.vSm,
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final t in types)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                      color: AppColors.arenaBlue.withValues(alpha: 0.10),
                      borderRadius: AppRadius.rLg,),
                  child: Text(t,
                      style: const TextStyle(
                          fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.arenaBlue,),),
                ),
            ],),
          ],
          AppSpacing.vLg,

          // ── Facts ──
          _factRow(Icons.event, _dateLabel()),
          if ((shoot.locationLabel ?? shoot.location) != null)
            _factRow(Icons.location_on_outlined, shoot.locationLabel ?? shoot.location!),
          if ((shoot.notes ?? '').isNotEmpty)
            _factRow(Icons.sticky_note_2_outlined, shoot.notes!),

          // ── Crew ──
          if (shoot.team.isNotEmpty) ...[
            AppSpacing.vLg,
            const Text('Crew on set',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.ink2),),
            AppSpacing.vSm,
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final m in shoot.team)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                      color: AppColors.appBg,
                      borderRadius: AppRadius.rLg,
                      border: Border.all(color: AppColors.divider),),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (m.id == shoot.leadId) ...[
                      const Icon(Icons.star, size: 13, color: AppColors.warning),
                      AppSpacing.hXs,
                    ],
                    Text(m.name, style: const TextStyle(fontSize: 12.5)),
                  ],),
                ),
            ],),
          ],

          // ── Attachments ──
          if (shoot.attachments.isNotEmpty) ...[
            const SizedBox(height: 18),
            const Text('Attachments',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.ink2),),
            AppSpacing.vSm,
            if (images.isNotEmpty)
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final a in images)
                  GestureDetector(
                    onTap: () => ref.read(attachmentDownloaderProvider).downloadAndOpen(
                          a.url ?? '', filename: a.name, mimeType: a.mime,),
                    child: ClipRRect(
                      borderRadius: AppRadius.rSm,
                      child: AuthedNetworkImage(
                          url: a.url ?? '', width: 92, height: 92, fit: BoxFit.cover,),
                    ),
                  ),
              ],),
            for (final a in files)
              _attachRow(Icons.insert_drive_file_outlined, a.name ?? 'File',
                  () => ref.read(attachmentDownloaderProvider).downloadAndOpen(
                        a.url ?? '', filename: a.name, mimeType: a.mime,),),
            for (final a in links)
              _attachRow(Icons.link, a.name ?? a.url ?? 'Link', () async {
                final u = Uri.tryParse(a.url ?? '');
                if (u != null) await launchUrl(u, mode: LaunchMode.externalApplication);
              }),
          ],

          // ── Edit (managers) ──
          if (canManage) ...[
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Edit shoot'),
                onPressed: () {
                  Navigator.of(context).pop();
                  AddShootSheet.show(context, existing: shoot);
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _dateLabel() {
    final parts = <String>[shoot.date];
    if (shoot.startTime != null) {
      parts.add('· ${shoot.startTime}${shoot.endTime != null ? '–${shoot.endTime}' : ''}');
    }
    return parts.join(' ');
  }

  Widget _factRow(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 17, color: AppColors.ink3),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                textDirection: detectBidiDirection(text),
                style: const TextStyle(fontSize: 13.5, color: AppColors.ink),),
          ),
        ],),
      );

  Widget _attachRow(IconData icon, String label, VoidCallback onTap) => InkWell(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(top: 6),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.appBg,
            borderRadius: AppRadius.rSm,
            border: Border.all(color: AppColors.divider),
          ),
          child: Row(children: [
            Icon(icon, size: 18, color: AppColors.arenaBlue),
            AppSpacing.hSm,
            Expanded(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13),),),
            const Icon(Icons.open_in_new, size: 15, color: AppColors.ink3),
          ],),
        ),
      );

  Widget _statusPill(String status) {
    final c = switch (status) {
      'cancelled' => AppColors.arenaRed,
      'delivered' => const Color(0xFF16A34A),
      'shot' || 'editing' || 'in_progress' => AppColors.warning,
      _ => AppColors.arenaBlue,
    };
    return StatusPill(status.replaceAll('_', ' '), color: c);
  }

  static Color? _parseHex(String? hex) {
    if (hex == null) return null;
    var h = hex.replaceAll('#', '');
    if (h.length == 6) h = 'FF$h';
    final v = int.tryParse(h, radix: 16);
    return v == null ? null : Color(v);
  }
}
