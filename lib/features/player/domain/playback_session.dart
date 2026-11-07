import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../library/domain/models.dart';
import 'playback_engine.dart';
import 'playback_queue.dart';

/// 进度保存回调（由 Application 层落库）。
typedef ProgressSaver =
    void Function({
      required String mediaId,
      required int positionMs,
      required int durationMs,
      required bool completed,
    });

/// 播放源解析：相册资源需要先换取本地文件路径。
typedef SourceResolver = Future<String?> Function(MediaItem item);

/// 播放会话：统一管理播放引擎、播放队列与进度记忆。
///
/// 高频进度只更新 [position]，不触发整页重建。
class PlaybackSession {
  PlaybackSession({
    required this.engine,
    required this.queue,
    required this.mediaById,
    required this.resolveSource,
    required this.onSaveProgress,
    double initialSpeed = 1.0,
  }) : speed = ValueNotifier<double>(initialSpeed) {
    _subscriptions.addAll(<StreamSubscription<dynamic>>[
      engine.positionStream.listen((Duration value) {
        position.value = value;
      }),
      engine.durationStream.listen((Duration value) {
        if (value > Duration.zero) duration.value = value;
      }),
      engine.playingStream.listen((bool value) {
        playing.value = value;
        if (status.value != PlaybackStatus.initializing &&
            status.value != PlaybackStatus.error &&
            status.value != PlaybackStatus.completed) {
          status.value = value ? PlaybackStatus.playing : PlaybackStatus.paused;
        }
      }),
      engine.bufferingStream.listen((bool value) {
        buffering.value = value;
      }),
      engine.completedStream.listen((bool value) {
        if (value) {
          unawaited(_handleCompleted());
        }
      }),
      engine.errorStream.listen((String message) {
        error.value = '播放出错：$message';
        status.value = PlaybackStatus.error;
      }),
    ]);
    _autoSaveTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (playing.value) saveProgress();
    });
  }

  final VideoPlaybackEngine engine;
  final PlaybackQueue queue;
  final Map<String, MediaItem> mediaById;
  final SourceResolver resolveSource;
  final ProgressSaver onSaveProgress;

  final ValueNotifier<Duration> position = ValueNotifier<Duration>(
    Duration.zero,
  );
  final ValueNotifier<Duration> duration = ValueNotifier<Duration>(
    Duration.zero,
  );
  final ValueNotifier<bool> playing = ValueNotifier<bool>(false);
  final ValueNotifier<bool> buffering = ValueNotifier<bool>(false);
  final ValueNotifier<double> speed;
  final ValueNotifier<String?> error = ValueNotifier<String?>(null);
  final ValueNotifier<String?> currentMediaId = ValueNotifier<String?>(null);
  final ValueNotifier<PlaybackStatus> status = ValueNotifier<PlaybackStatus>(
    PlaybackStatus.idle,
  );

  final List<StreamSubscription<dynamic>> _subscriptions =
      <StreamSubscription<dynamic>>[];
  Timer? _autoSaveTimer;
  bool _disposed = false;
  bool _opening = false;

  MediaItem? get currentItem {
    final String? id = currentMediaId.value;
    return id == null ? null : mediaById[id];
  }

  String get currentTitle => currentItem?.displayName ?? '';

  /// 开始播放。[startAt] 为空时从头播放。
  Future<void> start({Duration? startAt}) async {
    await _openCurrent(startAt: startAt ?? Duration.zero);
  }

  Future<void> _openCurrent({
    required Duration startAt,
    bool autoPlay = true,
  }) async {
    if (_disposed || _opening) return;
    final String? id = queue.currentId;
    if (id == null) {
      error.value = '播放队列为空';
      status.value = PlaybackStatus.error;
      return;
    }
    final MediaItem? item = mediaById[id];
    if (item == null) {
      error.value = '视频记录不存在';
      status.value = PlaybackStatus.error;
      return;
    }

    _opening = true;
    currentMediaId.value = id;
    completed.value = false;
    error.value = null;
    position.value = Duration.zero;
    duration.value = Duration.zero;
    status.value = PlaybackStatus.initializing;
    try {
      final String? source = await resolveSource(item);
      if (source == null || source.isEmpty) {
        throw const PlaybackException('视频文件不存在或访问权限已失效');
      }
      await engine.open(source, startAt: startAt, autoPlay: autoPlay);
      await engine.setSpeed(speed.value);
      status.value = autoPlay ? PlaybackStatus.playing : PlaybackStatus.paused;
    } on PlaybackException catch (exception) {
      error.value = exception.message;
      status.value = PlaybackStatus.error;
    } on Object {
      error.value = '无法播放该视频，文件可能已损坏或格式不受支持';
      status.value = PlaybackStatus.error;
    } finally {
      _opening = false;
    }
  }

  final ValueNotifier<bool> completed = ValueNotifier<bool>(false);

  Future<void> _handleCompleted() async {
    completed.value = true;
    saveProgress(forceCompleted: true);
    final String? nextId = queue.next(auto: true);
    if (nextId == null) {
      playing.value = false;
      status.value = PlaybackStatus.completed;
      return;
    }
    await _openCurrent(startAt: Duration.zero);
  }

  Future<void> togglePlay() async {
    if (status.value == PlaybackStatus.error) {
      await _openCurrent(startAt: position.value);
      return;
    }
    if (completed.value) {
      await seekTo(Duration.zero);
      completed.value = false;
    }
    if (playing.value) {
      await engine.pause();
      saveProgress();
    } else {
      await engine.play();
    }
  }

  Future<void> seekTo(Duration target) async {
    final Duration max = duration.value;
    Duration value = target;
    if (value < Duration.zero) value = Duration.zero;
    if (max > Duration.zero && value > max) value = max;
    await engine.seek(value);
    position.value = value;
    if (value < max && completed.value) completed.value = false;
    saveProgress();
  }

  Future<void> seekBy(Duration delta) => seekTo(position.value + delta);

  Future<void> setSpeed(double value) async {
    speed.value = value;
    await engine.setSpeed(value);
  }

  Future<void> setVolume(double value) async {
    await engine.setVolume(value.clamp(0, 1));
  }

  Future<void> next() async {
    final String? id = queue.next();
    if (id == null) return;
    await _openCurrent(startAt: Duration.zero);
  }

  Future<void> previous() async {
    final String? id = queue.previous();
    if (id == null) {
      await seekTo(Duration.zero);
      return;
    }
    await _openCurrent(startAt: Duration.zero);
  }

  Future<void> jumpTo(int index) async {
    final String? id = queue.jumpTo(index);
    if (id == null) return;
    await _openCurrent(startAt: Duration.zero);
  }

  void setRepeatMode(RepeatMode mode) {
    queue.setRepeatMode(mode);
    repeatMode.value = mode;
  }

  final ValueNotifier<RepeatMode> repeatMode = ValueNotifier<RepeatMode>(
    RepeatMode.sequential,
  );

  /// 保存当前进度（暂停、拖动、退出、进后台时调用）。
  void saveProgress({bool forceCompleted = false}) {
    if (_disposed) return;
    final String? id = currentMediaId.value;
    if (id == null) return;
    final int total = duration.value.inMilliseconds;
    if (total <= 0) return;
    final int currentPosition = forceCompleted
        ? total
        : position.value.inMilliseconds.clamp(0, total);
    onSaveProgress(
      mediaId: id,
      positionMs: currentPosition,
      durationMs: total,
      completed: forceCompleted,
    );
  }

  Future<void> dispose() async {
    if (_disposed) return;
    saveProgress();
    _disposed = true;
    _autoSaveTimer?.cancel();
    for (final StreamSubscription<dynamic> subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    await engine.dispose();
    position.dispose();
    duration.dispose();
    playing.dispose();
    buffering.dispose();
    speed.dispose();
    error.dispose();
    currentMediaId.dispose();
    status.dispose();
    completed.dispose();
    repeatMode.dispose();
  }
}
