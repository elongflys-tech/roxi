import 'package:hiddify/features/auth/widget/invite_rewards_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hiddify/features/auth/data/auth_i18n.dart';
import 'package:hiddify/features/auth/data/auth_service.dart';
import 'package:hiddify/features/auth/widget/plans_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Show trial-expired dialog. User must either pay or invite a friend.
/// Cannot be dismissed by tapping outside.
/// Guarded: only one dialog can be shown at a time.
bool _trialExpiredDialogShowing = false;

Future<void> showTrialExpiredDialog(BuildContext context) async {
  if (_trialExpiredDialogShowing) return; // prevent stacking
  _trialExpiredDialogShowing = true;
  await showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => const _TrialExpiredDialog(),
  );
  _trialExpiredDialogShowing = false;
}

class _TrialExpiredDialog extends StatelessWidget {
  const _TrialExpiredDialog();

  @override
  Widget build(BuildContext context) {
    final s = AuthI18n.t;
    final theme = Theme.of(context);

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Close button — top right
          Align(
            alignment: Alignment.topRight,
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, size: 18, color: Colors.grey),
              ),
            ),
          ),
          const Icon(Icons.timer_off_rounded, size: 56, color: Colors.orange),
          const SizedBox(height: 12),
          Text(s['trialExpiredTitle']!,
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(s['trialExpiredDesc']!,
              style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey),
              textAlign: TextAlign.center),
          const SizedBox(height: 20),
          // Primary: upgrade
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                showPlansSheet(context);
              },
              icon: const Icon(Icons.rocket_launch_rounded, size: 18),
              label: Text(s['upgradePlan']!),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          const SizedBox(height: 10),
          // Secondary: invite friend to get free nodes
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () async {
                Navigator.of(context).pop();
                Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(builder: (_) => const InviteRewardsPage()));
              },
              icon: const Icon(Icons.person_add_rounded, size: 18),
              label: Text(s['trialInviteBtn']!),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(s['trialInviteHint']!,
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey, fontSize: 11),
              textAlign: TextAlign.center),
        ],
      ),
      actionsPadding: const EdgeInsets.only(bottom: 12),
      actions: const [],
    );
  }
}

void _showInviteShareDialog(BuildContext context) async {
  final s = AuthI18n.t;
  final prefs = await SharedPreferences.getInstance();
  final auth = AuthService(prefs);
  final user = await auth.getUserInfo();
  final inviteInfo = await auth.getInviteInfo();
  final invCode = inviteInfo?['invite_code'] ?? '';

  if (!context.mounted) return;

  if (invCode.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('加载中，请稍后再试')),
    );
    return;
  }

  final msg = '想访问 Google、YouTube、Twitter？试试 Roxi 吧！\n'
      '免费注册，一键连接，安全稳定。\n\n'
      '📥 下载：https://dl.roxijet.cloud/roxi-latest.apk\n'
      '📢 群组：https://t.me/Roxifree\n\n'
      '🔗 邀请链接：https://roxijet.cloud/$invCode\n'
      '注册时填我的邀请码：$invCode\n'
      '填我的邀请码，领取免费节点！';

  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(s['guideInvite']!),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(s['trialInviteExplain']!, style: const TextStyle(fontSize: 13, color: Colors.grey)),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(msg, style: const TextStyle(fontSize: 12)),
          ),
        ],
      ),
      actions: [
        FilledButton.icon(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: msg));
            Navigator.of(ctx).pop();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(s['guideInviteCopied']!)),
            );
          },
          icon: const Icon(Icons.copy_rounded, size: 16),
          label: Text(s['trialCopyShare']!),
        ),
      ],
    ),
  );
}
