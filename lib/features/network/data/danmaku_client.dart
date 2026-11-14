// -------------------------------------------------------------------------
// 功能：B 站直播弹幕 WebSocket 客户端
//
// 主要内容：
// - 取弹幕服务器：getDanmuInfo（WBI 签名）
// - 建连与鉴权：wss://{host}/sub，op=7
// - 心跳（op=2，25 秒）与 70 秒无消息超时
// - 解包：16 字节头 + protover=2 的 deflate 压缩 JSON
// - 解析 DANMU_MSG / SUPER_CHAT_MESSAGE
// - 断线指数退避重连，generation 防止旧连接串台
//
// 说明：只依赖 dart:io，页面通过回调接收消息，便于脱离 Flutter 单独调试。
// -------------------------------------------------------------------------

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../domain/danmaku_models.dart';
import 'bili_wbi.dart';

/// 弹幕连接异常（带用户可读提示）。
class DanmakuException implements Exception {
  const DanmakuException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 弹幕客户端：一个实例对应一个直播间，切换直播间请新建实例。
class DanmakuClient {
  DanmakuClient({
    required this.roomId,
    required this.onMessage,
    required this.onStatus,
    this.cookie,
    this.buvid = '',
    this.uid = 0,
    this.onLog,
    this.onError,
    HttpClient? client,
  }) : _client =
           client ??
           (HttpClient()..connectionTimeout = const Duration(seconds: 8)) {
    _wbi = BiliWbi(client: _client);
  }

  final int roomId;
  final void Function(DanmakuMessage message) onMessage;
  final void Function(DanmakuStatus status) onStatus;

  /// 登录态 Cookie（可空，匿名也能收弹幕）。
  final String? cookie;

  /// buvid3，弹幕鉴权必填；为空时仍会尝试连接，但容易被风控。
  final String buvid;

  /// 登录用户 UID，匿名为 0。
  final int uid;

  final void Function(String message)? onLog;

  /// 连接失败原因，供界面展示；恢复连接后不会再收到。
  final void Function(String message)? onError;

  final HttpClient _client;
  late final BiliWbi _wbi;

  static const String _userAgent =
      'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';

  WebSocket? _socket;
  StreamSubscription<dynamic>? _subscription;
  Timer? _heartbeat;
  Timer? _watchdog;
  Completer<void>? _pendingAuth;
  Completer<void>? _sessionDone;
  String? _token;

  /// 最近一次收到任意数据包的时间，用于 70 秒超时判断。
  DateTime _lastPacketAt = DateTime.now();

  int _generation = 0;
  bool _closed = false;
  bool _started = false;
  int _sequence = 0;
  int _messageSequence = 0;

  /// 启动连接。立即返回，后续状态通过 [onStatus] 推送。
  void start() {
    if (_started || _closed) return;
    _started = true;
    _generation++;
    unawaited(_run(_generation));
  }

  Future<void> close() async {
    _closed = true;
    _generation++;
    _heartbeat?.cancel();
    _watchdog?.cancel();
    _heartbeat = null;
    _watchdog = null;
    await _closeCurrentSocket();
    _client.close(force: true);
  }

  // ================================================================ 连接循环

  Future<void> _run(int generation) async {
    int attempt = 0;
    while (!_closed && generation == _generation) {
      final bool retrying = attempt > 0;
      _emitStatus(
        retrying ? DanmakuStatus.reconnecting : DanmakuStatus.connecting,
      );

      final Stopwatch watch = Stopwatch()..start();
      try {
        final List<String> urls = await _fetchEndpoints();
        Object? lastError;
        for (final String url in urls) {
          if (_closed || generation != _generation) return;
          try {
            await _openSocket(url, generation);
            lastError = null;
            break;
          } on DanmakuException catch (error) {
            lastError = error;
            _log('弹幕节点失败 $url：$error');
          }
        }
        if (lastError != null) throw lastError;
      } on Object catch (error) {
        _log('弹幕连接失败：$error');
        onError?.call('$error');
        _emitStatus(DanmakuStatus.failed);
      }

      if (_closed || generation != _generation) return;

      // 连接持续超过 30 秒说明是正常断开，退避从 2 秒重新开始。
      if (watch.elapsed >= const Duration(seconds: 30)) {
        attempt = 0;
      } else {
        attempt = min(attempt + 1, 5);
      }
      final Duration delay = Duration(seconds: min(30, 1 << attempt));
      _emitStatus(DanmakuStatus.reconnecting);
      _log('${delay.inSeconds}s 后重连弹幕');
      await Future<void>.delayed(delay);
    }
  }

