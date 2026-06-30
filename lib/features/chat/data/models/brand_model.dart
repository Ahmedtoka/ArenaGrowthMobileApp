import 'package:freezed_annotation/freezed_annotation.dart';

part 'brand_model.freezed.dart';
part 'brand_model.g.dart';

/// Mirrors `App\Http\Resources\TeamOS\BrandResource`.
@freezed
class BrandModel with _$BrandModel {
  const factory BrandModel({
    required int id,
    required String name,
    String? slug,
    @JsonKey(name: 'logo_path') String? logoPath,
    @JsonKey(name: 'logo_url') String? logoUrl,
    @JsonKey(name: 'primary_color') String? primaryColor,
    @JsonKey(name: 'secondary_color') String? secondaryColor,
    String? status,
    @JsonKey(name: 'account_manager_id') int? accountManagerId,
  }) = _BrandModel;

  factory BrandModel.fromJson(Map<String, dynamic> json) =>
      _$BrandModelFromJson(json);
}
