// -------------------------------------------------------------------------
// 功能：媒体库仓储（写操作）
//
// 主要内容：
// - 扫描结果合并、增删改分类/播放列表
// - 收藏与收藏夹维护
// - 进度更新与清理，全部返回新 LibraryState
// -------------------------------------------------------------------------

import 'dart:async';

import 'package:uuid/uuid.dart';

import '../../../core/database/local_database.dart';
import '../domain/models.dart';

/// 视频库仓储：所有业务写操作都经过这里，UI 不直接碰存储。
///
/// 每个方法接收当前快照并返回新快照，便于单元测试与回滚。
class LibraryRepository {
  LibraryRepository({required this.database, Uuid? uuid})
    : _uuid = uuid ?? const Uuid();

  final LocalDatabase database;
  final Uuid _uuid;

  static const String importedFolderId = 'imported';
  static const String importedFolderName = '导入的视频';

  // ---------------------------------------------------------------- 读取

  // ===== 读取与扫描 =====
  LibraryState load() {
    final List<MediaItem> media = database
        .readList('media')
        .whereType<Map<String, dynamic>>()
        .map(MediaItem.fromJson)
        .toList();
    final List<SourceFolder> folders = database
        .readList('folders')
        .whereType<Map<String, dynamic>>()
        .map(SourceFolder.fromJson)
        .toList();
    final List<Category> categories = database
        .readList('categories')
        .whereType<Map<String, dynamic>>()
        .map(Category.fromJson)
        .toList();
    final List<Playlist> playlists = database
        .readList('playlists')
        .whereType<Map<String, dynamic>>()
        .map(Playlist.fromJson)
        .toList();
    List<FavoriteFolder> favoriteFolders = database
        .readList('favoriteFolders')
        .whereType<Map<String, dynamic>>()
        .map(FavoriteFolder.fromJson)
        .toList();

    // 旧版本只有 isFavorite 布尔值：升级后把它们归入「我的收藏」。
    if (favoriteFolders.isEmpty) {
      final List<String> legacyIds = media
          .where((MediaItem item) => item.isFavorite)
          .map((MediaItem item) => item.id)
          .toList();
      if (legacyIds.isNotEmpty) {
        favoriteFolders = <FavoriteFolder>[
          FavoriteFolder(
            id: _uuid.v4(),
            name: '我的收藏',
            createdAt: DateTime.now(),
            mediaIds: legacyIds,
          ),
        ];
      }
    }

    final Map<String, PlaybackProgress> progress = <String, PlaybackProgress>{};
    for (final Map<String, dynamic> json
        in database.readList('progress').whereType<Map<String, dynamic>>()) {
      final PlaybackProgress record = PlaybackProgress.fromJson(json);
      progress[record.mediaId] = record;
    }

    return LibraryState(
      media: media,
      folders: folders,
      categories: categories,
      playlists: playlists,
      favoriteFolders: favoriteFolders,
      progress: progress,
      permission: MediaPermission.values.firstWhere(
        (MediaPermission value) =>
            value.name == (database.data['permission'] as String? ?? 'unknown'),
        orElse: () => MediaPermission.unknown,
      ),
      lastScanAt: DateTime.tryParse(
        database.data['lastScanAt'] as String? ?? '',
      ),
    );
  }

  // ---------------------------------------------------------------- 扫描