  /// 取弹幕服务器列表（wss 优先，最多 4 个）。
  ///
  /// 签名被风控拒绝时（密钥轮换）会丢弃缓存并重试一次。
  Future<List<String>> _fetchEndpoints({bool allowRetry = true}) async {
    final Map<String, String> signed = await _wbi.sign(<String, String>{
      'id': '$roomId',
      'type': '0',
    }, cookie: cookie);
    final Uri uri = Uri.https(
      'api.live.bilibili.com',
      '/xlive/web-room/v1/index/getDanmuInfo',
      signed,
    );

    final HttpClientRequest request;
    try {
      request = await _client.getUrl(uri).timeout(const Duration(seconds: 10));
    } on Object {
      throw const DanmakuException('弹幕服务器地址获取超时');
    }

    request.headers.set(HttpHeaders.userAgentHeader, _userAgent);
    request.headers.set('Referer', 'https://live.bilibili.com/$roomId');
    request.headers.set('Origin', 'https://live.bilibili.com');
    request.headers.set('Accept', 'application/json, text/plain, */*');
    final String? header = cookie;
    if (header != null && header.isNotEmpty) {
      request.headers.set(HttpHeaders.cookieHeader, header);
    }

    final Map<String, dynamic> root;
    try {
      final HttpClientResponse response = await request.close().timeout(
        const Duration(seconds: 12),
      );
      final String text = await utf8.decoder
          .bind(response)
          .join()
          .timeout(const Duration(seconds: 12));
      final Object? decoded = jsonDecode(text);
      root = decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : <String, dynamic>{};
    } on Object {
      throw const DanmakuException('弹幕服务器信息获取失败');
    }

    final int code = _asInt(root['code']);
    if (code != 0) {
      if (allowRetry && (code == -352 || code == -412)) {
        _wbi.invalidate();
        return _fetchEndpoints(allowRetry: false);
      }
      throw DanmakuException(
        code == -352 || code == -412 || code == 412
            ? 'B站限制了弹幕请求（$code），请稍后重试'
            : '弹幕接口错误：$code ${root['message'] ?? ''}'.trim(),
      );
    }

    final Map<String, dynamic> data = _asMap(root['data']);
    final String token = '${data['token'] ?? ''}';
    if (token.isEmpty) throw const DanmakuException('弹幕鉴权凭证为空');

    final List<String> urls = <String>[];
    for (final Map<String, dynamic> host in _asRows(data['host_list'])) {
      final String name = '${host['host'] ?? ''}';
      if (name.isEmpty) continue;
      final int port = _asInt(host['wss_port']);
      final String url = port > 0 ? 'wss://$name:$port/sub' : 'wss://$name/sub';
      if (!urls.contains(url)) urls.add(url);
      if (urls.length >= 4) break;
    }
    if (urls.isEmpty) throw const DanmakuException('没有可用的弹幕服务器');

    _token = token;
    _log('弹幕服务器 ${urls.length} 个，首选 ${urls.first}');
    return urls;
  }

  Future<void> _openSocket(String url, int generation) async {
    final WebSocket socket;
    try {
      socket = await WebSocket.connect(
        url,
        headers: <String, dynamic>{
          'User-Agent': _userAgent,
          'Origin': 'https://live.bilibili.com',
          if (cookie != null && cookie!.isNotEmpty) 'Cookie': cookie!,
        },
      ).timeout(const Duration(seconds: 8));
    } on Object {
      throw const DanmakuException('弹幕服务器连接失败');
    }

    if (_closed || generation != _generation) {
      await socket.close();
      return;
    }

    _socket = socket;
    _lastPacketAt = DateTime.now();
    final Completer<void> auth = Completer<void>();
    final Completer<void> done = Completer<void>();
    _pendingAuth = auth;
    _sessionDone = done;

    _subscription = socket.listen(
      (dynamic data) {
        try {
          if (data is List<int>) {
            _handlePacket(Uint8List.fromList(data));
          } else if (data is String) {
            _handleText(data);
          }
        } on Object catch (error) {
          _log('弹幕解包失败：$error');
        }
      },
      onError: (Object error) {
        if (!auth.isCompleted) {
          auth.completeError(DanmakuException('弹幕连接异常：$error'));
        }
        if (!done.isCompleted) done.complete();
      },
      onDone: () {
        if (!auth.isCompleted) {
          auth.completeError(const DanmakuException('弹幕连接已断开'));
        }
        if (!done.isCompleted) done.complete();
      },
      cancelOnError: false,
    );

    _sendJson(7, <String, dynamic>{
      'uid': uid,
      'roomid': roomId,
      'protover': 2,
      'platform': 'web',
      'type': 2,
      'key': _token ?? '',
      if (buvid.isNotEmpty) 'buvid': buvid,
    });

    try {
      await auth.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw const DanmakuException('弹幕鉴权超时'),
      );
    } on Object {
      await _closeCurrentSocket();
      rethrow;
    } finally {
      _pendingAuth = null;
    }

