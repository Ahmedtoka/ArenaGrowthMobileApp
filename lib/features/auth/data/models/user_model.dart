import 'package:freezed_annotation/freezed_annotation.dart';

part 'user_model.freezed.dart';
part 'user_model.g.dart';

/// Mirrors `App\Http\Resources\TeamOS\UserResource` on the Laravel side.
///
/// Run `dart run build_runner build --delete-conflicting-outputs` after
/// editing this file to regenerate `*.freezed.dart` and `*.g.dart`.
@freezed
class UserModel with _$UserModel {
  const factory UserModel({
    required int id,
    required String name,
    required String email,
    String? phone,
    @JsonKey(name: 'job_title') String? jobTitle,
    String? department,
    @JsonKey(name: 'team_role') String? teamRole,
    @JsonKey(name: 'avatar_path') String? avatarPath,
    @JsonKey(name: 'avatar_url') String? avatarUrl,
    @JsonKey(name: 'avatar_color') String? avatarColor,
    String? initials,
    String? locale,
    String? timezone,
    @JsonKey(name: 'status_message') String? statusMessage,
    @JsonKey(name: 'last_seen_at') DateTime? lastSeenAt,
    @Default(true) @JsonKey(name: 'is_active') bool isActive,
    @Default(false) @JsonKey(name: 'is_owner') bool isOwner,
    @Default(false) @JsonKey(name: 'is_department_manager') bool isDepartmentManager,
    @Default(false) @JsonKey(name: 'is_account_manager') bool isAccountManager,
  }) = _UserModel;

  factory UserModel.fromJson(Map<String, dynamic> json) =>
      _$UserModelFromJson(json);
}
