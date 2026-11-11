// -------------------------------------------------------------------------
// 功能：播放队列
//
// 主要内容：
// - 上一首/下一首与循环模式
// - 队列增删与当前项维护
// -------------------------------------------------------------------------

import 'dart:math';

import '../../library/domain/models.dart';

/// 播放队列：负责顺序、列表循环、单曲循环与随机播放的索引推进。
///
/// 纯 Dart 实现，便于单元测试。
class PlaybackQueue {
  PlaybackQueue({
    required List<String> mediaIds,
    int startIndex = 0,
    RepeatMode repeatMode = RepeatMode.sequential,
    Random? random,
  }) : _repeatMode = repeatMode {
    final List<String> ids = mediaIds.toList();
    if (ids.isEmpty) {
      _order = <String>[];
      _index = 0;
      return;
    }
    final int safeIndex = startIndex.clamp(0, ids.length - 1);
    if (repeatMode == RepeatMode.shuffle) {
      final String current = ids[safeIndex];
      final List<String> rest = ids.where((String id) => id != current).toList()
        ..shuffle(random ?? Random());
      _order = <String>[current, ...rest];
      _index = 0;
    } else {
      _order = ids;
      _index = safeIndex;
    }
  }

  late final List<String> _order;
  int _index = 0;
  RepeatMode _repeatMode;

  List<String> get order => List<String>.unmodifiable(_order);
  int get index => _index;
  int get length => _order.length;
  bool get isEmpty => _order.isEmpty;
  RepeatMode get repeatMode => _repeatMode;

  String? get currentId => _order.isEmpty ? null : _order[_index];

  bool get hasNext {
    if (_order.isEmpty) return false;
    if (_repeatMode == RepeatMode.loopAll ||
        _repeatMode == RepeatMode.shuffle) {
      return true;
    }
    return _index < _order.length - 1;
  }

  bool get hasPrevious {
    if (_order.isEmpty) return false;
    if (_repeatMode == RepeatMode.loopAll ||
        _repeatMode == RepeatMode.shuffle) {
      return true;
    }
    return _index > 0;
  }

  void setRepeatMode(RepeatMode mode) {
    if (mode == _repeatMode) return;
    if (mode == RepeatMode.shuffle) {
      final String? current = currentId;
      final List<String> rest =
          _order.where((String id) => id != current).toList()..shuffle();
      _order
        ..clear()
        ..addAll(<String>[?current, ...rest]);
      _index = 0;
    }
    _repeatMode = mode;
  }

  /// 下一首。[auto] 为 true 表示播放结束自动续播（受单曲循环影响）。
  String? next({bool auto = false}) {
    if (_order.isEmpty) return null;
    if (auto && _repeatMode == RepeatMode.loopOne) {
      return currentId;
    }
    if (_index < _order.length - 1) {
      _index++;
      return currentId;
    }
    if (_repeatMode == RepeatMode.loopAll ||
        _repeatMode == RepeatMode.shuffle) {
      _index = 0;
      return currentId;
    }
    return null;
  }

  String? previous() {
    if (_order.isEmpty) return null;
    if (_index > 0) {
      _index--;
      return currentId;
    }
    if (_repeatMode == RepeatMode.loopAll ||
        _repeatMode == RepeatMode.shuffle) {
      _index = _order.length - 1;
      return currentId;
    }
    return null;
  }

  String? jumpTo(int index) {
    if (_order.isEmpty) return null;
    if (index < 0 || index >= _order.length) return null;
    _index = index;
    return currentId;
  }

  /// 播放列表在播放过程中被修改时保持当前视频尽量不变。
  void replaceItems(List<String> mediaIds) {
    final String? current = currentId;
    _order
      ..clear()
      ..addAll(mediaIds);
    if (_order.isEmpty) {
      _index = 0;
      return;
    }
    final int found = current == null ? -1 : _order.indexOf(current);
    _index = found >= 0 ? found : _index.clamp(0, _order.length - 1);
  }
}
