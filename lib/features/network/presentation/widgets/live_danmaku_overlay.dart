// -------------------------------------------------------------------------
// 功能：横屏飘屏弹幕
//
// 参考 FreeCast 的做法：
// - 等像素速度：所有弹幕按「屏宽 / 9 秒」移动，长短弹幕不会互相追赶
// - 分轨道：按字号计算行高，默认使用上方 65% 区域
// - 防追尾：同轨道最后一条完全进入并留出 gap 后才允许下一条
// - 轨道全忙时直接丢弃，不排队（排队会让弹幕和画面错位）
//
// 实现上用单个 Ticker 推进所有位置，CustomPainter 统一绘制，
// 避免几十条弹幕各自重建 Widget。
// -------------------------------------------------------------------------

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../domain/danmaku_models.dart';

class LiveDanmakuOverlay extends StatefulWidget {
  const LiveDanmakuOverlay({
    super.key,
    required this.messages,
    this.paused = false,
    this.enabled = true,
    this.area = 0.5,
    this.opacity = 0.8,
    this.fontScale = 1.0,
    this.speed = 1.0,
  });

  /// 新弹幕流。只播放订阅之后到达的消息，转屏不重放历史。
  final Stream<DanmakuMessage> messages;

  /// 暂停时冻结弹幕，和画面保持一致。
  final bool paused;

  /// 弹幕开关：关闭后清空当前弹幕，也不再生成新的。
  final bool enabled;

  /// 显示区域占屏幕高度的比例（0.1 ~ 1.0）。
  final double area;

  /// 不透明度（0.2 ~ 1.0）。
  final double opacity;

  /// 字号缩放（0.5 ~ 2.0）。
  final double fontScale;

  /// 速度倍率（0.5 ~ 2.0）。
  final double speed;

  @override
  State<LiveDanmakuOverlay> createState() => _LiveDanmakuOverlayState();
}