  /// 合并一次扫描结果。
  ///
  /// - 以 [MediaItem.sourceId] 去重，已存在记录保留 id / 收藏 / 自定义名称 / 播放记录；
  /// - 本次未出现的相册资源标记为不可访问（不删除管理记录）；
  /// - 文件夹数量与大小由媒体列表重新统计，避免脏数据。
  LibraryState mergeScan(
    LibraryState state, {
    required List<SourceFolder> folders,
    required List<MediaItem> scannedMedia,
    MediaPermission permission = MediaPermission.granted,
  }) {
    final Map<String, MediaItem> existingBySource = <String, MediaItem>{
      for (final MediaItem item in state.media) item.sourceId: item,
    };
    final List<MediaItem> merged = <MediaItem>[];
    final Set<String> seenSourceIds = <String>{};
    final DateTime now = DateTime.now();

    for (final MediaItem incoming in scannedMedia) {
      seenSourceIds.add(incoming.sourceId);
      final MediaItem? existing = existingBySource[incoming.sourceId];
      if (existing == null) {
        merged.add(incoming);
        continue;
      }
      merged.add(
        existing.copyWith(
          folderId: incoming.folderId,
          sourceLocator: incoming.sourceLocator,
          durationMs: incoming.durationMs,
          fileSize: incoming.fileSize,
          width: incoming.width,
          height: incoming.height,
          modifiedAt: incoming.modifiedAt,
          thumbnailPath: existing.thumbnailPath,
          isAvailable: true,
          updatedAt: now,
        ),
      );
    }

    // 保留应用内导入的视频（不在相册扫描结果里）。
    for (final MediaItem item in state.media) {
      if (item.sourceType != MediaSourceType.photoAsset) {
        if (!seenSourceIds.contains(item.sourceId)) merged.add(item);
        continue;
      }
      if (!seenSourceIds.contains(item.sourceId) && item.isAvailable) {
        merged.add(item.copyWith(isAvailable: false, updatedAt: now));
      } else if (!seenSourceIds.contains(item.sourceId)) {
        merged.add(item);
      }
    }

    final Map<String, SourceFolder> folderIndex = <String, SourceFolder>{
      for (final SourceFolder folder in folders) folder.id: folder,
    };
    if (merged.any(
      (MediaItem item) => item.sourceType == MediaSourceType.imported,
    )) {
      folderIndex.putIfAbsent(
        importedFolderId,
        () => SourceFolder(
          id: importedFolderId,
          name: importedFolderName,
          path: '',
          itemCount: 0,
          totalSize: 0,
          lastScannedAt: now,
        ),
      );
    }

    final LibraryState next = state.copyWith(
      media: merged,
      folders: _recalculateFolders(merged, folderIndex.values.toList()),
      permission: permission,
      lastScanAt: now,
      isScanning: false,
      scanProgress: 1,
      clearScanMessage: true,
    );
    _persist(next);
    return next;
  }

  /// 导入外部文件（已复制到应用目录）。
  LibraryState addImportedMedia(
    LibraryState state, {
    required List<MediaItem> items,
  }) {
    if (items.isEmpty) return state;
    // 同名同大小视为重复导入，避免产生重复记录。
    final Set<String> existing = <String>{
      for (final MediaItem item in state.media)
        '${item.originalName}|${item.fileSize}',
    };
    final List<MediaItem> unique = items
        .where(
          (MediaItem item) =>
              existing.add('${item.originalName}|${item.fileSize}'),
        )
        .toList();
    if (unique.isEmpty) return state;
    final List<MediaItem> media = <MediaItem>[...state.media, ...unique];
    final List<SourceFolder> folders = <SourceFolder>[...state.folders];
    if (!folders.any((SourceFolder folder) => folder.id == importedFolderId)) {
      folders.add(
        SourceFolder(
          id: importedFolderId,
          name: importedFolderName,
          path: '',
          itemCount: 0,
          totalSize: 0,
          lastScannedAt: DateTime.now(),
        ),
      );
    }
    final LibraryState next = state.copyWith(
      media: media,
      folders: _recalculateFolders(media, folders),
    );
    _persist(next);
    return next;
  }

  List<SourceFolder> _recalculateFolders(
    List<MediaItem> media,
    List<SourceFolder> folders,
  ) {
    return folders.map((SourceFolder folder) {
      final List<MediaItem> items = media
          .where((MediaItem item) => item.folderId == folder.id)
          .toList(growable: false);
      return folder.copyWith(
        itemCount: items.length,
        totalSize: items.fold<int>(
          0,
          (int sum, MediaItem item) => sum + item.fileSize,
        ),
        lastScannedAt: folder.lastScannedAt ?? DateTime.now(),
      );
    }).toList();
  }

  // ---------------------------------------------------------------- 视频

  // ===== 收藏与收藏夹 =====
  LibraryState toggleFavorite(LibraryState state, String mediaId) {
    final MediaItem? item = state.itemById(mediaId);
    if (item == null) return state;
    return _applyFavorite(state, <String>{mediaId}, value: !item.isFavorite);
  }

  LibraryState setFavorite(
    LibraryState state,
    Set<String> mediaIds,
    bool value,
  ) {
    return _applyFavorite(state, mediaIds, value: value);
  }

