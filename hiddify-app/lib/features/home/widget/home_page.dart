import 'package:dartx/dartx.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/app_info/app_info_provider.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/router/bottom_sheets/bottom_sheets_notifier.dart';
import 'package:hiddify/features/auth/data/auto_sub_import.dart';
import 'package:hiddify/features/auth/data/auth_service.dart';
import 'package:hiddify/features/auth/data/auth_i18n.dart';
import 'package:hiddify/features/auth/widget/guide_card.dart';
import 'package:hiddify/features/auth/widget/profile_page.dart';
import 'package:hiddify/features/auth/widget/network_error_dialog.dart';
import 'package:hiddify/features/auth/widget/trial_expired_dialog.dart';
import 'package:hiddify/features/auth/widget/user_avatar_badge.dart';
import 'package:hiddify/features/auth/widget/plans_page.dart';
import 'package:hiddify/features/home/widget/connection_button.dart';
import 'package:hiddify/features/home/widget/node_list_card.dart';
import 'package:hiddify/features/home/widget/node_list_sheet.dart';
import 'package:hiddify/features/home/widget/node_selector_card.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/proxy/active/active_proxy_delay_indicator.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sliver_tools/sliver_tools.dart';

class HomePage extends HookConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final t = ref.watch(translationsProvider).requireValue;
    final activeProfile = ref.watch(activeProfileProvider);

    // Trial status
    final trialStatus = useState<String?>(null);
    final trialRemainingSec = useState<int>(0);
    final trialChecked = useState(false);
    final expireDate = useState<String?>(null);
    final isPaidUser = useState(false);

    // Check trial status on mount
    useEffect(() {
      () async {
        final hasNetwork = await checkNetwork();
        if (!hasNetwork && context.mounted) {
          Future.delayed(const Duration(milliseconds: 300), () async {
            if (!context.mounted) return;
            final retry = await showNetworkErrorDialog(context);
            if (retry && context.mounted) {
              trialChecked.value = false;
              trialChecked.value = true;
            }
          });
          return;
        }
        try {
          final prefs = await SharedPreferences.getInstance();
          final auth = AuthService(prefs);
          if (!auth.isLoggedIn) return;
          final status = await auth.getTrialStatus();
          if (status != null) {
            trialStatus.value = status['status'] as String?;
            trialRemainingSec.value = status['remaining_sec'] as int? ?? 0;
            trialChecked.value = true;
            if (status['status'] == 'expired' && context.mounted) {
              Future.delayed(const Duration(milliseconds: 500), () {
                if (context.mounted) showTrialExpiredDialog(context);
              });
            }
          }
          final userInfo = await auth.getUserInfo();
          if (userInfo != null) {
            final ed = userInfo['expire_date'];
            if (ed != null && ed.toString().isNotEmpty) {
              expireDate.value = ed.toString();
              isPaidUser.value = true;
            }
          }
          // Prefetch plans so the sheet opens instantly
          auth.getPlans(); auth.getShowcaseNodes();
        } catch (_) {}
      }();
      return null;
    }, []);

    // Real-time countdown timer
    final connectionStatus = ref.watch(
      connectionNotifierProvider.select((v) => v.valueOrNull ?? const Disconnected()),
    );
    final isConnected = connectionStatus == const Connected();

    useEffect(() {
      if (trialStatus.value != 'trial' || trialRemainingSec.value <= 0) return null;
      if (!isConnected) return null;

      final ticker = Stream.periodic(const Duration(seconds: 1));
      final sub = ticker.listen((_) {
        if (trialRemainingSec.value > 0) {
          trialRemainingSec.value = trialRemainingSec.value - 1;
        }
        if (trialRemainingSec.value <= 0) {
          trialStatus.value = 'expired';
          if (context.mounted) showTrialExpiredDialog(context);
        }
      });

      final heartbeat = Stream.periodic(const Duration(seconds: 10));
      final hbSub = heartbeat.listen((_) async {
        try {
          final prefs = await SharedPreferences.getInstance();
          final auth = AuthService(prefs);
          final result = await auth.trialHeartbeat();
          if (result != null) {
            final serverRemaining = result['remaining_sec'] as int? ?? 0;
            trialRemainingSec.value = serverRemaining;
            if (result['status'] == 'expired') {
              trialStatus.value = 'expired';
              if (context.mounted) showTrialExpiredDialog(context);
            }
          }
        } catch (_) {}
      });

      return () {
        sub.cancel();
        hbSub.cancel();
      };
    }, [trialStatus.value, trialChecked.value, isConnected]);

    // Auto-import subscription if no profile exists
    final autoImportDone = useRef(false);
    useEffect(() {
      if (autoImportDone.value) return null;
      if (activeProfile case AsyncData(value: null)) {
        autoImportDone.value = true;
        Future.microtask(() {
          ref.read(autoSubImportProvider.notifier).tryImport();
        });
      }
      return null;
    }, [activeProfile]);

    // Build the left-side status widget for the top bar
    Widget buildStatusLabel() {
      final s = AuthI18n.t;
      // Trial active — show countdown
      if (trialChecked.value && trialStatus.value == 'trial') {
        final min = trialRemainingSec.value ~/ 60;
        final sec = trialRemainingSec.value % 60;
        final timeStr = '${min.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
        return Text(
          '${s['trialBadge']} $timeStr',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.orange.shade700,
          ),
        );
      }
      // Expired — tappable red label
      if (trialChecked.value && trialStatus.value == 'expired') {
        return GestureDetector(
          onTap: () => showPlansSheet(context),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.red.shade200, width: 0.5),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline_rounded, size: 14, color: Colors.red.shade400),
                const SizedBox(width: 4),
                Text(
                  '${s['expiredBadge']} · ${s['upgradePlan']}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.red.shade600,
                  ),
                ),
              ],
            ),
          ),
        );
      }
      // Paid user — show expire date compactly
      if (isPaidUser.value && expireDate.value != null) {
        final ed = expireDate.value!;
        final short = ed.length >= 10 ? ed.substring(0, 10) : ed;
        return Text(
          short,
          style: TextStyle(
            fontSize: 12,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        );
      }
      // Default — app name
      return Text(
        'Roxi',
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: theme.colorScheme.primary,
        ),
      );
    }

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          image: DecorationImage(
            image: const AssetImage('assets/images/world_map.png'),
            fit: BoxFit.cover,
            opacity: 0.09,
            colorFilter: theme.brightness == Brightness.dark
                ? ColorFilter.mode(Colors.white.withValues(alpha: .15), BlendMode.srcIn)
                : ColorFilter.mode(
                    Colors.grey.withValues(alpha: 1),
                    BlendMode.srcATop,
                  ),
          ),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: CustomScrollView(
                  slivers: [
                    MultiSliver(
                      children: [
                        // Top bar — status label + settings + avatar, all in one row
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Row(
                            children: [
                              buildStatusLabel(),
                              const Spacer(),
                              IconButton(
                                icon: Icon(Icons.tune_rounded, color: theme.colorScheme.primary, size: 22),
                                onPressed: () => ref.read(bottomSheetsNotifierProvider.notifier).showQuickSettings(),
                                padding: const EdgeInsets.all(6),
                                constraints: const BoxConstraints(),
                              ),
                              const Gap(2),
                              UserAvatarBadge(
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(builder: (_) => const ProfilePage()),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                        GuideCard(
                          isTrialActive: trialChecked.value && trialStatus.value == 'trial',
                          trialRemainingSec: trialRemainingSec.value,
                        ),
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const ConnectionButton(),
                                    const ActiveProxyDelayIndicator(),
                                    const Gap(16),
                                    NodeSelectorCard(),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            // New user gift floating button (bottom-left)
            if (!isPaidUser.value)
              Positioned(
                left: 12,
                bottom: 16,
                child: _NewUserGiftButton(onTap: () => showPlansSheet(context)),
              ),
          ],
        ),
      ),
    );
  }
}

class AppVersionLabel extends HookConsumerWidget {
  const AppVersionLabel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final theme = Theme.of(context);

    final version = ref.watch(appInfoProvider).requireValue.presentVersion;
    if (version.isBlank) return const SizedBox();

    return Semantics(
      label: t.common.version,
      button: false,
      child: Container(
        decoration: BoxDecoration(color: theme.colorScheme.secondaryContainer, borderRadius: BorderRadius.circular(4)),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        child: Text(
          version,
          textDirection: TextDirection.ltr,
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSecondaryContainer),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// New user gift floating button
// ─────────────────────────────────────────────────────────────────────────────
class _NewUserGiftButton extends StatefulWidget {
  final VoidCallback onTap;
  const _NewUserGiftButton({required this.onTap});

  @override
  State<_NewUserGiftButton> createState() => _NewUserGiftButtonState();
}

class _NewUserGiftButtonState extends State<_NewUserGiftButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _bounce;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _bounce = Tween<double>(begin: 0, end: -6).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AuthI18n.t;
    return AnimatedBuilder(
      animation: _bounce,
      builder: (_, child) => Transform.translate(
        offset: Offset(0, _bounce.value),
        child: child,
      ),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.pink.shade300, Colors.orange.shade300],
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.pink.withOpacity(0.3),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Text(
            s['newUserGift']!,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
