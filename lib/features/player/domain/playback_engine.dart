import 'playback_tracks.dart';

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

  /// 切换到当前文件中的指定内嵌字幕轨。
  Future<void> selectSubtitleTrack(String trackId);

  /// 恢复文件的自动选轨策略。
  Future<void> selectAutomaticSubtitle();

  /// 关闭字幕显示，不卸载文件里的字幕轨。
  Future<void> disableSubtitles();

  Future<void> dispose();

  Stream<Duration> get positionStream;

  Stream<Duration> get durationStream;

  Stream<bool> get playingStream;

  Stream<bool> get bufferingStream;

  Stream<bool> get completedStream;

  Stream<String> get errorStream;

  /// 当前视频的字幕轨道与选择状态。
  Stream<PlaybackSubtitles> get subtitlesStream;

  PlaybackSubtitles get subtitles;

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
