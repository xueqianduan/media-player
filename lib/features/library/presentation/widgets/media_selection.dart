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
    // 这个操作条放在页面 body 的最底部（不放进 Scaffold.bottomNavigationBar），
    // 这样 MediaQuery.padding.bottom 仍然有效；再用 minimum 兜底，保证即使
    // ROM 把底部安全区报成 0，按钮也离开屏幕最底边、不落进系统手势区被吞掉。
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 24),
        child: Material(
          color: context.cardColorHigh,
          elevation: 10,
          shadowColor: Colors.black26,
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
            child: Row(
              children: <Widget>[
                _SelectionAction(
                  icon: favorited
                      ? Icons.star_rounded
                      : Icons.star_border_rounded,
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
        ),
      ),
    );
  }
}

class _SelectionAction extends StatefulWidget {
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
  State<_SelectionAction> createState() => _SelectionActionState();
}

class _SelectionActionState extends State<_SelectionAction> {
  bool _pressed = false;
  DateTime? _lastFired;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  /// 在「按下」时就执行，而不是等抬手。
  ///
  /// 部分 ROM 的系统手势区会把底部的抬手事件取消掉（只给一个 pointer cancel），
  /// 表现就是「按下去有水波纹，但什么也没发生」。这里不等抬手，按下即响应；
  /// 再用 500ms 去抖防止连点重复打开面板。
  void _fire() {
    final DateTime now = DateTime.now();
    if (_lastFired != null &&
        now.difference(_lastFired!) < const Duration(milliseconds: 500)) {
      return;
    }
    _lastFired = now;
    debugPrint('[ReelBox] selection action: ${widget.label}');
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final Color iconColor = widget.color ?? context.textPrimary;
    final Color pressColor = context.isDark
        ? Colors.white.withValues(alpha: 0.10)
        : Colors.black.withValues(alpha: 0.06);
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (TapDownDetails _) {
          _setPressed(true);
          _fire();
        },
        onTapUp: (TapUpDetails _) => _setPressed(false),
        onTapCancel: () => _setPressed(false),
        child: Padding(
          // 触摸热区约 56dp，手指不用点得很准。
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              // 圆形的按压反馈，比 InkWell 的整条矩形水波纹小得多。
              AnimatedContainer(
                duration: const Duration(milliseconds: 110),
                width: 38,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _pressed ? pressColor : Colors.transparent,
                ),
                child: Icon(widget.icon, size: 21, color: iconColor),
              ),
              const SizedBox(height: 2),
              Text(
                widget.label,
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
