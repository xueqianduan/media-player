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

  /// 画面进度：缓存窗口内的当前位置与直播边缘。
  final ValueNotifier<LiveProgress> progress = ValueNotifier<LiveProgress>(
    const LiveProgress(),
  );

  Timer? _progressTimer;
  Duration _liveEdge = Duration.zero;

  /// 用户主动回拖造成的落后量；0 表示正在看直播。
  Duration _behind = Duration.zero;

  /// 进度条可回退的窗口，初始 40 秒，随后按实际 demuxer 缓存增长。
  Duration _window = const Duration(seconds: 40);

  /// seek 进行中：暂停进度刷新，避免 ticker 用旧位置把滑块拉回去。
  bool _seeking = false;

  int _progressTicks = 0;

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

  // ------------------------------------------------------------------ 进度

  void _startProgressTicker() {
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(
      const Duration(milliseconds: 500),
      (Timer _) => _updateProgress(),
    );
  }

  void _updateProgress() {
    final LiveLeg? video = picture;
    if (_closed || video == null || _seeking) return;
    final Duration position = video.player.state.position;
    // media_kit 的 state.buffer 来自 mpv 的 demuxer-cache-time，
    // 表示「缓存末尾的绝对时间」，直接就是直播边缘，不能再加 position。
    final Duration edge = video.player.state.buffer;
    if (edge <= Duration.zero) return;
    if (edge > _liveEdge) _liveEdge = edge;
    progress.value = LiveProgress(
      position: position,
      behind: _behind,
      liveEdge: _liveEdge,
      window: _window,
    );

    _progressTicks++;
    if (_progressTicks % 6 == 0) {
      unawaited(_refreshWindow(video));
    }
  }

  /// 按实际 demuxer 缓存调整可回退窗口（最多 10 分钟）。
  Future<void> _refreshWindow(LiveLeg video) async {
    final String? raw = await video.property('demuxer-cache-duration');
    final double? seconds = double.tryParse(raw ?? '');
    if (seconds == null || seconds <= 1) return;
    final Duration next = Duration(milliseconds: (seconds * 1000).round());
    if (next <= _window) return;
    _window = next > const Duration(minutes: 10)
        ? const Duration(minutes: 10)
        : next;
  }

  void _resetProgress() {
    _liveEdge = Duration.zero;
    _behind = Duration.zero;
    _window = const Duration(seconds: 40);
    _progressTicks = 0;
    _seeking = false;
    if (!_closed) progress.value = const LiveProgress();
  }

  /// 在缓存窗口内跳转。使用解说时，声音那一路按相同偏移跟随。
  Future<void> seekTo(Duration target) => _seekBoth(target, resetBehind: false);

  /// 回到直播边缘（留 1.5 秒余量）。
  Future<void> goLive() {
    if (_liveEdge <= const Duration(seconds: 1)) {
      return Future<void>.error(StateError('还没有可回到的直播位置'));
    }
    final Duration target = _liveEdge - const Duration(milliseconds: 300);
    return _seekBoth(
      target > Duration.zero ? target : Duration.zero,
      resetBehind: true,
    );
  }

  Future<void> _seekBoth(Duration target, {required bool resetBehind}) {
    return _run(() async {
      final LiveLeg? video = picture;
      if (video == null) throw StateError('画面源尚未连接');

      Duration clamped = target;
      final Duration maxTarget = _liveEdge > const Duration(seconds: 1)
          ? _liveEdge - const Duration(milliseconds: 300)
          : Duration.zero;
      if (maxTarget > Duration.zero && clamped > maxTarget) {
        clamped = maxTarget;
      }
      if (clamped < Duration.zero) clamped = Duration.zero;

      final Duration current = video.player.state.position;
      // 正数表示往回拖，负数表示往前追。
      final Duration delta = current - clamped;
      final Duration previousBehind = _behind;

      // 先把状态改到位再 seek：seek 期间 ticker 会被 _seeking 挡住，
      // 不会出现「松手后滑块又跳回原位」。
      Duration nextBehind;
      if (resetBehind) {
        nextBehind = Duration.zero;
      } else {
        nextBehind = _behind + delta;
        if (nextBehind < Duration.zero) nextBehind = Duration.zero;
        if (nextBehind > _window) nextBehind = _window;
      }
      _seeking = true;
      _behind = nextBehind;
      progress.value = LiveProgress(
        position: clamped,
        behind: _behind,
        liveEdge: _liveEdge,
        window: _window,
      );

      final bool wasPaused = paused.value;
      try {
        // exact：避免落到几秒前的关键帧，回到直播后更接近真实直播点。
        // 个别线路不支持精确 seek 时退回普通的 absolute seek。
        try {
          await video.seekExact(clamped);
        } on Object catch (error) {
          debugPrint('[LumiPlayer] exact seek failed, fallback: $error');
          await video.player.seek(clamped);
        }

        final LiveLeg? audio = voice;
        if (audio != null && usingVoice.value) {
          final Duration audioTarget = audio.player.state.position - delta;
          if (audioTarget >= Duration.zero) {
            await audio.player.seek(audioTarget);
          }
        }

        // 回到直播后再按最新缓存末尾校正一次：
        // mpv 可能落到关键帧或缓存末尾之前，这里补一次精确 seek。
        if (resetBehind) {
          await Future<void>.delayed(const Duration(milliseconds: 600));
          final double? edgeSeconds = double.tryParse(
            await video.property('demuxer-cache-time') ?? '',
          );
          if (edgeSeconds != null && edgeSeconds > 0) {
            final Duration edge = Duration(
              milliseconds: (edgeSeconds * 1000).round(),
            );
            final Duration actual = video.player.state.position;
            if (edge - actual > const Duration(seconds: 3)) {
              final Duration snap = edge - const Duration(milliseconds: 300);
              debugPrint(
                '[LumiPlayer] goLive snap '
                '${actual.inMilliseconds}ms -> ${snap.inMilliseconds}ms',
              );
              try {
                await video.seekExact(snap);
              } on Object catch (error) {
                debugPrint('[LumiPlayer] goLive snap failed: $error');
              }
            }
          }
        }

        // 回到直播时如果处于暂停，顺手恢复播放。
        if (resetBehind && wasPaused) {
          for (final LiveLeg? leg in <LiveLeg?>[video, audio]) {
            if (leg != null) await leg.player.play();
          }
          paused.value = false;
        }
      } on Object {
        // seek 失败时回滚落后量，避免滑块显示与画面不一致。
        _behind = previousBehind;
        rethrow;
      } finally {
        _seeking = false;
        _updateProgress();
      }
      if (resetBehind) _message('已回到直播');
    });
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
        _startProgressTicker();
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
      // 新流从当前直播点开始，旧同步偏移与进度窗口都不再成立。
      pictureDelay = Duration.zero;
      _resetProgress();
      await _applySound(official: voice == null || !usingVoice.value);
      if (paused.value) await picture?.player.pause();
      _message('直播中');
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
      // 新流从当前直播点开始，旧同步偏移与进度窗口都不再成立。
      pictureDelay = Duration.zero;
      _resetProgress();
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
    if (video == null) {
      throw StateError('画面源尚未连接');
    }
    if (audio == null) {
      throw StateError('还没有声音源，先在首页选择「声音来源」');
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
    if (paused.value) {
      throw StateError('暂停状态下不能校准，请先继续播放');
    }

    // 直播刚起播或换线时，另一路可能还在缓冲：等最多 3 秒再判定失败，
    // 而不是一上来就报「尚未稳定播放」。
    final Stopwatch readyWatch = Stopwatch()..start();
    while (reference.player.state.buffering ||
        !reference.player.state.playing) {
      _checkOpen();
      if (readyWatch.elapsed > const Duration(seconds: 3)) {
        throw StateError('另一路还没准备好，请等画面与声音都播放后再试');
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }

    debugPrint(
      '[LumiPlayer] sync start ${pictureSide ? 'picture' : 'voice'} '
      '+${amount.inMilliseconds}ms',
    );

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

      // 缓存时间只做诊断记录，不再作为失败条件：
      // 直播的 demuxer-cache-time 语义随线路不同，误判过一次就直接报错。
      final double? cacheEnd = double.tryParse(
        await held.property('demuxer-cache-time') ?? '',
      );
      final double positionSeconds =
          heldPosition.inMicroseconds / Duration.microsecondsPerSecond;
      debugPrint(
        '[LumiPlayer] sync cache-end=$cacheEnd held=${positionSeconds.toStringAsFixed(1)}s',
      );
    } finally {
      if (!_closed) await held.player.play();
    }

    if (pictureSide) {
      pictureDelay += added;
    } else {
      voiceDelay += added;
    }
    debugPrint(
      '[LumiPlayer] sync done added=${added.inMilliseconds}ms '
      'picture=${pictureDelay.inMilliseconds}ms '
      'voice=${voiceDelay.inMilliseconds}ms',
    );
    _message('画面延迟 ${_seconds(pictureDelay)}s，声音延迟 ${_seconds(voiceDelay)}s');
  }

  String _seconds(Duration value) =>
      (value.inMilliseconds / 1000).toStringAsFixed(1);

  // ------------------------------------------------------------------ 生命周期

  Future<void> _release() async {
    _progressTimer?.cancel();
    _resetProgress();
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
    progress.dispose();
  }
}
