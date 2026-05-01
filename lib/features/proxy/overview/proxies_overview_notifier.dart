import 'dart:async';

import 'package:dartx/dartx.dart';
import 'package:rxdart/rxdart.dart';

import 'package:hiddify/core/haptic/haptic_service.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/core/utils/preferences_utils.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/profile/data/profile_data_providers.dart';
import 'package:hiddify/features/proxy/data/proxy_data_providers.dart';
import 'package:hiddify/features/proxy/data/proxies_cache.dart';
import 'package:hiddify/features/proxy/model/proxy_failure.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hiddify/hiddifycore/hiddify_core_service_provider.dart';
import 'package:hiddify/hiddifycore/init_signal.dart';
import 'package:hiddify/utils/riverpod_utils.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'proxies_overview_notifier.g.dart';

enum ProxiesSort {
  unsorted,
  name,
  delay,
  usage;

  String present(TranslationsEn t) => switch (this) {
    ProxiesSort.unsorted => t.pages.proxies.sortOptions.unsorted,
    ProxiesSort.name => t.pages.proxies.sortOptions.name,
    ProxiesSort.delay => t.pages.proxies.sortOptions.delay,
    ProxiesSort.usage => t.pages.proxies.sortOptions.usage,
  };
}

@Riverpod(keepAlive: true)
class ProxiesSortNotifier extends _$ProxiesSortNotifier with AppLogger {
  late final _pref = PreferencesEntry(
    preferences: ref.watch(sharedPreferencesProvider).requireValue,
    key: "proxies_sort_mode",
    defaultValue: ProxiesSort.delay,
    mapFrom: ProxiesSort.values.byName,
    mapTo: (value) => value.name,
  );

  @override
  ProxiesSort build() {
    final sortBy = _pref.read();
    loggy.info("sort proxies by: [${sortBy.name}]");
    return sortBy;
  }

  Future<void> update(ProxiesSort value) {
    state = value;
    return _pref.write(value);
  }
}

@riverpod
class ProxiesOverviewNotifier extends _$ProxiesOverviewNotifier with AppLogger {
  /// When true, incoming stream updates only merge delay/selection data into
  /// the existing item order instead of re-sorting the list.  This prevents
  /// the jarring list-jump users see after tapping a node.
  bool _sortFrozen = false;

  /// The tag-order snapshot captured when sort was frozen.  Stream updates
  /// preserve this order and only patch delay / isSelected fields.
  List<String>? _frozenOrder;

  @override
  Stream<OutboundGroup?> build() async* {
    ref.disposeDelay(const Duration(seconds: 15));
    ref.watch(coreRestartSignalProvider);
    final serviceRunning = await ref.watch(serviceRunningProvider.future);
    final sortBy = ref.watch(proxiesSortNotifierProvider);

    // Reset freeze state on rebuild (e.g. sort mode changed by user).
    _sortFrozen = false;
    _frozenOrder = null;

    if (!serviceRunning) {
      // Service not running — try offline parsing of the active profile's
      // config file so the node list is available before connection.
      final activeProfile = await ref.watch(activeProfileProvider.future);
      if (activeProfile != null) {
        final singbox = ref.read(hiddifyCoreServiceProvider);
        final pathResolver = ref.read(profilePathResolverProvider);
        final configPath = pathResolver.file(activeProfile.id).path;
        final parsed = await singbox.parseOutbounds(configPath);
        if (parsed != null && parsed.items.isNotEmpty) {
          final group = parsed.items.first;
          // Also update the cache with the freshly parsed data.
          ProxiesCache.save(group);
          yield await _sortOutbounds(group, sortBy);
          return;
        }
      }
      // Offline parsing failed or no profile — fall back to cache.
      final cached = await ProxiesCache.load();
      if (cached != null) {
        yield await _sortOutbounds(cached, sortBy);
      } else {
        // Nothing available — yield null so the UI receives AsyncData(null)
        // instead of staying stuck in AsyncLoading forever.
        yield null;
      }
      return;
    }

    yield* ref
        .watch(proxyRepositoryProvider)
        .watchProxies()
        .throttleTime(const Duration(seconds: 1), leading: true, trailing: true)
        .map(
          (event) => event.getOrElse((err) {
            loggy.warning("error receiving proxies", err);
            throw err;
          }),
        )
        .asyncMap((proxies) async {
          // Persist to cache for next cold start.
          if (proxies != null) {
            ProxiesCache.save(proxies);
          }

          if (_sortFrozen && _frozenOrder != null && proxies != null) {
            // Sort is frozen — merge fresh delay / selection data into the
            // existing order so the list doesn't jump around.
            return _mergeIntoFrozenOrder(proxies);
          }
          return await _sortOutbounds(proxies, sortBy);
        });
  }