  /// 收藏 / 取消收藏的统一入口：收藏时放进默认收藏夹，取消时移出所有收藏夹。
  LibraryState _applyFavorite(
    LibraryState state,
    Set<String> mediaIds, {
    required bool value,
  }) {
    if (mediaIds.isEmpty) return state;

    List<FavoriteFolder> folders = state.favoriteFolders;
    if (value) {
      if (folders.isEmpty) {
        folders = <FavoriteFolder>[
          FavoriteFolder(
            id: _uuid.v4(),
            name: '我的收藏',
            createdAt: DateTime.now(),
          ),
        ];
      }
      final String defaultId = folders.first.id;
      folders = folders.map((FavoriteFolder folder) {
        if (folder.id != defaultId) return folder;
        final Set<String> ids = <String>{...folder.mediaIds, ...mediaIds};
        return folder.copyWith(mediaIds: ids.toList());
      }).toList();
    } else {
      folders = folders
          .map(
            (FavoriteFolder folder) => folder.copyWith(
              mediaIds: folder.mediaIds
                  .where((String id) => !mediaIds.contains(id))
                  .toList(),
            ),
          )
          .toList();
    }

    final Set<String> remaining = <String>{
      for (final FavoriteFolder folder in folders) ...folder.mediaIds,
    };
    final List<MediaItem> media = state.media.map((MediaItem item) {
      if (!mediaIds.contains(item.id)) return item;
      return item.copyWith(
        isFavorite: remaining.contains(item.id),
        updatedAt: DateTime.now(),
      );
    }).toList();

    final LibraryState next = state.copyWith(
      media: media,
      favoriteFolders: folders,
    );
    _persist(next);
    return next;
  }

  // ---------------------------------------------------------------- 收藏夹

  LibraryState createFavoriteFolder(LibraryState state, String name) {
    final String trimmed = name.trim();
    if (trimmed.isEmpty) return state;
    final FavoriteFolder folder = FavoriteFolder(
      id: _uuid.v4(),
      name: trimmed,
      createdAt: DateTime.now(),
    );
    final LibraryState next = state.copyWith(
      favoriteFolders: <FavoriteFolder>[...state.favoriteFolders, folder],
    );
    _persist(next);
    return next;
  }

  LibraryState renameFavoriteFolder(
    LibraryState state,
    String folderId,
    String name,
  ) {
    final String trimmed = name.trim();
    if (trimmed.isEmpty) return state;
    final LibraryState next = state.copyWith(
      favoriteFolders: state.favoriteFolders
          .map(
            (FavoriteFolder folder) =>
                folder.id == folderId ? folder.copyWith(name: trimmed) : folder,
          )
          .toList(),
    );
    _persist(next);
    return next;
  }

  LibraryState deleteFavoriteFolder(LibraryState state, String folderId) {
    final FavoriteFolder? removed = state.favoriteFolderById(folderId);
    if (removed == null) return state;

    final List<FavoriteFolder> folders = state.favoriteFolders
        .where((FavoriteFolder folder) => folder.id != folderId)
        .toList();
    final Set<String> remaining = <String>{
      for (final FavoriteFolder folder in folders) ...folder.mediaIds,
    };
    final Set<String> affected = removed.mediaIds.toSet();

    final LibraryState next = state.copyWith(
      favoriteFolders: folders,
      media: state.media.map((MediaItem item) {
        if (!affected.contains(item.id)) return item;
        return item.copyWith(
          isFavorite: remaining.contains(item.id),
          updatedAt: DateTime.now(),
        );
      }).toList(),
    );
    _persist(next);
    return next;
  }

  LibraryState addToFavoriteFolders(
    LibraryState state,
    Set<String> mediaIds,
    Set<String> folderIds,
  ) {
    if (mediaIds.isEmpty || folderIds.isEmpty) return state;
    final List<FavoriteFolder> folders = state.favoriteFolders.map((
      FavoriteFolder folder,
    ) {
      if (!folderIds.contains(folder.id)) return folder;
      final Set<String> ids = <String>{...folder.mediaIds, ...mediaIds};
      return folder.copyWith(mediaIds: ids.toList());
    }).toList();

    final LibraryState next = state.copyWith(
      favoriteFolders: folders,
      media: state.media.map((MediaItem item) {
        if (!mediaIds.contains(item.id) || item.isFavorite) return item;
        return item.copyWith(isFavorite: true, updatedAt: DateTime.now());
      }).toList(),
    );
    _persist(next);
    return next;
  }

