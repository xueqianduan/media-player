import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// 本地文档数据库。
///
/// V1.0 只需要保存视频元数据、分类、播放列表与播放进度，数据量在几千条量级，
/// 因此采用「单文件 + 版本号 + 迁移函数」的存储方式，避免引入代码生成链路；
/// 对外接口保持 Repository 化，后续替换为 Drift/SQLite 时不影响业务层。
class LocalDatabase {
  LocalDatabase._(this._data, this._file);

  /// 当前数据结构版本。
  static const int schemaVersion = 2;

  final Map<String, dynamic> _data;
  final File? _file;
  Future<void> _writeQueue = Future<void>.value();

  Map<String, dynamic> get data => _data;
  bool get isPersistent => _file != null;

  /// 内存数据库，用于单元测试。
  factory LocalDatabase.inMemory([Map<String, dynamic>? seed]) {
    return LocalDatabase._(
      seed == null ? _emptyDocument() : migrate(seed),
      null,
    );
  }

  /// 打开应用私有目录下的数据库文件。
  static Future<LocalDatabase> open({String? directory}) async {
    final Directory base = directory != null
        ? Directory(directory)
        : await getApplicationSupportDirectory();
    final Directory folder = Directory(
      '${base.path}${Platform.pathSeparator}reelbox',
    );
    if (!await folder.exists()) {
      await folder.create(recursive: true);
    }
    final File file = File(
      '${folder.path}${Platform.pathSeparator}library.json',
    );

    Map<String, dynamic> raw = _emptyDocument();
    if (await file.exists()) {
      try {
        final String content = await file.readAsString();
        if (content.trim().isNotEmpty) {
          final Object? decoded = jsonDecode(content);
          if (decoded is Map<String, dynamic>) raw = decoded;
        }
      } on FormatException {
        // 文件损坏时回退为空库，避免应用无法启动。
        raw = _emptyDocument();
      }
    }

    return LocalDatabase._(migrate(raw), file);
  }

  static Map<String, dynamic> _emptyDocument() => <String, dynamic>{
    'schemaVersion': schemaVersion,
    'media': <dynamic>[],
    'folders': <dynamic>[],
    'categories': <dynamic>[],
    'playlists': <dynamic>[],
    'progress': <dynamic>[],
    'settings': <String, dynamic>{},
    'permission': 'unknown',
  };

  /// 结构迁移。旧版本数据在读取时升级到 [schemaVersion]。
  static Map<String, dynamic> migrate(Map<String, dynamic> raw) {
    final Map<String, dynamic> data = Map<String, dynamic>.from(raw);
    int version = (data['schemaVersion'] as num?)?.toInt() ?? 1;

    if (version < 2) {
      // v1 把收藏单独存成 id 数组，v2 合并进 media[].isFavorite。
      final List<String> favorites =
          (data['favorites'] as List<dynamic>? ?? <dynamic>[])
              .map((dynamic id) => id.toString())
              .toList();
      final List<dynamic> media =
          (data['media'] as List<dynamic>?) ?? <dynamic>[];
      for (final dynamic entry in media) {
        if (entry is Map<String, dynamic>) {
          entry['isFavorite'] = favorites.contains(entry['id']);
        }
      }
      data.remove('favorites');
      data['categories'] ??= <dynamic>[];
      data['playlists'] ??= <dynamic>[];
      version = 2;
    }

    data['schemaVersion'] = schemaVersion;
    data['media'] ??= <dynamic>[];
    data['folders'] ??= <dynamic>[];
    data['categories'] ??= <dynamic>[];
    data['playlists'] ??= <dynamic>[];
    data['progress'] ??= <dynamic>[];
    // 收藏夹（可多选），旧版本只有 media.isFavorite 布尔值。
    data['favoriteFolders'] ??= <dynamic>[];
    data['settings'] ??= <String, dynamic>{};
    data['permission'] ??= 'unknown';
    return data;
  }

  /// 写入磁盘（先写临时文件再替换，避免中途退出导致文件损坏）。
  Future<void> flush() {
    final File? file = _file;
    if (file == null) return Future<void>.value();
    _writeQueue = _writeQueue
        .then((_) async {
          final File temp = File('${file.path}.tmp');
          await temp.writeAsString(jsonEncode(_data), flush: true);
          if (await file.exists()) {
            await file.delete();
          }
          await temp.rename(file.path);
        })
        .catchError((Object error) {
          // 写入失败不应影响内存中的使用体验；下一次写入会重试。
        });
    return _writeQueue;
  }

  /// 覆盖某个表的数据。
  void writeTable(String table, Object? value) {
    _data[table] = value;
  }

  Map<String, dynamic> readTable(String table) {
    final Object? value = _data[table];
    if (value is Map<String, dynamic>) return value;
    return <String, dynamic>{};
  }

  List<dynamic> readList(String table) {
    final Object? value = _data[table];
    if (value is List<dynamic>) return value;
    return <dynamic>[];
  }
}
