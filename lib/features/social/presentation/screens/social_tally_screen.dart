import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/app_providers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_dimens.dart';
import '../../../../core/utils/text_direction_util.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_states.dart';
import '../../../../core/widgets/attendance_guard.dart';

/// ─── السبحة — Social tally ────────────────────────────────────────────
/// One tap = one published item (logged server-side with its exact time).
/// Per brand: platform selector (FB/IG/TikTok) + three big counters
/// (Post / Story / Reel) showing TODAY's numbers. Long-press = undo.

class _BrandTally {
  final int id;
  final String name;
  final String? logoUrl;
  final String? color;
  final Map<String, int> counts; // "platform.kind" → n
  _BrandTally(this.id, this.name, this.logoUrl, this.color, this.counts);
}

final socialTodayProvider =
    FutureProvider.autoDispose<List<_BrandTally>>((ref) async {
  final dio = ref.read(dioClientProvider);
  final res = await dio.get('/team/social/today');
  final data = res.data as Map<String, dynamic>;
  return [
    for (final b in (data['brands'] as List))
      _BrandTally(
        b['id'] as int,
        b['name'] as String,
        b['logo_url'] as String?,
        b['color'] as String?,
        {
          for (final e in ((b['counts'] ?? {}) as Map<String, dynamic>).entries)
            e.key: (e.value as num).toInt(),
        },
      ),
  ];
});

class SocialTallyScreen extends ConsumerStatefulWidget {
  const SocialTallyScreen({super.key});

  @override
  ConsumerState<SocialTallyScreen> createState() => _SocialTallyScreenState();
}

class _SocialTallyScreenState extends ConsumerState<SocialTallyScreen> {
  static const platforms = [
    ('facebook', 'Facebook', Color(0xFF1D4ED8)),
    ('instagram', 'Instagram', Color(0xFFBE185D)),
    ('tiktok', 'TikTok', Color(0xFF0F172A)),
  ];
  static const kinds = [
    ('post', 'Post', Icons.article_outlined),
    ('story', 'Story', Icons.amp_stories_outlined),
    ('reel', 'Reel', Icons.movie_outlined),
  ];

  /// Selected platform per brand (default facebook).
  final Map<int, String> _platform = {};

  /// Optimistic local deltas applied on top of the fetched counts.
  final Map<String, int> _delta = {}; // "brandId.platform.kind" → ±n

  int _countFor(_BrandTally b, String platform, String kind) {
    final base = b.counts['$platform.$kind'] ?? 0;
    return base + (_delta['${b.id}.$platform.$kind'] ?? 0);
  }

