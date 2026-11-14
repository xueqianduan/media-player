// -------------------------------------------------------------------------
// 功能：弹幕设置侧栏（横屏）
//
// 主要内容：
// - 显示区域 / 不透明度 / 字体大小 / 弹幕速度 四个滑块
// - 修改立即生效并持久化
// - 复用 LiveSidePanel，从右侧滑出
// -------------------------------------------------------------------------

import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import 'live_side_panel.dart';

class LiveDanmakuSettingsPanel extends StatelessWidget {
  const LiveDanmakuSettingsPanel({
    super.key,
    required this.area,
    required this.opacity,
    required this.fontScale,
    required this.speed,
    required this.onAreaChanged,
    required this.onOpacityChanged,
    required this.onFontScaleChanged,
    required this.onSpeedChanged,
    required this.onReset,
    required this.onClose,
  });

  final double area;
  final double opacity;
  final double fontScale;
  final double speed;

  final ValueChanged<double> onAreaChanged;
  final ValueChanged<double> onOpacityChanged;
  final ValueChanged<double> onFontScaleChanged;
  final ValueChanged<double> onSpeedChanged;
  final VoidCallback onReset;
  final VoidCallback onClose;

  /// 显示区域五档：10% / 25% / 50% / 75% / 100%。
  static const List<double> areaOptions = <double>[
    0.10,
    0.25,
    0.50,
    0.75,
    1.00,
  ];
  static const List<String> areaLabels = <String>[
    '10%',
    '25%',
    '50%',
    '75%',
    '100%',
  ];

  /// 速度五档，映射到飘屏的速度倍率。
  static const List<double> speedOptions = <double>[0.5, 0.75, 1.0, 1.5, 2.0];
  static const List<String> speedLabels = <String>[
    '极慢',
    '较慢',
    '正常',
    '较快',
    '极快',
  ];

  static int nearestIndex(List<double> values, double value) {
    int best = 0;
    double distance = double.infinity;
    for (int i = 0; i < values.length; i++) {
      final double next = (values[i] - value).abs();
      if (next < distance) {
        distance = next;
        best = i;
      }
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    final int areaIndex = nearestIndex(areaOptions, area);
    final int speedIndex = nearestIndex(speedOptions, speed);
    return LiveSidePanel(
      onClose: onClose,
      widthFactor: 0.95,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 12, 16, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Expanded(
                  child: Text(
                    '弹幕设置',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: onClose,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(
                    Icons.close_rounded,
                    color: Colors.white54,
                    size: 20,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            _DanmakuSlider(
              title: '显示区域',
              valueLabel: areaLabels[areaIndex],
              value: areaIndex.toDouble(),
              min: 0,
              max: (areaOptions.length - 1).toDouble(),
              divisions: areaOptions.length - 1,
              onChanged: (double next) =>
                  onAreaChanged(areaOptions[next.round()]),
            ),
            _DanmakuSlider(
              title: '不透明度',
              valueLabel: '${(opacity * 100).round()}%',
              value: opacity,
              min: 0.2,
              max: 1.0,
              onChanged: onOpacityChanged,
            ),
            _DanmakuSlider(
              title: '字体大小',
              valueLabel: '${(fontScale * 100).round()}%',
              value: fontScale,
              min: 0.5,
              max: 2.0,
              onChanged: onFontScaleChanged,
            ),
            _DanmakuSlider(
              title: '弹幕速度',
              valueLabel: speedLabels[speedIndex],
              value: speedIndex.toDouble(),
              min: 0,
              max: (speedOptions.length - 1).toDouble(),
              divisions: speedOptions.length - 1,
              onChanged: (double next) =>
                  onSpeedChanged(speedOptions[next.round()]),
            ),
            const SizedBox(height: 6),
            const Text(
              '只影响横屏飘屏弹幕，竖屏弹幕列表保持原样。',
              style: TextStyle(color: Colors.white38, fontSize: 10.5),
            ),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: onReset,
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white54,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  textStyle: const TextStyle(fontSize: 11.5),
                ),
                child: const Text('恢复默认'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DanmakuSlider extends StatelessWidget {
  const _DanmakuSlider({
    required this.title,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    this.divisions,
    required this.onChanged,
  });

  final String title;
  final String valueLabel;
  final double value;
  final double min;
  final double max;

  /// null 表示连续滑动，不显示刻度点。
  final int? divisions;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(color: Colors.white70, fontSize: 12.5),
                ),
              ),
              Text(
                valueLabel,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              activeTrackColor: AppColors.primary,
              inactiveTrackColor: Colors.white12,
              thumbColor: Colors.white,
              overlayColor: AppColors.primary.withValues(alpha: 0.16),
              tickMarkShape: const RoundSliderTickMarkShape(
                tickMarkRadius: 1.4,
              ),
              activeTickMarkColor: Colors.white70,
              inactiveTickMarkColor: Colors.white24,
            ),
            child: SizedBox(
              height: 34,
              child: Slider(
                value: value.clamp(min, max),
                min: min,
                max: max,
                divisions: divisions,
                onChanged: onChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
