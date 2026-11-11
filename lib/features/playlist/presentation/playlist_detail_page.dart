// -------------------------------------------------------------------------
// 功能：播放列表详情页
//
// 主要内容：
// - 列表内视频展示与播放
// - 移除/排序等操作
// -------------------------------------------------------------------------

import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/ui_kit.dart';
import '../../library/application/library_controller.dart';
import '../../library/domain/models.dart';
import '../../library/presentation/video_actions.dart';
import '../../library/presentation/widgets/media_tiles.dart';
import '../../settings/application/settings_controller.dart';

/// 播放列表详情：支持播放全部、逐条播放与拖动排序。
///
/// 播放列表是独立的视频组织方式，列表内的播放会使用用户选择的播放模式：
/// 列表循环 / 单集循环 / 不循环。
class PlaylistDetailPage extends ConsumerWidget {
  const PlaylistDetailPage({super.key, required this.playlistId});

  final String playlistId;

  @override
  // ===== 页面骨架 =====
  Widget build(BuildContext context, WidgetRef ref) {
    final LibraryState state = ref.watch(libraryControllerProvider);
    final settings = ref.watch(settingsControllerProvider);
    final LibraryController controller = ref.read(
      libraryControllerProvider.notifier,
    );
    final Playlist? playlist = state.playlistById(playlistId);
    final List<MediaItem> items = state.mediaInPlaylist(playlistId);
    final RepeatMode repeatMode = settings.playlistRepeatMode;

    return Scaffold(
      backgroundColor: context.appBackground,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            PageHeader(
              title: playlist?.name ?? '播放列表',
              subtitle: '共 ${items.length} 个视频 · 拖动右侧图标可调整顺序',
              leading: AppIconButton(
                icon: Icons.arrow_back_ios_new_rounded,
                iconSize: 18,
                onPressed: () =>
                    context.canPop() ? context.pop() : context.go('/'),
              ),
              actions: <Widget>[
                IconButton(
                  tooltip: settings.viewMode == ViewMode.list ? '切换网格' : '切换列表',
                  onPressed: () => ref
                      .read(settingsControllerProvider.notifier)
                      .toggleViewMode(),
                  icon: Icon(
                    settings.viewMode == ViewMode.list
                        ? Icons.grid_view_rounded
                        : Icons.view_list_rounded,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ),
            if (items.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => openPlayer(
                          context,
                          items: items,
                          title: playlist?.name,
                          repeatMode: repeatMode,
                        ),
                        icon: const Icon(Icons.play_arrow_rounded, size: 20),
                        label: const Text('播放全部'),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    OutlinedButton.icon(
                      onPressed: () => _showModeSheet(context, ref, repeatMode),
                      icon: Icon(switch (repeatMode) {
                        RepeatMode.loopAll => Icons.repeat_rounded,
                        RepeatMode.loopOne => Icons.repeat_one_rounded,
                        _ => Icons.trending_flat_rounded,
                      }, size: 17),
                      label: Text(
                        repeatMode.label,
                        style: const TextStyle(fontSize: 12),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 13,
                        ),
                        side: BorderSide(color: context.dividerColor),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (items.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(
                  children: <Widget>[
                    Icon(
                      Icons.info_outline_rounded,
                      size: 14,
                      color: context.textSecondary,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        switch (repeatMode) {
                          RepeatMode.loopAll => '播完自动播放下一个，最后一个播完回到第一个',
                          RepeatMode.loopOne => '当前视频播完后从头重新播放',
                          RepeatMode.shuffle => '随机顺序播放下一个视频',
                          RepeatMode.sequential => '播完当前视频后自动停止',
                        },
                        style: TextStyle(
                          fontSize: 11,
                          color: context.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: items.isEmpty
                  ? const EmptyState(
                      icon: Icons.playlist_add_rounded,
                      title: '播放列表是空的',
                      message: '在视频的更多操作里选择「添加到播放列表」，把视频加进来。',
                    )
                  : settings.viewMode == ViewMode.grid
                  ? GridView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
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
                          progress: state.progress[item.id],
                          onTap: () => openPlayer(
                            context,
                            items: items,
                            index: index,
                            title: playlist?.name,
                            repeatMode: repeatMode,
                          ),
                          onMore: () =>
                              showVideoActionSheet(context, ref, item),
                          onLongPress: () {},
                        );
                      },
                    )
                  : ReorderableListView.builder(
                      padding: const EdgeInsets.only(bottom: 24),
                      buildDefaultDragHandles: false,
                      itemCount: items.length,
                      // ignore: deprecated_member_use
                      onReorder: (int oldIndex, int newIndex) => controller
                          .reorderPlaylist(playlistId, oldIndex, newIndex),
                      itemBuilder: (BuildContext context, int index) {
                        final MediaItem item = items[index];
                        return Container(
                          key: ValueKey<String>(item.id),
                          color: context.cardColor,
                          child: Row(
                            children: <Widget>[
                              Expanded(
                                child: MediaListTile(
                                  item: item,
                                  progress: state.progress[item.id],
                                  onTap: () => openPlayer(
                                    context,
                                    items: items,
                                    index: index,
                                    title: playlist?.name,
                                    repeatMode: repeatMode,
                                  ),
                                  onMore: () => _showItemActions(
                                    context,
                                    ref,
                                    item,
                                    playlistId,
                                  ),
                                ),
                              ),
                              ReorderableDragStartListener(
                                index: index,
                                child: Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: Icon(
                                    Icons.drag_handle_rounded,
                                    size: 22,
                                    color: context.textSecondary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // ===== 播放模式与条目操作面板 =====
  Future<void> _showModeSheet(
    BuildContext context,
    WidgetRef ref,
    RepeatMode current,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const SheetHeader(title: '播放模式', subtitle: '仅对播放列表生效，单个视频默认播完即停'),
              for (final RepeatMode mode in RepeatMode.playbackModes)
                ListTile(
                  onTap: () {
                    ref
                        .read(settingsControllerProvider.notifier)
                        .setPlaylistRepeatMode(mode);
                    Navigator.of(sheetContext).pop();
                    showToast(context, '播放模式：${mode.label}');
                  },
                  leading: Icon(
                    switch (mode) {
                      RepeatMode.loopAll => Icons.repeat_rounded,
                      RepeatMode.loopOne => Icons.repeat_one_rounded,
                      _ => Icons.trending_flat_rounded,
                    },
                    size: 20,
                    color: mode == current
                        ? AppColors.primary
                        : context.textSecondary,
                  ),
                  title: Text(
                    mode.label,
                    style: TextStyle(fontSize: 14, color: context.textPrimary),
                  ),
                  subtitle: Text(
                    switch (mode) {
                      RepeatMode.loopAll => '自动连播下一个，最后一个播完回到第一个',
                      RepeatMode.loopOne => '当前视频播完后从头重新播放',
                      _ => '播完当前视频后自动停止',
                    },
                    style: TextStyle(
                      fontSize: 11.5,
                      color: context.textSecondary,
                    ),
                  ),
                  trailing: mode == current
                      ? const Icon(
                          Icons.check_rounded,
                          size: 20,
                          color: AppColors.primary,
                        )
                      : null,
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showItemActions(
    BuildContext context,
    WidgetRef ref,
    MediaItem item,
    String playlistId,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              SheetHeader(title: item.displayName),
              SheetActionTile(
                icon: Icons.info_outline_rounded,
                label: '视频详情',
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  showVideoActionSheet(context, ref, item);
                },
              ),
              SheetActionTile(
                icon: Icons.playlist_remove_rounded,
                label: '从播放列表移除',
                danger: true,
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  ref
                      .read(libraryControllerProvider.notifier)
                      .removeFromPlaylist(playlistId, <String>{item.id});
                  showToast(context, '已从播放列表移除');
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }
}