  LibraryState removeFromFavoriteFolders(
    LibraryState state,
    Set<String> mediaIds,
    Set<String> folderIds,
  ) {
    if (mediaIds.isEmpty || folderIds.isEmpty) return state;
    final List<FavoriteFolder> folders = state.favoriteFolders.map((
      FavoriteFolder folder,
    ) {
      if (!folderIds.contains(folder.id)) return folder;
      return folder.copyWith(
        mediaIds: folder.mediaIds
            .where((String id) => !mediaIds.contains(id))
            .toList(),
      );
    }).toList();

    final Set<String> remaining = <String>{
      for (final FavoriteFolder folder in folders) ...folder.mediaIds,
    };

    final LibraryState next = state.copyWith(
      favoriteFolders: folders,
      media: state.media.map((MediaItem item) {
        if (!mediaIds.contains(item.id)) return item;
        return item.copyWith(
          isFavorite: remaining.contains(item.id),
          updatedAt: DateTime.now(),
        );
      }).toList(),
    );
    _persist(next);
    return next;
  }

  // ===== 单条编辑与移除 =====
  LibraryState renameMedia(LibraryState state, String mediaId, String name) {
    final String trimmed = name.trim();
    if (trimmed.isEmpty) return state;
    final List<MediaItem> media = state.media.map((MediaItem item) {
      if (item.id != mediaId) return item;
      return item.copyWith(displayName: trimmed, updatedAt: DateTime.now());
    }).toList();
    final LibraryState next = state.copyWith(media: media);
    _persist(next);
    return next;
  }

  /// 从 LumiPlayer 移除：只删除应用内记录，不动手机原始文件。
  LibraryState removeFromLibrary(LibraryState state, Set<String> mediaIds) {
    final List<MediaItem> media = state.media
        .where((MediaItem item) => !mediaIds.contains(item.id))
        .toList();
    // 收藏夹里也要清掉这些 id，否则数量统计会对不上。
    final List<FavoriteFolder> folders = state.favoriteFolders
        .map(
          (FavoriteFolder folder) => folder.copyWith(
            mediaIds: folder.mediaIds
                .where((String id) => !mediaIds.contains(id))
                .toList(),
          ),
        )
        .toList();
    final List<Category> categories = state.categories
        .map(
          (Category category) => category.copyWith(
            mediaIds: category.mediaIds
                .where((String id) => !mediaIds.contains(id))
                .toList(),
          ),
        )
        .toList();
    final List<Playlist> playlists = state.playlists
        .map(
          (Playlist list) => list.copyWith(
            mediaIds: list.mediaIds
                .where((String id) => !mediaIds.contains(id))
                .toList(),
            updatedAt: DateTime.now(),
          ),
        )
        .toList();
    final Map<String, PlaybackProgress> progress =
        Map<String, PlaybackProgress>.of(state.progress)
          ..removeWhere((String key, _) => mediaIds.contains(key));

    final LibraryState next = state.copyWith(
      media: media,
      categories: categories,
      playlists: playlists,
      favoriteFolders: folders,
      progress: progress,
      folders: _recalculateFolders(media, state.folders),
    );
    _persist(next);
    return next;
  }

  // ===== 文件夹、权限与扫描状态 =====
  LibraryState setFolderHidden(
    LibraryState state,
    String folderId,
    bool hidden,
  ) {
    final List<SourceFolder> folders = state.folders
        .map(
          (SourceFolder folder) => folder.id == folderId
              ? folder.copyWith(isHidden: hidden)
              : folder,
        )
        .toList();
    final LibraryState next = state.copyWith(folders: folders);
    _persist(next);
    return next;
  }

  LibraryState setPermission(LibraryState state, MediaPermission permission) {
    final LibraryState next = state.copyWith(permission: permission);
    _persist(next);
    return next;
  }

  LibraryState setScanning(
    LibraryState state, {
    required bool scanning,
    double progress = 0,
    String? message,
  }) {
    return state.copyWith(
      isScanning: scanning,
      scanProgress: progress,
      scanMessage: message,
      clearScanMessage: message == null,
    );
  }

  // ---------------------------------------------------------------- 分类

  // ===== 分类 =====
  LibraryState createCategory(LibraryState state, String name) {
    final String trimmed = name.trim();
    if (trimmed.isEmpty) return state;
    final Category category = Category(
      id: _uuid.v4(),
      name: trimmed,
      sortOrder: state.categories.length,
      createdAt: DateTime.now(),
    );
    final LibraryState next = state.copyWith(
      categories: <Category>[...state.categories, category],
    );
    _persist(next);
    return next;
  }

