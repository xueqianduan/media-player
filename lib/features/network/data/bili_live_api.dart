// -------------------------------------------------------------------------
// 功能：B 站直播接口封装
//
// 主要内容：
// - 搜索直播间/主播（含 412 重试）
// - 开播状态与房间详情
// - 取流地址解析（getRoomPlayInfo）
// - 统一的中文错误映射
// -------------------------------------------------------------------------

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../domain/live_models.dart';

/// 网络请求或接口返回错误（带可读中文提示）。
class LiveApiException implements Exception {
  const LiveApiException(this.message, {this.status});

  final String message;
  final int? status;

  @override
  String toString() => message;
}

/// 直播间当前未开播。
class LiveOfflineException implements Exception {
  const LiveOfflineException(this.roomId);

  final int roomId;

  @override
  String toString() => '直播间暂时未开播';
}

/// B 站直播接口：搜索直播间 / 主播、校验开播状态、获取播放地址。
///
/// 只使用 Dart 自带的 [HttpClient]，不引入额外依赖。播放地址不缓存，
/// 每次开播前重新解析。
class BiliLiveApi {
  BiliLiveApi({HttpClient? client})
    : _client =
          client ??
          (HttpClient()..connectionTimeout = const Duration(seconds: 8));

  final HttpClient _client;

  static const String _userAgent =
      'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';

  static const String _searchReferer = 'https://search.bilibili.com/';
  static const String _liveReferer = 'https://live.bilibili.com/';

  // ---------------------------------------------------------------- 基础请求

  Future<Map<String, dynamic>> _get(
    String host,
    String path,
    Map<String, String> query, {
    String referer = _liveReferer,
    String? cookie,
  }) async {
    late final HttpClientRequest request;
    try {
      request = await _client
          .getUrl(Uri.https(host, path, query))
          .timeout(const Duration(seconds: 10));
    } on TimeoutException {
      throw const LiveApiException('网络连接超时，请检查网络后重试');
    } on SocketException {
      throw const LiveApiException('无法连接网络，请检查网络设置');
    }

    request.headers.set(HttpHeaders.userAgentHeader, _userAgent);
    request.headers.set('Referer', referer);
    request.headers.set('Accept', 'application/json, text/plain, */*');
    if (cookie != null && cookie.isNotEmpty) {
      request.headers.set(HttpHeaders.cookieHeader, cookie);
    }

    final HttpClientResponse response;
    final String text;
    try {
      response = await request.close().timeout(const Duration(seconds: 12));
      text = await utf8.decoder
          .bind(response)
          .join()
          .timeout(const Duration(seconds: 12));
    } on TimeoutException {
      request.abort();
      throw const LiveApiException('接口响应超时，请稍后重试');
    } on SocketException {
      request.abort();
      throw const LiveApiException('网络中断，请稍后重试');
    }

    if (response.statusCode == 412 || response.statusCode == 429) {
      throw LiveApiException(
        response.statusCode == 412
            ? 'B站暂时限制了请求（412），请稍后重试'
            : '请求过于频繁（429），请稍后重试',
        status: response.statusCode,
      );
    }
    if (response.statusCode != 200) {
      throw LiveApiException(
        '接口返回异常（HTTP ${response.statusCode}）',
        status: response.statusCode,
      );
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      throw const LiveApiException('接口返回内容无法解析，请稍后重试');
    }
    final Map<String, dynamic> root = _jsonMap(decoded);
    final int code = _jsonInt(root['code']);
    if (code != 0) {
      throw LiveApiException(
        code == -412 || code == -352
            ? 'B站拒绝了本次请求（$code），请稍后重试'
            : 'B站接口错误：$code ${root['message'] ?? ''}'.trim(),
        status: code,
      );
    }
    return _jsonMap(root['data']);
  }

  // -------------------------------------------------------------------- 搜索