  // Future<List<OutboundGroup>> _sortOutbounds(
  //   List<OutboundGroup> proxies,
  //   ProxiesSort sortBy,
  // ) async {
  //   final groupWithSelected = {
  //     for (final o in proxies) o.tag: o.selected,
  //   };
  //   final sortedProxies = <OutboundGroup>[];
  //   for (final group in proxies) {
  //     final sortedItems = switch (sortBy) {
  //       ProxiesSort.name => group.items.sortedWith((a, b) {
  //           if (a.isGroup && !b.isGroup) return -1;
  //           if (!a.isGroup && b.isGroup) return 1;
  //           return a.tag.compareTo(b.tag);
  //         }),
  //       ProxiesSort.delay => group.items.sortedWith((a, b) {
  //           if (a.isGroup && !b.isGroup) return -1;
  //           if (!a.isGroup && b.isGroup) return 1;

  //           final ai = a.urlTestDelay;
  //           final bi = b.urlTestDelay;
  //           if (ai == 0 && bi == 0) return -1;
  //           if (ai == 0 && bi > 0) return 1;
  //           if (ai > 0 && bi == 0) return -1;
  //           return ai.compareTo(bi);
  //         }),
  //       ProxiesSort.unsorted => group.items,
  //     };
  //     final items = <OutboundInfo>[];
  //     for (final item in sortedItems) {
  //       // if (groupWithSelected.keys.contains(item.tag)) {
  //       //   items.add(item.copyWith(selectedTag: groupWithSelected[item.tag]));
  //       // } else {
  //       items.add(item);
  //       // }
  //     }
  //     group.items.clear();
  //     group.items.addAll(items);
  //     sortedProxies.add(group);
  //   }
  //   return sortedProxies;
  // }

  Future<OutboundGroup?> _sortOutbounds(OutboundGroup? proxies, ProxiesSort sortBy) async {
    if (proxies == null) return null;

    final sortedItems = switch (sortBy) {
      ProxiesSort.name => proxies.items.sortedWith((a, b) {
        if (a.isGroup && !b.isGroup) return -1;
        if (!a.isGroup && b.isGroup) return 1;
        return a.tag.compareTo(b.tag);
      }),
      ProxiesSort.delay => proxies.items.sortedWith((a, b) {
        if (a.isGroup && !b.isGroup) return -1;
        if (!a.isGroup && b.isGroup) return 1;

        final ai = a.urlTestDelay;
        final bi = b.urlTestDelay;
        if (ai == 0 && bi == 0) return -1;
        if (ai == 0 && bi > 0) return 1;
        if (ai > 0 && bi == 0) return -1;
        return ai.compareTo(bi);
      }),
      ProxiesSort.unsorted => proxies.items,
      ProxiesSort.usage => proxies.items.sortedWith((a, b) {
        if (a.isGroup && !b.isGroup) return -1;
        if (!a.isGroup && b.isGroup) return 1;
        return (b.upload + b.download).compareTo(a.upload + a.download);
      }),
    };
    final items = <OutboundInfo>[];
    for (final item in sortedItems) {
      items.add(item);
    }
    proxies.items.clear();
    proxies.items.addAll(items);
    return proxies;
  }

