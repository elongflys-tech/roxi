import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hiddify/features/auth/data/auth_i18n.dart';
import 'package:hiddify/features/auth/data/auth_service.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LoginPage extends HookConsumerWidget {
  final VoidCallback onLoginSuccess;

  const LoginPage({super.key, required this.onLoginSuccess});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final s = AuthI18n.t;
    final isLogin = useState(true);
    final isLoading = useState(false);
    final emailController = useTextEditingController();
    final passwordController = useTextEditingController();
    final inviteCodeController = useTextEditingController();
    final errorMsg = useState<String?>(null);

    Future<void> handleSubmit() async {
      final email = emailController.text.trim();
      final password = passwordController.text;
      if (email.isEmpty || password.isEmpty) {
        errorMsg.value = s['fillFields'];
        return;
      }
      if (password.length < 6) {
        errorMsg.value = s['passMin6'];
        return;
      }

      isLoading.value = true;
      errorMsg.value = null;

      final prefs = await SharedPreferences.getInstance();
      final auth = AuthService(prefs);

      String? result;
      if (isLogin.value) {
        result = await auth.login(email, password);
      } else {
        result = await auth.register(email, password, inviteCode: inviteCodeController.text.trim());
      }

      isLoading.value = false;

      if (result == null) {
        onLoginSuccess();
      } else {
        errorMsg.value = result;
      }
    }

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset('assets/images/roxi_icon.png', width: 80, height: 80),
                const SizedBox(height: 16),
                Text(
                  'Roxi',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  s['tagline']!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 40),
                // Tab switcher
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: () => isLogin.value = true,
                        style: FilledButton.styleFrom(
                          backgroundColor: isLogin.value
                              ? theme.colorScheme.primary
                              : theme.colorScheme.surfaceContainerHighest,
                          foregroundColor: isLogin.value
                              ? theme.colorScheme.onPrimary
                              : theme.colorScheme.onSurface,
                        ),
                        child: Text(s['login']!),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => isLogin.value = false,
                        style: FilledButton.styleFrom(
                          backgroundColor: !isLogin.value
                              ? theme.colorScheme.primary
                              : theme.colorScheme.surfaceContainerHighest,
                          foregroundColor: !isLogin.value
                              ? theme.colorScheme.onPrimary
                              : theme.colorScheme.onSurface,
                        ),
                        child: Text(s['register']!),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: s['email'],
                    prefixIcon: const Icon(Icons.email_outlined),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: passwordController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: s['password'],
                    prefixIcon: const Icon(Icons.lock_outlined),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onSubmitted: (_) => handleSubmit(),
                ),
                // Invite code field (register only)
                if (!isLogin.value) ...[
                  const SizedBox(height: 16),
                  TextField(
                    controller: inviteCodeController,
                    decoration: InputDecoration(
                      labelText: s['inviteCode'],
                      prefixIcon: const Icon(Icons.card_giftcard_outlined),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                if (errorMsg.value != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      errorMsg.value!,
                      style: TextStyle(color: theme.colorScheme.error, fontSize: 13),
                    ),
                  ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton(
                    onPressed: isLoading.value ? null : handleSubmit,
                    child: isLoading.value
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(isLogin.value ? s['login']! : s['register']!),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
