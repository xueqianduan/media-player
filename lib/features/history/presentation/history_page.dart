import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/dialogs.dart';
import '../../../core/widgets/ui_kit.dart';
import '../../library/application/library_controller.dart';
import '../../library/domain/models.dart';
import '../../library/presentation/video_actions.dart';
import '../../library/presentation/widgets/media_tiles.dart';

/// 观看历史：最近播放与已看完的完整记录。
class HistoryPage extends ConsumerWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final LibraryState state = ref.watch(libraryControllerProvider);
    final List<MediaItem> items = state.recentlyPlayed;

    return Scaffold(
      backgroundColor: context.appBackground,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            PageHeader(
              title: '观看历史',
              subtitle: '共 ${items.length} 条记录',
              leading: AppIconButton(
                icon: Icons.arrow_back_ios_new_rounded,
                iconSize: 18,
                onPressed: () =>
                    context.canPop() ? context.pop() : context.go('/'),
              ),
              actions: <Widget>[
                if (items.isNotEmpty)
                  TextButton(
                    onPressed: () async {
                      final bool confirmed = await showConfirmDialog(
                        context,
                        title: '清空观看历史',
                        message: '只清除播放记录与进度，不会删除任何视频文件。',
                        confirmLabel: '清空',
                        danger: true,
                      );
                      if (confirmed) {
                        ref
                            .read(libraryControllerProvider.notifier)
                            .clearAllHistory();
                        if (!context.mounted) return;
                        showToast(context, '已清空观看历史');
                      }
                    },
                    child: const Text('清空', style: TextStyle(fontSize: 13)),
                  ),
                const SizedBox(width: 8),
              ],
            ),
            Expanded(
              child: items.isEmpty
                  ? const EmptyState(
                      icon: Icons.history_rounded,
                      title: '还没有观看历史',
                      message: '播放视频后，这里会记录观看位置与时间。',
                    )
                  : ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(18),
                      ),
                      child: ListView.separated(
                        padding: const EdgeInsets.only(bottom: 24),
                        itemCount: items.length,
                        separatorBuilder: (_, _) => Divider(
                          height: 1,
                          indent: 128,
                          color: context.dividerColor,
                        ),
                        itemBuilder: (BuildContext context, int index) {
                          final MediaItem item = items[index];
                          final PlaybackProgress? record =
                              state.progress[item.id];
                          return GestureDetector(
                            onLongPress: () =>
                                _showRecordActions(context, ref, item, record),
                            child: _HistoryTile(
                              item: item,
                              record: record,
                              onTap: () => playSingleVideo(context, item),
                              onMore: () => _showRecordActions(
                                context,
                                ref,
                                item,
                                record,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showRecordActions(
    BuildContext context,
    WidgetRef ref,
    MediaItem item,
    PlaybackProgress? record,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              SheetHeader(
                title: item.displayName,
                subtitle: record == null
                    ? '未观看'
                    : '上次观看 ${formatRelativeTime(record.lastPlayedAt)}',
              ),
              SheetActionTile(
                icon: Icons.play_arrow_rounded,
                label: record != null && record.shouldResume
                    ? '从上次位置继续'
                    : '从头播放',
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  openPlayer(context, items: <MediaItem>[item]);
                },
              ),
              SheetActionTile(
                icon: Icons.delete_outline_rounded,
                label: '删除这条记录',
                danger: true,
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  ref
                      .read(libraryControllerProvider.notifier)
                      .clearHistoryEntry(item.id);
                  showToast(context, '已删除观看记录');
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

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({
    required this.item,
    required this.record,
    required this.onTap,
    required this.onMore,
  });

  final MediaItem item;
  final PlaybackProgress? record;
  final VoidCallback onTap;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.cardColor,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
          child: Row(
            children: <Widget>[
              MediaThumbnail(
                item: item,
                width: 104,
                height: 60,
                showProgress: true,
                progress: record?.fraction,
              ),
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
                          ? '未观看'
                          : record!.completed
                          ? '已看完 · ${formatRelativeTime(record!.lastPlayedAt)}'
                          : '${formatWatchPercent(record!.fraction)} · ${formatRelativeTime(record!.lastPlayedAt)}',
                      style: TextStyle(
                        fontSize: 11,
                        color: context.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${formatDuration(item.durationMs)} · ${formatResolution(item.width, item.height)}',
                      style: TextStyle(
                        fontSize: 10.5,
                        color: context.textSecondary.withValues(alpha: 0.85),
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
