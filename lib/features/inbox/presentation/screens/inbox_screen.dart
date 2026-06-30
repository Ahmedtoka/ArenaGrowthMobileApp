import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/text_direction_util.dart';
import '../../data/models/inbox_item.dart';
import '../controllers/inbox_providers.dart';

class InboxScreen extends ConsumerWidget {
  const InboxScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inboxAsync = ref.watch(inboxProvider);
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: AppColors.appBg,
        appBar: AppBar(
          title: const Text('Inbox'),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => ref.invalidate(inboxProvider),
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(48),
            child: inboxAsync.when(
              loading: () => const SizedBox(height: 48),
              error: (_, __) => const SizedBox(height: 48),
              data: (bundle) => TabBar(
                indicatorColor: Colors.white,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white70,
                labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                tabs: [
                  _CountTab(
                    label: 'Needs reply',
                    count: bundle.redCount,
                    color: AppColors.redBorder,
                  ),
                  _CountTab(
                    label: 'Awaiting approval',
                    count: bundle.orangeCount,
                    color: AppColors.orangeBorder,
                  ),
                  _CountTab(
                    label: 'Approved',
                    count: bundle.greenCount,
                    color: AppColors.greenBorder,
                  ),
                ],
              ),
            ),
          ),
        ),
        body: inboxAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.red),
                  const SizedBox(height: 12),
                  Text('Could not load inbox\n$e',
                      textAlign: TextAlign.center,),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () => ref.invalidate(inboxProvider),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
          data: (b) => TabBarView(
            children: [
              _InboxList(items: b.red, emptyLabel: 'No messages need a reply'),
              _InboxList(items: b.orange, emptyLabel: 'No replies awaiting approval'),
              _InboxList(items: b.green, emptyLabel: 'No recently approved messages'),
            ],
          ),
        ),
      ),
    );
  }
}

class _CountTab extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  const _CountTab({required this.label, required this.count, required this.color});

  @override
  Widget build(BuildContext context) {
    return Tab(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          // Flexible + ellipsis so long labels (e.g. "Awaiting approval")
          // never overflow the fixed-width tab.
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11.5),
            ),
          ),
          if (count > 0) ...[
            const SizedBox(width: 3),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$count',
                style: const TextStyle(
                    fontSize: 10, color: Colors.white, fontWeight: FontWeight.w700,),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _InboxList extends StatelessWidget {
  final List<InboxItem> items;
  final String emptyLabel;
  const _InboxList({required this.items, required this.emptyLabel});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.inbox_outlined, size: 56, color: Colors.grey),
              const SizedBox(height: 12),
              Text(emptyLabel,
                  style: const TextStyle(color: AppColors.ink3),),
            ],
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 4),
      itemBuilder: (ctx, i) => _ItemRow(item: items[i]),
    );
  }
}

class _ItemRow extends StatelessWidget {
  final InboxItem item;
  const _ItemRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final accent = switch (item.importanceStatus) {
      'red' => AppColors.redBorder,
      'orange' => AppColors.orangeBorder,
      'green' => AppColors.greenBorder,
      _ => AppColors.ink3,
    };
    final time = item.markedRedAt ??
        item.markedOrangeAt ??
        item.markedGreenAt ??
        item.createdAt;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () {
          // Jump to the chat. Flash-highlight will need message anchor (TODO).
          context.push('/chat/${item.groupId}');
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 4,
                height: 56,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.brandName ?? item.groupName ?? 'Chat',
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.ink,
                            ),
                          ),
                        ),
                        if (time != null)
                          Text(
                            DateFormat('d/M h:mm a').format(time.toLocal()),
                            style: const TextStyle(
                                fontSize: 11, color: AppColors.ink3,),
                          ),
                      ],
                    ),
                    if (item.sender?.name != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          item.sender!.name,
                          style: const TextStyle(
                              fontSize: 11.5,
                              color: AppColors.ink3,
                              fontWeight: FontWeight.w500,),
                        ),
                      ),
                    if (item.bodyExcerpt != null &&
                        item.bodyExcerpt!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        item.bodyExcerpt!,
                        textDirection: detectBidiDirection(item.bodyExcerpt),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 13, color: AppColors.ink2, height: 1.3,),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
