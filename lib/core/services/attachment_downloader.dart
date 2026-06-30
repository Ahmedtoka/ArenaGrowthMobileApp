import 'dart:io';

import 'package:dio/dio.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../network/dio_client.dart';
import '../widgets/authed_network_image.dart';

/// Sprint Q — single source of truth for authenticated downloads.
///
/// All file URLs in the system (chat attachments, task attachments,
/// completion files, voice notes) sit behind Sanctum and require a
/// `Authorization: Bearer <token>` header. Launching them in the OS
/// browser fails with 401 because the browser has no token.
///
/// This service:
///   1. Resolves the URL to an absolute one (handles `/team/...`,
///      `/api/team/...`, `/storage/...`).
///   2. Pulls the bytes through Dio (the auth interceptor adds the
///      bearer token automatically).
///   3. Writes to a cached location so repeated taps don't re-download.
///   4. Optionally opens it with the OS default app, or shares it
///      through the native share sheet.
class AttachmentDownloader {
  final DioClient _client;
  AttachmentDownloader(this._client);

  /// Downloads [url] (relative or absolute) into the app's documents
  /// dir under `arena_downloads/`. Skips the network call if the file
  /// already exists with a non-zero size — handy when the user taps
  /// the same chip twice in a row.
  ///
  /// [filename] is the on-disk name; if omitted we derive one from the
  /// URL or fall back to `download.bin`.
  ///
  /// [onProgress] is `(received, total)` — `total` is `-1` if the
  /// server doesn't send `Content-Length`.
  Future<File> download(
    String url, {
    String? filename,
    void Function(int received, int total)? onProgress,
  }) async {
    final absolute = AuthedNetworkImage.resolve(url);
    final dir = await _ensureDir();
    final safe = _safeFilename(filename, fallbackUrl: absolute);
    final path = p.join(dir.path, safe);
    final file = File(path);

    // Cache hit: don't re-download something already in our scratch dir.
    if (await file.exists() && (await file.length()) > 0) {
      return file;
    }

    await _client.dio.download(
      absolute,
      path,
      onReceiveProgress: onProgress,
      options: Options(
        responseType: ResponseType.bytes,
        // 5xx still throws; 4xx surfaces as a parsable error body.
        validateStatus: (s) => s != null && s < 500,
      ),
    );
    if (!await file.exists() || (await file.length()) == 0) {
      throw Exception('Download produced an empty file.');
    }
    return file;
  }

  /// Convenience: download then hand the file to the OS to open with
  /// its default app (Adobe Reader, photo viewer, etc).
  Future<OpenResult> downloadAndOpen(
    String url, {
    String? filename,
    String? mimeType,
  }) async {
    final file = await download(url, filename: filename);
    return OpenFilex.open(file.path, type: mimeType);
  }

  /// Convenience: download then push it through the native share sheet
  /// so the user can forward to WhatsApp, Mail, Drive, etc.
  Future<void> downloadAndShare(
    String url, {
    String? filename,
    String? subject,
    String? text,
  }) async {
    final file = await download(url, filename: filename);
    await Share.shareXFiles(
      [XFile(file.path)],
      subject: subject,
      text: text,
    );
  }

  /// Quick text-only share — no download needed.
  Future<void> shareText(String text, {String? subject}) {
    return Share.share(text, subject: subject);
  }

  Future<Directory> _ensureDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, 'arena_downloads'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Strips path separators and reserved chars; falls back to the URL
  /// tail when the caller didn't supply a filename.
  String _safeFilename(String? requested, {required String fallbackUrl}) {
    String name = (requested ?? '').trim();
    if (name.isEmpty) {
      final uri = Uri.tryParse(fallbackUrl);
      if (uri != null && uri.pathSegments.isNotEmpty) {
        name = uri.pathSegments.last;
      }
    }
    if (name.isEmpty) name = 'download.bin';
    // Strip path separators + Windows-reserved chars so we never escape
    // the scratch dir or trip path_provider on weird names.
    return name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  }
}
