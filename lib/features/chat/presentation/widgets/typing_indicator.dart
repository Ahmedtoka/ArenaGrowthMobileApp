import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// WhatsApp-style "X is typing..." bar shown between the messages list and
/// the composer. Has three animated dots that bounce sequentially.
class TypingIndicator extends StatefulWidget {
  final List<String> names;
  const TypingIndicator({super.key, required this.names});

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String get _label {
    final n = widget.names;
    if (n.isEmpty) return '';
    if (n.length == 1) return '${n.first} is typing';
    if (n.length == 2) return '${n[0]} and ${n[1]} are typing';
    return '${n.first} and ${n.length - 1} others are typing';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Align(
        alignment: Alignment.centerRight,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 260),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(14),
                topRight: Radius.circular(14),
                bottomLeft: Radius.circular(14),
                bottomRight: Radius.circular(4),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _AnimatedDots(controller: _ctrl),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    _label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.ink2,
                      fontStyle: FontStyle.italic,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AnimatedDots extends StatelessWidget {
  final AnimationController controller;
  const _AnimatedDots({required this.controller});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 28,
      height: 12,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (int i = 0; i < 3; i++)
            AnimatedBuilder(
              animation: controller,
              builder: (_, __) {
                // each dot is offset 0/0.33/0.66 of the cycle
                final t = (controller.value - i * 0.18) % 1.0;
                // bounce: 0→1→0 over 0.5 of the cycle, stays low otherwise
                final v = t < 0.5 ? (1 - (t * 2 - 0.5).abs() * 2) : 0.0;
                return Transform.translate(
                  offset: Offset(0, -3 * v),
                  child: Opacity(
                    opacity: 0.4 + v * 0.6,
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: AppColors.arenaBlue,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
