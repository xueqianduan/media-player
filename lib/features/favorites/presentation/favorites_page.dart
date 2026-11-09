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
  /// 当前筛选的收藏夹；为空表示全部。
  String? _favoriteFolderId;

  @override
  Widget build(BuildContext context) {
    final LibraryState state = ref.watch(libraryControllerProvider);
    final settings = ref.watch(settingsControllerProvider);
    final List<FavoriteFolder> folders = state.favoriteFolders;
    final FavoriteFolder? activeFolder = _favoriteFolderId == null
        ? null
        : state.favoriteFolderById(_favoriteFolderId!);
    final List<MediaItem> allFavorites = state.favorites;
    final List<MediaItem> items = sortMedia(
      activeFolder == null
          ? allFavorites
          : allFavorites
                .where((MediaItem item) => activeFolder.contains(item.id))
                .toList(),
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
            if (!selectionMode && folders.isNotEmpty)
              SizedBox(
                height: 38,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: <Widget>[
                    _FolderChip(
                      label: '全部',
                      selected: activeFolder == null,
                      onTap: () => setState(() => _favoriteFolderId = null),
                    ),
                    for (final FavoriteFolder folder in folders) ...<Widget>[
                      const SizedBox(width: 8),
                      _FolderChip(
                        label: '${folder.name} ${folder.itemCount}',
                        selected: activeFolder?.id == folder.id,
                        onTap: () =>
                            setState(() => _favoriteFolderId = folder.id),
                      ),
                    ],
                  ],
                ),
              ),
            Expanded(
              child: items.isEmpty
                  ? EmptyState(
                      icon: Icons.star_outline_rounded,
                      title: allFavorites.isEmpty ? '还没有收藏的视频' : '这个收藏夹还是空的',
                      message: allFavorites.isEmpty
                          ? '长按视频点「收藏」，选择收藏夹即可在这里找到它。'
                          : '在批量操作里把视频加入这个收藏夹，就会显示在这里。',
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
              onMore: () => showBatchActionSheet(context, ref, selectedIds),
            )
          : null,
    );
  }
}

/// 收藏页顶部的收藏夹筛选胶囊。
class _FolderChip extends StatelessWidget {
  const _FolderChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 13),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : context.cardColor,
          borderRadius: BorderRadius.circular(19),
          border: Border.all(
            color: selected
                ? AppColors.primary
                : context.dividerColor.withValues(alpha: 0.7),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? Colors.white : context.textSecondary,
          ),
        ),
      ),
    );
  }
}
