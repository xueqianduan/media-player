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
  LiveLeg({
    required this.picture,
    required void Function(String message) onError,
  }) : player = Player(
         configuration: const PlayerConfiguration(
           muted: true,
           bufferSize: 48 * 1024 * 1024,
         ),
       ) {
    controller = picture ? VideoController(player) : null;
    _errors = player.stream.error.listen((String message) {
      error = message;
      onError(message);
    });
  }

  final bool picture;
  final Player player;
  late final VideoController? controller;
  late final StreamSubscription<String> _errors;

  String? error;

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
    await _setProperty('cache', 'yes');
    await _setProperty('cache-secs', '40');
    await _setProperty('demuxer-readahead-secs', '40');
    await _setProperty('demuxer-seekable-cache', 'yes');

    await player.open(
      Media(source.url, httpHeaders: source.headers),
      play: false,
    );

    await player.setVideoTrack(picture ? VideoTrack.auto() : VideoTrack.no());
    await player.setAudioTrack(picture ? AudioTrack.no() : AudioTrack.auto());
    await player.setVolume(0);

    final Duration initialPosition = player.state.position;
    await player.play();

    if (picture) {
      await controller!.waitUntilFirstFrameRendered.timeout(
        const Duration(seconds: 20),
      );
      return;
    }

    final Stopwatch watch = Stopwatch()..start();
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
      if (watch.elapsed > const Duration(seconds: 20)) {
        throw TimeoutException('声音源没有开始播放');
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
