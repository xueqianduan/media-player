/// ReelBox 领域模型：视频、文件夹、分类、播放列表、播放进度。
///
/// 这些类型不依赖任何 Flutter 插件，便于单元测试与后续替换数据源。
library;

/// 视频来源：系统相册资源 / 应用内导入副本。
enum MediaSourceType {
  photoAsset,
  imported;

  static MediaSourceType parse(String? value) {
    return MediaSourceType.values.firstWhere(
      (MediaSourceType type) => type.name == value,
      orElse: () => MediaSourceType.imported,
    );
  }
}

/// 视频排序方式。排序选择会被持久化。
enum SortOption {
  nameAsc('名称升序'),
  nameDesc('名称降序'),
  dateAdded('添加时间'),
  dateModified('修改时间'),
  duration('视频时长'),
  fileSize('文件大小');

  const SortOption(this.label);

  final String label;

  static SortOption parse(String? value) {
    return SortOption.values.firstWhere(
      (SortOption option) => option.name == value,
      orElse: () => SortOption.dateAdded,
    );
  }
}

/// 列表 / 网格展示模式。
enum ViewMode {
  list,
  grid;

  static ViewMode parse(String? value) {
    return ViewMode.values.firstWhere(
      (ViewMode mode) => mode.name == value,
      orElse: () => ViewMode.list,
    );
  }
}

/// 播放模式。
///
/// 单个视频默认「不循环」：播完即停；
/// 播放列表可选择不循环 / 列表循环 / 单集循环。
enum RepeatMode {
  sequential('不循环'),
  loopAll('列表循环'),
  loopOne('单集循环'),
  shuffle('随机播放');

  const RepeatMode(this.label);

  final String label;

  /// 播放器与播放列表里可选的前三种模式（随机播放暂不在 UI 暴露）。
  static const List<RepeatMode> playbackModes = <RepeatMode>[
    RepeatMode.sequential,
    RepeatMode.loopAll,
    RepeatMode.loopOne,
  ];

  /// 在 UI 中循环切换播放模式。
  RepeatMode next() {
    final int index = playbackModes.indexOf(this);
    if (index < 0) return RepeatMode.sequential;
    return playbackModes[(index + 1) % playbackModes.length];
  }
}

/// 媒体访问权限状态。
enum MediaPermission {
  unknown,
  granted,
  limited,
  denied,
  permanentlyDenied,
  unsupported;

  bool get canRead =>
      this == MediaPermission.granted || this == MediaPermission.limited;
}

/// 一条视频媒体记录（媒体文件本身不入库）。
class MediaItem {
  const MediaItem({
    required this.id,
    required this.folderId,
    required this.sourceType,
    required this.sourceId,
    required this.sourceLocator,
    required this.displayName,
    required this.originalName,
    required this.mimeType,
    required this.durationMs,
    required this.width,
    required this.height,
    required this.fileSize,
    this.thumbnailPath,
    this.isFavorite = false,
    this.isAvailable = true,
    this.lastPlayedAt,
    required this.createdAt,
    required this.updatedAt,
    this.modifiedAt,
  });

  final String id;

  /// 所属系统相册分组（[SourceFolder.id]）。
  final String folderId;
  final MediaSourceType sourceType;

  /// 系统资源标识，用于去重与重新获取资源。
  final String sourceId;

  /// 文件路径（导入副本）或资源 id（相册资源）。
  final String sourceLocator;
  final String displayName;
  final String originalName;
  final String mimeType;
  final int durationMs;
  final int width;
  final int height;
  final int fileSize;
  final String? thumbnailPath;
  final bool isFavorite;
  final bool isAvailable;
  final DateTime? lastPlayedAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? modifiedAt;

  double get aspectRatio {
    if (width <= 0 || height <= 0) return 16 / 9;
    return width / height;
  }

