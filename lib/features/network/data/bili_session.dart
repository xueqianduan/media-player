// -------------------------------------------------------------------------
// 功能：B 站账号会话（登录、资料、Cookie）
//
// 主要内容：
// - 网页登录：从内嵌的 B 站官方登录页取回 Cookie 建立会话
// - 账号资料：/x/web-interface/nav
// - 凭证存取：Android EncryptedSharedPreferences（flutter_secure_storage）
// -------------------------------------------------------------------------

import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// B 站账号摘要。
class BiliAccount {
  const BiliAccount({
    required this.mid,
    required this.name,
    required this.face,
    this.vip = false,
  });

  final int mid;
  final String name;
  final String face;
  final bool vip;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'mid': mid,
    'name': name,
    'face': face,
    'vip': vip,
  };

  static BiliAccount? fromJson(Object? value) {
    if (value is! Map) return null;
    final Map<String, dynamic> json = Map<String, dynamic>.from(value);
    final int mid = (json['mid'] as num?)?.toInt() ?? 0;
    if (mid <= 0) return null;
    return BiliAccount(
      mid: mid,
      name: '${json['name'] ?? 'B站用户'}',
      face: '${json['face'] ?? ''}',
      vip: json['vip'] == true,
    );
  }
}

class BiliSessionService {
  BiliSessionService({HttpClient? client})
    : _client =
          client ??
          (HttpClient()..connectionTimeout = const Duration(seconds: 8));

  final HttpClient _client;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  static const String _userAgent =
      'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';

  static const String _kSessData = 'bili_sessdata';
  static const String _kCsrf = 'bili_jct';
  static const String _kUid = 'bili_dedeuserid';
  static const String _kProfile = 'bili_profile';

  String? _cookie;

  /// 已登录时返回可附加到平台请求的 Cookie 头。
  String? get cookieHeader => _cookie;

  bool get isLoggedIn => _cookie != null && _cookie!.isNotEmpty;

  // ------------------------------------------------------------------ 读取

  /// 恢复上次登录：有 Cookie 就请求一次 nav 确认是否仍有效。
  Future<BiliAccount?> restore() async {
    final String? sess = await _storage.read(key: _kSessData);
    final String? uid = await _storage.read(key: _kUid);
    final String? csrf = await _storage.read(key: _kCsrf);
    if (sess == null || sess.isEmpty) return null;

    _cookie = _buildCookie(sess: sess, uid: uid, csrf: csrf);
    final BiliAccount? account = await fetchProfile();
    if (account != null) return account;

    // 网络失败时保留凭证，返回缓存资料，避免把网络问题当成退出登录。
    final String? cached = await _storage.read(key: _kProfile);
    if (cached == null) return null;
    try {
      return BiliAccount.fromJson(jsonDecode(cached));
    } on FormatException {
      return null;
    }
  }

  /// 请求账号资料，同时用于校验登录态。
  Future<BiliAccount?> fetchProfile() async {
    final String? cookie = _cookie;
    if (cookie == null) return null;

    final Map<String, dynamic>? data = await _get(
      'api.bilibili.com',
      '/x/web-interface/nav',
      const <String, String>{},
      cookie: cookie,
    );
    if (data == null) return null;
    if (data['isLogin'] != true) {
      await logout();
      return null;
    }

    final BiliAccount account = BiliAccount(
      mid: (data['mid'] as num?)?.toInt() ?? 0,
      name: '${data['uname'] ?? 'B站用户'}',
      face: '${data['face'] ?? ''}',
      vip: (data['vipStatus'] as num?)?.toInt() == 1,
    );
    await _storage.write(key: _kProfile, value: jsonEncode(account.toJson()));
    return account;
  }

  // ------------------------------------------------------------------ 登录

