// -------------------------------------------------------------------------
// 功能：直播控制台左上角的来源信息条
//
// 主要内容：
// - 返回、双源头像（画面 / 声音）
// - 标题「画面主播 · 声音主播」与房间号副标题
// - 原声 / 解说切换
// - 连接中的状态提示
// -------------------------------------------------------------------------

import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/live_models.dart';
import 'live_source_avatars.dart';

/// 画面左上角的来源信息与声音切换。
class LiveConsoleHeader extends StatelessWidget {
  const LiveConsoleHeader({
    super.key,
    required this.picture,
    required this.voice,
    required this.hint,
    required this.starting,
    required this.usingVoice,
    required this.hasVoice,
    required this.onBack,
    required this.onOfficialSound,
    required this.onCommentatorSound,
  });

  final LiveRoom picture;
  final LiveRoom? voice;

  /// 连接状态或警告；为空时不占位。
  final String hint;

  /// 是否还在建立首路连接。
  final bool starting;
  final bool usingVoice;
  final bool hasVoice;

  final VoidCallback onBack;
  final VoidCallback onOfficialSound;
  final VoidCallback onCommentatorSound;

  String get _title =>
      voice == null ? picture.name : '${picture.name} · ${voice!.name}';

  String get _subtitle => voice == null
      ? '画面 ${picture.roomId} · 原声'
      : '画面 ${picture.roomId} · 声音 ${voice!.roomId}';

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          children: <Widget>[
            GestureDetector(
              onTap: onBack,
              behavior: HitTestBehavior.opaque,
              child: const SizedBox(
                width: 30,
                height: 30,
                child: Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: Colors.white,
                  size: 18,
                ),
              ),
            ),
            const SizedBox(width: 2),
            LiveSourceAvatars(picture: picture, voice: voice),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    _title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      shadows: <Shadow>[
                        Shadow(color: Colors.black54, blurRadius: 6),
                      ],
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white60,
                      fontSize: 10.5,
                      shadows: <Shadow>[
                        Shadow(color: Colors.black54, blurRadius: 6),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (starting)
              const SizedBox(
                width: 13,
                height: 13,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white54,
                ),
              ),
          ],
        ),
        const SizedBox(height: 7),
        Row(
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
        if (hint.isNotEmpty) ...<Widget>[
          const SizedBox(height: 5),
          Text(
            hint,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 10,
              shadows: <Shadow>[Shadow(color: Colors.black54, blurRadius: 6)],
            ),
          ),
        ],
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
        : (selected ? Colors.white : Colors.white70);
    return GestureDetector(
      onTap: enabled ? onTap : null,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.9)
              : Colors.black.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: selected
                ? AppColors.primary
                : Colors.white.withValues(alpha: 0.16),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 11.5,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}
