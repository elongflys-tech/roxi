import 'dart:convert';

import 'package:hiddify/features/auth/data/auth_service.dart';
import 'package:hiddify/features/profile/data/profile_data_providers.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/utils/custom_loggers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'auto_sub_import.g.dart';

/// Two real VLESS xhttp bootstrap nodes hardcoded in APK.
/// Used as last-resort when ALL API domains (roxi.cc, roxijet.cloud) are blocked.
/// Once connected via these, the app auto-retries fetching the real subscription.
const _bootstrapVlessNodes = [
  'vless://94134baf-dab3-41dc-9c15-085fdf15b86e@168.231.126.166:443?hiddify=1&sni=168.231.126.166&type=xhttp&alpn=http%2F1.1&path=%2FlY4xhKGq8xfNOWdIEmY7Q&host=168.231.126.166&encryption=none&fp=chrome&core=xray&extra=%7B%22headers%22%3A%7B%7D%7D&headerType=none&allowInsecure=true&insecure=true&security=tls#%F0%9F%8C%90%20%E5%BC%95%E5%AF%BC%E8%8A%82%E7%82%B91',
  'vless://94134baf-dab3-41dc-9c15-085fdf15b86e@72.61.170.142:443?hiddify=1&sni=72.61.170.142&type=xhttp&alpn=http%2F1.1&path=%2FmwNPtjMmRlEizimS5Qr3&host=72.61.170.142&encryption=none&fp=chrome&core=xray&extra=%7B%22headers%22%3A%7B%7D%7D&headerType=none&allowInsecure=true&insecure=true&security=tls#%F0%9F%8C%90%20%E5%BC%95%E5%AF%BC%E8%8A%82%E7%82%B92',
];

/// Profile name used for bootstrap so we can identify & replace it later.
const _bootstrapProfileName = 'Roxi-Bootstrap';
const _bootstrapImportedKey = 'bootstrap_imported';

@riverpod
class AutoSubImport extends _$AutoSubImport with InfraLogger {
  static bool _importing = false;  // static: survives notifier rebuild
  static const _importedKey = 'auto_sub_imported';
  static int _retryCount = 0;
  static const _maxRetries = 3;

  @override
  AsyncValue<bool> build() => const AsyncData(false);

