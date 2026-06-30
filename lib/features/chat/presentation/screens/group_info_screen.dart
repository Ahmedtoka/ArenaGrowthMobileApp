import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/providers/app_providers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/text_direction_util.dart';
import '../../../../core/widgets/authed_network_image.dart';
import '../../data/models/group_attachment.dart';
import '../controllers/group_attachments_providers.dart';
import '../controllers/groups_controller.dart';

/// WhatsApp-style group info screen with media/files/links tabs.
class GroupInfoScreen extends ConsumerWidget {
  final int groupId;
  const GroupInfoScreen({super.key, required this.groupId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final group = ref
        .watch(groupsControllerProvider)
        .valueOrNull
        ?.where((g) => g.id == groupId)
        .firstOrNull;

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: AppColors.appBg,
        appBar: AppBar(
          title: Text(group?.name ?? 'Group info'),
          bottom: const TabBar(
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: [
              Tab(icon: Icon(Icons.photo_library), text: 'Media'),
              Tab(icon: Icon(Icons.insert_drive_file), text: 'Files'),
              Tab(icon: Icon(Icons.link), text: 'Links'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _ImagesTab(groupId: groupId),
            _FilesTab(groupId: groupId),
            _LinksTab(groupId: groupId),
          ],
        ),
      ),
    );
  }
}

class _ImagesTab extends ConsumerWidget {
  final int groupId;
  const _ImagesTab({required this.groupId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(groupImagesProvider(groupId));
    return _withState(
      async,
      () => ref.invalidate(groupImagesProvider(groupId)),
      (images) {
      if (images.isEmpty) return const _EmptyState(label: 'No photos yet');
      return GridView.builder(
        padding: const EdgeInsets.all(2),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 2,
          crossAxisSpacing: 2,
        ),
        itemCount: images.length,
        itemBuilder: (ctx, i) {
          final att = images[i];
          return InkWell(
            onTap: () => _openViewer(context, att),
            child: AuthedNetworkImage(
              url: att.downloadUrl,
              fit: BoxFit.cover,
            ),
          );
        },
      );
    },
    );
  }

  void _openViewer(BuildContext context, GroupAttachment att) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Consumer(
        builder: (ctx, ref, _) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            title: Text(att.originalName ?? 'Image',
                style: const TextStyle(fontSize: 14),),
            actions: [
              IconButton(
                icon: const Icon(Icons.share),
                tooltip: 'Share',
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(ctx);
                  try {
                    await ref
                        .read(attachmentDownloaderProvider)
                        .downloadAndShare(
                          att.downloadUrl,
                          filename: att.originalName,
                        );
                  } catch (e) {
                    messenger.showSnackBar(
                      SnackBar(content: Text('Share failed: $e')),
                    );
                  }
                },
              ),
              IconButton(
                icon: const Icon(Icons.download),
                tooltip: 'Download',
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(ctx);
                  try {
                    await ref
                        .read(attachmentDownloaderProvider)
                        .downloadAndOpen(
                          att.downloadUrl,
                          filename: att.originalName,
                          mimeType: att.mimeType,
                        );
                  } catch (e) {
                    messenger.showSnackBar(
                      SnackBar(content: Text('Download failed: $e')),
                    );
                  }
                },
              ),
            ],
          ),
          body: Center(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 4,
              child:
                  AuthedNetworkImage(url: att.downloadUrl, fit: BoxFit.contain),
            ),
          ),
        ),
      ),
    ),);
  }
}

class _FilesTab extends ConsumerWidget {
  final int groupId;
  const _FilesTab({required this.groupId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(groupFilesProvider(groupId));
    return _withState(
      async,
      () => ref.invalidate(groupFilesProvider(groupId)),
      (files) {
        if (files.isEmpty) return const _EmptyState(label: 'No files yet');
        return ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: files.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (ctx, i) => _FileRow(att: files[i]),
        );
      },
    );
  }
}

