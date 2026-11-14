// -------------------------------------------------------------------------
// 功能：直播画质面板
//
// 主要内容：
// - 从屏幕右侧滑出的档位列表（与本地播放器倍速面板一致）
// - 点左侧空白关闭，选中档位后回调页面切换
// -------------------------------------------------------------------------

import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/live_models.dart';
import 'live_side_panel.dart';

/// 画质侧栏：铺满屏幕右侧，左侧空白区域点击即关闭。
class LiveQualityPanelOverlay extends StatelessWidget {
  const LiveQualityPanelOverlay({
    super.key,
    required this.options,
    required this.currentQn,
    required this.loggedIn,
    required this.onSelect,
    required this.onClose,
  });

  final List<LiveQuality> options;

  /// 当前实际生效的档位。
  final int currentQn;

  /// B 站账号是否已登录：未登录时高档位只提示「登录后可用」。
  final bool loggedIn;

  final ValueChanged<int> onSelect;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return LiveSidePanel(
      onClose: onClose,
      widthFactor: 0.62,
      child: _QualityList(
        options: options,
        currentQn: currentQn,
        loggedIn: loggedIn,
        onSelect: onSelect,
      ),
    );
  }
}

/// 档位一列：每档一个整行矩形，文字横纵居中。
class _QualityList extends StatelessWidget {
  const _QualityList({
    required this.options,
    required this.currentQn,
    required this.loggedIn,
    required this.onSelect,
  });

  final List<LiveQuality> options;
  final int currentQn;
  final bool loggedIn;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final bool compact = MediaQuery.sizeOf(context).height < 520;
    final double rowHeight = compact ? 40 : 51;

    return Padding(
      padding: compact
          ? const EdgeInsets.fromLTRB(6, 6, 6, 10)
          : const EdgeInsets.fromLTRB(8, 8, 8, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final LiveQuality option in options)
            _QualityRow(
              option: option,
              selected: option.qn == currentQn,
              locked: !loggedIn && option.requiresLogin,
              compact: compact,
              rowHeight: rowHeight,
              onTap: () => onSelect(option.qn),
            ),
        ],
      ),
    );
  }
}

/// 单个画质档位：未登录时高档位置灰，右侧提示「登录后可用」。
class _QualityRow extends StatelessWidget {
  const _QualityRow({
    required this.option,
    required this.selected,
    required this.locked,
    required this.compact,
    required this.rowHeight,
    required this.onTap,
  });

  final LiveQuality option;
  final bool selected;
  final bool locked;
  final bool compact;
  final double rowHeight;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color labelColor = selected
        ? Colors.white
        : (locked ? Colors.white30 : Colors.white70);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: locked ? null : onTap,
      child: Container(
        height: rowHeight,
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: <Widget>[
            Text(
              option.label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: labelColor,
                fontSize: compact ? 15 : 18.5,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
            if (locked)
              Positioned(
                right: 4,
                child: Text(
                  '登录后可用',
                  style: TextStyle(
                    fontSize: compact ? 8.5 : 9.5,
                    color: AppColors.primary.withValues(alpha: 0.85),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
