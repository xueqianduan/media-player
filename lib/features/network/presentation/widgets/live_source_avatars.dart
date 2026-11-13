// -------------------------------------------------------------------------
// 功能：双路直播源头像
//
// 主要内容：
// - 画面源头像 + 声音源头像叠放，右下角带来源角标
// - 复用：播放页左上角信息条、收藏组合卡片
// -------------------------------------------------------------------------

import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/live_models.dart';

/// 双源头像：左画面、右声音；没有声音源时只显示画面。
class LiveSourceAvatars extends StatelessWidget {
  const LiveSourceAvatars({
    super.key,
    required this.picture,
    this.voice,
    this.size = 38,
  });

  final LiveRoom? picture;
  final LiveRoom? voice;
  final double size;

  @override
  Widget build(BuildContext context) {
    final LiveRoom? first = picture;
    final LiveRoom? second = voice;
    final double overlap = size * 0.58;
    return SizedBox(
      width: second == null ? size : size + overlap,
      height: size,
      child: Stack(
        children: <Widget>[
          if (first != null)
            _SourceAvatar(
              room: first,
              icon: Icons.desktop_windows_rounded,
              tint: AppColors.primary,
              size: size,
            )
          else
            _Placeholder(
              icon: Icons.desktop_windows_rounded,
              tint: AppColors.primary,
              size: size,
            ),
          if (second != null)
            Positioned(
              left: overlap,
              child: _SourceAvatar(
                room: second,
                icon: Icons.headphones_rounded,
                tint: const Color(0xFF37C26A),
                size: size,
              ),
            ),
        ],
      ),
    );
  }
}

/// 单个源头像：圆形头像 + 右下角来源角标。
class _SourceAvatar extends StatelessWidget {
  const _SourceAvatar({
    required this.room,
    required this.icon,
    required this.tint,
    required this.size,
  });

  final LiveRoom room;
  final IconData icon;
  final Color tint;
  final double size;

  @override
  Widget build(BuildContext context) {
    final String raw = room.avatarUrl;
    final String url = raw.startsWith('//') ? 'https:$raw' : raw;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: <Widget>[
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFF0B0D14), width: 2),
            ),
            child: ClipOval(
              child: url.isEmpty
                  ? _fallback()
                  : Image.network(
                      url,
                      fit: BoxFit.cover,
                      headers: const <String, String>{
                        'Referer': 'https://www.bilibili.com/',
                      },
                      errorBuilder: (_, _, _) => _fallback(),
                    ),
            ),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: size * 0.4,
              height: size * 0.4,
              decoration: BoxDecoration(
                color: const Color(0xFF0B0D14),
                shape: BoxShape.circle,
                border: Border.all(
                  color: tint.withValues(alpha: 0.9),
                  width: 1,
                ),
              ),
              child: Icon(icon, size: size * 0.24, color: tint),
            ),
          ),
        ],
      ),
    );
  }

  Widget _fallback() {
    return ColoredBox(
      color: const Color(0xFF1A1E2A),
      child: Center(
        child: Icon(
          icon,
          size: size * 0.4,
          color: tint.withValues(alpha: 0.85),
        ),
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({
    required this.icon,
    required this.tint,
    required this.size,
  });

  final IconData icon;
  final Color tint;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF1A1E2A),
        border: Border.all(color: const Color(0xFF0B0D14), width: 2),
      ),
      child: Icon(icon, size: size * 0.4, color: tint.withValues(alpha: 0.6)),
    );
  }
}
