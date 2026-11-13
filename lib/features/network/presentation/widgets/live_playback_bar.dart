// -------------------------------------------------------------------------
// 功能：直播画面下方的常驻工具条
//
// 主要内容：
// - 暂停 / 继续
// - 刷新画面源（只重连画面，声音源不动）
// -------------------------------------------------------------------------

import 'package:flutter/material.dart';

/// 画面下方的两个常驻按钮。
class LivePlaybackBar extends StatelessWidget {
  const LivePlaybackBar({
    super.key,
    required this.paused,
    required this.refreshing,
    required this.onTogglePause,
    required this.onRefresh,
  });

  final bool paused;

  /// 刷新画面源中，按钮显示进度并禁用。
  final bool refreshing;

  final VoidCallback onTogglePause;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Row(
        children: <Widget>[
          Expanded(
            child: _ConsoleButton(
              icon: paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
              label: paused ? '继续' : '暂停',
              onTap: onTogglePause,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _ConsoleButton(
              icon: Icons.refresh_rounded,
              label: refreshing ? '刷新中…' : '刷新画面源',
              busy: refreshing,
              onTap: onRefresh,
            ),
          ),
        ],
      ),
    );
  }
}

class _ConsoleButton extends StatelessWidget {
  const _ConsoleButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.busy = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final bool enabled = onTap != null && !busy;
    return GestureDetector(
      onTap: enabled ? onTap : null,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 42,
        decoration: BoxDecoration(
          color: const Color(0xFF12151E),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            if (busy)
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 1.8,
                  color: Colors.white54,
                ),
              )
            else
              Icon(
                icon,
                size: 16,
                color: enabled ? Colors.white70 : Colors.white24,
              ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                color: enabled ? Colors.white : Colors.white38,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
