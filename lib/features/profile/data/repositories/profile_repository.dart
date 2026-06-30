import 'dart:io';

import 'package:dio/dio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/constants/api_constants.dart';
import '../../../../core/network/dio_client.dart';
import '../../../../core/providers/app_providers.dart';
import '../../../auth/data/models/user_model.dart';

part 'profile_repository.g.dart';

@Riverpod(keepAlive: true)
ProfileRepository profileRepository(ProfileRepositoryRef ref) {
  return ProfileRepository(ref.watch(dioClientProvider));
}

/// Self-service profile endpoints — avatar upload and password change.
class ProfileRepository {
  final DioClient _client;
  const ProfileRepository(this._client);

  /// POST /api/team/me/avatar  (multipart, key=avatar)
  /// Returns the refreshed user (so the caller can update its local cache).
  Future<UserModel> uploadAvatar(File file) async {
    final fileName = file.path.split('/').last;
    final form = FormData.fromMap({
      'avatar': await MultipartFile.fromFile(
        file.path,
        filename: fileName,
      ),
    });
    final res = await _client.post(ApiConstants.myAvatar, data: form);
    final data = res.data as Map<String, dynamic>;
    return UserModel.fromJson(data['user'] as Map<String, dynamic>);
  }

  /// POST /api/team/me/password
  /// Throws a typed exception with the server's message on 422.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    await _client.post(
      ApiConstants.myPassword,
      data: {
        'current_password': currentPassword,
        'password': newPassword,
        'password_confirmation': newPassword,
      },
    );
  }
}
