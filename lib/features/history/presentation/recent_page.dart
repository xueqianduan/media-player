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

/// 最近播放：继续观看 + 按「今天 / 昨天 / 更早」分组的播放记录。
class RecentPage extends ConsumerWidget {
  const RecentPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final LibraryState state = ref.watch(libraryControllerProvider);
    final List<MediaItem> continueItems = state.continueWatching;
    final List<MediaItem> played = state.recentlyPlayed
        .where((MediaItem item) => !continueItems.contains(item))
        .toList();

    final DateTime now = DateTime.now();
    final DateTime startOfToday = DateTime(now.year, now.month, now.day);
    final DateTime startOfYesterday = startOfToday.subtract(
      const Duration(days: 1),
    );
    final List<MediaItem> today = <MediaItem>[];
    final List<MediaItem> yesterday = <MediaItem>[];
    final List<MediaItem> earlier = <MediaItem>[];
    for (final MediaItem item in played) {
      final DateTime at = state.progressOf(item.id)?.lastPlayedAt ?? now;
      if (!at.isBefore(startOfToday)) {
        today.add(item);
      } else if (!at.isBefore(startOfYesterday)) {
        yesterday.add(item);
      } else {
        earlier.add(item);
      }
    }

    return SafeArea(
      bottom: false,
      child: Column(
        children: <Widget>[
          PageHeader(
            title: '最近播放',
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
            child: continueItems.isEmpty && played.isEmpty
                ? const EmptyState(
                    icon: Icons.history_rounded,
                    title: '还没有观看记录',
                    message: '播放过的视频会出现在这里，没看完的可以在「继续观看」中接着看。',
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    children: <Widget>[
                      if (continueItems.isNotEmpty) ...<Widget>[
                        const SectionHeader(title: '继续观看'),
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
                        const SizedBox(height: 4),
                      ],
                      ..._buildGroup(context, ref, state, '今天', today),
                      ..._buildGroup(context, ref, state, '昨天', yesterday),
                      ..._buildGroup(context, ref, state, '更早', earlier),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  /// 一个时间段分组：标题 + 圆角卡片列表。
  List<Widget> _buildGroup(
    BuildContext context,
    WidgetRef ref,
    LibraryState state,
    String title,
    List<MediaItem> items,
  ) {
    if (items.isEmpty) return const <Widget>[];
    return <Widget>[
      SectionHeader(title: title),
      ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Column(
          children: <Widget>[
            for (int i = 0; i < items.length; i++) ...<Widget>[
              _RecentTile(
                item: items[i],
                progress: state.progress[items[i].id],
                onTap: () => playSingleVideo(context, items[i]),
                onMore: () => showVideoActionSheet(context, ref, items[i]),
              ),
              if (i != items.length - 1)
                Divider(height: 1, indent: 128, color: context.dividerColor),
            ],
          ],
        ),
      ),
    ];
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