  MediaItem copyWith({
    String? folderId,
    String? displayName,
    String? sourceLocator,
    String? thumbnailPath,
    bool? isFavorite,
    bool? isAvailable,
    DateTime? lastPlayedAt,
    DateTime? updatedAt,
    DateTime? modifiedAt,
    int? durationMs,
    int? fileSize,
    int? width,
    int? height,
  }) {
    return MediaItem(
      id: id,
      folderId: folderId ?? this.folderId,
      sourceType: sourceType,
      sourceId: sourceId,
      sourceLocator: sourceLocator ?? this.sourceLocator,
      displayName: displayName ?? this.displayName,
      originalName: originalName,
      mimeType: mimeType,
      durationMs: durationMs ?? this.durationMs,
      width: width ?? this.width,
      height: height ?? this.height,
      fileSize: fileSize ?? this.fileSize,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      isFavorite: isFavorite ?? this.isFavorite,
      isAvailable: isAvailable ?? this.isAvailable,
      lastPlayedAt: lastPlayedAt ?? this.lastPlayedAt,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      modifiedAt: modifiedAt ?? this.modifiedAt,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'folderId': folderId,
    'sourceType': sourceType.name,
    'sourceId': sourceId,
    'sourceLocator': sourceLocator,
    'displayName': displayName,
    'originalName': originalName,
    'mimeType': mimeType,
    'durationMs': durationMs,
    'width': width,
    'height': height,
    'fileSize': fileSize,
    'thumbnailPath': thumbnailPath,
    'isFavorite': isFavorite,
    'isAvailable': isAvailable,
    'lastPlayedAt': lastPlayedAt?.toIso8601String(),
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'modifiedAt': modifiedAt?.toIso8601String(),
  };

  static MediaItem fromJson(Map<String, dynamic> json) {
    return MediaItem(
      id: json['id'] as String,
      folderId: (json['folderId'] as String?) ?? '',
      sourceType: MediaSourceType.parse(json['sourceType'] as String?),
      sourceId: (json['sourceId'] as String?) ?? '',
      sourceLocator: (json['sourceLocator'] as String?) ?? '',
      displayName: (json['displayName'] as String?) ?? '未命名视频',
      originalName: (json['originalName'] as String?) ?? '',
      mimeType: (json['mimeType'] as String?) ?? 'video/*',
      durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
      width: (json['width'] as num?)?.toInt() ?? 0,
      height: (json['height'] as num?)?.toInt() ?? 0,
      fileSize: (json['fileSize'] as num?)?.toInt() ?? 0,
      thumbnailPath: json['thumbnailPath'] as String?,
      isFavorite: json['isFavorite'] as bool? ?? false,
      isAvailable: json['isAvailable'] as bool? ?? true,
      lastPlayedAt: _parseTime(json['lastPlayedAt']),
      createdAt: _parseTime(json['createdAt']) ?? DateTime.now(),
      updatedAt: _parseTime(json['updatedAt']) ?? DateTime.now(),
      modifiedAt: _parseTime(json['modifiedAt']),
    );
  }
}

DateTime? _parseTime(Object? value) {
  if (value is String && value.isNotEmpty) return DateTime.tryParse(value);
  return null;
}

/// 系统相册分组 / 真实文件夹。
class SourceFolder {
  const SourceFolder({
    required this.id,
    required this.name,
    required this.path,
    required this.itemCount,
    required this.totalSize,
    this.isHidden = false,
    this.lastScannedAt,
  });

  final String id;
  final String name;
  final String path;
  final int itemCount;
  final int totalSize;
  final bool isHidden;
  final DateTime? lastScannedAt;

  SourceFolder copyWith({
    String? name,
    String? path,
    int? itemCount,
    int? totalSize,
    bool? isHidden,
    DateTime? lastScannedAt,
  }) {
    return SourceFolder(
      id: id,
      name: name ?? this.name,
      path: path ?? this.path,
      itemCount: itemCount ?? this.itemCount,
      totalSize: totalSize ?? this.totalSize,
      isHidden: isHidden ?? this.isHidden,
      lastScannedAt: lastScannedAt ?? this.lastScannedAt,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'path': path,
    'itemCount': itemCount,
    'totalSize': totalSize,
    'isHidden': isHidden,
    'lastScannedAt': lastScannedAt?.toIso8601String(),
  };

  static SourceFolder fromJson(Map<String, dynamic> json) {
    return SourceFolder(
      id: json['id'] as String,
      name: (json['name'] as String?) ?? '未知文件夹',
      path: (json['path'] as String?) ?? '',
      itemCount: (json['itemCount'] as num?)?.toInt() ?? 0,
      totalSize: (json['totalSize'] as num?)?.toInt() ?? 0,
      isHidden: json['isHidden'] as bool? ?? false,
      lastScannedAt: _parseTime(json['lastScannedAt']),
    );
  }
}

/// 自定义分类（应用内虚拟文件夹，不改变真实存储位置）。
class Category {
  const Category({
    required this.id,
    required this.name,
    this.icon,
    this.color,
    this.sortOrder = 0,
    required this.createdAt,
    this.mediaIds = const <String>[],
  });