  /// 搜索直播间与主播，保留未开播的主播结果（用于「声音来源」）。
  Future<List<LiveRoom>> search(String keyword, {int page = 1}) async {
    final String query = keyword.trim();
    if (query.isEmpty) return const <LiveRoom>[];

    Map<String, dynamic> data;
    try {
      data = await _searchPage(query, page);
    } on LiveApiException catch (error) {
      // 缺少 cookie 时搜索接口容易返回 412，用随机 buvid3 重试一次。
      final int? status = error.status;
      if (status == 412 || status == 429 || status == -412 || status == -352) {
        data = await _searchPage(
          query,
          page,
          cookie: 'buvid3=${_randomBuvid()}infoc',
        );
      } else {
        rethrow;
      }
    }

    final Map<String, dynamic> result = _jsonMap(data['result']);
    final Map<int, LiveRoom> rooms = <int, LiveRoom>{};

    for (final Map<String, dynamic> row in <Map<String, dynamic>>[
      ..._jsonRows(result['live_room']).map(
        (Map<String, dynamic> item) => <String, dynamic>{...item, '_up': false},
      ),
      ..._jsonRows(result['live_user']).map(
        (Map<String, dynamic> item) => <String, dynamic>{...item, '_up': true},
      ),
    ]) {
      final int roomId = _jsonInt(row['roomid']);
      if (roomId <= 0) continue;
      final bool isUp = row['_up'] == true;
      final String cover = _plainText(
        row['cover'] ?? row['user_cover'] ?? row['keyframe'],
      );
      final String avatar = _plainText(row['uface'] ?? row['face']);
      rooms.putIfAbsent(
        roomId,
        () => LiveRoom(
          roomId: roomId,
          uid: _jsonInt(row['uid']),
          name: _plainText(row['uname']).isEmpty
              ? '未知主播'
              : _plainText(row['uname']),
          title: _plainText(row['title']),
          live: _jsonInt(row['live_status']) == 1,
          coverUrl: cover,
          avatarUrl: avatar,
          isUp: isUp,
        ),
      );
    }

    return rooms.values.toList();
  }

  Future<Map<String, dynamic>> _searchPage(
    String keyword,
    int page, {
    String? cookie,
  }) {
    return _get(
      'api.bilibili.com',
      '/x/web-interface/search/type',
      <String, String>{
        'search_type': 'live',
        'keyword': keyword,
        'page': '$page',
      },
      referer: _searchReferer,
      cookie: cookie,
    );
  }

  // ------------------------------------------------------------ 状态与取流

  /// 校验直播间当前是否开播（用于收藏列表的状态刷新）。
  Future<bool> isLive(int inputRoomId) async {
    final Map<String, dynamic> room = await _get(
      'api.live.bilibili.com',
      '/room/v1/Room/room_init',
      <String, String>{'id': '$inputRoomId'},
    );
    return _jsonInt(room['live_status']) == 1;
  }

  /// 按房间号获取直播间详情（名称、标题、封面、开播状态）。
  ///
  /// 用 getRoomBaseInfo 而不是 getInfoByRoom：后者在未登录时会返回 -352。
  Future<LiveRoom> roomDetail(int inputRoomId) async {
    final Map<String, dynamic> data = await _get(
      'api.live.bilibili.com',
      '/xlive/web-room/v1/index/getRoomBaseInfo',
      <String, String>{
        'req_biz': 'web_room_componet',
        'room_ids': '$inputRoomId',
      },
    );

    final Map<String, dynamic> byRoom = _jsonMap(data['by_room_ids']);
    final Map<String, dynamic> row = byRoom.length == 1
        ? _jsonMap(byRoom.values.first)
        : _jsonMap(byRoom['$inputRoomId']);

    final int roomId = _jsonInt(row['room_id']);
    if (roomId <= 0) {
      throw const LiveApiException('找不到这个直播间，请检查房间号');
    }

    // getRoomBaseInfo 不带主播头像，单独取一次房间资料（失败不影响主体信息）。
    Map<String, dynamic> info = <String, dynamic>{};
    try {
      info = await _get(
        'api.live.bilibili.com',
        '/room/v1/Room/get_info',
        <String, String>{'room_id': '$roomId'},
      );
    } on Object {
      info = <String, dynamic>{};
    }

    final String name = _plainText(row['uname']);
    return LiveRoom(
      roomId: roomId,
      uid: _jsonInt(row['uid']),
      name: name.isEmpty ? '直播间 $roomId' : name,
      title: _plainText(info['title'] ?? row['title']),
      live: _jsonInt(row['live_status']) == 1,
      coverUrl: _plainText(row['cover'] ?? row['keyframe']),
      avatarUrl: _plainText(info['face']),
    );
  }

