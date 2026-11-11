// -------------------------------------------------------------------------
// 功能：网络模块状态控制器
//
// 主要内容：
// - 收藏/组合/网络视频的增删
// - 收藏列表开播状态批量刷新
// -------------------------------------------------------------------------

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../data/bili_live_api.dart';
import '../data/network_repository.dart';
import '../domain/live_models.dart';

/// B 站直播接口（全局单例，退出应用时关闭连接）。
final Provider<BiliLiveApi> biliLiveApiProvider = Provider<BiliLiveApi>((
  Ref ref,
) {
  final BiliLiveApi api = BiliLiveApi();
  ref.onDispose(api.close);
  return api;
});

final Provider<NetworkRepository> networkRepositoryProvider =
    Provider<NetworkRepository>(
      (Ref ref) => NetworkRepository(database: ref.watch(databaseProvider)),
    );

/// 网络模块状态控制器：收藏、双路组合、网络视频。
class NetworkController extends Notifier<NetworkState> {
  @override
  NetworkState build() => ref.watch(networkRepositoryProvider).load();

  NetworkRepository get _repository => ref.read(networkRepositoryProvider);

  bool isFavorite(int roomId) => state.isFavorite(roomId);

  bool toggleFavorite(LiveRoom room) {
    state = _repository.toggleFavorite(state, room);
    return state.isFavorite(room.roomId);
  }

  void removeFavorite(int roomId) {
    state = _repository.removeFavorite(state, roomId);
  }

  void savePreset(LivePreset preset) {
    state = _repository.setPreset(state, preset);
  }

  void clearPreset() {
    state = _repository.clearPreset(state);
  }

  void addVideo({required String name, required String url}) {
    state = _repository.addVideo(state, name: name, url: url);
  }

  void removeVideo(String id) {
    state = _repository.removeVideo(state, id);
  }

  /// 刷新收藏列表的开播状态（分 4 路并发，单个失败不影响其它）。
  Future<void> refreshFavoriteStatus() async {
    final List<int> roomIds = state.favorites
        .map((LiveFavorite item) => item.room.roomId)
        .toList();
    if (roomIds.isEmpty) return;

    final BiliLiveApi api = ref.read(biliLiveApiProvider);
    final Map<int, bool> liveByRoom = <int, bool>{};

    for (int start = 0; start < roomIds.length; start += 4) {
      final List<int> chunk = roomIds.sublist(
        start,
        (start + 4).clamp(0, roomIds.length),
      );
      final List<bool?> results = await Future.wait(
        chunk.map((int roomId) async {
          try {
            return await api.isLive(roomId);
          } on Object {
            return null;
          }
        }),
      );
      for (int i = 0; i < chunk.length; i++) {
        final bool? live = results[i];
        if (live != null) liveByRoom[chunk[i]] = live;
      }
    }

    if (liveByRoom.isEmpty) return;
    state = _repository.updateFavoriteLive(state, liveByRoom);
  }
}

final NotifierProvider<NetworkController, NetworkState>
networkControllerProvider = NotifierProvider<NetworkController, NetworkState>(
  NetworkController.new,
);
