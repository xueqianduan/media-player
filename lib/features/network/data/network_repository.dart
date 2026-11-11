// -------------------------------------------------------------------------
// 功能：网络模块持久化
//
// 主要内容：
// - 收藏、双路组合、网络视频的读写
// -------------------------------------------------------------------------

import 'dart:async';

import '../../../core/database/local_database.dart';
import '../domain/live_models.dart';

/// 网络模块的持久化：收藏、双路组合、网络视频直链。
///
/// 只保存用户的选择，播放地址每次重新解析，避免存下会过期的直链。
class NetworkRepository {
  const NetworkRepository({required this.database});

  final LocalDatabase database;

  static const String _table = 'network';

  NetworkState load() {
    final Map<String, dynamic> raw = database.readTable(_table);
    if (raw.isEmpty) return const NetworkState();
    return NetworkState.fromJson(raw);
  }

  NetworkState _save(NetworkState state) {
    database.writeTable(_table, state.toJson());
    unawaited(database.flush());
    return state;
  }

  NetworkState toggleFavorite(NetworkState state, LiveRoom room) {
    final bool exists = state.isFavorite(room.roomId);
    final List<LiveFavorite> favorites = exists
        ? state.favorites
              .where((LiveFavorite item) => item.room.roomId != room.roomId)
              .toList()
        : <LiveFavorite>[
            LiveFavorite(room: room, savedAt: DateTime.now()),
            ...state.favorites,
          ];
    return _save(state.copyWith(favorites: favorites));
  }

  NetworkState removeFavorite(NetworkState state, int roomId) {
    return _save(
      state.copyWith(
        favorites: state.favorites
            .where((LiveFavorite item) => item.room.roomId != roomId)
            .toList(),
      ),
    );
  }

  NetworkState setPreset(NetworkState state, LivePreset preset) {
    return _save(state.copyWith(preset: preset));
  }

  NetworkState clearPreset(NetworkState state) {
    return _save(state.copyWith(preset: const LivePreset()));
  }

  NetworkState updateFavoriteLive(
    NetworkState state,
    Map<int, bool> liveByRoom,
  ) {
    if (liveByRoom.isEmpty) return state;
    final List<LiveFavorite> favorites = state.favorites
        .map(
          (LiveFavorite item) => liveByRoom.containsKey(item.room.roomId)
              ? item.copyWith(
                  room: item.room.copyWith(live: liveByRoom[item.room.roomId]),
                )
              : item,
        )
        .toList();
    return _save(state.copyWith(favorites: favorites));
  }

  NetworkState addVideo(
    NetworkState state, {
    required String name,
    required String url,
  }) {
    final NetworkVideo video = NetworkVideo(
      id: '${DateTime.now().microsecondsSinceEpoch}',
      name: name,
      url: url,
      savedAt: DateTime.now(),
    );
    return _save(
      state.copyWith(videos: <NetworkVideo>[video, ...state.videos]),
    );
  }

  NetworkState removeVideo(NetworkState state, String id) {
    return _save(
      state.copyWith(
        videos: state.videos
            .where((NetworkVideo item) => item.id != id)
            .toList(),
      ),
    );
  }
}
