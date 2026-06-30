import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../data/models/group_attachment.dart';
import 'chat_providers.dart';

part 'group_attachments_providers.g.dart';

@riverpod
Future<List<GroupAttachment>> groupImages(
    GroupImagesRef ref, int groupId,) async {
  final repo = ref.read(chatRepositoryProvider);
  return repo.listImages(groupId);
}

@riverpod
Future<List<GroupAttachment>> groupFiles(
    GroupFilesRef ref, int groupId,) async {
  final repo = ref.read(chatRepositoryProvider);
  return repo.listFiles(groupId);
}

@riverpod
Future<List<GroupLink>> groupLinks(GroupLinksRef ref, int groupId) async {
  final repo = ref.read(chatRepositoryProvider);
  return repo.listLinks(groupId);
}
