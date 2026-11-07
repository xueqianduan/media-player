import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/ui_kit.dart';
import '../../settings/application/settings_controller.dart';
import '../../library/application/library_controller.dart';
import '../../library/domain/models.dart';
import '../../library/presentation/video_actions.dart';
import '../../library/presentation/widgets/media_collection_view.dart';
import '../../library/presentation/widgets/media_selection.dart';

/// 我的收藏。
class FavoritesPage extends ConsumerStatefulWidget {
  const FavoritesPage({super.key});

  @override
  ConsumerState<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends ConsumerState<FavoritesPage>
    with MediaSelectionState<FavoritesPage> {
  @override
  Widget build(BuildContext context) {
    final LibraryState state = ref.watch(libraryControllerProvider);
    final settings = ref.watch(settingsControllerProvider);
    final List<MediaItem> items = sortMedia(
      state.favorites,
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
                title: '我的收藏',
                subtitle: '共 ${items.length} 个视频',
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
                      icon: Icons.star_outline_rounded,
                      title: '还没有收藏的视频',
                      message: '在视频的更多操作里点击「收藏」，就能在这里快速找到它。',
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
              onFavorite: () {
                ref
                    .read(libraryControllerProvider.notifier)
                    .setFavorite(selectedIds, false);
                showToast(context, '已取消收藏');
                exitSelection();
              },
              onCategory: () =>
                  showCategoryPicker(context, ref, mediaIds: selectedIds),
              onPlaylist: () =>
                  showPlaylistPicker(context, ref, mediaIds: selectedIds),
              onMore: () => showBatchActionSheet(context, ref, selectedIds),
            )
          : null,
    );
  }
}
