import 'dart:io';
import 'package:flutter/material.dart';
import 'package:hiddify/features/auth/data/auth_i18n.dart';

/// Check network connectivity by attempting a DNS lookup.
Future<bool> checkNetwork() async {
  try {
    final result = await InternetAddress.lookup('roxi.cc').timeout(const Duration(seconds: 5));
    return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
  } catch (_) {
    return false;
  }
}

/// Show a network error dialog similar to SeetheWorld's "网络异常" dialog.
/// Returns true if user tapped "重试" (retry), false if "知道了" (dismiss).
Future<bool> showNetworkErrorDialog(BuildContext context) async {
  final s = AuthI18n.t;
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Warning icon
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.wifi_off_rounded, size: 32, color: Colors.orange.shade600),
            ),
            const SizedBox(height: 16),
            // Title
            Text(
              s['networkError']!,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            // Description
            Text(
              s['networkErrorDesc']!,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey.shade600, height: 1.5),
            ),
            const SizedBox(height: 20),
            // Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      side: BorderSide(color: Colors.grey.shade300),
                    ),
                    child: Text(s['networkGotIt']!, style: TextStyle(color: Colors.grey.shade700)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(ctx).pop(true),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      backgroundColor: Theme.of(ctx).colorScheme.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: Text(s['networkRetry']!),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
  return result ?? false;
}
