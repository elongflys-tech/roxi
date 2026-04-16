import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hiddify/features/auth/data/auth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Top-level auth gate.
/// Auto device-register on first launch — no login page needed.
/// User can bind email later from profile page.
class AuthGate extends HookWidget {
  final Future<void> Function(String? subscriptionUrl) onReady;

  const AuthGate({super.key, required this.onReady});

  @override
  Widget build(BuildContext context) {
    // 0=loading, 1=done
    final state = useState(0);
    final errorMsg = useState<String?>(null);

    Future<void> init() async {
      final prefs = await SharedPreferences.getInstance();
      final auth = AuthService(prefs);

      // If not logged in, auto device-register
      if (!auth.isLoggedIn) {
        final err = await auth.deviceRegister();
        if (err != null) {
          errorMsg.value = err;
          return;
        }
        // Check clipboard for invite code from web download flow
        // Format: "roxi-invite:XXXXX"
        await _tryApplyClipboardInvite(auth, prefs);
      }

      // Fetch subscription URL
      String? subUrl;
      try {
        final sub = await auth.getSubscription().timeout(const Duration(seconds: 8));
        if (sub != null && sub['subscription_url'] != null) {
          subUrl = sub['subscription_url'] as String;
        }
      } catch (_) {}

      await onReady(subUrl);
      state.value = 1;
    }

    useEffect(() {
      init();
      return null;
    }, []);

    if (errorMsg.value != null) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData.light(useMaterial3: true),
        home: Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off_rounded, size: 48, color: Colors.grey),
                const SizedBox(height: 16),
                Text('连接失败', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(errorMsg.value!, style: const TextStyle(color: Colors.grey, fontSize: 13)),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () {
                    errorMsg.value = null;
                    state.value = 0;
                    init();
                  },
                  child: const Text('重试'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (state.value == 1) return const SizedBox();

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.light(useMaterial3: true),
      home: const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

/// Read clipboard for invite code planted by the web download page.
/// Only runs once (first launch). Clears clipboard after use.
const _inviteAppliedKey = 'roxi_clipboard_invite_applied';

Future<void> _tryApplyClipboardInvite(AuthService auth, SharedPreferences prefs) async {
  if (prefs.getBool(_inviteAppliedKey) == true) return; // already tried once
  try {
    final data = await Clipboard.getData(Clipboard.kTextPlain).timeout(
      const Duration(seconds: 2),
      onTimeout: () => null,
    );
    final text = data?.text?.trim() ?? '';
    if (text.startsWith('roxi-invite:') && text.length > 12) {
      final code = text.substring(12).trim();
      if (code.isNotEmpty && code.length <= 20) {
        await auth.applyInvite(code);
        // Clear the clipboard so it doesn't re-trigger
        await Clipboard.setData(const ClipboardData(text: ''));
      }
    }
  } catch (_) {
    // Clipboard access may fail on some devices — ignore
  }
  await prefs.setBool(_inviteAppliedKey, true);
}
