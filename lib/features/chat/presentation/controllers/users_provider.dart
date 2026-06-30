import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/providers/app_providers.dart';
import '../../../auth/data/models/user_model.dart';
import '../../data/repositories/users_repository.dart';

part 'users_provider.g.dart';

@Riverpod(keepAlive: true)
UsersRepository usersRepository(UsersRepositoryRef ref) {
  final client = ref.watch(dioClientProvider);
  return UsersRepository(client);
}

/// Search users for the @mention autocomplete.
///
/// Family on `(groupId, query)`. Returns empty list for very short queries
/// to avoid hammering the API on every keystroke.
@riverpod
Future<List<UserModel>> mentionableUsers(
  MentionableUsersRef ref,
  ({int groupId, String query}) args,
) async {
  final repo = ref.read(usersRepositoryProvider);
  return repo.search(
    query: args.query,
    groupId: args.groupId,
    limit: 8,
  );
}