  LibraryState renameCategory(
    LibraryState state,
    String categoryId,
    String name,
  ) {
    final String trimmed = name.trim();
    if (trimmed.isEmpty) return state;
    final List<Category> categories = state.categories
        .map(
          (Category category) => category.id == categoryId
              ? category.copyWith(name: trimmed)
              : category,
        )
        .toList();
    final LibraryState next = state.copyWith(categories: categories);
    _persist(next);
    return next;
  }

  /// 删除分类只删除分类记录与关联，不删除视频本身。
  LibraryState deleteCategory(LibraryState state, String categoryId) {
    final LibraryState next = state.copyWith(
      categories: state.categories
          .where((Category item) => item.id != categoryId)
          .toList(),
    );
    _persist(next);
    return next;
  }

  /// 一个视频可以同时属于多个分类（幂等，不会重复添加）。
  LibraryState addToCategories(
    LibraryState state,
    Set<String> mediaIds,
    Set<String> categoryIds,
  ) {
    if (mediaIds.isEmpty || categoryIds.isEmpty) return state;
    final List<Category> categories = state.categories.map((Category category) {
      if (!categoryIds.contains(category.id)) return category;
      final Set<String> merged = <String>{...category.mediaIds, ...mediaIds};
      return category.copyWith(mediaIds: merged.toList());
    }).toList();
    final LibraryState next = state.copyWith(categories: categories);
    _persist(next);
    return next;
  }

  LibraryState removeFromCategory(
    LibraryState state,
    Set<String> mediaIds,
    String categoryId,
  ) {
    final List<Category> categories = state.categories.map((Category category) {
      if (category.id != categoryId) return category;
      return category.copyWith(
        mediaIds: category.mediaIds
            .where((String id) => !mediaIds.contains(id))
            .toList(),
      );
    }).toList();
    final LibraryState next = state.copyWith(categories: categories);
    _persist(next);
    return next;
  }

  // ---------------------------------------------------------------- 播放列表

  // ===== 播放列表 =====
  LibraryState createPlaylist(LibraryState state, String name) {
    final String trimmed = name.trim();
    if (trimmed.isEmpty) return state;
    final DateTime now = DateTime.now();
    final Playlist playlist = Playlist(
      id: _uuid.v4(),
      name: trimmed,
      createdAt: now,
      updatedAt: now,
    );
    final LibraryState next = state.copyWith(
      playlists: <Playlist>[...state.playlists, playlist],
    );
    _persist(next);
    return next;
  }

  LibraryState renamePlaylist(
    LibraryState state,
    String playlistId,
    String name,
  ) {
    final String trimmed = name.trim();
    if (trimmed.isEmpty) return state;
    final List<Playlist> playlists = state.playlists
        .map(
          (Playlist list) => list.id == playlistId
              ? list.copyWith(name: trimmed, updatedAt: DateTime.now())
              : list,
        )
        .toList();
    final LibraryState next = state.copyWith(playlists: playlists);
    _persist(next);
    return next;
  }

  LibraryState deletePlaylist(LibraryState state, String playlistId) {
    final LibraryState next = state.copyWith(
      playlists: state.playlists
          .where((Playlist list) => list.id != playlistId)
          .toList(),
    );
    _persist(next);
    return next;
  }

  LibraryState addToPlaylists(
    LibraryState state,
    Set<String> mediaIds,
    Set<String> playlistIds,
  ) {
    if (mediaIds.isEmpty || playlistIds.isEmpty) return state;
    final List<Playlist> playlists = state.playlists.map((Playlist list) {
      if (!playlistIds.contains(list.id)) return list;
      final List<String> merged = <String>[...list.mediaIds];
      for (final String id in mediaIds) {
        if (!merged.contains(id)) merged.add(id);
      }
      return list.copyWith(mediaIds: merged, updatedAt: DateTime.now());
    }).toList();
    final LibraryState next = state.copyWith(playlists: playlists);
    _persist(next);
    return next;
  }

  LibraryState removeFromPlaylist(
    LibraryState state,
    String playlistId,
    Set<String> mediaIds,
  ) {
    final List<Playlist> playlists = state.playlists.map((Playlist list) {
      if (list.id != playlistId) return list;
      return list.copyWith(
        mediaIds: list.mediaIds
            .where((String id) => !mediaIds.contains(id))
            .toList(),
        updatedAt: DateTime.now(),
      );
    }).toList();
    final LibraryState next = state.copyWith(playlists: playlists);
    _persist(next);
    return next;
  }

