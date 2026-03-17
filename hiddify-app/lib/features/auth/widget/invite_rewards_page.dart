import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/features/auth/data/auth_service.dart';
import 'package:hiddify/features/auth/data/auth_i18n.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Invite rewards page showing 2-level referral system.
/// Mimics LetsGo VPN's invite rewards UI with gift icon, stats, and detailed rules.
class InviteRewardsPage extends HookWidget {
  const InviteRewardsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AuthI18n.t;
    final theme = Theme.of(context);
    
    final inviteCode = useState<String>('');
    final invitedCount = useState<int>(0);
    final bonusDays = useState<int>(0);
    final loading = useState(true);

    useEffect(() {
      () async {
        try {
          final prefs = await SharedPreferences.getInstance();
          final auth = AuthService(prefs);
          final info = await auth.getInviteInfo();
          if (info != null) {
            inviteCode.value = info['invite_code'] ?? '';
            invitedCount.value = info['invited_count'] ?? 0;
            bonusDays.value = info['bonus_days'] ?? 0;
          }
        } catch (_) {}
        loading.value = false;
      }();
      return null;
    }, []);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          s['inviteRewardsTitle'] ?? '邀请奖励',
          style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w600),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline_rounded, color: Colors.black54),
            onPressed: () => _showRulesDialog(context),
          ),
        ],
      ),
      body: loading.value
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  // Gift icon
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [Colors.pink.shade100, Colors.orange.shade100],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: const Icon(Icons.card_giftcard_rounded, size: 60, color: Colors.pink),
                  ),
                  const Gap(16),
                  Text(
                    s['inviteRewardsHeadline'] ?? '推荐好友，领永久会员',
                    style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  const Gap(8),
                  Text(
                    s['inviteRewardsSubtitle'] ?? '好友安装后填写您的邀请码即算推荐成功\n当其购买会员时，您均可获得 20% 的时长！永久有效！',
                    style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600, height: 1.5),
                    textAlign: TextAlign.center,
                  ),
                  const Gap(24),
                  // Invite code card
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      children: [
                        Text(
                          s['inviteYourCode'] ?? '您的邀请码',
                          style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
                        ),
                        const Gap(8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              inviteCode.value,
                              style: theme.textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: Colors.pink.shade700,
                                letterSpacing: 2,
                              ),
                            ),
                            const Gap(8),
                            IconButton(
                              icon: Icon(Icons.copy_rounded, size: 20, color: Colors.grey.shade600),
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: inviteCode.value));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(s['inviteCodeCopied'] ?? '邀请码已复制')),
                                );
                              },
                            ),
                          ],
                        ),
                        const Gap(16),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: () => _shareInvite(context, inviteCode.value),
                            icon: const Icon(Icons.share_rounded, size: 18),
                            label: Text(s['inviteShareBtn'] ?? '推荐给好友'),
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.pink,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Gap(32),
                  // Stats
                  Row(
                    children: [
                      Expanded(
                        child: _StatCard(
                          icon: Icons.people_rounded,
                          label: s['inviteSuccessCount'] ?? '成功推荐',
                          value: '${invitedCount.value}',
                          unit: s['invitePeople'] ?? '人',
                          color: Colors.blue,
                        ),
                      ),
                      const Gap(12),
                      Expanded(
                        child: _StatCard(
                          icon: Icons.access_time_rounded,
                          label: s['inviteTotalReward'] ?? '累计获得',
                          value: '${bonusDays.value}',
                          unit: s['inviteDays'] ?? '天',
                          color: Colors.orange,
                        ),
                      ),
                    ],
                  ),
                  const Gap(24),
                  // Hint
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline_rounded, size: 20, color: Colors.blue.shade700),
                        const Gap(12),
                        Expanded(
                          child: Text(
                            s['inviteHint'] ?? '好友购买或从其推荐人处获得会员时，您都将获得 20% 的奖励，二级推荐获得 10%',
                            style: TextStyle(fontSize: 12, color: Colors.blue.shade900, height: 1.4),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String unit;
  final Color color;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.unit,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: .2)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 28, color: color),
          const Gap(8),
          Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          const Gap(4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                value,
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: color, height: 1),
              ),
              const Gap(2),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(unit, style: TextStyle(fontSize: 14, color: color)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

void _shareInvite(BuildContext context, String inviteCode) {
  final s = AuthI18n.t;
  final msg = '想访问 Google、YouTube、Twitter？试试 Roxi 吧！\n'
      '免费注册，一键连接，安全稳定。\n\n'
      '📥 下载：https://dl.roxi.cc/roxi-latest.apk\n'
      '📢 群组：https://t.me/Roxifree\n\n'
      '注册时填我的邀请码：$inviteCode\n'
      '好友购买会员，你我各得时长奖励！';

  Clipboard.setData(ClipboardData(text: msg));
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(s['guideInviteCopied'] ?? '邀请信息已复制')),
  );
}

void _showRulesDialog(BuildContext context) {
  final s = AuthI18n.t;
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: const LinearGradient(
                colors: [Color(0xFFFF6B9D), Color(0xFF6C3CE0)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: const Icon(Icons.card_giftcard_rounded, color: Colors.white, size: 24),
          ),
          const Gap(12),
          Text(s['inviteRulesTitle'] ?? '详细规则'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _RuleItem(
              number: '1',
              text: s['inviteRule1'] ?? '朋友首次安装 Roxi 后填写您的邀请码即算推荐成功；',
            ),
            _RuleItem(
              number: '2',
              text: s['inviteRule2'] ?? '朋友购买或从其推荐人处获得会员时，您都将获得 20% 的奖励；举个例子：',
            ),
            Padding(
              padding: const EdgeInsets.only(left: 32, top: 4),
              child: Text(
                s['inviteExample'] ??
                    '(1) A 推荐 B，B 推荐 C；\n'
                        '(2) B 买年卡会员，A 获得 73 天会员；\n'
                        '(3) C 买年卡会员，B 获得 73 天会员，A 获得 37 天会员；',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade700, height: 1.6),
              ),
            ),
            _RuleItem(
              number: '3',
              text: s['inviteRule3'] ?? '关系永久绑定且没有上限；',
            ),
            _RuleItem(
              number: '4',
              text: s['inviteRule4'] ?? '赠送的会员与账户级别一致，如果不是会员，则赠送基础会员。',
            ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text(s['inviteGotIt'] ?? '知道了'),
        ),
      ],
    ),
  );
}

class _RuleItem extends StatelessWidget {
  final String number;
  final String text;

  const _RuleItem({required this.number, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [Color(0xFFFF6B9D), Color(0xFF6C3CE0)],
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              number,
              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),
          const Gap(12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 14, color: Colors.grey.shade800, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}
