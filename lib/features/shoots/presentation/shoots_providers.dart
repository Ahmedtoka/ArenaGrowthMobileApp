import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import '../../../core/utils/upload_prep.dart';
import '../data/shoot_models.dart';

/// Result of GET /team/shoots: the list + whether the viewer can add/edit.
class ShootsResult {
  final bool canManage;
  final List<Shoot> shoots;
  const ShootsResult(this.canManage, this.shoots);
}

/// All shoots in the default window (this month → +60 days), grouped-ready.
final shootsProvider = FutureProvider.autoDispose<ShootsResult>((ref) async {
  final dio = ref.read(dioClientProvider);
  final res = await dio.get('/team/shoots');
  final data = res.data as Map<String, dynamic>;
  return ShootsResult(
    data['can_manage'] == true,
    ((data['shoots'] ?? []) as List)
        .map((e) => Shoot.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
});

/// Brands + team + types for the "Add to Cuva" form. Loaded on demand.
final shootFormOptionsProvider =
    FutureProvider.autoDispose<ShootFormOptions>((ref) async {
  final dio = ref.read(dioClientProvider);
  final res = await dio.get('/team/shoots/form-options');
  return ShootFormOptions.fromJson(res.data as Map<String, dynamic>);
});

/// Build a multipart body for a shoot with file/image attachments + link URLs.
Future<FormData> _shootForm(
  Map<String, dynamic> payload,
  List<File> files,
  List<String> links,
) async {
  final map = <String, dynamic>{};
  payload.forEach((k, v) {
    if (k == 'collaborators' || v == null) return;
    map[k] = v is int ? v.toString() : v;
  });
  final form = FormData.fromMap(map);

  final collab = (payload['collaborators'] as List?) ?? const [];
  for (var i = 0; i < collab.length; i++) {
    form.fields.add(MapEntry('collaborators[$i]', collab[i].toString()));
  }
  for (var i = 0; i < links.length; i++) {
    form.fields.add(MapEntry('links[$i]', links[i]));
  }
  final prepared = await Future.wait(files.map(UploadPrep.prepare));
  for (final f in prepared) {
    form.files.add(MapEntry(
      'attachments[]',
      await MultipartFile.fromFile(f.path,
          filename: f.path.split(Platform.pathSeparator).last),
    ));
  }
  return form;
}

/// Create a shoot. Caller invalidates [shootsProvider] afterwards.
Future<void> createShoot(
  WidgetRef ref,
  Map<String, dynamic> payload, {
  List<File> files = const [],
  List<String> links = const [],
}) async {
  final dio = ref.read(dioClientProvider);
  if (files.isEmpty && links.isEmpty) {
    await dio.post('/team/shoots', data: payload);
    return;
  }
  await dio.post('/team/shoots', data: await _shootForm(payload, files, links));
}

/// Edit an existing shoot (append attachments). Uses POST + _method=PUT so
/// multipart bodies parse correctly.
Future<void> updateShoot(
  WidgetRef ref,
  int id,
  Map<String, dynamic> payload, {
  List<File> files = const [],
  List<String> links = const [],
}) async {
  final dio = ref.read(dioClientProvider);
  if (files.isEmpty && links.isEmpty) {
    await dio.put('/team/shoots/$id', data: payload);
    return;
  }
  final form = await _shootForm(payload, files, links);
  form.fields.add(const MapEntry('_method', 'PUT'));
  await dio.post('/team/shoots/$id', data: form);
}

/// Cancel a shoot (soft — keeps the row, flags it cancelled).
Future<void> cancelShoot(WidgetRef ref, int id, {String? reason}) async {
  final dio = ref.read(dioClientProvider);
  await dio.post('/team/shoots/$id/cancel', data: {if (reason != null) 'reason': reason});
}
