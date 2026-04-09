import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/failures.dart';
import 'package:hiddify/core/router/bottom_sheets/bottom_sheets_notifier.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/core/router/dialog/widgets/custom_alert_dialog.dart';
import 'package:hiddify/core/theme/theme_extensions.dart';
import 'package:hiddify/core/widget/animated_text.dart';
import 'package:hiddify/features/auth/data/auth_service.dart';
import 'package:hiddify/features/auth/data/auto_sub_import.dart';
import 'package:hiddify/features/auth/widget/trial_expired_dialog.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/proxy/active/active_proxy_notifier.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/features/settings/notifier/config_option/config_option_notifier.dart';
import 'package:hiddify/gen/assets.gen.dart';
import 'package:hiddify/singbox/model/singbox_config_enum.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hiddify/features/auth/data/auth_i18n.dart';

class ConnectionButton extends HookConsumerWidget {
  const ConnectionButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final connectionStatus = ref.watch(connectionNotifierProvider);
    final activeProxy = ref.watch(activeProxyNotifierProvider);
    final delay = activeProxy.valueOrNull?.urlTestDelay ?? 0;
    final requiresReconnect = ref.watch(configOptionNotifierProvider).valueOrNull;
    final today = DateTime.now();

    // Debounce: prevent rapid double-taps
    final isBusy = useRef(false);

    const buttonTheme = ConnectionButtonTheme.light;
    final s = AuthI18n.t;

    var secureLabel =
        (ref.watch(ConfigOptions.enableWarp) && ref.watch(ConfigOptions.warpDetourMode) == WarpDetourMode.warpOverProxy)
        ? t.connection.secure
        : "";
    if (delay <= 0 || delay > 65000 || connectionStatus.value != const Connected()) {
      secureLabel = "";
    }

    // Debounce wrapper — prevents rapid double-taps
    Future<void> Function() debounced(Future<void> Function() fn) {
      return () async {
        if (isBusy.value) return;
        isBusy.value = true;
        try { await fn(); } finally {
          await Future.delayed(const Duration(milliseconds: 800));
          isBusy.value = false;
        }
      };
    }

    return _ConnectionButton(
      onTap: switch (connectionStatus) {
        AsyncData(value: Connected()) when requiresReconnect == true => debounced(() async {
          final activeProfile = await ref.read(activeProfileProvider.future);
          await ref.read(connectionNotifierProvider.notifier).reconnect(activeProfile);
        }),
        AsyncData(value: Disconnected()) || AsyncError() => debounced(() async {
          // Pre-check: block if trial expired (fire-and-forget style to avoid flicker)
          final prefs = await SharedPreferences.getInstance();
          final auth = AuthService(prefs);
          if (auth.isLoggedIn) {
            final status = await auth.getTrialStatus();
            if (status != null && status['status'] == 'expired') {
              if (context.mounted) showTrialExpiredDialog(context);
              return;
            }
          }
          // Check profile exists before proceeding
          if (ref.read(activeProfileProvider).valueOrNull == null) {
            // No active profile — try auto-importing subscription first
            final imported = await ref.read(autoSubImportProvider.notifier).forceImport();
            if (imported && ref.read(activeProfileProvider).valueOrNull != null) {
              // Profile now exists — proceed to connect
              if (await ref.read(dialogNotifierProvider.notifier).showExperimentalFeatureNotice()) {
                await ref.read(connectionNotifierProvider.notifier).toggleConnection();
              }
              return;
            }
            // Still no profile after retry — show manual add prompt
            await ref.read(dialogNotifierProvider.notifier).showNoActiveProfile();
            ref.read(bottomSheetsNotifierProvider.notifier).showAddProfile();
            return; // Don't continue to toggle — wait for profile to be added
          }
          if (await ref.read(dialogNotifierProvider.notifier).showExperimentalFeatureNotice()) {
            await ref.read(connectionNotifierProvider.notifier).toggleConnection();
          }
        }),
        AsyncData(value: Connected()) => debounced(() async {
          if (requiresReconnect == true &&
              await ref.read(dialogNotifierProvider.notifier).showExperimentalFeatureNotice()) {
            await ref.read(connectionNotifierProvider.notifier)
                .reconnect(await ref.read(activeProfileProvider.future));
            return;
          }
          await ref.read(connectionNotifierProvider.notifier).toggleConnection();
        }),
        _ => () {},
      },
      enabled: switch (connectionStatus) {
        AsyncData(value: Connected()) || AsyncData(value: Disconnected()) || AsyncError() => true,
        _ => false,
      },
      label: switch (connectionStatus) {
        AsyncData(value: Connected()) when requiresReconnect == true => t.connection.reconnect,
        AsyncData(value: Connected()) when delay <= 0 || delay >= 65000 => t.connection.connecting,
        AsyncData(value: final status) => status.present(t),
        _ => "",
      },
      buttonColor: switch (connectionStatus) {
        AsyncData(value: Connected()) when requiresReconnect == true => Colors.teal,
        AsyncData(value: Connected()) when delay <= 0 || delay >= 65000 => const Color.fromARGB(255, 185, 176, 103),
        AsyncData(value: Connected()) => buttonTheme.connectedColor!,
        AsyncData(value: _) => buttonTheme.idleColor!,
        _ => Colors.red,
      },
      image: switch (connectionStatus) {
        AsyncData(value: Connected()) when requiresReconnect == true => Assets.images.disconnectNorouz,
        AsyncData(value: Connected()) => Assets.images.connectNorouz,
        AsyncData(value: _) => Assets.images.disconnectNorouz,
        _ => Assets.images.disconnectNorouz,
        AsyncData(value: Disconnected()) || AsyncError() => Assets.images.disconnectNorouz,
        AsyncData(value: Connected()) => Assets.images.connectNorouz,
        _ => Assets.images.disconnectNorouz,
      },
      newButtonColor: switch (connectionStatus) {
        AsyncData(value: Connected()) when requiresReconnect == true => Colors.teal,
        AsyncData(value: Connected()) when delay <= 0 || delay >= 65000 => const Color.fromARGB(255, 185, 176, 103),
        AsyncData(value: Connected()) => buttonTheme.connectedColor!,
        AsyncData(value: _) => buttonTheme.idleColor!,
        _ => Colors.red,
      },
      animated: switch (connectionStatus) {
        AsyncData(value: Connected()) when requiresReconnect == true => false,
        AsyncData(value: Connected()) when delay <= 0 || delay >= 65000 => false,
        AsyncData(value: Connected()) => true,
        AsyncData(value: _) => true,
        _ => false,
      },
      useImage: today.day >= 19 && today.day <= 23 && today.month == 3,
      secureLabel: secureLabel,
    );
  }
}

