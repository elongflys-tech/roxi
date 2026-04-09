import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hiddify/features/auth/data/device_fingerprint.dart';

/// Service for communicating with our business backend API.
class AuthService {
  static const String baseUrl = 'https://roxi.cc';
  static const List<String> _fallbackUrls = [
    'https://roxi.cc',
    'https://roxijet.cloud',
  ];

  /// Try GET request across all fallback domains. Returns first successful response.
  static Future<http.Response?> _getWithFallback(
    String path, {
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    for (int i = 0; i < _fallbackUrls.length; i++) {
      if (i > 0) await Future.delayed(Duration(milliseconds: 800 * i));
      try {
        final resp = await http.get(
          Uri.parse('${_fallbackUrls[i]}$path'),
          headers: headers,
        ).timeout(timeout);
        if (resp.statusCode == 200) return resp;
      } catch (_) {
        // Try next domain after backoff
      }
    }
    return null;
  }

  /// Try POST request across all fallback domains. Returns first successful response.
  static Future<http.Response?> _postWithFallback(
    String path, {
    Map<String, String>? headers,
    String? body,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    for (int i = 0; i < _fallbackUrls.length; i++) {
      if (i > 0) await Future.delayed(Duration(milliseconds: 800 * i));
      try {
        final resp = await http.post(
          Uri.parse('${_fallbackUrls[i]}$path'),
          headers: headers,
          body: body,
        ).timeout(timeout);
        if (resp.statusCode == 200) return resp;
      } catch (_) {
        // Try next domain after backoff
      }
    }
    return null;
  }

  // In-memory cache for plans (avoid re-fetching on every sheet open)
  static List<Map<String, dynamic>>? _plansCache;
  static DateTime? _plansCacheTime;
  static const _plansCacheTTL = Duration(seconds: 60);

  static List<Map<String, dynamic>>? _nodesCache;
  static DateTime? _nodesCacheTime;
  static const _nodesCacheTTL = Duration(seconds: 120);

  static Map<String, dynamic>? _userInfoCache;
  static DateTime? _userInfoCacheTime;
  static const _userInfoCacheTTL = Duration(seconds: 30);

  static Map<String, dynamic>? _inviteInfoCache;
  static DateTime? _inviteInfoCacheTime;
  static const _inviteInfoCacheTTL = Duration(seconds: 60);

  static Map<String, String>? _inviteTextCache;
  static DateTime? _inviteTextCacheTime;
  static const _inviteTextCacheTTL = Duration(minutes: 30);

  static const _tokenKey = 'roxi_token';
  static const _emailKey = 'roxi_email';
  static const _deviceIdKey = 'roxi_device_id';
  static const _cachedTierKey = 'roxi_cached_tier';
  static const _cachedStatusKey = 'roxi_cached_status';
  static const _cachedExpireDateKey = 'roxi_cached_expire_date';

  final SharedPreferences _prefs;

  AuthService(this._prefs);

  String? get token => _prefs.getString(_tokenKey);
  String? get email => _prefs.getString(_emailKey);
  String? get deviceId => _prefs.getString(_deviceIdKey);
  bool get isLoggedIn => token != null && token!.isNotEmpty;
  bool get hasEmail => email != null && email!.isNotEmpty;

  /// Cached tier from last successful API call. Works offline.
  String get cachedTier => _prefs.getString(_cachedTierKey) ?? 'free';

  /// Cached user status from last successful API call. Works offline.
  String get cachedStatus => _prefs.getString(_cachedStatusKey) ?? 'free';

  /// Quick check: is user VIP or SVIP with active subscription?
  /// Uses cached data — safe to call offline.
  bool get isPaidUser {
    final tier = cachedTier;
    final status = cachedStatus;
    return (tier == 'vip' || tier == 'svip') && status != 'expired';
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json; charset=utf-8',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  String _body(http.Response resp) => utf8.decode(resp.bodyBytes);

  Future<void> _saveAuth(String token, String email) async {
    await _prefs.setString(_tokenKey, token);
    await _prefs.setString(_emailKey, email);
  }

  Future<void> logout() async {
    await _prefs.remove(_tokenKey);
    await _prefs.remove(_emailKey);
  }

  /// Auto device register — no email/password needed.
  /// Uses hardware fingerprint as stable device_id (survives reinstall).
  /// Falls back to random ID only if fingerprint unavailable.
  Future<String?> deviceRegister() async {
    try {
      // Collect hardware fingerprint first — this is the stable device identity
      String? hwFp;
      int envFlags = 0;
      try {
        final results = await Future.wait([
          _getHwFingerprint(),
          _getEnvFlags(),
        ]);
        hwFp = results[0] as String?;
        envFlags = results[1] as int;
      } catch (_) {}

      // Device ID: prefer hardware fingerprint (stable across reinstalls)
      // Fall back to cached random ID, then generate new random as last resort
      String? devId = _prefs.getString(_deviceIdKey);
      if (hwFp != null && hwFp.isNotEmpty) {
        // Use hw fingerprint as device_id — same device = same ID after reinstall
        devId = hwFp;
        await _prefs.setString(_deviceIdKey, devId);
      } else if (devId == null || devId.isEmpty) {
        // No fingerprint available — generate random (legacy fallback)
        devId = DateTime.now().millisecondsSinceEpoch.toRadixString(36) +
            (hashCode ^ DateTime.now().microsecond).toRadixString(36);
        await _prefs.setString(_deviceIdKey, devId);
      }

      final body = <String, dynamic>{'device_id': devId};
      if (hwFp != null && hwFp.isNotEmpty) body['hw_fingerprint'] = hwFp;
      if (envFlags > 0) body['env_flags'] = envFlags;
      body['platform'] = Platform.operatingSystem;  // "android", "ios", "windows", "macos", "linux"

      final resp = await _postWithFallback(
        '/api/auth/device-register',
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );
      if (resp != null) {
        final data = jsonDecode(_body(resp));
        await _prefs.setString(_tokenKey, data['access_token']);
        return null;
      }
      return '网络连接失败，请检查网络';
    } catch (e) {
      return '网络错误: $e';
    }
  }

  static Future<String?> _getHwFingerprint() async {
    try {
      return await DeviceFingerprint.getHardwareFingerprint();
    } catch (_) {
      return null;
    }
  }

  static Future<int> _getEnvFlags() async {
    try {
      return await DeviceFingerprint.detectEnvironment();
    } catch (_) {
      return 0;
    }
  }

  /// Bind email to device account for cross-device sync.
  Future<String?> bindEmail(String email, String password) async {
    try {
      final resp = await http.post(
        Uri.parse('$baseUrl/api/auth/bind-email'),
        headers: _headers,
        body: jsonEncode({'email': email, 'password': password}),
      );
      if (resp.statusCode == 200) {
        await _prefs.setString(_emailKey, email);
        return null;
      }
      final err = jsonDecode(_body(resp));
      return err['detail'] ?? '绑定失败';
    } catch (e) {
      return '网络错误: $e';
    }
  }

  /// Apply invite code anytime (not just at registration).
  Future<String?> applyInvite(String inviteCode) async {
    try {
      final resp = await http.post(
        Uri.parse('$baseUrl/api/auth/apply-invite'),
        headers: _headers,
        body: jsonEncode({'invite_code': inviteCode}),
      );
      if (resp.statusCode == 200) {
        return null;
      }
      final err = jsonDecode(_body(resp));
      return err['detail'] ?? '邀请码无效';
    } catch (e) {
      return '网络错误: $e';
    }
  }

  Future<String?> register(String email, String password, {String? inviteCode}) async {
    try {
      final body = <String, dynamic>{'email': email, 'password': password};
      if (inviteCode != null && inviteCode.isNotEmpty) {
        body['invite_code'] = inviteCode;
      }
      final resp = await http.post(
        Uri.parse('$baseUrl/api/auth/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );
      if (resp.statusCode == 200) {
        final data = jsonDecode(_body(resp));
        await _saveAuth(data['access_token'], email);
        return null;
      }
      final err = jsonDecode(_body(resp));
      return err['detail'] ?? '注册失败';
    } catch (e) {
      return '网络错误: $e';
    }
  }

  Future<String?> login(String email, String password) async {
    try {
      final resp = await http.post(
        Uri.parse('$baseUrl/api/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': password}),
      );
      if (resp.statusCode == 200) {
        final data = jsonDecode(_body(resp));
        await _saveAuth(data['access_token'], email);
        return null;
      }
      final err = jsonDecode(_body(resp));
      return err['detail'] ?? '登录失败';
    } catch (e) {
      return '网络错误: $e';
    }
  }

  Future<Map<String, dynamic>?> getSubscription() async {
    try {
      final resp = await _getWithFallback('/api/user/subscription', headers: _headers);
      if (resp != null) {
        return jsonDecode(_body(resp));
      }
    } catch (_) {}
    return null;
  }

  Future<List<Map<String, dynamic>>> getPlans({bool forceRefresh = false}) async {
    // Return cache if fresh
    if (!forceRefresh &&
        _plansCache != null &&
        _plansCacheTime != null &&
        DateTime.now().difference(_plansCacheTime!) < _plansCacheTTL) {
      return _plansCache!;
    }
    try {
      final resp = await _getWithFallback('/api/plans/', headers: _headers);
      if (resp != null) {
        final data = List<Map<String, dynamic>>.from(jsonDecode(_body(resp)));
        if (data.isNotEmpty) { _plansCache = data; _plansCacheTime = DateTime.now(); }
        return data;
      }
    } catch (_) {}
    // Return stale cache on error if available
    if (_plansCache != null) return _plansCache!;
    return [];
  }

  /// Get showcase node list (works without VPN connection).
  /// Uses multi-domain fallback to survive GFW blocking.
  Future<List<Map<String, dynamic>>> getShowcaseNodes({bool forceRefresh = false}) async {
    if (!forceRefresh && _nodesCache != null && _nodesCacheTime != null &&
        DateTime.now().difference(_nodesCacheTime!) < _nodesCacheTTL) {
      return _nodesCache!;
    }
    try {
      final resp = await _getWithFallback('/api/nodes/showcase', headers: _headers);
      if (resp != null) {
        final data = List<Map<String, dynamic>>.from(jsonDecode(_body(resp)));
        if (data.isNotEmpty) { _nodesCache = data; _nodesCacheTime = DateTime.now(); }
        return data;
      }
    } catch (_) {}
    if (_nodesCache != null) return _nodesCache!;
    return [];
  }

  Future<Map<String, dynamic>?> createOrder(int planId) async {
    try {
      final resp = await http.post(
        Uri.parse('$baseUrl/api/orders/'),
        headers: _headers,
        body: jsonEncode({'plan_id': planId}),
      );
      if (resp.statusCode == 200) {
        return jsonDecode(_body(resp));
      }
      // Return error detail from server
      try {
        final err = jsonDecode(_body(resp));
        return {'error': true, 'detail': err['detail'] ?? 'HTTP ${resp.statusCode}'};
      } catch (_) {
        return {'error': true, 'detail': 'HTTP ${resp.statusCode}'};
      }
    } catch (e) {
      return {'error': true, 'detail': e.toString()};
    }
  }

  /// Create CNY order (alipay/wechat) via JLB gateway.
  Future<Map<String, dynamic>?> createCNYOrder(int planId, String channel) async {
    try {
      final resp = await http.post(
        Uri.parse('$baseUrl/api/pay/create'),
        headers: _headers,
        body: jsonEncode({'plan_id': planId, 'channel': channel}),
      );
      if (resp.statusCode == 200) {
        return jsonDecode(_body(resp));
      }
      // Return error detail from server
      try {
        final err = jsonDecode(_body(resp));
        return {'error': true, 'detail': err['detail'] ?? 'HTTP ${resp.statusCode}'};
      } catch (_) {
        return {'error': true, 'detail': 'HTTP ${resp.statusCode}'};
      }
    } catch (e) {
      return {'error': true, 'detail': e.toString()};
    }
  }

  Future<Map<String, dynamic>?> getPayInfo(String orderNo) async {
    try {
      final resp = await http.get(
        Uri.parse('$baseUrl/api/orders/pay-info/$orderNo'),
        headers: _headers,
      );
      if (resp.statusCode == 200) {
        return jsonDecode(_body(resp));
      }
    } catch (_) {}
    return null;
  }

  Future<String?> checkOrderStatus(String orderNo) async {
    try {
      final resp = await http.get(
        Uri.parse('$baseUrl/api/orders/status/$orderNo'),
        headers: _headers,
      );
      if (resp.statusCode == 200) {
        final data = jsonDecode(_body(resp));
        return data['status'];
      }
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>?> getUserInfo() async {
    try {
      final resp = await _getWithFallback('/api/user/me', headers: _headers);
      if (resp != null) {
        final data = jsonDecode(_body(resp)) as Map<String, dynamic>;
        // Cache key fields locally for offline access
        final tier = data['tier'] as String?;
        if (tier != null) _prefs.setString(_cachedTierKey, tier);
        final ed = data['expire_date'];
        if (ed != null) _prefs.setString(_cachedExpireDateKey, ed.toString());
        return data;
      }
    } catch (_) {}
    // Offline fallback: return cached data
    final ct = _prefs.getString(_cachedTierKey);
    if (ct != null) {
      return {
        'tier': ct,
        'expire_date': _prefs.getString(_cachedExpireDateKey),
      };
    }
    return null;
  }

  Future<Map<String, dynamic>?> getInviteInfo() async {
    try {
      final resp = await http.get(
        Uri.parse('$baseUrl/api/user/invite'),
        headers: _headers,
      );
      if (resp.statusCode == 200) {
        return jsonDecode(_body(resp));
      }
    } catch (_) {}
    return null;
  }

  /// Check trial status from backend. Caches result for offline use.
  Future<Map<String, dynamic>?> getTrialStatus() async {
    try {
      final resp = await _getWithFallback('/api/user/trial-status', headers: _headers);
      if (resp != null) {
        final data = jsonDecode(_body(resp)) as Map<String, dynamic>;
        // Cache status for offline
        final status = data['status'] as String?;
        if (status != null) _prefs.setString(_cachedStatusKey, status);
        return data;
      }
    } catch (_) {}
    // Offline fallback
    final cs = _prefs.getString(_cachedStatusKey);
    if (cs != null) return {'status': cs};
    return null;
  }

  /// Send heartbeat while VPN connected — deducts 10s from trial.
  /// Returns updated remaining_sec or null on error.
  Future<Map<String, dynamic>?> trialHeartbeat() async {
    try {
      final resp = await _postWithFallback(
        '/api/user/trial-heartbeat',
        headers: _headers,
      );
      if (resp != null) {
        return jsonDecode(_body(resp));
      }
    } catch (_) {}
    return null;
  }

  /// Check for app updates. Returns version info or null.
  Future<Map<String, dynamic>?> checkAppUpdate() async {
    try {
      final resp = await _getWithFallback('/api/app/version');
      if (resp != null) {
        return jsonDecode(_body(resp));
      }
    } catch (_) {}
    return null;
  }

  /// Refresh JWT token before it expires. Call periodically (e.g. every 12h).
  /// Returns true if token was refreshed successfully.
  Future<bool> refreshToken() async {
    if (!isLoggedIn) return false;
    try {
      final resp = await _postWithFallback(
        '/api/auth/refresh-token',
        headers: _headers,
      );
      if (resp != null) {
        final data = jsonDecode(_body(resp));
        final newToken = data['access_token'] as String?;
        if (newToken != null && newToken.isNotEmpty) {
          await _prefs.setString(_tokenKey, newToken);
          return true;
        }
      }
    } catch (_) {}
    return false;
  }

  Future<String?> changePassword(String oldPassword, String newPassword) async {
    try {
      final resp = await http.post(
        Uri.parse('$baseUrl/api/user/change-password'),
        headers: _headers,
        body: jsonEncode({'old_password': oldPassword, 'new_password': newPassword}),
      );
      if (resp.statusCode == 200) {
        return null;
      }
      final err = jsonDecode(_body(resp));
      return err['detail'] ?? '修改失败';
    } catch (e) {
      return '网络错误: $e';
    }
  }

  /// Report node health to backend for GFW detection.
  /// Called when VPN connection succeeds or fails on a specific node.
  Future<void> reportNodeHealth({
    required String nodeHost,
    int port = 443,
    required bool success,
    int latencyMs = -1,
  }) async {
    try {
      await http.post(
        Uri.parse('$baseUrl/api/user/report-node-health'),
        headers: _headers,
        body: jsonEncode({
          'node_host': nodeHost,
          'port': port,
          'success': success,
          'latency_ms': latencyMs,
        }),
      );
    } catch (_) {
      // Fire-and-forget, don't block on failure
    }
  }

  /// Quick connectivity check — tries HEAD on all fallback domains.
  /// Returns true if at least one domain responds within timeout.
  static Future<bool> isApiReachable({Duration timeout = const Duration(seconds: 6)}) async {
    for (final base in _fallbackUrls) {
      try {
        final resp = await http.head(Uri.parse('$base/api/plans/')).timeout(timeout);
        if (resp.statusCode < 500) return true;
      } catch (_) {}
    }
    return false;
  }

  /// Fetch server-driven invite text strings (cached 30min).
  /// Returns a Map<String, String> of invite-related i18n keys, or null on error.
  Future<Map<String, String>?> getInviteText(String lang, {bool forceRefresh = false}) async {
    if (!forceRefresh &&
        _inviteTextCache != null &&
        _inviteTextCacheTime != null &&
        DateTime.now().difference(_inviteTextCacheTime!) < _inviteTextCacheTTL) {
      return _inviteTextCache!;
    }
    try {
      final resp = await http.get(
        Uri.parse('$baseUrl/api/user/config/invite-text?lang=$lang'),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
      if (resp.statusCode == 200) {
        final data = jsonDecode(_body(resp));
        final texts = Map<String, String>.from(data['texts'] ?? {});
        if (texts.isNotEmpty) {
          _inviteTextCache = texts;
          _inviteTextCacheTime = DateTime.now();
        }
        return texts;
      }
    } catch (_) {}
    // Return stale cache on error
    if (_inviteTextCache != null) return _inviteTextCache!;
    return null;
  }
}
