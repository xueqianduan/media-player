// -------------------------------------------------------------------------
// 功能：Android 传输引擎桥接
//
// MethodChannel 下发命令，EventChannel 接收状态与进度。
// -------------------------------------------------------------------------

import 'package:flutter/services.dart';

import '../domain/transfer_models.dart';

class TransferBridgeException implements Exception {
  const TransferBridgeException(this.message);
  final String message;

  @override
  String toString() => message;
}

class TransferBridge {
  TransferBridge({MethodChannel? method, EventChannel? events})
    : _method = method ?? const MethodChannel('lumiplayer/transfer'),
      _events = events ?? const EventChannel('lumiplayer/transfer/events');

  final MethodChannel _method;
  final EventChannel _events;

  Stream<Map<String, dynamic>> get eventStream => _events
      .receiveBroadcastStream()
      .map((Object? event) => Map<String, dynamic>.from(event as Map));

  Future<Map<String, dynamic>> prepareReceive() => _invoke('prepareReceive');

  Future<void> stopReceive() => _invokeVoid('stopReceive');

  Future<void> cancel() => _invokeVoid('cancel');

  Future<Map<String, dynamic>> snapshot() => _invoke('snapshot');

  Future<String> send({
    required String invite,
    required List<TransferFile> files,
    required String deviceName,
  }) async {
    final Map<String, dynamic> result = await _invoke('send', <String, Object?>{
      'invite': invite,
      'deviceName': deviceName,
      'files': files
          .map(
            (TransferFile file) => <String, Object?>{
              'id': file.id,
              'name': file.name,
              'type': file.type.name,
              'size': file.size,
              'mime': mimeOf(file),
              'uri': file.path,
            },
          )
          .toList(),
    });
    return '${result['taskId'] ?? ''}';
  }

  Future<List<Map<String, dynamic>>> pickDocuments() async {
    final List<Object?> rows =
        (await _method.invokeMethod<List<Object?>>('pickDocuments')) ??
        const <Object?>[];
    return rows
        .whereType<Map>()
        .map((Map row) => Map<String, dynamic>.from(row))
        .toList();
  }

  Future<bool> openFile({required String uri, required String mime}) async {
    try {
      final bool? ok = await _method.invokeMethod<bool>(
        'openFile',
        <String, Object?>{'uri': uri, 'mime': mime},
      );
      return ok ?? false;
    } on PlatformException catch (error) {
      throw TransferBridgeException(error.message ?? '无法打开文件');
    }
  }

  Future<Map<String, dynamic>> _invoke(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    try {
      final Map<Object?, Object?>? result = await _method
          .invokeMethod<Map<Object?, Object?>>(method, arguments);
      return result == null
          ? <String, dynamic>{}
          : Map<String, dynamic>.from(result);
    } on PlatformException catch (error) {
      throw TransferBridgeException(error.message ?? '传输操作失败');
    } on MissingPluginException {
      throw const TransferBridgeException('当前设备不支持文件传输');
    }
  }

  Future<void> _invokeVoid(String method) async {
    try {
      await _method.invokeMethod<void>(method);
    } on PlatformException catch (error) {
      throw TransferBridgeException(error.message ?? '传输操作失败');
    } on MissingPluginException {
      throw const TransferBridgeException('当前设备不支持文件传输');
    }
  }
}

/// 按扩展名推断 MIME，Android 侧只用于保存与打开方式。
String mimeOf(TransferFile file) {
  final String name = file.name.toLowerCase();
  const Map<String, String> table = <String, String>{
    'mp4': 'video/mp4',
    'mkv': 'video/x-matroska',
    'avi': 'video/x-msvideo',
    'mov': 'video/quicktime',
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'gif': 'image/gif',
    'webp': 'image/webp',
    'mp3': 'audio/mpeg',
    'flac': 'audio/flac',
    'wav': 'audio/wav',
    'aac': 'audio/aac',
    'm4a': 'audio/mp4',
    'pdf': 'application/pdf',
    'txt': 'text/plain',
    'md': 'text/markdown',
    'zip': 'application/zip',
    'apk': 'application/vnd.android.package-archive',
  };
  final int dot = name.lastIndexOf('.');
  if (dot > 0 && dot < name.length - 1) {
    final String ext = name.substring(dot + 1);
    final String? hit = table[ext];
    if (hit != null) return hit;
  }
  switch (file.type) {
    case TransferFileType.video:
      return 'video/*';
    case TransferFileType.image:
      return 'image/*';
    case TransferFileType.audio:
      return 'audio/*';
    default:
      return 'application/octet-stream';
  }
}
