import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/dialogs.dart';
import '../../../core/widgets/ui_kit.dart';
import '../../library/application/library_controller.dart';
import '../../library/domain/models.dart';
import '../../library/presentation/video_actions.dart';
import '../../settings/application/settings_controller.dart';

/// 播放列表管理。
class PlaylistsPage extends ConsumerWidget {
  const PlaylistsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final LibraryState state = ref.watch(libraryControllerProvider);
    final LibraryController controller = ref.read(
      libraryControllerProvider.notifier,
    );

    return Scaffold(
      backgroundColor: context.appBackground,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final String? name = await showTextInputDialog(
            context,
            title: '新建播放列表',
            description: '播放列表用于组织播放顺序，可以手动调整顺序。',
            hintText: '例如：周末电影',
          );
          if (name != null && name.isNotEmpty) controller.createPlaylist(name);
        },
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        highlightElevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        icon: const Icon(Icons.add_rounded, size: 20),
        label: const Text('新建播放列表', style: TextStyle(fontSize: 13)),
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            PageHeader(
              title: '播放列表',
              subtitle: '共 ${state.playlists.length} 个列表',
              leading: AppIconButton(
                icon: Icons.arrow_back_ios_new_rounded,
                iconSize: 18,
                onPressed: () =>
                    context.canPop() ? context.pop() : context.go('/'),
              ),
            ),
            Expanded(
              child: state.playlists.isEmpty
                  ? const EmptyState(
                      icon: Icons.playlist_play_rounded,
                      title: '还没有播放列表',
                      message: '把想连续观看的视频放进同一个列表，支持顺序、循环与随机播放。',
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                      itemCount: state.playlists.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (BuildContext context, int index) {
                        final Playlist playlist = state.playlists[index];
                        final List<MediaItem> items = state.mediaInPlaylist(
                          playlist.id,
                        );
                        return AppCard(
                          padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
                          onTap: () =>
                              context.push('/playlists/${playlist.id}'),
                          child: Row(
                            children: <Widget>[
                              Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: context.softPrimary,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(
                                  Icons.playlist_play_rounded,
                                  size: 23,
                                  color: AppColors.primary,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: <Widget>[
                                    Text(
                                      playlist.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 14.5,
                                        fontWeight: FontWeight.w600,
                                        color: context.textPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      '${items.length} 个视频',
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        color: context.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                tooltip: '播放全部',
                                onPressed: items.isEmpty
                                    ? null
                                    : () => openPlayer(
                                        context,
                                        items: items,
                                        title: playlist.name,
                                        repeatMode: ref
                                            .read(settingsControllerProvider)
                                            .playlistRepeatMode,
                                      ),
                                icon: const Icon(
                                  Icons.play_circle_fill_rounded,
                                  size: 28,
                                  color: AppColors.primary,
                                ),
                              ),
                              PopupMenuButton<String>(
                                icon: Icon(
                                  Icons.more_horiz_rounded,
                                  size: 20,
                                  color: context.textSecondary,
                                ),
                                onSelected: (String value) async {
                                  if (value == 'rename') {
                                    final String? name =
                                        await showTextInputDialog(
                                          context,
                                          title: '重命名播放列表',
                                          initialValue: playlist.name,
                                        );
                                    if (name != null && name.isNotEmpty) {
                                      controller.renamePlaylist(
                                        playlist.id,
                                        name,
                                      );
                                    }
                                  } else if (value == 'delete') {
                                    final bool confirmed =
                                        await showConfirmDialog(
                                          context,
                                          title: '删除播放列表',
                                          message: '只删除播放列表本身，不会删除视频文件和视频库记录。',
                                          confirmLabel: '删除',
                                          danger: true,
                                        );
                                    if (confirmed) {
                                      controller.deletePlaylist(playlist.id);
                                    }
                                  }
                                },
                                itemBuilder: (BuildContext context) =>
                                    const <PopupMenuEntry<String>>[
                                      PopupMenuItem<String>(
                                        value: 'rename',
                                        child: Text('重命名'),
                                      ),
                                      PopupMenuItem<String>(
                                        value: 'delete',
                                        child: Text('删除播放列表'),
                                      ),
                                    ],
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
}
