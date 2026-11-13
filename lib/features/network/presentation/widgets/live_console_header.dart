// -------------------------------------------------------------------------
// 功能：直播控制台顶部信息条
//
// 主要内容：
// - 返回按钮
// - 双源头像（画面源 / 声音源）叠加展示
// - 房间名、连接状态与启动中的转圈
// -------------------------------------------------------------------------

import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/live_models.dart';

/// 直播控制台顶部信息条。
class LiveConsoleHeader extends StatelessWidget {
  const LiveConsoleHeader({
    super.key,
    required this.picture,
    required this.voice,
    required this.status,
    required this.starting,
    required this.onBack,
  });

  final LiveRoom picture;
  final LiveRoom? voice;

  /// 连接状态或声音源警告，显示在房间名下方。
  final String status;

  /// 是否还在建立首路连接。
  final bool starting;

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 10, 8),
      child: Row(
        children: <Widget>[
          IconButton(
            onPressed: onBack,
            icon: const Icon(
              Icons.arrow_back_ios_new_rounded,
              color: Colors.white,
              size: 19,
            ),
          ),
          _SourceAvatars(picture: picture, voice: voice),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  picture.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  status,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ],
            ),
          ),
          if (starting)
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white54,
              ),
            ),
        ],
      ),
    );
  }
}

/// 双源头像：左画面、右声音；没有声音源时只显示画面。
class _SourceAvatars extends StatelessWidget {
  const _SourceAvatars({required this.picture, this.voice});

  final LiveRoom picture;
  final LiveRoom? voice;

  @override
  Widget build(BuildContext context) {
    final LiveRoom? second = voice;
    return SizedBox(
      width: second == null ? 38 : 60,
      height: 38,
      child: Stack(
        children: <Widget>[
          _SourceAvatar(
            room: picture,
            icon: Icons.desktop_windows_rounded,
            tint: AppColors.primary,
          ),
          if (second != null)
            Positioned(
              left: 22,
              child: _SourceAvatar(
                room: second,
                icon: Icons.headphones_rounded,
                tint: const Color(0xFF37C26A),
              ),
            ),
        ],
      ),
    );
  }
}

/// 单个源头像：圆形头像 + 右下角来源角标，拼在一起表示双路合流。
class _SourceAvatar extends StatelessWidget {
  const _SourceAvatar({
    required this.room,
    required this.icon,
    required this.tint,
  });

  final LiveRoom room;
  final IconData icon;
  final Color tint;

  static const double _size = 38;

  @override
  Widget build(BuildContext context) {
    final String raw = room.avatarUrl;
    final String url = raw.startsWith('//') ? 'https:$raw' : raw;
    return SizedBox(
      width: _size,
      height: _size,
      child: Stack(
        children: <Widget>[
          Container(
            width: _size,
            height: _size,
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
              width: 15,
              height: 15,
              decoration: BoxDecoration(
                color: const Color(0xFF0B0D14),
                shape: BoxShape.circle,
                border: Border.all(
                  color: tint.withValues(alpha: 0.9),
                  width: 1,
                ),
              ),
              child: Icon(icon, size: 9, color: tint),
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
          size: _size * 0.4,
          color: tint.withValues(alpha: 0.85),
        ),
      ),
    );
  }
}
