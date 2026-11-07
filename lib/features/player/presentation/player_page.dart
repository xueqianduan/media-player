import 'dart:async';

import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter/services.dart';
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 拖动调节音量时不要弹出系统音量面板。
    VolumeController.instance.showSystemUI = false;
    VolumeController.instance.addListener(_onSystemVolumeChanged);
    unawaited(_loadSystemLevels());
    final LibraryState library = ref.read(libraryControllerProvider);
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
      resolveSource: (MediaItem item) =>
          ref.read(mediaResolverProvider).resolve(item),
      onSaveProgress:
          ({
            required String mediaId,
            required int positionMs,
            required int durationMs,
            required bool completed,
          }) {
            ref
                .read(libraryControllerProvider.notifier)
                .saveProgress(
                  mediaId: mediaId,
                  positionMs: positionMs,
                  durationMs: durationMs,
                  completed: completed,
                );
          },
      initialSpeed: ref.read(settingsControllerProvider).defaultSpeed,
    );
    // 首帧即绑定当前视频，避免在 post-frame 打开前渲染错误页。
    _session.currentMediaId.value = first.id;
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
    Duration startAt = Duration.zero;
    if (record != null && record.shouldResume && prompt) {
      final bool? resume = await showDialog<bool>(
        context: context,
        builder: (BuildContext dialogContext) => AlertDialog(
          title: const Text(
            '继续观看？',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          content: Text(
            '上次看到 ${formatDuration(record.positionMs)} / ${formatDuration(record.durationMs)}，是否从上次位置继续？',
            style: const TextStyle(fontSize: 13.5, height: 1.6),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('从头播放'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text(
                '继续观看',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (resume == true) {
        startAt = Duration(milliseconds: record.positionMs);
      }
    }
    await _session.start(startAt: startAt);
    if (!mounted) return;
    _scheduleHide();
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
    _session.dispose();
    super.dispose();
  }

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

  Future<void> _onDoubleTap(TapDownDetails details) async {
    final double width = MediaQuery.sizeOf(context).width;
    final double x = details.localPosition.dx;
    if (x < width * 0.36) {
      await _seekBy(const Duration(seconds: -10));
    } else if (x > width * 0.64) {
      await _seekBy(const Duration(seconds: 10));
    } else {
      await _togglePlay();
    }
  }

  void _onVerticalStart(DragStartDetails details) {
    final double width = MediaQuery.sizeOf(context).width;
    _dragStartFraction = details.localPosition.dx / width;
    _dragStartBrightness = _brightness;
    _dragStartVolume = _volume;
  }

  double _dragStartFraction = 0.5;
  double _dragStartBrightness = 1;
  double _dragStartVolume = 1;

  void _onVerticalUpdate(DragUpdateDetails details) {
    final double delta = -details.primaryDelta! / 220;
    if (_dragStartFraction < 0.4) {
      final double value = (_dragStartBrightness + delta).clamp(0.05, 1.0);
      setState(() => _brightness = value);
      // 直接修改当前窗口亮度（不申请系统设置权限，退出播放器后恢复）。
      ScreenBrightness.instance
          .setApplicationScreenBrightness(value)
          .catchError((Object _) {});
      _showHint('亮度 ${(value * 100).round()}%');
    } else {
      final double value = (_dragStartVolume + delta).clamp(0.0, 1.0);
      setState(() => _volume = value);
      // 调节系统媒体音量，而不是只调播放器内部音量。
      VolumeController.instance.setVolume(value).catchError((Object _) {});
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
    _boosted = true;
    await _session.setSpeed(_boostStart);
    if (mounted) {
      _showHint('${_formatSpeed(_boostStart)}x · 左右滑动调速');
    }
  }

  /// 长按后左右滑动：以 0.25x 为步进，在 0.5x ~ 5x 之间调整。
  Future<void> _onBoostMove(LongPressMoveUpdateDetails details) async {
    if (!_boosted) return;
    final double dx = details.localOffsetFromOrigin.dx;
    double speed = (_boostStart + dx / 70 * 0.25).clamp(0.5, 5.0);
    speed = (speed * 4).roundToDouble() / 4;
    if ((speed - _lastBoost).abs() < 0.001) return;
    _lastBoost = speed;
    await _session.setSpeed(speed);
    if (mounted) _showHint('${_formatSpeed(speed)}x');
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

  Widget _buildPanelHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 6, 4),
      child: Row(
        children: <Widget>[
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          IconButton(
            onPressed: _closePanel,
            icon: const Icon(
              Icons.close_rounded,
              color: Colors.white54,
              size: 20,
            ),
          ),
        ],
      ),
    );
  }

  /// 播放器内嵌面板：不依赖系统弹窗，避免部分机型上弹层不显示。
  Widget _buildPanelOverlay() {
    final double maxHeight = MediaQuery.sizeOf(context).height * 0.78;
    return Stack(
      children: <Widget>[
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _closePanel,
            child: ColoredBox(color: Colors.black.withValues(alpha: 0.55)),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                color: Color(0xFF16181F),
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: SafeArea(
                top: false,
                child: SingleChildScrollView(
                  child: _panel == _PlayerPanel.speed
                      ? _buildSpeedPanel()
                      : _buildMorePanel(),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSpeedPanel() {
    final double current = _session.speed.value;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _buildPanelHeader('播放速度'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: AppSettings.speedOptions.map((double value) {
                final bool selected = (current - value).abs() < 0.01;
                return SizedBox(
                  width: 68,
                  height: 42,
                  child: OutlinedButton(
                    onPressed: () {
                      _session.setSpeed(value);
                      _closePanel();
                      _showHint('${_formatSpeed(value)}x 倍速');
                    },
                    style: OutlinedButton.styleFrom(
                      padding: EdgeInsets.zero,
                      backgroundColor: selected
                          ? AppColors.primary
                          : const Color(0xFF23262F),
                      foregroundColor: selected ? Colors.white : Colors.white70,
                      side: BorderSide(
                        color: selected
                            ? AppColors.primary
                            : const Color(0xFF333743),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: Text(
                      '${value}x',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                  ),
                );
              }).toList(),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _buildPanelHeader('播放设置'),
        const _SheetSectionTitle('播放方式'),
        ValueListenableBuilder<RepeatMode>(
          valueListenable: _session.repeatMode,
          builder: (BuildContext context, RepeatMode mode, _) {
            return Column(
              children: <Widget>[
                for (final RepeatMode option in RepeatMode.playbackModes)
                  _SheetOption(
                    icon: switch (option) {
                      RepeatMode.loopAll => Icons.repeat_rounded,
                      RepeatMode.loopOne => Icons.repeat_one_rounded,
                      _ => Icons.trending_flat_rounded,
                    },
                    title: option.label,
                    subtitle: switch (option) {
                      RepeatMode.loopAll => '播完自动下一个，最后一个回到第一个',
                      RepeatMode.loopOne => '当前视频播完从头重播',
                      _ => '播完当前视频后自动停止',
                    },
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
        const Divider(color: Color(0xFF2A2E3A), height: 20),
        const _SheetSectionTitle('画面尺寸'),
        for (final VideoScaleMode option in VideoScaleMode.values)
          _SheetOption(
            icon: switch (option) {
              VideoScaleMode.original => Icons.crop_free_rounded,
              VideoScaleMode.fit => Icons.fit_screen_rounded,
              VideoScaleMode.cover => Icons.crop_rounded,
              VideoScaleMode.stretch => Icons.open_in_full_rounded,
            },
            title: option.label,
            subtitle: switch (option) {
              VideoScaleMode.original => '按视频原始尺寸显示，不放大',
              VideoScaleMode.fit => '保持比例完整显示，可能有黑边',
              VideoScaleMode.cover => '保持比例铺满屏幕，可能裁剪边缘',
              VideoScaleMode.stretch => '拉伸填满屏幕，画面比例会变形',
            },
            selected: option == scaleMode,
            onTap: () {
              ref
                  .read(settingsControllerProvider.notifier)
                  .setVideoScaleMode(option);
              _showHint(option.label);
            },
          ),
        const Divider(color: Color(0xFF2A2E3A), height: 20),
        _SheetOption(
          icon: Icons.tune_rounded,
          title: '视频操作',
          subtitle: '收藏、分类、重命名、详情等',
          selected: false,
          onTap: () {
            _closePanel();
            final MediaItem? item = _session.currentItem;
            if (item != null) showVideoActionSheet(context, ref, item);
          },
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
          child: Text(
            'ReelBox 1.0.0 · build 2026-11-07',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.28),
              fontSize: 10,
            ),
          ),
        ),
      ],
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

  Future<void> _showQueueSheet() async {
    final List<String> order = _session.queue.order;
    final Map<String, MediaItem> media = ref
        .read(libraryControllerProvider)
        .mediaById;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF16181F),
      isScrollControlled: true,
      builder: (BuildContext sheetContext) {
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.6,
            child: Column(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 12, 10),
                  child: Row(
                    children: <Widget>[
                      Text(
                        '播放队列（${order.length}）',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: () => Navigator.of(sheetContext).pop(),
                        icon: const Icon(
                          Icons.close_rounded,
                          color: Colors.white70,
                          size: 20,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: order.length,
                    itemBuilder: (BuildContext context, int index) {
                      final MediaItem? item = media[order[index]];
                      if (item == null) return const SizedBox.shrink();
                      final bool active = index == _session.queue.index;
                      return ListTile(
                        onTap: () {
                          _session.jumpTo(index);
                          Navigator.of(sheetContext).pop();
                        },
                        leading: Icon(
                          active
                              ? Icons.equalizer_rounded
                              : Icons.play_arrow_rounded,
                          color: active ? AppColors.primary : Colors.white38,
                          size: 20,
                        ),
                        title: Text(
                          item.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: active ? AppColors.primary : Colors.white,
                            fontSize: 13.5,
                          ),
                        ),
                        subtitle: Text(
                          formatDuration(item.durationMs),
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 11,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
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
      body: Stack(
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
              return VideoSurface(
                engine: _session.engine,
                fit: _fitFor(scaleMode),
              );
            },
          ),
          // 手势层放在控制层下方：按钮不再被父级 GestureDetector 抢走点击。
          Positioned.fill(child: _buildGestureLayer()),
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
                    style: const TextStyle(color: Colors.white, fontSize: 12.5),
                  ),
                ),
              ),
            ),
          Positioned.fill(
            child: IgnorePointer(
              ignoring: !_controlsVisible,
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
          if (_panel != null) Positioned.fill(child: _buildPanelOverlay()),
        ],
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
      onVerticalDragStart: gesturesEnabled ? _onVerticalStart : null,
      onVerticalDragUpdate: gesturesEnabled ? _onVerticalUpdate : null,
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
            return Column(
              children: <Widget>[
                SliderTheme(
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
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Row(
                    children: <Widget>[
                      Text(
                        formatDuration(safe.round()),
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        formatDuration(duration.inMilliseconds),
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 11,
                        ),
                      ),
                    ],
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
    // 单个视频没有队列，隐藏队列与上一集/下一集，只保留播放与倍速。
    final bool hasQueue = _session.queue.length > 1;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Row(
        children: <Widget>[
          if (hasQueue)
            _PlayerSideButton(
              icon: Icons.queue_music_rounded,
              label: '队列',
              onTap: _showQueueSheet,
            )
          else
            const SizedBox(width: 48),
          const Spacer(),
          if (hasQueue)
            IconButton(
              onPressed: () => _session.previous(),
              icon: const Icon(
                Icons.skip_previous_rounded,
                color: Colors.white,
                size: 28,
              ),
            ),
          const SizedBox(width: 4),
          ValueListenableBuilder<bool>(
            valueListenable: _session.playing,
            builder: (BuildContext context, bool playing, _) {
              return GestureDetector(
                onTap: _togglePlay,
                child: Container(
                  width: 58,
                  height: 58,
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 34,
                  ),
                ),
              );
            },
          ),
          const SizedBox(width: 4),
          if (hasQueue)
            IconButton(
              onPressed: () => _session.next(),
              icon: const Icon(
                Icons.skip_next_rounded,
                color: Colors.white,
                size: 28,
              ),
            ),
          const Spacer(),
          ValueListenableBuilder<double>(
            valueListenable: _session.speed,
            builder: (BuildContext context, double speed, _) {
              return _PlayerSideButton(
                icon: Icons.speed_rounded,
                label: '${speed}x',
                onTap: _showSpeedSheet,
              );
            },
          ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: _landscape ? '切换竖屏' : '切换横屏',
            onPressed: _toggleOrientation,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 38, height: 38),
            icon: Icon(
              _landscape
                  ? Icons.screen_lock_rotation_rounded
                  : Icons.screen_rotation_rounded,
              color: Colors.white,
              size: 21,
            ),
          ),
        ],
      ),
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
                onTap: _showQueueSheet,
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

class _PlayerSideButton extends StatelessWidget {
  const _PlayerSideButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          constraints: const BoxConstraints(minWidth: 48, minHeight: 46),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(icon, color: Colors.white, size: 21),
              const SizedBox(height: 3),
              Text(
                label,
                style: const TextStyle(color: Colors.white70, fontSize: 10),
              ),
            ],
          ),
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

/// 播放设置面板的小节标题。
class _SheetSectionTitle extends StatelessWidget {
  const _SheetSectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.white54,
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// 播放设置面板的选项行。
class _SheetOption extends StatelessWidget {
  const _SheetOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Row(
          children: <Widget>[
            Icon(
              icon,
              size: 20,
              color: selected ? AppColors.primary : Colors.white54,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    title,
                    style: TextStyle(
                      color: selected ? AppColors.primary : Colors.white,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                ],
              ),
            ),
            if (selected)
              const Icon(
                Icons.check_rounded,
                size: 18,
                color: AppColors.primary,
              ),
          ],
        ),
      ),
    );
  }
}

/// 播放器内嵌面板类型。
enum _PlayerPanel { speed, more }
