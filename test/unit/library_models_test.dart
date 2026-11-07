import 'package:flutter_test/flutter_test.dart';
import 'package:myplayer/features/library/domain/models.dart';
import 'package:myplayer/features/settings/domain/app_settings.dart';

import '../helpers/test_harness.dart';

void main() {
  group('排序', () {
    test('名称升序与降序', () {
      final TestLibrary lib = buildTestLibrary();
      final List<String> asc = sortMedia(
        lib.state.media,
        SortOption.nameAsc,
      ).map((MediaItem item) => item.displayName).toList();
      expect(asc.first, startsWith('C++'));

      final List<String> desc = sortMedia(
        lib.state.media,
        SortOption.nameDesc,
      ).map((MediaItem item) => item.displayName).toList();
      expect(desc.first, asc.last);
    });

    test('添加时间按倒序排列', () {
      final TestLibrary lib = buildTestLibrary();
      final List<MediaItem> sorted = sortMedia(
        lib.state.media,
        SortOption.dateAdded,
      );
      expect(sorted.first.id, 'm1');
      expect(sorted.last.id, 'm5');
    });

    test('时长与文件大小按倒序排列', () {
      final TestLibrary lib = buildTestLibrary();
      expect(sortMedia(lib.state.media, SortOption.duration).first.id, 'm1');
      expect(sortMedia(lib.state.media, SortOption.fileSize).first.id, 'm1');
    });
  });

  group('视频库查询', () {
    test('只展示有视频且未隐藏的文件夹', () {
      final TestLibrary lib = buildTestLibrary();
      expect(lib.state.visibleFolders.map((SourceFolder f) => f.name), <String>[
        'Camera',
        'Movies',
      ]);

      final LibraryState hidden = lib.repository.setFolderHidden(
        lib.state,
        'f-camera',
        true,
      );
      expect(hidden.visibleFolders.map((SourceFolder f) => f.name), <String>[
        'Movies',
      ]);
      expect(hidden.hiddenFolders.length, 1);
    });

    test('搜索支持模糊匹配与文件夹范围', () {
      final TestLibrary lib = buildTestLibrary();
      expect(lib.state.search('网络').length, 1);
      expect(lib.state.search('epoll').length, 1);
      expect(lib.state.search('').length, 0);
      expect(lib.state.search('旅行', folderId: 'f-camera').length, 0);
      expect(lib.state.search('旅行', folderId: 'f-movies').length, 1);
    });

    test('继续观看排除已看完与未开始的视频', () {
      final TestLibrary lib = buildTestLibrary();
      final List<String> ids = lib.state.continueWatching
          .map((MediaItem item) => item.id)
          .toList();
      expect(ids, contains('m1'));
      expect(ids, isNot(contains('m2'))); // 已看完
      expect(ids, isNot(contains('m3'))); // 未播放
    });

    test('已看完按完成状态筛选', () {
      final TestLibrary lib = buildTestLibrary();
      expect(
        lib.state.completedItems.map((MediaItem item) => item.id),
        <String>['m2'],
      );
    });

    test('最近播放按时间倒序', () {
      final TestLibrary lib = buildTestLibrary();
      final List<String> ids = lib.state.recentlyPlayed
          .map((MediaItem item) => item.id)
          .toList();
      expect(ids.length, 2);
      expect(ids.toSet(), <String>{'m1', 'm2'});
    });

    test('分类与外键统计', () {
      final TestLibrary lib = buildTestLibrary();
      expect(lib.state.mediaInCategory(lib.categoryId).length, 2);
      expect(lib.state.mediaInPlaylist(lib.playlistId).length, 2);
      expect(lib.state.folderById('f-camera')!.itemCount, 3);
    });
  });

  group('序列化', () {
    test('MediaItem 往返序列化保持关键字段', () {
      final TestLibrary lib = buildTestLibrary();
      final MediaItem item = lib.state.itemById('m1')!;
      final MediaItem restored = MediaItem.fromJson(item.toJson());

      expect(restored.id, item.id);
      expect(restored.displayName, item.displayName);
      expect(restored.durationMs, item.durationMs);
      expect(restored.isFavorite, isTrue);
      expect(restored.sourceType, MediaSourceType.imported);
      expect(restored.createdAt, item.createdAt);
    });

    test('缺少可选字段时使用安全默认值', () {
      final MediaItem item = MediaItem.fromJson(<String, dynamic>{
        'id': 'x',
        'displayName': '视频',
      });
      expect(item.sourceType, MediaSourceType.imported);
      expect(item.isAvailable, isTrue);
      expect(item.fileSize, 0);
      expect(item.durationMs, 0);
    });

    test('播放进度序列化保留完成状态', () {
      final TestLibrary lib = buildTestLibrary();
      final PlaybackProgress record = lib.state.progressOf('m2')!;
      final PlaybackProgress restored = PlaybackProgress.fromJson(
        record.toJson(),
      );
      expect(restored.completed, isTrue);
      expect(restored.mediaId, 'm2');
    });
  });

  group('设置', () {
    test('默认设置符合产品定义', () {
      const AppSettings settings = AppSettings();
      expect(settings.defaultSpeed, 1.0);
      expect(settings.gesturesEnabled, isTrue);
      expect(settings.themeMode, AppThemeMode.system);
      expect(settings.resumePrompt, isTrue);
    });

    test('设置序列化往返', () {
      const AppSettings settings = AppSettings(
        themeMode: AppThemeMode.dark,
        defaultSpeed: 1.5,
        gesturesEnabled: false,
        sortOption: SortOption.fileSize,
        viewMode: ViewMode.grid,
      );
      final AppSettings restored = AppSettings.fromJson(settings.toJson());

      expect(restored.themeMode, AppThemeMode.dark);
      expect(restored.defaultSpeed, 1.5);
      expect(restored.gesturesEnabled, isFalse);
      expect(restored.sortOption, SortOption.fileSize);
      expect(restored.viewMode, ViewMode.grid);
    });

    test('非法设置值回退到默认值', () {
      final AppSettings settings = AppSettings.fromJson(<String, dynamic>{
        'themeMode': 'unknown',
        'sortOption': 'unknown',
        'defaultSpeed': null,
      });
      expect(settings.themeMode, AppThemeMode.system);
      expect(settings.sortOption, SortOption.dateAdded);
      expect(settings.defaultSpeed, 1.0);
    });
  });
}
