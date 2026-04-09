import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hiddify/features/auth/data/auth_i18n.dart';
import 'package:hiddify/features/auth/data/auth_service.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Show plans as a modal bottom sheet.
Future<void> showPlansSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _PlansSheet(),
  );
}

class _PlansSheet extends HookWidget {
  const _PlansSheet();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = AuthI18n.t;
    final plans = useState<List<Map<String, dynamic>>>([]);
    final isLoading = useState(true);
    final remainingSec = useState<int?>(null);
    final discountLabel = useState<String>('');

    useEffect(() {
      () async {
        final prefs = await SharedPreferences.getInstance();
        final auth = AuthService(prefs);
        final fetched = await auth.getPlans();
        plans.value = fetched;
        // Get countdown and label from first plan that has it
        if (fetched.isNotEmpty) {
          final sec = fetched[0]['discount_remaining_sec'] as int?;
          if (sec != null && sec > 0) remainingSec.value = sec;
          discountLabel.value = (fetched[0]['discount_label'] as String?) ?? '';
        }
        isLoading.value = false;
      }();
      return null;
    }, []);

    // Countdown timer
    useEffect(() {
      if (remainingSec.value == null || remainingSec.value! <= 0) return null;
      final timer = Timer.periodic(const Duration(seconds: 1), (_) {
        final cur = remainingSec.value ?? 0;
        if (cur <= 0) return;
        remainingSec.value = cur - 1;
      });
      return timer.cancel;
    }, [remainingSec.value != null]);

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.92,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.max,
        children: [
          // Handle bar + close
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
            child: Row(
              children: [
                const Spacer(),
                Container(
                  width: 36, height: 4,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.onSurfaceVariant.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          Text(
            s['unlockNodes']!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          // Countdown banner
          if (remainingSec.value != null && remainingSec.value! > 0)
            _CountdownBanner(
              remainingSec: remainingSec.value!,
              label: discountLabel.value,
            ),
          const SizedBox(height: 8),
          if (isLoading.value)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            )
          else
            Flexible(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                shrinkWrap: true,
                itemCount: plans.value.length,
                itemBuilder: (ctx, i) => _PlanCard(
                  plan: plans.value[i],
                  onBuy: () => _handleBuy(context, plans.value[i]),
                  discountActive: remainingSec.value != null && remainingSec.value! > 0,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _handleBuy(BuildContext context, Map<String, dynamic> plan) async {
    final s = AuthI18n.t;
    // Show payment method picker
    final method = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => _PayMethodPicker(),
    );
    if (method == null || !context.mounted) return;

    if (method == 'usdt') {
      await _handleUsdtBuy(context, plan);
    } else {
      await _handleCNYBuy(context, plan, method);
    }
  }

  Future<void> _handleUsdtBuy(BuildContext context, Map<String, dynamic> plan) async {
    final s = AuthI18n.t;
    final prefs = await SharedPreferences.getInstance();
    final auth = AuthService(prefs);

    if (!context.mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final order = await auth.createOrder(plan['id']).timeout(const Duration(seconds: 15));
      if (!context.mounted) return;
      Navigator.of(context).pop(); // dismiss loading

      if (order == null || order['error'] == true) {
        final detail = order?['detail'] ?? s['orderFailed']!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$detail')),
        );
        return;
      }

      final info = await auth.getPayInfo(order['order_no']).timeout(const Duration(seconds: 10));
      if (info == null || !context.mounted) return;

      final paid = await showDialog<bool>(
        context: context,
        barrierDismissible: true,
        builder: (_) => _PaymentDialog(
          payInfo: info,
          orderNo: order['order_no'] as String,
          planName: plan['name'] ?? '',
        ),
      );

      if (paid == true && context.mounted) {
        Navigator.of(context).pop();
      }
    } catch (_) {
      if (context.mounted) {
        Navigator.of(context).pop(); // dismiss loading
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s['orderFailed']!)),
        );
      }
    }
  }

  Future<void> _handleCNYBuy(BuildContext context, Map<String, dynamic> plan, String channel) async {
    final s = AuthI18n.t;
    final prefs = await SharedPreferences.getInstance();
    final auth = AuthService(prefs);

    if (!context.mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final result = await auth.createCNYOrder(plan['id'], channel).timeout(const Duration(seconds: 15));
      if (!context.mounted) return;
      Navigator.of(context).pop(); // dismiss loading

      if (result == null || result['error'] == true) {
        final detail = result?['detail'] ?? s['orderFailed']!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$detail')),
        );
        return;
      }

      final payUrl = result['pay_url'] as String? ?? '';
      final orderNo = result['order_no'] as String? ?? '';

      if (payUrl.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s['payLinkFailed'] ?? '获取支付链接失败')),
        );
        return;
      }

      // Show CNY payment dialog with webview-like pay URL
      final paid = await showDialog<bool>(
        context: context,
        barrierDismissible: true,
        builder: (_) => _CNYPaymentDialog(
          payUrl: payUrl,
          orderNo: orderNo,
          planName: plan['name'] ?? '',
          channel: channel,
          amount: (result['amount_cny'] as num?)?.toDouble() ?? 0,
        ),
      );

      if (paid == true && context.mounted) {
        Navigator.of(context).pop();
      }
    } catch (_) {
      if (context.mounted) {
        Navigator.of(context).pop(); // dismiss loading
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s['orderFailed']!)),
        );
      }
    }
  }
}

