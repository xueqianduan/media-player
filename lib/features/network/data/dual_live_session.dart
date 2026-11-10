import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../domain/live_models.dart';
import 'bili_live_api.dart';
import 'live_leg.dart';

/// 双路直播会话：画面源 + 声音源，负责线路回退、声音切换与手动同步。
///
/// 所有控制操作串行执行，避免快速点击导致播放器状态冲突。
class DualLiveSession {
  DualLiveSession({required this.api, this.onVideo});

  final BiliLiveApi api;

  /// 画面控制器变化时回调（页面据此挂载 / 卸载 [Video]）。
  final void Function(VideoController? controller)? onVideo;

  final ValueNotifier<String> status = ValueNotifier<String>('尚未开始');
  final ValueNotifier<bool> usingVoice = ValueNotifier<bool>(false);
  final ValueNotifier<bool> paused = ValueNotifier<bool>(false);

  LiveLeg? picture;
  LiveLeg? voice;

  LiveRoom? pictureRoom;
  LiveRoom? voiceRoom;

  Duration pictureDelay = Duration.zero;
  Duration voiceDelay = Duration.zero;

  final Set<LiveLeg> _owned = <LiveLeg>{};
  Future<void> _tail = Future<void>.value();
  Future<void>? _closing;
  bool _closed = false;

  bool get hasVoice => voice != null;

  /// 声音源失败的原因（用于页面提示「可先听赛事原声」）。
  String? voiceFailure;

  void _checkOpen() {
    if (_closed) throw StateError('直播会话已关闭');
  }

  void _message(String message) {
    if (!_closed) status.value = message;
  }

  Future<void> _run(Future<void> Function() action) {
    final Future<void> next = _tail.then((_) async {
      _checkOpen();
      try {
        await action();
      } on Object catch (error) {
        _message('$error');
        rethrow;
      }
    });
    // 保留本次异常，但不要让操作队列永久失效。
    _tail = next.catchError((Object _) {});
    return next;
  }

  Future<LiveLeg> _connect(LiveRoom room, {required bool asPicture}) async {
    final List<LiveStream> candidates = await api.resolve(room.roomId);
    Object? lastError;

    for (final LiveStream source in candidates) {
      _checkOpen();

      final LiveLeg leg = LiveLeg(
        picture: asPicture,
        onError: (String message) {
          _message('${asPicture ? '画面源' : '声音源'}异常：$message');
        },
      );
      _owned.add(leg);

      if (asPicture) {
        picture = leg;
        // 页面必须及时挂载 Video，首帧检测才能完成。
        onVideo?.call(leg.controller);
      }

      try {
        await leg.open(source).timeout(const Duration(seconds: 30));
        _checkOpen();
        return leg;
      } on Object catch (error) {
        lastError = error;
        await leg.close().timeout(const Duration(seconds: 8), onTimeout: () {});
        _owned.remove(leg);
        if (picture == leg) {
          picture = null;
          if (!_closed) onVideo?.call(null);
        }
        _checkOpen();
      }
    }

    throw LiveApiException('所有直播线路均失败：$lastError');
  }

  /// 开始双路播放。[voiceRoom] 为空或未开播时，自动使用赛事原声。
  Future<void> start({required LiveRoom pictureRoom, LiveRoom? voiceRoom}) {
    return _run(() async {
      await _release();
      _checkOpen();

      pictureDelay = Duration.zero;
      voiceDelay = Duration.zero;
      voiceFailure = null;
      paused.value = false;
      usingVoice.value = false;
      this.pictureRoom = pictureRoom;
      this.voiceRoom = voiceRoom;

      try {
        _message('正在连接画面源…');
        picture = await _connect(pictureRoom, asPicture: true);

        if (voiceRoom != null && voiceRoom.roomId != pictureRoom.roomId) {
          try {
            _message('正在连接声音源…');
            voice = await _connect(voiceRoom, asPicture: false);
          } on Object catch (error) {
            _checkOpen();
            voiceFailure = '$error';
            voice = null;
          }
        }

        await _applySound(official: voice == null);

        _message(
          voice == null
              ? (voiceFailure == null ? '正在使用赛事原声' : '声音源不可用，已切到赛事原声')
              : '双路直播已开始，可调整同步',
        );
      } on Object {
        await _release();
        rethrow;
      }
    });
  }

