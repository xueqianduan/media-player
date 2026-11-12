// -------------------------------------------------------------------------
// 功能：双路直播控制台（播放页）
//
// 主要内容：
// - 顶部双源头像（画面源 / 声音源）与房间信息
// - 画面区、点击呼出控制层、横屏全屏观看
// - 弹幕区占位与弹幕输入栏（连接能力后续接入）
// - 声音切换、暂停、同步调节、画质切换
// -------------------------------------------------------------------------

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:volume_controller/volume_controller.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/ui_kit.dart';
import '../application/bili_account_controller.dart';
import '../application/network_controller.dart';
import '../data/dual_live_session.dart';
import '../domain/live_models.dart';

/// 播放双路直播所需的选择。
class LivePlayArgs {
  const LivePlayArgs({
    required this.picture,
    this.voice,
    this.danmaku = DanmakuSource.off,
  });

  final LiveRoom picture;
  final LiveRoom? voice;
  final DanmakuSource danmaku;
}

/// 双路直播播放页：画面源看比赛，声音源听解说，可切换声音与手动同步。
class LivePlayerPage extends ConsumerStatefulWidget {
  const LivePlayerPage({super.key, required this.args});

  final LivePlayArgs args;

  @override
  ConsumerState<LivePlayerPage> createState() => _LivePlayerPageState();
}

class _LivePlayerPageState extends ConsumerState<LivePlayerPage> {
  DualLiveSession? _session;
  VideoController? _controller;
  String _status = '正在准备…';
  bool _starting = true;
  bool _paused = false;
  bool _usingVoice = false;
  String? _error;
  String? _voiceWarning;
  int _qn = 250;

  /// 是否处于横屏全屏观看。
  bool _landscape = false;

  /// 画面上的控制层是否可见。
  bool _controlsVisible = true;

  /// 是否正在刷新画面源。
  bool _refreshing = false;

  /// 画质面板是否从右侧展开。
  bool _qualityOpen = false;

  // ===== 亮度 / 音量手势状态（与本地播放器一致） =====
  double _brightness = 1;
  double _volume = 1;
  double _dragStartFraction = 0.5;
  double _dragStartBrightness = 1;
  double _dragStartVolume = 1;
  double _dragAccum = 0;
  double _dragRangePx = 220;
  String? _gestureHint;
  Timer? _hintTimer;
  Timer? _hideTimer;