class _ConnectionButton extends StatelessWidget {
  const _ConnectionButton({
    required this.onTap,
    required this.enabled,
    required this.label,
    required this.buttonColor,
    required this.image,
    required this.useImage,
    required this.newButtonColor,
    required this.animated,
    required this.secureLabel,
  });

  final VoidCallback onTap;
  final bool enabled;
  final String label;
  final Color buttonColor;
  final AssetGenImage image;
  final bool useImage;
  final String secureLabel;

  final Color newButtonColor;

  final bool animated;

  // Determine visual state
  // Connected: buttonColor == connectedColor
  // Connecting/Disconnecting: enabled == false (not Connected, not Disconnected)
  // Disconnected: enabled == true AND buttonColor != connectedColor
  bool get _isConnected => buttonColor == ConnectionButtonTheme.light.connectedColor;
  bool get _isConnecting => !_isConnected && !enabled;
  bool get _isDisconnected => !_isConnected && enabled;

  @override
  Widget build(BuildContext context) {
    // State-dependent colors
    final glowColor = _isConnected
        ? Colors.green.withValues(alpha: .45)
        : _isConnecting
            ? Colors.orange.withValues(alpha: .35)
            : Colors.orange.withValues(alpha: .25);
    final ringColor = _isConnected
        ? Colors.green.shade400
        : _isConnecting
            ? Colors.orange.shade300
            : Colors.orange.shade300;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Semantics(
          button: true,
          enabled: enabled,
          label: label,
          child: GestureDetector(
            onTap: onTap,
            child: SizedBox(
              width: 172,
              height: 172,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Outer ring
                  _AnimatedRing(
                    color: ringColor,
                    glowColor: glowColor,
                    isConnecting: _isConnecting,
                    isConnected: _isConnected,
                  ),
                  // Main button circle
                  Container(
                    width: 140,
                    height: 140,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(blurRadius: 20, spreadRadius: 2, color: glowColor),
                      ],
                    ),
                    child: Material(
                      key: const ValueKey("home_connection_button"),
                      shape: const CircleBorder(),
                      color: Colors.white,
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: _isDisconnected
                            ? ColorFiltered(
                                colorFilter: const ColorFilter.matrix(<double>[
                                  0.2126, 0.7152, 0.0722, 0, 0,
                                  0.2126, 0.7152, 0.0722, 0, 0,
                                  0.2126, 0.7152, 0.0722, 0, 0,
                                  0, 0, 0, 0.5, 0,
                                ]),
                                child: ClipOval(
                                  child: Image.asset('assets/images/roxi_icon.png'),
                                ),
                              )
                            : ClipOval(
                                child: Image.asset('assets/images/roxi_icon.png'),
                              ),
                      ),
                    ),
                  ),
                  // Disconnected slash overlay
                  if (_isDisconnected)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(painter: _DisconnectedSlashPainter()),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        const Gap(12),
        ExcludeSemantics(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Status text — clear like LetsVPN
              Text(
                _isConnected
                    ? AuthI18n.t['vpnConnected']!
                    : _isConnecting
                        ? AuthI18n.t['vpnConnecting']!
                        : AuthI18n.t['vpnDisconnected']!,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (_isConnected && secureLabel.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    AuthI18n.t['networkEncrypted']!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.green.shade600,
                      fontSize: 12,
                    ),
                  ),
                ),
              if (secureLabel.isNotEmpty) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(FontAwesomeIcons.shieldHalved, size: 16, color: Theme.of(context).colorScheme.secondary),
                    const Gap(4),
                    Text(
                      secureLabel,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: Theme.of(context).colorScheme.secondary,
                      ),
                    ),
                  ],
                ),
              ],
              const Gap(14),
              // Action button — "开启快连" / "断开连接"
              SizedBox(
                width: 180,
                height: 42,
                child: ElevatedButton(
                  onPressed: enabled ? onTap : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isConnected
                        ? Colors.grey.shade200
                        : Theme.of(context).colorScheme.primary,
                    foregroundColor: _isConnected
                        ? Colors.grey.shade700
                        : Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(22),
                    ),
                    elevation: _isConnected ? 0 : 2,
                  ),
                  child: Text(
                    _isConnected ? AuthI18n.t['disconnect']! : (_isConnecting ? AuthI18n.t['connecting']! : AuthI18n.t['tapConnect']!),
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}


