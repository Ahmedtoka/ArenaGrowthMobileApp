import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/constants/api_constants.dart';
import '../../../../core/providers/app_providers.dart';
import '../../data/models/inbox_item.dart';

part 'inbox_providers.g.dart';

@riverpod
Future<InboxBundle> inbox(InboxRef ref) async {
  final client = ref.read(dioClientProvider);
  final res = await client.get(ApiConstants.myInbox);
  final data = res.data as Map<String, dynamic>;
  final counts = (data['counts'] as Map<String, dynamic>? ?? const {});
  return InboxBundle(
    redCount: (counts['red'] ?? 0) as int,
    orangeCount: (counts['orange'] ?? 0) as int,
    greenCount: (counts['green'] ?? 0) as int,
    red: ((data['red'] ?? const []) as List)
        .map((e) => InboxItem.fromJson(e as Map<String, dynamic>))
        .toList(),
    orange: ((data['orange'] ?? const []) as List)
        .map((e) => InboxItem.fromJson(e as Map<String, dynamic>))
        .toList(),
    green: ((data['green'] ?? const []) as List)
        .map((e) => InboxItem.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}
