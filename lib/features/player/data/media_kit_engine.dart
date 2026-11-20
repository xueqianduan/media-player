// -------------------------------------------------------------------------
// 功能：media_kit 播放实现
//
// 主要内容：
// - VideoPlaybackEngine 的具体实现
// - 视频渲染组件 VideoSurface
// - 截图等扩展能力
// -------------------------------------------------------------------------

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:flutter/widgets.dart';

import '../domain/playback_engine.dart';
import '../domain/playback_tracks.dart';

/// media_kit 播放引擎实现（data 层适配器）。
class MediaKitPlaybackEngine implements VideoPlaybackEngine {
  MediaKitPlaybackEngine() {
    _player = Player();
    _controller = VideoController(_player);
    _trackListSubscription = _player.stream.tracks.listen(_replaceTracks);
  }

  late final Player _player;
  late final VideoController _controller;
  late final StreamSubscription<Tracks> _trackListSubscription;
  final StreamController<PlaybackSubtitles> _subtitlesController =
      StreamController<PlaybackSubtitles>.broadcast();
  List<SubtitleTrackInfo> _subtitleTracks = const <SubtitleTrackInfo>[];
  SubtitleSelection _subtitleSelection = const SubtitleSelection.auto();
  PlaybackSubtitles _subtitles = const PlaybackSubtitles.loading();
  bool _subtitlesLoading = true;
  double _volume = 1;

  Player get player => _player;
  VideoController get videoController => _controller;

  @override
  Future<void> open(
    String source, {
    Duration startAt = Duration.zero,
    bool autoPlay = true,
  }) async {
    _subtitlesLoading = true;
    _subtitleTracks = const <SubtitleTrackInfo>[];
    _subtitleSelection = const SubtitleSelection.auto();
    _publishSubtitles();

    final Stopwatch watch = Stopwatch()..start();
    try {
      await _player.open(Media(source), play: autoPlay);
      // open() 返回只代表命令被接受，不代表真的解析出了媒体。
      // 这里必须等到有效时长，否则界面会停在 00:00 + 转圈。
      final Duration total = await _waitForDuration();
      debugPrint(
        '[LumiPlayer] open ${_shortPath(source)} '
        'cost=${watch.elapsedMilliseconds}ms '
        'duration=${total.inMilliseconds}ms '
        'size=${_player.state.width}x${_player.state.height}',
      );
      if (total <= Duration.zero) {
        throw const PlaybackException('视频解析失败：读不到时长，文件可能损坏或格式不受支持');
      }
      if (startAt > Duration.zero) {
        Duration target = startAt;
        if (target > total) target = total;
        try {
          await _player.seek(target).timeout(const Duration(seconds: 8));
        } on Object {
          // 定位失败时继续从头播放，不阻断播放流程。
        }
      }
      // 同结构文件之间 mpv 可能沿用上一条显式轨道，换片时主动恢复自动。
      try {
        await _player.setSubtitleTrack(SubtitleTrack.auto());
      } on Object catch (error) {
        debugPrint('[LumiPlayer] reset subtitle track failed: $error');
      }
      await _player.setVolume(_volume * 100);
    } finally {
      _subtitlesLoading = false;
      _subtitleSelection = const SubtitleSelection.auto();
      _replaceTracks(_player.state.tracks);
    }
  }

