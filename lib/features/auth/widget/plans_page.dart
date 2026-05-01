import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hiddify/features/auth/data/auth_i18n.dart';
import 'package:hiddify/features/auth/data/auth_service.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

/// Global event bus for payment success — listeners refresh user info.
class PaymentEvents {
  static final List<VoidCallback> _listeners = [];
  static void addListener(VoidCallback cb) => _listeners.add(cb);
  static void removeListener(VoidCallback cb) => _listeners.remove(cb);
  static void notifySuccess() {
    for (final cb in List.of(_listeners)) { cb(); }
  }
}

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
    final loadError = useState(false);
    final remainingSec = useState<int?>(null);
    final discountLabel = useState<String>('');
    final selectedIndex = useState<int?>(null);

    Future<void> loadPlans() async {
      isLoading.value = true;
      loadError.value = false;
      try {
        final prefs = await SharedPreferences.getInstance();
        final auth = AuthService(prefs);
        final fetched = await auth.getPlans(forceRefresh: true).timeout(const Duration(seconds: 12));
        plans.value = fetched;
        if (fetched.isNotEmpty) {
          final sec = fetched[0]['discount_remaining_sec'] as int?;
          if (sec != null && sec > 0) remainingSec.value = sec;
          discountLabel.value = (fetched[0]['discount_label'] as String?) ?? '';
          // Default select the recommended plan (SVIP 3-day trial), or first
          final recIdx = fetched.indexWhere((p) => (p['tier'] ?? 'vip') == 'svip' && ((p['days'] as num?)?.toInt() ?? 0) <= 3);
          selectedIndex.value = recIdx >= 0 ? recIdx : 0;
        }
        if (fetched.isEmpty) loadError.value = true;
      } catch (_) {
        loadError.value = true;
      }
      isLoading.value = false;
    }

    useEffect(() {
      loadPlans();
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
      decoration: const BoxDecoration(
        color: Color(0xFF12122A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.max,
        children: [
          // Handle bar + title + close
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
            child: Row(
              children: [
                const SizedBox(width: 40), // balance the close button
                const Spacer(),
                Container(
                  width: 36, height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white70),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('💎 ', style: TextStyle(fontSize: 18)),
                Text(
                  s['buyPlan'] ?? '购买套餐',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
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
              child: Center(child: CircularProgressIndicator(color: Colors.white54)),
            )
          else if (loadError.value || plans.value.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.cloud_off_rounded, size: 40, color: Colors.grey.shade600),
                    const SizedBox(height: 12),
                    Text(
                      s['plansLoadFailed'] ?? '加载套餐失败，请检查网络',
                      style: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton(
                      onPressed: loadPlans,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white70,
                        side: BorderSide(color: Colors.white.withOpacity(0.3)),
                      ),
                      child: Text(s['retry'] ?? '重试'),
                    ),
                  ],
                ),
              ),
            )
          else
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                child: _buildPlanSections(context, plans.value, selectedIndex, remainingSec.value),
              ),
            ),
          // Footer — supported payment methods
          Padding(
            padding: const EdgeInsets.only(bottom: 16, top: 4),
            child: Text(
              s['payMethodsHint'] ?? '支持 USDT / USDC 多链 · 支付宝 · 微信 · 余额支付',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleBuy(BuildContext context, Map<String, dynamic> plan) async {
    final s = AuthI18n.t;

    // Check if user has an active subscription — warn before purchasing
    final prefs = await SharedPreferences.getInstance();
    final auth = AuthService(prefs);
    final userInfo = await auth.getUserInfo();
    if (userInfo != null && context.mounted) {
      final currentTier = (userInfo['tier'] as String?) ?? 'free';
      final expStr = userInfo['expire_date']?.toString();
      final isActive = (currentTier == 'vip' || currentTier == 'svip') &&
          expStr != null && expStr.isNotEmpty &&
          DateTime.tryParse(expStr)?.isAfter(DateTime.now()) == true;

      if (isActive) {
        final planTier = (plan['tier'] as String?) ?? 'vip';
        final currentLabel = currentTier == 'svip' ? 'SVIP' : 'VIP';
        final newLabel = planTier == 'svip' ? 'SVIP' : 'VIP';
        final expShort = expStr!.length >= 10 ? expStr.substring(0, 10) : expStr;

        // Build warning message based on tier change
        String msg;
        String title;
        if (currentTier == 'svip' && planTier == 'vip') {
          // Downgrade purchase
          title = s['downgradeTitle'] ?? '⚠️ 降级购买提醒';
          msg = '您当前是 $currentLabel 会员（到期：$expShort）\n\n'
              '购买 $newLabel 套餐后：\n'
              '• $currentLabel 到期前继续享受 $currentLabel 权益\n'
              '• $currentLabel 到期后自动切换为 $newLabel\n'
              '• 新购天数叠加到总到期时间上';
        } else if (currentTier == planTier) {
          // Same tier renewal
          title = s['renewTitle'] ?? '续费确认';
          msg = '您当前是 $currentLabel 会员（到期：$expShort）\n\n'
              '新购天数将叠加到现有到期时间上。';
        } else {
          // Upgrade purchase
          title = s['upgradeTitle'] ?? '升级确认';
          msg = '您当前是 $currentLabel 会员（到期：$expShort）\n\n'
              '升级为 $newLabel 后立即生效，剩余 $currentLabel 天数将按价格比例折算为 $newLabel 天数。';
        }

        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(title),
            content: Text(msg),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(s['cancel'] ?? '取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(s['continueBuy'] ?? '继续购买'),
              ),
            ],
          ),
        );
        if (confirmed != true || !context.mounted) return;
      }
    }

    // Show payment method picker
    final method = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => _PayMethodPicker(),
    );
    if (method == null || !context.mounted) return;

    if (method.startsWith('usdt_') || method == 'usdt' || method.startsWith('usdc_')) {
      // Parse token and chain from method string
      // Format: "usdt_bsc", "usdc_polygon"
      final isUsdc = method.startsWith('usdc');
      final token = isUsdc ? 'usdc' : 'usdt';
      String chain;
      if (method == 'usdt') {
        chain = 'bsc'; // legacy fallback
      } else {
        chain = method.split('_').last; // "bsc", "polygon", "arbitrum", "base"
      }
      await _handleCryptoBuy(context, plan, chain: chain, token: token);
    } else {
      // CNY payment (alipay/wechat) — auto gateway: try xm first, fallback to jlb
      await _handleCNYBuy(context, plan, method);
    }
  }

  Future<void> _handleCryptoBuy(BuildContext context, Map<String, dynamic> plan, {String chain = 'trc20', String token = 'usdt'}) async {
    final s = AuthI18n.t;
    final prefs = await SharedPreferences.getInstance();
    final auth = AuthService(prefs);

    if (!context.mounted) return;

    // Use a dedicated GlobalKey navigator to ensure we close the right dialog
    final loadingRoute = DialogRoute<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    Navigator.of(context, rootNavigator: true).push(loadingRoute);

    void dismissLoading() {
      if (loadingRoute.isActive) {
        Navigator.of(context, rootNavigator: true).removeRoute(loadingRoute);
      }
    }

    try {
      final order = await auth.createOrder(plan['id'], chain: chain, token: token).timeout(const Duration(seconds: 15));
      if (!context.mounted) return;
      dismissLoading();

      if (order == null || order['error'] == true) {
        final detail = order?['detail'] ?? s['orderFailed']!;
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$detail')));
        }
        return;
      }

      final info = await auth.getPayInfo(order['order_no']).timeout(const Duration(seconds: 10));
      if (!context.mounted) return;
      if (info == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(s['orderFailed'] ?? '获取支付信息失败，请重试')),
          );
        }
        return;
      }

      final paid = await showDialog<bool>(
        context: context,
        barrierDismissible: true,
        builder: (_) => _PaymentDialog(
          payInfo: info,
          orderNo: order['order_no'] as String,
          planName: plan['name'] ?? '',
        ),
      );
      // Always refresh user info after payment dialog closes
      // (user may have paid after manually closing, or polling detected it)
      final updatedUser = await auth.getUserInfo();
      if (paid == true) {
        PaymentEvents.notifySuccess();
        // Prompt device users to bind email for account safety
        if (context.mounted && updatedUser != null && updatedUser['email'] == null) {
          _showBindEmailPrompt(context);
        }
      }
    } catch (_) {
      dismissLoading();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s['orderFailed']!)));
      }
    }
  }

  Future<void> _handleCNYBuy(BuildContext context, Map<String, dynamic> plan, String channel) async {
    final s = AuthI18n.t;
    final prefs = await SharedPreferences.getInstance();
    final auth = AuthService(prefs);

    if (!context.mounted) return;

    final loadingRoute = DialogRoute<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    Navigator.of(context, rootNavigator: true).push(loadingRoute);

    void dismissLoading() {
      if (loadingRoute.isActive) {
        Navigator.of(context, rootNavigator: true).removeRoute(loadingRoute);
      }
    }

    try {
      // Auto gateway: try xm (通道1) first, fallback to jlb (通道2) on failure.
      // Matches web frontend behavior — user never sees gateway selection.
      Map<String, dynamic>? result;
      result = await auth.createCNYOrder(plan['id'], channel, gateway: 'xm').timeout(const Duration(seconds: 15));

      // If xm failed, auto-fallback to jlb
      if (result == null || result['error'] == true || (result['pay_url'] as String? ?? '').isEmpty) {
        debugPrint('CNY gateway xm failed: ${result?['detail']}, trying jlb...');
        if (!context.mounted) return;
        result = await auth.createCNYOrder(plan['id'], channel, gateway: 'jlb').timeout(const Duration(seconds: 15));
      }

      if (!context.mounted) return;
      dismissLoading();

      if (result == null || result['error'] == true) {
        final detail = result?['detail'] ?? s['orderFailed']!;
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$detail')),
          );
        }
        return;
      }

      final payUrl = result['pay_url'] as String? ?? '';
      final orderNo = result['order_no'] as String? ?? '';

      if (payUrl.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(s['payLinkFailed'] ?? '获取支付链接失败')),
          );
        }
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
          amount: (result!['amount_cny'] as num?)?.toDouble() ?? 0,
        ),
      );
      // Always refresh user info after payment dialog closes
      final updatedUser = await auth.getUserInfo();
      if (paid == true) {
        PaymentEvents.notifySuccess();
        // Prompt device users to bind email for account safety
        if (context.mounted && updatedUser != null && updatedUser['email'] == null) {
          _showBindEmailPrompt(context);
        }
      }
    } catch (_) {
      dismissLoading();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s['orderFailed']!)),
        );
      }
    }
  }

  /// Build VIP and SVIP sections with grid layout (matching web design).
  Widget _buildPlanSections(
    BuildContext context,
    List<Map<String, dynamic>> plans,
    ValueNotifier<int?> selectedIndex,
    int? remainingSec,
  ) {
    final s = AuthI18n.t;
    final discountActive = remainingSec != null && remainingSec > 0;

    // Split plans by tier
    final vipPlans = <int, Map<String, dynamic>>{};
    final svipPlans = <int, Map<String, dynamic>>{};
    for (int i = 0; i < plans.length; i++) {
      final tier = plans[i]['tier'] ?? 'vip';
      if (tier == 'svip') {
        svipPlans[i] = plans[i];
      } else {
        vipPlans[i] = plans[i];
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // VIP section
        if (vipPlans.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 12, top: 4),
            child: Row(
              children: [
                const Text('⭐ ', style: TextStyle(fontSize: 16)),
                Text(
                  'VIP',
                  style: const TextStyle(
                    color: Color(0xFFD4A017),
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          _buildPlanGrid(context, vipPlans, selectedIndex, discountActive),
        ],
        // SVIP section
        if (svipPlans.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 12, top: 16),
            child: Row(
              children: [
                const Text('🔥 ', style: TextStyle(fontSize: 16)),
                Text(
                  'SVIP',
                  style: const TextStyle(
                    color: Color(0xFFFF6B9D),
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          _buildPlanGrid(context, svipPlans, selectedIndex, discountActive),
        ],
      ],
    );
  }

  /// Build a responsive grid of plan cards (2 columns on phone, 3 on wide screens).
  Widget _buildPlanGrid(
    BuildContext context,
    Map<int, Map<String, dynamic>> indexedPlans,
    ValueNotifier<int?> selectedIndex,
    bool discountActive,
  ) {
    final entries = indexedPlans.entries.toList();
    final screenWidth = MediaQuery.of(context).size.width;
    final crossAxisCount = screenWidth > 600 ? 3 : (entries.length <= 2 ? 2 : 3);

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 0.62,
      ),
      itemCount: entries.length,
      itemBuilder: (ctx, i) {
        final globalIdx = entries[i].key;
        final plan = entries[i].value;
        return _PlanCard(
          plan: plan,
          isSelected: selectedIndex.value == globalIdx,
          onTap: () => selectedIndex.value = globalIdx,
          onBuy: () {
            selectedIndex.value = globalIdx;
            _handleBuy(context, plan);
          },
          discountActive: discountActive,
        );
      },
    );
  }
}

/// Show bind-email prompt after payment for device-only users.
Future<void> _showBindEmailPrompt(BuildContext context) async {
  final s = AuthI18n.t;
  final result = await showDialog<String>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      return AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          s['bindEmailAfterPayTitle'] ?? '🔒 保护您的会员',
          style: const TextStyle(fontSize: 18),
        ),
        content: Text(
          s['bindEmailAfterPayDesc'] ?? '绑定邮箱后，换设备也不会丢失会员时长',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('skip'),
            child: Text(
              s['bindEmailAfterPaySkip'] ?? '稍后再说',
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop('bind'),
            child: Text(s['bindEmailAfterPayBtn'] ?? '立即绑定'),
          ),
        ],
      );
    },
  );
  if (result == 'bind' && context.mounted) {
    // Navigate to profile page where bind-email is available
    // Use the existing bind email dialog from profile_page
    _showBindEmailDialog(context);
  }
}

