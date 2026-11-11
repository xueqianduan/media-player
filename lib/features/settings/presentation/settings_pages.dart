// -------------------------------------------------------------------------
// 功能：设置页集合
//
// 主要内容：
// - 播放设置（手势、倍速、续播等）
// - 外观设置（主题、视图、排序）
// -------------------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/dialogs.dart';
import '../../../core/widgets/ui_kit.dart';
import '../../library/application/library_controller.dart';
import '../../library/domain/models.dart';
import '../application/settings_controller.dart';
import '../domain/app_settings.dart';

// ===== 设置页统一骨架 =====
/// 设置页通用骨架。
class SettingsScaffold extends StatelessWidget {
  const SettingsScaffold({
    super.key,
    required this.title,
    required this.children,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appBackground,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            PageHeader(
              title: title,
              subtitle: subtitle,
              leading: AppIconButton(
                icon: Icons.arrow_back_ios_new_rounded,
                iconSize: 18,
                onPressed: () =>
                    context.canPop() ? context.pop() : context.go('/'),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                children: children,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ===== 播放设置 =====
/// 播放设置。
class PlaybackSettingsPage extends ConsumerWidget {
  const PlaybackSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppSettings settings = ref.watch(settingsControllerProvider);
    final SettingsController controller = ref.read(
      settingsControllerProvider.notifier,
    );

    return SettingsScaffold(
      title: '播放设置',
      subtitle: '设置会应用到所有视频',
      children: <Widget>[
        AppCard(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '默认倍速',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: context.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '播放时仍可以在播放器里临时调整',
                style: TextStyle(fontSize: 11, color: context.textSecondary),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: AppSettings.speedOptions.map((double speed) {
                  final bool selected = settings.defaultSpeed == speed;
                  return ChoiceChip(
                    label: Text('${_speedLabel(speed)}x'),
                    selected: selected,
                    onSelected: (_) => controller.setDefaultSpeed(speed),
                    labelStyle: TextStyle(
                      fontSize: 12,
                      color: selected ? Colors.white : context.textPrimary,
                    ),
                    selectedColor: AppColors.primary,
                    backgroundColor: context.cardColor,
                    side: BorderSide(
                      color: selected
                          ? AppColors.primary
                          : context.dividerColor,
                    ),
                    showCheckmark: false,
                  );
                }).toList(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        AppCard(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '长按临时倍速',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: context.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '长按画面时临时加速，松手恢复原速',
                style: TextStyle(fontSize: 11, color: context.textSecondary),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: AppSettings.longPressSpeedOptions.map((double speed) {
                  final bool selected = settings.longPressSpeed == speed;
                  return ChoiceChip(
                    label: Text('${_speedLabel(speed)}x'),
                    selected: selected,
                    onSelected: (_) => controller.setLongPressSpeed(speed),
                    labelStyle: TextStyle(
                      fontSize: 12,
                      color: selected ? Colors.white : context.textPrimary,
                    ),
                    selectedColor: AppColors.primary,
                    backgroundColor: context.cardColor,
                    side: BorderSide(
                      color: selected
                          ? AppColors.primary
                          : context.dividerColor,
                    ),
                    showCheckmark: false,
                  );
                }).toList(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        AppCard(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Column(
            children: <Widget>[
              _SwitchTile(
                title: '播放器手势',
                subtitle:
                    '双击快进快退、上下滑动调节音量与亮度、长按 ${_speedLabel(settings.longPressSpeed)}x 加速',
                value: settings.gesturesEnabled,
                onChanged: controller.setGesturesEnabled,
              ),
              Divider(height: 1, indent: 16, color: context.dividerColor),
              _SwitchTile(
                title: '断点续播提醒',
                subtitle: '观看超过 15 秒后重新打开时从上次位置继续，可一键重新开始',
                value: settings.resumePrompt,
                onChanged: controller.setResumePrompt,
              ),
              Divider(height: 1, indent: 16, color: context.dividerColor),
              _SwitchTile(
                title: '播放时保持屏幕常亮',
                subtitle: '避免观看过程中自动锁屏',
                value: settings.keepScreenOn,
                onChanged: controller.setKeepScreenOn,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        AppCard(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(
                Icons.info_outline_rounded,
                size: 16,
                color: context.textSecondary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '每次退出播放器、暂停或拖动进度时都会保存进度；播放达到 95% 自动标记为已看完。',
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.6,
                    color: context.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static String _speedLabel(double speed) {
    if (speed == speed.roundToDouble()) return speed.toStringAsFixed(1);
    return speed.toStringAsFixed(2).replaceFirst(RegExp(r'0$'), '');
  }
}

// ===== 外观设置 =====
/// 外观与主题。
class AppearancePage extends ConsumerWidget {
  const AppearancePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppSettings settings = ref.watch(settingsControllerProvider);
    final SettingsController controller = ref.read(
      settingsControllerProvider.notifier,
    );

    return SettingsScaffold(
      title: '外观与主题',
      subtitle: '主题切换会应用到全部页面',
      children: <Widget>[
        AppCard(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: RadioGroup<AppThemeMode>(
            groupValue: settings.themeMode,
            onChanged: (AppThemeMode? value) {
              if (value != null) controller.setThemeMode(value);
            },
            child: Column(
              children: AppThemeMode.values.map((AppThemeMode mode) {
                return RadioListTile<AppThemeMode>(
                  value: mode,
                  title: Text(
                    mode.label,
                    style: TextStyle(fontSize: 14, color: context.textPrimary),
                  ),
                  subtitle: Text(
                    switch (mode) {
                      AppThemeMode.system => '跟随系统深色 / 浅色设置自动切换',
                      AppThemeMode.light => '白色背景 + 浅灰卡片 + 蓝紫强调色',
                      AppThemeMode.dark => '深色背景 + 深灰卡片，适合夜间观看',
                    },
                    style: TextStyle(
                      fontSize: 11,
                      color: context.textSecondary,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        const SizedBox(height: 12),
        AppCard(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  '预览',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: context.textSecondary,
                  ),
                ),
              ),
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: context.softPrimary,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: context.textPrimary,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ===== 存储管理 =====
/// 存储管理。
class StoragePage extends ConsumerStatefulWidget {
  const StoragePage({super.key});

  @override
  ConsumerState<StoragePage> createState() => _StoragePageState();
}

class _StoragePageState extends ConsumerState<StoragePage> {
  int? _cacheBytes;

  @override
  void initState() {
    super.initState();
    _loadCacheSize();
  }

  Future<void> _loadCacheSize() async {
    final int bytes = await ref.read(thumbnailServiceProvider).cacheSize();
    if (!mounted) return;
    setState(() => _cacheBytes = bytes);
  }

  @override
  Widget build(BuildContext context) {
    final LibraryState state = ref.watch(libraryControllerProvider);
    final LibraryController controller = ref.read(
      libraryControllerProvider.notifier,
    );

    return SettingsScaffold(
      title: '存储管理',
      subtitle: '缓存与原始视频分开管理',
      children: <Widget>[
        AppCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: <Widget>[
              _StorageRow(
                icon: Icons.video_library_outlined,
                label: '视频库索引',
                value:
                    '${state.totalCount} 个视频 · ${formatBytes(state.totalSize)}',
              ),
              const SizedBox(height: 14),
              _StorageRow(
                icon: Icons.image_outlined,
                label: '缩略图缓存',
                value: _cacheBytes == null ? '计算中…' : formatBytes(_cacheBytes!),
              ),
              const SizedBox(height: 14),
              _StorageRow(
                icon: Icons.play_circle_outline_rounded,
                label: '播放记录',
                value: '${state.progress.length} 条进度记录',
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        AppCard(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Column(
            children: <Widget>[
              _ActionTile(
                icon: Icons.cleaning_services_outlined,
                label: '清理缩略图缓存',
                onTap: () async {
                  final bool confirmed = await showConfirmDialog(
                    context,
                    title: '清理缩略图缓存',
                    message: '只删除应用生成的缩略图，不会删除任何原始视频。再次浏览时会重新生成。',
                    confirmLabel: '清理',
                  );
                  if (!confirmed) return;
                  final int freed = await ref
                      .read(thumbnailServiceProvider)
                      .clearCache();
                  if (!context.mounted) return;
                  setState(() => _cacheBytes = 0);
                  showToast(context, '已清理 ${formatBytes(freed)} 缩略图缓存');
                },
              ),
              Divider(height: 1, indent: 50, color: context.dividerColor),
              _ActionTile(
                icon: Icons.delete_sweep_outlined,
                label: '清空观看记录',
                onTap: () async {
                  final bool confirmed = await showConfirmDialog(
                    context,
                    title: '清空观看记录',
                    message: '只删除播放进度，不会删除视频文件。',
                    confirmLabel: '清空',
                    danger: true,
                  );
                  if (!confirmed) return;
                  controller.clearAllHistory();
                  if (!context.mounted) return;
                  showToast(context, '观看记录已清空');
                },
              ),
              Divider(height: 1, indent: 50, color: context.dividerColor),
              _ActionTile(
                icon: Icons.folder_delete_outlined,
                label: '清空视频库索引',
                danger: true,
                onTap: () async {
                  final bool confirmed = await showConfirmDialog(
                    context,
                    title: '清空视频库索引',
                    message: '只删除 ReelBox 中的应用内记录与分类关联，不会删除手机中的原始视频文件。',
                    confirmLabel: '清空',
                    danger: true,
                  );
                  if (!confirmed) return;
                  controller.clearLibraryRecords();
                  if (!context.mounted) return;
                  showToast(context, '已清空视频库索引，可重新扫描');
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'ReelBox 不会复制系统相册中的视频，只有通过「导入视频」添加的文件会复制到应用私有目录。',
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

// ===== 设置项小组件 =====
class _SwitchTile extends StatelessWidget {
  const _SwitchTile({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile.adaptive(
      value: value,
      onChanged: onChanged,
      activeThumbColor: AppColors.primary,
      contentPadding: const EdgeInsets.fromLTRB(16, 4, 12, 4),
      title: Text(
        title,
        style: TextStyle(fontSize: 13.5, color: context.textPrimary),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(
          subtitle,
          style: TextStyle(
            fontSize: 11,
            height: 1.45,
            color: context.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
        child: Row(
          children: <Widget>[
            Icon(
              icon,
              size: 20,
              color: danger ? const Color(0xFFE5484D) : context.textSecondary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13.5,
                  color: danger ? const Color(0xFFE5484D) : context.textPrimary,
                ),
              ),
            ),
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

class _StorageRow extends StatelessWidget {
  const _StorageRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Icon(icon, size: 19, color: context.textSecondary),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: TextStyle(fontSize: 13, color: context.textPrimary),
          ),
        ),
        Text(
          value,
          style: TextStyle(fontSize: 11.5, color: context.textSecondary),
        ),
      ],
    );
  }
}
