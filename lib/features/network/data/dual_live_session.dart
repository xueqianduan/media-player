// -------------------------------------------------------------------------
// 功能：双路直播会话
//
// 主要内容：
// - 画面源 + 声音源的建立与线路回退
// - 声音切换、暂停、手动同步
// - 所有控制操作串行执行
// -------------------------------------------------------------------------

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../domain/live_models.dart';
import 'bili_live_api.dart';
import 'live_leg.dart';

/// 双路直播会话：画面源 + 声音源，负责线路回退、声音切换与手动同步。
///
/// 所有控制操作串行执行，避免快速点击导致播放器状态冲突。
class DualLiveSession {
  DualLiveSession({required this.api, this.onVideo, this.cookie});

  final BiliLiveApi api;

  /// 已登录时的平台 Cookie，用于请求更高画质；为空表示匿名。
  final String? cookie;

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

  /// 画面源实际画质与本次可选画质。
  final ValueNotifier<int> currentQn = ValueNotifier<int>(250);
  final ValueNotifier<List<LiveQuality>> qualities =
      ValueNotifier<List<LiveQuality>>(const <LiveQuality>[]);

  int _requestedQn = 250;

  /// 单路连接的总预算：两轮取流 + 若干候选，超过就放弃，避免无限加载。
  static const Duration _connectBudget = Duration(seconds: 30);

  final Set<LiveLeg> _owned = <LiveLeg>{};

  /// 启动代际：新的 start 会让上一轮的后台解说连接自行作废。
  int _generation = 0;
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

  Future<LiveLeg> _connect(
    LiveRoom room, {
    required bool asPicture,
    int? qn,
  }) async {
    final String role = asPicture ? '画面源' : '声音源';
    final Stopwatch total = Stopwatch()..start();
    Object? lastError;
    int attempts = 0;

    // 两轮：第一轮把平台返回的候选都试一遍，全失败就重新取流再试一轮
    // （直链带时效签名，重新取流往往能拿到新的可用节点）。
    for (int round = 1; round <= 2; round++) {
      if (total.elapsed >= _connectBudget) break;

      final Stopwatch resolveWatch = Stopwatch()..start();
      final LivePlaylist playlist = await api.resolve(
        room.roomId,
        qn: qn ?? (asPicture ? _requestedQn : 250),
        cookie: cookie,
      );
      final List<LiveStream> candidates = playlist.streams;

      if (asPicture) {
        _requestedQn = qn ?? _requestedQn;
        qualities.value = playlist.qualities;
        currentQn.value = playlist.currentQn;
      }
      debugPrint(
        '[LumiPlayer] live $role resolve #$round '
        '${resolveWatch.elapsedMilliseconds}ms, ${candidates.length} streams',
      );

      for (final LiveStream source in candidates) {
        if (total.elapsed >= _connectBudget) break;
        attempts++;
        _checkOpen();

        final Stopwatch createWatch = Stopwatch()..start();
        final LiveLeg leg = LiveLeg(
          picture: asPicture,
          // 连接阶段不提示错误，换线由这里统一处理；成功后才开始上报。
          onError: (String message) => _message('$role异常：$message'),
        );
        debugPrint(
          '[LumiPlayer] live $role player create '
          '${createWatch.elapsedMilliseconds}ms',
        );
        _owned.add(leg);

        if (asPicture) {
          picture = leg;
          // 页面必须及时挂载 Video，首帧检测才能完成。
          onVideo?.call(leg.controller);
        }

        final Stopwatch openWatch = Stopwatch()..start();
        try {
          // 首帧内部已有 12s 超时，这里再兜一层，防止 player.open 卡住。
          await leg.open(source).timeout(const Duration(seconds: 15));
          _checkOpen();
          leg.notifyErrors = true;
          debugPrint(
            '[LumiPlayer] live $role ok ${source.format} '
            '${openWatch.elapsedMilliseconds}ms (try $attempts)',
          );
          return leg;
        } on Object catch (error) {
          lastError = error;
          debugPrint(
            '[LumiPlayer] live $role fail ${source.format} '
            '${openWatch.elapsedMilliseconds}ms: $error',
          );
          await leg.close().timeout(
            const Duration(seconds: 8),
            onTimeout: () {},
          );
          _owned.remove(leg);
          if (picture == leg) {
            picture = null;
            if (!_closed) onVideo?.call(null);
          }
          _checkOpen();
        }
      }

      if (round == 1 && total.elapsed < _connectBudget) {
        _message('$role线路不可用，正在重新取流…');
      }
    }

    throw LiveApiException('$role所有线路均失败：$lastError');
  }