  /// 解析房间号并返回本次可用的播放地址（FLV 优先，HLS 兜底）。
  ///
  /// [qn] 是期望画质（10000 原画 / 400 蓝光 / 250 超清 / 150 高清 / 80 流畅），
  /// [cookie] 传入登录态可尝试获取更高档位；实际结果看 [LivePlaylist.currentQn]。
  Future<LivePlaylist> resolve(
    int inputRoomId, {
    int qn = 10000,
    String? cookie,
  }) async {
    final Map<String, dynamic> room = await _get(
      'api.live.bilibili.com',
      '/room/v1/Room/room_init',
      <String, String>{'id': '$inputRoomId'},
    );

    final int roomId = _jsonInt(room['room_id']);
    if (roomId <= 0) {
      throw const LiveApiException('直播间不存在或已关闭');
    }
    if (room['is_locked'] == true || room['encrypted'] == true) {
      throw const LiveApiException('该直播间当前不能直接播放');
    }
    if (_jsonInt(room['live_status']) != 1) {
      throw LiveOfflineException(roomId);
    }

    final Map<String, dynamic> data = await _get(
      'api.live.bilibili.com',
      '/xlive/web-room/v2/index/getRoomPlayInfo',
      <String, String>{
        'room_id': '$roomId',
        'protocol': '0,1',
        // 0=flv、1=ts(HLS)、2=fmp4(HLS)，多要一种就多一组备用线路。
        'format': '0,1,2',
        'codec': '0',
        'qn': '$qn',
        'platform': 'web',
        'ptype': '8',
      },
      cookie: cookie,
    );

    if (_jsonInt(data['live_status']) != 1) {
      throw LiveOfflineException(roomId);
    }

    final Map<String, dynamic> playurl = _jsonMap(
      _jsonMap(data['playurl_info'])['playurl'],
    );

    final List<LiveStream> flv = <LiveStream>[];
    final List<LiveStream> hls = <LiveStream>[];

    final Map<int, LiveQuality> qualityByQn = <int, LiveQuality>{};
    for (final Map<String, dynamic> row in _jsonRows(playurl['g_qn_desc'])) {
      final int value = _jsonInt(row['qn']);
      if (value <= 0) continue;
      final String desc = _plainText(row['desc']);
      qualityByQn[value] = LiveQuality(
        qn: value,
        label: desc.isEmpty ? LiveQuality.labelOf(value) : desc,
      );
    }
    final Set<int> acceptQn = <int>{};
    int currentQn = 0;

    for (final Map<String, dynamic> stream in _jsonRows(playurl['stream'])) {
      for (final Map<String, dynamic> format in _jsonRows(stream['format'])) {
        final String formatName = '${format['format_name']}';
        // fmp4 同样是 HLS（m3u8），mpv 可以直接播。
        if (formatName != 'flv' && formatName != 'ts' && formatName != 'fmp4') {
          continue;
        }

        for (final Map<String, dynamic> codec in _jsonRows(format['codec'])) {
          if (codec['codec_name'] != 'avc') continue;

          final int codecQn = _jsonInt(codec['current_qn']);
          if (currentQn == 0 && codecQn > 0) currentQn = codecQn;
          for (final Object? value
              in codec['accept_qn'] as List<Object?>? ?? const <Object?>[]) {
            final int parsed = _jsonInt(value);
            if (parsed > 0) acceptQn.add(parsed);
          }

          for (final Map<String, dynamic> node in _jsonRows(
            codec['url_info'],
          )) {
            final String url =
                '${node['host']}${codec['base_url']}${node['extra'] ?? ''}';
            if (Uri.tryParse(url)?.scheme != 'https') continue;

            final LiveStream candidate = LiveStream(
              url: url,
              format: formatName,
              quality: _jsonInt(codec['current_qn']),
              headers: <String, String>{
                'User-Agent': _userAgent,
                'Referer': 'https://live.bilibili.com/$roomId',
              },
            );
            if (formatName == 'flv') {
              flv.add(candidate);
            } else {
              hls.add(candidate);
            }
          }
        }
      }
    }

    final List<LiveStream> candidates = <LiveStream>[...flv, ...hls];
    if (candidates.isEmpty) {
      throw const LiveApiException('当前没有返回可播放的直播地址，请稍后重试');
    }

    if (acceptQn.isNotEmpty) {
      qualityByQn.removeWhere(
        (int key, LiveQuality value) => !acceptQn.contains(key),
      );
      for (final int value in acceptQn) {
        qualityByQn.putIfAbsent(
          value,
          () => LiveQuality(qn: value, label: LiveQuality.labelOf(value)),
        );
      }
    }
    final List<LiveQuality> qualities = qualityByQn.values.toList()
      ..sort((LiveQuality a, LiveQuality b) => b.qn.compareTo(a.qn));

    return LivePlaylist(
      streams: candidates,
      qualities: qualities,
      currentQn: currentQn > 0 ? currentQn : qn,
    );
  }

