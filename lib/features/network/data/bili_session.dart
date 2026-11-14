// -------------------------------------------------------------------------
// 功能：B 站账号会话（登录、资料、Cookie）
//
// 主要内容：
// - 网页登录：从内嵌的 B 站官方登录页取回 Cookie 建立会话
// - 账号资料：/x/web-interface/nav
// - 凭证存取：Android EncryptedSharedPreferences（flutter_secure_storage）
// -------------------------------------------------------------------------

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

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
  static const String _kBuvid3 = 'bili_buvid3';

  String? _cookie;

  /// 设备指纹，弹幕鉴权必填；未登录也可以有。
  String? _buvid3;

  /// 登录用户 UID（DedeUserID），匿名时为 0。
  int _userId = 0;

  /// 可附加到平台请求的 Cookie 头。已登录时包含 SESSDATA / bili_jct /
  /// DedeUserID，任何情况下都会补上 buvid3。
  String? get cookieHeader {
    final List<String> parts = <String>[];
    final String? login = _cookie;
    if (login != null && login.isNotEmpty) parts.add(login);
    final String? buvid = _buvid3;
    if (buvid != null && buvid.isNotEmpty) parts.add('buvid3=$buvid');
    return parts.isEmpty ? null : parts.join('; ');
  }

  /// 当前设备指纹（可能为空，调用 [ensureBuvid] 保证取到）。
  String? get buvid3 => _buvid3;

  /// 登录用户 UID，匿名为 0。
  int get userId => _userId;

  bool get isLoggedIn => _cookie != null && _cookie!.isNotEmpty;

  // ------------------------------------------------------------------ 读取

  /// 恢复上次登录：有 Cookie 就请求一次 nav 确认是否仍有效。
  Future<BiliAccount?> restore() async {
    final String? sess = await _storage.read(key: _kSessData);
    final String? uid = await _storage.read(key: _kUid);
    final String? csrf = await _storage.read(key: _kCsrf);
    final String? buvid = await _storage.read(key: _kBuvid3);
    _buvid3 = (buvid == null || buvid.isEmpty) ? null : buvid;
    if (sess == null || sess.isEmpty) return null;

    _userId = int.tryParse(uid ?? '') ?? 0;
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

    _userId = int.tryParse(cookies['DedeUserID'] ?? '') ?? 0;
    _cookie = _buildCookie(
      sess: sess,
      uid: cookies['DedeUserID'],
      csrf: cookies['bili_jct'],
    );
    await _storage.write(key: _kSessData, value: sess);
    await _storage.write(key: _kUid, value: cookies['DedeUserID'] ?? '');
    await _storage.write(key: _kCsrf, value: cookies['bili_jct'] ?? '');

    // 登录页的 Cookie 里通常带 buvid3；没有就后台向 B 站要一个，
    // 不阻塞登录流程，弹幕连接前会再等它一次。
    final String? buvid = cookies['buvid3'];
    if (buvid != null && buvid.isNotEmpty) {
      _buvid3 = buvid;
      await _storage.write(key: _kBuvid3, value: buvid);
    } else {
      unawaited(ensureBuvid());
    }

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
    _userId = 0;
    // buvid3 是设备指纹，不属于账号，退出登录时保留，匿名弹幕仍需要它。
    await _storage.delete(key: _kSessData);
    await _storage.delete(key: _kUid);
    await _storage.delete(key: _kCsrf);
    await _storage.delete(key: _kProfile);
  }

  // ------------------------------------------------------------ 设备指纹

  /// 保证有可用的 buvid3：内存 → 安全存储 → 接口领取 → 本地随机兜底。
  ///
  /// 弹幕鉴权与 WBI 接口都要求带上它，缺失时请求容易被风控拒绝。
  Future<String> ensureBuvid() async {
    final String? memory = _buvid3;
    if (memory != null && memory.isNotEmpty) return memory;

    final String? stored = await _storage.read(key: _kBuvid3);
    if (stored != null && stored.isNotEmpty) {
      _buvid3 = stored;
      return stored;
    }

    final String value = await _fetchBuvid3() ?? _randomBuvid();
    _buvid3 = value;
    await _storage.write(key: _kBuvid3, value: value);
    return value;
  }

  /// 匿名设备指纹接口：/x/frontend/finger/spi 返回 b_3 / b_4。
  Future<String?> _fetchBuvid3() async {
    try {
      final HttpClientRequest request = await _client
          .getUrl(Uri.https('api.bilibili.com', '/x/frontend/finger/spi'))
          .timeout(const Duration(seconds: 8));
      request.headers.set(HttpHeaders.userAgentHeader, _userAgent);
      request.headers.set('Referer', 'https://www.bilibili.com/');
      request.headers.set('Accept', 'application/json, text/plain, */*');
      final HttpClientResponse response = await request.close().timeout(
        const Duration(seconds: 10),
      );
      final String text = await utf8.decoder
          .bind(response)
          .join()
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;
      final Object? decoded = jsonDecode(text);
      if (decoded is! Map) return null;
      final Object? data = decoded['data'];
      if (data is! Map) return null;
      final String value = '${data['b_3'] ?? ''}'.trim();
      return value.isEmpty ? null : value;
    } on Object {
      return null;
    }
  }

  static String _randomBuvid() {
    const String hex = '0123456789ABCDEF';
    final Random random = Random();
    final String body = List<String>.generate(
      32,
      (int _) => hex[random.nextInt(hex.length)],
    ).join();
    return '${body}infoc';
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