  final String id;
  final String name;
  final String? icon;
  final String? color;
  final int sortOrder;
  final DateTime createdAt;

  /// 关联的视频 id 列表。
  final List<String> mediaIds;

  Category copyWith({
    String? name,
    String? icon,
    String? color,
    int? sortOrder,
    List<String>? mediaIds,
  }) {
    return Category(
      id: id,
      name: name ?? this.name,
      icon: icon ?? this.icon,
      color: color ?? this.color,
      sortOrder: sortOrder ?? this.sortOrder,
      createdAt: createdAt,
      mediaIds: mediaIds ?? this.mediaIds,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'icon': icon,
    'color': color,
    'sortOrder': sortOrder,
    'createdAt': createdAt.toIso8601String(),
    'mediaIds': mediaIds,
  };

  static Category fromJson(Map<String, dynamic> json) {
    return Category(
      id: json['id'] as String,
      name: (json['name'] as String?) ?? '未命名分类',
      icon: json['icon'] as String?,
      color: json['color'] as String?,
      sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
      createdAt: _parseTime(json['createdAt']) ?? DateTime.now(),
      mediaIds: (json['mediaIds'] as List<dynamic>? ?? <dynamic>[])
          .map((dynamic id) => id as String)
          .toList(growable: false),
    );
  }
}

/// 播放列表：用于组织播放顺序。
class Playlist {
  const Playlist({
    required this.id,
    required this.name,
    this.description = '',
    required this.createdAt,
    required this.updatedAt,
    this.mediaIds = const <String>[],
  });

  final String id;
  final String name;
  final String description;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// 有序的视频 id 列表，顺序即播放顺序。
  final List<String> mediaIds;

  Playlist copyWith({
    String? name,
    String? description,
    DateTime? updatedAt,
    List<String>? mediaIds,
  }) {
    return Playlist(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      mediaIds: mediaIds ?? this.mediaIds,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'description': description,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'mediaIds': mediaIds,
  };

  static Playlist fromJson(Map<String, dynamic> json) {
    return Playlist(
      id: json['id'] as String,
      name: (json['name'] as String?) ?? '未命名播放列表',
      description: (json['description'] as String?) ?? '',
      createdAt: _parseTime(json['createdAt']) ?? DateTime.now(),
      updatedAt: _parseTime(json['updatedAt']) ?? DateTime.now(),
      mediaIds: (json['mediaIds'] as List<dynamic>? ?? <dynamic>[])
          .map((dynamic id) => id as String)
          .toList(growable: false),
    );
  }
}

/// 播放进度记录。
class PlaybackProgress {
  const PlaybackProgress({
    required this.mediaId,
    required this.positionMs,
    required this.durationMs,
    required this.lastPlayedAt,
    this.completed = false,
  });

  /// 达到总时长 95% 视为已看完。
  static const double completionThreshold = 0.95;

  /// 小于 15 秒默认从头播放。
  static const int resumeThresholdMs = 15000;

  final String mediaId;
  final int positionMs;
  final int durationMs;
  final DateTime lastPlayedAt;
  final bool completed;

  double get fraction {
    if (durationMs <= 0) return 0;
    return (positionMs / durationMs).clamp(0.0, 1.0);
  }

  /// 是否需要询问用户继续观看。
  bool get shouldResume => !completed && positionMs >= resumeThresholdMs;

  bool get isFinished => completed || fraction >= completionThreshold;

  PlaybackProgress copyWith({
    int? positionMs,
    int? durationMs,
    DateTime? lastPlayedAt,
    bool? completed,
  }) {
    return PlaybackProgress(
      mediaId: mediaId,
      positionMs: positionMs ?? this.positionMs,
      durationMs: durationMs ?? this.durationMs,
      lastPlayedAt: lastPlayedAt ?? this.lastPlayedAt,
      completed: completed ?? this.completed,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'mediaId': mediaId,
    'positionMs': positionMs,
    'durationMs': durationMs,
    'lastPlayedAt': lastPlayedAt.toIso8601String(),
    'completed': completed,
  };

  static PlaybackProgress fromJson(Map<String, dynamic> json) {
    return PlaybackProgress(
      mediaId: json['mediaId'] as String,
      positionMs: (json['positionMs'] as num?)?.toInt() ?? 0,
      durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
      lastPlayedAt: _parseTime(json['lastPlayedAt']) ?? DateTime.now(),
      completed: json['completed'] as bool? ?? false,
    );
  }
}

/// 视频库快照。UI 只读取该快照，所有写操作走 Repository。
class LibraryState {
  const LibraryState({
    this.media = const <MediaItem>[],
    this.folders = const <SourceFolder>[],
    this.categories = const <Category>[],
    this.playlists = const <Playlist>[],
    this.progress = const <String, PlaybackProgress>{},
    this.permission = MediaPermission.unknown,
    this.isScanning = false,
    this.scanProgress = 0,
    this.scanMessage,
    this.lastScanAt,
  });

