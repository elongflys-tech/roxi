import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:hiddify/features/auth/data/auth_i18n.dart';

/// Show app update dialog. If [force] is true, user cannot dismiss.
Future<void> showUpdateDialog(
  BuildContext context, {
  required String latestVersion,
  required String downloadUrl,
  String? changelog,
  bool force = false,
}) async {
  await showDialog(
    context: context,
    barrierDismissible: !force,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.system_update_rounded, size: 52, color: Colors.blue),
          const SizedBox(height: 12),
          Text(
            AuthI18n.t['updateAvailable'] ?? '发现新版本',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            'v$latestVersion',
            style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
          ),
          if (changelog != null && changelog.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(changelog, style: const TextStyle(fontSize: 13, height: 1.5)),
            ),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () async {
                final uri = Uri.parse(downloadUrl);
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
              icon: const Icon(Icons.download_rounded, size: 18),
              label: Text(AuthI18n.t['updateNow'] ?? '立即更新'),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          if (!force) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(
                AuthI18n.t['updateLater'] ?? '稍后再说',
                style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
              ),
            ),
          ],
        ],
      ),
    ),
  );
}
