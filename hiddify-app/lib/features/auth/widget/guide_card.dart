import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hiddify/features/auth/data/auth_i18n.dart';
import 'package:hiddify/features/auth/data/auth_service.dart';
import 'package:hiddify/features/auth/widget/plans_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Guidance card shown on home page: invite + upgrade (with optional trial countdown).
class GuideCard extends HookWidget {
  const GuideCard({
    super.key,
    this.isTrialActive = false,
    this.trialRemainingSec = 0,
  });

  final bool isTrialActive;
  final int trialRemainingSec;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = AuthI18n.t;
    final inviteCode = useState<String?>(null);

    useEffect(() {
      () async {
        final prefs = await SharedPreferences.getInstance();
        final auth = AuthService(prefs);
        final user = await auth.getUserInfo();
        if (user != null) {
          inviteCode.value = user['invite_code'] as String?;
        }
      }();
      return null;
    }, []);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: theme.colorScheme.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Invite row
            _GuideRow(
              icon: Icons.person_add_rounded,
              iconColor: Colors.green,
              title: s['guideInvite']!,
              subtitle: s['guideInviteDesc']!,
              trailing: IconButton(
                icon: const Icon(Icons.share_rounded, size: 18),
                onPressed: () {
                  final code = inviteCode.value;
                  if (code != null && code.isNotEmpty) {
                    final msg = '想访问 Google、YouTube、Twitter？试试 Roxi 吧！\n'
                        '免费注册，一键连接，安全稳定。\n\n'
                        '📥 下载：https://dl.roxi.cc/roxi-latest.apk\n'
                        '📢 群组：https://t.me/Roxifree\n\n'
                        '注册时填我的邀请码：$code\n'
                        '好友购买会员，你我各得时长奖励！';
                    Clipboard.setData(ClipboardData(text: msg));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(s['guideInviteCopied']!), duration: const Duration(seconds: 2)),
                    );
                  }
                },
              ),
            ),
            const Divider(height: 1),
            // Upgrade row — with trial countdown when active
            if (isTrialActive) ...[
              _TrialUpgradeRow(
                remainingSec: trialRemainingSec,
                onUpgrade: () => showPlansSheet(context),
              ),
            ] else ...[
              _GuideRow(
                icon: Icons.rocket_launch_rounded,
                iconColor: Colors.orange,
                title: s['guideUpgrade']!,
                subtitle: s['guideUpgradeDesc']!,
                trailing: IconButton(
                  icon: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
                  onPressed: () => showPlansSheet(context),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Trial-active upgrade row: icon + "体验剩余 MM:SS" + 升级套餐 button
class _TrialUpgradeRow extends StatelessWidget {
  final int remainingSec;
  final VoidCallback onUpgrade;

  const _TrialUpgradeRow({
    required this.remainingSec,
    required this.onUpgrade,
  });

  @override
  Widget build(BuildContext context) {
    final s = AuthI18n.t;
    final mm = (remainingSec ~/ 60).toString().padLeft(2, '0');
    final ss = (remainingSec % 60).toString().padLeft(2, '0');

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          children: [
            const Icon(Icons.timer_rounded, size: 18, color: Colors.orange),
            const SizedBox(width: 8),
            Text(
              '${s['trialBanner']} $mm:$ss',
              style: TextStyle(
                color: Colors.orange.shade800,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
            const Spacer(),
            TextButton(
              onPressed: onUpgrade,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(s['upgradePlan']!, style: const TextStyle(fontSize: 12)),
            ),
          ],
        ),
      ),
    );
  }
}

class _GuideRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final Widget trailing;

  const _GuideRow({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 20, color: iconColor),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                Text(subtitle, style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant, fontSize: 11,
                )),
              ],
            ),
          ),
          trailing,
        ],
      ),
    );
  }
}
