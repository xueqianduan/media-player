import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/ui_kit.dart';
import '../../settings/application/settings_controller.dart';
import '../application/library_controller.dart';
import '../domain/models.dart';
import 'import_action.dart';
import 'video_actions.dart';
import 'widgets/media_selection.dart';

/// 本地视频首页：文件夹优先，不展示文件夹内部封面。
class LocalPage extends ConsumerWidget {
  const LocalPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final LibraryState state = ref.watch(libraryControllerProvider);
    final SettingsController settings = ref.read(
      settingsControllerProvider.notifier,
    );
    final List<SourceFolder> folders = state.visibleFolders;

    return SafeArea(
      bottom: false,
      child: Column(
        children: <Widget>[
          PageHeader(
            title: '本地视频',
            actions: <Widget>[
              MediaPageActions(
                onSearch: () => context.push('/search'),
                onSort: () async {
                  final SortOption? option = await showSortSheet(
                    context,
                    ref.read(settingsControllerProvider).sortOption,
                  );
                  if (option != null) settings.setSortOption(option);
                },
                showViewToggle: false,
                showMore: true,
                onMore: () => _showMoreActions(context, ref),
              ),
            ],
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () =>
                  ref.read(libraryControllerProvider.notifier).scan(),
              color: AppColors.primary,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                children: <Widget>[
                  _QuickActions(state: state),
                  if (state.isScanning) ...<Widget>[
                    const SizedBox(height: 12),
                    _ScanningBanner(state: state),
                  ],
                  if (!state.permission.canRead &&
                      state.permission !=
                          MediaPermission.unsupported) ...<Widget>[
                    const SizedBox(height: 12),
                    _PermissionBanner(
                      permission: state.permission,
                      message: state.scanMessage,
                    ),
                  ],
                  if (state.scanMessage != null &&
                      !state.isScanning &&
                      state.permission.canRead) ...<Widget>[
                    const SizedBox(height: 10),
                    Text(
                      state.scanMessage!,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: context.textSecondary,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  if (folders.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 24),
                      child: EmptyState(
                        icon: Icons.video_library_outlined,
                        title: state.isScanning ? '正在扫描视频…' : '还没有找到视频',
                        message: state.permission == MediaPermission.unsupported
                            ? '当前平台无法自动扫描系统相册，可以从文件中导入视频。'
                            : '授权访问相册后即可自动建立文件夹列表，也可以手动导入视频。',
                        actionLabel: '导入视频',
                        onAction: () => _importVideos(context, ref),
                      ),
                    )
                  else
                    ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: Column(
                        children: <Widget>[
                          for (int i = 0; i < folders.length; i++) ...<Widget>[
                            _FolderTile(
                              folder: folders[i],
                              subtitle:
                                  '${folders[i].itemCount} 个视频 · ${formatBytes(folders[i].totalSize)}',
                              dateLabel: _latestDate(state, folders[i].id),
                              onTap: () =>
                                  context.push('/folder/${folders[i].id}'),
                            ),
                            if (i != folders.length - 1)
                              Divider(
                                height: 1,
                                indent: 68,
                                color: context.dividerColor,
                              ),
                          ],
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String? _latestDate(LibraryState state, String folderId) {
    DateTime? latest;
    for (final MediaItem item in state.mediaInFolder(folderId)) {
      final DateTime value = item.modifiedAt ?? item.createdAt;
      if (latest == null || value.isAfter(latest)) latest = value;
    }
    return latest == null ? null : formatDateTime(latest);
  }

  Future<void> _importVideos(BuildContext context, WidgetRef ref) =>
      importVideosWithFeedback(context, ref);

  Future<void> _showMoreActions(BuildContext context, WidgetRef ref) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const SheetHeader(title: '更多操作'),
              SheetActionTile(
                icon: Icons.refresh_rounded,
                label: '重新扫描视频',
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  ref.read(libraryControllerProvider.notifier).scan();
                },
              ),
              SheetActionTile(
                icon: Icons.file_download_outlined,
                label: '导入视频文件',
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _importVideos(context, ref);
                },
              ),
              SheetActionTile(
                icon: Icons.visibility_off_outlined,
                label: '隐藏文件夹管理',
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  context.push('/hidden-folders');
                },
              ),
              SheetActionTile(
                icon: Icons.perm_media_outlined,
                label: '媒体扫描管理',
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  context.push('/settings/media');
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

class _QuickActions extends ConsumerWidget {
  const _QuickActions({required this.state});

  final LibraryState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<_QuickActionData> actions = <_QuickActionData>[
      _QuickActionData(
        icon: Icons.video_library_rounded,
        label: '全部视频',
        onTap: () => context.push('/videos'),
      ),
      _QuickActionData(
        icon: Icons.history_rounded,
        label: '最近播放',
        onTap: () => ref.read(navTabProvider.notifier).select(2),
      ),
      _QuickActionData(
        icon: Icons.star_rounded,
        label: '我的收藏',
        onTap: () => context.push('/favorites'),
      ),
      _QuickActionData(
        icon: Icons.playlist_play_rounded,
        label: '播放列表',
        onTap: () => context.push('/playlists'),
      ),
    ];

    return AppCard(
      radius: 18,
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
      child: Row(
        children: actions
            .map(
              (_QuickActionData action) => Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: action.onTap,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        SoftIconBadge(
                          icon: action.icon,
                          size: 44,
                          iconSize: 21,
                        ),
                        const SizedBox(height: 7),
                        Text(
                          action.label,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: context.textPrimary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _QuickActionData {
  const _QuickActionData({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
}

class _FolderTile extends StatelessWidget {
  const _FolderTile({
    required this.folder,
    required this.subtitle,
    required this.onTap,
    this.dateLabel,
  });

  final SourceFolder folder;
  final String subtitle;
  final String? dateLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.cardColor,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 13, 10, 13),
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
                  Icons.folder_rounded,
                  size: 21,
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
                      folder.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: context.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: context.textSecondary,
                      ),
                    ),
                    if (dateLabel != null) ...<Widget>[
                      const SizedBox(height: 2),
                      Text(
                        dateLabel!,
                        style: TextStyle(
                          fontSize: 10.5,
                          color: context.textSecondary.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: context.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScanningBanner extends StatelessWidget {
  const _ScanningBanner({required this.state});

  final LibraryState state;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: <Widget>[
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              state.scanMessage ?? '正在扫描…',
              style: TextStyle(fontSize: 12, color: context.textSecondary),
            ),
          ),
          Text(
            '${(state.scanProgress * 100).clamp(0, 100).toStringAsFixed(0)}%',
            style: const TextStyle(
              fontSize: 11.5,
              color: AppColors.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _PermissionBanner extends ConsumerWidget {
  const _PermissionBanner({required this.permission, this.message});

  final MediaPermission permission;
  final String? message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const SoftIconBadge(
                icon: Icons.lock_outline_rounded,
                size: 36,
                iconSize: 18,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '需要访问视频',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: context.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            message ?? 'ReelBox 需要读取视频资源来建立本地视频库。视频只保存在你的设备上，不会上传。',
            style: TextStyle(
              fontSize: 11.5,
              height: 1.55,
              color: context.textSecondary,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              FilledButton(
                onPressed: () {
                  ref
                      .read(libraryControllerProvider.notifier)
                      .requestPermission();
                },
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 9,
                  ),
                  minimumSize: Size.zero,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text('授权访问', style: TextStyle(fontSize: 12.5)),
              ),
              const SizedBox(width: 10),
              TextButton(
                onPressed: () {
                  ref
                      .read(libraryControllerProvider.notifier)
                      .openSystemPermissionSettings();
                },
                child: const Text('打开系统设置', style: TextStyle(fontSize: 12.5)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