  /// Merge fresh data from [incoming] into the frozen tag order.
  /// Preserves list position; only updates delay, isSelected, ipinfo, etc.
  OutboundGroup _mergeIntoFrozenOrder(OutboundGroup incoming) {
    final freshByTag = <String, OutboundInfo>{};
    for (final item in incoming.items) {
      freshByTag[item.tag] = item;
    }

    final merged = <OutboundInfo>[];
    // First: items in frozen order (preserving position).
    for (final tag in _frozenOrder!) {
      final fresh = freshByTag.remove(tag);
      if (fresh != null) {
        merged.add(fresh);
      }
    }
    // Then: any new items that weren't in the frozen snapshot (append at end).
    merged.addAll(freshByTag.values);

    incoming.items.clear();
    incoming.items.addAll(merged);
    return incoming;
  }

  // Future<void> changeProxy(String groupTag, String outboundTag) async {
  //   loggy.debug(
  //     "changing proxy, group: [$groupTag] - outbound: [$outboundTag]",
  //   );
  //   if (state case AsyncData(value: final outbounds)) {
  //     await ref.read(hapticServiceProvider.notifier).lightImpact();
  //     await ref.read(proxyRepositoryProvider).selectProxy(groupTag, outboundTag).getOrElse((err) {
  //       loggy.warning("error selecting outbound", err);
  //       throw err;
  //     }).run();
  //     final outboundg = outbounds.where((e) => e.tag == groupTag).firstOrNull;
  //     if (outboundg != null) {
  //       final newselected = outboundg.items.where((e) => e.tag == outboundTag).firstOrNull;
  //       if (newselected != null) {
  //         newselected.isSelected = true;
  //         outboundg.selected = newselected;
  //       }
  //     }
  //     state = AsyncData(
  //       [...outbounds],
  //     ).copyWithPrevious(state);
  //   }
  // }

  Future<void> changeProxy(String groupTag, String outboundTag) async {
    loggy.debug("changing proxy, group: [$groupTag] - outbound: [$outboundTag]");
    if (!state.hasValue) return;
    final outbounds = state.value!;

    // Remember previous selection for rollback
    final previousSelected = outbounds.selected;

    // Freeze sort order — capture current tag positions so that incoming
    // stream updates only patch delay/selection without re-ordering.
    _frozenOrder = outbounds.items.map((e) => e.tag).toList();
    _sortFrozen = true;

    // Optimistic UI update — show selection immediately
    final newselected = outbounds.items.where((e) => e.tag == outboundTag).firstOrNull;
    if (newselected != null) {
      // Clear previous selection
      for (final item in outbounds.items) {
        item.isSelected = false;
      }
      newselected.isSelected = true;
      outbounds.selected = newselected.tag;
      state = AsyncValue.data(outbounds);
    }

    await ref.read(hapticServiceProvider.notifier).lightImpact();
    final result = await ref.read(proxyRepositoryProvider).selectProxy(groupTag, outboundTag).run();
    result.match(
      (err) {
        loggy.warning("error selecting outbound, rolling back", err);
        // Rollback UI to previous selection
        for (final item in outbounds.items) {
          item.isSelected = item.tag == previousSelected;
        }
        outbounds.selected = previousSelected;
        state = AsyncValue.data(outbounds);
        // Unfreeze on error so next stream update re-sorts normally.
        _sortFrozen = false;
        _frozenOrder = null;
      },
      (_) {},
    );
  }

  Future<void> urlTest(String groupTag) async {
    loggy.debug("testing group: [$groupTag]");
    if (state case AsyncData()) {
      await ref.read(hapticServiceProvider.notifier).lightImpact();
      await ref.read(proxyRepositoryProvider).urlTest(groupTag).getOrElse((err) {
        loggy.error("error testing group", err);
        throw err;
      }).run();
      // Unfreeze sort after explicit url-test so the list re-sorts with
      // fresh delay values on the next stream update.
      _sortFrozen = false;
      _frozenOrder = null;
    }
  }

  /// Unfreeze sort order.  Called externally when the user explicitly
  /// refreshes the subscription or triggers a full re-sort.
  void unfreezeSort() {
    _sortFrozen = false;
    _frozenOrder = null;
  }
}
