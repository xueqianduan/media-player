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

/// 画质侧栏：铺满屏幕右侧，左侧空白区域点击即关闭。
class LiveQualityPanelOverlay extends StatelessWidget {
  const LiveQualityPanelOverlay({
    super.key,
    required this.options,
    required this.currentQn,
    required this.onSelect,
    required this.onClose,
  });

  final List<LiveQuality> options;

  /// 当前实际生效的档位。
  final int currentQn;

  final ValueChanged<int> onSelect;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final Size size = MediaQuery.sizeOf(context);
    final bool landscape = size.width > size.height;
    final double baseWidth = landscape
        ? (size.width * 0.44).clamp(300.0, 460.0).toDouble()
        : (size.width * 0.68).clamp(250.0, 330.0).toDouble();
    // 只有一列档位文字，比常规侧栏窄一些。
    final double panelWidth = baseWidth * 0.62;

    return Stack(
      children: <Widget>[
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          right: panelWidth,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onClose,
          ),
        ),
        Positioned(
          right: 0,
          top: 0,
          bottom: 0,
          width: panelWidth,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {},
            child: DecoratedBox(
              decoration: const BoxDecoration(
                color: Color(0xF20A0C12),
                border: Border(left: BorderSide(color: Color(0x14FFFFFF))),
              ),
              child: SafeArea(
                left: false,
                child: TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  builder: (BuildContext context, double value, Widget? child) {
                    return FractionalTranslation(
                      translation: Offset((1 - value) * 0.18, 0),
                      child: Opacity(
                        opacity: value.clamp(0.0, 1.0),
                        child: child,
                      ),
                    );
                  },
                  child: SingleChildScrollView(
                    child: _QualityList(
                      options: options,
                      currentQn: currentQn,
                      onSelect: onSelect,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 档位一列：每档一个整行矩形，文字横纵居中。
class _QualityList extends StatelessWidget {
  const _QualityList({
    required this.options,
    required this.currentQn,
    required this.onSelect,
  });

  final List<LiveQuality> options;
  final int currentQn;
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
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onSelect(option.qn),
              child: Container(
                height: rowHeight,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: option.qn == currentQn
                      ? AppColors.primary
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  option.label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: option.qn == currentQn
                        ? Colors.white
                        : Colors.white70,
                    fontSize: compact ? 15 : 18.5,
                    fontWeight: option.qn == currentQn
                        ? FontWeight.w600
                        : FontWeight.w400,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
