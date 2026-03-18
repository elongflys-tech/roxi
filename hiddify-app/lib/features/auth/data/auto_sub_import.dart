import 'package:hiddify/features/auth/data/auth_service.dart';
import 'package:hiddify/features/profile/data/profile_data_providers.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/utils/custom_loggers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'auto_sub_import.g.dart';

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
          state = const AsyncData(false);
          return false;
        }
      }

      final sub = await auth.getSubscription().timeout(const Duration(seconds: 15));
      final subUrl = sub?['subscription_url'] as String?;
      if (subUrl == null || subUrl.isEmpty) {
        loggy.warning("auto-sub: no subscription_url from backend");
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
      state = AsyncError(e, st);
      return false;
    } finally {
      _importing = false;
    }
  }
}
