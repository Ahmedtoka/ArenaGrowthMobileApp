import 'package:flutter/material.dart';

/// Corner-radius scale. Replaces the 16 ad-hoc `circular(N)` values scattered
/// across the app with one small, consistent set.
///
///   xs  6  → tiny chips / badges
///   sm  10 → inputs, small tiles
///   md  14 → cards, sheets sections
///   lg  20 → bottom sheets, prominent cards
///   pill 999 → fully rounded (chips, FABs, avatars)
class AppRadius {
  AppRadius._();

  static const double xs = 6;
  static const double sm = 10;
  static const double md = 14;
  static const double lg = 20;
  static const double pill = 999;

  static BorderRadius get rXs => BorderRadius.circular(xs);
  static BorderRadius get rSm => BorderRadius.circular(sm);
  static BorderRadius get rMd => BorderRadius.circular(md);
  static BorderRadius get rLg => BorderRadius.circular(lg);
  static BorderRadius get rPill => BorderRadius.circular(pill);

  /// Rounded only on the top — for bottom sheets.
  static const BorderRadius sheetTop =
      BorderRadius.vertical(top: Radius.circular(lg));
}

/// 4pt spacing scale. Use these instead of magic numbers for gaps + padding.
///
///   xs 4 · sm 8 · md 12 · lg 16 · xl 24 · xxl 32
class AppSpacing {
  AppSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;

  // Ready-made SizedBox gaps (const-friendly).
  static const gapXs = SizedBox(height: xs, width: xs);
  static const gapSm = SizedBox(height: sm, width: sm);
  static const gapMd = SizedBox(height: md, width: md);
  static const gapLg = SizedBox(height: lg, width: lg);

  static const hXs = SizedBox(width: xs);
  static const hSm = SizedBox(width: sm);
  static const hMd = SizedBox(width: md);

  static const vXs = SizedBox(height: xs);
  static const vSm = SizedBox(height: sm);
  static const vMd = SizedBox(height: md);
  static const vLg = SizedBox(height: lg);

  /// Standard page padding + a card's inner padding.
  static const EdgeInsets page = EdgeInsets.all(lg);
  static const EdgeInsets card = EdgeInsets.all(md);
}
