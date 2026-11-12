// -------------------------------------------------------------------------
// 功能：单路播放器封装
//
// 主要内容：
// - 一路直播的 mpv 打开/关闭与缓存参数
// - 错误流监听与首帧等待
// -------------------------------------------------------------------------

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../domain/live_models.dart';

/// 单路直播播放器。
///
/// 画面源会创建 [VideoController] 并保留视频轨；声音源不创建视频控制器，
/// 并关闭视频轨。两路启动时都先静音，由 [DualLiveSession] 决定哪一路发声。
class LiveLeg {
  LiveLeg({required this.picture, required this.onError})
    : player = Player(
        configuration: const PlayerConfiguration(
          muted: true,
          bufferSize: 48 * 1024 * 1024,
        ),
      ) {
    controller = picture ? VideoController(player) : null;
    _errors = player.stream.error.listen((String message) {
      error = message;
      // 连接阶段由 _connect 统一换线，不往界面上抛错误；
      // 连接成功后打开，运行中出错才提示用户。
      if (notifyErrors) onError(message);
    });
  }

  final bool picture;
  final void Function(String message) onError;
  final Player player;
  late final VideoController? controller;
  late final StreamSubscription<String> _errors;

  String? error;

  /// 连接成功后再置为 true：只有真正在用的线路才把错误暴露到界面。
  bool notifyErrors = false;

  /// 单路就绪超时：坏线路尽快失败，避免连续累积等待。
  static const Duration _readyTimeout = Duration(seconds: 12);

  bool _closed = false;
  Future<void>? _closing;

  NativePlayer? get _native {
    final PlatformPlayer? platform = player.platform;
    return platform is NativePlayer ? platform : null;
  }

  /// 读取 mpv 属性（用于同步时确认缓存是否还在）。
  Future<String?> property(String key) async {
    try {
      return await _native?.getProperty(key);
    } on Object {
      return null;
    }
  }

  Future<void> _setProperty(String key, String value) async {
    try {
      await _native?.setProperty(key, value);
    } on Object catch (error) {
      debugPrint('[LumiPlayer] live setProperty $key failed: $error');
    }
  }

  /// 打开一路直播。直播总时长为 0，不能用「必须读到时长」作为启动条件。
  Future<void> open(LiveStream source) async {
    final Stopwatch watch = Stopwatch()..start();

    await _setProperty('cache', 'yes');
    await _setProperty('cache-secs', '40');
    await _setProperty('demuxer-readahead-secs', '40');
    await _setProperty('demuxer-seekable-cache', 'yes');

    await player.open(
      Media(source.url, httpHeaders: source.headers),
      play: false,
    );
    debugPrint(
      '[LumiPlayer] live open request ${watch.elapsedMilliseconds}ms '
      '(${source.format})',
    );

    await player.setVideoTrack(picture ? VideoTrack.auto() : VideoTrack.no());
    await player.setAudioTrack(picture ? AudioTrack.no() : AudioTrack.auto());
    await player.setVolume(0);

    final Duration initialPosition = player.state.position;
    await player.play();

    if (picture) {
      await _waitFirstFrame(watch);
      debugPrint(
        '[LumiPlayer] live picture ready in ${watch.elapsedMilliseconds}ms '
        '(${source.format})',
      );
      return;
    }

    await _waitAudioReady(initialPosition, watch);
    debugPrint(
      '[LumiPlayer] live voice ready in ${watch.elapsedMilliseconds}ms '
      '(${source.format})',
    );
  }

  /// 首帧与错误流赛跑：线路 403 时立刻失败换线，不再空等首帧超时。
  Future<void> _waitFirstFrame(Stopwatch watch) async {
    final String? existing = error;
    if (existing != null) throw StateError(existing);

    final Completer<void> failure = Completer<void>();
    final StreamSubscription<String> errors = player.stream.error.listen((
      String message,
    ) {
      if (!failure.isCompleted) {
        failure.completeError(StateError(message));
      }
    });
    try {
      await Future.any<void>(<Future<void>>[
        controller!.waitUntilFirstFrameRendered,
        failure.future,
      ]).timeout(_readyTimeout);
    } on TimeoutException {
      throw TimeoutException('首帧渲染超时（${watch.elapsedMilliseconds}ms）');
    } finally {
      await errors.cancel();
    }
  }

  Future<void> _waitAudioReady(
    Duration initialPosition,
    Stopwatch watch,
  ) async {
    while (!_closed) {
      if (error != null) throw StateError(error!);

      final bool hasAudio = player.state.tracks.audio.any(
        (AudioTrack track) => track.id != 'auto' && track.id != 'no',
      );
      if (hasAudio &&
          !player.state.buffering &&
          player.state.position > initialPosition) {
        return;
      }
      if (watch.elapsed > _readyTimeout) {
        throw TimeoutException('声音源没有开始播放（${watch.elapsedMilliseconds}ms）');
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    throw StateError('播放器已关闭');
  }

  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    _closed = true;
    try {
      await _errors.cancel();
    } on Object catch (error) {
      debugPrint('[LumiPlayer] live cancel error stream failed: $error');
    }
    try {
      await player.dispose();
    } on Object catch (error) {
      debugPrint('[LumiPlayer] live dispose player failed: $error');
    }
  }
}
