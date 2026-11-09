import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/ui_kit.dart';
import '../../library/application/library_controller.dart';
import '../../library/domain/models.dart';
import '../../settings/application/settings_controller.dart';
import '../../settings/domain/app_settings.dart';

/// 我的：应用信息 + 快捷宫格 + 设置入口。
class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  static const String version = '1.0.2';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final LibraryState state = ref.watch(libraryControllerProvider);

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
        children: <Widget>[
          PageHeader(
            title: '我的',
            padding: const EdgeInsets.fromLTRB(0, 8, 0, 14),
          ),
          AppCard(
            padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
            onTap: () => context.push('/about'),
            child: Row(
              children: <Widget>[
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: <Color>[Color(0xFF7C8CFF), Color(0xFF4C5BE8)],
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 30,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Text(
                            'ReelBox',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: context.textPrimary,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: context.softPrimary,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'V$version',
                              style: TextStyle(
                                fontSize: 9,
                                color: AppColors.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '轻量 · 简洁 · 高效 的本地视频播放器',
                        style: TextStyle(
                          fontSize: 11,
                          color: context.textSecondary,
                        ),
                      ),
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
          const SizedBox(height: 12),
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              children: <Widget>[
                Row(
                  children: <Widget>[
                    _GridAction(
                      icon: Icons.star_outline_rounded,
                      label: '我的收藏',
                      onTap: () => context.push('/favorites'),
                    ),
                    _GridAction(
                      icon: Icons.playlist_play_rounded,
                      label: '播放列表',
                      onTap: () => context.push('/playlists'),
                    ),
                    _GridAction(
                      icon: Icons.visibility_off_outlined,
                      label: '隐藏文件夹',
                      onTap: () => context.push('/hidden-folders'),
                    ),
                  ],
                ),
                Divider(height: 1, color: context.dividerColor),
                Row(
                  children: <Widget>[
                    _GridAction(
                      icon: Icons.history_rounded,
                      label: '最近播放',
                      onTap: () => context.push('/recent'),
                    ),
                    _GridAction(
                      icon: Icons.perm_media_outlined,
                      label: '媒体管理',
                      onTap: () => context.push('/settings/media'),
                    ),
                    _GridAction(
                      icon: Icons.delete_outline_rounded,
                      label: '回收站',
                      onTap: () => showToast(context, '回收站将在后续版本提供'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _SettingsGroup(
            children: <Widget>[
              _SettingsTile(
                icon: Icons.tune_rounded,
                label: '播放设置',
                onTap: () => context.push('/settings/playback'),
              ),
              _SettingsTile(
                icon: Icons.palette_outlined,
                label: '外观与主题',
                trailingLabel: ref.watch(
                  settingsControllerProvider.select(
                    (AppSettings settings) => settings.themeMode.label,
                  ),
                ),
                onTap: () => context.push('/settings/appearance'),
              ),
              _SettingsTile(
                icon: Icons.storage_rounded,
                label: '存储管理',
                trailingLabel: formatBytes(state.totalSize),
                onTap: () => context.push('/settings/storage'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _SettingsGroup(
            children: <Widget>[
              _SettingsTile(
                icon: Icons.info_outline_rounded,
                label: '关于 ReelBox',
                onTap: () => context.push('/about'),
              ),
              _SettingsTile(
                icon: Icons.privacy_tip_outlined,
                label: '隐私与权限',
                onTap: () => context.push('/privacy'),
              ),
              _SettingsTile(
                icon: Icons.help_outline_rounded,
                label: '帮助与反馈',
                onTap: () => context.push('/help'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              'ReelBox $version · 视频只保存在本地',
              style: TextStyle(fontSize: 10.5, color: context.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

class _GridAction extends StatelessWidget {
  const _GridAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 15),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 23, color: AppColors.primary),
              const SizedBox(height: 7),
              Text(
                label,
                style: TextStyle(fontSize: 11, color: context.textPrimary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        children: <Widget>[
          for (int i = 0; i < children.length; i++) ...<Widget>[
            children[i],
            if (i != children.length - 1)
              Divider(height: 1, indent: 50, color: context.dividerColor),
          ],
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.trailingLabel,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final String? trailingLabel;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Row(
          children: <Widget>[
            Icon(icon, size: 20, color: context.textSecondary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(fontSize: 13.5, color: context.textPrimary),
              ),
            ),
            if (trailingLabel != null)
              Text(
                trailingLabel!,
                style: TextStyle(fontSize: 11.5, color: context.textSecondary),
              ),
            const SizedBox(width: 2),
            Icon(
              Icons.chevron_right_rounded,
              size: 19,
              color: context.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}