  final List<MediaItem> media;
  final List<SourceFolder> folders;
  final List<Category> categories;
  final List<Playlist> playlists;
  final Map<String, PlaybackProgress> progress;
  final MediaPermission permission;
  final bool isScanning;
  final double scanProgress;
  final String? scanMessage;
  final DateTime? lastScanAt;

  bool get isEmpty => media.isEmpty;
  int get totalCount => media.length;
  int get totalSize => media.fold(
    0,
    (int sum, MediaItem item) => sum + (item.fileSize > 0 ? item.fileSize : 0),
  );

  Map<String, MediaItem> get mediaById => <String, MediaItem>{
    for (final MediaItem item in media) item.id: item,
  };

  MediaItem? itemById(String id) {
    for (final MediaItem item in media) {
      if (item.id == id) return item;
    }
    return null;
  }

  SourceFolder? folderById(String id) {
    for (final SourceFolder folder in folders) {
      if (folder.id == id) return folder;
    }
    return null;
  }

  Category? categoryById(String id) {
    for (final Category category in categories) {
      if (category.id == id) return category;
    }
    return null;
  }

  Playlist? playlistById(String id) {
    for (final Playlist playlist in playlists) {
      if (playlist.id == id) return playlist;
    }
    return null;
  }

  PlaybackProgress? progressOf(String mediaId) => progress[mediaId];

