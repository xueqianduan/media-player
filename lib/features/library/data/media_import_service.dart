// -------------------------------------------------------------------------
// 功能：文件导入
//
// 主要内容：
// - file_picker 选择视频并复制到应用目录
// - 导入结果与失败的汇总
// -------------------------------------------------------------------------

import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../domain/models.dart';
import 'media_probe.dart';
import 'library_repository.dart';

/// 导入结果。
class ImportResult {
  const ImportResult({
    this.items = const <MediaItem>[],
    this.failed = 0,
    this.cancelled = false,
  });

  final List<MediaItem> items;
  final int failed;
  final bool cancelled;
}

/// 通过系统文件选择器导入视频。
///
/// 默认复制到应用私有目录，保证后续访问稳定（见 TRD 19.2）。
class MediaImportService {
  MediaImportService({this.probe = const MediaProbe(), Uuid? uuid})
    : _uuid = uuid ?? const Uuid();

  final MediaProbe probe;
  final Uuid _uuid;

  static const List<String> videoExtensions = <String>[
    'mp4',
    'mkv',
    'mov',
    'avi',
    'flv',
    'webm',
    'm4v',
    'ts',
    '3gp',
    'wmv',
    'mpg',
    'mpeg',
    'rmvb',
  ];

  Future<ImportResult> pickAndImport({
    void Function(double progress, String message)? onProgress,
  }) async {
    final List<PlatformFile> picked = await FilePicker.pickFiles(
      dialogTitle: '选择要导入的视频',
      type: FileType.custom,
      allowedExtensions: videoExtensions,
    );
    if (picked.isEmpty) return const ImportResult(cancelled: true);
    return importPicked(picked, onProgress: onProgress);
  }

  /// 便于测试与桌面端拖拽导入。
  Future<ImportResult> importPicked(
    List<PlatformFile> picked, {
    void Function(double progress, String message)? onProgress,
  }) async {
    final Directory support = await getApplicationSupportDirectory();
    final Directory target = Directory(
      '${support.path}${Platform.pathSeparator}imported',
    );
    if (!await target.exists()) {
      await target.create(recursive: true);
    }

    final List<MediaItem> items = <MediaItem>[];
    int failed = 0;
    for (int i = 0; i < picked.length; i++) {
      final PlatformFile file = picked[i];
      onProgress?.call(
        (i / picked.length).clamp(0.0, 1.0),
        '正在导入 ${i + 1}/${picked.length}',
      );
      try {
        final String? sourcePath = file.path;
        if (sourcePath == null) {
          failed++;
          continue;
        }
        final String id = _uuid.v4();
        final String extension = _extensionOf(file.name);
        final String destination =
            '${target.path}${Platform.pathSeparator}$id$extension';
        await File(sourcePath).copy(destination);
        final int size = await File(destination).length();

        String? thumbnailPath;
        try {
          thumbnailPath = await MediaProbe.thumbnailCachePath(id);
        } on Exception {
          thumbnailPath = null;
        }
        final ProbedMedia? probed = await probe.probe(
          destination,
          thumbnailPath: thumbnailPath,
        );
        final DateTime now = DateTime.now();
        items.add(
          MediaItem(
            id: id,
            folderId: LibraryRepository.importedFolderId,
            sourceType: MediaSourceType.imported,
            sourceId: 'imported:$id',
            sourceLocator: destination,
            displayName: file.name,
            originalName: file.name,
            mimeType: 'video/${extension.replaceFirst('.', '')}',
            durationMs: probed?.durationMs ?? 0,
            width: probed?.width ?? 0,
            height: probed?.height ?? 0,
            fileSize: size,
            thumbnailPath: probed?.thumbnailPath,
            createdAt: now,
            updatedAt: now,
            modifiedAt: now,
          ),
        );
      } on Exception {
        failed++;
      }
    }
    onProgress?.call(1, '导入完成');
    return ImportResult(items: items, failed: failed);
  }

  /// 支持 Web 环境下的字节导入（无本地路径）。
  Future<Uint8List?> readBytes(PlatformFile file) async {
    try {
      return await file.readAsBytes();
    } on Exception {
      return null;
    }
  }

  String _extensionOf(String name) {
    final int index = name.lastIndexOf('.');
    if (index <= 0 || index == name.length - 1) return '.mp4';
    final String ext = name.substring(index).toLowerCase();
    return videoExtensions.contains(ext.substring(1)) ? ext : '.mp4';
  }
}
