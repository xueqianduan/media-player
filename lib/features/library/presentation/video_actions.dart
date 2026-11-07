import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/dialogs.dart';
import '../../../core/widgets/ui_kit.dart';
import '../application/library_controller.dart';
import '../domain/models.dart';
import 'widgets/media_collection_view.dart';

/// 打开播放器（支持队列与起始位置）。
void openPlayer(
  BuildContext context, {
  required List<MediaItem> items,
  int index = 0,
  String? title,
  RepeatMode repeatMode = RepeatMode.sequential,
}) {
  if (items.isEmpty) return;
  context.push(
    '/player',
    extra: PlayerArgs(
      mediaIds: items.map((MediaItem item) => item.id).toList(),
      startIndex: index.clamp(0, items.length - 1),
      title: title,
      repeatMode: repeatMode,
    ),
  );
}

/// 只播放单个视频（不进入任何播放队列）。
void playSingleVideo(BuildContext context, MediaItem item) {
  openPlayer(context, items: <MediaItem>[item]);
}

/// 播放器路由参数。
class PlayerArgs {
  const PlayerArgs({
    required this.mediaIds,
    required this.startIndex,
    this.title,
    this.repeatMode = RepeatMode.sequential,
  });

  final List<String> mediaIds;
  final int startIndex;
  final String? title;
  final RepeatMode repeatMode;
}

