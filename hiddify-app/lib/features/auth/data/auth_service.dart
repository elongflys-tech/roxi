import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Service for communicating with our business backend API.
class AuthService {
  static const String baseUrl = 'https://roxi.cc';

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

  static const _tokenKey = 'roxi_token';
  static const _emailKey = 'roxi_email';
  static const _deviceIdKey = 'roxi_device_id';

  final SharedPreferences _prefs;

  AuthService(this._prefs);

  String? get token => _prefs.getString(_tokenKey);
  String? get email => _prefs.getString(_emailKey);
  String? get deviceId => _prefs.getString(_deviceIdKey);
  bool get isLoggedIn => token != null && token!.isNotEmpty;
  bool get hasEmail => email != null && email!.isNotEmpty;

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
  /// Generates a device_id on first launch, reuses it on subsequent launches.
  Future<String?> deviceRegister() async {
    try {
      String? devId = _prefs.getString(_deviceIdKey);
      if (devId == null || devId.isEmpty) {
        devId = DateTime.now().millisecondsSinceEpoch.toRadixString(36) +
            (hashCode ^ DateTime.now().microsecond).toRadixString(36);
        await _prefs.setString(_deviceIdKey, devId);
      }
      final resp = await http.post(
        Uri.parse('$baseUrl/api/auth/device-register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'device_id': devId}),
      );
      if (resp.statusCode == 200) {
        final data = jsonDecode(_body(resp));
        await _prefs.setString(_tokenKey, data['access_token']);
        return null;
      }
      final err = jsonDecode(_body(resp));
      return err['detail'] ?? '设备注册失败';
    } catch (e) {
      return '网络错误: $e';
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
      final resp = await http.get(
        Uri.parse('$baseUrl/api/user/subscription'),
        headers: _headers,
      );
      if (resp.statusCode == 200) {
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
      final resp = await http.get(
        Uri.parse('$baseUrl/api/plans/'),
        headers: _headers,
      );
      if (resp.statusCode == 200) {
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
  Future<List<Map<String, dynamic>>> getShowcaseNodes({bool forceRefresh = false}) async {
    if (!forceRefresh && _nodesCache != null && _nodesCacheTime != null &&
        DateTime.now().difference(_nodesCacheTime!) < _nodesCacheTTL) {
      return _nodesCache!;
    }
    try {
      final resp = await http.get(
        Uri.parse('$baseUrl/api/nodes/showcase'),
        headers: _headers,
      );
      if (resp.statusCode == 200) {
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
    } catch (_) {}
    return null;
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
    } catch (_) {}
    return null;
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
      final resp = await http.get(
        Uri.parse('$baseUrl/api/user/me'),
        headers: _headers,
      );
      if (resp.statusCode == 200) {
        return jsonDecode(_body(resp));
      }
    } catch (_) {}
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

  /// Check trial status from backend.
  Future<Map<String, dynamic>?> getTrialStatus() async {
    try {
      final resp = await http.get(
        Uri.parse('$baseUrl/api/user/trial-status'),
        headers: _headers,
      );
      if (resp.statusCode == 200) {
        return jsonDecode(_body(resp));
      }
    } catch (_) {}
    return null;
  }

  /// Send heartbeat while VPN connected — deducts 10s from trial.
  /// Returns updated remaining_sec or null on error.
  Future<Map<String, dynamic>?> trialHeartbeat() async {
    try {
      final resp = await http.post(
        Uri.parse('$baseUrl/api/user/trial-heartbeat'),
        headers: _headers,
      );
      if (resp.statusCode == 200) {
        return jsonDecode(_body(resp));
      }
    } catch (_) {}
    return null;
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
}
