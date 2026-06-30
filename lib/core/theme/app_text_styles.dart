import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

class AppTextStyles {
  AppTextStyles._();

  // Using Cairo as the base font — works well for both English and Arabic.
  static TextStyle _base(double size, FontWeight weight, Color color) =>
      GoogleFonts.cairo(fontSize: size, fontWeight: weight, color: color);

  static TextStyle headingXL = _base(28, FontWeight.bold, AppColors.textPrimary);
  static TextStyle headingL = _base(24, FontWeight.bold, AppColors.textPrimary);
  static TextStyle headingM = _base(20, FontWeight.w600, AppColors.textPrimary);
  static TextStyle headingS = _base(18, FontWeight.w600, AppColors.textPrimary);

  static TextStyle bodyL = _base(16, FontWeight.normal, AppColors.textPrimary);
  static TextStyle bodyM = _base(14, FontWeight.normal, AppColors.textPrimary);
  static TextStyle bodyS = _base(12, FontWeight.normal, AppColors.textSecondary);

  static TextStyle button = _base(16, FontWeight.w600, AppColors.textOnPrimary);
  static TextStyle caption = _base(12, FontWeight.normal, AppColors.textSecondary);
  static TextStyle label = _base(14, FontWeight.w500, AppColors.textPrimary);
}
