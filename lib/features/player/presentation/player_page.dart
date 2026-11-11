// -------------------------------------------------------------------------
// 功能：播放器页面
//
// 主要内容：
// - 播放状态与引擎装配
// - 单击/双击/滑动/长按手势
// - 控制层、倍速/更多/队列面板、错误兜底
// -------------------------------------------------------------------------

import 'dart:async';

import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:volume_controller/volume_controller.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../app/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../library/application/library_controller.dart';
import '../../library/domain/models.dart';
import '../../library/presentation/video_actions.dart';
import '../../settings/application/settings_controller.dart';
import '../../settings/domain/app_settings.dart';
import '../data/media_kit_engine.dart';
import '../domain/playback_engine.dart';
import '../domain/playback_queue.dart';
import '../domain/playback_session.dart';

/// 播放器页面：全屏播放 + 手势 + 队列 + 倍速 + 进度记忆。
class PlayerPage extends ConsumerStatefulWidget {
  const PlayerPage({super.key, required this.args});

  final PlayerArgs args;

  @override
  ConsumerState<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends ConsumerState<PlayerPage>
    with WidgetsBindingObserver {
  late final PlaybackSession _session;
  Timer? _hideTimer;
  bool _controlsVisible = true;
  bool _landscape = false;
  double _brightness = 1;
  double _volume = 1;
  bool _boosted = false;
  double? _dragPositionMs;
  String? _gestureHint;
  Timer? _hintTimer;
  bool _initialised = false;
  _PlayerPanel? _panel;
  double _boostBase = 1;
  double _boostStart = 2;
  double _lastBoost = 2;

  /// 长按调速时，横向滑动多少逻辑像素换一档（0.25x）。
  double _boostStepPx = 72;
  bool _resumeTipVisible = false;
  Timer? _resumeTipTimer;
  // 双指缩放
  final Map<int, Offset> _pointers = <int, Offset>{};
  double _videoScale = 1.0;
  Offset _videoOffset = Offset.zero;
  double _pinchStartDistance = 0;
  double _pinchStartScale = 1.0;
  Offset _pinchStartFocal = Offset.zero;
  Offset _pinchStartOffset = Offset.zero;
  bool _pinching = false;
  bool _locked = false;
  bool _lockIconVisible = false;
  Timer? _lockIconTimer;

  @override
  // ===== 生命周期与初始化 =====
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 拖动调节音量时不要弹出系统音量面板。
    VolumeController.instance.showSystemUI = false;
    VolumeController.instance.addListener(_onSystemVolumeChanged);
    unawaited(_loadSystemLevels());
    final LibraryState library = ref.read(libraryControllerProvider);
    // 提前取出依赖：State.dispose() 里不能再碰 ref，否则 Riverpod 会抛
    // StateError，销毁流程中断导致播放引擎泄漏。
    final LibraryController libraryController = ref.read(
      libraryControllerProvider.notifier,
    );
    final resolver = ref.read(mediaResolverProvider);
    final MediaItem? first = _itemFor(widget.args.startIndex, library);
    if (first == null) {
      _session = PlaybackSession(
        engine: _FailedEngine(),
        queue: PlaybackQueue(mediaIds: const <String>[]),
        mediaById: const <String, MediaItem>{},
        resolveSource: (_) async => null,
        onSaveProgress:
            ({
              required String mediaId,
              required int positionMs,
              required int durationMs,
              required bool completed,
            }) {},
      );
      return;
    }

    _session = PlaybackSession(
      engine: MediaKitPlaybackEngine(),
      queue: PlaybackQueue(
        mediaIds: widget.args.mediaIds,
        startIndex: widget.args.startIndex,
        repeatMode: widget.args.repeatMode,
      ),
      mediaById: library.mediaById,
      resolveSource: (MediaItem item) => resolver.resolve(item),
      onSaveProgress:
          ({
            required String mediaId,
            required int positionMs,
            required int durationMs,
            required bool completed,
          }) {
            libraryController.saveProgress(
              mediaId: mediaId,
              positionMs: positionMs,
              durationMs: durationMs,
              completed: completed,
              speed: _speedToPersist,
            );
          },
      initialSpeed: ref.read(settingsControllerProvider).defaultSpeed,
    );
    // 首帧即绑定当前视频，避免在 post-frame 打开前渲染错误页。
    _session.currentMediaId.value = first.id;
    _session.currentMediaId.addListener(_resetVideoZoom);
    _session.repeatMode.value = widget.args.repeatMode;
    _session.playing.addListener(_syncWakelock);
    WidgetsBinding.instance.addPostFrameCallback((_) => _prepareAndStart());
    _scheduleHide();
  }

  void _onSystemVolumeChanged(double volume) {
    if (!mounted) return;
    setState(() => _volume = volume.clamp(0.0, 1.0));
  }

  /// 读取当前系统亮度与媒体音量，避免每次滑动都从 100% 开始。
  Future<void> _loadSystemLevels() async {
    try {
      final double appBrightness = await ScreenBrightness.instance.application;
      final double systemBrightness = appBrightness >= 0
          ? appBrightness
          : await ScreenBrightness.instance.system;
      if (mounted) {
        setState(() => _brightness = systemBrightness.clamp(0.0, 1.0));
      }
    } on Object {
      // 部分平台（桌面 / 模拟器）不支持读取亮度，忽略即可。
    }
    try {
      final double volume = await VolumeController.instance.getVolume();
      if (mounted) setState(() => _volume = volume.clamp(0.0, 1.0));
    } on Object {
      // 忽略不支持音量控制的平台。
    }
  }

  MediaItem? _itemFor(int index, LibraryState library) {
    if (widget.args.mediaIds.isEmpty) return null;
    final int safe = index.clamp(0, widget.args.mediaIds.length - 1);
    return library.mediaById[widget.args.mediaIds[safe]];
  }

