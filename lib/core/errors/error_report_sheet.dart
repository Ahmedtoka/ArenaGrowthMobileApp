import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/app_colors.dart';
import 'error_reporter.dart';

/// Bottom sheet shown when an uncaught error is intercepted by
/// [ErrorReporter]. Friendly summary + "Send screenshot" button that posts
/// the report to /api/diagnostics/report.
class ErrorReportSheet extends ConsumerStatefulWidget {
  final String errorMessage;
  final String stackTrace;
  final Uint8List? capturedPng;

  const ErrorReportSheet({
    super.key,
    required this.errorMessage,
    required this.stackTrace,
    this.capturedPng,
  });

  static Future<void> show(
    BuildContext context, {
    required String errorMessage,
    required String stackTrace,
  }) async {
    // Try to grab a frame BEFORE we show the sheet, so the capture reflects
    // the moment of failure (rather than the modal overlay itself).
    final png = await ErrorReporter.capturePng();
    if (!context.mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => ErrorReportSheet(
        errorMessage: errorMessage,
        stackTrace: stackTrace,
        capturedPng: png,
      ),
    );
  }

  @override
  ConsumerState<ErrorReportSheet> createState() => _ErrorReportSheetState();
}

class _ErrorReportSheetState extends ConsumerState<ErrorReportSheet> {
  bool _sending = false;
  bool _sent = false;
  String? _sendError;

  String get _errorType {
    final colon = widget.errorMessage.indexOf(':');
    return colon > 0 && colon < 60
        ? widget.errorMessage.substring(0, colon)
        : 'Error';
  }

  String get _errorReason {
    final colon = widget.errorMessage.indexOf(':');
    return colon > 0
        ? widget.errorMessage.substring(colon + 1).trim()
        : widget.errorMessage;
  }

  String get _topStackFrame {
    final firstNewline = widget.stackTrace.indexOf('\n');
    return firstNewline > 0
        ? widget.stackTrace.substring(0, firstNewline)
        : widget.stackTrace;
  }

  Future<void> _send() async {
    setState(() {
      _sending = true;
      _sendError = null;
    });
    final client = ref.read(errorReporterClientProvider);
    final error = await ErrorReporter.send(
      client: client,
      errorMessage: widget.errorMessage,
      stackTrace: widget.stackTrace,
      screenshot: widget.capturedPng,
    );
    if (!mounted) return;
    setState(() {
      _sending = false;
      _sent = error == null;
      _sendError = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            20, 12, 20, 20 + MediaQuery.of(context).viewInsets.bottom,),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: AppColors.arenaRed.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.error_outline,
                    color: AppColors.arenaRed, size: 24,),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Something went wrong',
                      style: TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _errorType,
                      style: const TextStyle(
                          fontSize: 12.5, color: AppColors.ink3,),
                    ),
                  ],
                ),
              ),
            ],),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFECACA)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _kv('Reason', _errorReason),
                  const SizedBox(height: 6),
                  _kv('Where', _topStackFrame),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (_sent)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFECFDF5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Row(children: [
                  Icon(Icons.check_circle, color: AppColors.greenBorder),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Thanks — screenshot + details sent.',
                      style: TextStyle(
                          fontSize: 13.5, fontWeight: FontWeight.w600,),
                    ),
                  ),
                ],),
              )
            else
              FilledButton.icon(
                onPressed: _sending ? null : _send,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.arenaBlue,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                icon: _sending
                    ? const SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          valueColor: AlwaysStoppedAnimation(Colors.white),
                        ),
                      )
                    : const Icon(Icons.send_outlined, color: Colors.white),
                label: Text(
                  _sending ? 'Sending…' : 'Send screenshot to support',
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 14.5,),
                ),
              ),
            if (_sendError != null) ...[
              const SizedBox(height: 8),
              Text(
                _sendError!,
                style: const TextStyle(
                    fontSize: 12, color: AppColors.arenaRed,),
              ),
            ],
            TextButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text(
                'Close',
                style: TextStyle(color: AppColors.ink3),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _kv(String label, String value) {
    return RichText(
      text: TextSpan(
        style: const TextStyle(fontSize: 12.5, color: AppColors.ink2),
        children: [
          TextSpan(
            text: '$label: ',
            style: const TextStyle(
                fontWeight: FontWeight.w700, color: AppColors.arenaRed,),
          ),
          TextSpan(
            text: value,
            style: const TextStyle(color: Color(0xFF7F1D1D)),
          ),
        ],
      ),
    );
  }
}
