import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_harness.dart';

void main() {
  testWidgets('我的页面展示快捷宫格与设置入口', (WidgetTester tester) async {
    await pumpReelBox(tester);

    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();

    expect(find.text('ReelBox'), findsOneWidget);
    expect(find.text('我的收藏'), findsOneWidget);
    expect(find.text('隐藏文件夹'), findsOneWidget);
    expect(find.text('媒体管理'), findsOneWidget);
    expect(find.text('播放设置'), findsOneWidget);
    expect(find.text('外观与主题'), findsOneWidget);
    expect(find.text('存储管理'), findsOneWidget);
    expect(find.text('关于 ReelBox'), findsOneWidget);
  });

  testWidgets('主题切换到深色模式并立即生效', (WidgetTester tester) async {
    await pumpReelBox(tester, initialLocation: '/settings/appearance');

    expect(find.text('跟随系统'), findsOneWidget);
    expect(find.text('浅色模式'), findsOneWidget);

    await tester.tap(find.text('深色模式'));
    await tester.pumpAndSettle();

    final MaterialApp app = tester.widget<MaterialApp>(
      find.byType(MaterialApp),
    );
    expect(app.themeMode, ThemeMode.dark);
  });

  testWidgets('分类页展示分类并可以进入查看视频', (WidgetTester tester) async {
    await pumpReelBox(tester, initialLocation: '/categories');

    expect(find.text('我的分类'), findsOneWidget);
    expect(find.text('学习资料'), findsOneWidget);
    expect(find.textContaining('2 个视频'), findsOneWidget);

    await tester.tap(find.text('学习资料'));
    await tester.pumpAndSettle();

    expect(find.text('C++ 网络编程（上）'), findsOneWidget);
    expect(find.text('Epoll 原理讲解'), findsOneWidget);
    expect(find.text('Movies 之夜'), findsNothing);
  });

  testWidgets('播放列表页展示列表与视频数量', (WidgetTester tester) async {
    await pumpReelBox(tester, initialLocation: '/playlists');

    expect(find.text('播放列表'), findsOneWidget);
    expect(find.text('周末电影'), findsOneWidget);

    await tester.tap(find.text('周末电影'));
    await tester.pumpAndSettle();

    expect(find.text('播放全部'), findsOneWidget);
    expect(find.text('C++ 网络编程（上）'), findsOneWidget);
    expect(find.text('Movies 之夜'), findsOneWidget);
  });

  testWidgets('磁力页展示功能预告且按钮不可用', (WidgetTester tester) async {
    await pumpReelBox(tester);

    await tester.tap(find.text('磁力').first);
    await tester.pumpAndSettle();

    expect(find.text('功能开发中'), findsOneWidget);
    expect(find.text('添加磁力链接'), findsOneWidget);

    final OutlinedButton button = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, '添加磁力链接'),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('最近页展示观看记录与继续观看', (WidgetTester tester) async {
    await pumpReelBox(tester);

    await tester.tap(find.text('最近'));
    await tester.pumpAndSettle();

    expect(find.text('继续观看'), findsOneWidget);
    expect(find.text('已看完'), findsOneWidget);
    expect(find.textContaining('已观看 30%'), findsWidgets);
    // 已看完的视频只在「已看完」中出现一次，避免与最近播放重复。
    expect(find.text('Epoll 原理讲解'), findsOneWidget);
  });
}