class _FileRow extends ConsumerWidget {
  final GroupAttachment att;
  const _FileRow({required this.att});

  IconData _icon() {
    final m = att.mimeType ?? '';
    if (m.contains('pdf')) return Icons.picture_as_pdf;
    if (m.contains('zip') || m.contains('rar')) return Icons.archive;
    if (m.contains('word') || m.contains('document')) return Icons.description;
    if (m.contains('sheet') || m.contains('excel')) return Icons.table_chart;
    return Icons.insert_drive_file;
  }

  String _size(int? b) {
    if (b == null) return '';
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(attachmentDownloaderProvider).downloadAndOpen(
            att.downloadUrl,
            filename: att.originalName,
            mimeType: att.mimeType,
          );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not open: $e')));
    }
  }

  Future<void> _share(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(attachmentDownloaderProvider).downloadAndShare(
            att.downloadUrl,
            filename: att.originalName,
          );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Share failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      tileColor: Colors.white,
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppColors.arenaBlue,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(_icon(), color: Colors.white, size: 22),
      ),
      title: Text(
        att.originalName ?? 'File',
        textDirection: detectBidiDirection(att.originalName),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        [_size(att.sizeBytes), att.senderName]
            .whereType<String>()
            .where((s) => s.isNotEmpty)
            .join(' · '),
        style: const TextStyle(fontSize: 11.5, color: AppColors.ink3),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.share, size: 18),
            color: AppColors.ink3,
            onPressed: () => _share(context, ref),
            tooltip: 'Share',
          ),
          IconButton(
            icon: const Icon(Icons.download, size: 18),
            color: AppColors.ink3,
            onPressed: () => _open(context, ref),
            tooltip: 'Download',
          ),
        ],
      ),
      onTap: () => _open(context, ref),
    );
  }
}

class _LinksTab extends ConsumerWidget {
  final int groupId;
  const _LinksTab({required this.groupId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(groupLinksProvider(groupId));
    return _withState(
      async,
      () => ref.invalidate(groupLinksProvider(groupId)),
      (links) {
        if (links.isEmpty) return const _EmptyState(label: 'No links yet');
        return ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: links.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (ctx, i) => _LinkRow(link: links[i]),
        );
      },
    );
  }
}

class _LinkRow extends StatelessWidget {
  final GroupLink link;
  const _LinkRow({required this.link});

  Future<void> _open() async {
    final uri = Uri.tryParse(link.url);
    if (uri == null) return;
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      tileColor: Colors.white,
      leading: const CircleAvatar(
        backgroundColor: AppColors.arenaBlueLight,
        child: Icon(Icons.link, color: AppColors.arenaBlue, size: 20),
      ),
      title: Text(
        link.url,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 13, color: AppColors.arenaBlue),
      ),
      subtitle: Text(
        [
          link.senderName,
          if (link.createdAt != null)
            DateFormat('d/M h:mm a').format(link.createdAt!.toLocal()),
        ]
            .whereType<String>()
            .where((s) => s.isNotEmpty)
            .join(' · '),
        style: const TextStyle(fontSize: 11.5, color: AppColors.ink3),
      ),
      onTap: _open,
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String label;
  const _EmptyState({required this.label});

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.folder_open, size: 56, color: Colors.grey),
            const SizedBox(height: 12),
            Text(label, style: const TextStyle(color: AppColors.ink3)),
          ],
        ),
      );
}

/// Helper to render any AsyncValue with refresh + loading + error.
/// Takes a refresh callback so we don't fight Riverpod's typing.
Widget _withState<T>(
  AsyncValue<T> async,
  VoidCallback onRefresh,
  Widget Function(T data) build,
) {
  return RefreshIndicator(
    onRefresh: () async => onRefresh(),
    child: async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ListView(
        children: [
          const SizedBox(height: 100),
          Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.red),
                  const SizedBox(height: 12),
                  Text('Could not load: $e', textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: onRefresh,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      data: build,
    ),
  );
}
