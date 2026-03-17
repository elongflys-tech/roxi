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

  @override
  AsyncValue<bool> build() => const AsyncData(false);

  Future<void> tryImport() async {
    if (_importing) return;
    if (state is AsyncLoading) return;

    // Check if already imported before (persistent flag)
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_importedKey) == true) {
      state = const AsyncData(true);
      return;
    }

    _importing = true;
    state = const AsyncLoading();
    try {
      final repo = ref.read(profileRepositoryProvider).requireValue;
      final existing = await repo.watchAll().first;
      final profileList = existing.getOrElse((_) => []);
      if (profileList.isNotEmpty) {
        await prefs.setBool(_importedKey, true);
        state = const AsyncData(true);
        return;
      }
      final auth = AuthService(prefs);
      if (!auth.isLoggedIn) {
        state = const AsyncData(false);
        return;
      }
      final sub = await auth.getSubscription().timeout(const Duration(seconds: 15));
      final subUrl = sub?['subscription_url'] as String?;
      if (subUrl == null || subUrl.isEmpty) {
        state = const AsyncData(false);
        return;
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
        return;
      }
      loggy.info("auto-sub: importing $subUrl");
      final result = await repo.upsertRemote(subUrl).run();
      result.fold(
        (f) => loggy.warning("auto-sub failed: $f"),
        (_) => loggy.info("auto-sub: added"),
      );
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
      await prefs.setBool(_importedKey, true);
      state = const AsyncData(true);
    } catch (e, st) {
      loggy.error("auto-sub error", e, st);
      state = AsyncError(e, st);
    } finally {
      _importing = false;
    }
  }
}