  Future<void> _tap(_BrandTally b, String kind, {bool undo = false}) async {
    // Work-gate: logging social items only while checked-in + active.
    if (!await ref.ensureCheckedIn(context)) return;
    final platform = _platform[b.id] ?? 'facebook';
    final key = '${b.id}.$platform.$kind';
    if (undo && _countFor(b, platform, kind) <= 0) return;

    HapticFeedback.lightImpact();
    setState(() => _delta[key] = (_delta[key] ?? 0) + (undo ? -1 : 1));

    try {
      final dio = ref.read(dioClientProvider);
      await dio.post(
        undo ? '/team/social/undo' : '/team/social/tap',
        data: {'brand_id': b.id, 'platform': platform, 'kind': kind},
      );
    } catch (_) {
      // Roll back the optimistic bump on failure.
      if (mounted) {
        setState(() => _delta[key] = (_delta[key] ?? 0) + (undo ? 1 : -1));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed — check your connection')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final today = ref.watch(socialTodayProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Social tally'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () {
              _delta.clear();
              ref.invalidate(socialTodayProvider);
            },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: today.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => AppErrorState(
          onRetry: () {
            _delta.clear();
            ref.invalidate(socialTodayProvider);
          },
        ),
        data: (brands) => ListView.separated(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.xl,),
          itemCount: brands.length + 1,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            if (i == 0) {
              final grandTotal = [
                for (final b in brands)
                  for (final p in platforms)
                    for (final k in kinds) _countFor(b, p.$1, k.$1),
              ].fold<int>(0, (a, c) => a + c);
              return Container(
                margin: const EdgeInsets.only(bottom: 2),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0EA5A4), Color(0xFF0F766E)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: AppRadius.rMd,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: AppRadius.rMd,
                      ),
                      child: Text(
                        '$grandTotal',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    AppSpacing.hMd,
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Published today',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Tap = +1 item · long-press = undo',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }
            final b = brands[i - 1];
            final selected = _platform[b.id] ?? 'facebook';
            final brandTotal = [
              for (final p in platforms)
                for (final k in kinds) _countFor(b, p.$1, k.$1),
            ].fold<int>(0, (a, c) => a + c);

            return AppCard(
              margin: EdgeInsets.zero,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Brand header ──
                  Row(
                    children: [
                      if (b.logoUrl != null && b.logoUrl!.isNotEmpty)
                        ClipRRect(
                          borderRadius: AppRadius.rSm,
                          child: Image.network(b.logoUrl!,
                              width: 34, height: 34, fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  _initialBox(b),),
                        )
                      else
                        _initialBox(b),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(b.name,
                            textDirection: detectBidiDirection(b.name),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w700,),),
                      ),
                      if (brandTotal > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2,),
                          decoration: BoxDecoration(
                            color: AppColors.greenBg,
                            borderRadius: AppRadius.rPill,
                          ),
                          child: Text('$brandTotal today',
                              style: const TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF047857),),),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // ── Platform chips ──
                  Row(
                    children: [
                      for (final p in platforms) ...[
                        Expanded(
                          child: GestureDetector(
                            onTap: () =>
                                setState(() => _platform[b.id] = p.$1),
                            child: Container(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 7),
                              decoration: BoxDecoration(
                                color: selected == p.$1
                                    ? p.$3
                                    : const Color(0xFFF1F5F9),
                                borderRadius: AppRadius.rPill,
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                p.$2,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: selected == p.$1
                                      ? Colors.white
                                      : AppColors.ink2,
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (p != platforms.last) const SizedBox(width: 6),
                      ],
                    ],
                  ),
                  const SizedBox(height: 10),
                  // ── Counter buttons ──
                  Row(
                    children: [
                      for (final k in kinds) ...[
                        Expanded(
                          child: _CounterButton(
                            label: k.$2,
                            icon: k.$3,
                            count: _countFor(b, selected, k.$1),
                            onTap: () => _tap(b, k.$1),
                            onLongPress: () => _tap(b, k.$1, undo: true),
                          ),
                        ),
                        if (k != kinds.last) AppSpacing.hSm,
                      ],
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _initialBox(_BrandTally b) => Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _hex(b.color) ?? AppColors.teal,
          borderRadius: AppRadius.rSm,
        ),
        child: Text(
          b.name.isNotEmpty ? b.name[0].toUpperCase() : '?',
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.w700,),
        ),
      );

  Color? _hex(String? h) {
    if (h == null || h.isEmpty) return null;
    final v = int.tryParse(h.replaceFirst('#', ''), radix: 16);
    return v == null ? null : Color(0xFF000000 | v);
  }
}

class _CounterButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final int count;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _CounterButton({
    required this.label,
    required this.icon,
    required this.count,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final active = count > 0;
    return Material(
      color: active ? const Color(0xFFE7F8F5) : const Color(0xFFF8FAFC),
      borderRadius: AppRadius.rMd,
      child: InkWell(
        borderRadius: AppRadius.rMd,
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            borderRadius: AppRadius.rMd,
            border: Border.all(
                color: active
                    ? const Color(0xFF99E6D8)
                    : AppColors.border,),
          ),
          child: Column(
            children: [
              Text('$count',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: active ? AppColors.teal : AppColors.ink3,
                  ),),
              const SizedBox(height: 2),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 13, color: AppColors.ink3),
                  const SizedBox(width: 3),
                  Text(label,
                      style: const TextStyle(
                          fontSize: 11.5, color: AppColors.ink2,),),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
