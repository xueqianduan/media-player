import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:myplayer/app/providers.dart';
import 'package:myplayer/app/router.dart';
import 'package:myplayer/core/theme/app_theme.dart';
import 'package:myplayer/features/library/data/media_scanner.dart';
import 'package:myplayer/features/library/presentation/widgets/media_tiles.dart';
import 'package:myplayer/features/settings/application/settings_controller.dart';
import 'package:myplayer/features/settings/domain/app_settings.dart';

import '../test/helpers/test_harness.dart';

/// 端到端流程：本地视频库 → 文件夹 → 多选 → 添加到分类。
///
/// 使用内存数据库与固定媒体数据，避免依赖真机相册授权；
/// 真实播放需要设备上有视频文件，需单独在真机验证。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('文件夹浏览与批量分类流程可以走通', (WidgetTester tester) async {
    final TestLibrary library = buildTestLibrary();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(library.database),
          initialLibraryStateProvider.overrideWithValue(library.state),
          mediaScannerProvider.overrideWithValue(
            const UnsupportedMediaScanner(),
          ),
        ],
        child: MaterialApp.router(
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: ThemeMode.light,
          routerConfig: buildRouter(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Camera'), findsOneWidget);

    await tester.tap(find.text('Camera'));
    await tester.pumpAndSettle();
    expect(find.textContaining('共 3 个视频'), findsOneWidget);

    await tester.longPress(find.text('Epoll 原理讲解'));
    await tester.pumpAndSettle();
    expect(find.text('已选择 1 项'), findsOneWidget);

    await tester.tap(find.text('分类'));
    await tester.pumpAndSettle();
    expect(find.text('学习资料'), findsOneWidget);

    await tester.tap(find.text('学习资料'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认添加'));
    await tester.pumpAndSettle();

    expect(find.byType(MediaListTile), findsWidgets);
  });

  testWidgets('主题切换写入设置', (WidgetTester tester) async {
    final TestLibrary library = buildTestLibrary();
    final ProviderContainer container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(library.database),
        initialLibraryStateProvider.overrideWithValue(library.state),
        initialSettingsProvider.overrideWithValue(const AppSettings()),
        mediaScannerProvider.overrideWithValue(const UnsupportedMediaScanner()),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: ThemeMode.light,
          routerConfig: buildRouter(initialLocation: '/settings/appearance'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('深色模式'));
    await tester.pumpAndSettle();

    expect(
      container.read(settingsControllerProvider).themeMode,
      AppThemeMode.dark,
    );
  });
}