  /// 轮询等待时长就绪，最多 10 秒（大文件解析可能偏慢）。
  Future<Duration> _waitForDuration() async {
    for (int i = 0; i < 100; i++) {
      final Duration value = _player.state.duration;
      if (value > Duration.zero) return value;
      // 已经能拿到分辨率，说明媒体至少解析成功了一部分，提前返回。
      if ((_player.state.width ?? 0) > 0) return value;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    return _player.state.duration;
  }

  /// 日志里只保留文件名，避免整条路径刷屏。
  String _shortPath(String path) {
    final int index = path.lastIndexOf(RegExp(r'[/\\]'));
    return index < 0 ? path : path.substring(index + 1);
  }

  /// 抓取当前视频帧（不含控制层与手势层），返回 JPEG 字节。
  ///
  /// 优先让 mpv 自己把帧写成文件：内置的 `screenshot()` 会在 isolate 里逐像素
  /// 编码，安卓上又慢又容易失败。写文件失败再回退到内置实现。
  Future<Uint8List?> screenshot() async {
    try {
      final Directory directory = await getTemporaryDirectory();
      final String path =
          '${directory.path}/reelbox_shot_'
          '${DateTime.now().millisecondsSinceEpoch}.jpg';
      // NativePlayer 的 command 不在 PlatformPlayer 接口里，用 dynamic 调用。
      final dynamic platform = _player.platform;
      await platform?.command('screenshot-to-file', <String>[path, 'video']);
      final File file = File(path);
      // mpv 命令返回后文件一般已写完，这里再等一小会儿兜底。
      for (int i = 0; i < 5; i++) {
        if (await file.exists()) break;
        await Future<void>.delayed(const Duration(milliseconds: 60));
      }
      if (await file.exists()) {
        final Uint8List bytes = await file.readAsBytes();
        await file.delete();
        debugPrint('[LumiPlayer] screenshot ok, ${bytes.length} bytes');
        if (bytes.isNotEmpty) return bytes;
      }
      debugPrint('[LumiPlayer] screenshot-to-file produced no file');
    } on Object catch (error) {
      debugPrint('[LumiPlayer] screenshot-to-file failed: $error');
    }

    try {
      final Uint8List? bytes = await _player.screenshot(format: 'image/jpeg');
      debugPrint(
        '[LumiPlayer] screenshot fallback ${bytes?.length ?? 0} bytes',
      );
      return bytes;
    } on Object catch (error) {
      debugPrint('[LumiPlayer] screenshot fallback failed: $error');
      return null;
    }
  }

  void _replaceTracks(Tracks tracks) {
    final List<SubtitleTrackInfo> visible = <SubtitleTrackInfo>[];
    for (final SubtitleTrack track in tracks.subtitle) {
      // auto / no 是库提供的虚拟选项，外挂字幕也不在首版范围内。
      if (track.id == 'auto' || track.id == 'no' || track.uri || track.data) {
        continue;
      }
      visible.add(
        SubtitleTrackInfo(
          id: track.id,
          title: track.title,
          language: track.language,
          codec: track.codec,
          isDefault: track.isDefault ?? false,
          isImage: track.image ?? false,
        ),
      );
    }
    _subtitleTracks = List<SubtitleTrackInfo>.unmodifiable(visible);
    _publishSubtitles();
  }

  void _publishSubtitles() {
    _subtitles = PlaybackSubtitles(
      tracks: _subtitleTracks,
      selection: _subtitleSelection,
      loading: _subtitlesLoading,
    );
    if (!_subtitlesController.isClosed) {
      _subtitlesController.add(_subtitles);
    }
  }

  Future<void> _applySubtitleTrack(
    SubtitleTrack track,
    SubtitleSelection selection,
  ) async {
    try {
      await _player.setSubtitleTrack(track);
    } on Object catch (error) {
      debugPrint('[LumiPlayer] select subtitle failed: $error');
      throw const PlaybackException('切换字幕失败');
    }
    _subtitleSelection = selection;
    _publishSubtitles();
  }

  @override
  Future<void> selectSubtitleTrack(String trackId) async {
    if (_subtitlesLoading) {
      throw const PlaybackException('字幕轨道仍在读取');
    }
    SubtitleTrackInfo? info;
    for (final SubtitleTrackInfo track in _subtitleTracks) {
      if (track.id == trackId) {
        info = track;
        break;
      }
    }
    if (info == null) {
      throw const PlaybackException('字幕轨道已失效');
    }
    if (!info.supportsTextRendering) {
      throw const PlaybackException('图片字幕暂不支持');
    }
    SubtitleTrack? target;
    for (final SubtitleTrack track in _player.state.tracks.subtitle) {
      if (track.id == trackId && !track.uri && !track.data) {
        target = track;
        break;
      }
    }
    if (target == null) {
      throw const PlaybackException('字幕轨道已失效');
    }
    await _applySubtitleTrack(target, SubtitleSelection.track(trackId));
  }

  @override
  Future<void> selectAutomaticSubtitle() {
    return _applySubtitleTrack(
      SubtitleTrack.auto(),
      const SubtitleSelection.auto(),
    );
  }

  @override
  Future<void> disableSubtitles() {
    return _applySubtitleTrack(
      SubtitleTrack.no(),
      const SubtitleSelection.off(),
    );
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
    await _trackListSubscription.cancel();
    await _subtitlesController.close();
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
  Stream<PlaybackSubtitles> get subtitlesStream => _subtitlesController.stream;

  @override
  PlaybackSubtitles get subtitles => _subtitles;

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
    this.subtitlePadding = const EdgeInsets.fromLTRB(20, 0, 20, 24),
  });

  final VideoPlaybackEngine engine;
  final BoxFit fit;
  final EdgeInsets subtitlePadding;

  static const TextStyle _subtitleStyle = TextStyle(
    height: 1.32,
    fontSize: 30,
    letterSpacing: 0,
    wordSpacing: 0,
    color: Color(0xFFFFFFFF),
    fontWeight: FontWeight.w500,
    backgroundColor: Color(0xB3000000),
    shadows: <Shadow>[
      Shadow(color: Color(0xFF000000), blurRadius: 3, offset: Offset(0, 1)),
    ],
  );

  @override
  Widget build(BuildContext context) {
    if (engine is MediaKitPlaybackEngine) {
      return Video(
        controller: (engine as MediaKitPlaybackEngine).videoController,
        fit: fit,
        controls: NoVideoControls,
        wakelock: false,
        subtitleViewConfiguration: SubtitleViewConfiguration(
          style: _subtitleStyle,
          padding: subtitlePadding,
        ),
      );
    }
    return const ColoredBox(color: Color(0xFF000000));
  }
}
