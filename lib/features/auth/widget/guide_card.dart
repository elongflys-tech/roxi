import 'package:flutter/material.dart';
import 'package:hiddify/features/auth/data/auth_i18n.dart';
import 'package:hiddify/features/auth/widget/invite_rewards_page.dart';
import 'package:hiddify/features/auth/widget/plans_page.dart';

/// Guidance card shown on home page: invite + upgrade.
class GuideCard extends StatelessWidget {
  const GuideCard({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = AuthI18n.t;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: theme.colorScheme.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Invite row — navigate to invite rewards page
            _GuideRow(
              icon: Icons.person_add_rounded,
              iconColor: Colors.green,
              title: s['guideInvite']!,
              subtitle: s['guideInviteDesc']!,
              trailingIcon: Icons.arrow_forward_ios_rounded,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const InviteRewardsPage()),
              ),
            ),
            const Divider(height: 1),
            // Upgrade row
            _GuideRow(
              icon: Icons.rocket_launch_rounded,
              iconColor: Colors.orange,
              title: s['guideUpgrade']!,
              subtitle: s['guideUpgradeDesc']!,
              trailingIcon: Icons.arrow_forward_ios_rounded,
              onTap: () => showPlansSheet(context),
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
  final IconData trailingIcon;
  final VoidCallback onTap;

  const _GuideRow({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.trailingIcon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
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
            Icon(trailingIcon, size: 16, color: theme.colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