/// Inline bind-email bottom sheet (self-contained, no navigation needed).
Future<void> _showBindEmailDialog(BuildContext context) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: const _BindEmailSheet(),
    ),
  );

  if (result == true && context.mounted) {
    final s = AuthI18n.t;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(s['bindSuccess'] ?? '邮箱绑定成功')),
    );
  }
}

class _BindEmailSheet extends StatefulWidget {
  const _BindEmailSheet();
  @override
  State<_BindEmailSheet> createState() => _BindEmailSheetState();
}

class _BindEmailSheetState extends State<_BindEmailSheet> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  bool _obscurePass = true;
  bool _isLoading = false;
  int _cooldown = 0;
  bool _codeSent = false;
  String? _errorMsg;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  bool _isValidEmail(String email) =>
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);

  void _startCooldown() {
    _cooldown = 60;
    _tick();
  }

  void _tick() {
    if (_cooldown <= 0 || !mounted) return;
    Future.delayed(const Duration(seconds: 1), () {
      if (!mounted) return;
      setState(() { _cooldown--; });
      _tick();
    });
  }

  Future<void> _sendCode() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      setState(() => _errorMsg = AuthI18n.t['enterEmail']);
      return;
    }
    if (!_isValidEmail(email)) {
      setState(() => _errorMsg = AuthI18n.t['invalidEmail']);
      return;
    }
    setState(() => _errorMsg = null);
    final prefs = await SharedPreferences.getInstance();
    final err = await AuthService(prefs).sendVerifyCode(email);
    if (!mounted) return;
    if (err == null) {
      setState(() { _codeSent = true; });
      _startCooldown();
    } else {
      setState(() => _errorMsg = err);
    }
  }

  Future<void> _submit() async {
    final s = AuthI18n.t;
    final email = _emailCtrl.text.trim();
    final pass = _passCtrl.text;
    final code = _codeCtrl.text.trim();

    if (email.isEmpty || !_isValidEmail(email)) {
      setState(() => _errorMsg = s['invalidEmail']);
      return;
    }
    if (pass.length < 6) {
      setState(() => _errorMsg = s['passMin6']);
      return;
    }
    if (code.isEmpty) {
      setState(() => _errorMsg = s['enterCode']);
      return;
    }

    setState(() { _isLoading = true; _errorMsg = null; });
    try {
      final prefs = await SharedPreferences.getInstance();
      final err = await AuthService(prefs).bindEmail(email, pass, code: code);
      if (!mounted) return;
      if (err == null) {
        Navigator.of(context).pop(true);
      } else {
        setState(() { _isLoading = false; _errorMsg = err; });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() { _isLoading = false; _errorMsg = s['bindFailed']; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AuthI18n.t;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
        const SizedBox(height: 16),
        Text(s['bindEmail'] ?? '绑定邮箱', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        const SizedBox(height: 16),
        TextField(
          controller: _emailCtrl,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(
            labelText: s['email'] ?? '邮箱',
            prefixIcon: const Icon(Icons.email_outlined, size: 20),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            isDense: true,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _passCtrl,
          obscureText: _obscurePass,
          decoration: InputDecoration(
            labelText: s['password'] ?? '密码',
            prefixIcon: const Icon(Icons.lock_outlined, size: 20),
            suffixIcon: IconButton(
              icon: Icon(_obscurePass ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20),
              onPressed: () => setState(() => _obscurePass = !_obscurePass),
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            isDense: true,
          ),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: TextField(
            controller: _codeCtrl,
            keyboardType: TextInputType.number,
            maxLength: 6,
            decoration: InputDecoration(
              labelText: s['verifyCode'] ?? '验证码',
              prefixIcon: const Icon(Icons.verified_outlined, size: 20),
              counterText: '',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              isDense: true,
            ),
          )),
          const SizedBox(width: 8),
          SizedBox(height: 44, child: FilledButton.tonal(
            onPressed: _cooldown > 0 ? null : _sendCode,
            child: Text(
              _cooldown > 0 ? '${_cooldown}s' : (_codeSent ? (s['resendBtn'] ?? '重发') : (s['sendBtn'] ?? '发送')),
              style: const TextStyle(fontSize: 13),
            ),
          )),
        ]),
        if (_errorMsg != null) ...[
          const SizedBox(height: 8),
          Text(_errorMsg!, style: const TextStyle(color: Colors.red, fontSize: 12)),
        ],
        const SizedBox(height: 16),
        SizedBox(width: double.infinity, child: FilledButton(
          onPressed: _isLoading ? null : _submit,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: _isLoading
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text(s['confirm'] ?? '确认'),
        )),
      ]),
    );
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
  final VoidCallback? onTap;
  final bool discountActive;
  final bool isSelected;

  const _PlanCard({required this.plan, required this.onBuy, this.onTap, this.discountActive = false, this.isSelected = false});

  @override
  Widget build(BuildContext context) {
    final s = AuthI18n.t;
    final tier = plan['tier'] ?? 'vip';
    final isVip = tier == 'vip';
    final days = (plan['days'] as num?)?.toInt() ?? 0;
    final priceCny = (plan['price_cny'] as num?)?.toDouble() ?? 0;
    final discountCny = plan['discount_price_cny'];
    final discountLabel = plan['discount_label'] as String?;
    final hasDiscount = discountActive && discountLabel != null && discountCny != null;
    final actualPrice = hasDiscount ? (discountCny as num).toDouble() : priceCny;
    final perDay = days > 0 ? actualPrice / days : 0.0;
    final usdApprox = (actualPrice / 7.1).toStringAsFixed(1);
    final isRecommended = days >= 365;

    // Colors matching the web design
    final cardBg = const Color(0xFF1E1E3A);
    final borderColor = isSelected
        ? (isVip ? const Color(0xFFD4A017) : const Color(0xFFFF6B9D))
        : Colors.transparent;
    final buttonGradient = isVip
        ? const [Color(0xFF7B2FBE), Color(0xFFE040FB)]
        : const [Color(0xFFFF6B35), Color(0xFFFF1493)];

    return GestureDetector(
      onTap: () {
        onTap?.call();
        onBuy();
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: borderColor,
            width: isSelected ? 1.5 : 0.5,
          ),
          boxShadow: isSelected
              ? [BoxShadow(color: borderColor.withOpacity(0.3), blurRadius: 12, spreadRadius: 1)]
              : null,
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 16, 12, 10),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Days label
                  Text(
                    '${days}${s['days'] ?? '天'}',
                    style: TextStyle(
                      color: Colors.grey.shade400,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 4),
                  // Main price — large and bold
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text('¥', style: TextStyle(
                            color: Colors.white.withOpacity(0.9),
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          )),
                        ),
                        Text(
                          hasDiscount
                              ? '${(discountCny as num).toInt()}'
                              : '${priceCny.toInt()}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 36,
                            fontWeight: FontWeight.w800,
                            height: 1.1,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Original price (strikethrough) if discounted
                  if (hasDiscount) ...[
                    const SizedBox(height: 2),
                    Text(
                      '¥${priceCny.toInt()}',
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 13,
                        decoration: TextDecoration.lineThrough,
                        decorationColor: Colors.grey.shade500,
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  // USD approximation
                  Text(
                    '≈ \$$usdApprox',
                    style: TextStyle(
                      color: Colors.grey.shade500,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 2),
                  // Per-day cost — green for VIP, orange for SVIP
                  Text(
                    '¥${perDay.toStringAsFixed(perDay < 1 ? 2 : 1)}/${s['perDay'] ?? '天'}',
                    style: TextStyle(
                      color: isVip ? const Color(0xFF4CAF50) : const Color(0xFFFF9800),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  // Gradient buy button
                  Container(
                    width: double.infinity,
                    height: 38,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: buttonGradient),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: onBuy,
                        child: Center(
                          child: Text(
                            s['buyNow'] ?? '立即购买',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // "推荐" badge — top center
            if (isRecommended)
              Positioned(
                top: -10,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF4CAF50),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('⭐ ', style: TextStyle(fontSize: 10)),
                        Text(
                          s['recommended'] ?? '推荐',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
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
    final chain = payInfo['chain'] as String? ?? 'trc20';
    final token = payInfo['token'] as String? ?? 'usdt';
    final tokenLabel = token.toUpperCase();
    final chainLabel = chain == 'bsc' ? 'BSC (BEP-20)'
        : chain == 'polygon' ? 'Polygon'
        : chain == 'arbitrum' ? 'Arbitrum'
        : chain == 'base' ? 'Base'
        : chain.toUpperCase();

    // Poll order status (with concurrency guard & 30-min timeout)
    useEffect(() {
      var polling = false;
      var pollCount = 0;
      const maxPolls = 180; // 180 × 10s = 30 min
      Timer? timer;
      timer = Timer.periodic(const Duration(seconds: 10), (_) async {
        if (isPaid.value || polling) return;
        pollCount++;
        if (pollCount > maxPolls) { timer?.cancel(); return; }
        polling = true;
        try {
          isChecking.value = true;
          final prefs = await SharedPreferences.getInstance();
          final auth = AuthService(prefs);
          final status = await auth.checkOrderStatus(orderNo);
          if (status == 'paid') {
            isPaid.value = true;
            timer?.cancel();
            await Future.delayed(const Duration(seconds: 1));
            if (context.mounted) Navigator.of(context).pop(true);
          }
        } catch (_) {
          // Network error — will retry next tick
        } finally {
          isChecking.value = false;
          polling = false;
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
                    Text('$amount $tokenLabel', style: theme.textTheme.headlineMedium?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.bold)),
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
              Text('$tokenLabel · $chainLabel', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Fixed header: handle bar + title
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
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
                const SizedBox(height: 12),
              ],
            ),
          ),
          // Scrollable payment options
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
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
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('USDT', style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(height: 6),
                  _PayMethodTile(
                    icon: Icons.currency_bitcoin_rounded,
                    color: const Color(0xFFF0B90B),
                    label: 'USDT (BSC)',
                    subtitle: '手续费极低 · 推荐',
                    onTap: () => Navigator.of(context).pop('usdt_bsc'),
                  ),
                  const SizedBox(height: 8),
                  _PayMethodTile(
                    icon: Icons.currency_bitcoin_rounded,
                    color: const Color(0xFF0052FF),
                    label: 'USDT (Base)',
                    subtitle: '手续费极低',
                    onTap: () => Navigator.of(context).pop('usdt_base'),
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('USDC', style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(height: 6),
                  _PayMethodTile(
                    icon: Icons.monetization_on_rounded,
                    color: const Color(0xFF2775CA),
                    label: 'USDC (BSC)',
                    subtitle: '手续费极低',
                    onTap: () => Navigator.of(context).pop('usdc_bsc'),
                  ),
                  const SizedBox(height: 8),
                  _PayMethodTile(
                    icon: Icons.monetization_on_rounded,
                    color: const Color(0xFF2775CA),
                    label: 'USDC (Base)',
                    subtitle: '手续费极低',
                    onTap: () => Navigator.of(context).pop('usdc_base'),
                  ),
                ],
              ),
            ),
          ),
        ],
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

    // Poll order status every 5s (with concurrency guard & 30-min timeout)
    useEffect(() {
      var polling = false;
      var pollCount = 0;
      const maxPolls = 360; // 360 × 5s = 30 min
      Timer? timer;
      timer = Timer.periodic(const Duration(seconds: 5), (_) async {
        if (isPaid.value || polling) return;
        pollCount++;
        if (pollCount > maxPolls) { timer?.cancel(); return; }
        polling = true;
        try {
          isChecking.value = true;
          final prefs = await SharedPreferences.getInstance();
          final auth = AuthService(prefs);
          final status = await auth.checkOrderStatus(orderNo);
          if (status == 'paid') {
            isPaid.value = true;
            timer?.cancel();
            await Future.delayed(const Duration(seconds: 1));
            if (context.mounted) Navigator.of(context).pop(true);
          }
        } catch (_) {
          // Network error — will retry next tick
        } finally {
          isChecking.value = false;
          polling = false;
        }
      });
      return () => timer?.cancel();
    }, [orderNo]);

    // Detect platform
    final isDesktop = Theme.of(context).platform == TargetPlatform.windows ||
        Theme.of(context).platform == TargetPlatform.macOS ||
        Theme.of(context).platform == TargetPlatform.linux;

    // Mobile: auto open pay URL in browser/app; Desktop: show QR for scanning
    useEffect(() {
      if (payUrl.isNotEmpty && !isDesktop) {
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
            // Desktop: show QR code for scanning with phone
            if (isDesktop && payUrl.isNotEmpty) ...[
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
            ],
            // Mobile: show "opened in browser" hint + re-open button
            if (!isDesktop) ...[
              Icon(Icons.open_in_browser_rounded, size: 48, color: channelColor),
              const SizedBox(height: 8),
              Text('已跳转到${channelLabel}', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text('请在打开的页面完成支付', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => _launchUrl(payUrl),
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: Text('重新打开支付页面'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                ),
              ),
            ],
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
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }
}
