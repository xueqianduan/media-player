// -------------------------------------------------------------------------
// 功能：传输会话控制器
//
// 职责：订阅 Android 事件、维护当前会话状态、把终态写进历史记录。
// -------------------------------------------------------------------------

import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';

import '../data/transfer_bridge.dart';
import '../domain/transfer_models.dart';
import '../domain/transfer_session.dart';
import 'transfer_controller.dart';

final Provider<TransferBridge> transferBridgeProvider =
    Provider<TransferBridge>((Ref ref) => TransferBridge());

class TransferSessionController extends Notifier<TransferSessionState> {
  StreamSubscription<Map<String, dynamic>>? _subscription;
  final Map<String, TransferFile> _files = <String, TransferFile>{};
  String? _recordedTaskId;

  TransferBridge get _bridge => ref.read(transferBridgeProvider);

  @override
  TransferSessionState build() {
    final Stream<Map<String, dynamic>> stream = _bridge.eventStream;
    _subscription = stream.listen(
      _onEvent,
      onError: (Object error) {
        state = state.copyWith(phase: TransferPhase.failed, error: '$error');
      },
    );
    ref.onDispose(() => _subscription?.cancel());
    return const TransferSessionState();
  }

  // ---------------------------------------------------------------- 接收

  Future<void> prepareReceive() async {
    if (state.phase == TransferPhase.waiting || state.phase.isBusy) {
      return;
    }
    state = TransferSessionState(
      phase: TransferPhase.checking,
      direction: TransferDirection.receive,
    );
    try {
      final Map<String, dynamic> data = await _bridge.prepareReceive();
      final int expires = (data['expiresAt'] as num?)?.toInt() ?? 0;
      state = state.copyWith(
        phase: TransferPhase.waiting,
        invite: '${data['invite'] ?? ''}',
        ip: '${data['ip'] ?? ''}',
        port: (data['port'] as num?)?.toInt(),
        sessionId: '${data['sessionId'] ?? ''}',
        expiresAt: expires > 0
            ? DateTime.fromMillisecondsSinceEpoch(expires * 1000)
            : null,
        clearError: true,
      );
    } on Object catch (error) {
      state = state.copyWith(phase: TransferPhase.failed, error: '$error');
    }
  }

  Future<void> stopReceive() async {
    await _bridge.stopReceive();
    _reset();
  }

  // ---------------------------------------------------------------- 发送

  Future<String?> startSend({
    required String invite,
    required List<TransferFile> files,
  }) async {
    if (files.isEmpty) {
      state = state.copyWith(phase: TransferPhase.failed, error: '请先选择要发送的文件');
      return null;
    }
    final List<TransferFile> resolved;
    try {
      resolved = await _resolveSources(files);
    } on Object catch (error) {
      state = TransferSessionState(
        phase: TransferPhase.failed,
        direction: TransferDirection.send,
        error: '$error',
      );
      return null;
    }
    _files
      ..clear()
      ..addEntries(resolved.map((TransferFile f) => MapEntry(f.id, f)));
    _recordedTaskId = null;
    state = TransferSessionState(
      phase: TransferPhase.connecting,
      direction: TransferDirection.send,
      totalBytes: files.fold<int>(0, (int sum, TransferFile f) => sum + f.size),
    );
    try {
      final String taskId = await _bridge.send(
        invite: invite,
        files: resolved,
        deviceName: 'LumiPlayer',
      );
      state = state.copyWith(taskId: taskId, clearError: true);
      return taskId;
    } on Object catch (error) {
      state = state.copyWith(phase: TransferPhase.failed, error: '$error');
      return null;
    }
  }

  /// 把相册 / 分享入口带进来的来源解析成 Android 能直接读的 URI。
  Future<List<TransferFile>> _resolveSources(List<TransferFile> files) async {
    final List<TransferFile> out = <TransferFile>[];
    for (final TransferFile file in files) {
      String path = file.path;
      int size = file.size;
      final bool isUri =
          path.startsWith('content://') ||
          path.startsWith('file://') ||
          path.startsWith('/');
      bool readable = isUri;
      if (path.startsWith('/')) {
        readable = await File(path).exists();
      }
      if (!readable) {
        final AssetEntity? asset = await AssetEntity.fromId(file.id);
        if (asset == null) throw StateError('无法读取 ${file.name}');
        final String? url = await asset.getMediaUrl();
        final File? local = await asset.file;
        path = (url != null && url.isNotEmpty) ? url : (local?.path ?? '');
        if (path.isEmpty) throw StateError('无法读取 ${file.name}');
        if (size <= 0 && local != null) size = await local.length();
      } else if (size <= 0 && path.startsWith('/')) {
        size = await File(path).length();
      }
      out.add(
        TransferFile(
          id: file.id,
          path: path,
          name: file.name,
          size: size,
          type: file.type,
          source: file.source,
        ),
      );
    }
    return out;
  }