  /// Force re-import: ignores the persistent flag and retry count.
  /// Called when user taps connect but has no active profile.
  Future<bool> forceImport() async {
    _retryCount = 0;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_importedKey);
    return await _doImport(force: true);
  }

  Future<void> tryImport() async {
    await _doImport(force: false);
  }

  /// Core import logic. Returns true if a profile was successfully added.
  Future<bool> _doImport({required bool force}) async {
    if (_importing) return false;
    if (!force && state is AsyncLoading) return false;

    final prefs = await SharedPreferences.getInstance();
    if (!force && prefs.getBool(_importedKey) == true) {
      state = const AsyncData(true);
      return true;
    }

    _importing = true;
    state = const AsyncLoading();
    try {
      final repo = ref.read(profileRepositoryProvider).requireValue;

      // Check existing profiles — but only mark done if they have a remote URL
      // (prevents marking done when profile exists but is empty/broken)
      if (!force) {
        final existing = await repo.watchAll().first;
        final profileList = existing.getOrElse((_) => []);
        final hasRemote = profileList.any((p) => p is RemoteProfileEntity);
        if (hasRemote) {
          await prefs.setBool(_importedKey, true);
          state = const AsyncData(true);
          return true;
        }
      }

      final auth = AuthService(prefs);
      if (!auth.isLoggedIn) {
        // Try device register first
        final err = await auth.deviceRegister();
        if (err != null) {
          loggy.warning("auto-sub: device register failed: $err");
          // API completely unreachable — backoff then try bootstrap nodes as last resort
          await Future.delayed(const Duration(seconds: 2));
          final bootstrapped = await _importBootstrapNodes(prefs);
          if (bootstrapped) {
            state = const AsyncData(true);
            return true;
          }
          state = const AsyncData(false);
          return false;
        }
      }

      final sub = await auth.getSubscription().timeout(const Duration(seconds: 15));
      final subUrl = sub?['subscription_url'] as String?;
      if (subUrl == null || subUrl.isEmpty) {
        loggy.warning("auto-sub: no subscription_url from backend");
        // Could be API issue — backoff then try bootstrap if API is truly unreachable
        await Future.delayed(const Duration(seconds: 2));
        final reachable = await AuthService.isApiReachable();
        if (!reachable) {
          final bootstrapped = await _importBootstrapNodes(prefs);
          if (bootstrapped) {
            state = const AsyncData(true);
            return true;
          }
        }
        state = const AsyncData(false);
        return false;
      }

      // Double-check: re-read profiles in case another import snuck in
      final recheck = await repo.watchAll().first;
      final recheckList = recheck.getOrElse((_) => []);
      final alreadyExists = recheckList.any(
        (p) => p is RemoteProfileEntity && p.url == subUrl,
      );
      if (alreadyExists) {
        loggy.info("auto-sub: profile already exists for $subUrl, skipping");
        await prefs.setBool(_importedKey, true);
        state = const AsyncData(true);
        return true;
      }

      loggy.info("auto-sub: importing $subUrl");
      final result = await repo.upsertRemote(subUrl).run();
      bool success = false;
      result.fold(
        (f) => loggy.warning("auto-sub upsertRemote failed: $f"),
        (_) {
          loggy.info("auto-sub: added");
          success = true;
        },
      );

      if (!success) {
        // upsertRemote failed (e.g. singbox rejected config) — do NOT mark as done
        _retryCount++;
        loggy.warning("auto-sub: upsertRemote failed, retry $_retryCount/$_maxRetries");
        state = const AsyncData(false);
        return false;
      }

      final after = await repo.watchAll().first;
      final list = after.getOrElse((_) => []);
      if (list.isNotEmpty) {
        final t = list.firstWhere(
          (p) => p is RemoteProfileEntity && p.url == subUrl,
          orElse: () => list.first,
        );
        await repo.setAsActive(t.id).run();
        loggy.info("auto-sub: active=${t.id}");
      }
      // Only mark done on actual success
      await prefs.setBool(_importedKey, true);
      state = const AsyncData(true);
      return true;
    } catch (e, st) {
      loggy.error("auto-sub error", e, st);
      // Last resort: if exception was network-related, backoff then try bootstrap
      try {
        await Future.delayed(const Duration(seconds: 3));
        final prefs = await SharedPreferences.getInstance();
        final reachable = await AuthService.isApiReachable();
        if (!reachable) {
          final bootstrapped = await _importBootstrapNodes(prefs);
          if (bootstrapped) {
            state = const AsyncData(true);
            return true;
          }
        }
      } catch (_) {}
      state = AsyncError(e, st);
      return false;
    } finally {
      _importing = false;
    }
  }

  /// Import hardcoded bootstrap VLESS nodes as a local subscription profile.
  /// This is the last-resort fallback when ALL API domains are blocked by GFW.
  /// After connecting, [scheduleBootstrapReplacement] will auto-retry the real sub.
  Future<bool> _importBootstrapNodes(SharedPreferences prefs) async {
    try {
      // Don't re-import if we already have a bootstrap profile
      if (prefs.getBool(_bootstrapImportedKey) == true) {
        loggy.info("bootstrap: already imported, skipping");
        return true;
      }

      loggy.info("bootstrap: API unreachable, importing ${_bootstrapVlessNodes.length} embedded nodes");

      final repo = ref.read(profileRepositoryProvider).requireValue;

      // Build a subscription-style content: base64-encoded VLESS URIs (one per line)
      final rawContent = _bootstrapVlessNodes.join('\n');
      final b64Content = base64Encode(utf8.encode(rawContent));

      // Create a data URI that Hiddify's profile parser can consume
      // Using a special URL scheme so we can identify it later
      final bootstrapUrl = 'data:application/octet-stream;base64,$b64Content';

      final result = await repo.upsertRemote(bootstrapUrl).run();
      bool success = false;
      result.fold(
        (f) => loggy.warning("bootstrap: upsertRemote failed: $f"),
        (_) {
          loggy.info("bootstrap: profile added successfully");
          success = true;
        },
      );

      if (success) {
        // Set as active profile
        final after = await repo.watchAll().first;
        final list = after.getOrElse((_) => []);
        if (list.isNotEmpty) {
          final bp = list.last; // newest profile
          await repo.setAsActive(bp.id).run();
          loggy.info("bootstrap: set active=${bp.id}");
        }
        await prefs.setBool(_bootstrapImportedKey, true);

        // Schedule replacement: after VPN connects, retry real subscription
        _scheduleBootstrapReplacement();
        return true;
      }
    } catch (e, st) {
      loggy.error("bootstrap: import error", e, st);
    }
    return false;
  }

  /// After connecting via bootstrap nodes, periodically retry fetching the
  /// real subscription. Once successful, the bootstrap profile is replaced.
  void _scheduleBootstrapReplacement() {
    Future.delayed(const Duration(seconds: 30), () async {
      for (int attempt = 1; attempt <= 5; attempt++) {
        loggy.info("bootstrap-replace: attempt $attempt/5");
        try {
          final reachable = await AuthService.isApiReachable(timeout: const Duration(seconds: 10));
          if (!reachable) {
            loggy.info("bootstrap-replace: API still unreachable, waiting...");
            await Future.delayed(Duration(seconds: 15 * attempt));
            continue;
          }

          // API is reachable now — clear bootstrap flag and force real import
          final prefs = await SharedPreferences.getInstance();
          await prefs.remove(_bootstrapImportedKey);
          await prefs.remove(_importedKey);
          _retryCount = 0;

          final success = await _doImport(force: true);
          if (success) {
            loggy.info("bootstrap-replace: real subscription imported, bootstrap replaced");
            return;
          }
        } catch (e) {
          loggy.warning("bootstrap-replace: attempt $attempt failed: $e");
        }
        await Future.delayed(Duration(seconds: 20 * attempt));
      }
      loggy.warning("bootstrap-replace: all 5 attempts failed, user stays on bootstrap nodes");
    });
  }
}
