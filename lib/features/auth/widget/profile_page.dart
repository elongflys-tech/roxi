import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hiddify/features/auth/data/auth_i18n.dart';
import 'package:hiddify/features/auth/data/auth_service.dart';
import 'package:hiddify/features/auth/widget/invite_rewards_page.dart';
import 'package:hiddify/features/auth/widget/plans_page.dart';
import 'package:hiddify/features/auth/widget/ticket_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

class ProfilePage extends HookWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = AuthI18n.t;
    final userInfo = useState<Map<String, dynamic>?>(null);
    final inviteInfo = useState<Map<String, dynamic>?>(null);
    final isLoading = useState(true);
    final showAuthPanel = useState(false);

    Future<void> reload() async {
      final prefs = await SharedPreferences.getInstance();
      final auth = AuthService(prefs);
      final futures = await Future.wait([auth.getUserInfo(), auth.getInviteInfo()]);
      userInfo.value = futures[0];
      inviteInfo.value = futures[1];
      isLoading.value = false;
      final em = futures[0]?['email'];
      if (em != null && em.toString().isNotEmpty) showAuthPanel.value = false;
    }

    useEffect(() { reload(); return null; }, []);

    if (isLoading.value) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(backgroundColor: Colors.white, elevation: 0,
          title: Text(s['profileTitle']!, style: const TextStyle(color: Colors.black87)),
          iconTheme: const IconThemeData(color: Colors.black87)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final email = userInfo.value?['email'];
    final hasEmail = email != null && email.toString().isNotEmpty;
    final deviceId = userInfo.value?['device_id'] ?? '';
    final expireDate = userInfo.value?['expire_date'];
    final trafficUsed = (userInfo.value?['total_traffic_used_gb'] ?? 0).toDouble();
    final dailyUsed = (userInfo.value?['daily_traffic_used_gb'] ?? 0).toDouble();
    final monthlyUsed = (userInfo.value?['monthly_traffic_used_gb'] ?? 0).toDouble();
    final tier = (userInfo.value?['tier'] as String?) ?? 'free';
    final isPaid = tier == 'vip' || tier == 'svip';
    final tierLabel = isPaid ? (tier == 'svip' ? s['svipTier']! : s['vipTier']!) : s['freeTier']!;
    final tierColor = isPaid ? (tier == 'svip' ? const Color(0xFF7B1FA2) : const Color(0xFFD4A017)) : Colors.grey;
    final invCode = inviteInfo.value?['invite_code'] ?? '';
    final invCount = inviteInfo.value?['invited_count'] ?? 0;
    final bonusDays = inviteInfo.value?['bonus_days'] ?? 0;
    final hasUsedInvite = userInfo.value?['invited_by'] != null;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(backgroundColor: Colors.white, elevation: 0,
        title: Text(s['profileTitle']!, style: const TextStyle(color: Colors.black87)),
        iconTheme: const IconThemeData(color: Colors.black87)),
      body: ListView(padding: const EdgeInsets.all(16), children: [

        // ── 1. User card (header + plan info + upgrade button) ──
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: tier == 'svip'
                ? const LinearGradient(colors: [Color(0x1A9C27B0), Color(0x1AD4A017), Color(0x00FFFFFF)], begin: Alignment.topLeft, end: Alignment.bottomRight)
                : LinearGradient(colors: [
                    isPaid ? tierColor.withOpacity(0.08) : Colors.grey.shade50,
                    Colors.white,
                  ], begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: isPaid
                ? (tier == 'svip' ? const Color(0xFF9C27B0).withOpacity(0.25) : tierColor.withOpacity(0.25))
                : Colors.grey.shade200),
          ),
          child: Column(children: [
            // Avatar row
            Row(children: [
              CircleAvatar(radius: 28,
                backgroundColor: isPaid ? tierColor.withOpacity(0.15) : (hasEmail ? Colors.blue.shade100 : Colors.grey.shade200),
                child: Icon(hasEmail ? Icons.person_rounded : Icons.phone_android_rounded, size: 28,
                  color: isPaid ? tierColor.withOpacity(0.7) : (hasEmail ? Colors.blue.shade700 : Colors.grey.shade500))),
              const SizedBox(width: 16),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(hasEmail ? email.toString() : s['deviceUser']!,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: hasEmail ? Colors.black87 : Colors.grey.shade700)),
                const SizedBox(height: 4),
                Text(hasEmail ? 'ID: ${deviceId.toString().length > 8 ? deviceId.toString().substring(0, 8) : deviceId}' : s['notBound']!,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
              ])),
              Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: tier == 'svip' ? null : tierColor.withOpacity(0.15),
                  gradient: tier == 'svip' ? const LinearGradient(colors: [Color(0x269C27B0), Color(0x26D4A017)]) : null,
                  borderRadius: BorderRadius.circular(20)),
                child: tier == 'svip'
                    ? ShaderMask(
                        shaderCallback: (bounds) => const LinearGradient(colors: [Color(0xFF9C27B0), Color(0xFFD4A017)]).createShader(bounds),
                        child: const Text('SVIP', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white)))
                    : Text(tierLabel, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: tierColor))),
            ]),
            const SizedBox(height: 14),
            // Plan info rows
            if (isPaid) ...[
              _infoRow(s['expireDate']!, _fmtDateWithDays(expireDate), null),
              _infoRow(s['trafficUsed']!, s['unlimitedTraffic']!, null),
            ],
            if (!isPaid) ...[
              _infoRow(s['dailyTraffic'] ?? '今日流量', '${dailyUsed.toStringAsFixed(1)} / 5 GB', dailyUsed >= 5 ? Colors.red : null),
              _infoRow(s['monthlyTraffic'] ?? '本月流量', '${monthlyUsed.toStringAsFixed(1)} / 100 GB', monthlyUsed >= 100 ? Colors.red : null),
              _infoRow(s['freeNodeLimit']!, s['freeNodeLimitVal']!, Colors.orange),
            ],
            const SizedBox(height: 14),
            // Upgrade / renew button
            SizedBox(width: double.infinity, child: FilledButton.icon(
              onPressed: () => showPlansSheet(context),
              icon: const Icon(Icons.rocket_launch_rounded, size: 18),
              label: Text(isPaid ? (s['renewOrUpgrade'] ?? s['upgradePlan']!) : s['upgradePlan']!),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))))),
          ]),
        ),

        // ── 2. Bind email banner (device users only) ──
        if (!hasEmail && showAuthPanel.value) ...[const SizedBox(height: 12), _AuthPanel(onSuccess: reload)],
        if (!hasEmail && !showAuthPanel.value) ...[
          const SizedBox(height: 12),
          Material(color: Colors.transparent, child: InkWell(
            onTap: () => showAuthPanel.value = true,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.shade100)),
              child: Row(children: [
                Icon(Icons.devices_rounded, size: 20, color: Colors.blue.shade700),
                const SizedBox(width: 12),
                Expanded(child: Text(s['bindEmailBanner'] ?? '绑定邮箱，换机不丢账号，多设备同步',
                  style: TextStyle(fontSize: 13, color: Colors.blue.shade800))),
                Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.blue.shade400),
              ])))),
        ],

        // ── 3. Invite card (merged: invite info + apply code) ──
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Tappable invite header → InviteRewardsPage
            InkWell(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const InviteRewardsPage()),
              ),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                    child: const Icon(Icons.card_giftcard_rounded, size: 22, color: Colors.green),
                  ),
                  const SizedBox(width: 14),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(s['inviteTitle']!, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(
                      invCount > 0
                          ? '${s['inviteCount']} $invCount${s['invitePeople']}  ·  ${s['inviteBonusReward']} $bonusDays${s['inviteBonusDays']}'
                          : s['guideInviteDesc']!,
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                  ])),
                  Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.grey.shade400),
                ]),
              ),
            ),
            // Apply invite code (inline, only if not yet used)
            if (!hasUsedInvite) ...[
              Divider(height: 1, indent: 16, endIndent: 16, color: Colors.grey.shade200),
              _InlineApplyInvite(onSuccess: reload),
            ],
          ]),
        ),

        // ── 4. Service & Support ──
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(children: [
            _ActionTile(
              icon: Icons.support_agent_rounded,
              iconColor: Colors.blue,
              label: s['ticketBtn'] ?? '问题反馈',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const TicketListPage()),
              ),
            ),
            Divider(height: 1, indent: 52, color: Colors.grey.shade200),
            _ActionTile(
              icon: Icons.receipt_long_rounded,
              iconColor: Colors.grey.shade600,
              label: s['orderHistory'] ?? '订单记录',
              onTap: () => _showOrderHistorySheet(context),
            ),
            Divider(height: 1, indent: 52, color: Colors.grey.shade200),
            _ResetSubscriptionTile(onReset: reload),
          ]),
        ),

        // ── 5. Account & Security ──
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(children: [
            if (hasEmail) ...[
              _ActionTile(
                icon: Icons.lock_outline_rounded,
                iconColor: Colors.grey.shade600,
                label: s['changePassword']!,
                onTap: () => _showChangePasswordSheet(context),
              ),
              Divider(height: 1, indent: 52, color: Colors.grey.shade200),
            ],
            _ActionTile(
              icon: Icons.delete_outline_rounded,
              iconColor: Colors.red.shade300,
              label: s['deleteAccountBtn'] ?? '注销账号',
              onTap: () => _showDeleteAccountDialog(context, reload),
            ),
          ]),
        ),

        // ── 6. Logout (bottom) ──
        if (hasEmail) ...[
          const SizedBox(height: 24),
          Center(child: TextButton.icon(
            onPressed: () async {
              final s = AuthI18n.t;
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Text(s['logout']!),
                  content: Text(s['logoutConfirm'] ?? '确定要退出登录吗？'),
                  actions: [
                    TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(s['cancel'] ?? '取消')),
                    TextButton(onPressed: () => Navigator.of(ctx).pop(true),
                      child: Text(s['logout']!, style: const TextStyle(color: Colors.red))),
                  ],
                ),
              );
              if (confirmed == true) {
                final p = await SharedPreferences.getInstance();
                await AuthService(p).logout();
                reload();
              }
            },
            icon: const Icon(Icons.logout_rounded, size: 18, color: Colors.red),
            label: Text(s['logout']!, style: const TextStyle(color: Colors.red)),
          )),
        ],
        const SizedBox(height: 32),
      ]),
    );
  }

  static Widget _buildSection(ThemeData theme, String title, List<Widget> children) {
    return Container(padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
        const SizedBox(height: 8), ...children,
      ]));
  }

  static Widget _infoRow(String label, String value, Color? valueColor) {
    return Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
        Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: valueColor ?? Colors.black87)),
      ]));
  }

  static String _fmtDate(dynamic d) {
    if (d == null) return '-';
    final s = d.toString();
    return s.length >= 10 ? s.substring(0, 10) : s;
  }

  static String _fmtDateWithDays(dynamic d) {
    if (d == null) return '-';
    final s = d.toString();
    final dateStr = s.length >= 10 ? s.substring(0, 10) : s;
    try {
      final expire = DateTime.parse(s);
      final remaining = expire.difference(DateTime.now()).inDays;
      if (remaining >= 0) return '$dateStr（${remaining}天）';
      return '$dateStr（已过期）';
    } catch (_) {
      return dateStr;
    }
  }
}

