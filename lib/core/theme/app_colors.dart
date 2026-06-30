import 'package:flutter/material.dart';

/// Arena OS palette — derived from the Arena Business Growth logo.
///
/// Primary: electric royal blue.
/// Accent: crimson red (used sparingly — important notifications, R marker).
class AppColors {
  AppColors._();

  // ─── Arena brand ────────────────────────────────────────
  // Tuned to match the new app icon: electric royal blue on deep navy.
  static const Color arenaBlue = Color(0xFF2235FF);       // primary — electric
  static const Color arenaBlueDark = Color(0xFF1A26C7);   // pressed
  static const Color arenaBlueLight = Color(0xFFE9EBFF);  // tint / my-bubble bg
  static const Color arenaBlueSoft = Color(0xFFCFD3FF);   // hover / chip bg
  static const Color arenaRed = Color(0xFFE63A2D);        // accent — icon red
  static const Color arenaBlack = Color(0xFF0A0F2C);      // deep navy (icon bg)
  static const Color arenaNavyDeep = Color(0xFF050818);   // splash gradient core

  // ─── Surfaces ───────────────────────────────────────────
  static const Color chatBg = Color(0xFFF5F4FA);          // conversation wallpaper
  static const Color appBg = Color(0xFFF0F2F5);           // page background
  static const Color outBubble = arenaBlueLight;          // my message bubble bg
  static const Color surface = Colors.white;

  // ─── Ink (text) ─────────────────────────────────────────
  static const Color ink = Color(0xFF111B21);
  static const Color ink2 = Color(0xFF54656F);
  static const Color ink3 = Color(0xFF8696A0);

  // ─── R/O/G importance markers ───────────────────────────
  static const Color redBg = Color(0xFFFEE2E2);
  static const Color redBorder = arenaRed;
  static const Color orangeBg = Color(0xFFFED7AA);
  static const Color orangeBorder = Color(0xFFEA580C);
  static const Color greenBg = Color(0xFFD1FAE5);
  static const Color greenBorder = Color(0xFF059669);

  // ─── Aliases for theme compatibility ────────────────────
  static const Color teal = arenaBlue;                    // legacy alias
  static const Color tealDark = arenaBlueDark;
  static const Color tealLight = arenaBlueLight;
  static const Color primary = arenaBlue;
  static const Color primaryDark = arenaBlueDark;
  static const Color primaryLight = arenaBlueLight;
  static const Color accent = arenaRed;
  static const Color background = appBg;
  static const Color cardBackground = Colors.white;
  static const Color textPrimary = ink;
  static const Color textSecondary = ink2;
  static const Color textHint = ink3;
  static const Color textOnPrimary = Colors.white;

  // ─── Status colors ──────────────────────────────────────
  static const Color success = Color(0xFF22C55E);
  static const Color warning = Color(0xFFF59E0B);
  static const Color error = arenaRed;
  static const Color info = arenaBlue;

  // ─── Borders & dividers ─────────────────────────────────
  static const Color border = Color(0xFFE5E7EB);
  static const Color divider = Color(0xFFE5E7EB);

  // ─── Dark mode ──────────────────────────────────────────
  static const Color darkBackground = arenaBlack;
  static const Color darkSurface = Color(0xFF18181F);
}
