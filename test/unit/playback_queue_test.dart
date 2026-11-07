import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:myplayer/features/library/domain/models.dart';
import 'package:myplayer/features/player/domain/playback_queue.dart';

void main() {
  group('顺序播放', () {
    test('逐条前进，播放到末尾后停止', () {
      final PlaybackQueue queue = PlaybackQueue(
        mediaIds: <String>['a', 'b', 'c'],
      );
      expect(queue.currentId, 'a');
      expect(queue.next(), 'b');
      expect(queue.next(), 'c');
      expect(queue.next(), isNull);
      expect(queue.currentId, 'c');
      expect(queue.hasNext, isFalse);
    });

    test('第一首上一曲返回空，由播放器重播当前视频', () {
      final PlaybackQueue queue = PlaybackQueue(mediaIds: <String>['a', 'b']);
      expect(queue.previous(), isNull);
      expect(queue.next(), 'b');
      expect(queue.previous(), 'a');
    });

    test('从指定视频开始播放', () {
      final PlaybackQueue queue = PlaybackQueue(
        mediaIds: <String>['a', 'b', 'c'],
        startIndex: 1,
      );
      expect(queue.currentId, 'b');
      expect(queue.index, 1);
    });

    test('越界索引被收敛到合法范围', () {
      final PlaybackQueue queue = PlaybackQueue(
        mediaIds: <String>['a', 'b'],
        startIndex: 9,
      );
      expect(queue.index, 1);
    });
  });

  group('循环模式', () {
    test('列表循环从末尾回到开头', () {
      final PlaybackQueue queue = PlaybackQueue(
        mediaIds: <String>['a', 'b'],
        repeatMode: RepeatMode.loopAll,
      );
      expect(queue.next(), 'b');
      expect(queue.next(), 'a');
      expect(queue.hasNext, isTrue);
    });

    test('单曲循环自动续播返回同一视频，手动下一首仍前进', () {
      final PlaybackQueue queue = PlaybackQueue(
        mediaIds: <String>['a', 'b'],
        repeatMode: RepeatMode.loopOne,
      );
      expect(queue.next(auto: true), 'a');
      expect(queue.currentId, 'a');
      expect(queue.next(), 'b');
    });

    test('循环模式下上一曲从第一首跳到末尾', () {
      final PlaybackQueue queue = PlaybackQueue(
        mediaIds: <String>['a', 'b', 'c'],
        repeatMode: RepeatMode.loopAll,
      );
      expect(queue.previous(), 'c');
    });

    test('随机模式包含全部视频且以当前视频开始', () {
      final PlaybackQueue queue = PlaybackQueue(
        mediaIds: <String>['a', 'b', 'c', 'd'],
        startIndex: 2,
        repeatMode: RepeatMode.shuffle,
        random: Random(7),
      );
      expect(queue.currentId, 'c');
      expect(queue.order.length, 4);
      expect(queue.order.toSet(), <String>{'a', 'b', 'c', 'd'});
      expect(queue.order.first, 'c');
      expect(queue.next(), isNotNull);
    });

    test('切换到随机模式后仍然保持当前视频', () {
      final PlaybackQueue queue = PlaybackQueue(
        mediaIds: <String>['a', 'b', 'c'],
        startIndex: 1,
      );
      queue.setRepeatMode(RepeatMode.shuffle);
      expect(queue.currentId, 'b');
      expect(queue.order.first, 'b');
    });
  });

  group('队列编辑', () {
    test('跳转到指定位置', () {
      final PlaybackQueue queue = PlaybackQueue(
        mediaIds: <String>['a', 'b', 'c'],
      );
      expect(queue.jumpTo(2), 'c');
      expect(queue.jumpTo(5), isNull);
      expect(queue.currentId, 'c');
    });

    test('播放列表变化时尽量保持当前视频不变', () {
      final PlaybackQueue queue = PlaybackQueue(
        mediaIds: <String>['a', 'b', 'c'],
      );
      queue.jumpTo(1);
      queue.replaceItems(<String>['x', 'b', 'y']);
      expect(queue.currentId, 'b');
      expect(queue.index, 1);
    });

    test('当前视频被删除时回到合法位置', () {
      final PlaybackQueue queue = PlaybackQueue(
        mediaIds: <String>['a', 'b', 'c'],
      );
      queue.jumpTo(2);
      queue.replaceItems(<String>['a', 'b']);
      expect(queue.index, lessThan(2));
      expect(queue.currentId, isNotNull);
    });
  });

  group('播放完成判定', () {
    test('95% 阈值与 15 秒续播阈值', () {
      final PlaybackProgress short = PlaybackProgress(
        mediaId: 'a',
        positionMs: 10000,
        durationMs: 100000,
        lastPlayedAt: DateTime(2025),
      );
      expect(short.shouldResume, isFalse);

      final PlaybackProgress record = PlaybackProgress(
        mediaId: 'b',
        positionMs: 16000,
        durationMs: 100000,
        lastPlayedAt: DateTime(2025),
      );
      expect(record.shouldResume, isTrue);
      expect(record.isFinished, isFalse);

      final PlaybackProgress finished = PlaybackProgress(
        mediaId: 'c',
        positionMs: 95000,
        durationMs: 100000,
        lastPlayedAt: DateTime(2025),
      );
      expect(finished.isFinished, isTrue);
    });
  });
}
