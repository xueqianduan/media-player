// -------------------------------------------------------------------------
// 功能：直播画面上的浮层控制条
//
// 主要内容：
// - 左上：原声 / 解说切换
// - 左下：横屏时暂停、刷新、弹幕开关与弹幕设置
// - 右下：同步、画质胶囊与横竖屏切换
// - 上下渐变遮罩，保证控件在亮画面上可读
// -------------------------------------------------------------------------

import 'package:flutter/material.dart';

import '../../domain/live_models.dart';
import 'live_console_header.dart';
import 'live_icon_button.dart';

/// 画面控制层。是否显示由页面控制，本组件只负责摆放与回调。
class LiveControlOverlay extends StatelessWidget {
  const LiveControlOverlay({
    super.key,
    required this.picture,
    required this.voice,
    required this.hint,
    required this.starting,
    required this.onBack,
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
    required this.danmakuEnabled,
    required this.onToggleDanmaku,
    required this.onDanmakuSettings,
    required this.onSync,
    required this.onQuality,
    required this.onToggleFullscreen,
    required this.onOfficialSound,
    required this.onCommentatorSound,
  });

  final LiveRoom picture;
  final LiveRoom? voice;

  /// 连接状态或警告，显示在切换按钮下方。
  final String hint;
  final bool starting;
  final VoidCallback onBack;

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
  final bool danmakuEnabled;
  final VoidCallback onToggleDanmaku;
  final VoidCallback onDanmakuSettings;
  final VoidCallback onSync;
  final VoidCallback onQuality;
  final VoidCallback onToggleFullscreen;
  final VoidCallback onOfficialSound;
  final VoidCallback onCommentatorSound;

  @override
  Widget build(BuildContext context) {
    // 横屏沉浸式下 SafeArea 不生效，这里按刘海 / 挖孔让出安全区。
    final EdgeInsets viewPadding = MediaQuery.viewPaddingOf(context);
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
          left: 8 + viewPadding.left,
          top: 8 + viewPadding.top,
          right: 12 + viewPadding.right,
          child: LiveConsoleHeader(
            picture: picture,
            voice: voice,
            hint: hint,
            starting: starting,
            usingVoice: usingVoice,
            hasVoice: hasVoice,
            onBack: onBack,
            onOfficialSound: onOfficialSound,
            onCommentatorSound: onCommentatorSound,
          ),
        ),
        Positioned(
          left: 8 + viewPadding.left,
          bottom: 8 + viewPadding.bottom,
          child: Row(
            children: <Widget>[
              if (landscape) ...<Widget>[
                LiveIconButton(
                  icon: paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                  onTap: ready ? onTogglePause : null,
                ),
                const SizedBox(width: 6),
                LiveIconButton(
                  icon: Icons.refresh_rounded,
                  onTap: refreshing ? null : onRefresh,
                  tooltip: '刷新画面源',
                ),
                const SizedBox(width: 6),
                LiveIconButton(
                  icon: danmakuEnabled
                      ? Icons.subtitles_rounded
                      : Icons.subtitles_off_rounded,
                  onTap: onToggleDanmaku,
                  tooltip: danmakuEnabled ? '关闭弹幕' : '开启弹幕',
                ),
                const SizedBox(width: 6),
                LiveIconButton(
                  icon: Icons.tune_rounded,
                  onTap: onDanmakuSettings,
                  tooltip: '弹幕设置',
                ),
                const SizedBox(width: 6),
              ],
            ],
          ),
        ),
        Positioned(
          right: 8 + viewPadding.right,
          bottom: 8 + viewPadding.bottom,
          child: Row(
            children: <Widget>[
              // 延迟调节放在画质左边，竖屏不提供。
              LiveIconButton(
                icon: Icons.sync_rounded,
                onTap: onSync,
                tooltip: '同步',
              ),
              const SizedBox(width: 6),
              if (hasQuality) ...<Widget>[
                _QualityChip(label: qualityLabel, onTap: onQuality),
                const SizedBox(width: 6),
              ],
              LiveIconButton(
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