    _log('弹幕已连接：$url');
    _emitStatus(DanmakuStatus.connected);
    _heartbeat = Timer.periodic(
      const Duration(seconds: 25),
      (Timer _) => _sendEmpty(2),
    );
    _watchdog = Timer.periodic(const Duration(seconds: 10), (Timer _) {
      if (DateTime.now().difference(_lastPacketAt) >
          const Duration(seconds: 70)) {
        _log('弹幕 70 秒无消息，主动断开重连');
        unawaited(_closeCurrentSocket());
      }
    });

    await done.future;
    await _closeCurrentSocket();
    _emitStatus(DanmakuStatus.reconnecting);
  }

  Future<void> _closeCurrentSocket() async {
    _heartbeat?.cancel();
    _watchdog?.cancel();
    _heartbeat = null;
    _watchdog = null;

    final Completer<void>? done = _sessionDone;
    _sessionDone = null;
    if (done != null && !done.isCompleted) done.complete();

    final StreamSubscription<dynamic>? subscription = _subscription;
    _subscription = null;
    await subscription?.cancel();

    final WebSocket? socket = _socket;
    _socket = null;
    if (socket != null && socket.readyState == WebSocket.open) {
      await socket.close();
    }
  }

  // ================================================================ 协议收发

  void _sendJson(int op, Map<String, dynamic> body) {
    _sendRaw(op, utf8.encode(jsonEncode(body)));
  }

  void _sendEmpty(int op) => _sendRaw(op, const <int>[]);

  void _sendRaw(int op, List<int> body) {
    final WebSocket? socket = _socket;
    if (socket == null || socket.readyState != WebSocket.open) return;

    final ByteData header = ByteData(16);
    header.setUint32(0, 16 + body.length);
    header.setUint16(4, 16);
    header.setUint16(6, 1);
    header.setUint32(8, op);
    header.setUint32(12, ++_sequence);

    final BytesBuilder builder = BytesBuilder(copy: false)
      ..add(header.buffer.asUint8List())
      ..add(body);
    try {
      socket.add(builder.takeBytes());
    } on Object catch (error) {
      _log('弹幕发送失败：$error');
    }
  }

  /// 解一个或多个包：压缩包解出来的内容仍然是完整的包序列。
  void _handlePacket(Uint8List data) {
    int offset = 0;
    while (offset + 16 <= data.length) {
      final ByteData header = ByteData.sublistView(data, offset, offset + 16);
      final int total = header.getUint32(0);
      final int headerLength = header.getUint16(4);
      final int protover = header.getUint16(6);
      final int op = header.getUint32(8);
      if (total < headerLength || offset + total > data.length) break;

      final Uint8List body = Uint8List.sublistView(
        data,
        offset + headerLength,
        offset + total,
      );
      offset += total;
      _handleFrame(op: op, protover: protover, body: body);
    }
  }

  void _handleFrame({
    required int op,
    required int protover,
    required Uint8List body,
  }) {
    _lastPacketAt = DateTime.now();

    if (op == 8) {
      _handleAuthReply(body, protover);
      return;
    }
    if (op == 3) return; // 人气值心跳回复
    if (op != 5) return;

    if (protover == 2) {
      try {
        final List<int> inflated = ZLibCodec().decode(body);
        _handlePacket(Uint8List.fromList(inflated));
      } on Object catch (error) {
        _log('弹幕解压失败：$error');
      }
      return;
    }
    if (protover == 3) {
      // 鉴权时已声明 protover=2，正常不会收到 brotli；收到就跳过。
      _log('收到未支持的 brotli 弹幕包');
      return;
    }

    _handleText(utf8.decode(body, allowMalformed: true));
  }

  void _handleAuthReply(Uint8List body, int protover) {
    final String text;
    try {
      if (protover == 2) {
        text = utf8.decode(ZLibCodec().decode(body), allowMalformed: true);
      } else {
        text = utf8.decode(body, allowMalformed: true);
      }
    } on Object {
      _failAuth(const DanmakuException('弹幕鉴权回复无法解析'));
      return;
    }

    int code = -1;
    try {
      final Object? decoded = jsonDecode(text);
      if (decoded is Map) code = _asInt(decoded['code']);
    } on FormatException {
      code = -1;
    }
    if (code == 0) {
      final Completer<void>? auth = _pendingAuth;
      if (auth != null && !auth.isCompleted) auth.complete();
    } else {
      _failAuth(DanmakuException('弹幕鉴权失败（$code）'));
    }
  }

  void _failAuth(DanmakuException error) {
    final Completer<void>? auth = _pendingAuth;
    if (auth != null && !auth.isCompleted) auth.completeError(error);
  }

