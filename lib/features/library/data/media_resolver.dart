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

    // 相册资源：优先用 photo_manager 换取可访问文件（iOS 会落到临时副本）。
    if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS) {
      try {
        final AssetEntity? asset = await AssetEntity.fromId(item.sourceId);
        final File? file = await asset?.file;
        if (file != null && await file.exists()) return file.path;
      } on Exception {
        // 权限被撤销或资源已删除。
      }
      return null;
    }

    final File fallback = File(item.sourceLocator);
    if (await fallback.exists()) return fallback.path;
    return null;
  }
}