  /// 首页文件夹：只展示有视频且未隐藏的文件夹。
  List<SourceFolder> get visibleFolders {
    final List<SourceFolder> result = folders
        .where(
          (SourceFolder folder) => !folder.isHidden && folder.itemCount > 0,
        )
        .toList(growable: false);
    result.sort(
      (SourceFolder a, SourceFolder b) =>
          a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    return result;
  }

  List<SourceFolder> get hiddenFolders =>
      folders.where((SourceFolder folder) => folder.isHidden).toList();

  List<MediaItem> mediaInFolder(String folderId) =>
      media.where((MediaItem item) => item.folderId == folderId).toList();

  List<MediaItem> get favorites =>
      media.where((MediaItem item) => item.isFavorite).toList();

  List<MediaItem> get availableMedia =>
      media.where((MediaItem item) => item.isAvailable).toList();

  List<MediaItem> mediaInCategory(String categoryId) {
    final Category? category = categoryById(categoryId);
    if (category == null) return const <MediaItem>[];
    final Set<String> ids = category.mediaIds.toSet();
    return media.where((MediaItem item) => ids.contains(item.id)).toList();
  }

  List<MediaItem> mediaInPlaylist(String playlistId) {
    final Playlist? playlist = playlistById(playlistId);
    if (playlist == null) return const <MediaItem>[];
    final Map<String, MediaItem> index = mediaById;
    return playlist.mediaIds
        .map((String id) => index[id])
        .whereType<MediaItem>()
        .toList(growable: false);
  }

  /// 继续观看：已开始、未看完，按最近播放倒序。
  List<MediaItem> get continueWatching {
    final List<MediaItem> result = <MediaItem>[];
    for (final MediaItem item in media) {
      final PlaybackProgress? record = progress[item.id];
      if (record == null) continue;
      if (record.completed) continue;
      if (record.fraction <= 0.01) continue;
      if (record.fraction >= PlaybackProgress.completionThreshold) continue;
      if (!item.isAvailable) continue;
      result.add(item);
    }
    result.sort((MediaItem a, MediaItem b) {
      final DateTime at = progress[a.id]?.lastPlayedAt ?? DateTime(1970);
      final DateTime bt = progress[b.id]?.lastPlayedAt ?? DateTime(1970);
      return bt.compareTo(at);
    });
    return result;
  }

  /// 最近播放：所有有播放记录的视频，按时间倒序。
  List<MediaItem> get recentlyPlayed {
    final List<MediaItem> result = <MediaItem>[];
    for (final MediaItem item in media) {
      if (progress.containsKey(item.id)) result.add(item);
    }
    result.sort((MediaItem a, MediaItem b) {
      final DateTime at = progress[a.id]?.lastPlayedAt ?? DateTime(1970);
      final DateTime bt = progress[b.id]?.lastPlayedAt ?? DateTime(1970);
      return bt.compareTo(at);
    });
    return result;
  }

  /// 已看完：达到完成阈值。
  List<MediaItem> get completedItems {
    final List<MediaItem> result = <MediaItem>[];
    for (final MediaItem item in media) {
      final PlaybackProgress? record = progress[item.id];
      if (record != null && record.completed) result.add(item);
    }
    result.sort((MediaItem a, MediaItem b) {
      final DateTime at = progress[a.id]?.lastPlayedAt ?? DateTime(1970);
      final DateTime bt = progress[b.id]?.lastPlayedAt ?? DateTime(1970);
      return bt.compareTo(at);
    });
    return result;
  }

  /// 按名称模糊搜索；[folderId] 为空时搜索全部视频。
  List<MediaItem> search(String query, {String? folderId}) {
    final String keyword = query.trim().toLowerCase();
    if (keyword.isEmpty) return const <MediaItem>[];
    return media.where((MediaItem item) {
      if (folderId != null && item.folderId != folderId) return false;
      return item.displayName.toLowerCase().contains(keyword) ||
          item.originalName.toLowerCase().contains(keyword);
    }).toList();
  }

  LibraryState copyWith({
    List<MediaItem>? media,
    List<SourceFolder>? folders,
    List<Category>? categories,
    List<Playlist>? playlists,
    Map<String, PlaybackProgress>? progress,
    MediaPermission? permission,
    bool? isScanning,
    double? scanProgress,
    String? scanMessage,
    bool clearScanMessage = false,
    DateTime? lastScanAt,
  }) {
    return LibraryState(
      media: media ?? this.media,
      folders: folders ?? this.folders,
      categories: categories ?? this.categories,
      playlists: playlists ?? this.playlists,
      progress: progress ?? this.progress,
      permission: permission ?? this.permission,
      isScanning: isScanning ?? this.isScanning,
      scanProgress: scanProgress ?? this.scanProgress,
      scanMessage: clearScanMessage ? null : (scanMessage ?? this.scanMessage),
      lastScanAt: lastScanAt ?? this.lastScanAt,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'media': media.map((MediaItem item) => item.toJson()).toList(),
    'folders': folders.map((SourceFolder folder) => folder.toJson()).toList(),
    'categories': categories
        .map((Category category) => category.toJson())
        .toList(),
    'playlists': playlists.map((Playlist list) => list.toJson()).toList(),
    'progress': progress.values
        .map((PlaybackProgress record) => record.toJson())
        .toList(),
    'permission': permission.name,
    'lastScanAt': lastScanAt?.toIso8601String(),
  };
}

/// 排序：名称升/降序、添加时间、修改时间、时长、文件大小。
List<MediaItem> sortMedia(List<MediaItem> items, SortOption option) {
  final List<MediaItem> result = List<MediaItem>.of(items);
  int byName(MediaItem a, MediaItem b) =>
      a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
  DateTime added(MediaItem item) => item.createdAt;
  DateTime modified(MediaItem item) => item.modifiedAt ?? item.createdAt;

  switch (option) {
    case SortOption.nameAsc:
      result.sort(byName);
    case SortOption.nameDesc:
      result.sort((MediaItem a, MediaItem b) => byName(b, a));
    case SortOption.dateAdded:
      result.sort((MediaItem a, MediaItem b) => added(b).compareTo(added(a)));
    case SortOption.dateModified:
      result.sort(
        (MediaItem a, MediaItem b) => modified(b).compareTo(modified(a)),
      );
    case SortOption.duration:
      result.sort(
        (MediaItem a, MediaItem b) => b.durationMs.compareTo(a.durationMs),
      );
    case SortOption.fileSize:
      result.sort(
        (MediaItem a, MediaItem b) => b.fileSize.compareTo(a.fileSize),
      );
  }
  return result;
}