  @override
  // ===== 生命周期与启动 =====
  void initState() {
    super.initState();
    // 拖动调音量时不要弹出系统音量面板。
    VolumeController.instance.showSystemUI = false;
    VolumeController.instance.addListener(_onSystemVolumeChanged);
    unawaited(_loadSystemLevels());
    if (kDebugMode) {
      SchedulerBinding.instance.addTimingsCallback(_onFrameTimings);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    final Stopwatch startup = Stopwatch()..start();
    final DualLiveSession? previous = _session;
    if (previous != null) {
      previous.status.removeListener(_onStatus);
      previous.usingVoice.removeListener(_onSoundChanged);
      previous.paused.removeListener(_onPausedChanged);
      previous.currentQn.removeListener(_onQnChanged);
      await previous.close();
    }

    if (!mounted) return;
    setState(() {
      _session = null;
      _controller = null;
      _starting = true;
      _error = null;
      _voiceWarning = null;
      _qn = 250;
      _status = '正在连接画面源…';
    });

    final DualLiveSession session = DualLiveSession(
      api: ref.read(biliLiveApiProvider),
      cookie: ref.read(biliSessionProvider).cookieHeader,
      onVideo: (VideoController? controller) {
        if (mounted) setState(() => _controller = controller);
      },
    );
    session.status.addListener(_onStatus);
    session.usingVoice.addListener(_onSoundChanged);
    session.paused.addListener(_onPausedChanged);
    session.currentQn.addListener(_onQnChanged);
    setState(() => _session = session);

    try {
      await session.start(
        pictureRoom: widget.args.picture,
        voiceRoom: widget.args.voice,
      );
      if (!mounted) return;
      setState(() {
        _status = session.status.value;
        if (session.voiceFailure != null && widget.args.voice != null) {
          _voiceWarning = '声音源未开播，已切到赛事原声';
        }
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _error = '$error');
    } finally {
      if (mounted) {
        setState(() => _starting = false);
        // 播放就绪后才开始自动隐藏控制层；加载中保持可见。
        _scheduleHide();
        debugPrint(
          '[LumiPlayer] live console ready in ${startup.elapsedMilliseconds}ms',
        );
      }
    }
  }

  /// 只记录明显掉帧的帧（构建 + 光栅 ≥ 80ms），用于定位横竖屏切换卡顿。
  void _onFrameTimings(List<FrameTiming> timings) {
    for (final FrameTiming timing in timings) {
      final int build = timing.buildDuration.inMilliseconds;
      final int raster = timing.rasterDuration.inMilliseconds;
      if (build + raster >= 80) {
        debugPrint(
          '[LumiPlayer] jank frame build=${build}ms raster=${raster}ms',
        );
      }
    }
  }

  void _onStatus() {
    if (!mounted) return;
    setState(() => _status = _session?.status.value ?? '');
  }

  void _onSoundChanged() {
    if (!mounted) return;
    setState(() => _usingVoice = _session?.usingVoice.value ?? false);
  }

  void _onPausedChanged() {
    if (!mounted) return;
    setState(() => _paused = _session?.paused.value ?? false);
  }

  void _onQnChanged() {
    if (!mounted) return;
    setState(() => _qn = _session?.currentQn.value ?? _qn);
  }

  // ===== 亮度 / 音量手势（与本地播放器一致） =====
  void _onSystemVolumeChanged(double volume) {
    if (!mounted) return;
    setState(() => _volume = volume.clamp(0.0, 1.0));
  }

  Future<void> _loadSystemLevels() async {
    try {
      final double app = await ScreenBrightness.instance.application;
      final double system = app >= 0
          ? app
          : await ScreenBrightness.instance.system;
      if (mounted) setState(() => _brightness = system.clamp(0.0, 1.0));
    } on Object {
      // 平台不支持时保持默认值。
    }
    try {
      final double volume = await VolumeController.instance.getVolume();
      if (mounted) setState(() => _volume = volume.clamp(0.0, 1.0));
    } on Object {
      // 同上。
    }
  }

  void _showHint(String text) {
    _hintTimer?.cancel();
    setState(() => _gestureHint = text);
    _hintTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _gestureHint = null);
    });
  }

  void _onVerticalStart(DragStartDetails details) {
    final Size size = MediaQuery.sizeOf(context);
    _dragStartFraction = details.localPosition.dx / size.width;
    _dragStartBrightness = _brightness;
    _dragStartVolume = _volume;
    // 累计滑动量：整段手势一直叠加，而不是只看最后一帧。
    _dragAccum = 0;
    // 竖直滑动屏幕高度的 70% 即为 0 → 100%，和本地播放器保持一致。
    _dragRangePx = size.height * 0.7;
  }

  void _onVerticalUpdate(DragUpdateDetails details) {
    final double? delta = details.primaryDelta;
    if (delta == null) return;
    _dragAccum += -delta / _dragRangePx;
    if (_dragStartFraction < 0.4) {
      final double value = (_dragStartBrightness + _dragAccum).clamp(0.05, 1.0);
      setState(() => _brightness = value);
      // 调的是当前窗口亮度，退出页面时恢复，不需要系统设置权限。
      ScreenBrightness.instance
          .setApplicationScreenBrightness(value)
          .catchError((Object error) => debugPrint('调节亮度失败：$error'));
      _showHint('亮度 ${(value * 100).round()}%');
    } else {
      final double value = (_dragStartVolume + _dragAccum).clamp(0.0, 1.0);
      setState(() => _volume = value);
      // 调系统媒体音量，画面与解说两路一起吃这个音量。
      VolumeController.instance
          .setVolume(value)
          .catchError((Object error) => debugPrint('调节音量失败：$error'));
      _showHint('音量 ${(value * 100).round()}%');
    }
  }

  Widget _buildGestureHint() {
    final String? hint = _gestureHint;
    if (hint == null) return const SizedBox.shrink();
    return IgnorePointer(
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(
            color: AppColors.playerScrim,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            hint,
            style: const TextStyle(color: Colors.white, fontSize: 12.5),
          ),
        ),
      ),
    );
  }

  // ===== 控制层显隐与横屏 =====
  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) {
      _scheduleHide();
    } else {
      _hideTimer?.cancel();
    }
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    // 加载中、出错、暂停时都保持控制层可见，避免用户没得点。
    if (_paused || _starting || _error != null) return;
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _controlsVisible) {
        setState(() => _controlsVisible = false);
      }
    });
  }

  Future<void> _toggleOrientation() async {
    final Stopwatch watch = Stopwatch()..start();
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
    if (!mounted) return;
    setState(() => _controlsVisible = true);
    _scheduleHide();
    debugPrint(
      '[LumiPlayer] orientation -> ${_landscape ? 'landscape' : 'portrait'} '
      'platform calls ${watch.elapsedMilliseconds}ms',
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      debugPrint(
        '[LumiPlayer] orientation first frame in '
        '${watch.elapsedMilliseconds}ms',
      );
    });
  }

  // ===== 播放控制：暂停 / 声音 / 同步 =====
  Future<void> _togglePause() async {
    final DualLiveSession? session = _session;
    if (session == null) return;
    try {
      await session.setPaused(!_paused);
    } on Object catch (error) {
      if (mounted) showToast(context, '$error');
    }
    if (!mounted) return;
    // 暂停时把控制层留在画面上，方便再次点播放。
    setState(() => _controlsVisible = true);
    _scheduleHide();
  }

  Future<void> _switchSound({required bool official}) async {
    final DualLiveSession? session = _session;
    if (session == null) return;
    try {
      if (official) {
        await session.useOfficialSound();
      } else {
        await session.useCommentatorSound();
      }
    } on Object catch (error) {
      if (mounted) showToast(context, '$error');
    }
  }

  // ===== 画质面板：从右侧滑出，样式与本地播放器的倍速面板一致 =====
  void _openQualityPanel() {
    final DualLiveSession? session = _session;
    if (session == null) return;
    if (session.qualities.value.isEmpty) {
      showToast(context, '这个直播间暂时没有可选画质');
      return;
    }
    _hideTimer?.cancel();
    setState(() {
      _qualityOpen = true;
      _controlsVisible = true;
    });
  }

  void _closeQualityPanel() {
    if (!_qualityOpen) return;
    setState(() => _qualityOpen = false);
    _scheduleHide();
  }

  /// 面板铺满屏幕右侧：点左侧空白关闭，右侧一列档位。
  Widget _buildQualityPanelOverlay() {
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
            onTap: _closeQualityPanel,
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
                  child: SingleChildScrollView(child: _buildQualityPanel()),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 画质档位：右侧竖向排列，每档一个整行矩形，文字横纵居中。
  Widget _buildQualityPanel() {
    final DualLiveSession? session = _session;
    final List<LiveQuality> options =
        session?.qualities.value ?? const <LiveQuality>[];
    final int current = session?.currentQn.value ?? _qn;
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
              onTap: () {
                _closeQualityPanel();
                _switchQuality(option.qn);
              },
              child: Container(
                height: rowHeight,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: option.qn == current
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
                    color: option.qn == current ? Colors.white : Colors.white70,
                    fontSize: compact ? 15 : 18.5,
                    fontWeight: option.qn == current
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

  Future<void> _switchQuality(int qn) async {
    final DualLiveSession? session = _session;
    if (session == null) return;
    setState(() => _status = '正在切换画质…');
    try {
      await session.switchQuality(qn);
    } on Object catch (error) {
      if (mounted) showToast(context, '$error');
    }
  }

  Future<void> _showSyncSheet() async {
    final DualLiveSession? session = _session;
    if (session == null) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF16181F),
      builder: (BuildContext sheetContext) {
        return _SyncSheet(
          session: session,
          onRestart: () {
            Navigator.of(sheetContext).pop();
            _start();
          },
        );
      },
    );
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _hintTimer?.cancel();
    if (kDebugMode) {
      SchedulerBinding.instance.removeTimingsCallback(_onFrameTimings);
    }
    VolumeController.instance.removeListener().catchError((Object _) {});
    try {
      ScreenBrightness.instance.resetApplicationScreenBrightness().catchError(
        (Object error) => debugPrint('恢复亮度失败：$error'),
      );
    } on Object {
      // 平台不支持时忽略。
    }
    // 离开页面时恢复竖屏与系统栏，避免其它页面被横屏状态带偏。
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(const <DeviceOrientation>[
      DeviceOrientation.portraitUp,
    ]);
    final DualLiveSession? session = _session;
    if (session != null) {
      session.status.removeListener(_onStatus);
      session.usingVoice.removeListener(_onSoundChanged);
      session.paused.removeListener(_onPausedChanged);
      session.currentQn.removeListener(_onQnChanged);
      session.close();
    }
    super.dispose();
  }

  @override
  // ===== 页面骨架 =====
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_landscape && !_qualityOpen,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop) return;
        // 面板打开时返回键先收起面板；横屏时先退出全屏，都不是直接离开播放页。
        if (_qualityOpen) {
          _closeQualityPanel();
          return;
        }
        _toggleOrientation();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0B0D14),
        body: Stack(
          children: <Widget>[
            _landscape
                ? _buildLandscape(context)
                : SafeArea(child: _buildPortrait(context)),
            if (_qualityOpen)
              Positioned.fill(child: _buildQualityPanelOverlay()),
          ],
        ),
      ),
    );
  }

  // ===== 竖屏：头部 / 画面 / 播放按钮 / 弹幕 / 输入栏 =====
  Widget _buildPortrait(BuildContext context) {
    return Column(
      children: <Widget>[
        _buildHeader(context),
        _buildVideoStage(context),
        _buildPlaybackBar(context),
        Expanded(child: _buildDanmakuPanel(context)),
        _buildDanmakuInput(context),
      ],
    );
  }

  Widget _buildLandscape(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _toggleControls,
          onVerticalDragStart: _onVerticalStart,
          onVerticalDragUpdate: _onVerticalUpdate,
          child: ColoredBox(
            color: Colors.black,
            child: _buildVideo(BoxFit.contain),
          ),
        ),
        if (_controlsVisible) _buildOverlay(context),
        _buildGestureHint(),
      ],
    );
  }

  Widget _buildVideo(BoxFit fit) {
    final VideoController? controller = _controller;
    if (controller == null) return _buildPlaceholder();
    return Video(
      controller: controller,
      controls: NoVideoControls,
      fit: fit,
      wakelock: true,
    );
  }

  /// 画面区：固定 16:9，点一下呼出 / 收起控制层。
  Widget _buildVideoStage(BuildContext context) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggleControls,
        onVerticalDragStart: _onVerticalStart,
        onVerticalDragUpdate: _onVerticalUpdate,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            ColoredBox(color: Colors.black, child: _buildVideo(BoxFit.contain)),
            if (_controlsVisible) _buildOverlay(context),
            _buildGestureHint(),
          ],
        ),
      ),
    );
  }

  /// 画面控制层：左上原声 / 解说，左下同步（横屏时补上暂停与刷新），
  /// 右下画质与横屏。
  Widget _buildOverlay(BuildContext context) {
    final DualLiveSession? session = _session;
    final bool hasVoice = session?.hasVoice ?? false;
    final bool ready = session != null && _controller != null;
    final bool hasQuality =
        (session?.qualities.value ?? const <LiveQuality>[]).isNotEmpty;
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[
                  Colors.black.withValues(alpha: 0.42),
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.55),
                ],
                stops: const <double>[0, 0.45, 1],
              ),
            ),
          ),
        ),
        Positioned(
          left: 8,
          top: 8,
          child: Row(
            children: <Widget>[
              _SoundChip(
                label: '原声',
                selected: !_usingVoice,
                onTap: () => _switchSound(official: true),
              ),
              const SizedBox(width: 6),
              _SoundChip(
                label: '解说',
                selected: _usingVoice,
                enabled: hasVoice,
                onTap: () => _switchSound(official: false),
              ),
            ],
          ),
        ),
        Positioned(
          left: 8,
          bottom: 8,
          child: Row(
            children: <Widget>[
              if (_landscape) ...<Widget>[
                _OverlayIconButton(
                  icon: _paused
                      ? Icons.play_arrow_rounded
                      : Icons.pause_rounded,
                  onTap: ready ? _togglePause : null,
                  filled: true,
                ),
                const SizedBox(width: 6),
                _OverlayIconButton(
                  icon: Icons.refresh_rounded,
                  onTap: _refreshing ? null : _refreshPicture,
                  tooltip: '刷新画面源',
                ),
                const SizedBox(width: 6),
              ],
              _OverlayIconButton(
                icon: Icons.tune_rounded,
                onTap: hasVoice ? _showSyncSheet : null,
                tooltip: '同步',
              ),
            ],
          ),
        ),
        Positioned(
          right: 8,
          bottom: 8,
          child: Row(
            children: <Widget>[
              if (hasQuality) ...<Widget>[
                _QualityChip(
                  label: LiveQuality.labelOf(_qn),
                  onTap: _openQualityPanel,
                ),
                const SizedBox(width: 6),
              ],
              _OverlayIconButton(
                icon: _landscape
                    ? Icons.fullscreen_exit_rounded
                    : Icons.fullscreen_rounded,
                onTap: _toggleOrientation,
                tooltip: _landscape ? '退出横屏' : '横屏观看',
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 画面下方的常驻按钮：暂停 / 继续、刷新画面源（声音源不动）。
  Widget _buildPlaybackBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Row(
        children: <Widget>[
          Expanded(
            child: _ConsoleButton(
              icon: _paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
              label: _paused ? '继续' : '暂停',
              onTap: _togglePause,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _ConsoleButton(
              icon: Icons.refresh_rounded,
              label: _refreshing ? '刷新中…' : '刷新画面源',
              busy: _refreshing,
              onTap: _refreshPicture,
            ),
          ),
        ],
      ),
    );
  }

  /// 刷新画面源：只重连画面，声音源与解说选择保留。
  Future<void> _refreshPicture() async {
    final DualLiveSession? session = _session;
    if (session == null || _refreshing) return;
    setState(() => _refreshing = true);
    try {
      await session.refreshPicture();
      if (mounted) showToast(context, '画面源已刷新');
    } on Object catch (error) {
      if (mounted) showToast(context, '$error');
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Widget _buildPlaceholder() {
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (_error == null)
                const SizedBox(
                  width: 30,
                  height: 30,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: Colors.white70,
                  ),
                ),
              if (_error != null)
                const Icon(
                  Icons.wifi_off_rounded,
                  size: 40,
                  color: Colors.white38,
                ),
              const SizedBox(height: 16),
              Text(
                _error ?? _status,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  height: 1.6,
                ),
              ),
              if (_error != null) ...<Widget>[
                const SizedBox(height: 18),
                OutlinedButton(
                  onPressed: _start,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white30),
                  ),
                  child: const Text('重试'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 10, 8),
      child: Row(
        children: <Widget>[
          IconButton(
            onPressed: () => context.canPop() ? context.pop() : context.go('/'),
            icon: const Icon(
              Icons.arrow_back_ios_new_rounded,
              color: Colors.white,
              size: 19,
            ),
          ),
          _SourceAvatars(
            picture: widget.args.picture,
            voice: widget.args.voice,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  widget.args.picture.name,
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
                  _voiceWarning ?? _status,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ],
            ),
          ),
          if (_starting)
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

  /// 弹幕区：先占位，接入弹幕连接后在这里滚动消息。
  Widget _buildDanmakuPanel(BuildContext context) {
    final String source;
    switch (widget.args.danmaku) {
      case DanmakuSource.picture:
        source = '画面直播间';
      case DanmakuSource.voice:
        source = '声音直播间';
      case DanmakuSource.off:
        source = '未开启';
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      decoration: BoxDecoration(
        color: const Color(0xFF12151E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 11, 12, 8),
            child: Row(
              children: <Widget>[
                const Icon(
                  Icons.forum_rounded,
                  size: 14,
                  color: Colors.white54,
                ),
                const SizedBox(width: 6),
                const Text(
                  '弹幕',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$source · 待接入',
                    style: const TextStyle(color: Colors.white38, fontSize: 10),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      Icons.chat_bubble_outline_rounded,
                      size: 30,
                      color: Colors.white.withValues(alpha: 0.18),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      '弹幕区已就位',
                      style: TextStyle(color: Colors.white54, fontSize: 12.5),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      '接入弹幕连接后，这里会实时滚动画面源的弹幕',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white24,
                        fontSize: 11,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 底部弹幕输入栏：发送能力等弹幕连接接入后再开放。
  Widget _buildDanmakuInput(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Row(
        children: <Widget>[
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _showDanmakuComingSoon,
              child: Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                child: Row(
                  children: <Widget>[
                    const Text(
                      '发个弹幕…',
                      style: TextStyle(color: Colors.white30, fontSize: 12.5),
                    ),
                    const Spacer(),
                    Icon(
                      Icons.emoji_emotions_outlined,
                      size: 18,
                      color: Colors.white.withValues(alpha: 0.25),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _showDanmakuComingSoon,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.35),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.send_rounded,
                size: 18,
                color: Colors.white70,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showDanmakuComingSoon() {
    showToast(context, '发弹幕将在接入弹幕连接后开放');
  }
}

// ===== 面板与小组件 =====
/// 头部的双源头像：左画面、右声音；没有声音源时只显示画面。
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

/// 画面右上角的画质胶囊。
class _QualityChip extends StatelessWidget {
  const _QualityChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.high_quality_rounded,
              size: 12,
              color: Colors.white70,
            ),
            const SizedBox(width: 3),
            Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

/// 控制层上的方形图标按钮。
class _OverlayIconButton extends StatelessWidget {
  const _OverlayIconButton({
    required this.icon,
    required this.onTap,
    this.filled = false,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final bool filled;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final Widget button = GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: filled
              ? AppColors.primary
              : Colors.black.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(10),
          border: filled
              ? null
              : Border.all(color: Colors.white.withValues(alpha: 0.16)),
        ),
        child: Icon(icon, size: filled ? 20 : 18, color: Colors.white),
      ),
    );
    final String? message = tooltip;
    if (message == null) return button;
    return Tooltip(message: message, child: button);
  }
}

/// 同步面板：分别让画面 / 声音额外延迟 0.5 秒，或重新从零校准。
class _SyncSheet extends StatefulWidget {
  const _SyncSheet({required this.session, required this.onRestart});

  final DualLiveSession session;
  final VoidCallback onRestart;

  @override
  State<_SyncSheet> createState() => _SyncSheetState();
}

class _SyncSheetState extends State<_SyncSheet> {
  bool _busy = false;

  Future<void> _delay({required bool picture}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (picture) {
        await widget.session.delayPicture(const Duration(milliseconds: 500));
      } else {
        await widget.session.delayVoice(const Duration(milliseconds: 500));
      }
    } on Object catch (error) {
      if (mounted) showToast(context, '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final DualLiveSession session = widget.session;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Text(
                  '同步调节',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(
                    Icons.close_rounded,
                    color: Colors.white54,
                    size: 20,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              '画面延迟 ${(session.pictureDelay.inMilliseconds / 1000).toStringAsFixed(1)}s'
              ' · 声音延迟 ${(session.voiceDelay.inMilliseconds / 1000).toStringAsFixed(1)}s',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 16),
            _SyncAction(
              icon: Icons.ondemand_video_rounded,
              title: '画面慢 0.5 秒',
              subtitle: '声音比画面晚时使用',
              enabled: !_busy && session.hasVoice,
              onTap: () => _delay(picture: true),
            ),
            _SyncAction(
              icon: Icons.graphic_eq_rounded,
              title: '声音慢 0.5 秒',
              subtitle: '画面比声音晚时使用',
              enabled: !_busy && session.hasVoice,
              onTap: () => _delay(picture: false),
            ),
            _SyncAction(
              icon: Icons.restart_alt_rounded,
              title: '重新连接并从零校准',
              subtitle: '延迟会重置，需要重新建立两路连接',
              enabled: !_busy,
              onTap: widget.onRestart,
            ),
            const SizedBox(height: 6),
            const Text(
              '同步只在本次播放内有效，重连或切换直播间后会重置。',
              style: TextStyle(
                color: Colors.white30,
                fontSize: 11,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SyncAction extends StatelessWidget {
  const _SyncAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: <Widget>[
            Icon(
              icon,
              size: 20,
              color: enabled ? AppColors.primary : Colors.white24,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    title,
                    style: TextStyle(
                      color: enabled ? Colors.white : Colors.white38,
                      fontSize: 13.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(color: Colors.white30, fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 画面下方的常驻操作按钮（暂停 / 刷新画面源）。
class _ConsoleButton extends StatelessWidget {
  const _ConsoleButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.busy = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final bool enabled = onTap != null && !busy;
    return GestureDetector(
      onTap: enabled ? onTap : null,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 42,
        decoration: BoxDecoration(
          color: const Color(0xFF12151E),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            if (busy)
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 1.8,
                  color: Colors.white54,
                ),
              )
            else
              Icon(
                icon,
                size: 16,
                color: enabled ? Colors.white70 : Colors.white24,
              ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                color: enabled ? Colors.white : Colors.white38,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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
        : (selected ? AppColors.primary : Colors.white70);
    return GestureDetector(
      onTap: enabled ? onTap : null,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.18)
              : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? AppColors.primary.withValues(alpha: 0.55)
                : Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}
