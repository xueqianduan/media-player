import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/ui_kit.dart';
import '../../library/application/library_controller.dart';
import '../../library/domain/models.dart';
import 'settings_pages.dart';

/// 隐藏文件夹管理。
class HiddenFoldersPage extends ConsumerWidget {
  const HiddenFoldersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final LibraryState state = ref.watch(libraryControllerProvider);
    final LibraryController controller = ref.read(
      libraryControllerProvider.notifier,
    );
    final List<SourceFolder> folders = <SourceFolder>[...state.folders]
      ..sort(
        (SourceFolder a, SourceFolder b) =>
            a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );

    return SettingsScaffold(
      title: '隐藏文件夹',
      subtitle: '隐藏后不在本地首页展示，视频仍保留在视频库中',
      children: <Widget>[
        if (folders.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 40),
            child: EmptyState(
              icon: Icons.folder_off_outlined,
              title: '还没有可管理的文件夹',
              message: '扫描到本地视频后，可以在这里隐藏不想展示的文件夹。',
            ),
          )
        else
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Column(
              children: <Widget>[
                for (int i = 0; i < folders.length; i++) ...<Widget>[
                  SwitchListTile.adaptive(
                    value: folders[i].isHidden,
                    onChanged: (bool value) {
                      controller.setFolderHidden(folders[i].id, value);
                    },
                    activeThumbColor: AppColors.primary,
                    secondary: Icon(
                      folders[i].isHidden
                          ? Icons.folder_off_outlined
                          : Icons.folder_outlined,
                      size: 20,
                      color: context.textSecondary,
                    ),
                    title: Text(
                      folders[i].name,
                      style: TextStyle(
                        fontSize: 13.5,
                        color: context.textPrimary,
                      ),
                    ),
                    subtitle: Text(
                      '${folders[i].itemCount} 个视频 · ${formatBytes(folders[i].totalSize)}',
                      style: TextStyle(
                        fontSize: 11,
                        color: context.textSecondary,
                      ),
                    ),
                  ),
                  if (i != folders.length - 1)
                    Divider(height: 1, indent: 16, color: context.dividerColor),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

/// 媒体扫描管理。
class MediaScanPage extends ConsumerWidget {
  const MediaScanPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final LibraryState state = ref.watch(libraryControllerProvider);
    final LibraryController controller = ref.read(
      libraryControllerProvider.notifier,
    );

    final String permissionLabel = switch (state.permission) {
      MediaPermission.granted => '已授权访问全部视频',
      MediaPermission.limited => '已授权访问部分视频',
      MediaPermission.denied => '未授权',
      MediaPermission.permanentlyDenied => '权限被永久拒绝',
      MediaPermission.unsupported => '当前平台不支持自动扫描',
      MediaPermission.unknown => '尚未申请权限',
    };

    return SettingsScaffold(
      title: '媒体扫描管理',
      subtitle: '扫描结果会保存到本地，可随时手动刷新',
      children: <Widget>[
        AppCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  SoftIconBadge(
                    icon: state.permission.canRead
                        ? Icons.verified_user_outlined
                        : Icons.lock_outline_rounded,
                    size: 38,
                    iconSize: 19,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          '视频访问权限',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: context.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          permissionLabel,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: context.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _InfoLine(label: '视频总数', value: '${state.totalCount} 个'),
              _InfoLine(label: '占用空间', value: formatBytes(state.totalSize)),
              _InfoLine(label: '文件夹数量', value: '${state.folders.length} 个'),
              _InfoLine(
                label: '上次扫描',
                value: state.lastScanAt == null
                    ? '尚未扫描'
                    : formatDateTime(state.lastScanAt!),
              ),
              const SizedBox(height: 14),
              Row(
                children: <Widget>[
                  FilledButton.icon(
                    onPressed: state.isScanning
                        ? null
                        : () => controller.scan(),
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('重新扫描'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 11,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(11),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  TextButton(
                    onPressed: () => controller.openSystemPermissionSettings(),
                    child: const Text(
                      '系统权限设置',
                      style: TextStyle(fontSize: 12.5),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (state.scanMessage != null)
          Text(
            state.scanMessage!,
            style: TextStyle(fontSize: 11.5, color: context.textSecondary),
          ),
        const SizedBox(height: 12),
        Text(
          '扫描在后台异步进行，期间可以正常浏览已加载的内容；重复扫描会按系统资源标识去重，不会产生重复视频。',
          style: TextStyle(
            fontSize: 11,
            height: 1.6,
            color: context.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: 12, color: context.textSecondary),
            ),
          ),
          Text(
            value,
            style: TextStyle(fontSize: 12, color: context.textPrimary),
          ),
        ],
      ),
    );
  }
}
