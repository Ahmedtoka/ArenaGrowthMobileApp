import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Pre-upload preparation: shrink huge images BEFORE they hit the network.
///
/// A modern phone camera produces 8–25MB photos; uploading ten of those on
/// mobile data is what made "create task with 10 photos" take 10 minutes.
/// Compressing to max 2048px @ 82% JPEG keeps screens-worth of quality while
/// cutting the payload ~10–20×.
class UploadPrep {
  UploadPrep._();

  static const _imageExts = {'.jpg', '.jpeg', '.png', '.webp', '.heic', '.heif'};

  /// Files smaller than this skip compression entirely (already cheap).
  static const _skipBelowBytes = 900 * 1024; // 900 KB

  static bool isImagePath(String path) =>
      _imageExts.contains(p.extension(path).toLowerCase());

  /// Returns a compressed temp copy for large images, or the ORIGINAL file
  /// for non-images / already-small images / any compression failure.
  /// Never throws — worst case you upload the original.
  static Future<File> prepare(File file) async {
    try {
      if (!isImagePath(file.path)) return file;

      final size = await file.length();
      if (size < _skipBelowBytes) return file;

      final dir = await getTemporaryDirectory();
      final target = p.join(
        dir.path,
        'up_${DateTime.now().millisecondsSinceEpoch}_${p.basenameWithoutExtension(file.path)}.jpg',
      );

      final out = await FlutterImageCompress.compressAndGetFile(
        file.absolute.path,
        target,
        quality: 82,
        minWidth: 2048,
        minHeight: 2048,
        keepExif: true,
        format: CompressFormat.jpeg,
      );
      if (out == null) return file;

      final outFile = File(out.path);
      final outSize = await outFile.length();
      if (kDebugMode) {
        debugPrint('[upload] compressed ${p.basename(file.path)}: '
            '${(size / 1048576).toStringAsFixed(1)}MB → '
            '${(outSize / 1048576).toStringAsFixed(1)}MB');
      }
      // If compression somehow grew the file (rare, tiny PNGs), keep original.
      return outSize < size ? outFile : file;
    } catch (e) {
      if (kDebugMode) debugPrint('[upload] compress failed, using original: $e');
      return file;
    }
  }
}
