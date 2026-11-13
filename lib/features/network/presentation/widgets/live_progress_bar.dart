// -------------------------------------------------------------------------
// 功能：直播进度条
//
// 主要内容：
// - 表示缓存窗口内的播放位置，可拖动回看
// - 不在直播边缘时，右侧出现「回到直播」
// - 在边缘时显示「直播中」红点
// -------------------------------------------------------------------------

import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/live_models.dart';

/// 直播进度条：只在缓存窗口内有效。
class LiveProgressBar extends StatefulWidget {
  const LiveProgressBar({
    super.key,
    required this.progress,
    required this.onSeek,
    required this.onGoLive,
    this.compact = false,
  });

  final LiveProgress progress;

  /// 拖动结束后回调目标位置（绝对时间）。
  final Future<void> Function(Duration) onSeek;

  final VoidCallback onGoLive;

  /// 紧凑模式：嵌在画面底部的工具栏里，去掉外边距与「直播中」标签。
  final bool compact;

  @override
  State<LiveProgressBar> createState() => _LiveProgressBarState();
}

class _LiveProgressBarState extends State<LiveProgressBar> {
  /// 拖动中的临时比例，避免每 500ms 的进度刷新把滑块拽回去。
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    final LiveProgress progress = widget.progress;
    final bool enabled = progress.available;
    final double value = (_dragValue ?? progress.fraction).clamp(0.0, 1.0);
    final bool behind =
        enabled && (progress.lag > const Duration(seconds: 3) || value < 0.95);

    return Padding(
      padding: widget.compact
          ? EdgeInsets.zero
          : const EdgeInsets.fromLTRB(12, 4, 12, 0),
      child: SizedBox(
        height: widget.compact ? 28 : 34,
        child: Row(
          children: <Widget>[
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 2.5,
                  activeTrackColor: AppColors.primary,
                  inactiveTrackColor: Colors.white24,
                  thumbColor: AppColors.primary,
                  overlayColor: AppColors.primary.withValues(alpha: 0.15),
                  thumbShape: RoundSliderThumbShape(
                    enabledThumbRadius: widget.compact ? 5 : 6,
                  ),
                  overlayShape: RoundSliderOverlayShape(
                    overlayRadius: widget.compact ? 12 : 14,
                  ),
                  disabledActiveTrackColor: Colors.white24,
                  disabledInactiveTrackColor: Colors.white12,
                  disabledThumbColor: Colors.white24,
                ),
                child: Slider(
                  value: value,
                  onChangeStart: enabled
                      ? (double next) => setState(() => _dragValue = next)
                      : null,
                  onChanged: enabled
                      ? (double next) => setState(() => _dragValue = next)
                      : null,
                  onChangeEnd: enabled
                      ? (double next) async {
                          final Duration target = progress.targetFor(next);
                          try {
                            await widget.onSeek(target);
                          } finally {
                            // 等 seek 完成再放开滑块，避免松手瞬间被旧进度拉回。
                            if (mounted) setState(() => _dragValue = null);
                          }
                        }
                      : null,
                ),
              ),
            ),
            const SizedBox(width: 6),
            if (behind)
              _GoLiveButton(
                compact: widget.compact,
                onTap: () {
                  setState(() => _dragValue = null);
                  widget.onGoLive();
                },
              )
            else if (!widget.compact)
              const _LiveBadge(),
          ],
        ),
      ),
    );
  }
}

/// 回到直播边缘。
class _GoLiveButton extends StatelessWidget {
  const _GoLiveButton({required this.onTap, this.compact = false});

  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 7 : 9,
          vertical: compact ? 3.5 : 5,
        ),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.play_arrow_rounded, size: 14, color: Colors.white),
            SizedBox(width: 2),
            Text('回到直播', style: TextStyle(color: Colors.white, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

/// 已在直播边缘。
class _LiveBadge extends StatelessWidget {
  const _LiveBadge();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 5,
          height: 5,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Color(0xFFE24B4A),
          ),
        ),
        const SizedBox(width: 4),
        const Text(
          '直播中',
          style: TextStyle(color: Colors.white54, fontSize: 10.5),
        ),
      ],
    );
  }
}
