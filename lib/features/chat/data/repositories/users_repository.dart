import '../../../../core/constants/api_constants.dart';
import '../../../../core/network/dio_client.dart';
import '../../../auth/data/models/user_model.dart';

class UsersRepository {
  final DioClient _client;
  UsersRepository(this._client);

  /// GET /api/team/users?search=<q>&group_id=<id>&limit=<n>
  ///
  /// Used by the @mention autocomplete in the composer. Limiting to the
  /// current group narrows results to people who can actually be mentioned.
  Future<List<UserModel>> search({
    String? query,
    int? groupId,
    int limit = 10,
  }) async {
    final res = await _client.get(
      ApiConstants.users,
      query: {
        if (query != null && query.isNotEmpty) 'search': query,
        if (groupId != null) 'group_id': groupId,
        'active': 1,
        'limit': limit,
      },
    );
    final data = res.data as Map<String, dynamic>;
    final list = (data['users'] ?? data['data'] ?? []) as List<dynamic>;
    return list
        .map((u) => UserModel.fromJson(u as Map<String, dynamic>))
        .toList();
  }
}