class _LiveDanmakuOverlayState extends State<LiveDanmakuOverlay>
    with SingleTickerProviderStateMixin {
  /// 基准字号，实际字号 = 基准 × 用户缩放。
  static const double _baseFontSize = 18;

  /// 同轨道两条弹幕之间的最小间距。
  static const double _gap = 32;

  /// 同屏最多 45 条，和 FreeCast 默认密度接近。
  static const int _maxBullets = 45;

  /// 穿过一屏宽度所需秒数；像素速度 = 宽度 / 该值。
  static const double _secondsPerWidth = 9;

  static const double _topPadding = 8;

  late final Ticker _ticker;
  final List<_FlyingBullet> _bullets = <_FlyingBullet>[];
  final ValueNotifier<int> _repaint = ValueNotifier<int>(0);

  StreamSubscription<DanmakuMessage>? _subscription;
  Size _size = Size.zero;
  int _nextLane = 0;
  Duration? _lastTick;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    _subscription = widget.messages.listen(_spawn);
  }

  /// 只有真的有弹幕在飞时才启动 Ticker，空闲时完全不占帧。
  void _ensureTicker() {
    if (_ticker.isActive) return;
    if (widget.paused || !widget.enabled || _bullets.isEmpty) return;
    _lastTick = null;
    _ticker.start();
  }

  double get _fontSize => _baseFontSize * widget.fontScale.clamp(0.5, 2.0);

  double get _laneHeight => _fontSize * 1.8 + 4;

  double get _areaFactor => widget.area.clamp(0.1, 1.0);

  @override
  void didUpdateWidget(covariant LiveDanmakuOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.messages != widget.messages) {
      _subscription?.cancel();
      _subscription = widget.messages.listen(_spawn);
    }
    // 字号或显示区域变化后，旧轨道与文本尺寸不再成立，直接清空。
    if (oldWidget.fontScale != widget.fontScale ||
        oldWidget.area != widget.area) {
      _bullets.clear();
      _nextLane = 0;
      _ticker.stop();
      _repaint.value++;
    }
    if (oldWidget.speed != widget.speed) {
      final double speed = _size.width / _secondsPerWidth * widget.speed;
      for (final _FlyingBullet bullet in _bullets) {
        bullet.speed = speed;
      }
    }
    if (oldWidget.enabled != widget.enabled) {
      if (!widget.enabled) {
        _bullets.clear();
        _ticker.stop();
      } else {
        _ensureTicker();
      }
      _repaint.value++;
    }
    if (oldWidget.paused != widget.paused) {
      if (widget.paused) {
        _ticker.stop();
      } else {
        _ensureTicker();
      }
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _ticker.dispose();
    _repaint.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- 推进

  void _onTick(Duration elapsed) {
    if (!widget.enabled) {
      _ticker.stop();
      return;
    }
    final Duration? previous = _lastTick;
    _lastTick = elapsed;
    if (previous == null) return;

    double delta = (elapsed - previous).inMicroseconds / 1000000;
    // 切后台 / 掉帧后不要一步跳很远，最多按一帧推进。
    if (delta <= 0 || delta > 0.1) delta = 1 / 60;

    bool removed = false;
    for (final _FlyingBullet bullet in _bullets) {
      bullet.x -= bullet.speed * delta;
      if (bullet.x + bullet.width < -24) removed = true;
    }
    if (removed) {
      _bullets.removeWhere(
        (_FlyingBullet bullet) => bullet.x + bullet.width < -24,
      );
    }
    _repaint.value++;
    if (_bullets.isEmpty) {
      // 最后一条飞出屏幕后停下，等新弹幕到来再启动。
      _ticker.stop();
      _lastTick = null;
    }
  }

  // ---------------------------------------------------------------- 生成

  void _spawn(DanmakuMessage message) {
    if (!mounted || widget.paused || !widget.enabled) return;
    if (_size.width < 1 || _size.height < 1) return;
    if (_bullets.length >= _maxBullets) return;

    final String text = message.superChat
        ? '¥${message.price} ${message.text}'
        : message.text;
    if (text.trim().isEmpty) return;

    final TextPainter painter = _buildPainter(
      text: text,
      color: _readableColor(message.color),
      bold: message.superChat,
      maxWidth: _size.width * 0.88,
    );
    if (painter.width <= 0) return;

    final int rows = math.max(
      1,
      ((_size.height - _topPadding * 2) * _areaFactor / _laneHeight).floor(),
    );
    final int? lane = _pickLane(rows);
    if (lane == null) return;

    _nextLane = (lane + 1) % rows;
    final double y =
        _topPadding +
        lane * _laneHeight +
        math.max(0.0, (_laneHeight - painter.height) / 2);

    _bullets.add(
      _FlyingBullet(
        painter: painter,
        lane: lane,
        x: _size.width,
        y: y,
        width: painter.width,
        // 等像素速度：长弹幕耗时更长，但每秒移动的距离相同。
        speed: _size.width / _secondsPerWidth * widget.speed,
      ),
    );
    _repaint.value++;
    _ensureTicker();
  }

  /// 从上次轨道的下一条开始轮询，找到第一条尾部已经进入屏幕 left-gap 的轨道。
  int? _pickLane(int rows) {
    for (int i = 0; i < rows; i++) {
      final int lane = (_nextLane + i) % rows;
      bool free = true;
      for (final _FlyingBullet bullet in _bullets) {
        if (bullet.lane != lane) continue;
        if (bullet.x + bullet.width > _size.width - _gap) {
          free = false;
          break;
        }
      }
      if (free) return lane;
    }
    return null;
  }

  TextPainter _buildPainter({
    required String text,
    required Color color,
    required bool bold,
    required double maxWidth,
  }) {
    final TextPainter painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: _fontSize,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
          height: 1.3,
          shadows: const <Shadow>[
            Shadow(color: Colors.black87, blurRadius: 3),
            Shadow(color: Colors.black, offset: Offset(1, 1), blurRadius: 2),
          ],
        ),
      ),
      maxLines: 1,
      ellipsis: '…',
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxWidth);
    return painter;
  }

  /// 深色弹幕在亮画面上看不清、在暗画面上也发灰，统一向白色提亮。
  static Color _readableColor(int rgb) {
    final Color raw = Color(0xFF000000 | (rgb & 0xFFFFFF));
    if (raw.computeLuminance() >= 0.28) return raw;
    return Color.lerp(raw, Colors.white, 0.55) ?? Colors.white;
  }

  // ---------------------------------------------------------------- 绘制

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final Size size = Size(constraints.maxWidth, constraints.maxHeight);
        if (size != _size) {
          // 尺寸变化（转屏 / 分屏）后旧轨道不再成立，直接清空。
          _size = size;
          _bullets.clear();
          _nextLane = 0;
        }
        return IgnorePointer(
          child: RepaintBoundary(
            child: CustomPaint(
              size: Size.infinite,
              painter: _DanmakuPainter(
                bullets: _bullets,
                repaint: _repaint,
                opacity: widget.opacity,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _FlyingBullet {
  _FlyingBullet({
    required this.painter,
    required this.lane,
    required this.x,
    required this.y,
    required this.width,
    required this.speed,
  });

  final TextPainter painter;
  final int lane;
  final double y;
  final double width;

  /// 每秒移动的像素数；调节速度时会在原值上更新。
  double speed;

  /// 左边缘位置，每帧按 [speed] 向左推进。
  double x;
}

class _DanmakuPainter extends CustomPainter {
  _DanmakuPainter({
    required this.bullets,
    required this.repaint,
    required this.opacity,
  }) : super(repaint: repaint);

  final List<_FlyingBullet> bullets;
  final Listenable repaint;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    final double alpha = opacity.clamp(0.0, 1.0);
    final bool layered = alpha < 0.999;
    if (layered) {
      canvas.saveLayer(
        Offset.zero & size,
        Paint()..color = Colors.white.withValues(alpha: alpha),
      );
    }
    for (final _FlyingBullet bullet in bullets) {
      if (bullet.x > size.width + 40) continue;
      if (bullet.x + bullet.width < -40) continue;
      bullet.painter.paint(canvas, Offset(bullet.x, bullet.y));
    }
    if (layered) canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _DanmakuPainter oldDelegate) => true;
}
