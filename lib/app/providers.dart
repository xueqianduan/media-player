import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/database/local_database.dart';
import '../features/library/data/library_repository.dart';
import '../features/library/data/media_import_service.dart';
import '../features/library/data/media_resolver.dart';
import '../features/library/data/media_scanner.dart';
import '../features/library/data/thumbnail_service.dart';
import '../features/library/domain/models.dart';
import '../features/settings/data/settings_repository.dart';
import '../features/settings/domain/app_settings.dart';

/// 数据库实例（在 bootstrap 中 override）。
final Provider<LocalDatabase> databaseProvider = Provider<LocalDatabase>(
  (Ref ref) => throw UnimplementedError('databaseProvider 必须在启动时覆盖'),
);

final Provider<LibraryRepository> libraryRepositoryProvider =
    Provider<LibraryRepository>((Ref ref) {
      return LibraryRepository(database: ref.watch(databaseProvider));
    });

final Provider<SettingsRepository> settingsRepositoryProvider =
    Provider<SettingsRepository>((Ref ref) {
      return SettingsRepository(database: ref.watch(databaseProvider));
    });

/// 启动时读取的初始快照（在 bootstrap 中 override），避免首帧闪烁。
final Provider<LibraryState> initialLibraryStateProvider =
    Provider<LibraryState>((Ref ref) => const LibraryState());

final Provider<AppSettings> initialSettingsProvider = Provider<AppSettings>(
  (Ref ref) => const AppSettings(),
);

final Provider<MediaScanner> mediaScannerProvider = Provider<MediaScanner>((
  Ref ref,
) {
  if (kIsWeb) return const UnsupportedMediaScanner();
  if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS) {
    return PhotoManagerMediaScanner();
  }
  return const UnsupportedMediaScanner();
});

final Provider<ThumbnailService> thumbnailServiceProvider =
    Provider<ThumbnailService>((Ref ref) => ThumbnailService());

final Provider<MediaImportService> mediaImportServiceProvider =
    Provider<MediaImportService>((Ref ref) => MediaImportService());

final Provider<MediaResolver> mediaResolverProvider = Provider<MediaResolver>(
  (Ref ref) => const MediaResolver(),
);
