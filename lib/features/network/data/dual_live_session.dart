// -------------------------------------------------------------------------
// 功能：双路直播会话
//
// 主要内容：
// - 画面源 + 声音源的建立与线路回退
// - 声音切换、暂停、手动同步
// - 所有控制操作串行执行
// -------------------------------------------------------------------------

import 'dart:async';
import 'dart:convert';

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

  /// 画面进度：当前位置 + 播放器实际可定位区间。
  final ValueNotifier<LiveProgress> progress = ValueNotifier<LiveProgress>(
    const LiveProgress(),
  );

  Timer? _progressTimer;

  /// 当前连续可定位区间（来自 mpv `seekable-ranges`）。
  Duration _rangeStart = Duration.zero;
  Duration _rangeEnd = Duration.zero;
  bool _rangeKnown = false;

  /// 正在执行定位 / 正在重新取流回到直播。
  bool _seeking = false;
  bool _returning = false;

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

  LiveProgress _progressAt(
    Duration position, {
    bool seeking = false,
    bool returning = false,
    Duration? seekTarget,
  }) {
    return LiveProgress(
      position: position,
      rangeStart: _rangeStart,
      rangeEnd: _rangeEnd,
      available:
          _rangeKnown && _rangeEnd - _rangeStart > const Duration(seconds: 1),
      seeking: seeking,
      returning: returning,
      seekTarget: seekTarget,
    );
  }

  void _updateProgress() {
    final LiveLeg? video = picture;
    if (_closed || video == null || _seeking || _returning) return;

    progress.value = _progressAt(video.player.state.position);

    // 真实可定位区间每秒刷新一次；拖动 / 回直播期间不改，避免界面抖动。
    _progressTicks++;
    if (_progressTicks % 2 == 0) {
      unawaited(_refreshSeekableRange(video));
    }
  }

  /// 读取 mpv `seekable-ranges`，只保留当前播放位置所在的那一段。
  Future<void> _refreshSeekableRange(LiveLeg video) async {
    if (_closed || _seeking || _returning) return;
    final List<_SeekableRange>? ranges = await _readSeekableRanges(video);
    if (_closed || _seeking || _returning || ranges == null) return;

    final _SeekableRange? picked = _pickRange(
      ranges,
      video.player.state.position,
    );
    if (picked == null) {
      _rangeStart = Duration.zero;
      _rangeEnd = Duration.zero;
      _rangeKnown = false;
      return;
    }
    if (_rangeStart != picked.start || _rangeEnd != picked.end) {
      debugPrint(
        '[LumiPlayer] seekable range '
        '${picked.start.inMilliseconds}ms..${picked.end.inMilliseconds}ms',
      );
    }
    _rangeStart = picked.start;
    _rangeEnd = picked.end;
    _rangeKnown = true;
  }

  /// 读取真实可定位区间。返回 null 表示这次读取失败（保留上一次结果），
  /// 空列表表示播放器明确报告当前没有可 seek 的缓存。
  Future<List<_SeekableRange>?> _readSeekableRanges(LiveLeg leg) async {
    try {
      final String? state = await leg.property('demuxer-cache-state');
      if (state != null && state.isNotEmpty && state != 'no') {
        final Object? decoded = jsonDecode(state);
        if (decoded is Map) {
          final Object? rows = decoded['seekable-ranges'];
          if (rows is List) return _parseRanges(rows);
        }
      }

      // 兼容只提供 seekable-ranges 属性的 mpv 版本。
      final String? raw = await leg.property('seekable-ranges');
      if (raw != null && raw.isNotEmpty && raw != 'no') {
        final Object? decoded = jsonDecode(raw);
        if (decoded is List) return _parseRanges(decoded);
      }
    } on Object catch (error) {
      debugPrint('[LumiPlayer] seekable-ranges read failed: $error');
    }
    return null;
  }

  static List<_SeekableRange> _parseRanges(List<dynamic> rows) {
    final List<_SeekableRange> ranges = <_SeekableRange>[];
    for (final Object? row in rows) {
      if (row is! Map) continue;
      final Duration start = _secondsToDuration(row['start']);
      final Duration end = _secondsToDuration(row['end']);
      if (end <= start) continue;
      ranges.add(_SeekableRange(start, end));
    }
    ranges.sort(
      (_SeekableRange a, _SeekableRange b) => a.start.compareTo(b.start),
    );
    return ranges;
  }

  static Duration _secondsToDuration(Object? value) {
    final double? seconds = value is num
        ? value.toDouble()
        : double.tryParse('${value ?? ''}');
    if (seconds == null || seconds.isNaN || seconds <= 0) {
      return Duration.zero;
    }
    return Duration(milliseconds: (seconds * 1000).round());
  }

  /// 区间可能有缺口：只取包含当前位置的一段，不把多段拼成一段连续时间。
  static _SeekableRange? _pickRange(
    List<_SeekableRange> ranges,
    Duration position,
  ) {
    if (ranges.isEmpty) return null;
    for (final _SeekableRange range in ranges) {
      if (position >= range.start && position <= range.end) return range;
    }
    _SeekableRange? before;
    for (final _SeekableRange range in ranges) {
      if (range.start <= position) before = range;
    }
    return before ?? ranges.first;
  }

  void _resetProgress() {
    _rangeStart = Duration.zero;
    _rangeEnd = Duration.zero;
    _rangeKnown = false;
    _progressTicks = 0;
    _seeking = false;
    if (!_closed) {
      progress.value = LiveProgress(returning: _returning);
    }
  }

  // ------------------------------------------------------------------ 定位

  /// 在真实可定位区间内跳转；定位完成后还要确认画面确实到达目标。
  Future<void> seekTo(Duration target) {
    return _run(() async {
      final LiveLeg? video = picture;
      if (video == null) throw StateError('画面源尚未连接');
      if (_seeking || _returning) return;

      final List<_SeekableRange>? fresh = await _readSeekableRanges(video);
      final _SeekableRange? range = fresh == null
          ? (_rangeKnown ? _SeekableRange(_rangeStart, _rangeEnd) : null)
          : _pickRange(fresh, video.player.state.position);
      if (range == null) {
        throw StateError('当前线路没有可回看的缓存');
      }
      if (fresh != null) {
        _rangeStart = range.start;
        _rangeEnd = range.end;
        _rangeKnown = true;
      }

      final Duration guard = const Duration(milliseconds: 300);
      Duration maxTarget = range.end - guard;
      if (maxTarget < range.start) maxTarget = range.start;
      Duration clamped = target;
      if (clamped < range.start) clamped = range.start;
      if (clamped > maxTarget) clamped = maxTarget;

      final Duration before = video.player.state.position;
      if ((clamped - before).abs() < const Duration(milliseconds: 250)) {
        return;
      }

      final bool wasPaused = paused.value;
      _seeking = true;
      // 先显示目标位置与“定位中”，确认落点后再提交真实位置。
      progress.value = _progressAt(clamped, seeking: true, seekTarget: clamped);

      try {
        await _seekLeg(video, clamped);
        if (!wasPaused) await video.player.play();

        final LiveLeg? audio = voice;
        if (audio != null && usingVoice.value) {
          await _seekVoice(audio, before - clamped);
        }

        final Duration actual = await _waitSeekSettled(
          video,
          clamped,
          expectPlaying: !wasPaused,
        );
        debugPrint(
          '[LumiPlayer] seek verified target=${clamped.inMilliseconds}ms '
          'actual=${actual.inMilliseconds}ms',
        );
      } on Object catch (error) {
        debugPrint('[LumiPlayer] seek failed: $error');
        throw StateError('定位失败：$error');
      } finally {
        _seeking = false;
        _updateProgress();
      }
    });
  }

  Future<void> _seekLeg(LiveLeg leg, Duration target) async {
    try {
      await leg.seekExact(target);
    } on Object catch (error) {
      debugPrint('[LumiPlayer] exact seek failed, fallback: $error');
      await leg.player.seek(target);
    }
  }

  /// 解说按画面相同的偏移跟随；先夹到它自己的可定位区间，失败只记录日志。
  Future<void> _seekVoice(LiveLeg audio, Duration delta) async {
    Duration target = audio.player.state.position - delta;
    if (target < Duration.zero) target = Duration.zero;

    final List<_SeekableRange>? ranges = await _readSeekableRanges(audio);
    if (ranges != null) {
      final _SeekableRange? range = _pickRange(
        ranges,
        audio.player.state.position,
      );
      if (range == null) {
        debugPrint('[LumiPlayer] voice has no seekable range');
        return;
      }
      final Duration guard = const Duration(milliseconds: 300);
      Duration maxTarget = range.end - guard;
      if (maxTarget < range.start) maxTarget = range.start;
      if (target < range.start) target = range.start;
      if (target > maxTarget) target = maxTarget;
    }

    try {
      await _seekLeg(audio, target);
      if (!paused.value) await audio.player.play();
      await _waitSeekSettled(
        audio,
        target,
        expectPlaying: !paused.value,
        timeout: const Duration(seconds: 4),
      );
      debugPrint(
        '[LumiPlayer] voice seek verified target=${target.inMilliseconds}ms',
      );
    } on Object catch (error) {
      debugPrint('[LumiPlayer] voice seek failed: $error');
    }
  }

  /// 等待定位真正结束：seeking 关闭、位置接近目标，并且（播放中时）位置继续前进。
  Future<Duration> _waitSeekSettled(
    LiveLeg leg,
    Duration target, {
    required bool expectPlaying,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final Stopwatch watch = Stopwatch()..start();
    Duration last = leg.player.state.position;

    while (watch.elapsed < timeout) {
      _checkOpen();
      if (leg.error != null) {
        throw StateError('定位后播放器报错：${leg.error}');
      }

      final Duration position = leg.player.state.position;
      last = position;
      final bool seeking = await _isSeeking(leg);
      final bool buffering = leg.player.state.buffering;
      final Duration diff = (position - target).abs();

      final bool settled =
          !seeking &&
          (!expectPlaying || !buffering) &&
          diff <= const Duration(seconds: 3);
      if (settled) {
        if (!expectPlaying) return position;
        await Future<void>.delayed(const Duration(milliseconds: 250));
        final Duration next = leg.player.state.position;
        if (next > position) return next;
      }

      await Future<void>.delayed(const Duration(milliseconds: 120));
    }

    throw TimeoutException(
      '定位未完成（目标 ${target.inMilliseconds}ms，当前 ${last.inMilliseconds}ms）',
    );
  }

  Future<bool> _isSeeking(LiveLeg leg) async {
    final String? raw = await leg.property('seeking');
    if (raw == null) return false;
    final String value = raw.trim().toLowerCase();
    return value == 'yes' || value == 'true' || value == '1';
  }

  /// 回到直播：本地缓存末尾不等于直播最新位置，重新取流才可靠。
  Future<void> goLive() {
    return _run(() async {
      final LiveLeg? video = picture;
      if (video == null) throw StateError('画面源尚未连接');
      if (_returning) return;

      final bool wasUsingVoice = usingVoice.value && voice != null;
      _returning = true;
      _seeking = false;
      progress.value = _progressAt(
        _rangeKnown ? _rangeEnd : video.player.state.position,
        returning: true,
      );
      _message('正在回到直播…');

      try {
        // 重新取流并打开当前直播点，成功后才算回到直播。
        await _reopenPicture(message: '画面已重连，正在对齐声音…');

        bool voiceFailed = false;
        if (wasUsingVoice && voiceRoom != null) {
          try {
            await _reopenVoice();
            await _applySound(official: false);
          } on Object catch (error) {
            debugPrint('[LumiPlayer] goLive voice reconnect failed: $error');
            voice = null;
            voiceFailure = '$error';
            voiceFailed = true;
            await _applySound(official: true);
          }
        } else {
          await _applySound(official: true);
        }

        paused.value = false;
        for (final LiveLeg? leg in <LiveLeg?>[picture, voice]) {
          if (leg != null) await leg.player.play();
        }

        _returning = false;
        _resetProgress();
        _updateProgress();
        _message(voiceFailed ? '画面已回到直播，解说回连失败，已切到原声' : '已回到直播');
      } on Object {
        _returning = false;
        final LiveLeg? current = picture;
        progress.value = current == null
            ? const LiveProgress()
            : _progressAt(current.player.state.position);
        _message('回到直播失败，请重试');
        rethrow;
      }
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

      _returning = false;
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
  Future<void> refreshPicture() => _run(_reopenPicture);

  /// 重新解析地址并只重建画面这一路；声音源保持不动。
  Future<void> _reopenPicture({String message = '直播中'}) async {
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
    // 新流从当前直播点开始，旧同步偏移与可定位区间都不再成立。
    pictureDelay = Duration.zero;
    _resetProgress();
    // 回到直播时先用原声顶上，等解说重连成功后再切回，避免中间静音。
    await _applySound(
      official: _returning || voice == null || !usingVoice.value,
    );
    if (paused.value) await picture?.player.pause();
    _message(message);
  }

  /// 回到直播时重新连接声音源，确保解说也停在最新位置。
  Future<void> _reopenVoice() async {
    final LiveRoom? room = voiceRoom;
    if (room == null) throw StateError('还没有声音源');

    final LiveLeg? old = voice;
    voice = null;
    if (old != null) {
      _owned.remove(old);
      await old.close().timeout(const Duration(seconds: 8), onTimeout: () {});
    }

    final LiveLeg leg = await _connect(room, asPicture: false);
    _checkOpen();
    voice = leg;
    voiceFailure = null;
    // 新解说流从当前直播点开始，旧的同步偏移不再成立。
    voiceDelay = Duration.zero;
    if (paused.value) await leg.player.pause();
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
    _returning = false;
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

/// mpv `seekable-ranges` 中的一段连续可定位区间。
class _SeekableRange {
  const _SeekableRange(this.start, this.end);

  final Duration start;
  final Duration end;

  @override
  String toString() => '${start.inMilliseconds}ms..${end.inMilliseconds}ms';
}