  /// 用内嵌官方登录页登录后的 Cookie 建立会话。
  ///
  /// [rawCookie] 是 WebView 的 Cookie 头（`SESSDATA=...; bili_jct=...; DedeUserID=...`）。
  /// SESSDATA 是 HttpOnly，只能由原生 CookieManager 读出，JavaScript 拿不到。
  ///
  /// 成功后返回账号资料；凭证已写入安全存储，但账号接口取不到资料时抛出异常，
  /// 由界面提示重试（不会丢弃已保存的凭证）。
  Future<BiliAccount> loginWithCookie(String rawCookie) async {
    final Map<String, String> cookies = _parseCookieHeader(rawCookie);
    final String sess = cookies['SESSDATA'] ?? '';
    if (sess.isEmpty) {
      throw const BiliSessionException('没有拿到登录凭证，请重新登录');
    }

    _cookie = _buildCookie(
      sess: sess,
      uid: cookies['DedeUserID'],
      csrf: cookies['bili_jct'],
    );
    await _storage.write(key: _kSessData, value: sess);
    await _storage.write(key: _kUid, value: cookies['DedeUserID'] ?? '');
    await _storage.write(key: _kCsrf, value: cookies['bili_jct'] ?? '');

    final Map<String, dynamic>? data = await _get(
      'api.bilibili.com',
      '/x/web-interface/nav',
      const <String, String>{},
      cookie: _cookie,
    );
    if (data == null) {
      // 网络问题：凭证保留，允许稍后自动重试。
      throw const BiliSessionException(
        '网络不稳定，账号信息获取失败，稍后会自动重试',
        retryable: true,
      );
    }
    if (data['isLogin'] != true) {
      // 这是 WebView 里残留的旧凭证，尚未真正登录成功：清掉，等用户完成登录。
      await logout();
      throw const BiliSessionException('登录尚未生效');
    }

    final BiliAccount account = BiliAccount(
      mid: (data['mid'] as num?)?.toInt() ?? 0,
      name: '${data['uname'] ?? 'B站用户'}',
      face: '${data['face'] ?? ''}',
      vip: (data['vipStatus'] as num?)?.toInt() == 1,
    );
    await _storage.write(key: _kProfile, value: jsonEncode(account.toJson()));
    return account;
  }

  Future<void> logout() async {
    _cookie = null;
    await _storage.delete(key: _kSessData);
    await _storage.delete(key: _kUid);
    await _storage.delete(key: _kCsrf);
    await _storage.delete(key: _kProfile);
  }

  // ------------------------------------------------------------------ 工具

  String _buildCookie({required String sess, String? uid, String? csrf}) {
    final List<String> parts = <String>['SESSDATA=$sess'];
    if (uid != null && uid.isNotEmpty) parts.add('DedeUserID=$uid');
    if (csrf != null && csrf.isNotEmpty) parts.add('bili_jct=$csrf');
    return parts.join('; ');
  }

  /// 解析 Cookie 头。同名 Cookie 只取第一个（.bilibili.com 域优先于子域）。
  Map<String, String> _parseCookieHeader(String raw) {
    final Map<String, String> result = <String, String>{};
    for (final String part in raw.split(';')) {
      final int index = part.indexOf('=');
      if (index <= 0) continue;
      final String name = part.substring(0, index).trim();
      if (name.isEmpty) continue;
      // SESSDATA 里的逗号是 URL 编码的，保持原样回传给平台接口。
      result.putIfAbsent(name, () => part.substring(index + 1).trim());
    }
    return result;
  }

  Future<Map<String, dynamic>?> _get(
    String host,
    String path,
    Map<String, String> query, {
    String referer = 'https://www.bilibili.com/',
    String? cookie,
  }) async {
    try {
      final HttpClientRequest request = await _client
          .getUrl(Uri.https(host, path, query.isEmpty ? null : query))
          .timeout(const Duration(seconds: 10));
      request.headers.set(HttpHeaders.userAgentHeader, _userAgent);
      request.headers.set('Referer', referer);
      request.headers.set('Accept', 'application/json, text/plain, */*');
      if (cookie != null && cookie.isNotEmpty) {
        request.headers.set(HttpHeaders.cookieHeader, cookie);
      }
      final HttpClientResponse response = await request.close().timeout(
        const Duration(seconds: 12),
      );
      final String text = await utf8.decoder
          .bind(response)
          .join()
          .timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) return null;
      final Object? decoded = jsonDecode(text);
      if (decoded is! Map) return null;
      final Map<String, dynamic> root = Map<String, dynamic>.from(decoded);
      if ((root['code'] as num?)?.toInt() != 0) return null;
      final Object? data = root['data'];
      return data is Map ? Map<String, dynamic>.from(data) : null;
    } on Object {
      return null;
    }
  }

  void close() => _client.close(force: true);
}

class BiliSessionException implements Exception {
  const BiliSessionException(this.message, {this.retryable = false});

  final String message;

  /// 是否属于「换个时间还能成功」的临时错误（例如网络抖动）。
  final bool retryable;

  @override
  String toString() => message;
}
