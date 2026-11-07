import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:myplayer/features/library/domain/models.dart';
import 'package:myplayer/features/player/domain/playback_engine.dart';
import 'package:myplayer/features/player/domain/playback_queue.dart';
import 'package:myplayer/features/player/domain/playback_session.dart';

void main() {
  late _FakeEngine engine;
  late List<_SavedProgress> saved;
  late PlaybackSession session;

  MediaItem item(String id) => MediaItem(
    id: id,
    folderId: 'f',
    sourceType: MediaSourceType.imported,
    sourceId: 'imported:$id',
    sourceLocator: '/videos/$id.mp4',
    displayName: id,
    originalName: '$id.mp4',
    mimeType: 'video/mp4',
    durationMs: 100000,
    width: 1920,
    height: 1080,
    fileSize: 1024,
    createdAt: DateTime(2025),
    updatedAt: DateTime(2025),
  );

  setUp(() {
    engine = _FakeEngine();
    saved = <_SavedProgress>[];
    session = PlaybackSession(
      engine: engine,
      queue: PlaybackQueue(
        mediaIds: <String>['a', 'b'],
        repeatMode: RepeatMode.sequential,
      ),
      mediaById: <String, MediaItem>{'a': item('a'), 'b': item('b')},
      resolveSource: (MediaItem media) async => '/resolved/${media.id}.mp4',
      onSaveProgress:
          ({
            required String mediaId,
            required int positionMs,
            required int durationMs,
            required bool completed,
          }) {
            saved.add(
              _SavedProgress(
                mediaId: mediaId,
                positionMs: positionMs,
                durationMs: durationMs,
                completed: completed,
              ),
            );
          },
    );
  });

  tearDown(() async {
    await session.dispose();
  });

  test('开始播放时打开解析后的本地路径', () async {
    await session.start();

    expect(engine.opened, <String>['/resolved/a.mp4']);
    expect(session.currentMediaId.value, 'a');
    expect(engine.playing, isTrue);
  });

  test('暂停时立即保存当前进度', () async {
    await session.start();
    engine.emitDuration(const Duration(seconds: 100));
    engine.emitPosition(const Duration(seconds: 42));
    await Future<void>.delayed(Duration.zero);

    await session.togglePlay(); // 正在播放 → 暂停

    expect(saved, isNotEmpty);
    expect(saved.last.mediaId, 'a');
    expect(saved.last.positionMs, 42000);
    expect(saved.last.durationMs, 100000);
    expect(saved.last.completed, isFalse);
  });

  test('播放完成写入已看完并自动播放下一集', () async {
    await session.start();
    engine.emitDuration(const Duration(seconds: 100));
    engine.emitPosition(const Duration(seconds: 99));

    engine.emitCompleted();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(saved.any((_SavedProgress p) => p.completed), isTrue);
    expect(engine.opened.last, '/resolved/b.mp4');
    expect(session.currentMediaId.value, 'b');
  });

  test('顺序播放到最后一集后停止', () async {
    await session.start();
    await session.next();
    expect(session.currentMediaId.value, 'b');

    engine.emitDuration(const Duration(seconds: 100));
    engine.emitCompleted();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(engine.opened.length, 2);
    expect(session.status.value, PlaybackStatus.completed);
  });

  test('单曲循环在播放结束后重播当前视频', () async {
    session.setRepeatMode(RepeatMode.loopOne);
    await session.start();
    engine.emitDuration(const Duration(seconds: 100));
    engine.emitCompleted();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(engine.opened.length, 2);
    expect(engine.opened.last, '/resolved/a.mp4');
  });

  test('视频不可访问时给出可读错误', () async {
    await session.dispose();
    session = PlaybackSession(
      engine: engine,
      queue: PlaybackQueue(mediaIds: <String>['a']),
      mediaById: <String, MediaItem>{'a': item('a')},
      resolveSource: (MediaItem media) async => null,
      onSaveProgress:
          ({
            required String mediaId,
            required int positionMs,
            required int durationMs,
            required bool completed,
          }) {},
    );

    await session.start();

    expect(session.error.value, contains('不存在'));
    expect(session.status.value, PlaybackStatus.error);
    expect(engine.opened, isEmpty);
  });
}

class _SavedProgress {
  const _SavedProgress({
    required this.mediaId,
    required this.positionMs,
    required this.durationMs,
    required this.completed,
  });

  final String mediaId;
  final int positionMs;
  final int durationMs;
  final bool completed;
}

class _FakeEngine implements VideoPlaybackEngine {
  final StreamController<Duration> _position =
      StreamController<Duration>.broadcast();
  final StreamController<Duration> _duration =
      StreamController<Duration>.broadcast();
  final StreamController<bool> _playing = StreamController<bool>.broadcast();
  final StreamController<bool> _buffering = StreamController<bool>.broadcast();
  final StreamController<bool> _completed = StreamController<bool>.broadcast();
  final StreamController<String> _error = StreamController<String>.broadcast();

  final List<String> opened = <String>[];
  bool playing = false;
  double _speed = 1;
  Duration _positionValue = Duration.zero;
  Duration _durationValue = Duration.zero;

  void emitPosition(Duration value) {
    _positionValue = value;
    _position.add(value);
  }

  void emitDuration(Duration value) {
    _durationValue = value;
    _duration.add(value);
  }

  void emitCompleted() => _completed.add(true);

  @override
  Future<void> open(
    String source, {
    Duration startAt = Duration.zero,
    bool autoPlay = true,
  }) async {
    opened.add(source);
    emitDuration(const Duration(seconds: 100));
    if (startAt > Duration.zero) {
      emitPosition(startAt);
    }
    playing = autoPlay;
    _playing.add(autoPlay);
  }

  @override
  Future<void> play() async {
    playing = true;
    _playing.add(true);
  }

  @override
  Future<void> pause() async {
    playing = false;
    _playing.add(false);
  }

  @override
  Future<void> seek(Duration position) async => emitPosition(position);

  @override
  Future<void> setSpeed(double speed) async => _speed = speed;

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> dispose() async {
    await _position.close();
    await _duration.close();
    await _playing.close();
    await _buffering.close();
    await _completed.close();
    await _error.close();
  }

  @override
  Stream<Duration> get positionStream => _position.stream;

  @override
  Stream<Duration> get durationStream => _duration.stream;

  @override
  Stream<bool> get playingStream => _playing.stream;

  @override
  Stream<bool> get bufferingStream => _buffering.stream;

  @override
  Stream<bool> get completedStream => _completed.stream;

  @override
  Stream<String> get errorStream => _error.stream;

  @override
  Duration get position => _positionValue;

  @override
  Duration get duration => _durationValue;

  @override
  bool get isPlaying => playing;

  @override
  double get speed => _speed;
}
