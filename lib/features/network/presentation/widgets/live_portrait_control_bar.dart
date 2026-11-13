// -------------------------------------------------------------------------
// 功能：竖屏画面底部工具栏
//
// 主要内容：
// - 暂停 / 继续（纯图标）
// - 直播进度条（紧凑模式，含「回到直播」）
// - 横屏入口（刷新与同步只在横屏提供）
// -------------------------------------------------------------------------

import 'package:flutter/material.dart';

import '../../domain/live_models.dart';
import 'live_icon_button.dart';
import 'live_progress_bar.dart';

/// 嵌在竖屏画面底部的控制条。
class LivePortraitControlBar extends StatelessWidget {
  const LivePortraitControlBar({
    super.key,
    required this.progress,
    required this.paused,
    required this.ready,
    required this.onTogglePause,
    required this.onSeek,
    required this.onGoLive,
    required this.onToggleFullscreen,
  });

  final LiveProgress progress;
  final bool paused;
  final bool ready;

  final VoidCallback onTogglePause;
  final Future<void> Function(Duration) onSeek;
  final VoidCallback onGoLive;
  final VoidCallback onToggleFullscreen;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            Colors.transparent,
            Colors.black.withValues(alpha: 0.55),
          ],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
        child: Row(
          children: <Widget>[
            LiveIconButton(
              icon: paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
              iconSize: 22,
              onTap: ready ? onTogglePause : null,
            ),
            Expanded(
              child: LiveProgressBar(
                progress: progress,
                compact: true,
                onSeek: onSeek,
                onGoLive: onGoLive,
              ),
            ),
            LiveIconButton(
              icon: Icons.fullscreen_rounded,
              onTap: onToggleFullscreen,
              tooltip: '横屏观看',
            ),
          ],
        ),
      ),
    );
  }
}
