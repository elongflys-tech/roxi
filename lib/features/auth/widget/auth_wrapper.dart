import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hiddify/features/auth/data/auth_service.dart';
import 'package:hiddify/features/auth/widget/login_page.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Auth gate that wraps the entire app.
/// Flow: Login → check subscription → Main App.
class AuthWrapper extends HookConsumerWidget {
  final Widget child;
  final Future<void> Function(String subscriptionUrl) onSubscriptionReady;

  const AuthWrapper({
    super.key,
    required this.child,
    required this.onSubscriptionReady,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 0 = checking, 1 = login, 2 = app
    final authState = useState(0);

    Future<void> checkAuth() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final auth = AuthService(prefs);

        if (!auth.isLoggedIn) {
          authState.value = 1;
          return;
        }

        // Try to get subscription, but don't block on failure
        try {
          final sub = await auth.getSubscription().timeout(
            const Duration(seconds: 8),
          );
          if (sub != null && sub['subscription_url'] != null) {
            await onSubscriptionReady(sub['subscription_url']).timeout(
              const Duration(seconds: 8),
            );
          }
        } catch (_) {
          // Subscription fetch failed — proceed anyway
        }

        authState.value = 2;
      } catch (_) {
        // If anything fails, show login
        authState.value = 1;
      }
    }

    useEffect(() {
      checkAuth();
      return null;
    }, []);

    switch (authState.value) {
      case 0:
        return const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        );
      case 1:
        return LoginPage(
          onLoginSuccess: () {
            authState.value = 0;
            checkAuth();
          },
        );
      default:
        return child;
    }
  }
}
