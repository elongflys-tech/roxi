import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hiddify/features/auth/data/auth_i18n.dart';
import 'package:hiddify/features/auth/data/auth_service.dart';
import 'package:hiddify/features/auth/widget/invite_rewards_page.dart';
import 'package:hiddify/features/auth/widget/plans_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
    final trafficLimit = (userInfo.value?['traffic_limit_gb'] ?? 0).toDouble();
    final tier = (userInfo.value?['tier'] as String?) ?? 'free';
    final isPaid = tier == 'vip' || tier == 'svip';
    final tierLabel = isPaid ? (tier == 'svip' ? s['svipTier']! : s['vipTier']!) : s['freeTier']!;
    final tierColor = isPaid ? (tier == 'svip' ? Colors.amber : Colors.blue) : Colors.grey;
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
        _UserHeaderCard(hasEmail: hasEmail, email: email?.toString() ?? '',
          deviceId: deviceId.toString(), tierLabel: tierLabel, tierColor: tierColor,
          onTap: hasEmail ? null : () => showAuthPanel.value = !showAuthPanel.value),
        if (!hasEmail && showAuthPanel.value) ...[const SizedBox(height: 12), _AuthPanel(onSuccess: reload)],
        if (!hasEmail && !showAuthPanel.value) ...[
          const SizedBox(height: 8),
          GestureDetector(onTap: () => showAuthPanel.value = true,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.shade100)),
              child: Row(children: [
                Icon(Icons.devices_rounded, size: 20, color: Colors.blue.shade700),
                const SizedBox(width: 12),
                Expanded(child: Text('登录或注册账户，在不同设备间共享会员时长',
                  style: TextStyle(fontSize: 13, color: Colors.blue.shade800))),
                Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.blue.shade400),
              ]))),
        ],
        const SizedBox(height: 16),
        _buildSection(theme, s['currentPlan']!, [
          _infoRow(s['currentPlan']!, isPaid ? tierLabel : s['noPlan']!, tierColor),
          if (isPaid) ...[
            _infoRow(s['expireDate']!, _fmtDate(expireDate), null),
            _infoRow(s['trafficUsed']!, trafficLimit > 0 ? '${trafficLimit.toStringAsFixed(0)} GB' : s['unlimitedTraffic']!, null),
          ],
          if (!isPaid) ...[
            _infoRow(s['freeNodeLimit']!, s['freeNodeLimitVal']!, Colors.orange),
            _infoRow(s['freeStability']!, s['freeStabilityVal']!, Colors.red),
          ],
        ]),
        const SizedBox(height: 12),
        SizedBox(width: double.infinity, child: ElevatedButton.icon(
          onPressed: () => showPlansSheet(context),
          icon: const Icon(Icons.rocket_launch_rounded, size: 18), label: Text(s['upgradePlan']!),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))))),
        const SizedBox(height: 16),
        _buildSection(theme, s['inviteTitle']!, [
          _infoRow(s['inviteCount']!, '$invCount ${s['invitePeople']}', null),
          _infoRow('累计奖励', '${bonusDays}天', null),
          if (invCode.toString().isNotEmpty) _infoRow(s['inviteCodeLabel']!, invCode.toString(), Colors.blue),
        ]),
        const SizedBox(height: 8),
        if (invCode.toString().isNotEmpty)
          TextButton.icon(onPressed: () {
            Clipboard.setData(ClipboardData(text: 'https://roxi.cc/i/$invCode'));
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s['guideInviteCopied']!), duration: const Duration(seconds: 2)));
          }, icon: const Icon(Icons.copy_rounded, size: 16), label: Text(s['copyInviteLink']!)),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const InviteRewardsPage())),
          icon: const Icon(Icons.card_giftcard_rounded, size: 18), label: Text(s['inviteRewardsBtn']!),
          style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)))),
        if (!hasUsedInvite) ...[const SizedBox(height: 16), _ApplyInviteCard(onSuccess: reload)],
        if (hasEmail) ...[const SizedBox(height: 16), _ChangePasswordCard()],
        if (hasEmail) ...[
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () async { final p = await SharedPreferences.getInstance(); await AuthService(p).logout(); reload(); },
            icon: const Icon(Icons.logout_rounded, size: 18, color: Colors.red),
            label: Text(s['logout']!, style: const TextStyle(color: Colors.red))),
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
}

class _UserHeaderCard extends StatelessWidget {
  final bool hasEmail;
  final String email;
  final String deviceId;
  final String tierLabel;
  final Color tierColor;
  final VoidCallback? onTap;
  const _UserHeaderCard({required this.hasEmail, required this.email, required this.deviceId, required this.tierLabel, required this.tierColor, this.onTap});

