import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/models.dart';
import '../video_actions.dart';

/// 视频列表页的多选状态管理。
mixin MediaSelectionState<T extends ConsumerStatefulWidget>
    on ConsumerState<T> {
  final Set<String> selectedIds = <String>{};

  bool get selectionMode => selectedIds.isNotEmpty;

  void toggleSelection(MediaItem item) {
    setState(() {
      if (!selectedIds.remove(item.id)) {
        selectedIds.add(item.id);
      }
    });
  }

  void exitSelection() {
    setState(selectedIds.clear);
  }

  void selectAll(List<MediaItem> items) {
    setState(() {
      if (selectedIds.length == items.length) {
        selectedIds.clear();
      } else {
        selectedIds
          ..clear()
          ..addAll(items.map((MediaItem item) => item.id));
      }
    });
  }

  /// 点击：多选状态下切换选中，否则只播放当前这一个视频。
  void handleTap(MediaItem item) {
    if (selectionMode) {
      toggleSelection(item);
      return;
    }
    playSingleVideo(context, item);
  }

  void handleLongPress(MediaItem item) {
    if (!selectionMode) {
      setState(() => selectedIds.add(item.id));
    } else {
      toggleSelection(item);
    }
  }
}

/// 多选操作条。
class SelectionActionBar extends StatelessWidget {
  const SelectionActionBar({
    super.key,
    required this.onFavorite,
    required this.onCategory,
    required this.onPlaylist,
    required this.onMore,
    this.favorited = false,
  });

  /// 选中项是否已全部收藏：已收藏用实心星，否则空心星。
  final bool favorited;

  final VoidCallback onFavorite;
  final VoidCallback onCategory;
  final VoidCallback onPlaylist;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: context.cardColor,
      padding: const EdgeInsets.only(top: 6, bottom: 6),
      child: SafeArea(
        top: false,
        child: Row(
          children: <Widget>[
            _SelectionAction(
              icon: favorited ? Icons.star_rounded : Icons.star_border_rounded,
              label: '收藏',
              color: favorited ? AppColors.primary : null,
              onTap: onFavorite,
            ),
            _SelectionAction(
              icon: Icons.folder_copy_outlined,
              label: '分类',
              onTap: onCategory,
            ),
            _SelectionAction(
              icon: Icons.playlist_add_rounded,
              label: '播放列表',
              onTap: onPlaylist,
            ),
            _SelectionAction(
              icon: Icons.more_horiz_rounded,
              label: '更多',
              onTap: onMore,
            ),
          ],
        ),
      ),
    );
  }
}

class _SelectionAction extends StatelessWidget {
  const _SelectionAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 21, color: color ?? context.textPrimary),
              const SizedBox(height: 3),
              Text(
                label,
                style: TextStyle(fontSize: 10.5, color: context.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 顶部筛选/排序按钮组，供各页面复用。
class MediaPageActions extends ConsumerWidget {
  const MediaPageActions({
    super.key,
    this.onSearch,
    this.onSort,
    this.onToggleView,
    this.onMore,
    this.showSearch = true,
    this.showSort = true,
    this.showViewToggle = true,
    this.showMore = false,
  });

  final VoidCallback? onSearch;
  final VoidCallback? onSort;
  final VoidCallback? onToggleView;
  final VoidCallback? onMore;
  final bool showSearch;
  final bool showSort;
  final bool showViewToggle;
  final bool showMore;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (showSearch)
          IconButton(
            onPressed: onSearch,
            icon: const Icon(Icons.search_rounded, size: 21),
            color: context.textPrimary,
            tooltip: '搜索',
          ),
        if (showSort)
          IconButton(
            onPressed: onSort,
            icon: const Icon(Icons.swap_vert_rounded, size: 21),
            color: context.textPrimary,
            tooltip: '排序',
          ),
        if (showViewToggle)
          IconButton(
            onPressed: onToggleView,
            icon: const Icon(Icons.grid_view_rounded, size: 20),
            color: context.textPrimary,
            tooltip: '切换列表 / 网格',
          ),
        if (showMore)
          IconButton(
            onPressed: onMore,
            icon: const Icon(Icons.more_horiz_rounded, size: 21),
            color: context.textPrimary,
            tooltip: '更多',
          ),
        const SizedBox(width: 4),
      ],
    );
  }
}
