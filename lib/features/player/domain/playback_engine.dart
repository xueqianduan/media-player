/// 播放器状态机（与具体播放引擎解耦）。
enum PlaybackStatus {
  idle,
  initializing,
  ready,
  playing,
  paused,
  buffering,
  completed,
  error,
}

/// 统一的播放引擎接口。
///
/// 播放器 UI 只依赖该接口，实际实现（media_kit）放在 data 层。
abstract interface class VideoPlaybackEngine {
  Future<void> open(
    String source, {
    Duration startAt = Duration.zero,
    bool autoPlay = true,
  });

  Future<void> play();

  Future<void> pause();

  Future<void> seek(Duration position);

  Future<void> setSpeed(double speed);

  Future<void> setVolume(double volume);

  Future<void> dispose();

  Stream<Duration> get positionStream;

  Stream<Duration> get durationStream;

  Stream<bool> get playingStream;

  Stream<bool> get bufferingStream;

  Stream<bool> get completedStream;

  Stream<String> get errorStream;

  Duration get position;

  Duration get duration;

  bool get isPlaying;

  double get speed;
}

/// 播放失败时对用户展示的统一异常文案。
class PlaybackException implements Exception {
  const PlaybackException(this.message);

  final String message;

  @override
  String toString() => message;
}
