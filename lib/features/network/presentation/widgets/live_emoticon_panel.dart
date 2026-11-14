// -------------------------------------------------------------------------
// 功能：官方弹幕表情面板
//
// 主要内容：
// - 表情网格（图片来自 B 站图床）
// - 未登录 / 加载中 / 加载失败 / 空列表 四种状态
// - 竖屏与横屏共用，横屏时高度更小
// -------------------------------------------------------------------------

import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/danmaku_models.dart';

/// 弹幕表情选择面板：贴在输入框上方弹出。
class LiveEmoticonPanel extends StatelessWidget {
  const LiveEmoticonPanel({
    super.key,
    required this.items,
    required this.loading,
    required this.error,
    required this.loggedIn,
    required this.compact,
    required this.onLogin,
    required this.onRetry,
    required this.onPick,
    required this.onClose,
  });

  final List<LiveEmoticon> items;
  final bool loading;
  final String? error;
  final bool loggedIn;

  /// 横屏使用紧凑高度。
  final bool compact;

  final VoidCallback onLogin;
  final VoidCallback onRetry;
  final ValueChanged<LiveEmoticon> onPick;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: compact ? 152 : 218,
      decoration: BoxDecoration(
        color: const Color(0xF20A0C12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 4, 0),
            child: Row(
              children: <Widget>[
                const Icon(
                  Icons.emoji_emotions_outlined,
                  size: 15,
                  color: Colors.white54,
                ),
                const SizedBox(width: 6),
                const Text(
                  '表情',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: onClose,
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                  icon: const Icon(
                    Icons.close_rounded,
                    size: 17,
                    color: Colors.white38,
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: _buildBody(context)),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (!loggedIn) {
      return _StateView(
        icon: Icons.lock_outline_rounded,
        text: '登录 B 站账号后可使用官方表情',
        actionLabel: '去登录',
        onAction: onLogin,
      );
    }
    if (loading) {
      return const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Colors.white38,
          ),
        ),
      );
    }
    final String? message = error;
    if (message != null) {
      return _StateView(
        icon: Icons.wifi_off_rounded,
        text: message,
        actionLabel: '重试',
        onAction: onRetry,
      );
    }
    if (items.isEmpty) {
      return const _StateView(
        icon: Icons.emoji_emotions_outlined,
        text: '这个直播间暂无可用表情',
      );
    }

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final int columns = ((constraints.maxWidth - 20) / 46).floor().clamp(
          5,
          9,
        );
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(10, 2, 10, 10),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 6,
            crossAxisSpacing: 6,
          ),
          itemCount: items.length,
          itemBuilder: (BuildContext context, int index) {
            final LiveEmoticon item = items[index];
            return Tooltip(
              message: item.label,
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => onPick(item),
                child: Center(
                  child: Image.network(
                    item.url,
                    width: 30,
                    height: 30,
                    fit: BoxFit.contain,
                    headers: const <String, String>{
                      'Referer': 'https://live.bilibili.com/',
                    },
                    errorBuilder: (_, _, _) => const Icon(
                      Icons.broken_image_outlined,
                      size: 17,
                      color: Colors.white24,
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _StateView extends StatelessWidget {
  const _StateView({
    required this.icon,
    required this.text,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final String? label = actionLabel;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 22, color: Colors.white24),
            const SizedBox(height: 8),
            Text(
              text,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 11,
                height: 1.4,
              ),
            ),
            if (label != null) ...<Widget>[
              const SizedBox(height: 8),
              GestureDetector(
                onTap: onAction,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Text(
                    label,
                    style: const TextStyle(color: Colors.white, fontSize: 11.5),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