  Future<void> cancel() async {
    await _bridge.cancel();
    state = state.copyWith(phase: TransferPhase.cancelled);
    _writeHistory(TransferStatus.cancelled);
  }

  void reset() {
    _bridge.stopReceive();
    _reset();
  }

  void _reset() {
    _files.clear();
    _recordedTaskId = null;
    state = const TransferSessionState();
  }

  // ---------------------------------------------------------------- 事件

  void _onEvent(Map<String, dynamic> event) {
    switch (event['type']) {
      case 'invite':
        final int expires = (event['expiresAt'] as num?)?.toInt() ?? 0;
        state = state.copyWith(
          phase: TransferPhase.waiting,
          direction: TransferDirection.receive,
          invite: '${event['invite'] ?? ''}',
          ip: '${event['ip'] ?? ''}',
          port: (event['port'] as num?)?.toInt(),
          sessionId: '${event['sessionId'] ?? ''}',
          expiresAt: expires > 0
              ? DateTime.fromMillisecondsSinceEpoch(expires * 1000)
              : null,
        );
      case 'state':
        _onState(event);
      case 'progress':
        state = state.copyWith(
          phase: TransferPhase.transferring,
          receivedBytes:
              (event['received'] as num?)?.toInt() ?? state.receivedBytes,
          totalBytes: (event['total'] as num?)?.toInt() ?? state.totalBytes,
          currentFile: '${event['current'] ?? state.currentFile}',
          taskId: '${event['taskId'] ?? state.taskId ?? ''}',
        );
      case 'file':
        final String id = '${event['id'] ?? ''}';
        final String name = '${event['name'] ?? '文件'}';
        final bool ok = '${event['status']}' == 'ok';
        final TransferFileResult result = TransferFileResult(
          id: id,
          name: name,
          bytes: (event['bytes'] as num?)?.toInt() ?? 0,
          ok: ok,
          uri: event['uri'] as String?,
          error: event['error'] as String?,
        );
        state = state.copyWith(
          results: <TransferFileResult>[...state.results, result],
        );
      case 'error':
        state = state.copyWith(
          phase: TransferPhase.failed,
          error: '${event['message'] ?? '传输失败'}',
        );
        _writeHistory(TransferStatus.failed);
    }
  }

  void _onState(Map<String, dynamic> event) {
    final String value = '${event['state'] ?? ''}';
    final String taskId = '${event['taskId'] ?? state.taskId ?? ''}';
    switch (value) {
      case 'receiving':
        state = state.copyWith(
          phase: TransferPhase.transferring,
          direction: TransferDirection.receive,
          taskId: taskId,
          deviceName: '${event['deviceName'] ?? ''}',
          totalBytes: (event['totalBytes'] as num?)?.toInt() ?? 0,
        );
      case 'connected':
        state = state.copyWith(
          phase: TransferPhase.connecting,
          taskId: taskId,
          deviceName: '${event['deviceName'] ?? ''}',
        );
      case 'completed':
        state = state.copyWith(
          phase: TransferPhase.completed,
          taskId: taskId,
          receivedBytes:
              (event['receivedBytes'] as num?)?.toInt() ??
              (event['confirmedBytes'] as num?)?.toInt() ??
              state.totalBytes,
        );
        _writeHistory(TransferStatus.completed);
      case 'cancelled':
        state = state.copyWith(phase: TransferPhase.cancelled, taskId: taskId);
        _writeHistory(TransferStatus.cancelled);
    }
  }

  // ---------------------------------------------------------------- 历史

  void _writeHistory(TransferStatus status) {
    final String taskId = state.taskId ?? '';
    if (taskId.isEmpty || _recordedTaskId == taskId) return;
    _recordedTaskId = taskId;

    final List<TransferFile> files = state.direction == TransferDirection.send
        ? _files.values.toList()
        : state.results
              .map(
                (TransferFileResult r) => TransferFile(
                  id: r.id,
                  path: r.uri ?? '',
                  name: r.name,
                  size: r.bytes,
                  type: TransferFileType.other,
                  source: '接收',
                ),
              )
              .toList();

    final TransferRecord record = TransferRecord(
      id: taskId,
      direction: state.direction,
      status: status,
      deviceName: state.deviceName,
      files: files,
      totalBytes: state.totalBytes,
      transferredBytes: state.receivedBytes,
      startedAt: DateTime.now(),
      finishedAt: DateTime.now(),
      savePath: state.results.isEmpty ? null : state.results.first.uri,
      error: state.error,
    );
    ref.read(transferControllerProvider.notifier).upsert(record);
  }
}

final NotifierProvider<TransferSessionController, TransferSessionState>
transferSessionProvider =
    NotifierProvider<TransferSessionController, TransferSessionState>(
      TransferSessionController.new,
    );
