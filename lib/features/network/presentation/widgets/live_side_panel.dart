// -------------------------------------------------------------------------
// 功能：右侧滑出面板容器
//
// 主要内容：
// - 统一画质 / 同步等侧栏的宽度、底色、描边与滑入动画
// - 点左侧空白关闭
// -------------------------------------------------------------------------

import 'package:flutter/material.dart';

/// 从屏幕右侧滑出的面板外壳，内容由调用方提供。
class LiveSidePanel extends StatelessWidget {
  const LiveSidePanel({
    super.key,
    required this.child,
    required this.onClose,
    this.widthFactor = 0.62,
  });

  final Widget child;
  final VoidCallback onClose;

  /// 相对基准宽度的比例：只有一列文字的窄栏用 0.62，表单类用 0.8。
  final double widthFactor;

  @override
  Widget build(BuildContext context) {
    final Size size = MediaQuery.sizeOf(context);
    final bool landscape = size.width > size.height;
    final double baseWidth = landscape
        ? (size.width * 0.44).clamp(300.0, 460.0).toDouble()
        : (size.width * 0.68).clamp(250.0, 330.0).toDouble();
    final double panelWidth = baseWidth * widthFactor;

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
                  child: SingleChildScrollView(child: child),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