  Future<void> _prepareAndStart() async {
    if (_initialised || !mounted) return;
    _initialised = true;
    final MediaItem? item = _session.currentItem;
    if (item == null) return;
    final PlaybackProgress? record = ref
        .read(libraryControllerProvider)
        .progressOf(item.id);
    final bool prompt = ref.read(settingsControllerProvider).resumePrompt;
    // 有上次进度时直接从该位置开始，不再用阻塞式对话框；
    // 画面下方给一个「重新开始」入口，点了立刻回到 0。
    final bool resume = record != null && record.shouldResume && prompt;
    final Duration startAt = resume
        ? Duration(milliseconds: record.positionMs)
        : Duration.zero;
    // 单视频倍速记忆：优先用这个视频上次的倍速，没有记录才回落全局默认。
    final double fallbackSpeed = ref
        .read(settingsControllerProvider)
        .defaultSpeed;
    final double initialSpeed = record != null && record.speed > 0
        ? record.speed
        : fallbackSpeed;
    _session.speed.value = initialSpeed.clamp(0.5, 5.0);
    await _session.start(startAt: startAt);
    if (!mounted) return;
    if (resume) _showResumeTip();
    _scheduleHide();
  }

  // ---------------------------------------------------------------- 双指缩放

  // ===== 画面缩放、拖拽与截图 =====
  double _pointerDistance() {
    final List<Offset> points = _pointers.values.take(2).toList();
    if (points.length < 2) return 0;
    return (points.first - points.last).distance;
  }

  Offset _pointerFocal() {
    final List<Offset> points = _pointers.values.take(2).toList();
    if (points.length < 2) return Offset.zero;
    return (points.first + points.last) / 2;
  }

  Offset _clampVideoOffset(Offset offset, double scale) {
    final Size size = MediaQuery.sizeOf(context);
    final double maxX = (scale - 1) * size.width / 2;
    final double maxY = (scale - 1) * size.height / 2;
    return Offset(offset.dx.clamp(-maxX, maxX), offset.dy.clamp(-maxY, maxY));
  }

