// -------------------------------------------------------------------------
// 功能：B 站 WBI 签名
//
// 主要内容：
// - 从 nav 接口取 wbi_img，按 mixinKeyEncTab 重排出 mixinKey
// - 给查询参数补 wts、按 key 排序、过滤特殊字符后计算 w_rid（MD5）
// - 纯 dart:io 实现，不依赖第三方包，也不依赖 Flutter
// -------------------------------------------------------------------------

import 'dart:convert';
import 'dart:io';

/// WBI 签名失败（取不到密钥或接口异常）。
class BiliWbiException implements Exception {
  const BiliWbiException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// WBI 签名器：密钥缓存 30 分钟，失败后下次重新获取。
class BiliWbi {
  BiliWbi({HttpClient? client})
    : _client =
          client ??
          (HttpClient()..connectionTimeout = const Duration(seconds: 8));

  final HttpClient _client;

  static const String _userAgent =
      'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';

  /// 官方的重排表，固定 64 项。
  static const List<int> _mixinKeyEncTab = <int>[
    46,
    47,
    18,
    2,
    53,
    8,
    23,
    32,
    15,
    50,
    10,
    31,
    58,
    3,
    45,
    35,
    27,
    43,
    5,
    49,
    33,
    9,
    42,
    19,
    29,
    28,
    14,
    39,
    12,
    38,
    41,
    13,
    37,
    48,
    7,
    16,
    24,
    55,
    40,
    61,
    26,
    17,
    0,
    1,
    60,
    51,
    30,
    4,
    22,
    25,
    54,
    21,
    56,
    59,
    6,
    63,
    57,
    62,
    11,
    36,
    20,
    34,
    44,
    52,
  ];

  static const Duration _ttl = Duration(minutes: 30);

  String? _mixinKey;
  DateTime? _fetchedAt;

  /// 给 [params] 补上 `wts` 与 `w_rid`，返回可直接拼进 URL 的查询参数。
  Future<Map<String, String>> sign(
    Map<String, String> params, {
    String? cookie,
  }) async {
    final String mixinKey = await _ensureMixinKey(cookie: cookie);
    final Map<String, String> query = <String, String>{...params};
    query['wts'] = '${DateTime.now().millisecondsSinceEpoch ~/ 1000}';

    final List<String> keys = query.keys.toList()..sort();
    final String joined = keys
        .map(
          (String key) =>
              '${Uri.encodeQueryComponent(key)}='
              '${Uri.encodeQueryComponent(_sanitize(query[key] ?? ''))}',
        )
        .join('&');

    query['w_rid'] = md5Hex('$joined$mixinKey');
    return query;
  }

  /// 强制丢弃缓存的密钥，下次签名重新拉取。
  void invalidate() {
    _mixinKey = null;
    _fetchedAt = null;
  }

  Future<String> _ensureMixinKey({String? cookie}) async {
    final String? cached = _mixinKey;
    final DateTime? fetchedAt = _fetchedAt;
    if (cached != null &&
        fetchedAt != null &&
        DateTime.now().difference(fetchedAt) < _ttl) {
      return cached;
    }

    final Map<String, dynamic> data = await _fetchNav(cookie: cookie);
    final Map<String, dynamic> wbi = _asMap(data['wbi_img']);
    final String imgKey = _keyFromUrl('${wbi['img_url'] ?? ''}');
    final String subKey = _keyFromUrl('${wbi['sub_url'] ?? ''}');
    if (imgKey.isEmpty || subKey.isEmpty) {
      throw const BiliWbiException('B站签名密钥获取失败，请稍后重试');
    }

    final String raw = '$imgKey$subKey';
    final StringBuffer buffer = StringBuffer();
    for (final int index in _mixinKeyEncTab) {
      if (index < raw.length) buffer.write(raw[index]);
    }
    final String mixin = buffer.toString();
    if (mixin.length < 32) {
      throw const BiliWbiException('B站签名密钥不完整，请稍后重试');
    }

    _mixinKey = mixin.substring(0, 32);
    _fetchedAt = DateTime.now();
    return _mixinKey!;
  }

  /// nav 接口未登录时 code 为 -101，但 data.wbi_img 仍然有效，所以这里不用
  /// 通用的「code 必须为 0」逻辑。
  Future<Map<String, dynamic>> _fetchNav({String? cookie}) async {
    late final HttpClientRequest request;
    try {
      request = await _client
          .getUrl(Uri.https('api.bilibili.com', '/x/web-interface/nav'))
          .timeout(const Duration(seconds: 8));
    } on Object {
      throw const BiliWbiException('网络连接超时，无法获取B站签名');
    }

    request.headers.set(HttpHeaders.userAgentHeader, _userAgent);
    request.headers.set('Referer', 'https://www.bilibili.com/');
    request.headers.set('Accept', 'application/json, text/plain, */*');
    if (cookie != null && cookie.isNotEmpty) {
      request.headers.set(HttpHeaders.cookieHeader, cookie);
    }

    try {
      final HttpClientResponse response = await request.close().timeout(
        const Duration(seconds: 10),
      );
      final String text = await utf8.decoder
          .bind(response)
          .join()
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        throw BiliWbiException('B站签名接口异常（HTTP ${response.statusCode}）');
      }
      final Object? decoded = jsonDecode(text);
      if (decoded is! Map) {
        throw const BiliWbiException('B站签名接口返回内容异常');
      }
      return _asMap(decoded['data']);
    } on BiliWbiException {
      rethrow;
    } on Object {
      throw const BiliWbiException('B站签名接口请求失败，请稍后重试');
    }
  }

