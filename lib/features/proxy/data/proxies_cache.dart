import 'dart:convert';

import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Simple cache for the last-known outbound group so the node list can be
/// displayed immediately before sing-box starts.
class ProxiesCache {
  static const _key = 'cached_outbound_group';

  /// Persist the current [OutboundGroup] to SharedPreferences as proto3 JSON.
  static Future<void> save(OutboundGroup group) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = jsonEncode(group.toProto3Json());
      await prefs.setString(_key, json);
    } catch (_) {
      // Best-effort — never block the main flow.
    }
  }

  /// Load the previously cached [OutboundGroup].
  ///
  /// Returns `null` if nothing is cached or the data is corrupt.
  /// Delay values are cleared so the UI shows "--" instead of stale numbers.
  static Future<OutboundGroup?> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null || raw.isEmpty) return null;
      final group = OutboundGroup()..mergeFromProto3Json(jsonDecode(raw));
      // Clear stale delay values — they are meaningless without a live test.
      for (final item in group.items) {
        item.urlTestDelay = 0;
        item.clearUrlTestTime();
      }
      return group;
    } catch (_) {
      return null;
    }
  }
}
