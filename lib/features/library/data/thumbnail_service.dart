import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';

import '../domain/models.dart';

/// 缩略图服务：磁盘缓存 + 懒加载，缓存缺失时返回 null 由 UI 显示占位图。
///
/// 缓存与原始视频完全分开：清理缓存不会删除任何视频文件。
class ThumbnailService {
  final Map<String, File?> _memoryCache = <String, File?>{};
  final Set<String> _inFlight = <String>{};
  String? _cacheDirectory;

  Future<File?> thumbnailOf(MediaItem item) async {
    if (_memoryCache.containsKey(item.id)) return _memoryCache[item.id];
    if (_inFlight.contains(item.id)) return null;
    _inFlight.add(item.id);
    try {
      final File? cached = await _readCached(item);
      if (cached != null) {
        _memoryCache[item.id] = cached;
        return cached;
      }
      if (item.sourceType != MediaSourceType.photoAsset) {
        _memoryCache[item.id] = null;
        return null;
      }
      final File? generated = await _generateFromAsset(item);
      _memoryCache[item.id] = generated;
      return generated;
    } on Exception {
      _memoryCache[item.id] = null;
      return null;
    } finally {
      _inFlight.remove(item.id);
    }
  }

  void evict(String mediaId) {
    _memoryCache.remove(mediaId);
  }

  Future<File?> _readCached(MediaItem item) async {
    final String? path = item.thumbnailPath;
    if (path != null && path.isNotEmpty) {
      final File file = File(path);
      if (await file.exists()) return file;
    }
    // 同一视频的封面使用固定文件名，重启后可以直接命中缓存。
    try {
      final Directory directory = await _thumbnailDirectory();
      final File cached = File(
        '${directory.path}${Platform.pathSeparator}${item.id}.jpg',
      );
      if (await cached.exists()) return cached;
    } on Exception {
      return null;
    }
    return null;
  }

  /// 清理缩略图缓存（不删除原始视频），返回释放的字节省略值。
  Future<int> clearCache() async {
    _memoryCache.clear();
    try {
      final Directory directory = await _thumbnailDirectory();
      int freed = 0;
      await for (final FileSystemEntity entity in directory.list()) {
        if (entity is File) {
          freed += await entity.length();
          await entity.delete();
        }
      }
      return freed;
    } on Exception {
      return 0;
    }
  }

  /// 当前缓存占用。
  Future<int> cacheSize() async {
    try {
      final Directory directory = await _thumbnailDirectory();
      int total = 0;
      await for (final FileSystemEntity entity in directory.list()) {
        if (entity is File) total += await entity.length();
      }
      return total;
    } on Exception {
      return 0;
    }
  }

  Future<File?> _generateFromAsset(MediaItem item) async {
    if (!Platform.isAndroid && !Platform.isIOS && !Platform.isMacOS) {
      return null;
    }
    final AssetEntity? asset = await AssetEntity.fromId(item.sourceId);
    if (asset == null) return null;
    final Uint8List? bytes = await asset.thumbnailDataWithSize(
      const ThumbnailSize(480, 270),
      quality: 82,
    );
    if (bytes == null || bytes.isEmpty) return null;

    final Directory directory = await _thumbnailDirectory();
    final File file = File(
      '${directory.path}${Platform.pathSeparator}${item.id}.jpg',
    );
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  Future<Directory> _thumbnailDirectory() async {
    final String? cached = _cacheDirectory;
    if (cached != null) return Directory(cached);
    final Directory base = await getApplicationCacheDirectory();
    final Directory directory = Directory(
      '${base.path}${Platform.pathSeparator}reelbox_thumbs',
    );
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    _cacheDirectory = directory.path;
    return directory;
  }
}
