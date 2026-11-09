import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/ui_kit.dart';
import '../../library/application/library_controller.dart';
import '../../library/domain/models.dart';
import '../../library/presentation/video_actions.dart';
import '../../library/presentation/widgets/media_collection_view.dart';
import '../../library/presentation/widgets/media_selection.dart';
import '../../settings/application/settings_controller.dart';

/// 分类内的视频列表。
class CategoryDetailPage extends ConsumerStatefulWidget {
  const CategoryDetailPage({super.key, required this.categoryId});

  final String categoryId;

  @override
  ConsumerState<CategoryDetailPage> createState() => _CategoryDetailPageState();
}

class _CategoryDetailPageState extends ConsumerState<CategoryDetailPage>
    with MediaSelectionState<CategoryDetailPage> {
  @override
  Widget build(BuildContext context) {
    final LibraryState state = ref.watch(libraryControllerProvider);
    final settings = ref.watch(settingsControllerProvider);
    final Category? category = state.categoryById(widget.categoryId);
    final List<MediaItem> items = sortMedia(
      state.mediaInCategory(widget.categoryId),
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
                title: category?.name ?? '分类',
                subtitle: '${items.length} 个视频 · 分类内的视频不会改变真实存储位置',
                leading: AppIconButton(
                  icon: Icons.arrow_back_ios_new_rounded,
                  iconSize: 18,
                  onPressed: () =>
                      context.canPop() ? context.pop() : context.go('/'),
                ),
                actions: <Widget>[
                  MediaPageActions(
                    showSearch: false,
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
                      icon: Icons.folder_special_outlined,
                      title: '分类中还没有视频',
                      message: '在视频的更多操作里选择「添加到分类」，把视频放进来。',
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
          ],
        ),
      ),
      bottomNavigationBar: selectionMode
          ? SelectionActionBar(
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
              onMore: () => showBatchActionSheet(
                context,
                ref,
                selectedIds,
                categoryId: widget.categoryId,
              ),
            )
          : null,
    );
  }
}