/// Compact inline invite code input — sits inside the invite card.
class _InlineApplyInvite extends HookWidget {
  final VoidCallback onSuccess;
  const _InlineApplyInvite({required this.onSuccess});

  @override
  Widget build(BuildContext context) {
    final s = AuthI18n.t;
    final ctrl = useTextEditingController();
    final isLoading = useState(false);
    final errorMsg = useState<String?>(null);

    Future<void> apply() async {
      final code = ctrl.text.trim();
      if (code.isEmpty) return;
      if (!RegExp(r'^[a-zA-Z0-9]{4,20}$').hasMatch(code)) {
        errorMsg.value = s['invalidInviteCode'] ?? '邀请码格式不正确';
        return;
      }
      isLoading.value = true; errorMsg.value = null;
      final prefs = await SharedPreferences.getInstance();
      final result = await AuthService(prefs).applyInvite(code);
      isLoading.value = false;
      if (result == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s['inviteApplied']!), duration: const Duration(seconds: 2)));
        }
        onSuccess();
      } else { errorMsg.value = result; }
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(s['applyInviteCode']!, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: SizedBox(height: 38, child: TextField(
            controller: ctrl,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              hintText: s['inviteCodeHint'],
              hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade400),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            ),
          ))),
          const SizedBox(width: 8),
          SizedBox(height: 38, child: FilledButton(
            onPressed: isLoading.value ? null : apply,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            child: isLoading.value
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text(s['confirm']!, style: const TextStyle(fontSize: 13)),
          )),
        ]),
        if (errorMsg.value != null) ...[
          const SizedBox(height: 4),
          Text(errorMsg.value!, style: const TextStyle(color: Colors.red, fontSize: 11)),
        ],
      ]),
    );
  }
}