/// 排序选择。
Future<SortOption?> showSortSheet(BuildContext context, SortOption current) {
  return showModalBottomSheet<SortOption>(
    context: context,
    isScrollControlled: true,
    builder: (BuildContext sheetContext) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const SheetHeader(title: '排序方式'),
            ...SortOption.values.map(
              (SortOption option) => ListTile(
                onTap: () => Navigator.of(sheetContext).pop(option),
                title: Text(
                  option.label,
                  style: TextStyle(
                    fontSize: 14.5,
                    color: sheetContext.textPrimary,
                  ),
                ),
                trailing: option == current
                    ? const Icon(
                        Icons.check_rounded,
                        size: 20,
                        color: AppColors.primary,
                      )
                    : null,
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}

/// 视频操作菜单。
Future<void> showVideoActionSheet(
  BuildContext context,
  WidgetRef ref,
  MediaItem item,
) async {
  final LibraryController controller = ref.read(
    libraryControllerProvider.notifier,
  );
  final PlaybackProgress? record = ref
      .read(libraryControllerProvider)
      .progressOf(item.id);
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (BuildContext sheetContext) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SheetHeader(title: item.displayName, subtitle: '选择一个操作'),
            SheetActionTile(
              icon: item.isFavorite
                  ? Icons.star_rounded
                  : Icons.star_outline_rounded,
              label: item.isFavorite ? '取消收藏' : '收藏',
              onTap: () {
                Navigator.of(sheetContext).pop();
                controller.toggleFavorite(item.id);
                showToast(context, item.isFavorite ? '已取消收藏' : '已加入收藏');
              },
            ),
            SheetActionTile(
              icon: Icons.folder_copy_outlined,
              label: '添加到分类',
              onTap: () {
                Navigator.of(sheetContext).pop();
                showCategoryPicker(context, ref, mediaIds: <String>{item.id});
              },
            ),
            SheetActionTile(
              icon: Icons.playlist_add_rounded,
              label: '添加到播放列表',
              onTap: () {
                Navigator.of(sheetContext).pop();
                showPlaylistPicker(context, ref, mediaIds: <String>{item.id});
              },
            ),
            SheetActionTile(
              icon: Icons.drive_file_rename_outline_rounded,
              label: '重命名显示名称',
              onTap: () async {
                Navigator.of(sheetContext).pop();
                final String? name = await showTextInputDialog(
                  context,
                  title: '重命名',
                  description: '只修改 ReelBox 中显示的名称，不会重命名手机里的文件。',
                  initialValue: item.displayName,
                  hintText: '输入新的显示名称',
                );
                if (name == null || name.isEmpty) return;
                controller.rename(item.id, name);
                if (!context.mounted) return;
                showToast(context, '已更新显示名称');
              },
            ),
            SheetActionTile(
              icon: Icons.info_outline_rounded,
              label: '查看视频详情',
              onTap: () {
                Navigator.of(sheetContext).pop();
                showMediaDetailDialog(context, item);
              },
            ),
            if (record != null)
              SheetActionTile(
                icon: Icons.history_toggle_off_rounded,
                label: '清除播放记录',
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  controller.clearHistoryEntry(item.id);
                  showToast(context, '已清除播放记录');
                },
              ),
            SheetActionTile(
              icon: Icons.share_outlined,
              label: '分享视频',
              onTap: () async {
                Navigator.of(sheetContext).pop();
                await Clipboard.setData(
                  ClipboardData(text: item.sourceLocator),
                );
                if (!context.mounted) return;
                showToast(context, '视频路径已复制到剪贴板');
              },
            ),
            Divider(height: 1, color: sheetContext.dividerColor),
            SheetActionTile(
              icon: Icons.playlist_remove_rounded,
              label: '从 ReelBox 移除',
              danger: true,
              onTap: () async {
                Navigator.of(sheetContext).pop();
                final bool confirmed = await showConfirmDialog(
                  context,
                  title: '从 ReelBox 移除',
                  message: '只会删除应用内的记录与播放进度，不会删除手机中的原始视频文件。',
                  confirmLabel: '移除',
                  danger: true,
                );
                if (!confirmed) return;
                controller.removeFromLibrary(<String>{item.id});
                if (!context.mounted) return;
                showToast(context, '已从 ReelBox 移除');
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}

/// 多选批量操作。
Future<void> showBatchActionSheet(
  BuildContext context,
  WidgetRef ref,
  Set<String> mediaIds, {
  String? categoryId,
}) async {
  if (mediaIds.isEmpty) return;
  final LibraryController controller = ref.read(
    libraryControllerProvider.notifier,
  );
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (BuildContext sheetContext) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SheetHeader(title: '已选择 ${mediaIds.length} 个视频', subtitle: '批量操作'),
            SheetActionTile(
              icon: Icons.star_rounded,
              label: '批量收藏',
              onTap: () {
                Navigator.of(sheetContext).pop();
                controller.setFavorite(mediaIds, true);
                showToast(context, '已收藏 ${mediaIds.length} 个视频');
              },
            ),
            SheetActionTile(
              icon: Icons.folder_copy_outlined,
              label: '批量添加到分类',
              onTap: () {
                Navigator.of(sheetContext).pop();
                showCategoryPicker(context, ref, mediaIds: mediaIds);
              },
            ),
            SheetActionTile(
              icon: Icons.playlist_add_rounded,
              label: '批量添加到播放列表',
              onTap: () {
                Navigator.of(sheetContext).pop();
                showPlaylistPicker(context, ref, mediaIds: mediaIds);
              },
            ),
            if (categoryId != null)
              SheetActionTile(
                icon: Icons.remove_circle_outline_rounded,
                label: '从当前分类移除',
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  controller.removeFromCategory(mediaIds, categoryId);
                  showToast(context, '已从分类移除');
                },
              ),
            Divider(height: 1, color: sheetContext.dividerColor),
            SheetActionTile(
              icon: Icons.delete_outline_rounded,
              label: '批量从 ReelBox 移除',
              danger: true,
              onTap: () async {
                Navigator.of(sheetContext).pop();
                final bool confirmed = await showConfirmDialog(
                  context,
                  title: '批量移除',
                  message: '只会删除应用内记录，不会删除手机中的原始视频文件。',
                  confirmLabel: '移除',
                  danger: true,
                );
                if (!confirmed) return;
                controller.removeFromLibrary(mediaIds);
                if (!context.mounted) return;
                showToast(context, '已移除 ${mediaIds.length} 个视频');
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}

/// 分类选择弹窗（支持一个视频加入多个分类、新建分类）。
Future<void> showCategoryPicker(
  BuildContext context,
  WidgetRef ref, {
  required Set<String> mediaIds,
}) async {
  final LibraryController controller = ref.read(
    libraryControllerProvider.notifier,
  );
  final List<Category> categories = ref
      .read(libraryControllerProvider)
      .categories;
  final Set<String> selected = <String>{
    for (final Category category in categories)
      if (mediaIds.every(category.mediaIds.contains)) category.id,
  };

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (BuildContext sheetContext) {
      return StatefulBuilder(
        builder: (BuildContext context, StateSetter setState) {
          final List<Category> current = ref
              .read(libraryControllerProvider)
              .categories;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  SheetHeader(
                    title: '添加到分类',
                    subtitle: '一个视频可以同时属于多个分类',
                    trailing: TextButton(
                      onPressed: () async {
                        final String? name = await showTextInputDialog(
                          context,
                          title: '新建分类',
                          hintText: '例如：学习资料',
                        );
                        if (name == null || name.isEmpty) return;
                        final String? newId = controller.createCategoryAndGetId(
                          name,
                        );
                        if (newId != null) {
                          setState(() => selected.add(newId));
                        }
                      },
                      child: const Text('新建分类'),
                    ),
                  ),
                  if (current.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 18,
                      ),
                      child: Text(
                        '还没有自定义分类，点击右上角「新建分类」创建一个。',
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.5,
                          color: context.textSecondary,
                        ),
                      ),
                    )
                  else
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 340),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: current.length,
                        itemBuilder: (BuildContext context, int index) {
                          final Category category = current[index];
                          final bool checked = selected.contains(category.id);
                          return CheckboxListTile(
                            value: checked,
                            onChanged: (bool? value) {
                              setState(() {
                                if (value == true) {
                                  selected.add(category.id);
                                } else {
                                  selected.remove(category.id);
                                }
                              });
                            },
                            activeColor: AppColors.primary,
                            title: Text(
                              category.name,
                              style: TextStyle(
                                fontSize: 14,
                                color: context.textPrimary,
                              ),
                            ),
                            subtitle: Text(
                              '${category.mediaIds.length} 个视频',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: context.textSecondary,
                              ),
                            ),
                            controlAffinity: ListTileControlAffinity.trailing,
                          );
                        },
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () {
                          controller.addToCategories(mediaIds, selected);
                          Navigator.of(sheetContext).pop();
                          showToast(context, '已添加到 ${selected.length} 个分类');
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('确认添加'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

/// 播放列表选择弹窗。
Future<void> showPlaylistPicker(
  BuildContext context,
  WidgetRef ref, {
  required Set<String> mediaIds,
}) async {
  final LibraryController controller = ref.read(
    libraryControllerProvider.notifier,
  );
  final Set<String> selected = <String>{};

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (BuildContext sheetContext) {
      return StatefulBuilder(
        builder: (BuildContext context, StateSetter setState) {
          final List<Playlist> current = ref
              .read(libraryControllerProvider)
              .playlists;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  SheetHeader(
                    title: '添加到播放列表',
                    subtitle: '用于组织播放顺序',
                    trailing: TextButton(
                      onPressed: () async {
                        final String? name = await showTextInputDialog(
                          context,
                          title: '新建播放列表',
                          hintText: '例如：周末电影',
                        );
                        if (name == null || name.isEmpty) return;
                        final String? newId = controller.createPlaylistAndGetId(
                          name,
                        );
                        if (newId != null) {
                          setState(() => selected.add(newId));
                        }
                      },
                      child: const Text('新建播放列表'),
                    ),
                  ),
                  if (current.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 18,
                      ),
                      child: Text(
                        '还没有播放列表，点击右上角「新建播放列表」创建一个。',
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.5,
                          color: context.textSecondary,
                        ),
                      ),
                    )
                  else
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 320),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: current.length,
                        itemBuilder: (BuildContext context, int index) {
                          final Playlist playlist = current[index];
                          return CheckboxListTile(
                            value: selected.contains(playlist.id),
                            onChanged: (bool? value) {
                              setState(() {
                                if (value == true) {
                                  selected.add(playlist.id);
                                } else {
                                  selected.remove(playlist.id);
                                }
                              });
                            },
                            activeColor: AppColors.primary,
                            title: Text(
                              playlist.name,
                              style: TextStyle(
                                fontSize: 14,
                                color: context.textPrimary,
                              ),
                            ),
                            subtitle: Text(
                              '${playlist.mediaIds.length} 个视频',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: context.textSecondary,
                              ),
                            ),
                            controlAffinity: ListTileControlAffinity.trailing,
                          );
                        },
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () {
                          controller.addToPlaylists(mediaIds, selected);
                          Navigator.of(sheetContext).pop();
                          showToast(context, '已添加到 ${selected.length} 个播放列表');
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('确认添加'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}
