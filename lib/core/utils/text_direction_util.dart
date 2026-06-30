import 'package:flutter/widgets.dart';

/// Picks an appropriate [TextDirection] for a piece of user-supplied text by
/// scanning for the FIRST strong-directional character.
///
/// Why we need this: the UI chrome is LTR (English), but individual chat
/// messages and task titles might be in Arabic. We want those rendered RTL
/// so punctuation lands on the correct side. For Latin content we keep LTR.
TextDirection detectBidiDirection(String? text, {TextDirection fallback = TextDirection.ltr}) {
  if (text == null || text.isEmpty) return fallback;
  for (final c in text.runes) {
    if (_isRtlChar(c)) return TextDirection.rtl;
    if (_isLtrChar(c)) return TextDirection.ltr;
  }
  return fallback;
}

bool _isRtlChar(int c) {
  // Arabic (incl. presentation forms), Hebrew, Syriac, Thaana, NKo.
  return (c >= 0x0590 && c <= 0x05FF) ||  // Hebrew
      (c >= 0x0600 && c <= 0x06FF) ||     // Arabic
      (c >= 0x0700 && c <= 0x074F) ||     // Syriac
      (c >= 0x0750 && c <= 0x077F) ||     // Arabic Supplement
      (c >= 0x0780 && c <= 0x07BF) ||     // Thaana
      (c >= 0x07C0 && c <= 0x07FF) ||     // NKo
      (c >= 0x08A0 && c <= 0x08FF) ||     // Arabic Extended-A
      (c >= 0xFB1D && c <= 0xFDFF) ||     // Hebrew + Arabic presentation
      (c >= 0xFE70 && c <= 0xFEFF);       // Arabic Presentation Forms-B
}

bool _isLtrChar(int c) {
  // Basic Latin letters + most European blocks.
  return (c >= 0x0041 && c <= 0x005A) ||  // A-Z
      (c >= 0x0061 && c <= 0x007A) ||     // a-z
      (c >= 0x00C0 && c <= 0x024F) ||     // Latin extended
      (c >= 0x0370 && c <= 0x03FF);       // Greek
}