  /// 发送弹幕。需要登录态（SESSDATA）与 CSRF Token（bili_jct）。
  ///
  /// 成功返回可忽略的提示（通常为空）；失败抛出带中文提示的
  /// [LiveApiException]。调用方需先确保 [cookie] 与 [csrf] 非空。
  Future<String?> sendDanmaku({
    required int roomId,
    required String text,
    required String cookie,
    required String csrf,
  }) async {
    final String message = text.trim();
    if (message.isEmpty) {
      throw const LiveApiException('弹幕内容不能为空');
    }
    if (message.runes.length > 20) {
      throw const LiveApiException('弹幕最多 20 个字');
    }
    if (cookie.isEmpty || csrf.isEmpty) {
      throw const LiveApiException('登录信息缺失，请重新登录 B 站账号');
    }

    final Map<String, String> form = <String, String>{
      'bubble': '0',
      'color': '16777215',
      'fontsize': '25',
      'mode': '1',
      'msg': message,
      'rnd': '${DateTime.now().millisecondsSinceEpoch ~/ 1000}',
      'roomid': '$roomId',
      'csrf': csrf,
      'csrf_token': csrf,
    };

    final HttpClientRequest request;
    try {
      request = await _client
          .postUrl(Uri.https('api.live.bilibili.com', '/msg/send'))
          .timeout(const Duration(seconds: 10));
    } on TimeoutException {
      throw const LiveApiException('发送请求超时，请检查网络后重试');
    } on SocketException {
      throw const LiveApiException('无法连接网络，弹幕未发送');
    }

    request.headers.set(HttpHeaders.userAgentHeader, _userAgent);
    request.headers.set('Referer', 'https://live.bilibili.com/$roomId');
    request.headers.set('Origin', 'https://live.bilibili.com');
    request.headers.set('Accept', 'application/json, text/plain, */*');
    request.headers.set(HttpHeaders.cookieHeader, cookie);
    request.headers.contentType = ContentType(
      'application',
      'x-www-form-urlencoded',
      charset: 'utf-8',
    );
    request.write(Uri(queryParameters: form).query);

    final HttpClientResponse response;
    final String body;
    try {
      response = await request.close().timeout(const Duration(seconds: 12));
      body = await utf8.decoder
          .bind(response)
          .join()
          .timeout(const Duration(seconds: 12));
    } on TimeoutException {
      request.abort();
      throw const LiveApiException('发送结果未知，请回到直播间确认是否已发出');
    } on SocketException {
      request.abort();
      throw const LiveApiException('发送过程中网络中断，弹幕可能未发出');
    }

    if (response.statusCode != 200) {
      throw LiveApiException(
        '弹幕发送失败（HTTP ${response.statusCode}）',
        status: response.statusCode,
      );
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      throw const LiveApiException('发送结果无法解析，请回到直播间确认');
    }
    final Map<String, dynamic> root = _jsonMap(decoded);
    final int code = _jsonInt(root['code']);
    final String apiMessage = _plainText(root['message'] ?? root['msg']);
    if (code != 0) {
      throw LiveApiException(_sendError(code, apiMessage), status: code);
    }

    // code 0 时个别情况仍会带一句提示（例如「发送成功」），只在有实际信息时返回。
    if (apiMessage.isEmpty || apiMessage == '0' || apiMessage.contains('成功')) {
      return null;
    }
    return apiMessage;
  }

