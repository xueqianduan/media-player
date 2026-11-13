// -------------------------------------------------------------------------
// 功能：直播画面上的浮层控制条
//
// 主要内容：
// - 左上：原声 / 解说切换
// - 左下：同步；横屏时补上暂停与刷新
// - 右下：画质胶囊与横竖屏切换
// - 上下渐变遮罩，保证控件在亮画面上可读
// -------------------------------------------------------------------------

import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

/// 画面控制层。是否显示由页面控制，本组件只负责摆放与回调。
class LiveControlOverlay extends StatelessWidget {
  const LiveControlOverlay({
    super.key,
    required this.landscape,
    required this.paused,
    required this.usingVoice,
    required this.hasVoice,
    required this.ready,
    required this.refreshing,
    required this.hasQuality,
    required this.qualityLabel,
    required this.onTogglePause,
    required this.onRefresh,
    required this.onSync,
    required this.onQuality,
    required this.onToggleFullscreen,
    required this.onOfficialSound,
    required this.onCommentatorSound,
  });

  final bool landscape;
  final bool paused;
  final bool usingVoice;
  final bool hasVoice;

  /// 画面播放器是否就绪；未就绪时暂停按钮禁用。
  final bool ready;
  final bool refreshing;
  final bool hasQuality;
  final String qualityLabel;

  final VoidCallback onTogglePause;
  final VoidCallback onRefresh;
  final VoidCallback onSync;
  final VoidCallback onQuality;
  final VoidCallback onToggleFullscreen;
  final VoidCallback onOfficialSound;
  final VoidCallback onCommentatorSound;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[
                  Colors.black.withValues(alpha: 0.42),
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.55),
                ],
                stops: const <double>[0, 0.45, 1],
              ),
            ),
          ),
        ),
        Positioned(
          left: 8,
          top: 8,
          child: Row(
            children: <Widget>[
              _SoundChip(
                label: '原声',
                selected: !usingVoice,
                onTap: onOfficialSound,
              ),
              const SizedBox(width: 6),
              _SoundChip(
                label: '解说',
                selected: usingVoice,
                enabled: hasVoice,
                onTap: onCommentatorSound,
              ),
            ],
          ),
        ),
        Positioned(
          left: 8,
          bottom: 8,
          child: Row(
            children: <Widget>[
              if (landscape) ...<Widget>[
                _OverlayIconButton(
                  icon: paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                  onTap: ready ? onTogglePause : null,
                  filled: true,
                ),
                const SizedBox(width: 6),
                _OverlayIconButton(
                  icon: Icons.refresh_rounded,
                  onTap: refreshing ? null : onRefresh,
                  tooltip: '刷新画面源',
                ),
                const SizedBox(width: 6),
              ],
              _OverlayIconButton(
                icon: Icons.tune_rounded,
                onTap: hasVoice ? onSync : null,
                tooltip: '同步',
              ),
            ],
          ),
        ),
        Positioned(
          right: 8,
          bottom: 8,
          child: Row(
            children: <Widget>[
              if (hasQuality) ...<Widget>[
                _QualityChip(label: qualityLabel, onTap: onQuality),
                const SizedBox(width: 6),
              ],
              _OverlayIconButton(
                icon: landscape
                    ? Icons.fullscreen_exit_rounded
                    : Icons.fullscreen_rounded,
                onTap: onToggleFullscreen,
                tooltip: landscape ? '退出横屏' : '横屏观看',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 原声 / 解说胶囊。
class _SoundChip extends StatelessWidget {
  const _SoundChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.enabled = true,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color color = !enabled
        ? Colors.white24
        : (selected ? AppColors.primary : Colors.white70);
    return GestureDetector(
      onTap: enabled ? onTap : null,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.18)
              : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? AppColors.primary.withValues(alpha: 0.55)
                : Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

/// 画面右下角的画质胶囊。
class _QualityChip extends StatelessWidget {
  const _QualityChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.high_quality_rounded,
              size: 12,
              color: Colors.white70,
            ),
            const SizedBox(width: 3),
            Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

/// 控制层上的方形图标按钮。
class _OverlayIconButton extends StatelessWidget {
  const _OverlayIconButton({
    required this.icon,
    required this.onTap,
    this.filled = false,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final bool filled;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final Widget button = GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: filled
              ? AppColors.primary
              : Colors.black.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(10),
          border: filled
              ? null
              : Border.all(color: Colors.white.withValues(alpha: 0.16)),
        ),
        child: Icon(icon, size: filled ? 20 : 18, color: Colors.white),
      ),
    );
    final String? message = tooltip;
    if (message == null) return button;
    return Tooltip(message: message, child: button);
  }
}
