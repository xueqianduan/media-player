import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/ui_kit.dart';
import '../../settings/application/settings_controller.dart';
import '../application/library_controller.dart';
import '../domain/models.dart';
import 'video_actions.dart';
import 'widgets/media_collection_view.dart';
import 'widgets/media_selection.dart';

/// 文件夹视频列表。
class FolderPage extends ConsumerStatefulWidget {
  const FolderPage({super.key, required this.folderId});

  final String folderId;

  @override
  ConsumerState<FolderPage> createState() => _FolderPageState();
}

class _FolderPageState extends ConsumerState<FolderPage>
    with MediaSelectionState<FolderPage> {
  @override
  Widget build(BuildContext context) {
    final LibraryState state = ref.watch(libraryControllerProvider);
    final settings = ref.watch(settingsControllerProvider);
    final SourceFolder? folder = state.folderById(widget.folderId);
    final List<MediaItem> items = sortMedia(
      state.mediaInFolder(widget.folderId),
      settings.sortOption,
    );

    return Scaffold(
      backgroundColor: context.appBackground,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            if (selectionMode)
              SelectionHeader(
                count: selectedIds.length,
                total: items.length,
                onSelectAll: () => selectAll(items),
                onClose: exitSelection,
              )
            else
              PageHeader(
                title: folder?.name ?? '文件夹',
                subtitle:
                    '共 ${items.length} 个视频 · ${formatBytes(items.fold<int>(0, (int sum, MediaItem item) => sum + item.fileSize))}',
                leading: AppIconButton(
                  icon: Icons.arrow_back_ios_new_rounded,
                  iconSize: 18,
                  onPressed: () =>
                      context.canPop() ? context.pop() : context.go('/'),
                ),
                actions: <Widget>[
                  MediaPageActions(
                    onSearch: () =>
                        context.push('/search?folder=${widget.folderId}'),
                    onSort: () async {
                      final SortOption? option = await showSortSheet(
                        context,
                        settings.sortOption,
                      );
                      if (option != null) {
                        ref
                            .read(settingsControllerProvider.notifier)
                            .setSortOption(option);
                      }
                    },
                    onToggleView: () => ref
                        .read(settingsControllerProvider.notifier)
                        .toggleViewMode(),
                  ),
                ],
              ),
            Expanded(
              child: items.isEmpty
                  ? const EmptyState(
                      icon: Icons.videocam_off_outlined,
                      title: '这个文件夹里还没有视频',
                    )
                  : MediaCollectionView(
                      items: items,
                      viewMode: settings.viewMode,
                      progress: state.progress,
                      selectedIds: selectedIds,
                      selectionMode: selectionMode,
                      onTap: handleTap,
                      onLongPress: handleLongPress,
                      onMore: (MediaItem item) =>
                          showVideoActionSheet(context, ref, item),
                    ),
            ),
            if (selectionMode)
              SelectionActionBar(
                favorited: selectedIds.every(
                  (String id) =>
                      ref
                          .read(libraryControllerProvider)
                          .itemById(id)
                          ?.isFavorite ??
                      false,
                ),
                onFavorite: () =>
                    showFavoriteSheet(context, ref, mediaIds: selectedIds),
                onCategory: () =>
                    showCategoryPicker(context, ref, mediaIds: selectedIds),
                onPlaylist: () =>
                    showPlaylistPicker(context, ref, mediaIds: selectedIds),
                onMore: () => showBatchActionSheet(context, ref, selectedIds),
              ),
          ],
        ),
      ),
    );
  }
}
