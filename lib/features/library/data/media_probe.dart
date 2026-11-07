import 'dart:async';
import 'dart:typed_data';
import 'dart:io';

import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';

/// 视频文件探测结果（导入时补齐时长、分辨率与封面）。
class ProbedMedia {
  const ProbedMedia({
    required this.durationMs,
    required this.width,
    required this.height,
    this.thumbnailPath,
  });

  final int durationMs;
  final int width;
  final int height;
  final String? thumbnailPath;
}

/// 用播放引擎探测本地视频元数据，并尝试截取一帧作为封面。
///
/// 仅在「导入」等低频路径调用，避免影响列表性能。
class MediaProbe {
  const MediaProbe();

  Future<ProbedMedia?> probe(String path, {String? thumbnailPath}) async {
    Player? player;
    try {
      player = Player(
        configuration: const PlayerConfiguration(title: 'ReelBox probe'),
      );
      await player.open(Media(path), play: false);
      final Duration duration = await player.stream.duration
          .firstWhere((Duration value) => value > Duration.zero)
          .timeout(const Duration(seconds: 8));
      int width = player.state.width ?? 0;
      int height = player.state.height ?? 0;
      if (width <= 0 || height <= 0) {
        try {
          final int? parsedWidth = await player.stream.width
              .firstWhere((int? value) => value != null && value > 0)
              .timeout(const Duration(seconds: 3));
          width = parsedWidth ?? width;
          height = player.state.height ?? height;
        } on Object {
          // 部分容器在探测阶段拿不到分辨率，保持 0 由 UI 显示占位。
        }
      }

      String? savedThumbnail;
      if (thumbnailPath != null) {
        try {
          await player.seek(
            Duration(milliseconds: duration.inMilliseconds ~/ 10),
          );
          await Future<void>.delayed(const Duration(milliseconds: 400));
          final Uint8List? bytes = await player.screenshot();
          if (bytes != null && bytes.isNotEmpty) {
            final File file = File(thumbnailPath);
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes, flush: true);
            savedThumbnail = file.path;
          }
        } on Exception {
          // 截图失败不影响导入，列表使用占位封面。
        }
      }

      return ProbedMedia(
        durationMs: duration.inMilliseconds,
        width: width,
        height: height,
        thumbnailPath: savedThumbnail,
      );
    } on Exception {
      return null;
    } finally {
      await player?.dispose();
    }
  }

  static Future<String> thumbnailCachePath(String mediaId) async {
    final Directory dir = await getApplicationCacheDirectory();
    final Directory thumbs = Directory(
      '${dir.path}${Platform.pathSeparator}thumbs',
    );
    if (!await thumbs.exists()) {
      await thumbs.create(recursive: true);
    }
    return '${thumbs.path}${Platform.pathSeparator}$mediaId.jpg';
  }
}
