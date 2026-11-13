// -------------------------------------------------------------------------
// 功能：直播弹幕区与弹幕输入栏
//
// 主要内容：
// - 弹幕占位区：显示所选来源，接入弹幕连接后在这里滚动消息
// - 底部输入栏：发送能力等弹幕连接接入后再开放
// -------------------------------------------------------------------------

import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/live_models.dart';

/// 弹幕区：先占位，接入弹幕连接后在这里滚动消息。
class LiveDanmakuPanel extends StatelessWidget {
  const LiveDanmakuPanel({super.key, required this.source});

  final DanmakuSource source;

  String get _sourceLabel {
    switch (source) {
      case DanmakuSource.picture:
        return '画面直播间';
      case DanmakuSource.voice:
        return '声音直播间';
      case DanmakuSource.off:
        return '未开启';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      decoration: BoxDecoration(
        color: const Color(0xFF12151E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 11, 12, 8),
            child: Row(
              children: <Widget>[
                const Icon(
                  Icons.forum_rounded,
                  size: 14,
                  color: Colors.white54,
                ),
                const SizedBox(width: 6),
                const Text(
                  '弹幕',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$_sourceLabel · 待接入',
                    style: const TextStyle(color: Colors.white38, fontSize: 10),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      Icons.chat_bubble_outline_rounded,
                      size: 30,
                      color: Colors.white.withValues(alpha: 0.18),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      '弹幕区已就位',
                      style: TextStyle(color: Colors.white54, fontSize: 12.5),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      '接入弹幕连接后，这里会实时滚动画面源的弹幕',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white24,
                        fontSize: 11,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 底部弹幕输入栏：发送能力等弹幕连接接入后再开放。
class LiveDanmakuInputBar extends StatelessWidget {
  const LiveDanmakuInputBar({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Row(
        children: <Widget>[
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              child: Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                child: Row(
                  children: <Widget>[
                    const Text(
                      '发个弹幕…',
                      style: TextStyle(color: Colors.white30, fontSize: 12.5),
                    ),
                    const Spacer(),
                    Icon(
                      Icons.emoji_emotions_outlined,
                      size: 18,
                      color: Colors.white.withValues(alpha: 0.25),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.35),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.send_rounded,
                size: 18,
                color: Colors.white70,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
