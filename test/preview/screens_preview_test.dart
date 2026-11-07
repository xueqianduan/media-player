@Tags(<String>['preview'])
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myplayer/app/providers.dart';
import 'package:myplayer/app/router.dart';
import 'package:myplayer/core/theme/app_theme.dart';
import 'package:myplayer/features/library/data/media_scanner.dart';
import 'package:myplayer/features/settings/domain/app_settings.dart';

import '../helpers/test_harness.dart';

/// 生成设计预览图：`flutter test test/preview --update-goldens` 不参与 CI。
///
/// 使用系统黑体渲染中文，输出到 `docs/preview/`，便于核对界面样式。
void main() {
  const String fontPath = 'C:/Windows/Fonts/simhei.ttf';
  final GlobalKey boundaryKey = GlobalKey();

  setUpAll(() async {
    Future<void> loadFont(String family, String path) async {
      final File font = File(path);
      if (!font.existsSync()) return;
      final Uint8List bytes = await font.readAsBytes();
      final FontLoader loader = FontLoader(family)
        ..addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
      await loader.load();
    }

    await loadFont('PreviewCJK', fontPath);
    // 测试环境默认不加载 Material 图标字体，预览图里需要手动注册。
    await loadFont(
      'MaterialIcons',
      'D:/Android/Flutter/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
    );
  });

  Future<void> capture(WidgetTester tester, String name) async {
    await tester.runAsync(() async {
      final RenderRepaintBoundary boundary =
          boundaryKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      final ui.Image image = await boundary.toImage(pixelRatio: 2);
      final ByteData? data = await image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      final Directory directory = Directory('docs/preview');
      if (!directory.existsSync()) directory.createSync(recursive: true);
      await File(
        '${directory.path}/$name.png',
      ).writeAsBytes(data!.buffer.asUint8List(), flush: true);
    });
  }

  Future<TestLibrary> pump(
    WidgetTester tester,
    String location, {
    AppSettings settings = const AppSettings(themeMode: AppThemeMode.light),
  }) async {
    final TestLibrary library = buildTestLibrary();
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final ThemeData light = AppTheme.light();
    final ThemeData dark = AppTheme.dark();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(library.database),
          initialLibraryStateProvider.overrideWithValue(library.state),
          initialSettingsProvider.overrideWithValue(settings),
          mediaScannerProvider.overrideWithValue(
            const UnsupportedMediaScanner(),
          ),
        ],
        child: RepaintBoundary(
          key: boundaryKey,
          child: MaterialApp.router(
            debugShowCheckedModeBanner: false,
            theme: light.copyWith(
              textTheme: light.textTheme.apply(fontFamily: 'PreviewCJK'),
            ),
            darkTheme: dark.copyWith(
              textTheme: dark.textTheme.apply(fontFamily: 'PreviewCJK'),
            ),
            themeMode: settings.themeMode == AppThemeMode.dark
                ? ThemeMode.dark
                : ThemeMode.light,
            routerConfig: buildRouter(initialLocation: location),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return library;
  }

  testWidgets('生成首页预览', (WidgetTester tester) async {
    await pump(tester, '/');
    await capture(tester, '01-local');
  });

  testWidgets('生成文件夹预览', (WidgetTester tester) async {
    await pump(tester, '/folder/f-camera');
    await capture(tester, '02-folder');
  });

  testWidgets('生成最近预览', (WidgetTester tester) async {
    await pump(tester, '/');
    await tester.tap(find.text('最近'));
    await tester.pumpAndSettle();
    await capture(tester, '03-recent');
  });

  testWidgets('生成我的预览', (WidgetTester tester) async {
    await pump(tester, '/');
    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();
    await capture(tester, '04-profile');
  });

  testWidgets('生成磁力预览', (WidgetTester tester) async {
    await pump(tester, '/');
    await tester.tap(find.text('磁力').first);
    await tester.pumpAndSettle();
    await capture(tester, '05-magnet');
  });

  testWidgets('生成分类预览', (WidgetTester tester) async {
    await pump(tester, '/categories');
    await capture(tester, '06-categories');
  });

  testWidgets('生成播放列表预览', (WidgetTester tester) async {
    await pump(tester, '/playlists');
    await capture(tester, '07-playlists');
  });

  testWidgets('生成深色首页预览', (WidgetTester tester) async {
    await pump(
      tester,
      '/',
      settings: const AppSettings(themeMode: AppThemeMode.dark),
    );
    await capture(tester, '08-dark');
  });
}