  static String _sendError(int code, String message) {
    switch (code) {
      case -101:
        return '登录已失效，请重新登录 B 站账号';
      case -111:
        return '登录凭证校验失败，请重新登录';
      case -400:
        // 未登录 / CSRF 失效时 B 站也返回 -400「请求错误」，先提示检查登录。
        return message.isEmpty || message == '请求错误'
            ? '发送请求被拒绝，请确认 B 站登录状态后重试'
            : '弹幕内容不合法：$message';
      case -403:
        return '当前账号没有发送权限（可能被禁言或未实名）';
      case -352:
        return 'B站风控拦截了本次发送，请稍后重试';
      case 10031:
      case 1003212:
        return '发送太快了，请稍后再试';
      default:
        return message.isEmpty ? '弹幕发送失败（$code）' : '弹幕发送失败（$code）：$message';
    }
  }

  /// 从用户输入中解析房间号：支持纯数字、live.bilibili.com/12345 等。
  static int? parseRoomInput(String input) {
    final String text = input.trim();
    if (text.isEmpty) return null;
    if (RegExp(r'^\d{1,12}$').hasMatch(text)) return int.tryParse(text);

    final RegExpMatch? match = RegExp(
      r'(?:live\.bilibili\.com/|roomid=)(\d{1,12})',
      caseSensitive: false,
    ).firstMatch(text);
    if (match != null) return int.tryParse(match.group(1)!);
    return null;
  }

  void close() => _client.close(force: true);

  // ------------------------------------------------------------------ 工具

  static String _randomBuvid() {
    const String hex = '0123456789ABCDEF';
    final Random random = Random();
    return List<String>.generate(
      32,
      (int _) => hex[random.nextInt(hex.length)],
    ).join();
  }

  static Map<String, dynamic> _jsonMap(Object? value) {
    return value is Map
        ? Map<String, dynamic>.from(value)
        : <String, dynamic>{};
  }

  static List<Map<String, dynamic>> _jsonRows(Object? value) {
    if (value is! List) return <Map<String, dynamic>>[];
    return value
        .whereType<Map>()
        .map((Map<dynamic, dynamic> item) => Map<String, dynamic>.from(item))
        .toList();
  }

  static int _jsonInt(Object? value) {
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? 0;
  }

  /// 去掉搜索结果里的 `<em class="keyword">` 高亮标签与常见实体。
  static String _plainText(Object? value) {
    return '${value ?? ''}'
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .trim();
  }
}
