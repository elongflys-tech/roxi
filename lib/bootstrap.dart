import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:hiddify/core/analytics/analytics_controller.dart';
import 'package:hiddify/core/app_info/app_info_provider.dart';
import 'package:hiddify/core/directories/directories_provider.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/logger/logger.dart';
import 'package:hiddify/core/logger/logger_controller.dart';
import 'package:hiddify/core/model/environment.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/core/preferences/preferences_migration.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/features/app/widget/app.dart';
import 'package:hiddify/features/auth/data/auth_service.dart';
import 'package:hiddify/features/auto_start/notifier/auto_start_notifier.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hiddify/features/log/data/log_data_providers.dart';
import 'package:hiddify/features/profile/data/profile_data_providers.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/system_tray/notifier/system_tray_notifier.dart';
import 'package:hiddify/features/window/notifier/window_notifier.dart';
import 'package:hiddify/hiddifycore/hiddify_core_service_provider.dart';
import 'package:hiddify/riverpod_observer.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Subscription URL obtained from auth flow, to be auto-added as profile.
String? _pendingSubscriptionUrl;

Future<void> lazyBootstrap(WidgetsBinding widgetsBinding, Environment env) async {
  if (!kIsWeb) {
    FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  }

  // --- Roxi Auth (non-blocking, runs in background) ---
  // Start device-register + fetch subscription URL in background.
  // Don't block bootstrap — splash screen stays visible while this runs.
  final authFuture = Future<String?>(() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final auth = AuthService(prefs);
      if (!auth.isLoggedIn) {
        await auth.deviceRegister();
      }
      if (auth.isLoggedIn) {
        try {
          final sub = await auth.getSubscription().timeout(const Duration(seconds: 6));
          if (sub != null && sub['subscription_url'] != null) {
            return sub['subscription_url'] as String;
          }
        } catch (_) {}
      }
    } catch (_) {}
    return null;
  });
  // --- End Roxi Auth ---

  LoggerController.preInit();
  FlutterError.onError = Logger.logFlutterError;
  WidgetsBinding.instance.platformDispatcher.onError = Logger.logPlatformDispatcherError;

  final stopWatch = Stopwatch()..start();

  final container = ProviderContainer(overrides: [environmentProvider.overrideWithValue(env)]);

  await _init("directories", () => container.read(appDirectoriesProvider.future));
  LoggerController.init(container.read(logPathResolverProvider).appFile().path);

  final appInfo = await _init("app info", () => container.read(appInfoProvider.future));
  await _init("preferences", () => container.read(sharedPreferencesProvider.future));

  final enableAnalytics = await container.read(analyticsControllerProvider.future);
  if (enableAnalytics) {
    await _init("analytics", () => container.read(analyticsControllerProvider.notifier).enableAnalytics());
  }

  await _init("preferences migration", () async {
    try {
      await PreferencesMigration(sharedPreferences: container.read(sharedPreferencesProvider).requireValue).migrate();
    } catch (e, stackTrace) {
      Logger.bootstrap.error("preferences migration failed", e, stackTrace);
      if (env == Environment.dev) rethrow;
      Logger.bootstrap.info("clearing preferences");
      await container.read(sharedPreferencesProvider).requireValue.clear();
    }
  });

  final debug = container.read(debugModeNotifierProvider) || kDebugMode;

  if (PlatformUtils.isDesktop) {
    await _init("window controller", () => container.read(windowNotifierProvider.future));

    final silentStart = container.read(Preferences.silentStart);
    Logger.bootstrap.debug("silent start [${silentStart ? "Enabled" : "Disabled"}]");
    if (!silentStart) {
      await container.read(windowNotifierProvider.notifier).show(focus: false);
    } else {
      Logger.bootstrap.debug("silent start, remain hidden accessible via tray");
    }
    await _init("auto start service", () => container.read(autoStartNotifierProvider.future));
  }
  await _init("logs repository", () => container.read(logRepositoryProvider.future));
  await _init("logger controller", () => LoggerController.postInit(debug));

  Logger.bootstrap.info(appInfo.format());

  await _init("profile repository", () => container.read(profileRepositoryProvider.future));

  // Mark intro as completed since user already went through our auth flow
  await container.read(Preferences.introCompleted.notifier).update(true);

  await _init("translations", () => container.read(translationsProvider.future));

  await _safeInit("active profile", () => container.read(activeProfileProvider.future), timeout: 1000);
  await _init("hiddify-core", () => container.read(hiddifyCoreServiceProvider).init());

  // Wait for auth result (should be done by now since it started early)
  _pendingSubscriptionUrl = await authFuture.timeout(
    const Duration(seconds: 3),
    onTimeout: () => null,
  );

  // Auto-add subscription URL from Roxi auth flow (must be after hiddify-core init)
  // Try up to 3 times with increasing delay if upsertRemote fails
  if (_pendingSubscriptionUrl != null) {
    await _safeInit("auto-add subscription", () async {
      final repo = container.read(profileRepositoryProvider).requireValue;

      bool added = false;
      for (int attempt = 1; attempt <= 3; attempt++) {
        final result = await repo.upsertRemote(_pendingSubscriptionUrl!).run();
        result.fold(
          (failure) {
            Logger.bootstrap.warning("auto-add subscription attempt $attempt/3 failed: $failure");
          },
          (_) {
            Logger.bootstrap.info("subscription auto-added: $_pendingSubscriptionUrl");
            added = true;
          },
        );
        if (added) break;
        // Wait before retry: 2s, 4s
        if (attempt < 3) {
          await Future.delayed(Duration(seconds: attempt * 2));
        }
      }

      if (!added) {
        Logger.bootstrap.warning("auto-add subscription failed after 3 attempts, will retry on connect");
        return;
      }

      // Set the newly added profile as active
      final profiles = await repo.watchAll().first;
      final profileList = profiles.getOrElse((_) => []);
      if (profileList.isNotEmpty) {
        final target = profileList.firstWhere(
          (p) => p is RemoteProfileEntity && p.url == _pendingSubscriptionUrl,
          orElse: () => profileList.first,
        );
        await repo.setAsActive(target.id).run();
        Logger.bootstrap.info("profile set as active: ${target.id}");
      }
    });
  }

  // Fallback: if there's still no active profile (subscription download failed
  // or auth was unreachable), import hardcoded bootstrap VLESS nodes so the
  // node list shows real connectable nodes instead of cosmetic previews.
  await _safeInit("bootstrap-nodes-fallback", () async {
    final activeProfile = await container.read(activeProfileProvider.future);
    if (activeProfile != null) return; // already have a profile, no need

    final prefs = container.read(sharedPreferencesProvider).requireValue;
    if (prefs.getBool('bootstrap_imported') == true) {
      // Bootstrap nodes were imported in a previous launch but profile might
      // have been cleaned up. Re-check if any profile exists at all.
      final repo = container.read(profileRepositoryProvider).requireValue;
      final existing = await repo.watchAll().first;
      final list = existing.getOrElse((_) => []);
      if (list.isNotEmpty) return; // profiles exist, just not active — skip
    }

    Logger.bootstrap.info("no active profile after bootstrap, importing embedded nodes");
    const bootstrapVless = [
      'vless://94134baf-dab3-41dc-9c15-085fdf15b86e@168.231.126.166:443?hiddify=1&sni=168.231.126.166&type=xhttp&alpn=http%2F1.1&path=%2FlY4xhKGq8xfNOWdIEmY7Q&host=168.231.126.166&encryption=none&fp=chrome&core=xray&extra=%7B%22headers%22%3A%7B%7D%7D&headerType=none&allowInsecure=true&insecure=true&security=tls#%F0%9F%8C%90%20%E5%BC%95%E5%AF%BC%E8%8A%82%E7%82%B91',
      'vless://94134baf-dab3-41dc-9c15-085fdf15b86e@72.61.170.142:443?hiddify=1&sni=72.61.170.142&type=xhttp&alpn=http%2F1.1&path=%2FmwNPtjMmRlEizimS5Qr3&host=72.61.170.142&encryption=none&fp=chrome&core=xray&extra=%7B%22headers%22%3A%7B%7D%7D&headerType=none&allowInsecure=true&insecure=true&security=tls#%F0%9F%8C%90%20%E5%BC%95%E5%AF%BC%E8%8A%82%E7%82%B92',
    ];
    final rawContent = bootstrapVless.join('\n');
    final b64Content = base64Encode(utf8.encode(rawContent));
    final bootstrapUrl = 'data:application/octet-stream;base64,$b64Content';

    final repo = container.read(profileRepositoryProvider).requireValue;
    final result = await repo.upsertRemote(bootstrapUrl).run();
    result.fold(
      (f) => Logger.bootstrap.warning("bootstrap nodes import failed: $f"),
      (_) => Logger.bootstrap.info("bootstrap nodes imported successfully"),
    );

    // Set as active
    final after = await repo.watchAll().first;
    final list = after.getOrElse((_) => []);
    if (list.isNotEmpty) {
      await repo.setAsActive(list.last.id).run();
      Logger.bootstrap.info("bootstrap profile set as active: ${list.last.id}");
    }
    await prefs.setBool('bootstrap_imported', true);
  });

  if (!kIsWeb) {
    // await _safeInit(
    //   "deep link service",
    //   () => container.read(deepLinkNotifierProvider.future),
    //   timeout: 1000,
    // );

    if (PlatformUtils.isDesktop) {
      await _safeInit("system tray", () => container.read(systemTrayNotifierProvider.future), timeout: 1000);
    }

    if (PlatformUtils.isAndroid) {
      await _safeInit("android display mode", () async {
        await FlutterDisplayMode.setHighRefreshRate();
      });
    }
  }

  Logger.bootstrap.info("bootstrap took [${stopWatch.elapsedMilliseconds}ms]");
  stopWatch.stop();

  runApp(
    ProviderScope(
      parent: container,
      observers: [RiverpodObserver()],
      child: SentryUserInteractionWidget(child: const App()),
    ),
  );

  if (!kIsWeb) {
    FlutterNativeSplash.remove();
  }

  // Remove macOS native splash screen
  if (Platform.isMacOS) {
    const MethodChannel('splash_screen').invokeMethod('remove');
  }
  // SentryFlutter.s(DateTime.now().toUtc());
}

Future<T> _init<T>(String name, Future<T> Function() initializer, {int? timeout}) async {
  final stopWatch = Stopwatch()..start();
  Logger.bootstrap.info("initializing [$name]");
  Future<T> func() => timeout != null ? initializer().timeout(Duration(milliseconds: timeout)) : initializer();
  try {
    final result = await func();
    Logger.bootstrap.debug("[$name] initialized in ${stopWatch.elapsedMilliseconds}ms");
    return result;
  } catch (e, stackTrace) {
    Logger.bootstrap.error("[$name] error initializing", e, stackTrace);
    rethrow;
  } finally {
    stopWatch.stop();
  }
}

Future<T?> _safeInit<T>(String name, Future<T> Function() initializer, {int? timeout}) async {
  try {
    return await _init(name, initializer, timeout: timeout);
  } catch (e) {
    return null;
  }
}
