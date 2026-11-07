import 'package:flutter_test/flutter_test.dart';
import 'package:myplayer/core/database/local_database.dart';
import 'package:myplayer/features/library/data/library_repository.dart';
import 'package:myplayer/features/library/domain/models.dart';

import '../helpers/test_harness.dart';

void main() {
  group('收藏', () {
    test('切换收藏只影响目标视频', () {
      final TestLibrary lib = buildTestLibrary();
      expect(lib.state.itemById('m1')!.isFavorite, isTrue);
      expect(lib.state.itemById('m3')!.isFavorite, isFalse);

      final LibraryState after = lib.repository.toggleFavorite(lib.state, 'm3');

      expect(after.itemById('m3')!.isFavorite, isTrue);
      expect(after.itemById('m1')!.isFavorite, isTrue);
      expect(after.itemById('m2')!.isFavorite, isFalse);
    });

    test('收藏状态持久化并可重新读取', () {
      final TestLibrary lib = buildTestLibrary();
      lib.repository.toggleFavorite(lib.state, 'm3');

      final LibraryState reloaded = lib.repository.load();

      expect(reloaded.itemById('m3')!.isFavorite, isTrue);
      expect(reloaded.favorites.length, 2);
    });

    test('批量收藏与取消收藏', () {
      final TestLibrary lib = buildTestLibrary();
      final LibraryState after = lib.repository.setFavorite(lib.state, <String>{
        'm2',
        'm3',
      }, true);
      expect(after.favorites.length, 3);

      final LibraryState cleared = lib.repository.setFavorite(after, <String>{
        'm1',
        'm2',
        'm3',
      }, false);
      expect(cleared.favorites, isEmpty);
    });
  });

  group('自定义分类', () {
    test('一个视频可以同时属于多个分类', () {
      final TestLibrary lib = buildTestLibrary();
      LibraryState state = lib.repository.createCategory(lib.state, '面试准备');
      final String interviewId = state.categories
          .firstWhere((Category c) => c.name == '面试准备')
          .id;

      state = lib.repository.addToCategories(
        state,
        <String>{'m1'},
        <String>{interviewId},
      );

      final Category learn = state.categories.firstWhere(
        (Category c) => c.id == lib.categoryId,
      );
      final Category interview = state.categories.firstWhere(
        (Category c) => c.id == interviewId,
      );

      expect(learn.mediaIds, contains('m1'));
      expect(interview.mediaIds, contains('m1'));
      expect(state.mediaInCategory(learn.id).length, 2);
      expect(state.mediaInCategory(interview.id).length, 1);
    });

    test('重复添加到同一分类是幂等的', () {
      final TestLibrary lib = buildTestLibrary();
      final LibraryState again = lib.repository.addToCategories(
        lib.state,
        <String>{'m1'},
        <String>{lib.categoryId},
      );
      final Category category = again.categoryById(lib.categoryId)!;
      expect(category.mediaIds.where((String id) => id == 'm1').length, 1);
    });

    test('删除分类只删除关联，不删除视频与其他分类', () {
      final TestLibrary lib = buildTestLibrary();
      LibraryState state = lib.repository.createCategory(lib.state, '临时分类');
      final String tempId = state.categories
          .firstWhere((Category c) => c.name == '临时分类')
          .id;
      state = lib.repository.addToCategories(
        state,
        <String>{'m1'},
        <String>{tempId},
      );

      final LibraryState after = lib.repository.deleteCategory(state, tempId);

      expect(after.categoryById(tempId), isNull);
      expect(after.itemById('m1'), isNotNull);
      expect(after.media.length, 5);
      expect(after.mediaInCategory(lib.categoryId).length, 2);
    });

    test('从分类移除视频不影响播放列表关联', () {
      final TestLibrary lib = buildTestLibrary();
      final LibraryState after = lib.repository.removeFromCategory(
        lib.state,
        <String>{'m1'},
        lib.categoryId,
      );

      expect(
        after.mediaInCategory(lib.categoryId).map((MediaItem m) => m.id),
        isNot(contains('m1')),
      );
      expect(
        after.mediaInPlaylist(lib.playlistId).map((MediaItem m) => m.id),
        contains('m1'),
      );
    });
  });

  group('播放列表', () {
    test('添加视频保持添加顺序', () {
      final TestLibrary lib = buildTestLibrary();
      expect(
        lib.state
            .mediaInPlaylist(lib.playlistId)
            .map((MediaItem item) => item.id),
        <String>['m1', 'm4'],
      );
    });

    test('拖动排序把第一项移动到末尾', () {
      final TestLibrary lib = buildTestLibrary();
      // ReorderableListView 语义：oldIndex=0, newIndex=2 表示移动到第 2 位。
      final LibraryState after = lib.repository.reorderPlaylist(
        lib.state,
        lib.playlistId,
        0,
        2,
      );

      expect(
        after.mediaInPlaylist(lib.playlistId).map((MediaItem item) => item.id),
        <String>['m4', 'm1'],
      );
      expect(after.playlists.first.updatedAt, isNotNull);
    });

    test('从播放列表移除不影响视频库记录', () {
      final TestLibrary lib = buildTestLibrary();
      final LibraryState after = lib.repository.removeFromPlaylist(
        lib.state,
        lib.playlistId,
        <String>{'m1'},
      );

      expect(after.mediaInPlaylist(lib.playlistId).length, 1);
      expect(after.media.length, 5);
    });

    test('删除播放列表不删除视频', () {
      final TestLibrary lib = buildTestLibrary();
      final LibraryState after = lib.repository.deletePlaylist(
        lib.state,
        lib.playlistId,
      );

      expect(after.playlistById(lib.playlistId), isNull);
      expect(after.media.length, 5);
    });
  });

  group('播放进度', () {
    test('小于 95% 不算看完，达到 95% 自动完成', () {
      final TestLibrary lib = buildTestLibrary();
      LibraryState state = lib.repository.updateProgress(
        lib.state,
        mediaId: 'm3',
        positionMs: 50000,
        durationMs: 100000,
      );
      expect(state.progressOf('m3')!.completed, isFalse);
      expect(state.progressOf('m3')!.fraction, closeTo(0.5, 0.001));

      state = lib.repository.updateProgress(
        state,
        mediaId: 'm3',
        positionMs: 96000,
        durationMs: 100000,
      );
      expect(state.progressOf('m3')!.completed, isTrue);
      expect(state.progressOf('m3')!.positionMs, 100000);
    });

    test('重新打开视频可以恢复上次位置', () {
      final TestLibrary lib = buildTestLibrary();
      final PlaybackProgress record = lib.repository.load().progressOf('m1')!;

      expect(record.positionMs, 30000);
      expect(record.shouldResume, isTrue);
      expect(record.completed, isFalse);
    });

    test('清空历史只删除进度，不删除视频与关联', () {
      final TestLibrary lib = buildTestLibrary();
      final LibraryState after = lib.repository.clearAllProgress(lib.state);

      expect(after.progress, isEmpty);
      expect(after.media.length, 5);
      expect(after.categories.first.mediaIds, contains('m1'));
    });
  });

  group('扫描合并', () {
    test('按 sourceId 去重并保留收藏、自定义名称与播放记录', () {
      final TestLibrary lib = buildTestLibrary();
      LibraryState state = lib.repository.renameMedia(lib.state, 'm1', '我的网络课');
      final MediaItem incoming = state
          .itemById('m1')!
          .copyWith(displayName: '原始名称');

      state = lib.repository.mergeScan(
        state,
        folders: state.folders,
        scannedMedia: <MediaItem>[incoming],
      );

      expect(
        state.media.where((MediaItem m) => m.sourceId == 'imported:m1').length,
        1,
      );
      expect(state.itemById('m1')!.displayName, '我的网络课');
      expect(state.itemById('m1')!.isFavorite, isTrue);
      expect(state.progressOf('m1'), isNotNull);
    });

    test('本次未出现的相册资源标记为不可访问，不删除记录', () {
      final LocalDatabaseTestDouble harness = LocalDatabaseTestDouble();
      final LibraryRepository repository = harness.repository;
      final MediaItem item = harness.photoItem(id: 'p1', sourceId: 'asset-1');
      LibraryState state = repository.mergeScan(
        const LibraryState(),
        folders: harness.folders,
        scannedMedia: <MediaItem>[item],
      );
      expect(state.media.single.isAvailable, isTrue);

      state = repository.mergeScan(
        state,
        folders: harness.folders,
        scannedMedia: <MediaItem>[],
      );

      expect(state.media.length, 1);
      expect(state.media.single.isAvailable, isFalse);
    });
  });

  group('导入', () {
    test('同名同大小的视频不会重复导入', () {
      final TestLibrary lib = buildTestLibrary();
      final MediaItem original = lib.state.itemById('m1')!;
      final MediaItem duplicate = MediaItem(
        id: 'dup',
        folderId: 'imported',
        sourceType: MediaSourceType.imported,
        sourceId: 'imported:dup',
        sourceLocator: '/tmp/dup.mp4',
        displayName: original.displayName,
        originalName: original.originalName,
        mimeType: 'video/mp4',
        durationMs: original.durationMs,
        width: original.width,
        height: original.height,
        fileSize: original.fileSize,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final LibraryState after = lib.repository.addImportedMedia(
        lib.state,
        items: <MediaItem>[duplicate],
      );

      expect(after.media.length, 5);
      expect(after.media.where((MediaItem item) => item.id == 'dup'), isEmpty);
    });

    test('新视频会加入「导入的视频」文件夹', () {
      final TestLibrary lib = buildTestLibrary();
      final MediaItem fresh = MediaItem(
        id: 'new',
        folderId: 'imported',
        sourceType: MediaSourceType.imported,
        sourceId: 'imported:new',
        sourceLocator: '/tmp/new.mp4',
        displayName: '新导入的视频',
        originalName: '新导入的视频.mp4',
        mimeType: 'video/mp4',
        durationMs: 60000,
        width: 1920,
        height: 1080,
        fileSize: 1024 * 1024,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final LibraryState after = lib.repository.addImportedMedia(
        lib.state,
        items: <MediaItem>[fresh],
      );

      expect(after.media.length, 6);
      final SourceFolder imported = after.visibleFolders.firstWhere(
        (SourceFolder folder) => folder.name == '导入的视频',
      );
      expect(imported.itemCount, 1);
    });
  });

  group('从 ReelBox 移除', () {
    test('清理视频、分类关联、播放列表关联与进度', () {
      final TestLibrary lib = buildTestLibrary();
      final LibraryState after = lib.repository.removeFromLibrary(
        lib.state,
        <String>{'m1'},
      );

      expect(after.itemById('m1'), isNull);
      expect(after.media.length, 4);
      expect(after.categories.first.mediaIds, isNot(contains('m1')));
      expect(after.playlists.first.mediaIds, isNot(contains('m1')));
      expect(after.progressOf('m1'), isNull);
      expect(after.folders.first.itemCount, 2);
    });
  });
}

/// 只用于验证相册资源失效逻辑的最小替身。
class LocalDatabaseTestDouble {
  LocalDatabaseTestDouble()
    : repository = LibraryRepository(database: LocalDatabase.inMemory());

  final LibraryRepository repository;

  List<SourceFolder> get folders => <SourceFolder>[
    const SourceFolder(
      id: 'album',
      name: 'Camera',
      path: '',
      itemCount: 1,
      totalSize: 100,
    ),
  ];

  MediaItem photoItem({required String id, required String sourceId}) {
    return MediaItem(
      id: id,
      folderId: 'album',
      sourceType: MediaSourceType.photoAsset,
      sourceId: sourceId,
      sourceLocator: sourceId,
      displayName: '相册视频',
      originalName: '相册视频',
      mimeType: 'video/mp4',
      durationMs: 1000,
      width: 1920,
      height: 1080,
      fileSize: 100,
      createdAt: DateTime(2025),
      updatedAt: DateTime(2025),
    );
  }
}
