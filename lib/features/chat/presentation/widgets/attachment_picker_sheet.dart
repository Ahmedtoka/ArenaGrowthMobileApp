import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/theme/app_colors.dart';

/// Result of the attachment picker — either a [File] to upload, or null if
/// the user cancelled.
enum AttachmentSource { gallery, video, camera, file }

class PickedAttachment {
  final File file;
  final AttachmentSource source;
  const PickedAttachment(this.file, this.source);
}

/// Bottom sheet that lets the user pick what to attach.
class AttachmentPickerSheet extends StatelessWidget {
  const AttachmentPickerSheet({super.key});

  /// Opens the source sheet then the picker. Gallery + Files support
  /// MULTI-select; Camera is inherently single-shot. Returns an empty list
  /// when the user cancels.
  static Future<List<PickedAttachment>> show(BuildContext context) async {
    final source = await showModalBottomSheet<AttachmentSource>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => const AttachmentPickerSheet(),
    );
    if (source == null) return const [];
    return _pick(source);
  }

  static Future<List<PickedAttachment>> _pick(AttachmentSource source) async {
    switch (source) {
      case AttachmentSource.gallery:
        final picker = ImagePicker();
        final picked = await picker.pickMultiImage(imageQuality: 85);
        return [
          for (final p in picked) PickedAttachment(File(p.path), source),
        ];
      case AttachmentSource.video:
        final picker = ImagePicker();
        final picked = await picker.pickVideo(source: ImageSource.gallery);
        if (picked == null) return const [];
        return [PickedAttachment(File(picked.path), source)];
      case AttachmentSource.camera:
        final picker = ImagePicker();
        final picked = await picker.pickImage(
          source: ImageSource.camera,
          imageQuality: 85,
        );
        if (picked == null) return const [];
        return [PickedAttachment(File(picked.path), source)];
      case AttachmentSource.file:
        final result = await FilePicker.platform.pickFiles(
          type: FileType.any,
          withData: false,
          allowMultiple: true,
        );
        if (result == null) return const [];
        return [
          for (final f in result.files)
            if (f.path != null) PickedAttachment(File(f.path!), source),
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(top: 8, bottom: 6),
            decoration: BoxDecoration(
              color: AppColors.ink3.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(
              children: [
                Text(
                  'Attach a file',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
              ],
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _PickerTile(
                icon: Icons.photo_library,
                label: 'Gallery',
                color: const Color(0xFF8B5CF6),
                onTap: () =>
                    Navigator.pop(context, AttachmentSource.gallery),
              ),
              _PickerTile(
                icon: Icons.videocam,
                label: 'Video',
                color: const Color(0xFFEF4444),
                onTap: () =>
                    Navigator.pop(context, AttachmentSource.video),
              ),
              _PickerTile(
                icon: Icons.camera_alt,
                label: 'Camera',
                color: const Color(0xFFEC4899),
                onTap: () =>
                    Navigator.pop(context, AttachmentSource.camera),
              ),
              _PickerTile(
                icon: Icons.attach_file,
                label: 'File',
                color: const Color(0xFF3B82F6),
                onTap: () =>
                    Navigator.pop(context, AttachmentSource.file),
              ),
            ],
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

class _PickerTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _PickerTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: Colors.white, size: 28),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: const TextStyle(fontSize: 12, color: AppColors.ink2),
            ),
          ],
        ),
      ),
    );
  }
}
