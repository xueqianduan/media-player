import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/ui_kit.dart';
import '../../library/application/library_controller.dart';
import '../../library/domain/models.dart';
import '../../library/presentation/video_actions.dart';
import '../../library/presentation/widgets/media_selection.dart';
import '../../library/presentation/widgets/media_tiles.dart';

/// 最近：继续观看 / 最近播放 / 已看完。
class RecentPage extends ConsumerWidget {
  const RecentPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final LibraryState state = ref.watch(libraryControllerProvider);
    final List<MediaItem> continueItems = state.continueWatching;
    final List<MediaItem> recentItems = state.recentlyPlayed
        .where((MediaItem item) => !state.continueWatching.contains(item))
        .where((MediaItem item) => state.progressOf(item.id)?.completed != true)
        .toList();
    final List<MediaItem> completed = state.completedItems;

    return SafeArea(
      bottom: false,
      child: Column(
        children: <Widget>[
          PageHeader(
            title: '最近',
            actions: <Widget>[
              MediaPageActions(
                onSearch: () => context.push('/search'),
                onSort: null,
                showSort: false,
                onToggleView: null,
                showViewToggle: false,
              ),
            ],
          ),
          Expanded(
            child: recentItems.isEmpty && continueItems.isEmpty
                ? const EmptyState(
                    icon: Icons.history_rounded,
                    title: '还没有观看记录',
                    message: '播放过的视频会出现在这里，没看完的可以在「继续观看」中接着看。',
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    children: <Widget>[
                      if (continueItems.isNotEmpty) ...<Widget>[
                        SectionHeader(
                          title: '继续观看',
                          actionLabel: '查看全部',
                          onAction: () => context.push('/history'),
                        ),
                        ...continueItems
                            .take(3)
                            .map(
                              (MediaItem item) => Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: _ContinueWatchingCard(
                                  item: item,
                                  progress: state.progress[item.id],
                                  onTap: () => playSingleVideo(context, item),
                                ),
                              ),
                            ),
                      ],
                      if (recentItems.isNotEmpty) ...<Widget>[
                        SectionHeader(
                          title: '最近播放',
                          actionLabel: '查看全部',
                          onAction: () => context.push('/history'),
                        ),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: Column(
                            children: <Widget>[
                              for (
                                int i = 0;
                                i < recentItems.take(6).length;
                                i++
                              ) ...<Widget>[
                                _RecentTile(
                                  item: recentItems[i],
                                  progress: state.progress[recentItems[i].id],
                                  onTap: () =>
                                      playSingleVideo(context, recentItems[i]),
                                  onMore: () => showVideoActionSheet(
                                    context,
                                    ref,
                                    recentItems[i],
                                  ),
                                ),
                                if (i != recentItems.take(6).length - 1)
                                  Divider(
                                    height: 1,
                                    indent: 128,
                                    color: context.dividerColor,
                                  ),
                              ],
                            ],
                          ),
                        ),
                      ],
                      if (completed.isNotEmpty) ...<Widget>[
                        SectionHeader(title: '已看完'),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: Column(
                            children: <Widget>[
                              for (
                                int i = 0;
                                i < completed.take(3).length;
                                i++
                              ) ...<Widget>[
                                _RecentTile(
                                  item: completed[i],
                                  progress: state.progress[completed[i].id],
                                  onTap: () =>
                                      playSingleVideo(context, completed[i]),
                                  onMore: () => showVideoActionSheet(
                                    context,
                                    ref,
                                    completed[i],
                                  ),
                                ),
                                if (i != completed.take(3).length - 1)
                                  Divider(
                                    height: 1,
                                    indent: 128,
                                    color: context.dividerColor,
                                  ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _ContinueWatchingCard extends StatelessWidget {
  const _ContinueWatchingCard({
    required this.item,
    required this.progress,
    required this.onTap,
  });

  final MediaItem item;
  final PlaybackProgress? progress;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(10),
      onTap: onTap,
      child: Row(
        children: <Widget>[
          MediaThumbnail(item: item, width: 132, height: 76, radius: 12),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  item.displayName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                    color: context.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${formatWatchPercent(progress?.fraction ?? 0)} · ${formatDuration(item.durationMs)}',
                  style: TextStyle(fontSize: 11, color: context.textSecondary),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: progress?.fraction ?? 0,
                    minHeight: 3,
                    backgroundColor: context.dividerColor,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      AppColors.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentTile extends StatelessWidget {
  const _RecentTile({
    required this.item,
    required this.progress,
    required this.onTap,
    required this.onMore,
  });

  final MediaItem item;
  final PlaybackProgress? progress;
  final VoidCallback onTap;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final PlaybackProgress? record = progress;
    final String subtitle = record == null
        ? '未观看'
        : record.completed
        ? '已看完'
        : '已观看 ${(record.fraction * 100).round()}%';
    return Material(
      color: context.cardColor,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
          child: Row(
            children: <Widget>[
              MediaThumbnail(item: item, width: 104, height: 60),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      item.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: context.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      record == null
                          ? subtitle
                          : '$subtitle · ${formatRelativeTime(record.lastPlayedAt)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: context.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 7),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: record?.fraction ?? 0,
                        minHeight: 3,
                        backgroundColor: context.dividerColor,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          (record?.completed ?? false)
                              ? AppColors.success
                              : AppColors.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              AppIconButton(
                icon: Icons.more_vert_rounded,
                iconSize: 19,
                size: 36,
                color: context.textSecondary,
                onPressed: onMore,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