  Future<void> _applySound({required bool official}) async {
    final LiveLeg? video = picture;
    if (video == null) throw StateError('画面源尚未连接');
    if (!official && voice == null) throw StateError('声音源尚未连接');

    // 先全部静音，再启用选中的一路，保证同时只有一路发声。
    await video.player.setVolume(0);
    await voice?.player.setVolume(0);

    if (official) {
      await video.player.setAudioTrack(AudioTrack.auto());
      await video.player.setVolume(100);
      usingVoice.value = false;
    } else {
      await video.player.setAudioTrack(AudioTrack.no());
      await voice!.player.setVolume(100);
      usingVoice.value = true;
    }
  }

  Future<void> useOfficialSound() => _run(() => _applySound(official: true));

  Future<void> useCommentatorSound() async {
    if (voice == null) {
      throw StateError('声音源未连接，暂时只能听赛事原声');
    }
    await _run(() => _applySound(official: false));
  }

  Future<void> setPaused(bool pause) => _run(() async {
    for (final LiveLeg? leg in <LiveLeg?>[picture, voice]) {
      if (leg == null) continue;
      if (pause) {
        await leg.player.pause();
      } else {
        await leg.player.play();
      }
    }
    paused.value = pause;
  });

  // ------------------------------------------------------------------ 同步

  Future<void> delayPicture(Duration amount) =>
      _run(() => _addDelay(pictureSide: true, amount: amount));

  Future<void> delayVoice(Duration amount) =>
      _run(() => _addDelay(pictureSide: false, amount: amount));

  /// 让某一侧额外延迟 [amount]：暂停该侧，等另一侧实际进度推进同样的时长。
  Future<void> _addDelay({
    required bool pictureSide,
    required Duration amount,
  }) async {
    final LiveLeg? video = picture;
    final LiveLeg? audio = voice;
    if (video == null || audio == null) {
      throw StateError('两路连接完成后才能校准');
    }
    if (amount <= Duration.zero || amount > const Duration(seconds: 5)) {
      throw ArgumentError('单次调整应在 0～5 秒之间');
    }

    final LiveLeg held = pictureSide ? video : audio;
    final LiveLeg reference = pictureSide ? audio : video;
    final Duration accumulated = pictureSide ? pictureDelay : voiceDelay;
    if (accumulated + amount > const Duration(seconds: 30)) {
      throw StateError('已达到延迟上限，请重新连接后再校准');
    }
    if (!reference.player.state.playing || reference.player.state.buffering) {
      throw StateError('另一路尚未稳定播放，请稍后再调整');
    }

    await held.player.pause();
    final Duration heldPosition = held.player.state.position;
    final Duration referenceStart = reference.player.state.position;
    final Stopwatch watch = Stopwatch()..start();
    Duration added = Duration.zero;

    try {
      while (true) {
        _checkOpen();
        if (held.error != null || reference.error != null) {
          throw StateError('直播发生异常，需要重新连接');
        }
        added = reference.player.state.position - referenceStart;
        if (added < Duration.zero) {
          throw StateError('直播时间轴发生变化，需要重新校准');
        }
        if (added >= amount) break;
        if (watch.elapsed > amount * 4 + const Duration(seconds: 12)) {
          throw TimeoutException('同步调整期间播放没有推进');
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      // 暂停期间缓存是否还有剩余：能读到缓存时间才校验，读不到就跳过，
      // 避免把不支持该属性的机型误判为失败。
      final double? cacheEnd = double.tryParse(
        await held.property('demuxer-cache-time') ?? '',
      );
      final double positionSeconds =
          heldPosition.inMicroseconds / Duration.microsecondsPerSecond;
      if (cacheEnd != null && cacheEnd > 0 && cacheEnd <= positionSeconds) {
        throw StateError('该线路没有保留有效缓存，无法确认同步调整');
      }
    } finally {
      if (!_closed) await held.player.play();
    }

    if (pictureSide) {
      pictureDelay += added;
    } else {
      voiceDelay += added;
    }
    _message('画面延迟 ${_seconds(pictureDelay)}s，声音延迟 ${_seconds(voiceDelay)}s');
  }

  String _seconds(Duration value) =>
      (value.inMilliseconds / 1000).toStringAsFixed(1);

  // ------------------------------------------------------------------ 生命周期

  Future<void> _release() async {
    if (!_closed) onVideo?.call(null);
    await Future.wait(
      _owned.toList().map(
        (LiveLeg leg) =>
            leg.close().timeout(const Duration(seconds: 8), onTimeout: () {}),
      ),
    );
    _owned.clear();
    picture = null;
    voice = null;
  }

  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    _closed = true;
    try {
      await _release();
    } on Object catch (error) {
      debugPrint('[ReelBox] close live session failed: $error');
    }
    await _tail.catchError((Object _) {});
    status.dispose();
    usingVoice.dispose();
    paused.dispose();
  }
}
