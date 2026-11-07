import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:flutter/widgets.dart';

import '../domain/playback_engine.dart';

/// media_kit 播放引擎实现（data 层适配器）。
class MediaKitPlaybackEngine implements VideoPlaybackEngine {
  MediaKitPlaybackEngine() {
    _player = Player();
    _controller = VideoController(_player);
  }

  late final Player _player;
  late final VideoController _controller;
  double _volume = 1;

  Player get player => _player;
  VideoController get videoController => _controller;

  @override
  Future<void> open(
    String source, {
    Duration startAt = Duration.zero,
    bool autoPlay = true,
  }) async {
    await _player.open(Media(source), play: autoPlay);
    if (startAt > Duration.zero) {
      try {
        await _player.stream.duration
            .firstWhere((Duration value) => value > Duration.zero)
            .timeout(const Duration(seconds: 6));
        await _player.seek(startAt);
      } on Object {
        // 定位失败时从头播放，不阻断播放流程。
      }
    }
    await _player.setVolume(_volume * 100);
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> setSpeed(double speed) => _player.setRate(speed);

  @override
  Future<void> setVolume(double volume) async {
    _volume = volume.clamp(0, 1);
    await _player.setVolume(_volume * 100);
  }

  @override
  Future<void> dispose() async {
    await _player.dispose();
  }

  @override
  Stream<Duration> get positionStream => _player.stream.position;

  @override
  Stream<Duration> get durationStream => _player.stream.duration;

  @override
  Stream<bool> get playingStream => _player.stream.playing;

  @override
  Stream<bool> get bufferingStream => _player.stream.buffering;

  @override
  Stream<bool> get completedStream => _player.stream.completed;

  @override
  Stream<String> get errorStream => _player.stream.error;

  @override
  Duration get position => _player.state.position;

  @override
  Duration get duration => _player.state.duration;

  @override
  bool get isPlaying => _player.state.playing;

  @override
  double get speed => _player.state.rate;
}

/// 渲染层：把引擎的视频输出挂到 Widget 树上。
///
/// 只有 media_kit 引擎有真实画面，其他实现（测试替身）返回黑色占位。
class VideoSurface extends StatelessWidget {
  const VideoSurface({
    super.key,
    required this.engine,
    this.fit = BoxFit.contain,
  });

  final VideoPlaybackEngine engine;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    if (engine is MediaKitPlaybackEngine) {
      return Video(
        controller: (engine as MediaKitPlaybackEngine).videoController,
        fit: fit,
        controls: NoVideoControls,
        wakelock: false,
      );
    }
    return const ColoredBox(color: Color(0xFF000000));
  }
}
