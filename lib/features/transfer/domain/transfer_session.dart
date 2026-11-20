// -------------------------------------------------------------------------
// 功能：传输会话状态（Dart 侧视图）
//
// 与 Android 引擎的事件一一对应：invite / state / progress / file / error。
// -------------------------------------------------------------------------

import 'transfer_models.dart';

enum TransferPhase {
  idle,
  checking,
  waiting,
  connecting,
  transferring,
  completed,
  failed,
  cancelled,
}

extension TransferPhaseX on TransferPhase {
  bool get isBusy =>
      this == TransferPhase.connecting || this == TransferPhase.transferring;

  String get label {
    switch (this) {
      case TransferPhase.idle:
        return '未开始';
      case TransferPhase.checking:
        return '正在准备';
      case TransferPhase.waiting:
        return '等待扫码';
      case TransferPhase.connecting:
        return '正在连接';
      case TransferPhase.transferring:
        return '传输中';
      case TransferPhase.completed:
        return '已完成';
      case TransferPhase.failed:
        return '失败';
      case TransferPhase.cancelled:
        return '已取消';
    }
  }
}

/// 单个文件的接收结果。
class TransferFileResult {
  const TransferFileResult({
    required this.id,
    required this.name,
    required this.bytes,
    required this.ok,
    this.uri,
    this.error,
  });

  final String id;
  final String name;
  final int bytes;
  final bool ok;
  final String? uri;
  final String? error;
}

class TransferSessionState {
  const TransferSessionState({
    this.phase = TransferPhase.idle,
    this.invite,
    this.ip,
    this.port,
    this.expiresAt,
    this.sessionId,
    this.taskId,
    this.direction = TransferDirection.send,
    this.deviceName = '',
    this.totalBytes = 0,
    this.receivedBytes = 0,
    this.currentFile = '',
    this.results = const <TransferFileResult>[],
    this.error,
  });

  final TransferPhase phase;
  final String? invite;
  final String? ip;
  final int? port;
  final DateTime? expiresAt;
  final String? sessionId;
  final String? taskId;
  final TransferDirection direction;
  final String deviceName;
  final int totalBytes;
  final int receivedBytes;
  final String currentFile;
  final List<TransferFileResult> results;
  final String? error;

  double get progress {
    if (totalBytes <= 0) return 0;
    return (receivedBytes / totalBytes).clamp(0.0, 1.0);
  }

  bool get finished =>
      phase == TransferPhase.completed ||
      phase == TransferPhase.failed ||
      phase == TransferPhase.cancelled;

  TransferSessionState copyWith({
    TransferPhase? phase,
    String? invite,
    String? ip,
    int? port,
    DateTime? expiresAt,
    String? sessionId,
    String? taskId,
    TransferDirection? direction,
    String? deviceName,
    int? totalBytes,
    int? receivedBytes,
    String? currentFile,
    List<TransferFileResult>? results,
    String? error,
    bool clearError = false,
  }) {
    return TransferSessionState(
      phase: phase ?? this.phase,
      invite: invite ?? this.invite,
      ip: ip ?? this.ip,
      port: port ?? this.port,
      expiresAt: expiresAt ?? this.expiresAt,
      sessionId: sessionId ?? this.sessionId,
      taskId: taskId ?? this.taskId,
      direction: direction ?? this.direction,
      deviceName: deviceName ?? this.deviceName,
      totalBytes: totalBytes ?? this.totalBytes,
      receivedBytes: receivedBytes ?? this.receivedBytes,
      currentFile: currentFile ?? this.currentFile,
      results: results ?? this.results,
      error: clearError ? null : (error ?? this.error),
    );
  }
}