  void _onPointerDown(PointerDownEvent event) {
    // 锁屏或右侧面板打开时不响应缩放。
    if (_locked || _panel != null) return;
    _pointers[event.pointer] = event.localPosition;
    if (_pointers.length == 2) {
      _pinching = true;
      _pinchStartDistance = _pointerDistance();
      _pinchStartScale = _videoScale;
      _pinchStartFocal = _pointerFocal();
      _pinchStartOffset = _videoOffset;
      _hideTimer?.cancel();
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (!_pointers.containsKey(event.pointer)) return;
    _pointers[event.pointer] = event.localPosition;
    if (!_pinching || _pinchStartDistance <= 0) return;
    final double distance = _pointerDistance();
    if (distance <= 0) return;
    final double scale = (_pinchStartScale * distance / _pinchStartDistance)
        .clamp(1.0, 4.0);
    // 双指整体移动时平移画面，方便放大看局部。
    final Offset offset =
        _pinchStartOffset + (_pointerFocal() - _pinchStartFocal);
    setState(() {
      _videoScale = scale;
      _videoOffset = _clampVideoOffset(offset, scale);
    });
  }

  void _onPointerEnd(PointerEvent event) {
    _pointers.remove(event.pointer);
    if (_pointers.length >= 2) return;
    _pinching = false;
    _pinchStartDistance = 0;
    if (!mounted) return;
    if (_videoScale < 1.02) {
      setState(() {
        _videoScale = 1.0;
        _videoOffset = Offset.zero;
      });
    } else {
      setState(
        () => _videoOffset = _clampVideoOffset(_videoOffset, _videoScale),
      );
    }
    _scheduleHide();
  }

  void _resetVideoZoom() {
    if (_videoScale == 1.0 && _videoOffset == Offset.zero) return;
    setState(() {
      _videoScale = 1.0;
      _videoOffset = Offset.zero;
    });
  }

  // ------------------------------------------------------------ 截图 / 锁定

  Future<void> _takeScreenshot() async {
    final VideoPlaybackEngine engine = _session.engine;
    if (engine is! MediaKitPlaybackEngine) {
      _showHint('当前播放器不支持截图');
      return;
    }

    // 首次点击先解释一次，避免直接弹系统权限框让用户莫名其妙。
    if (!ref.read(settingsControllerProvider).screenshotTipShown) {
      if (!mounted) return;
      final bool? confirmed = await showDialog<bool>(
        context: context,
        builder: (BuildContext dialogContext) => AlertDialog(
          title: const Text(
            '保存截图',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          content: const Text(
            '截图会保存到手机相册，首次使用需要授权相册访问权限。',
            style: TextStyle(fontSize: 13.5, height: 1.6),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text(
                '继续',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      ref.read(settingsControllerProvider.notifier).markScreenshotTipShown();
    }

    _showHint('正在截图…');
    final Uint8List? bytes = await engine.screenshot();
    if (bytes == null || bytes.isEmpty) {
      if (mounted) _showHint('截图失败，请重试');
      return;
    }

    try {
      if (!await Gal.hasAccess()) {
        final bool granted = await Gal.requestAccess();
        if (!granted) {
          if (mounted) _showHint('未获得相册权限，截图未保存');
          return;
        }
      }
      await Gal.putImageBytes(
        bytes,
        name: 'LumiPlayer_${DateTime.now().millisecondsSinceEpoch}',
      );
      if (mounted) _showHint('截图已保存到相册');
    } on Object catch (error) {
      debugPrint('[LumiPlayer] save screenshot failed: $error');
      if (mounted) _showHint('保存失败，请检查相册权限');
    }
  }

  // ===== 锁定、侧栏与系统交互 =====
  void _toggleLock() {
    final bool next = !_locked;
    _resumeTipTimer?.cancel();
    _lockIconTimer?.cancel();
    _lockIconTimer?.cancel();
    setState(() {
      _locked = next;
      _lockIconVisible = false;
      _panel = null;
      _resumeTipVisible = false;
      _controlsVisible = !next;
    });
    if (next) {
      _showHint('画面已锁定，点击屏幕显示解锁按钮');
    } else {
      _scheduleHide();
    }
  }

  /// 锁屏状态下点屏幕：只浮现一个锁图标，几秒后自动消失。
  void _showLockIcon() {
    _lockIconTimer?.cancel();
    if (!_lockIconVisible) setState(() => _lockIconVisible = true);
    _lockIconTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _lockIconVisible = false);
    });
  }

  /// 左侧竖排浮层：截图 / 锁屏。lockedOnly 时只保留锁图标且位置不变。
  Widget _buildSideRail({bool lockedOnly = false}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (lockedOnly)
          const SizedBox(height: 50)
        else ...<Widget>[
          _SideIconButton(
            icon: Icons.photo_camera_outlined,
            tooltip: '截图',
            onTap: _takeScreenshot,
          ),
          const SizedBox(height: 10),
        ],
        _SideIconButton(
          icon: lockedOnly ? Icons.lock_rounded : Icons.lock_open_rounded,
          tooltip: lockedOnly ? '解锁' : '锁定画面',
          onTap: _toggleLock,
        ),
      ],
    );
  }

  void _showResumeTip() {
    _resumeTipTimer?.cancel();
    setState(() => _resumeTipVisible = true);
    _resumeTipTimer = Timer(const Duration(seconds: 8), () {
      if (mounted) setState(() => _resumeTipVisible = false);
    });
  }

  void _dismissResumeTip() {
    _resumeTipTimer?.cancel();
    if (_resumeTipVisible) setState(() => _resumeTipVisible = false);
  }

  Future<void> _restartFromBeginning() async {
    _dismissResumeTip();
    await _session.seekTo(Duration.zero);
    if (mounted) _showHint('已从头开始播放');
  }

  /// 长按加速是临时状态，不要把那个倍速写进记录。
  double get _speedToPersist {
    final double value = _boosted ? _boostBase : _session.speed.value;
    return value.clamp(0.5, 5.0);
  }

  void _syncWakelock() {
    final bool keepOn = ref.read(settingsControllerProvider).keepScreenOn;
    if (_session.playing.value && keepOn) {
      WakelockPlus.enable();
    } else {
      WakelockPlus.disable();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _session.saveProgress();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hideTimer?.cancel();
    _hintTimer?.cancel();
    _resumeTipTimer?.cancel();
    WakelockPlus.disable();
    VolumeController.instance.removeListener().catchError((Object _) {});
    try {
      ScreenBrightness.instance.resetApplicationScreenBrightness().catchError(
        (Object _) {},
      );
    } on Object {
      // 忽略不支持的平台。
    }
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(const <DeviceOrientation>[
      DeviceOrientation.portraitUp,
    ]);
    _session.currentMediaId.removeListener(_resetVideoZoom);
    _session.dispose();
    super.dispose();
  }

  // ===== 控制层显隐与播放控制 =====
  void _scheduleHide() {
    _hideTimer?.cancel();
    if (_session.currentItem == null || _panel != null) return;
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _session.playing.value) {
        setState(() => _controlsVisible = false);
      }
    });
  }

  void _toggleControls() {
    if (_panel != null) {
      _closePanel();
      return;
    }
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) _scheduleHide();
  }

  void _showHint(String text) {
    _hintTimer?.cancel();
    setState(() => _gestureHint = text);
    _hintTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _gestureHint = null);
    });
  }

  Future<void> _togglePlay() async {
    await _session.togglePlay();
    if (!mounted) return;
    setState(() => _controlsVisible = true);
    _scheduleHide();
  }

  Future<void> _seekBy(Duration delta) async {
    await _session.seekBy(delta);
    _showHint(
      delta.isNegative
          ? '快退 ${delta.inSeconds.abs()} 秒'
          : '快进 ${delta.inSeconds} 秒',
    );
  }

  /// 双击左右两侧的快进/快退区域占 25%，中间 50% 用于播放暂停。
  static const double _doubleTapSideZone = 0.25;

  // ===== 手势：双击 / 横向 / 纵向 / 长按加速 =====
  Future<void> _onDoubleTap(TapDownDetails details) async {
    final double width = MediaQuery.sizeOf(context).width;
    final double x = details.localPosition.dx;
    if (x < width * _doubleTapSideZone) {
      await _seekBy(const Duration(seconds: -10));
    } else if (x > width * (1 - _doubleTapSideZone)) {
      await _seekBy(const Duration(seconds: 10));
    } else {
      await _togglePlay();
    }
  }

  double _seekStartMs = 0;
  double _seekAccumMs = 0;
  double _seekMsPerPx = 120;
  double _seekTargetMs = 0;
  bool _seeking = false;

  /// 左右滑动调进度：横向位移累计后换算成毫秒，松手才真正 seek。
  void _onHorizontalStart(DragStartDetails details) {
    final double durationMs = _session.duration.value.inMilliseconds.toDouble();
    _seeking = true;
    _seekStartMs = _session.position.value.inMilliseconds.toDouble();
    _seekAccumMs = 0;
    _seekTargetMs = _seekStartMs;
    // 一整屏宽度大约覆盖 20 秒 ~ 3 分钟：短视频不粗、长视频不慢。
    final double span = durationMs <= 0
        ? 60000
        : durationMs.clamp(20000, 180000).toDouble();
    _seekMsPerPx = span / MediaQuery.sizeOf(context).width;
    _hideTimer?.cancel();
    if (!_controlsVisible) setState(() => _controlsVisible = true);
  }

  void _onHorizontalUpdate(DragUpdateDetails details) {
    if (!_seeking || _pinching) return;
    final double durationMs = _session.duration.value.inMilliseconds.toDouble();
    if (durationMs <= 0) return;
    _seekAccumMs += details.primaryDelta! * _seekMsPerPx;
    _seekTargetMs = (_seekStartMs + _seekAccumMs).clamp(0.0, durationMs);
    _updateSeekUi(
      _seekTargetMs,
      '${formatDuration(_seekTargetMs.round())} / '
      '${formatDuration(durationMs.round())}',
    );
  }

  Future<void> _onHorizontalEnd(DragEndDetails details) async {
    if (!_seeking) return;
    _seeking = false;
    final double target = _seekTargetMs;
    // 先完成跳转再清掉预览值，避免进度条先弹回旧位置。
    if (_seekAccumMs.abs() > 1) {
      await _session.seekTo(Duration(milliseconds: target.round()));
    }
    if (!mounted) return;
    setState(() => _dragPositionMs = null);
    _scheduleHide();
  }

  void _onHorizontalCancel() {
    _seeking = false;
    if (mounted) setState(() => _dragPositionMs = null);
  }

  /// 拖动进度时同时更新进度条位置与中间提示。
  void _updateSeekUi(double targetMs, String hint) {
    _hintTimer?.cancel();
    setState(() {
      _dragPositionMs = targetMs;
      _gestureHint = hint;
    });
    _hintTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _gestureHint = null);
    });
  }

  void _onVerticalStart(DragStartDetails details) {
    final Size size = MediaQuery.sizeOf(context);
    _dragStartFraction = details.localPosition.dx / size.width;
    _dragStartBrightness = _brightness;
    _dragStartVolume = _volume;
    // 累计滑动量：整段手势内一直叠加，而不是只看最后一帧。
    _dragAccum = 0;
    // 竖直滑动屏幕高度的 70% 即为 0 → 100%，小屏手机也不会太钝。
    _dragRangePx = size.height * 0.7;
  }

  double _dragStartFraction = 0.5;
  double _dragStartBrightness = 1;
  double _dragStartVolume = 1;
  double _dragAccum = 0;
  double _dragRangePx = 220;

  void _onVerticalUpdate(DragUpdateDetails details) {
    if (_pinching) return;
    // primaryDelta 是「相对上一次回调」的增量，必须累加后再叠加到起始值上。
    _dragAccum += -details.primaryDelta! / _dragRangePx;
    if (_dragStartFraction < 0.4) {
      final double value = (_dragStartBrightness + _dragAccum).clamp(0.05, 1.0);
      setState(() => _brightness = value);
      // 直接修改当前窗口亮度（不申请系统设置权限，退出播放器后恢复）。
      ScreenBrightness.instance
          .setApplicationScreenBrightness(value)
          .catchError((Object error) => debugPrint('调节亮度失败：$error'));
      _showHint('亮度 ${(value * 100).round()}%');
    } else {
      final double value = (_dragStartVolume + _dragAccum).clamp(0.0, 1.0);
      setState(() => _volume = value);
      // 调节系统媒体音量，而不是只调播放器内部音量。
      VolumeController.instance
          .setVolume(value)
          .catchError((Object error) => debugPrint('调节音量失败：$error'));
      _showHint('音量 ${(value * 100).round()}%');
    }
  }

  String _formatSpeed(double value) {
    if (value == value.roundToDouble()) return value.toStringAsFixed(1);
    return value
        .toStringAsFixed(2)
        .replaceFirst(RegExp(r'0$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  Future<void> _startBoost() async {
    if (_boosted) return;
    _boostBase = _session.speed.value;
    _boostStart = ref.read(settingsControllerProvider).longPressSpeed;
    _lastBoost = _boostStart;
    // 灵敏度：横向滑过约 1/20 屏宽就换一档（0.25x），
    // 半屏大约能调 2.5x，比原来固定 70px 一档明显更跟手。
    _boostStepPx = (MediaQuery.sizeOf(context).width / 20).clamp(14.0, 56.0);
    _hintTimer?.cancel();
    setState(() {
      _boosted = true;
      _gestureHint = null;
    });
    await _session.setSpeed(_boostStart);
  }

  /// 长按后左右滑动：以 0.25x 为步进，在 0.5x ~ 5x 之间调整。
  Future<void> _onBoostMove(LongPressMoveUpdateDetails details) async {
    if (!_boosted) return;
    final double dx = details.localOffsetFromOrigin.dx;
    double speed = (_boostStart + dx / _boostStepPx * 0.25).clamp(0.5, 5.0);
    speed = (speed * 4).roundToDouble() / 4;
    if ((speed - _lastBoost).abs() < 0.001) return;
    _lastBoost = speed;
    // 刻度条通过 session.speed 自动刷新，这里不需要额外的文字提示。
    await _session.setSpeed(speed);
  }

  Future<void> _endBoost() async {
    if (!_boosted) return;
    _boosted = false;
    await _session.setSpeed(_boostBase);
    if (mounted) setState(() => _gestureHint = null);
  }

  Future<void> _toggleOrientation() async {
    _landscape = !_landscape;
    if (_landscape) {
      await SystemChrome.setPreferredOrientations(const <DeviceOrientation>[
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      await SystemChrome.setPreferredOrientations(const <DeviceOrientation>[
        DeviceOrientation.portraitUp,
      ]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    if (mounted) setState(() {});
  }

  void _showSharePlaceholder() {
    _showHint('分享功能后续开放');
  }

  // ===== 侧边面板：倍速 / 更多 / 队列 =====
  void _openPanel(_PlayerPanel panel) {
    _hideTimer?.cancel();
    setState(() {
      _panel = panel;
      _controlsVisible = true;
    });
  }

  void _closePanel() {
    if (_panel == null) return;
    setState(() => _panel = null);
    _scheduleHide();
  }

  /// 播放器内嵌面板：统一从屏幕右侧滑出，点左侧画面直接退出。
  Widget _buildPanelOverlay() {
    final Size size = MediaQuery.sizeOf(context);
    final bool landscape = size.width > size.height;
    final double baseWidth = landscape
        ? (size.width * 0.44).clamp(300.0, 460.0).toDouble()
        : (size.width * 0.68).clamp(250.0, 330.0).toDouble();
    // 倍速面板只放一列数字，宽度取一半。
    final double panelWidth = _panel == _PlayerPanel.speed
        ? baseWidth / 2
        : baseWidth;

    return Stack(
      children: <Widget>[
        // 面板左侧空白区域：点击直接关闭面板，继续看视频。
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          right: panelWidth,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _closePanel,
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
                    child: switch (_panel) {
                      _PlayerPanel.speed => _buildSpeedPanel(),
                      _PlayerPanel.queue => _buildQueuePanel(),
                      _PlayerPanel.more => _buildMorePanel(),
                      null => const SizedBox.shrink(),
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 倍速面板：右侧竖向排列，每档一个整行矩形，文字横纵居中。
  Widget _buildSpeedPanel() {
    final double current = _session.speed.value;
    final List<double> options = AppSettings.speedOptions.reversed.toList();
    final bool compact = MediaQuery.sizeOf(context).height < 520;
    final double rowHeight = compact ? 40 : 51;
    return Padding(
      padding: compact
          ? const EdgeInsets.fromLTRB(6, 6, 6, 10)
          : const EdgeInsets.fromLTRB(8, 8, 8, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (final double value in options)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                _session.setSpeed(value);
                _closePanel();
                _showHint('${_formatSpeed(value)}x 倍速');
              },
              child: Container(
                width: double.infinity,
                height: rowHeight,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: (current - value).abs() < 0.01
                      ? AppColors.primary
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${_formatSpeed(value)}x',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: (current - value).abs() < 0.01
                        ? Colors.white
                        : Colors.white70,
                    fontSize: compact ? 15 : 18.5,
                    fontWeight: (current - value).abs() < 0.01
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

  Widget _buildMorePanel() {
    final VideoScaleMode scaleMode = ref.watch(
      settingsControllerProvider.select(
        (AppSettings settings) => settings.videoScaleMode,
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 6, 12, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Text(
                '播放设置',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: _closePanel,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 32,
                  height: 32,
                ),
                icon: const Icon(
                  Icons.close_rounded,
                  color: Colors.white38,
                  size: 18,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ValueListenableBuilder<RepeatMode>(
            valueListenable: _session.repeatMode,
            builder: (BuildContext context, RepeatMode mode, _) {
              return _SettingsGroup(
                title: '播放方式：',
                children: <Widget>[
                  for (final RepeatMode option in RepeatMode.playbackModes)
                    _SettingsOption(
                      label: option.label,
                      selected: option == mode,
                      onTap: () {
                        _session.setRepeatMode(option);
                        _showHint(option.label);
                      },
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 22),
          _SettingsGroup(
            title: '画面尺寸：',
            children: <Widget>[
              for (final VideoScaleMode option in VideoScaleMode.values)
                _SettingsOption(
                  label: option.label,
                  selected: option == scaleMode,
                  onTap: () {
                    ref
                        .read(settingsControllerProvider.notifier)
                        .setVideoScaleMode(option);
                    _showHint(option.label);
                  },
                ),
            ],
          ),
          if (_session.queue.length > 1) ...<Widget>[
            const SizedBox(height: 22),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _openPanel(_PlayerPanel.queue),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(
                    Icons.queue_music_rounded,
                    size: 15,
                    color: Colors.white38,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '播放队列（${_session.queue.length}）',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12.5,
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    size: 16,
                    color: Colors.white30,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  BoxFit _fitFor(VideoScaleMode mode) {
    switch (mode) {
      case VideoScaleMode.original:
        return BoxFit.scaleDown;
      case VideoScaleMode.fit:
        return BoxFit.contain;
      case VideoScaleMode.cover:
        return BoxFit.cover;
      case VideoScaleMode.stretch:
        return BoxFit.fill;
    }
  }

  void _showSpeedSheet() => _openPanel(_PlayerPanel.speed);

  void _showMoreSheet() => _openPanel(_PlayerPanel.more);

  Widget _buildQueuePanel() {
    final List<String> order = _session.queue.order;
    final Map<String, MediaItem> media = ref
        .read(libraryControllerProvider)
        .mediaById;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 6, 14, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                '播放队列（${order.length}）',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: _closePanel,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 32,
                  height: 32,
                ),
                icon: const Icon(
                  Icons.close_rounded,
                  color: Colors.white38,
                  size: 18,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (int i = 0; i < order.length; i++)
            Builder(
              builder: (BuildContext context) {
                final MediaItem? item = media[order[i]];
                if (item == null) return const SizedBox.shrink();
                final bool active = i == _session.queue.index;
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    _session.jumpTo(i);
                    _closePanel();
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          item.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: active ? AppColors.primary : Colors.white,
                            fontSize: 12.5,
                            fontWeight: active
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          formatDuration(item.durationMs),
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 10.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  @override
  // ===== 页面骨架 =====
  Widget build(BuildContext context) {
    if (widget.args.mediaIds.isEmpty || _session.currentItem == null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Text(
                '视频不存在或已被移除',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () =>
                    context.canPop() ? context.pop() : context.go('/'),
                child: const Text('返回'),
              ),
            ],
          ),
        ),
      );
    }

    final VideoScaleMode scaleMode = ref.watch(
      settingsControllerProvider.select(
        (AppSettings settings) => settings.videoScaleMode,
      ),
    );

    return Scaffold(
      backgroundColor: Colors.black,
      body: PopScope<Object?>(
        // 锁定状态下系统返回键先解锁，避免误退出。
        canPop: !_locked,
        onPopInvokedWithResult: (bool didPop, Object? result) {
          if (!didPop && _locked) _toggleLock();
        },
        child: Listener(
          // 只观察原始指针事件，不参与手势竞争，不影响单击/双击/拖动。
          behavior: HitTestBehavior.translucent,
          onPointerDown: _onPointerDown,
          onPointerMove: _onPointerMove,
          onPointerUp: _onPointerEnd,
          onPointerCancel: _onPointerEnd,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              ValueListenableBuilder<String?>(
                valueListenable: _session.error,
                builder: (BuildContext context, String? error, _) {
                  if (error != null) {
                    return _ErrorView(
                      message: error,
                      onRetry: () =>
                          _session.start(startAt: _session.position.value),
                    );
                  }
                  return ClipRect(
                    child: Transform.translate(
                      offset: _videoOffset,
                      child: Transform.scale(
                        scale: _videoScale,
                        child: VideoSurface(
                          engine: _session.engine,
                          fit: _fitFor(scaleMode),
                        ),
                      ),
                    ),
                  );
                },
              ),
              // 手势层放在控制层下方：按钮不再被父级 GestureDetector 抢走点击。
              Positioned.fill(
                child: IgnorePointer(
                  ignoring: _locked,
                  child: _buildGestureLayer(),
                ),
              ),
              ValueListenableBuilder<bool>(
                valueListenable: _session.buffering,
                builder: (BuildContext context, bool buffering, _) {
                  if (!buffering) return const SizedBox.shrink();
                  return const Center(
                    child: SizedBox(
                      width: 34,
                      height: 34,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: Colors.white70,
                      ),
                    ),
                  );
                },
              ),
              if (_boosted)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Align(
                      alignment: const Alignment(0, 0.46),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 460),
                          child: _buildSpeedScale(),
                        ),
                      ),
                    ),
                  ),
                ),
              if (_gestureHint != null)
                Center(
                  child: IgnorePointer(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.playerScrim,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        _gestureHint!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                  ),
                ),
              Positioned.fill(
                child: IgnorePointer(
                  ignoring: !_controlsVisible || _locked,
                  child: AnimatedOpacity(
                    opacity: _controlsVisible ? 1 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: ValueListenableBuilder<String?>(
                      valueListenable: _session.currentMediaId,
                      builder: (BuildContext context, String? _, _) =>
                          _buildControls(context),
                    ),
                  ),
                ),
              ),
              if (_resumeTipVisible)
                Positioned(
                  // 左右安全区一起避开，横屏刘海在左侧也不会压住提示。
                  left: 16 + MediaQuery.paddingOf(context).left,
                  // 控制栏与进度条约占底部 90dp，再加上系统手势条的安全区，
                  // 保证提示始终落在进度条上方。
                  bottom: 96 + MediaQuery.paddingOf(context).bottom,
                  child: _buildResumeTip(),
                ),
              // 左侧竖直浮层：截图 + 锁屏。
              // 放进 SafeArea 再留 12dp，横屏时刘海/挖孔在左侧也不会挡住按钮。
              Positioned.fill(
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: IgnorePointer(
                        ignoring: _locked || !_controlsVisible,
                        child: AnimatedOpacity(
                          opacity: _controlsVisible && !_locked ? 1 : 0,
                          duration: const Duration(milliseconds: 180),
                          child: _buildSideRail(),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // 锁定态：点屏幕只浮现锁图标，点它解锁。
              if (_locked)
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _showLockIcon,
                    child: SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: _lockIconVisible
                              ? _buildSideRail(lockedOnly: true)
                              : const SizedBox.expand(),
                        ),
                      ),
                    ),
                  ),
                ),
              if (_panel != null) Positioned.fill(child: _buildPanelOverlay()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGestureLayer() {
    final bool gesturesEnabled = ref.watch(
      settingsControllerProvider.select(
        (AppSettings settings) => settings.gesturesEnabled,
      ),
    );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _toggleControls,
      onDoubleTapDown: _onDoubleTap,
      onDoubleTap: () {},
      onLongPressStart: (_) => _startBoost(),
      onLongPressMoveUpdate: _onBoostMove,
      onLongPressEnd: (_) => _endBoost(),
      onVerticalDragStart: gesturesEnabled && _panel == null
          ? _onVerticalStart
          : null,
      onVerticalDragUpdate: gesturesEnabled && _panel == null
          ? _onVerticalUpdate
          : null,
      onHorizontalDragStart: gesturesEnabled && _panel == null
          ? _onHorizontalStart
          : null,
      onHorizontalDragUpdate: gesturesEnabled && _panel == null
          ? _onHorizontalUpdate
          : null,
      onHorizontalDragEnd: gesturesEnabled && _panel == null
          ? _onHorizontalEnd
          : null,
      onHorizontalDragCancel: gesturesEnabled && _panel == null
          ? _onHorizontalCancel
          : null,
      child: const SizedBox.expand(),
    );
  }

  Widget _buildControls(BuildContext context) {
    final bool portrait =
        MediaQuery.orientationOf(context) == Orientation.portrait;
    return Stack(
      children: <Widget>[
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[
                    Color(0xCC000000),
                    Color(0x00000000),
                    Color(0x00000000),
                    Color(0xE6000000),
                  ],
                  stops: <double>[0, 0.22, 0.55, 1],
                ),
              ),
            ),
          ),
        ),
        SafeArea(
          child: Column(
            children: <Widget>[
              _buildTopBar(context),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                child: _buildProgressRow(context),
              ),
              _buildControlRow(context),
              if (portrait && _session.queue.length > 1)
                _buildQueuePreview(context),
              const SizedBox(height: 6),
            ],
          ),
        ),
      ],
    );
  }

  /// 长按调速时的横向速度刻度：当前档位高亮，并带一个指示三角。
  Widget _buildSpeedScale() {
    final List<double> options = AppSettings.speedOptions;
    return ValueListenableBuilder<double>(
      valueListenable: _session.speed,
      builder: (BuildContext context, double value, _) {
        int current = options.indexWhere(
          (double option) => (option - value).abs() < 0.01,
        );
        if (current < 0) {
          final int fallback = options.indexWhere(
            (double option) => (option - _lastBoost).abs() < 0.01,
          );
          current = fallback < 0 ? 0 : fallback;
        }
        return LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            // 减去容器左右各 4dp 的内边距，否则 Row 会超出 8dp。
            final double available = constraints.maxWidth - 8;
            // 按可用宽度决定一屏放几档，保持奇数让当前档位居中。
            int count = (available / 46).floor().clamp(3, options.length);
            if (count.isEven) count -= 1;
            int start = current - count ~/ 2;
            start = start.clamp(0, options.length - count);
            final List<double> window = options.sublist(start, start + count);
            final double slotWidth = available / count;
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 9),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.64),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Row(
                children: <Widget>[
                  for (final double option in window)
                    SizedBox(
                      width: slotWidth,
                      child: _SpeedScaleItem(
                        label: '${_formatSpeed(option)}x',
                        active: (option - value).abs() < 0.01,
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// 续播提示：左侧可关闭，右侧「重新开始」字号比说明文字大 2px。
  Widget _buildResumeTip() {
    return Material(
      color: Colors.transparent,
      // 整条提示都吞掉点击，避免点文字时透传成「显示/隐藏控制栏」。
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {},
        child: Container(
          padding: const EdgeInsets.fromLTRB(4, 4, 9, 4),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.66),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _dismissResumeTip,
                child: const Padding(
                  padding: EdgeInsets.all(3),
                  child: Icon(
                    Icons.close_rounded,
                    size: 14,
                    color: Colors.white54,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              const Text(
                '从上次停止的位置开始',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(width: 12),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _restartFromBeginning,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                  child: Text(
                    '重新开始',
                    style: TextStyle(
                      color: Color(0xFF4C8DFF),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 4, 8, 0),
      child: Row(
        children: <Widget>[
          IconButton(
            onPressed: () => context.pop(),
            icon: const Icon(
              Icons.arrow_back_ios_new_rounded,
              color: Colors.white,
              size: 19,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  _session.currentTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (_session.queue.length > 1) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(
                    '${_session.queue.index + 1} / ${_session.queue.length}',
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 10.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            tooltip: '分享（占位）',
            onPressed: _showSharePlaceholder,
            icon: const Icon(
              Icons.share_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
          IconButton(
            tooltip: '更多设置',
            onPressed: _showMoreSheet,
            icon: const Icon(
              Icons.more_horiz_rounded,
              color: Colors.white,
              size: 21,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressRow(BuildContext context) {
    return ValueListenableBuilder<Duration>(
      valueListenable: _session.position,
      builder: (BuildContext context, Duration position, _) {
        return ValueListenableBuilder<Duration>(
          valueListenable: _session.duration,
          builder: (BuildContext context, Duration duration, _) {
            final double total = duration.inMilliseconds.toDouble();
            final double currentMs =
                _dragPositionMs ?? position.inMilliseconds.toDouble();
            final double safe = total <= 0 ? 0 : currentMs.clamp(0, total);
            // 进度条左右两侧显示时间：左侧已播放，右侧总时长。
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                SizedBox(
                  width: 48,
                  child: Text(
                    formatDuration(safe.round()),
                    textAlign: TextAlign.left,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 2.5,
                      activeTrackColor: AppColors.primary,
                      inactiveTrackColor: Colors.white24,
                      thumbColor: AppColors.primary,
                      overlayShape: const RoundSliderOverlayShape(
                        overlayRadius: 14,
                      ),
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 6,
                      ),
                    ),
                    child: Slider(
                      padding: EdgeInsets.zero,
                      value: safe,
                      max: total <= 0 ? 1 : total,
                      onChanged: total <= 0
                          ? null
                          : (double value) =>
                                setState(() => _dragPositionMs = value),
                      onChangeEnd: (double value) async {
                        await _session.seekTo(
                          Duration(milliseconds: value.round()),
                        );
                        if (mounted) setState(() => _dragPositionMs = null);
                      },
                    ),
                  ),
                ),
                SizedBox(
                  width: 48,
                  child: Text(
                    formatDuration(duration.inMilliseconds),
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 11,
                      fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildControlRow(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: _session.playing,
      builder: (BuildContext context, bool playing, _) {
        return ValueListenableBuilder<double>(
          valueListenable: _session.speed,
          builder: (BuildContext context, double speed, _) {
            return _PlayerControlBar(
              playing: playing,
              speedLabel: '${_formatSpeed(speed)}x',
              landscape: _landscape,
              hasPrevious: _session.queue.hasPrevious,
              hasNext: _session.queue.hasNext,
              onPrevious: () => _session.previous(),
              onTogglePlay: _togglePlay,
              onNext: () => _session.next(),
              onSpeed: _showSpeedSheet,
              onOrientation: _toggleOrientation,
            );
          },
        );
      },
    );
  }

  Widget _buildQueuePreview(BuildContext context) {
    final Map<String, MediaItem> media = ref
        .read(libraryControllerProvider)
        .mediaById;
    final List<String> order = _session.queue.order;
    if (order.isEmpty) return const SizedBox.shrink();
    final int count = order.length < 3 ? order.length : 3;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 4),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.32),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                '播放队列（${order.length}）',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => _openPanel(_PlayerPanel.queue),
                child: const Text(
                  '全部',
                  style: TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (int i = 0; i < count; i++)
            Builder(
              builder: (BuildContext context) {
                final MediaItem? item = media[order[i]];
                if (item == null) return const SizedBox.shrink();
                final bool active = i == _session.queue.index;
                return InkWell(
                  onTap: () => _session.jumpTo(i),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: <Widget>[
                        Icon(
                          active
                              ? Icons.equalizer_rounded
                              : Icons.play_arrow_rounded,
                          size: 14,
                          color: active ? AppColors.primary : Colors.white54,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            item.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: active
                                  ? AppColors.primary
                                  : Colors.white70,
                              fontSize: 11.5,
                            ),
                          ),
                        ),
                        Text(
                          formatDuration(item.durationMs),
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

// ===== 控制层与面板用到的小组件 =====
/// 播放控制栏：上一集 / 播放暂停 / 下一集，右侧为倍速与横竖屏，全部小图标横向排列。
class _PlayerControlBar extends StatelessWidget {
  const _PlayerControlBar({
    required this.playing,
    required this.speedLabel,
    required this.landscape,
    required this.hasPrevious,
    required this.hasNext,
    required this.onPrevious,
    required this.onTogglePlay,
    required this.onNext,
    required this.onSpeed,
    required this.onOrientation,
  });

  final bool playing;
  final String speedLabel;
  final bool landscape;
  final bool hasPrevious;
  final bool hasNext;
  final VoidCallback onPrevious;
  final VoidCallback onTogglePlay;
  final VoidCallback onNext;
  final VoidCallback onSpeed;
  final VoidCallback onOrientation;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          _ControlIcon(
            icon: Icons.skip_previous_rounded,
            size: 24,
            enabled: hasPrevious,
            onTap: onPrevious,
          ),
          _ControlIcon(
            icon: playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
            size: 24,
            enabled: true,
            onTap: onTogglePlay,
          ),
          _ControlIcon(
            icon: Icons.skip_next_rounded,
            size: 24,
            enabled: hasNext,
            onTap: onNext,
          ),
          const Spacer(),
          _SpeedBadge(label: speedLabel, onTap: onSpeed),
          const SizedBox(width: 4),
          _ControlIcon(
            icon: landscape
                ? Icons.screen_lock_rotation_rounded
                : Icons.screen_rotation_rounded,
            size: 20,
            enabled: true,
            onTap: onOrientation,
          ),
        ],
      ),
    );
  }
}

/// 速度刻度条上的一档：选中时主色加粗并在左侧显示指示三角。
class _SpeedScaleItem extends StatelessWidget {
  const _SpeedScaleItem({required this.label, required this.active});

  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 22,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: <Widget>[
          AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            style: TextStyle(
              fontSize: active ? 14.5 : 12.5,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              color: active ? AppColors.primary : Colors.white60,
            ),
            child: Text(label),
          ),
          if (active)
            const Positioned(
              left: 0,
              child: Icon(
                Icons.play_arrow_rounded,
                size: 11,
                color: AppColors.primary,
              ),
            ),
        ],
      ),
    );
  }
}

/// 播放器左侧浮层的圆形小按钮。
class _SideIconButton extends StatelessWidget {
  const _SideIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.38),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
          ),
          child: Icon(icon, size: 20, color: Colors.white),
        ),
      ),
    );
  }
}

/// 控制栏小图标按钮：未启用时降低透明度。
class _ControlIcon extends StatelessWidget {
  const _ControlIcon({
    required this.icon,
    required this.size,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final double size;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Icon(
          icon,
          size: size,
          color: Colors.white.withValues(alpha: enabled ? 1 : 0.26),
        ),
      ),
    );
  }
}

/// 倍速小胶囊：图标 + 当前倍速，与左侧图标上下居中。
class _SpeedBadge extends StatelessWidget {
  const _SpeedBadge({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.speed_rounded, size: 20, color: Colors.white70),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.error_outline_rounded,
              color: Colors.white54,
              size: 40,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 13,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 18),
            OutlinedButton(
              onPressed: onRetry,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white24),
              ),
              child: const Text('重新加载'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 空引擎：视频记录缺失时占位，避免空指针。
class _FailedEngine implements VideoPlaybackEngine {
  final StreamController<Duration> _empty =
      StreamController<Duration>.broadcast();

  @override
  Future<void> open(
    String source, {
    Duration startAt = Duration.zero,
    bool autoPlay = true,
  }) async {}

  @override
  Future<void> play() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> setSpeed(double speed) async {}

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> dispose() async => _empty.close();

  @override
  Stream<Duration> get positionStream => _empty.stream;

  @override
  Stream<Duration> get durationStream => _empty.stream;

  @override
  Stream<bool> get playingStream => const Stream<bool>.empty();

  @override
  Stream<bool> get bufferingStream => const Stream<bool>.empty();

  @override
  Stream<bool> get completedStream => const Stream<bool>.empty();

  @override
  Stream<String> get errorStream => const Stream<String>.empty();

  @override
  Duration get position => Duration.zero;

  @override
  Duration get duration => Duration.zero;

  @override
  bool get isPlaying => false;

  @override
  double get speed => 1;
}

/// 右侧设置面板的小节：灰色标题 + 横向排列的选项。
class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          title,
          style: const TextStyle(color: Colors.white38, fontSize: 11.5),
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 14, runSpacing: 4, children: children),
      ],
    );
  }
}

/// 右侧设置面板的单个选项：纯文字，选中态用主色。
class _SettingsOption extends StatelessWidget {
  const _SettingsOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 2),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? AppColors.primary : Colors.white70,
            fontSize: 13.5,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

/// 播放器内嵌面板类型。
enum _PlayerPanel { speed, more, queue }