/// Animated outer ring that pulses when connecting, glows green when connected,
/// and stays grey when disconnected.
class _AnimatedRing extends StatefulWidget {
  final Color color;
  final Color glowColor;
  final bool isConnecting;
  final bool isConnected;

  const _AnimatedRing({
    required this.color,
    required this.glowColor,
    required this.isConnecting,
    required this.isConnected,
  });

  @override
  State<_AnimatedRing> createState() => _AnimatedRingState();
}

class _AnimatedRingState extends State<_AnimatedRing> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500));
    _updateAnimation();
  }

  @override
  void didUpdateWidget(covariant _AnimatedRing old) {
    super.didUpdateWidget(old);
    if (old.isConnecting != widget.isConnecting || old.isConnected != widget.isConnected) {
      _updateAnimation();
    }
  }

  void _updateAnimation() {
    if (widget.isConnecting) {
      _ctrl.repeat(reverse: true);
    } else if (widget.isConnected) {
      // Gentle breathing
      _ctrl.duration = const Duration(milliseconds: 2500);
      _ctrl.repeat(reverse: true);
    } else {
      _ctrl.stop();
      _ctrl.value = 0;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final scale = widget.isConnecting
            ? 1.0 + _ctrl.value * 0.08
            : widget.isConnected
                ? 1.0 + _ctrl.value * 0.03
                : 1.0;
        final opacity = widget.isConnecting
            ? 0.5 + _ctrl.value * 0.5
            : widget.isConnected
                ? 0.7 + _ctrl.value * 0.3
                : 0.7;
        return Transform.scale(
          scale: scale,
          child: Container(
            width: 160,
            height: 160,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: widget.color.withValues(alpha: opacity),
                width: widget.isConnecting ? 3 : 2,
              ),
              boxShadow: widget.isConnected || widget.isConnecting
                  ? [BoxShadow(blurRadius: 12, spreadRadius: 1, color: widget.glowColor)]
                  : null,
            ),
          ),
        );
      },
    );
  }
}

/// Draws a diagonal slash across the button to indicate "disconnected" state.
/// Similar to the broken chain visual in LetsGo VPN.
class _DisconnectedSlashPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.red.withValues(alpha: .35)
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width * 0.28;

    // Diagonal slash from top-right to bottom-left through center
    canvas.drawLine(
      Offset(cx + r * 0.7, cy - r * 0.7),
      Offset(cx - r * 0.7, cy + r * 0.7),
      paint,
    );

    // Small "break" marks perpendicular to the slash
    final breakPaint = Paint()
      ..color = Colors.red.withValues(alpha: .3)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(
      Offset(cx + r * 0.15, cy - r * 0.35),
      Offset(cx + r * 0.35, cy - r * 0.15),
      breakPaint,
    );
    canvas.drawLine(
      Offset(cx - r * 0.35, cy + r * 0.15),
      Offset(cx - r * 0.15, cy + r * 0.35),
      breakPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