/// Show order history as a bottom sheet.
void _showOrderHistorySheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (_) => DraggableScrollableSheet(
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      minChildSize: 0.3,
      expand: false,
      builder: (ctx, scrollCtrl) => Column(children: [
        const SizedBox(height: 12),
        Container(width: 36, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 12),
        Text(AuthI18n.t['orderHistory'] ?? '订单记录', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Expanded(child: _OrderHistoryList(scrollController: scrollCtrl)),
      ]),
    ),
  );
}

/// Order history list content for the bottom sheet.
class _OrderHistoryList extends HookWidget {
  final ScrollController scrollController;
  const _OrderHistoryList({required this.scrollController});

  @override
  Widget build(BuildContext context) {
    final s = AuthI18n.t;
    final orders = useState<List<Map<String, dynamic>>>([]);
    final isLoading = useState(true);
    final expandedOrderNo = useState<String?>(null);

    useEffect(() {
      () async {
        final prefs = await SharedPreferences.getInstance();
        final auth = AuthService(prefs);
        final all = await auth.getMyOrders();
        orders.value = all.where((o) => o['status'] == 'paid').toList();
        isLoading.value = false;
      }();
      return null;
    }, []);

    if (isLoading.value) {
      return const Center(child: CircularProgressIndicator());
    }
    if (orders.value.isEmpty) {
      return Center(child: Text('暂无订单', style: TextStyle(fontSize: 14, color: Colors.grey.shade500)));
    }

    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: orders.value.length,
      itemBuilder: (ctx, i) {
        final o = orders.value[i];
        final orderNo = o['order_no'] as String? ?? '';
        final isDetail = expandedOrderNo.value == orderNo;
        final amount = o['amount_cny'] != null
            ? '¥${o['amount_cny']}'
            : (o['pay_amount_usdt'] != null
                ? '\$${(o['pay_amount_usdt'] as num).toStringAsFixed(2)}'
                : '\$${(o['amount_usdt'] as num).toStringAsFixed(2)}');
        final created = o['created_at'] as String? ?? '';
        final paidAt = o['paid_at'] as String? ?? '';
        final dateStr = created.length >= 10 ? created.substring(0, 10) : created;
        final paidDateStr = paidAt.length >= 16 ? paidAt.substring(0, 16).replaceAll('T', ' ') : paidAt;
        final days = o['days'] ?? 0;
        final bonusDays = o['bonus_days'] ?? 0;
        final method = o['payment_method'] as String? ?? '';
        final methodLabel = const {'alipay': '支付宝', 'wechat': '微信', 'usdt': 'USDT', 'usdc': 'USDC'}[method] ?? method;

        return GestureDetector(
          onTap: () => expandedOrderNo.value = isDetail ? null : orderNo,
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDetail ? Colors.white : Colors.grey.shade50,
              borderRadius: BorderRadius.circular(10),
              border: isDetail ? Border.all(color: Colors.green.shade100) : null,
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(o['plan_name'] ?? '', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 2),
                  Text(dateStr, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                ])),
                Text(amount, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                  child: const Text('已支付', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.green)),
                ),
                const SizedBox(width: 4),
                Icon(isDetail ? Icons.expand_less : Icons.expand_more, size: 16, color: Colors.grey.shade400),
              ]),
              if (isDetail) ...[
                const SizedBox(height: 10),
                Divider(height: 1, color: Colors.grey.shade200),
                const SizedBox(height: 10),
                _orderDetailRow('订单号', orderNo),
                _orderDetailRow('支付方式', methodLabel),
                _orderDetailRow('套餐时长', '$days 天${bonusDays > 0 ? ' (+$bonusDays天赠送)' : ''}'),
                _orderDetailRow('支付时间', paidDateStr),
              ],
            ]),
          ),
        );
      },
    );
  }

  static Widget _orderDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        SizedBox(width: 70, child: Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade500))),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 12, color: Colors.black87))),
      ]),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final VoidCallback onTap;
  const _ActionTile({required this.icon, required this.iconColor, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(children: [
          Icon(icon, size: 20, color: iconColor),
          const SizedBox(width: 14),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 14))),
          Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.grey.shade400),
        ]),
      ),
    );
  }
}