/// Countdown banner — dynamic label per wave
class _CountdownBanner extends StatelessWidget {
  final int remainingSec;
  final String label;
  const _CountdownBanner({required this.remainingSec, this.label = ''});

  String _fmt(int totalSec) {
    final h = totalSec ~/ 3600;
    final m = (totalSec % 3600) ~/ 60;
    final s = totalSec % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    // Pick gradient colors based on wave label
    final isWave2 = label.contains('神秘');
    final isWave3 = label.contains('最后');
    final List<Color> colors = isWave3
        ? [Colors.purple.shade400, Colors.red.shade400]
        : isWave2
            ? [Colors.deepOrange.shade400, Colors.pink.shade400]
            : [Colors.red.shade400, Colors.orange.shade400];

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: colors),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Text(isWave3 ? '⚡' : isWave2 ? '🎁' : '🔥', style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label.isNotEmpty ? label : '限时优惠',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '倒计时 ${_fmt(remainingSec)}',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 13,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  final Map<String, dynamic> plan;
  final VoidCallback onBuy;
  final bool discountActive;

  const _PlanCard({required this.plan, required this.onBuy, this.discountActive = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = AuthI18n.t;
    final tier = plan['tier'] ?? 'vip';
    final isVip = tier == 'vip';
    final trafficGb = plan['traffic_gb'] ?? 0;
    final trafficText = trafficGb == 0 ? s['unlimited']! : '${trafficGb.toStringAsFixed(0)}GB';
    final discountLabel = plan['discount_label'] as String?;
    final discountCny = plan['discount_price_cny'];
    final hasDiscount = discountActive && discountLabel != null && discountCny != null;
    final nameHasDiscount = (plan['name'] ?? '').toString().contains('折');
    final showDiscountBadge = hasDiscount && !nameHasDiscount;
    final days = (plan['days'] as num?)?.toInt() ?? 0;
    final isRecommended = isVip && days >= 365;
    final actualPrice = hasDiscount ? (discountCny as num).toDouble() : ((plan['price_cny'] as num?)?.toDouble() ?? 0);
    final perDay = days > 0 ? actualPrice / days : 0.0;
    final perDayText = '约 ¥${perDay.toStringAsFixed(1)}/天';

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isRecommended
            ? BorderSide(color: theme.colorScheme.primary, width: 1.5)
            : isVip
                ? BorderSide.none
                : BorderSide(color: Colors.amber.withOpacity(0.5)),
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: isVip
                      ? theme.colorScheme.primaryContainer
                      : Colors.amber.withOpacity(0.2),
                  child: Text(
                    isVip ? 'V' : 'S',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: isVip ? theme.colorScheme.primary : Colors.amber,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(plan['name'] ?? '', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                          if (showDiscountBadge) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: Colors.red.shade50,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: Colors.red.shade200),
                              ),
                              child: Text(
                                '九折',
                                style: TextStyle(fontSize: 9, color: Colors.red.shade700, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 1),
                      Text(
                        perDayText,
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (hasDiscount) ...[
                      Text(
                        '¥${plan['price_cny']}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          decoration: TextDecoration.lineThrough,
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 11,
                        ),
                      ),
                    ],
                    FilledButton.tonal(
                      onPressed: onBuy,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        backgroundColor: hasDiscount ? Colors.red.shade400 : null,
                        foregroundColor: hasDiscount ? Colors.white : null,
                      ),
                      child: Text(
                        hasDiscount ? '¥$discountCny' : '¥${plan['price_cny']}',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // "推荐" badge for annual plan
          if (isRecommended)
            Positioned(
              top: 0,
              right: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(6),
                    bottomRight: Radius.circular(6),
                  ),
                ),
                child: const Text(
                  '推荐',
                  style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
class _PaymentDialog extends HookWidget {
  final Map<String, dynamic> payInfo;
  final String orderNo;
  final String planName;

  const _PaymentDialog({
    required this.payInfo,
    required this.orderNo,
    required this.planName,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = AuthI18n.t;
    final isPaid = useState(false);
    final isChecking = useState(false);

    final address = payInfo['usdt_address'] as String? ?? '';
    final amount = payInfo['pay_amount_usdt'] ?? 0;

    // Poll order status
    useEffect(() {
      Timer? timer;
      timer = Timer.periodic(const Duration(seconds: 10), (_) async {
        if (isPaid.value) { timer?.cancel(); return; }
        isChecking.value = true;
        final prefs = await SharedPreferences.getInstance();
        final auth = AuthService(prefs);
        final status = await auth.checkOrderStatus(orderNo);
        isChecking.value = false;
        if (status == 'paid') {
          isPaid.value = true;
          timer?.cancel();
          await Future.delayed(const Duration(seconds: 1));
          if (context.mounted) Navigator.of(context).pop(true);
        }
      });
      return () => timer?.cancel();
    }, [orderNo]);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      s['usdtPay']!,
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.of(context).pop(false),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(planName, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Text('$amount USDT', style: theme.textTheme.headlineMedium?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text(s['exactAmount']!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant, fontSize: 11)),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                child: QrImageView(data: address, version: QrVersions.auto, size: 200, backgroundColor: Colors.white,
                  eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Color(0xFF1a1a2e)),
                  dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: Color(0xFF1a1a2e))),
              ),
              const SizedBox(height: 8),
              Text('TRC-20', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              const SizedBox(height: 12),
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () {
                  Clipboard.setData(ClipboardData(text: address));
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s['addressCopied']!)));
                },
                child: Container(
                  width: double.infinity, padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(8)),
                  child: Row(
                    children: [
                      Expanded(child: Text(address, style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace', fontSize: 11))),
                      const SizedBox(width: 8),
                      Icon(Icons.copy_rounded, size: 16, color: theme.colorScheme.primary),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (isPaid.value)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                  decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.check_circle, color: Colors.green, size: 18),
                      const SizedBox(width: 6),
                      Text(s['paySuccess']!, style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                    ],
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                  decoration: BoxDecoration(color: Colors.orange.withOpacity(0.08), borderRadius: BorderRadius.circular(8)),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (isChecking.value)
                        const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      else
                        Container(width: 8, height: 8, decoration: const BoxDecoration(color: Colors.orange, shape: BoxShape.circle)),
                      const SizedBox(width: 8),
                      Text(s['waitingPay']!, style: theme.textTheme.bodySmall?.copyWith(color: Colors.orange)),
                    ],
                  ),
                ),
              const SizedBox(height: 6),
              Text(s['autoDetect']!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant, fontSize: 11)),
            ],
          ),
        ),
      ),
    );
  }
}


