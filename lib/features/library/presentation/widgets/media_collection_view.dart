// -------------------------------------------------------------------------
// 功能：视频集合容器
//
// 主要内容：
// - 根据视图模式渲染列表或网格
// - 多选状态下的点击/长按分发
// - 多选页头 SelectionHeader
// -------------------------------------------------------------------------

import 'package:flutter/material.dart';

import 'media_tiles.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/ui_kit.dart';
import '../../domain/models.dart';

// ===== 列表 / 网格容器 =====
/// 视频列表：列表 / 网格两种模式，支持多选状态渲染。
class MediaCollectionView extends StatelessWidget {
  const MediaCollectionView({
    super.key,
    required this.items,
    required this.viewMode,
    required this.onTap,
    required this.onLongPress,
    required this.onMore,
    this.progress = const <String, PlaybackProgress>{},
    this.selectionMode = false,
    this.selectedIds = const <String>{},
    this.padding = const EdgeInsets.fromLTRB(16, 4, 16, 24),
    this.shrinkWrap = false,
    this.physics,
  });

  final List<MediaItem> items;
  final ViewMode viewMode;
  final void Function(MediaItem item) onTap;
  final void Function(MediaItem item) onLongPress;
  final void Function(MediaItem item) onMore;
  final Map<String, PlaybackProgress> progress;
  final bool selectionMode;
  final Set<String> selectedIds;
  final EdgeInsets padding;
  final bool shrinkWrap;
  final ScrollPhysics? physics;

  @override
  Widget build(BuildContext context) {
    if (viewMode == ViewMode.grid) {
      return GridView.builder(
        padding: padding,
        shrinkWrap: shrinkWrap,
        physics: physics ?? const AlwaysScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 14,
          crossAxisSpacing: 12,
          childAspectRatio: 0.92,
        ),
        itemCount: items.length,
        itemBuilder: (BuildContext context, int index) {
          final MediaItem item = items[index];
          return MediaGridTile(
            item: item,
            selected: selectedIds.contains(item.id),
            selectionMode: selectionMode,
            progress: progress[item.id],
            onTap: () => onTap(item),
            onLongPress: () => onLongPress(item),
            onMore: () => onMore(item),
          );
        },
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: ListView.separated(
        padding: padding,
        shrinkWrap: shrinkWrap,
        physics: physics ?? const AlwaysScrollableScrollPhysics(),
        itemCount: items.length,
        separatorBuilder: (BuildContext context, int index) => Divider(
          height: 1,
          thickness: 1,
          indent: 128,
          color: context.dividerColor,
        ),
        itemBuilder: (BuildContext context, int index) {
          final MediaItem item = items[index];
          return MediaListTile(
            item: item,
            selected: selectedIds.contains(item.id),
            selectionMode: selectionMode,
            progress: progress[item.id],
            onTap: () => onTap(item),
            onLongPress: () => onLongPress(item),
            onMore: () => onMore(item),
          );
        },
      ),
    );
  }
}

// ===== 多选页头 =====
/// 多选状态下的顶部栏。
class SelectionHeader extends StatelessWidget {
  const SelectionHeader({
    super.key,
    required this.count,
    required this.total,
    required this.onSelectAll,
    required this.onClose,
  });

  final int count;
  final int total;
  final VoidCallback onSelectAll;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: context.appBackground,
      padding: const EdgeInsets.fromLTRB(4, 8, 8, 10),
      child: Row(
        children: <Widget>[
          AppIconButton(icon: Icons.close_rounded, onPressed: onClose),
          const SizedBox(width: 2),
          Text(
            '已选择 $count 项',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: context.textPrimary,
            ),
          ),
          const Spacer(),
          TextButton(
            onPressed: onSelectAll,
            child: Text(count == total ? '取消全选' : '全选'),
          ),
        ],
      ),
    );
  }
}

/// 视频详情弹窗。
Future<void> showMediaDetailDialog(BuildContext context, MediaItem item) {
  return showDialog<void>(
    context: context,
    builder: (BuildContext dialogContext) {
      final List<List<String>> rows = <List<String>>[
        <String>['名称', item.displayName],
        <String>['原始名称', item.originalName],
        <String>['时长', formatDuration(item.durationMs)],
        <String>['分辨率', formatResolution(item.width, item.height)],
        <String>['文件大小', formatBytes(item.fileSize)],
        <String>[
          '来源',
          item.sourceType == MediaSourceType.imported ? '应用内导入' : '系统相册',
        ],
        <String>['路径', item.sourceLocator],
      ];
      return AlertDialog(
        title: Text(
          '视频详情',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: dialogContext.textPrimary,
          ),
        ),
        content: SizedBox(
          width: 340,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: rows
                .map(
                  (List<String> row) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        SizedBox(
                          width: 70,
                          child: Text(
                            row[0],
                            style: TextStyle(
                              fontSize: 12.5,
                              color: dialogContext.textSecondary,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            row[1],
                            style: TextStyle(
                              fontSize: 12.5,
                              height: 1.4,
                              color: dialogContext.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('关闭'),
          ),
        ],
      );
    },
  );
}
