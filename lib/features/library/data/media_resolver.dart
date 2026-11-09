import 'dart:io';

import 'package:photo_manager/photo_manager.dart';

import '../domain/models.dart';

/// 把 [MediaItem] 解析成播放引擎可打开的本地路径。
class MediaResolver {
  const MediaResolver();

  Future<String?> resolve(MediaItem item) async {
    if (item.sourceType == MediaSourceType.imported) {
      final File file = File(item.sourceLocator);
      if (await file.exists()) return file.path;
      return null;
    }

    // 相册资源：扫描时如果已经拿到真实路径，直接用，避免每次都回查 MediaStore
    // （某些云同步资源在 fromId/file 上会长时间不返回）。
    final String cached = item.sourceLocator;
    if (cached.isNotEmpty &&
        !cached.startsWith('asset:') &&
        cached != item.sourceId) {
      final File file = File(cached);
      if (await file.exists()) return file.path;
    }

    // 回退 photo_manager，且必须带超时：解析卡住时调用方还要往下走。
    if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS) {
      try {
        final AssetEntity? asset = await AssetEntity.fromId(
          item.sourceId,
        ).timeout(const Duration(seconds: 5));
        if (asset == null) return null;
        final File? file = await asset.file.timeout(const Duration(seconds: 8));
        if (file != null && await file.exists()) return file.path;
      } on Object {
        // 权限被撤销、资源已删除或超时。
      }
      return null;
    }

    final File fallback = File(item.sourceLocator);
    if (await fallback.exists()) return fallback.path;
    return null;
  }
}