/// Payment method picker bottom sheet
class _PayMethodPicker extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurfaceVariant.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Text(AuthI18n.t['selectPayMethod'] ?? '选择支付方式', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            _PayMethodTile(
              icon: Icons.payment_rounded,
              color: const Color(0xFF1677FF),
              label: AuthI18n.t['alipay'] ?? '支付宝',
              subtitle: AuthI18n.t['recommended'] ?? '推荐',
              onTap: () => Navigator.of(context).pop('alipay'),
            ),
            const SizedBox(height: 8),
            _PayMethodTile(
              icon: Icons.chat_rounded,
              color: const Color(0xFF07C160),
              label: AuthI18n.t['wechatPay'] ?? '微信支付',
              subtitle: '',
              onTap: () => Navigator.of(context).pop('wechat'),
            ),
            const SizedBox(height: 8),
            _PayMethodTile(
              icon: Icons.currency_bitcoin_rounded,
              color: const Color(0xFF26A17B),
              label: 'USDT (TRC-20)',
              subtitle: AuthI18n.t['cryptoPay'] ?? '加密货币',
              onTap: () => Navigator.of(context).pop('usdt'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PayMethodTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  const _PayMethodTile({
    required this.icon, required this.color,
    required this.label, required this.subtitle, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          border: Border.all(color: theme.colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: color.withOpacity(0.1),
              radius: 20,
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
                  if (subtitle.isNotEmpty)
                    Text(subtitle, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: theme.colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

/// CNY Payment dialog — shows pay URL and polls order status
class _CNYPaymentDialog extends HookWidget {
  final String payUrl;
  final String orderNo;
  final String planName;
  final String channel;
  final double amount;

  const _CNYPaymentDialog({
    required this.payUrl,
    required this.orderNo,
    required this.planName,
    required this.channel,
    required this.amount,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = AuthI18n.t;
    final isPaid = useState(false);
    final isChecking = useState(false);
    final channelLabel = channel == 'alipay' ? '支付宝' : '微信支付';
    final channelColor = channel == 'alipay' ? const Color(0xFF1677FF) : const Color(0xFF07C160);

    // Poll order status every 5s
    useEffect(() {
      Timer? timer;
      timer = Timer.periodic(const Duration(seconds: 5), (_) async {
        if (isPaid.value) { timer?.cancel(); return; }
        isChecking.value = true;
        final prefs = await SharedPreferences.getInstance();
        final auth = AuthService(prefs);
        final status = await auth.checkOrderStatus(orderNo);
        isChecking.value = false;
        if (status == 'paid') {
          isPaid.value = true;
          timer?.cancel();
          await Future.delayed(const Duration(seconds: 1));
          if (context.mounted) Navigator.of(context).pop(true);
        }
      });
      return () => timer?.cancel();
    }, [orderNo]);

    // Auto open pay URL
    useEffect(() {
      if (payUrl.isNotEmpty) {
        _launchUrl(payUrl);
      }
      return null;
    }, []);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '$channelLabel 支付',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => Navigator.of(context).pop(false),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(planName, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 16),
            // Amount display
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: channelColor.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Text(
                    '¥${amount.toStringAsFixed(2)}',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      color: channelColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // QR code for pay URL
            if (payUrl.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                child: QrImageView(
                  data: payUrl,
                  version: QrVersions.auto,
                  size: 200,
                  backgroundColor: Colors.white,
                  eyeStyle: QrEyeStyle(eyeShape: QrEyeShape.square, color: channelColor),
                  dataModuleStyle: QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: channelColor),
                ),
              ),
            const SizedBox(height: 8),
            Text(AuthI18n.t['scanToPay'] ?? '${channelLabel}扫码支付', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 12),
            // Copy link button
            OutlinedButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: payUrl));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(AuthI18n.t['payLinkCopied'] ?? '支付链接已复制')),
                );
              },
              icon: const Icon(Icons.copy_rounded, size: 16),
              label: Text(AuthI18n.t['copyPayLink'] ?? '复制支付链接'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
            ),
            const SizedBox(height: 16),
            // Status indicator
            if (isPaid.value)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.check_circle, color: Colors.green, size: 18),
                    const SizedBox(width: 6),
                    Text(s['paySuccess']!, style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                  ],
                ),
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                decoration: BoxDecoration(color: Colors.orange.withOpacity(0.08), borderRadius: BorderRadius.circular(8)),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (isChecking.value)
                      const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                    else
                      Container(width: 8, height: 8, decoration: const BoxDecoration(color: Colors.orange, shape: BoxShape.circle)),
                    const SizedBox(width: 8),
                    Text(s['waitingPay']!, style: theme.textTheme.bodySmall?.copyWith(color: Colors.orange)),
                  ],
                ),
              ),
            const SizedBox(height: 6),
            Text(AuthI18n.t['payAutoConfirm'] ?? '支付完成后自动确认', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant, fontSize: 11)),
          ],
        ),
      ),
    );
  }

  Future<void> _launchUrl(String url) async {
    try {
      final uri = Uri.parse(url);
      // Use url_launcher if available, otherwise just copy
      // For now we show QR code which is the primary flow
    } catch (_) {}
  }
}