class _ResetSubscriptionTile extends HookWidget {
  final VoidCallback onReset;
  const _ResetSubscriptionTile({required this.onReset});

  @override
  Widget build(BuildContext context) {
    final s = AuthI18n.t;
    final isLoading = useState(false);

    Future<void> doReset() async {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(s['resetSubBtn'] ?? '重置订阅链接'),
          content: Text(s['resetSubConfirm'] ?? '重置后旧订阅链接将立即失效，所有客户端需重新导入新链接。\n\n确认重置？'),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(s['cancel'] ?? '取消')),
            TextButton(onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(s['resetSubBtn'] ?? '重置', style: const TextStyle(color: Colors.red))),
          ],
        ),
      );
      if (confirmed != true) return;
      isLoading.value = true;
      final prefs = await SharedPreferences.getInstance();
      final result = await AuthService(prefs).resetSubscription();
      isLoading.value = false;
      if (result['ok'] == true) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(s['resetSubSuccess'] ?? '订阅链接已重置'),
            duration: const Duration(seconds: 4)));
        }
        onReset();
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text((result['detail'] ?? s['resetSubFail'] ?? '重置失败').toString()),
            backgroundColor: Colors.red, duration: const Duration(seconds: 3)));
        }
      }
    }

    return InkWell(
      onTap: isLoading.value ? null : doReset,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(children: [
          isLoading.value
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : Icon(Icons.refresh_rounded, size: 20, color: Colors.grey.shade600),
          const SizedBox(width: 14),
          Expanded(child: Text(s['resetSubBtn'] ?? '重置订阅链接', style: const TextStyle(fontSize: 14))),
          Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.grey.shade400),
        ]),
      ),
    );
  }
}

