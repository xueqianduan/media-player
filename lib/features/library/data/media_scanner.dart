import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:uuid/uuid.dart';

import '../domain/models.dart';

/// 一次媒体扫描的结果。
class ScanOutcome {
  const ScanOutcome({
    required this.folders,
    required this.media,
    required this.permission,
  });

  final List<SourceFolder> folders;
  final List<MediaItem> media;
  final MediaPermission permission;
}

/// 媒体扫描抽象。Android / iOS 使用系统媒体库，其他平台不支持。
abstract interface class MediaScanner {
  bool get isSupported;

  Future<MediaPermission> requestPermission();

  Future<ScanOutcome> scan({
    void Function(double progress, String message)? onProgress,
  });

  Future<void> openSystemSettings();
}

/// 桌面 / Web 占位实现。
class UnsupportedMediaScanner implements MediaScanner {
  const UnsupportedMediaScanner();

  @override
  bool get isSupported => false;

  @override
  Future<MediaPermission> requestPermission() async =>
      MediaPermission.unsupported;

  @override
  Future<ScanOutcome> scan({
    void Function(double progress, String message)? onProgress,
  }) async {
    onProgress?.call(1, '当前平台不支持自动扫描，请手动导入视频');
    return const ScanOutcome(
      folders: <SourceFolder>[],
      media: <MediaItem>[],
      permission: MediaPermission.unsupported,
    );
  }

  @override
  Future<void> openSystemSettings() async {}
}

/// 基于 photo_manager 的系统相册扫描实现。
class PhotoManagerMediaScanner implements MediaScanner {
  PhotoManagerMediaScanner({Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  final Uuid _uuid;
  static const int _pageSize = 200;

  @override
  bool get isSupported {
    if (kIsWeb) return false;
    return Platform.isAndroid || Platform.isIOS || Platform.isMacOS;
  }

  @override
  Future<MediaPermission> requestPermission() async {
    if (!isSupported) return MediaPermission.unsupported;
    try {
      final PermissionState state = await PhotoManager.requestPermissionExtend(
        requestOption: const PermissionRequestOption(
          androidPermission: AndroidPermission(
            type: RequestType.video,
            mediaLocation: false,
          ),
        ),
      );
      return _mapPermission(state);
    } on Exception {
      return MediaPermission.denied;
    }
  }

  @override
  Future<void> openSystemSettings() async {
    if (!isSupported) return;
    await PhotoManager.openSetting();
  }

  MediaPermission _mapPermission(PermissionState state) {
    switch (state) {
      case PermissionState.authorized:
        return MediaPermission.granted;
      case PermissionState.limited:
        return MediaPermission.limited;
      case PermissionState.denied:
      case PermissionState.restricted:
        return MediaPermission.denied;
      case PermissionState.notDetermined:
        return MediaPermission.unknown;
    }
  }

  @override
  Future<ScanOutcome> scan({
    void Function(double progress, String message)? onProgress,
  }) async {
    if (!isSupported) {
      return const ScanOutcome(
        folders: <SourceFolder>[],
        media: <MediaItem>[],
        permission: MediaPermission.unsupported,
      );
    }

    final MediaPermission permission = await requestPermission();
    if (!permission.canRead) {
      return ScanOutcome(
        folders: const <SourceFolder>[],
        media: const <MediaItem>[],
        permission: permission,
      );
    }

    onProgress?.call(0.02, '正在读取相册分组…');
    final List<AssetPathEntity> albums = await PhotoManager.getAssetPathList(
      type: RequestType.video,
      hasAll: false,
      onlyAll: false,
    );

    final List<SourceFolder> folders = <SourceFolder>[];
    final List<MediaItem> media = <MediaItem>[];
    final Set<String> seenAssetIds = <String>{};
    final Map<String, int> albumCounts = <String, int>{};
    for (final AssetPathEntity album in albums) {
      albumCounts[album.id] = await album.assetCountAsync;
    }
    final int totalAssets = albumCounts.values.fold<int>(
      0,
      (int a, int b) => a + b,
    );
    int processed = 0;

    for (final AssetPathEntity album in albums) {
      if (album.isAll) continue;
      final String folderId = album.id;
      final String folderName = album.name;
      final List<MediaItem> folderItems = <MediaItem>[];
      int page = 0;
      while (true) {
        final List<AssetEntity> assets = await album.getAssetListPaged(
          page: page,
          size: _pageSize,
        );
        if (assets.isEmpty) break;
        for (final AssetEntity asset in assets) {
          processed++;
          if (!seenAssetIds.add(asset.id)) continue;
          final MediaItem? item = await _toMediaItem(asset, folderId);
          if (item == null) continue;
          folderItems.add(item);
          media.add(item);
          if (processed % 20 == 0 || processed == totalAssets) {
            final double progress = totalAssets == 0
                ? 1
                : (processed / totalAssets).clamp(0.02, 1.0);
            onProgress?.call(progress, '已扫描 $processed 个视频');
          }
        }
        page++;
      }

      if (folderItems.isEmpty) continue;
      folders.add(
        SourceFolder(
          id: folderId,
          name: folderName.isEmpty ? '未命名文件夹' : folderName,
          path: '',
          itemCount: folderItems.length,
          totalSize: folderItems.fold<int>(
            0,
            (int sum, MediaItem item) => sum + item.fileSize,
          ),
          lastScannedAt: DateTime.now(),
        ),
      );
    }

    onProgress?.call(1, '扫描完成，共 ${media.length} 个视频');
    return ScanOutcome(folders: folders, media: media, permission: permission);
  }

  Future<MediaItem?> _toMediaItem(AssetEntity asset, String folderId) async {
    try {
      final String title = await asset.titleAsync;
      final String name = title.trim().isNotEmpty ? title.trim() : '未命名视频';
      int fileSize = 0;
      String locator = asset.id;
      try {
        final File? file = await asset.file.timeout(const Duration(seconds: 3));
        if (file != null) {
          locator = file.path;
          fileSize = await file.length();
        }
      } on Exception {
        // 部分云同步资源无法立即取到本地文件，大小留空。
      }

      final DateTime created = asset.createDateTime;
      final DateTime modified = asset.modifiedDateTime;
      return MediaItem(
        id: _uuid.v4(),
        folderId: folderId,
        sourceType: MediaSourceType.photoAsset,
        sourceId: asset.id,
        sourceLocator: locator,
        displayName: name,
        originalName: name,
        mimeType: asset.mimeType ?? 'video/*',
        durationMs: asset.videoDuration.inMilliseconds,
        width: asset.width,
        height: asset.height,
        fileSize: fileSize,
        isAvailable: true,
        createdAt: created,
        updatedAt: DateTime.now(),
        modifiedAt: modified,
      );
    } on Exception {
      return null;
    }
  }
}