  void _handleText(String text) {
    final String raw = text.trim();
    if (raw.isEmpty) return;
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return;
    }
    if (decoded is List) {
      for (final Object? row in decoded) {
        if (row is Map) _handleCommand(Map<String, dynamic>.from(row));
      }
      return;
    }
    if (decoded is Map) {
      _handleCommand(Map<String, dynamic>.from(decoded));
    }
  }

  // ================================================================ 消息解析

  void _handleCommand(Map<String, dynamic> json) {
    final String cmd = '${json['cmd'] ?? ''}';
    if (cmd.startsWith('DANMU_MSG')) {
      _handleDanmaku(json);
      return;
    }
    if (cmd == 'SUPER_CHAT_MESSAGE') {
      _handleSuperChat(json);
    }
  }

  void _handleDanmaku(Map<String, dynamic> json) {
    final Object? raw = json['info'];
    if (raw is! List || raw.length < 2) return;

    final String text = '${raw[1]}'.trim();
    if (text.isEmpty) return;

    final List<dynamic> meta = raw[0] is List
        ? raw[0] as List<dynamic>
        : const <dynamic>[];
    final List<dynamic> userInfo = raw.length > 2 && raw[2] is List
        ? raw[2] as List<dynamic>
        : const <dynamic>[];

    final String user =
        userInfo.length > 1 && '${userInfo[1]}'.trim().isNotEmpty
        ? '${userInfo[1]}'.trim()
        : '匿名';

    int color = 0xFFFFFF;
    if (meta.length > 3 && meta[3] is num) {
      color = (meta[3] as num).toInt() & 0xFFFFFF;
    }

    String? emoticon;
    if (meta.length > 15 && meta[15] is Map) {
      final Object? extraRaw = _asMap(meta[15])['extra'];
      // B 站有时把 extra 作为对象返回，有时是一段 JSON 字符串，两种都要认。
      final Map<String, dynamic> extra = extraRaw is String
          ? _tryDecodeMap(extraRaw)
          : _asMap(extraRaw);
      final Map<String, dynamic> emots = _asMap(extra['emots']);
      final Object? hit = emots[text];
      if (hit is Map) {
        final String url = _absoluteUrl('${_asMap(hit)['url'] ?? ''}');
        if (url.isNotEmpty) emoticon = url;
      }
    }

    _emit(
      DanmakuMessage(
        id:
            '${json['msg_id'] ?? ''}_'
            '${DateTime.now().microsecondsSinceEpoch}_${_messageSequence++}',
        user: user,
        text: text,
        color: color,
        emoticonUrl: emoticon,
        receivedAt: DateTime.now(),
      ),
    );
  }

  void _handleSuperChat(Map<String, dynamic> json) {
    final Map<String, dynamic> data = _asMap(json['data']);
    final String text = '${data['message'] ?? ''}'.trim();
    if (text.isEmpty) return;

    final Map<String, dynamic> userInfo = _asMap(data['user_info']);
    final String user = '${userInfo['uname'] ?? '醒目留言'}'.trim();

    int color = 0xFFD666;
    final String start = '${data['background_color_start'] ?? ''}';
    if (start.startsWith('#') && start.length >= 7) {
      final int? value = int.tryParse(start.substring(1, 7), radix: 16);
      if (value != null) color = value & 0xFFFFFF;
    }

    _emit(
      DanmakuMessage(
        id: 'sc_${data['id'] ?? ''}_${DateTime.now().microsecondsSinceEpoch}',
        user: user,
        text: text,
        color: color,
        superChat: true,
        price: _asInt(data['price']),
        receivedAt: DateTime.now(),
      ),
    );
  }

  void _emit(DanmakuMessage message) {
    if (_closed) return;
    onMessage(message);
  }

  void _emitStatus(DanmakuStatus status) {
    if (_closed) return;
    onStatus(status);
  }

  void _log(String message) {
    final void Function(String message)? handler = onLog;
    if (handler != null) handler('[LumiPlayer] $message');
  }

  // ================================================================ 工具

  static String _absoluteUrl(String url) {
    if (url.isEmpty) return '';
    if (url.startsWith('//')) return 'https:$url';
    // Android 默认禁止明文 HTTP，表情图统一走 https。
    if (url.startsWith('http://')) return 'https://${url.substring(7)}';
    return url;
  }

  static Map<String, dynamic> _tryDecodeMap(String raw) {
    try {
      final Object? decoded = jsonDecode(raw);
      return decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : <String, dynamic>{};
    } on FormatException {
      return <String, dynamic>{};
    }
  }

  static Map<String, dynamic> _asMap(Object? value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

  static List<Map<String, dynamic>> _asRows(Object? value) {
    if (value is! List) return <Map<String, dynamic>>[];
    return value
        .whereType<Map>()
        .map((Map<dynamic, dynamic> row) => Map<String, dynamic>.from(row))
        .toList();
  }

  static int _asInt(Object? value) {
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? 0;
  }
}
