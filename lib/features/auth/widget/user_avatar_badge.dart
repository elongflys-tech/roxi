import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hiddify/features/auth/data/auth_service.dart';
import 'package:hiddify/features/auth/data/auth_i18n.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// User avatar with status badge and tier-colored border ring.
/// Mimics LetsGo VPN's avatar area that shows membership status at a glance.
///
/// Tiers:
///   - device/free (no plan): grey ring
///   - trial: orange ring + "体验" badge
///   - expired: red ring + "过期" badge
///   - VIP: gold ring + "VIP" badge
///   - SVIP: purple-gold gradient ring + "SVIP" badge

String _resolveTier(String tier, String? expireDateStr) {
  final t = tier.toLowerCase();
  if (t == 'vip' || t == 'svip') {
    if (expireDateStr != null) {
      final exp = DateTime.tryParse(expireDateStr);
      if (exp != null && exp.isBefore(DateTime.now())) return 'expired';
    }
    return t;
  }
  return 'free';
}

class UserAvatarBadge extends HookWidget {
  final VoidCallback onTap;
  final double size;

  const UserAvatarBadge({super.key, required this.onTap, this.size = 36});

  @override
  Widget build(BuildContext context) {
    // tier: "free" | "expired" | "vip" | "svip"
    final tier = useState<String>('free');
    final loading = useState(true);

    useEffect(() {
      () async {
        try {
          final prefs = await SharedPreferences.getInstance();
          final auth = AuthService(prefs);
          if (!auth.isLoggedIn) {
            tier.value = 'free';
            loading.value = false;
            return;
          }
          // Start with cached tier immediately (no network wait)
          tier.value = _resolveTier(auth.cachedTier, auth.cachedExpireDate);
          loading.value = false;

          // Then try to refresh from network in background
          final user = await auth.getUserInfo();
          if (user != null) {
            tier.value = _resolveTier(
              (user['tier'] as String?) ?? 'free',
              user['expire_date']?.toString(),
            );
          }
        } catch (_) {
          // Keep whatever tier we already set from cache
        }
        loading.value = false;
      }();
      return null;
    }, []);

    final config = _tierConfig(tier.value);

    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: size + 12,
        height: size + 12,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Ring + avatar
            Center(
              child: Container(
                width: size + 6,
                height: size + 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: config.gradient,
                  border: config.gradient == null
                      ? Border.all(color: config.ringColor, width: 2.5)
                      : null,
                ),
                padding: const EdgeInsets.all(2.5),
                child: CircleAvatar(
                  radius: size / 2,
                  backgroundColor: Colors.grey.shade100,
                  child: Icon(
                    Icons.person_rounded,
                    size: size * 0.6,
                    color: config.ringColor.withValues(alpha: .7),
                  ),
                ),
              ),
            ),
            // Badge label
            if (config.badge != null)
              Positioned(
                bottom: -2,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: config.badgeBg,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                    child: Text(
                      config.badge!,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 8,
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                      ),
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

class _TierConfig {
  final Color ringColor;
  final LinearGradient? gradient;
  final String? badge;
  final Color badgeBg;

  const _TierConfig({
    required this.ringColor,
    this.gradient,
    this.badge,
    this.badgeBg = Colors.grey,
  });
}

_TierConfig _tierConfig(String tier) {
  final s = AuthI18n.t;
  switch (tier) {
    case 'free':
      return _TierConfig(
        ringColor: Colors.green,
        badge: s['freeTier'] ?? '免费',
        badgeBg: Colors.green,
      );
    case 'expired':
      return _TierConfig(
        ringColor: Colors.red.shade400,
        badge: s['expiredBadge'] ?? '过期',
        badgeBg: Colors.red,
      );
    case 'vip':
      return _TierConfig(
        ringColor: const Color(0xFFD4A017),
        badge: 'VIP',
        badgeBg: const Color(0xFFD4A017),
      );
    case 'svip':
      return _TierConfig(
        ringColor: const Color(0xFF9C27B0),
        gradient: const LinearGradient(
          colors: [Color(0xFF9C27B0), Color(0xFFD4A017)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        badge: 'SVIP',
        badgeBg: const Color(0xFF7B1FA2),
      );
    default: // free
      return _TierConfig(
        ringColor: Colors.grey.shade400,
      );
  }
}