  /// `https://i0.hdslb.com/bfs/wbi/7cd084941338484aae1ad9425b84077c.png`
  /// → `7cd084941338484aae1ad9425b84077c`
  static String _keyFromUrl(String url) {
    if (url.isEmpty) return '';
    final String name = url.split('/').last;
    final int dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }

  /// 官方要求：值里不能出现 `!'()*` 这些字符。
  static String _sanitize(String value) =>
      value.replaceAll(RegExp(r"[!'()*]"), '');

  static Map<String, dynamic> _asMap(Object? value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

  void close() => _client.close(force: true);

  // ------------------------------------------------------------------ MD5

  /// 标准 MD5（小写十六进制）。WBI 只要求 MD5，单独实现避免再加依赖。
  static String md5Hex(String input) => _Md5.hash(utf8.encode(input));
}

/// 精简版 MD5：只处理字节数组，输出小写 hex。
class _Md5 {
  const _Md5._();

  static const List<int> _k = <int>[
    0xd76aa478,
    0xe8c7b756,
    0x242070db,
    0xc1bdceee,
    0xf57c0faf,
    0x4787c62a,
    0xa8304613,
    0xfd469501,
    0x698098d8,
    0x8b44f7af,
    0xffff5bb1,
    0x895cd7be,
    0x6b901122,
    0xfd987193,
    0xa679438e,
    0x49b40821,
    0xf61e2562,
    0xc040b340,
    0x265e5a51,
    0xe9b6c7aa,
    0xd62f105d,
    0x02441453,
    0xd8a1e681,
    0xe7d3fbc8,
    0x21e1cde6,
    0xc33707d6,
    0xf4d50d87,
    0x455a14ed,
    0xa9e3e905,
    0xfcefa3f8,
    0x676f02d9,
    0x8d2a4c8a,
    0xfffa3942,
    0x8771f681,
    0x6d9d6122,
    0xfde5380c,
    0xa4beea44,
    0x4bdecfa9,
    0xf6bb4b60,
    0xbebfbc70,
    0x289b7ec6,
    0xeaa127fa,
    0xd4ef3085,
    0x04881d05,
    0xd9d4d039,
    0xe6db99e5,
    0x1fa27cf8,
    0xc4ac5665,
    0xf4292244,
    0x432aff97,
    0xab9423a7,
    0xfc93a039,
    0x655b59c3,
    0x8f0ccc92,
    0xffeff47d,
    0x85845dd1,
    0x6fa87e4f,
    0xfe2ce6e0,
    0xa3014314,
    0x4e0811a1,
    0xf7537e82,
    0xbd3af235,
    0x2ad7d2bb,
    0xeb86d391,
  ];

  static const List<int> _s = <int>[
    7,
    12,
    17,
    22,
    7,
    12,
    17,
    22,
    7,
    12,
    17,
    22,
    7,
    12,
    17,
    22,
    5,
    9,
    14,
    20,
    5,
    9,
    14,
    20,
    5,
    9,
    14,
    20,
    5,
    9,
    14,
    20,
    4,
    11,
    16,
    23,
    4,
    11,
    16,
    23,
    4,
    11,
    16,
    23,
    4,
    11,
    16,
    23,
    6,
    10,
    15,
    21,
    6,
    10,
    15,
    21,
    6,
    10,
    15,
    21,
    6,
    10,
    15,
    21,
  ];

  static const int _mask = 0xFFFFFFFF;

  static String hash(List<int> message) {
    final int bitLength = message.length * 8;
    final List<int> bytes = List<int>.from(message)..add(0x80);
    while (bytes.length % 64 != 56) {
      bytes.add(0);
    }
    for (int i = 0; i < 8; i++) {
      bytes.add((bitLength >> (8 * i)) & 0xFF);
    }

    int a0 = 0x67452301;
    int b0 = 0xEFCDAB89;
    int c0 = 0x98BADCFE;
    int d0 = 0x10325476;

    final List<int> words = List<int>.filled(16, 0);
    for (int offset = 0; offset < bytes.length; offset += 64) {
      for (int i = 0; i < 16; i++) {
        final int base = offset + i * 4;
        words[i] =
            bytes[base] |
            (bytes[base + 1] << 8) |
            (bytes[base + 2] << 16) |
            (bytes[base + 3] << 24);
      }

      int a = a0;
      int b = b0;
      int c = c0;
      int d = d0;

      for (int i = 0; i < 64; i++) {
        int f;
        int g;
        if (i < 16) {
          f = (b & c) | ((~b & _mask) & d);
          g = i;
        } else if (i < 32) {
          f = (d & b) | ((~d & _mask) & c);
          g = (5 * i + 1) % 16;
        } else if (i < 48) {
          f = b ^ c ^ d;
          g = (3 * i + 5) % 16;
        } else {
          f = c ^ (b | (~d & _mask));
          g = (7 * i) % 16;
        }
        f = (f + a + _k[i] + words[g]) & _mask;
        a = d;
        d = c;
        c = b;
        b = (b + _rotateLeft(f, _s[i])) & _mask;
      }

      a0 = (a0 + a) & _mask;
      b0 = (b0 + b) & _mask;
      c0 = (c0 + c) & _mask;
      d0 = (d0 + d) & _mask;
    }

    final List<int> digest = <int>[];
    for (final int word in <int>[a0, b0, c0, d0]) {
      for (int i = 0; i < 4; i++) {
        digest.add((word >> (8 * i)) & 0xFF);
      }
    }
    return digest
        .map((int byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  static int _rotateLeft(int value, int count) =>
      ((value << count) | (value >> (32 - count))) & _mask;
}