void _showChangePasswordSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (_) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: const _ChangePasswordSheet(),
    ),
  );
}

void _showDeleteAccountDialog(BuildContext context, VoidCallback reload) {
  final s = AuthI18n.t;
  showDialog(
    context: context,
    builder: (ctx) {
      final passCtrl = TextEditingController();
      // Check if user has email (needs password confirmation)
      return _DeleteAccountDialog(onDeleted: reload);
    },
  );
}

class _DeleteAccountDialog extends StatefulWidget {
  final VoidCallback onDeleted;
  const _DeleteAccountDialog({required this.onDeleted});
  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  final _passCtrl = TextEditingController();
  bool _isLoading = false;
  String? _error;
  bool _hasEmail = false;

  @override
  void initState() {
    super.initState();
    _checkEmail();
  }

  Future<void> _checkEmail() async {
    final prefs = await SharedPreferences.getInstance();
    final auth = AuthService(prefs);
    final info = await auth.getUserInfo();
    if (mounted) {
      setState(() {
        final email = info?['email'];
        _hasEmail = email != null && email.toString().isNotEmpty;
      });
    }
  }

  @override
  void dispose() {
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _doDelete() async {
    final s = AuthI18n.t;
    if (_hasEmail && _passCtrl.text.isEmpty) {
      setState(() => _error = s['fillFields'] ?? '请输入密码');
      return;
    }
    setState(() { _isLoading = true; _error = null; });
    final prefs = await SharedPreferences.getInstance();
    final result = await AuthService(prefs).deleteAccount(password: _passCtrl.text);
    if (!mounted) return;
    if (result == null) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s['deleteAccountDone'] ?? '账号已注销')),
      );
      widget.onDeleted();
    } else {
      setState(() { _isLoading = false; _error = result; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AuthI18n.t;
    return AlertDialog(
      title: Text(s['deleteAccountBtn'] ?? '注销账号'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(s['deleteAccountConfirm'] ?? '注销后账号数据将被清除，此操作不可恢复。'),
        if (_hasEmail) ...[
          const SizedBox(height: 16),
          TextField(
            controller: _passCtrl,
            obscureText: true,
            decoration: InputDecoration(
              labelText: s['password'] ?? '密码',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              isDense: true,
            ),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
        ],
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(s['cancel'] ?? '取消')),
        TextButton(
          onPressed: _isLoading ? null : _doDelete,
          child: _isLoading
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(s['deleteAccountBtn'] ?? '注销', style: const TextStyle(color: Colors.red)),
        ),
      ],
    );
  }
}

void _launchForgotPassword(BuildContext context) {
  launchUrl(Uri.parse('https://roxi.cc/web/reset-password'), mode: LaunchMode.externalApplication);
}

class _AuthPanel extends HookWidget {
  final VoidCallback onSuccess;
  const _AuthPanel({required this.onSuccess});

  @override
  Widget build(BuildContext context) {
    final s = AuthI18n.t;
    final isRegister = useState(true);
    final isLoading = useState(false);
    final emailCtrl = useTextEditingController();
    final passCtrl = useTextEditingController();
    final inviteCtrl = useTextEditingController();
    final codeCtrl = useTextEditingController();
    final errorMsg = useState<String?>(null);
    final codeCooldown = useState(0);
    final codeSent = useState(false);
    final obscurePass = useState(true);

    // Countdown timer
    useEffect(() {
      if (codeCooldown.value <= 0) return null;
      Future.delayed(const Duration(seconds: 1), () {
        if (codeCooldown.value > 0) codeCooldown.value--;
      });
      return null;
    }, [codeCooldown.value]);

    Future<void> sendCode() async {
      final em = emailCtrl.text.trim();
      if (em.isEmpty || !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(em)) {
        errorMsg.value = s['invalidEmail'] ?? '请输入有效的邮箱地址';
        return;
      }
      errorMsg.value = null;
      final prefs = await SharedPreferences.getInstance();
      final auth = AuthService(prefs);
      final err = await auth.sendVerifyCode(em);
      if (err == null) {
        codeSent.value = true;
        codeCooldown.value = 60;
      } else {
        errorMsg.value = err;
      }
    }

    Future<void> submit() async {
      final em = emailCtrl.text.trim();
      final pw = passCtrl.text;
      if (em.isEmpty || pw.isEmpty) { errorMsg.value = s['fillFields']; return; }
      if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(em)) { errorMsg.value = s['invalidEmail'] ?? '邮箱格式不正确'; return; }
      if (pw.length < 6) { errorMsg.value = s['passMin6']; return; }
      isLoading.value = true; errorMsg.value = null;
      final prefs = await SharedPreferences.getInstance();
      final auth = AuthService(prefs);
      final String? result;
      if (isRegister.value) {
        final code = codeCtrl.text.trim();
        if (code.isEmpty) { isLoading.value = false; errorMsg.value = s['enterCode'] ?? '请输入验证码'; return; }
        result = await auth.bindEmail(em, pw, code: code);
      } else {
        result = await auth.login(em, pw);
      }
      isLoading.value = false;
      if (result == null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(isRegister.value ? s['bindSuccess']! : s['loginSuccess']!), duration: const Duration(seconds: 2)));
        onSuccess();
      } else { errorMsg.value = result; }
    }

    return Container(padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.blue.shade100),
        boxShadow: [BoxShadow(color: Colors.blue.withOpacity(0.06), blurRadius: 12, offset: const Offset(0, 4))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.devices_rounded, size: 20, color: Colors.blue.shade600), const SizedBox(width: 8),
          Expanded(child: Text(s['bindEmailBanner'] ?? '绑定邮箱，换机不丢账号，多设备同步',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade700))),
        ]),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: _tab(s['register']!, isRegister.value, () => isRegister.value = true)),
          const SizedBox(width: 8),
          Expanded(child: _tab(s['login']!, !isRegister.value, () => isRegister.value = false)),
        ]),
        const SizedBox(height: 16),
        TextField(controller: emailCtrl, keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(labelText: s['email'], prefixIcon: const Icon(Icons.email_outlined, size: 20),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)), isDense: true)),
        const SizedBox(height: 12),
        TextField(controller: passCtrl, obscureText: obscurePass.value, onSubmitted: (_) => submit(),
          decoration: InputDecoration(labelText: s['password'], prefixIcon: const Icon(Icons.lock_outlined, size: 20),
            suffixIcon: IconButton(
              icon: Icon(obscurePass.value ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20),
              onPressed: () => obscurePass.value = !obscurePass.value,
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)), isDense: true)),
        if (!isRegister.value) ...[
          const SizedBox(height: 6),
          Align(alignment: Alignment.centerRight,
            child: GestureDetector(
              onTap: () => _launchForgotPassword(context),
              child: Text(s['forgotPassword'] ?? '忘记密码？',
                style: TextStyle(fontSize: 12, color: Colors.blue.shade600)))),
        ],
        if (isRegister.value) ...[const SizedBox(height: 12),
          TextField(controller: inviteCtrl,
            decoration: InputDecoration(labelText: s['inviteCode'], prefixIcon: const Icon(Icons.card_giftcard_outlined, size: 20),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)), isDense: true)),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: TextField(controller: codeCtrl, keyboardType: TextInputType.number, maxLength: 6,
              decoration: InputDecoration(labelText: s['verifyCode'] ?? '验证码', prefixIcon: const Icon(Icons.verified_outlined, size: 20),
                counterText: '', border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)), isDense: true))),
            const SizedBox(width: 8),
            SizedBox(height: 44, child: FilledButton.tonal(
              onPressed: codeCooldown.value > 0 ? null : sendCode,
              child: Text(codeCooldown.value > 0 ? '${codeCooldown.value}s' : (codeSent.value ? (s['resendBtn'] ?? '重发') : (s['sendBtn'] ?? '发送')), style: const TextStyle(fontSize: 13)))),
          ]),
        ],
        if (errorMsg.value != null) ...[const SizedBox(height: 8), Text(errorMsg.value!, style: const TextStyle(color: Colors.red, fontSize: 12))],
        const SizedBox(height: 16),
        SizedBox(width: double.infinity, height: 44, child: FilledButton(
          onPressed: isLoading.value ? null : submit,
          style: FilledButton.styleFrom(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
          child: isLoading.value
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : Text(isRegister.value ? s['register']! : s['login']!))),
      ]));
  }

  Widget _tab(String label, bool active, VoidCallback onTap) {
    return GestureDetector(onTap: onTap, child: Container(
      padding: const EdgeInsets.symmetric(vertical: 8), alignment: Alignment.center,
      decoration: BoxDecoration(color: active ? Colors.blue : Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
      child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: active ? Colors.white : Colors.grey.shade600))));
  }
}

