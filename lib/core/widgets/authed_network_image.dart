import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/env.dart';
import '../providers/app_providers.dart';
import '../theme/app_colors.dart';

/// Loads a network image with the user's Sanctum Bearer token attached.
///
/// Wraps [CachedNetworkImage] so successful loads are cached on disk.
class AuthedNetworkImage extends ConsumerWidget {
  final String url;
  final BoxFit fit;
  final double? width;
  final double? height;
  final BorderRadius? borderRadius;

  const AuthedNetworkImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.borderRadius,
  });

  /// Resolves a possibly-relative URL against the API base so
  /// [CachedNetworkImage] can fetch it.
  ///
  /// Server-side `TaskAttachment::url()` returns a **relative** path like
  /// `/team/attachments/tasks/123` on purpose (so the same payload can be
  /// fetched from desktop browser, emulator, real phone, etc). The mobile
  /// app must prepend its own host. Cases handled:
  ///   - `http(s)://...`           → use as-is
  ///   - `/api/team/...`           → `<host>` + path
  ///   - `/team/attachments/...`   → `<host>/api` + path  (Sanctum-authed)
  ///   - `/storage/...`            → `<host>` + path      (public files)
  ///   - anything else relative    → join against API base
  static String resolve(String raw) {
    if (raw.isEmpty) return raw;
    final lower = raw.toLowerCase();
    if (lower.startsWith('http://') || lower.startsWith('https://')) {
      return raw;
    }
    final base = Uri.parse(Env.apiBaseUrl); // e.g. http://10.0.2.2:8000/api
    final origin = '${base.scheme}://${base.host}'
        '${base.hasPort ? ':${base.port}' : ''}';
    if (raw.startsWith('/api/')) {
      return '$origin$raw';
    }
    if (raw.startsWith('/storage/')) {
      return '$origin$raw';
    }
    if (raw.startsWith('/team/')) {
      // route('team.attachment.*', false) — sits under /api on the API.
      return '$origin/api$raw';
    }
    if (raw.startsWith('/')) {
      return '$origin$raw';
    }
    // Bare relative — append to API base.
    return '${Env.apiBaseUrl.replaceAll(RegExp(r'/+$'), '')}/$raw';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = ref.watch(dioClientProvider);
    final token = client.authInterceptor.cachedToken;
    final headers = <String, String>{
      'Accept': 'image/*',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };

    final resolved = resolve(url);
    final image = CachedNetworkImage(
      imageUrl: resolved,
      httpHeaders: headers,
      fit: fit,
      width: width,
      height: height,
      placeholder: (ctx, _) => Container(
        width: width,
        height: height,
        color: AppColors.appBg,
        child: const Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
      errorWidget: (ctx, _, err) => Container(
        width: width,
        height: height,
        color: AppColors.appBg,
        alignment: Alignment.center,
        child: const Icon(Icons.broken_image, color: AppColors.ink3),
      ),
    );

    if (borderRadius == null) return image;
    return ClipRRect(borderRadius: borderRadius!, child: image);
  }
}
