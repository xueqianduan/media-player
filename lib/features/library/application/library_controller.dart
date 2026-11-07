import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../data/library_repository.dart';
import '../domain/models.dart';

/// 视频库状态控制器（Application 层）。
///
/// 所有写操作都委托给 [LibraryRepository]，UI 只消费新的快照。
class LibraryController extends Notifier<LibraryState> {
  @override
  LibraryState build() => ref.watch(initialLibraryStateProvider);

  LibraryRepository get _repository => ref.read(libraryRepositoryProvider);

  // ------------------------------------------------------------ 扫描 / 导入

  Future<void> scan({bool silent = false}) async {
    if (state.isScanning) return;
    final scanner = ref.read(mediaScannerProvider);
    if (!scanner.isSupported) {
      state = _repository.setPermission(state, MediaPermission.unsupported);
      state = _repository.setScanning(
        state,
        scanning: false,
        progress: 0,
        message: '当前平台不支持自动扫描，可使用「导入视频」添加本地文件',
      );
      return;
    }
    state = _repository.setScanning(
      state,
      scanning: true,
      progress: 0,
      message: '正在申请视频访问权限…',
    );
    try {
      final outcome = await scanner.scan(
        onProgress: (double progress, String message) {
          state = _repository.setScanning(
            state,
            scanning: true,
            progress: progress,
            message: message,
          );
        },
      );
      state = _repository.mergeScan(
        state,
        folders: outcome.folders,
        scannedMedia: outcome.media,
        permission: outcome.permission,
      );
      if (!outcome.permission.canRead) {
        state = state.copyWith(scanMessage: '未获得视频访问权限，可在设置中重新授权');
      }
    } on Object {
      state = _repository.setScanning(
        state,
        scanning: false,
        message: '扫描失败，请稍后重试',
      );
    }
  }

  Future<void> requestPermission() async {
    final scanner = ref.read(mediaScannerProvider);
    if (!scanner.isSupported) return;
    final MediaPermission permission = await scanner.requestPermission();
    state = _repository.setPermission(state, permission);
    if (permission.canRead) {
      await scan();
    }
  }

  Future<void> openSystemPermissionSettings() async {
    await ref.read(mediaScannerProvider).openSystemSettings();
  }

  /// 返回成功导入的数量。
  Future<int> importVideos({
    void Function(double progress, String message)? onProgress,
  }) async {
    try {
      final result = await ref
          .read(mediaImportServiceProvider)
          .pickAndImport(onProgress: onProgress);
      if (result.items.isEmpty) return 0;
      state = _repository.addImportedMedia(state, items: result.items);
      return result.items.length;
    } on Object {
      return -1;
    }
  }

  // ------------------------------------------------------------ 视频

  void toggleFavorite(String mediaId) {
    state = _repository.toggleFavorite(state, mediaId);
  }

  void setFavorite(Set<String> ids, bool value) {
    state = _repository.setFavorite(state, ids, value);
  }

  void rename(String mediaId, String name) {
    state = _repository.renameMedia(state, mediaId, name);
  }

  void removeFromLibrary(Set<String> ids) {
    state = _repository.removeFromLibrary(state, ids);
  }

  void setFolderHidden(String folderId, bool hidden) {
    state = _repository.setFolderHidden(state, folderId, hidden);
  }

  // ------------------------------------------------------------ 分类

  void createCategory(String name) {
    state = _repository.createCategory(state, name);
  }

  /// 创建分类并返回新分类 id（供选择弹窗自动勾选）。
  String? createCategoryAndGetId(String name) {
    final Set<String> before = state.categories
        .map((Category item) => item.id)
        .toSet();
    state = _repository.createCategory(state, name);
    for (final Category category in state.categories) {
      if (!before.contains(category.id)) return category.id;
    }
    return null;
  }

  void renameCategory(String categoryId, String name) {
    state = _repository.renameCategory(state, categoryId, name);
  }

  void deleteCategory(String categoryId) {
    state = _repository.deleteCategory(state, categoryId);
  }

  void addToCategories(Set<String> mediaIds, Set<String> categoryIds) {
    state = _repository.addToCategories(state, mediaIds, categoryIds);
  }

  void removeFromCategory(Set<String> mediaIds, String categoryId) {
    state = _repository.removeFromCategory(state, mediaIds, categoryId);
  }

  // ------------------------------------------------------------ 播放列表

  void createPlaylist(String name) {
    state = _repository.createPlaylist(state, name);
  }

  /// 创建播放列表并返回新 id。
  String? createPlaylistAndGetId(String name) {
    final Set<String> before = state.playlists
        .map((Playlist item) => item.id)
        .toSet();
    state = _repository.createPlaylist(state, name);
    for (final Playlist playlist in state.playlists) {
      if (!before.contains(playlist.id)) return playlist.id;
    }
    return null;
  }

  void renamePlaylist(String playlistId, String name) {
    state = _repository.renamePlaylist(state, playlistId, name);
  }

  void deletePlaylist(String playlistId) {
    state = _repository.deletePlaylist(state, playlistId);
  }

  void addToPlaylists(Set<String> mediaIds, Set<String> playlistIds) {
    state = _repository.addToPlaylists(state, mediaIds, playlistIds);
  }

  void removeFromPlaylist(String playlistId, Set<String> mediaIds) {
    state = _repository.removeFromPlaylist(state, playlistId, mediaIds);
  }

  void reorderPlaylist(String playlistId, int oldIndex, int newIndex) {
    state = _repository.reorderPlaylist(state, playlistId, oldIndex, newIndex);
  }

  // ------------------------------------------------------------ 播放进度

  void saveProgress({
    required String mediaId,
    required int positionMs,
    required int durationMs,
    required bool completed,
  }) {
    state = _repository.updateProgress(
      state,
      mediaId: mediaId,
      positionMs: positionMs,
      durationMs: durationMs,
      forceCompleted: completed,
    );
  }

  void clearHistoryEntry(String mediaId) {
    state = _repository.clearProgress(state, mediaId);
  }

  void clearAllHistory() {
    state = _repository.clearAllProgress(state);
  }

  void clearLibraryRecords() {
    state = _repository.clearLibrary(state);
  }
}

/// 应用级 Provider。
final NotifierProvider<LibraryController, LibraryState>
libraryControllerProvider = NotifierProvider<LibraryController, LibraryState>(
  LibraryController.new,
);