class _ChangePasswordSheet extends HookWidget {
  const _ChangePasswordSheet();

  @override
  Widget build(BuildContext context) {
    final s = AuthI18n.t;
    final oldCtrl = useTextEditingController();
    final newCtrl = useTextEditingController();
    final confirmCtrl = useTextEditingController();
    final isLoading = useState(false);
    final errorMsg = useState<String?>(null);

    Future<void> submit() async {
      if (newCtrl.text != confirmCtrl.text) { errorMsg.value = s['passwordMismatch']; return; }
      if (newCtrl.text.length < 6) { errorMsg.value = s['passMin6']; return; }
      isLoading.value = true; errorMsg.value = null;
      final prefs = await SharedPreferences.getInstance();
      final result = await AuthService(prefs).changePassword(oldCtrl.text, newCtrl.text);
      isLoading.value = false;
      if (result == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s['passwordChanged']!), duration: const Duration(seconds: 2)));
          Navigator.of(context).pop();
        }
      } else { errorMsg.value = result; }
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
        const SizedBox(height: 16),
        Text(s['changePassword']!, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        const SizedBox(height: 16),
        TextField(controller: oldCtrl, obscureText: true,
          decoration: InputDecoration(labelText: s['oldPassword'], border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)), isDense: true)),
        const SizedBox(height: 12),
        TextField(controller: newCtrl, obscureText: true,
          decoration: InputDecoration(labelText: s['newPassword'], border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)), isDense: true)),
        const SizedBox(height: 12),
        TextField(controller: confirmCtrl, obscureText: true, onSubmitted: (_) => submit(),
          decoration: InputDecoration(labelText: s['confirmPassword'], border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)), isDense: true)),
        if (errorMsg.value != null) ...[const SizedBox(height: 8), Text(errorMsg.value!, style: const TextStyle(color: Colors.red, fontSize: 12))],
        const SizedBox(height: 16),
        SizedBox(width: double.infinity, child: FilledButton(
          onPressed: isLoading.value ? null : submit,
          style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
          child: isLoading.value
            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : Text(s['changePwdBtn']!))),
      ]),
    );
  }
}