  @override
  Widget build(BuildContext context) {
    final s = AuthI18n.t;
    return Material(color: Colors.transparent, child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(16),
      child: Container(padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [Colors.blue.shade50, Colors.white], begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.blue.shade100)),
        child: Row(children: [
          CircleAvatar(radius: 28, backgroundColor: hasEmail ? Colors.blue.shade100 : Colors.grey.shade200,
            child: Icon(hasEmail ? Icons.person_rounded : Icons.phone_android_rounded, size: 28,
              color: hasEmail ? Colors.blue.shade700 : Colors.grey.shade500)),
          const SizedBox(width: 16),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(hasEmail ? email : s['deviceUser']!,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: hasEmail ? Colors.black87 : Colors.grey.shade700)),
            const SizedBox(height: 4),
            Text(hasEmail ? 'ID: ${deviceId.length > 8 ? deviceId.substring(0, 8) : deviceId}' : s['notBound']!,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
          ])),
          Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: tierColor.withOpacity(0.15), borderRadius: BorderRadius.circular(20)),
            child: Text(tierLabel, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: tierColor))),
          if (!hasEmail) ...[const SizedBox(width: 8), Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.grey.shade400)],
        ]))));
  }
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
    final errorMsg = useState<String?>(null);

    Future<void> submit() async {
      final em = emailCtrl.text.trim();
      final pw = passCtrl.text;
      if (em.isEmpty || pw.isEmpty) { errorMsg.value = s['fillFields']; return; }
      if (pw.length < 6) { errorMsg.value = s['passMin6']; return; }
      isLoading.value = true; errorMsg.value = null;
      final prefs = await SharedPreferences.getInstance();
      final auth = AuthService(prefs);
      final result = isRegister.value ? await auth.bindEmail(em, pw) : await auth.login(em, pw);
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
          Expanded(child: Text('您可以登录或注册一个账户，在不同设备间共享会员时长。',
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
        TextField(controller: passCtrl, obscureText: true, onSubmitted: (_) => submit(),
          decoration: InputDecoration(labelText: s['password'], prefixIcon: const Icon(Icons.lock_outlined, size: 20),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)), isDense: true)),
        if (isRegister.value) ...[const SizedBox(height: 12),
          TextField(controller: inviteCtrl,
            decoration: InputDecoration(labelText: s['inviteCode'], prefixIcon: const Icon(Icons.card_giftcard_outlined, size: 20),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)), isDense: true))],
        if (errorMsg.value != null) ...[const SizedBox(height: 8), Text(errorMsg.value!, style: const TextStyle(color: Colors.red, fontSize: 12))],
        const SizedBox(height: 16),
        SizedBox(width: double.infinity, height: 44, child: ElevatedButton(
          onPressed: isLoading.value ? null : submit,
          style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white,
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

class _ApplyInviteCard extends HookWidget {
  final VoidCallback onSuccess;
  const _ApplyInviteCard({required this.onSuccess});

  @override
  Widget build(BuildContext context) {
    final s = AuthI18n.t;
    final ctrl = useTextEditingController();
    final isLoading = useState(false);
    final errorMsg = useState<String?>(null);

    Future<void> apply() async {
      final code = ctrl.text.trim();
      if (code.isEmpty) return;
      isLoading.value = true; errorMsg.value = null;
      final prefs = await SharedPreferences.getInstance();
      final result = await AuthService(prefs).applyInvite(code);
      isLoading.value = false;
      if (result == null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s['inviteApplied']!), duration: const Duration(seconds: 2)));
        onSuccess();
      } else { errorMsg.value = result; }
    }

    return Container(padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(s['applyInviteCode']!, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
        const SizedBox(height: 4),
        Text(s['applyInviteDesc']!, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: TextField(controller: ctrl,
            decoration: InputDecoration(hintText: s['inviteCodeHint'], border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10)))),
          const SizedBox(width: 8),
          ElevatedButton(onPressed: isLoading.value ? null : apply,
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            child: isLoading.value
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text(s['confirm']!)),
        ]),
        if (errorMsg.value != null) ...[const SizedBox(height: 8), Text(errorMsg.value!, style: const TextStyle(color: Colors.red, fontSize: 12))],
      ]));
  }
}

class _ChangePasswordCard extends HookWidget {
  @override
  Widget build(BuildContext context) {
    final s = AuthI18n.t;
    final expanded = useState(false);
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s['passwordChanged']!), duration: const Duration(seconds: 2)));
        oldCtrl.clear(); newCtrl.clear(); confirmCtrl.clear(); expanded.value = false;
      } else { errorMsg.value = result; }
    }

    return Container(padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        GestureDetector(onTap: () => expanded.value = !expanded.value,
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(s['changePassword']!, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
            Icon(expanded.value ? Icons.expand_less : Icons.expand_more, color: Colors.grey.shade500),
          ])),
        if (expanded.value) ...[
          const SizedBox(height: 12),
          TextField(controller: oldCtrl, obscureText: true,
            decoration: InputDecoration(labelText: s['oldPassword'], border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)), isDense: true)),
          const SizedBox(height: 10),
          TextField(controller: newCtrl, obscureText: true,
            decoration: InputDecoration(labelText: s['newPassword'], border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)), isDense: true)),
          const SizedBox(height: 10),
          TextField(controller: confirmCtrl, obscureText: true, onSubmitted: (_) => submit(),
            decoration: InputDecoration(labelText: s['confirmPassword'], border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)), isDense: true)),
          if (errorMsg.value != null) ...[const SizedBox(height: 8), Text(errorMsg.value!, style: const TextStyle(color: Colors.red, fontSize: 12))],
          const SizedBox(height: 12),
          SizedBox(width: double.infinity, child: ElevatedButton(
            onPressed: isLoading.value ? null : submit,
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            child: isLoading.value
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text(s['changePwdBtn']!))),
        ],
      ]));
  }
}