  /// 开始双路播放。[voiceRoom] 为空或未开播时，自动使用赛事原声。
  ///
  /// 画面连上就立即出声，解说在后台独立连接：解说慢或失败都不会拖住
  /// 启动、暂停、切换声音这些操作。
  Future<void> start({required LiveRoom pictureRoom, LiveRoom? voiceRoom}) {
    return _run(() async {
      final int generation = ++_generation;
      final Stopwatch watch = Stopwatch()..start();

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
        // 画面一就绪就先播原声，不等解说。
        await _applySound(official: true);
        _checkOpen();
        debugPrint(
          '[LumiPlayer] live picture started in ${watch.elapsedMilliseconds}ms',
        );

        if (voiceRoom == null || voiceRoom.roomId == pictureRoom.roomId) {
          _message('正在使用赛事原声');
          return;
        }

        _message('画面已开始，正在连接解说…');
        unawaited(_connectVoice(voiceRoom, generation));
      } on Object {
        await _release();
        rethrow;
      }
    });
  }

  /// 后台连接解说。失败只回落到赛事原声，不影响已经在播的画面。
  Future<void> _connectVoice(LiveRoom room, int generation) async {
    final Stopwatch watch = Stopwatch()..start();
    try {
      final LiveLeg leg = await _connect(room, asPicture: false);
      if (_closed || generation != _generation) {
        await leg.close().timeout(const Duration(seconds: 8), onTimeout: () {});
        return;
      }

      voice = leg;
      voiceFailure = null;
      // 连接期间用户可能已经暂停，新连上的解说保持暂停，避免突然出声。
      if (paused.value) await leg.player.pause();
      debugPrint(
        '[LumiPlayer] live voice ready in ${watch.elapsedMilliseconds}ms',
      );

      // 用户在等待期间已经点了「解说」的话，连上后立刻切过去。
      if (usingVoice.value) {
        await _run(() => _applySound(official: false));
      }
      _message('双路直播已就绪，可切换解说声音');
    } on Object catch (error) {
      if (_closed || generation != _generation) return;
      voice = null;
      voiceFailure = '$error';
      _message('声音源不可用，继续使用赛事原声');
      debugPrint('[LumiPlayer] live voice failed: $error');
    }
  }

  Future<void> _applySound({required bool official}) async {
    final LiveLeg? video = picture;
    if (video == null) throw StateError('画面源尚未连接');
    if (!official && voice == null) throw StateError('声音源尚未连接');

    // 只调音量，不动音轨：画面源的音轨从启动起就一直开着，
    // 音频时钟持续运行，切原声/解说时不用重新初始化音频链路。
    await video.player.setVolume(0);
    await voice?.player.setVolume(0);

    if (official) {
      await video.player.setVolume(100);
      usingVoice.value = false;
    } else {
      await voice!.player.setVolume(100);
      usingVoice.value = true;
    }
  }

  Future<void> useOfficialSound() => _run(() => _applySound(official: true));

  /// 刷新画面源：重新解析地址并只重建画面这一路，声音源保持不动。
  ///
  /// 直播地址带时效签名，掉流后重新解析通常就能恢复；这里不动声音，
  /// 已经调好的声音延迟与解说选择都会保留。
  Future<void> refreshPicture() {
    return _run(() async {
      final LiveRoom? room = pictureRoom;
      if (room == null) throw StateError('还没有画面源');

      _message('正在重新连接画面源…');

      final LiveLeg? old = picture;
      picture = null;
      if (!_closed) onVideo?.call(null);
      if (old != null) {
        _owned.remove(old);
        await old.close().timeout(const Duration(seconds: 8), onTimeout: () {});
      }

      await _connect(room, asPicture: true);
      _checkOpen();
      // 新流从当前直播点开始，旧同步偏移不再成立。
      pictureDelay = Duration.zero;
      await _applySound(official: voice == null || !usingVoice.value);
      if (paused.value) await picture?.player.pause();
      _message('画面源已刷新');
    });
  }

  /// 切换画面画质：重新取流并只重建画面这一路，声音源保持不动。
  Future<void> switchQuality(int qn) {
    return _run(() async {
      final LiveRoom? room = pictureRoom;
      if (room == null) throw StateError('还没有画面源');
      if (picture == null) throw StateError('画面源尚未连接');
      if (qn == currentQn.value) return;

      final int previous = currentQn.value;
      _message('正在切换画质…');

      final LiveLeg? old = picture;
      picture = null;
      if (!_closed) onVideo?.call(null);
      if (old != null) {
        _owned.remove(old);
        await old.close().timeout(const Duration(seconds: 8), onTimeout: () {});
      }

      try {
        await _connect(room, asPicture: true, qn: qn);
      } on Object {
        _checkOpen();
        _message('该画质不可用，已切回原档位');
        await _connect(room, asPicture: true, qn: previous);
      }

      _checkOpen();
      // 新流从当前直播点开始，旧同步偏移不再成立。
      pictureDelay = Duration.zero;
      await _applySound(official: voice == null || !usingVoice.value);
      if (paused.value) await picture?.player.pause();
      _message('画质：${LiveQuality.labelOf(currentQn.value)}');
    });
  }

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
      debugPrint('[LumiPlayer] close live session failed: $error');
    }
    await _tail.catchError((Object _) {});
    status.dispose();
    usingVoice.dispose();
    paused.dispose();
    currentQn.dispose();
    qualities.dispose();
  }
}