  /// 调整播放顺序（例如 ReorderableListView 拖动）。
  LibraryState reorderPlaylist(
    LibraryState state,
    String playlistId,
    int oldIndex,
    int newIndex,
  ) {
    final Playlist? playlist = state.playlistById(playlistId);
    if (playlist == null) return state;
    final List<String> ids = List<String>.of(playlist.mediaIds);
    if (oldIndex < 0 || oldIndex >= ids.length) return state;
    int target = newIndex;
    if (target > oldIndex) target -= 1;
    target = target.clamp(0, ids.length - 1);
    if (target == oldIndex) return state;
    final String moved = ids.removeAt(oldIndex);
    ids.insert(target, moved);

    final LibraryState next = state.copyWith(
      playlists: state.playlists
          .map(
            (Playlist list) => list.id == playlistId
                ? list.copyWith(mediaIds: ids, updatedAt: DateTime.now())
                : list,
          )
          .toList(),
    );
    _persist(next);
    return next;
  }

  // ---------------------------------------------------------------- 播放进度

  /// 记录播放进度；达到 95% 时标记为已看完。
  LibraryState updateProgress(
    LibraryState state, {
    required String mediaId,
    required int positionMs,
    required int durationMs,
    bool forceCompleted = false,
    double? speed,
    DateTime? at,
  }) {
    final DateTime now = at ?? DateTime.now();
    final int safeDuration = durationMs > 0 ? durationMs : 0;
    final double fraction = safeDuration > 0
        ? (positionMs / safeDuration).clamp(0.0, 1.0)
        : 0.0;
    final bool completed =
        forceCompleted || fraction >= PlaybackProgress.completionThreshold;
    final int position = completed
        ? safeDuration
        : positionMs.clamp(0, safeDuration);

    final Map<String, PlaybackProgress> progress =
        Map<String, PlaybackProgress>.of(state.progress);
    // 倍速与进度一起记住：没传就沿用该视频上次记录的值。
    final double savedSpeed = speed ?? state.progress[mediaId]?.speed ?? 0;
    progress[mediaId] = PlaybackProgress(
      mediaId: mediaId,
      positionMs: position,
      durationMs: safeDuration,
      lastPlayedAt: now,
      completed: completed,
      speed: savedSpeed,
    );

    final List<MediaItem> media = state.media.map((MediaItem item) {
      if (item.id != mediaId) return item;
      return item.copyWith(lastPlayedAt: now, updatedAt: now);
    }).toList();

    final LibraryState next = state.copyWith(media: media, progress: progress);
    _persist(next);
    return next;
  }

  LibraryState clearProgress(LibraryState state, String mediaId) {
    final Map<String, PlaybackProgress> progress =
        Map<String, PlaybackProgress>.of(state.progress)..remove(mediaId);
    final LibraryState next = state.copyWith(progress: progress);
    _persist(next);
    return next;
  }

  LibraryState clearAllProgress(LibraryState state) {
    final LibraryState next = state.copyWith(
      progress: const <String, PlaybackProgress>{},
    );
    _persist(next);
    return next;
  }

  /// 清空应用内所有索引记录（不删除原始视频文件）。
  LibraryState clearLibrary(LibraryState state) {
    final LibraryState next = state.copyWith(
      media: <MediaItem>[],
      folders: <SourceFolder>[],
      progress: const <String, PlaybackProgress>{},
    );
    _persist(next);
    return next;
  }

  void _persist(LibraryState state) {
    database
      ..writeTable(
        'media',
        state.media.map((MediaItem item) => item.toJson()).toList(),
      )
      ..writeTable(
        'folders',
        state.folders.map((SourceFolder folder) => folder.toJson()).toList(),
      )
      ..writeTable(
        'categories',
        state.categories.map((Category category) => category.toJson()).toList(),
      )
      ..writeTable(
        'playlists',
        state.playlists.map((Playlist list) => list.toJson()).toList(),
      )
      ..writeTable(
        'favoriteFolders',
        state.favoriteFolders
            .map((FavoriteFolder folder) => folder.toJson())
            .toList(),
      )
      ..writeTable(
        'progress',
        state.progress.values.map((PlaybackProgress p) => p.toJson()).toList(),
      )
      ..writeTable('permission', state.permission.name)
      ..writeTable('lastScanAt', state.lastScanAt?.toIso8601String());
    unawaited(database.flush());
  }
}
