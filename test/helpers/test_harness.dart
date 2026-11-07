import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myplayer/app/providers.dart';
import 'package:myplayer/app/router.dart';
import 'package:myplayer/core/database/local_database.dart';
import 'package:myplayer/core/theme/app_theme.dart';
import 'package:myplayer/features/library/data/library_repository.dart';
import 'package:myplayer/features/library/data/media_scanner.dart';
import 'package:myplayer/features/library/domain/models.dart';
import 'package:myplayer/features/settings/application/settings_controller.dart';
import 'package:myplayer/features/settings/domain/app_settings.dart';

/// 测试用媒体库：2 个文件夹、5 个视频、1 个分类、1 个播放列表与 2 条进度。
class TestLibrary {
  TestLibrary({
    required this.database,
    required this.repository,
    required this.state,
    required this.categoryId,
    required this.playlistId,
  });

  final LocalDatabase database;
  final LibraryRepository repository;
  final LibraryState state;
  final String categoryId;
  final String playlistId;
}

MediaItem _item({
  required String id,
  required String folderId,
  required String name,
  required int durationMs,
  required int size,
  required DateTime createdAt,
  int width = 1920,
  int height = 1080,
}) {
  return MediaItem(
    id: id,
    folderId: folderId,
    sourceType: MediaSourceType.imported,
    sourceId: 'imported:$id',
    sourceLocator: '/tmp/$id.mp4',
    displayName: name,
    originalName: name,
    mimeType: 'video/mp4',
    durationMs: durationMs,
    width: width,
    height: height,
    fileSize: size,
    createdAt: createdAt,
    updatedAt: createdAt,
    modifiedAt: createdAt,
  );
}

TestLibrary buildTestLibrary() {
  final LocalDatabase database = LocalDatabase.inMemory();
  final LibraryRepository repository = LibraryRepository(database: database);

  final DateTime base = DateTime(2025, 1, 16, 19, 32);
  final SourceFolder camera = SourceFolder(
    id: 'f-camera',
    name: 'Camera',
    path: '',
    itemCount: 0,
    totalSize: 0,
    lastScannedAt: base,
  );
  final SourceFolder movies = SourceFolder(
    id: 'f-movies',
    name: 'Movies',
    path: '',
    itemCount: 0,
    totalSize: 0,
    lastScannedAt: base,
  );

  final List<MediaItem> media = <MediaItem>[
    _item(
      id: 'm1',
      folderId: 'f-camera',
      name: 'C++ 网络编程（上）',
      durationMs: 2538000,
      size: 1024 * 1024 * 1000,
      createdAt: base,
    ),
    _item(
      id: 'm2',
      folderId: 'f-camera',
      name: 'Epoll 原理讲解',
      durationMs: 2165000,
      size: 986 * 1024 * 1024,
      createdAt: base.subtract(const Duration(days: 1)),
    ),
    _item(
      id: 'm3',
      folderId: 'f-camera',
      name: 'TCP 三次握手',
      durationMs: 1685000,
      size: 760 * 1024 * 1024,
      createdAt: base.subtract(const Duration(days: 2)),
    ),
    _item(
      id: 'm4',
      folderId: 'f-movies',
      name: 'Movies 之夜',
      durationMs: 900000,
      size: 420 * 1024 * 1024,
      createdAt: base.subtract(const Duration(days: 3)),
      width: 1280,
      height: 720,
    ),
    _item(
      id: 'm5',
      folderId: 'f-movies',
      name: '旅行记录',
      durationMs: 450000,
      size: 180 * 1024 * 1024,
      createdAt: base.subtract(const Duration(days: 4)),
    ),
  ];

  LibraryState state = const LibraryState();
  state = repository.mergeScan(
    state,
    folders: <SourceFolder>[camera, movies],
    scannedMedia: media,
    permission: MediaPermission.granted,
  );
  state = repository.toggleFavorite(state, 'm1');
  state = repository.createCategory(state, '学习资料');
  final String categoryId = state.categories.first.id;
  state = repository.addToCategories(
    state,
    <String>{'m1', 'm2'},
    <String>{categoryId},
  );
  state = repository.createPlaylist(state, '周末电影');
  final String playlistId = state.playlists.first.id;
  state = repository.addToPlaylists(
    state,
    <String>{'m1', 'm4'},
    <String>{playlistId},
  );
  state = repository.updateProgress(
    state,
    mediaId: 'm1',
    positionMs: 30000,
    durationMs: 100000,
  );
  state = repository.updateProgress(
    state,
    mediaId: 'm2',
    positionMs: 96000,
    durationMs: 100000,
  );

  return TestLibrary(
    database: database,
    repository: repository,
    state: state,
    categoryId: categoryId,
    playlistId: playlistId,
  );
}

/// 挂载应用（使用独立 Router 与内存数据库）。
Future<TestLibrary> pumpReelBox(
  WidgetTester tester, {
  String initialLocation = '/',
  AppSettings settings = const AppSettings(themeMode: AppThemeMode.light),
  TestLibrary? library,
}) async {
  final TestLibrary testLibrary = library ?? buildTestLibrary();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(testLibrary.database),
        initialLibraryStateProvider.overrideWithValue(testLibrary.state),
        initialSettingsProvider.overrideWithValue(settings),
        mediaScannerProvider.overrideWithValue(const UnsupportedMediaScanner()),
      ],
      child: _TestApp(initialLocation: initialLocation),
    ),
  );
  await tester.pumpAndSettle();
  return testLibrary;
}

class _TestApp extends ConsumerWidget {
  const _TestApp({required this.initialLocation});

  final String initialLocation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ref.watch(themeModeProvider),
      routerConfig: buildRouter(initialLocation: initialLocation),
    );
  }
}
