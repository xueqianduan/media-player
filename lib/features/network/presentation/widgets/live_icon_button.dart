// -------------------------------------------------------------------------
// 功能：直播控制台上的纯图标按钮
//
// 主要内容：
// - 无底色、无边框，只画一个白色图标（带轻微阴影保证亮画面可读）
// - 不可点击时自动变暗
// -------------------------------------------------------------------------

import 'package:flutter/material.dart';

/// 控制台上的纯图标按钮，和本地视频播放器的暂停键保持一致。
class LiveIconButton extends StatelessWidget {
  const LiveIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.size = 32,
    this.iconSize = 21,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final Widget button = GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: size,
        height: size,
        child: Icon(
          icon,
          size: iconSize,
          color: onTap == null ? Colors.white30 : Colors.white,
          shadows: const <Shadow>[Shadow(color: Colors.black54, blurRadius: 6)],
        ),
      ),
    );
    final String? message = tooltip;
    if (message == null) return button;
    return Tooltip(message: message, child: button);
  }
}
