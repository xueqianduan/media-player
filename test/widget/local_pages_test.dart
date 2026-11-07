import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myplayer/features/library/presentation/widgets/media_tiles.dart';

import '../helpers/test_harness.dart';

void main() {
  testWidgets('首页展示文件夹列表与快捷入口', (WidgetTester tester) async {
    await pumpReelBox(tester);

    expect(find.text('本地视频'), findsOneWidget);
    expect(find.text('Camera'), findsOneWidget);
    expect(find.text('Movies'), findsOneWidget);
    expect(find.textContaining('3 个视频'), findsOneWidget);
    expect(find.text('全部视频'), findsOneWidget);
    expect(find.text('最近播放'), findsOneWidget);
    expect(find.text('我的收藏'), findsOneWidget);
    expect(find.text('播放列表'), findsOneWidget);
  });

  testWidgets('点击文件夹进入视频列表', (WidgetTester tester) async {
    await pumpReelBox(tester);

    await tester.tap(find.text('Camera'));
    await tester.pumpAndSettle();

    expect(find.textContaining('共 3 个视频'), findsOneWidget);
    expect(find.text('C++ 网络编程（上）'), findsOneWidget);
    expect(find.text('TCP 三次握手'), findsOneWidget);
    expect(find.text('Movies 之夜'), findsNothing);
  });

  testWidgets('长按视频进入多选模式', (WidgetTester tester) async {
    await pumpReelBox(tester, initialLocation: '/folder/f-camera');

    await tester.longPress(find.text('Epoll 原理讲解'));
    await tester.pumpAndSettle();

    expect(find.text('已选择 1 项'), findsOneWidget);
    expect(find.text('全选'), findsOneWidget);

    await tester.tap(find.text('全选'));
    await tester.pumpAndSettle();
    expect(find.text('已选择 3 项'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();
    expect(find.textContaining('共 3 个视频'), findsOneWidget);
  });

  testWidgets('视频操作菜单可以收藏并给出反馈', (WidgetTester tester) async {
    await pumpReelBox(tester, initialLocation: '/folder/f-camera');

    final Finder row = find.ancestor(
      of: find.text('TCP 三次握手'),
      matching: find.byType(MediaListTile),
    );
    await tester.tap(
      find.descendant(of: row, matching: find.byIcon(Icons.more_vert_rounded)),
    );
    await tester.pumpAndSettle();

    expect(find.text('添加到分类'), findsOneWidget);
    expect(find.text('添加到播放列表'), findsOneWidget);
    expect(find.text('从 ReelBox 移除'), findsOneWidget);

    await tester.tap(find.text('收藏'));
    await tester.pumpAndSettle();

    expect(find.text('已加入收藏'), findsOneWidget);
  });

  testWidgets('分类选择弹窗可以勾选已有分类并确认', (WidgetTester tester) async {
    await pumpReelBox(tester, initialLocation: '/folder/f-camera');

    final Finder row = find.ancestor(
      of: find.text('TCP 三次握手'),
      matching: find.byType(MediaListTile),
    );
    await tester.tap(
      find.descendant(of: row, matching: find.byIcon(Icons.more_vert_rounded)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('添加到分类'));
    await tester.pumpAndSettle();

    expect(find.text('学习资料'), findsOneWidget);
    expect(find.text('确认添加'), findsOneWidget);

    await tester.tap(find.text('学习资料'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认添加'));
    await tester.pumpAndSettle();

    expect(find.text('已添加到 1 个分类'), findsOneWidget);
  });
}
