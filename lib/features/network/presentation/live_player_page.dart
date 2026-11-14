// -------------------------------------------------------------------------
// 功能：双路直播控制台（播放页）
//
// 主要内容：
// - 顶部双源头像（画面源 / 声音源）与房间信息
// - 画面区、点击呼出控制层、横屏全屏观看
// - 实时弹幕（WebSocket 接收 / 发送）、横屏飘屏与弹幕设置
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
import '../../settings/application/settings_controller.dart';
import '../../settings/domain/app_settings.dart';
import '../application/bili_account_controller.dart';
import '../application/network_controller.dart';
import '../data/danmaku_client.dart';
import '../data/dual_live_session.dart';
import '../domain/danmaku_models.dart';
import '../domain/live_models.dart';
import 'bili_login_page.dart';
import 'widgets/live_control_overlay.dart';
import 'widgets/live_console_header.dart';
import 'widgets/live_danmaku_overlay.dart';
import 'widgets/live_danmaku_panel.dart';
import 'widgets/live_danmaku_settings_panel.dart';
import 'widgets/live_emoticon_panel.dart';
import 'widgets/live_portrait_control_bar.dart';
import 'widgets/live_quality_panel.dart';
import 'widgets/live_sync_panel.dart';

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

  /// 同步面板是否从右侧展开。
  bool _syncOpen = false;

  /// 弹幕设置面板是否从右侧展开。
  bool _danmakuSettingsOpen = false;

  // ===== 弹幕 =====
  DanmakuClient? _danmaku;
  final List<DanmakuMessage> _danmakuMessages = <DanmakuMessage>[];
  final List<DanmakuMessage> _danmakuBuffer = <DanmakuMessage>[];

  /// 横屏飘屏的实时消息源：只发给当前订阅者，转屏不重放历史。
  final StreamController<DanmakuMessage> _danmakuFeed =
      StreamController<DanmakuMessage>.broadcast();
  DanmakuStatus _danmakuStatus = DanmakuStatus.idle;
  String? _danmakuError;
  Timer? _danmakuFlush;
  bool _sendingDanmaku = false;

  /// 弹幕输入框：竖屏与横屏共用，转屏不丢草稿。
  final TextEditingController _danmakuText = TextEditingController();
  final FocusNode _danmakuFocus = FocusNode();

  /// 输入框是否正在输入：横屏时整行让给输入区。
  bool _composerFocused = false;

  // ===== 官方表情 =====
  bool _emojiOpen = false;
  List<LiveEmoticon> _emoticons = const <LiveEmoticon>[];
  bool _emojiLoading = false;
  String? _emojiError;

  /// 列表上限：只保留最近 200 条，避免长时间挂机后内存持续增长。
  static const int _danmakuLimit = 200;

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
    _danmakuFocus.addListener(_onComposerFocus);
    unawaited(_loadSystemLevels());
    if (kDebugMode) {
      SchedulerBinding.instance.addTimingsCallback(_onFrameTimings);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_start());
      unawaited(_startDanmaku());
    });
  }

  Future<void> _start() async {
    final Stopwatch startup = Stopwatch()..start();
    final DualLiveSession? previous = _session;
    if (previous != null) {
      previous.status.removeListener(_onStatus);
      previous.usingVoice.removeListener(_onSoundChanged);
      previous.paused.removeListener(_onPausedChanged);
      previous.currentQn.removeListener(_onQnChanged);
      // 先摘掉会话再关闭：close() 会释放进度通知器，
      // 页面上的 ValueListenableBuilder 必须先退订。
      if (mounted) setState(() => _session = null);
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

  // ===== 弹幕连接 =====
  /// 当前弹幕来源对应的房间；选了解说但解说源不可用时回落到画面房间。
  LiveRoom get _danmakuRoom {
    if (widget.args.danmaku == DanmakuSource.voice) {
      return widget.args.voice ?? widget.args.picture;
    }
    return widget.args.picture;
  }

  String get _danmakuRoomName {
    final LiveRoom room = _danmakuRoom;
    return room.name.isEmpty ? '房间 ${room.roomId}' : room.name;
  }

  /// 弹幕独立于播放启动：拿不到 buvid3 或连接失败都不影响画面。
  Future<void> _startDanmaku() async {
    if (widget.args.danmaku == DanmakuSource.off) {
      if (mounted) setState(() => _danmakuStatus = DanmakuStatus.idle);
      return;
    }

    final LiveRoom room = _danmakuRoom;
    final session = ref.read(biliSessionProvider);
    String buvid = session.buvid3 ?? '';
    if (buvid.isEmpty) {
      try {
        buvid = await session.ensureBuvid();
      } on Object catch (error) {
        debugPrint('[LumiPlayer] buvid3 获取失败：$error');
      }
    }
    if (!mounted) return;

    final DanmakuClient client = DanmakuClient(
      roomId: room.roomId,
      cookie: session.cookieHeader,
      buvid: buvid,
      uid: session.userId,
      onMessage: _onDanmakuMessage,
      onStatus: _onDanmakuStatus,
      onError: _onDanmakuError,
      onLog: debugPrint,
    );

    final DanmakuClient? previous = _danmaku;
    if (previous != null) unawaited(previous.close());
    setState(() {
      _danmaku = client;
      _danmakuMessages.clear();
      _danmakuStatus = DanmakuStatus.connecting;
      _danmakuError = null;
    });
    client.start();
  }

  void _onDanmakuMessage(DanmakuMessage message) {
    if (!mounted) return;
    // 横屏飘屏直接吃原始消息，不等 250ms 批量刷新。
    if (!_danmakuFeed.isClosed) _danmakuFeed.add(message);

    // 热门直播间每秒可能有几十条：先入缓冲，250ms 合并刷新一次，
    // 避免每条弹幕都 setState 重建整个播放页。
    _danmakuBuffer.add(message);
    if (_danmakuBuffer.length > _danmakuLimit) {
      _danmakuBuffer.removeRange(0, _danmakuBuffer.length - _danmakuLimit);
    }
    _danmakuFlush ??= Timer(const Duration(milliseconds: 250), _flushDanmaku);
  }

  void _flushDanmaku() {
    _danmakuFlush = null;
    if (!mounted || _danmakuBuffer.isEmpty) return;
    setState(() {
      _danmakuMessages.addAll(_danmakuBuffer);
      _danmakuBuffer.clear();
      final int extra = _danmakuMessages.length - _danmakuLimit;
      if (extra > 0) _danmakuMessages.removeRange(0, extra);
    });
  }

  void _onDanmakuStatus(DanmakuStatus status) {
    if (!mounted) return;
    setState(() {
      _danmakuStatus = status;
      if (status == DanmakuStatus.connected) _danmakuError = null;
    });
  }

  void _onDanmakuError(String message) {
    if (!mounted) return;
    setState(() => _danmakuError = message);
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
    final DualLiveSession? session = _session;
    setState(() {
      _status = session?.status.value ?? '';
      if (session?.voiceFailure != null) {
        _voiceWarning = '声音源不可用，继续使用赛事原声';
      }
    });
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
    // 正在输入弹幕时，点画面只是退出输入，控制台恢复原样。
    if (_composerFocused) {
      _danmakuFocus.unfocus();
      return;
    }
    setState(() {
      _controlsVisible = !_controlsVisible;
      if (!_controlsVisible) _emojiOpen = false;
    });
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
    // 正在输入弹幕或挑表情时不隐藏，避免输入框突然消失。
    if (_emojiOpen || _danmakuFocus.hasFocus) return;
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted || !_controlsVisible) return;
      if (_emojiOpen || _danmakuFocus.hasFocus) return;
      setState(() => _controlsVisible = false);
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
    setState(() {
      _controlsVisible = true;
      _danmakuSettingsOpen = false;
    });
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
    // 登录可能发生在播放中：开面板前带上最新 Cookie，高档位才能真的生效。
    session.updateCookie(ref.read(biliSessionProvider).cookieHeader);
    if (session.qualities.value.isEmpty) {
      showToast(context, '这个直播间暂时没有可选画质');
      return;
    }
    _hideTimer?.cancel();
    setState(() {
      _qualityOpen = true;
      _syncOpen = false;
      _danmakuSettingsOpen = false;
      _emojiOpen = false;
      _controlsVisible = true;
    });
  }

  void _closeQualityPanel() {
    if (!_qualityOpen) return;
    setState(() => _qualityOpen = false);
    _scheduleHide();
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

  /// 刷新画面源：只重连画面，声音源与解说选择保留。
  Future<void> _refreshPicture() async {
    final DualLiveSession? session = _session;
    if (session == null || _refreshing) return;
    setState(() => _refreshing = true);
    try {
      await session.refreshPicture();
    } on Object catch (error) {
      if (mounted) showToast(context, '$error');
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  void _openSyncPanel() {
    final DualLiveSession? session = _session;
    if (session == null) return;
    _hideTimer?.cancel();
    setState(() {
      _syncOpen = true;
      _qualityOpen = false;
      _danmakuSettingsOpen = false;
      _emojiOpen = false;
      _controlsVisible = true;
    });
  }

  void _closeSyncPanel() {
    if (!_syncOpen) return;
    setState(() => _syncOpen = false);
    _scheduleHide();
  }

  // ===== 弹幕设置 / 开关 / 发送 =====
  void _openDanmakuSettings() {
    _hideTimer?.cancel();
    setState(() {
      _danmakuSettingsOpen = true;
      _qualityOpen = false;
      _syncOpen = false;
      _emojiOpen = false;
      _controlsVisible = true;
    });
  }

  void _closeDanmakuSettings() {
    if (!_danmakuSettingsOpen) return;
    setState(() => _danmakuSettingsOpen = false);
    _scheduleHide();
  }

  void _toggleDanmaku() {
    // 图标本身就是状态，不再弹提示。
    final bool next = !ref.read(settingsControllerProvider).danmakuEnabled;
    ref.read(settingsControllerProvider.notifier).setDanmakuEnabled(next);
    if (!next) {
      // 关闭弹幕后输入框和设置入口一起收起，留在页面上也没意义。
      _danmakuFocus.unfocus();
      setState(() {
        _emojiOpen = false;
        _danmakuSettingsOpen = false;
        _composerFocused = false;
      });
    }
    _scheduleHide();
  }

  Future<bool> _sendDanmaku(String text) async {
    if (_sendingDanmaku) return false;
    if (!await _ensureBiliLoginForSend()) return false;
    if (!mounted) return false;

    final session = ref.read(biliSessionProvider);
    final String? csrf = session.csrfToken;
    if (!session.isLoggedIn || csrf == null || csrf.isEmpty) {
      if (mounted) showToast(context, '登录信息不完整，请重新登录 B 站账号');
      return false;
    }

    final LiveRoom room = _danmakuRoom;
    setState(() => _sendingDanmaku = true);
    try {
      // 返回值可能是服务端附带的无意义字符（例如 "f"），一律丢弃。
      await ref
          .read(biliLiveApiProvider)
          .sendDanmaku(
            roomId: room.roomId,
            text: text,
            cookie: session.cookieHeader ?? '',
            csrf: csrf,
          );
      if (!mounted) return true;
      _danmakuFocus.unfocus();
      // 发送成功一律静默：自己的弹幕会出现在弹幕区里。
      return true;
    } on Object catch (error) {
      if (mounted) showToast(context, '$error');
      return false;
    } finally {
      if (mounted) setState(() => _sendingDanmaku = false);
    }
  }

  /// 未登录时提示并打开 B 站官方登录页；登录成功后本次发送会继续。
  Future<bool> _ensureBiliLoginForSend() async {
    final session = ref.read(biliSessionProvider);
    if (session.isLoggedIn && (session.csrfToken?.isNotEmpty ?? false)) {
      return true;
    }

    final bool? go = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1A1E2A),
          title: const Text(
            '需要登录 B 站账号',
            style: TextStyle(color: Colors.white, fontSize: 16),
          ),
          content: const Text(
            '发送弹幕前需要先登录 B 站账号，登录成功后会自动继续发送。',
            style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消', style: TextStyle(color: Colors.white54)),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('去登录'),
            ),
          ],
        );
      },
    );
    if (go != true || !mounted) return false;

    final bool? ok = await showBiliLoginPage(context);
    if (ok != true || !mounted) return false;

    final updated = ref.read(biliSessionProvider);
    if (!updated.isLoggedIn || (updated.csrfToken?.isEmpty ?? true)) {
      if (mounted) showToast(context, '登录信息不完整，请重试');
      return false;
    }
    return true;
  }

  // ===== 表情面板 =====
  void _onComposerFocus() {
    if (!mounted) return;
    _hideTimer?.cancel();
    final bool focused = _danmakuFocus.hasFocus;
    if (_composerFocused != focused) {
      setState(() => _composerFocused = focused);
    }
    if (!focused) _scheduleHide();
  }

  void _toggleEmojiPanel() {
    if (_emojiOpen) {
      _closeEmojiPanel();
      return;
    }
    _hideTimer?.cancel();
    // 表情面板优先：先收起键盘，横屏才有空间展示。
    _danmakuFocus.unfocus();
    setState(() {
      _emojiOpen = true;
      _controlsVisible = true;
      _qualityOpen = false;
      _syncOpen = false;
      _danmakuSettingsOpen = false;
    });
    if (ref.read(biliAccountProvider).loggedIn && _emoticons.isEmpty) {
      unawaited(_loadEmoticons());
    }
  }

  void _closeEmojiPanel() {
    if (!_emojiOpen) return;
    setState(() => _emojiOpen = false);
    _scheduleHide();
  }

  Future<void> _loadEmoticons() async {
    if (_emojiLoading) return;
    final LiveRoom room = _danmakuRoom;
    setState(() {
      _emojiLoading = true;
      _emojiError = null;
    });
    try {
      final List<LiveEmoticon> list = await ref
          .read(biliLiveApiProvider)
          .fetchEmoticons(
            roomId: room.roomId,
            cookie: ref.read(biliSessionProvider).cookieHeader,
          );
      if (!mounted) return;
      setState(() {
        _emoticons = list;
        _emojiLoading = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _emojiLoading = false;
        _emojiError = '$error';
      });
    }
  }

  Future<void> _loginForEmoji() async {
    final bool ok = await _ensureBiliLoginForSend();
    if (!ok || !mounted) return;
    await _loadEmoticons();
  }

  /// 表情以 `[dog]` 这种文本插入输入框，和官方发送格式一致。
  void _pickEmoticon(LiveEmoticon emoticon) {
    final String text = _danmakuText.text;
    if (text.length + emoticon.emoji.length > 20) return;
    final int offset = _danmakuText.selection.baseOffset;
    final int at = offset < 0 || offset > text.length ? text.length : offset;
    _danmakuText.value = TextEditingValue(
      text: text.replaceRange(at, at, emoticon.emoji),
      selection: TextSelection.collapsed(offset: at + emoticon.emoji.length),
    );
  }

  /// 表情面板：贴在输入框上方，点空白关闭。
  Widget _buildEmojiOverlay(BuildContext context) {
    final EdgeInsets padding = MediaQuery.viewPaddingOf(context);
    final double bottom = (_landscape ? 50 : 66) + padding.bottom;
    final double panelHeight = _landscape ? 152 : 218;
    return Stack(
      children: <Widget>[
        // 只挡住面板上方：输入框本身仍然可以点。
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          bottom: bottom + panelHeight,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _closeEmojiPanel,
          ),
        ),
        Positioned(
          left: 12 + (_landscape ? padding.left : 0),
          right: 12 + (_landscape ? padding.right : 0),
          bottom: bottom,
          child: LiveEmoticonPanel(
            items: _emoticons,
            loading: _emojiLoading,
            error: _emojiError,
            loggedIn: ref.watch(biliAccountProvider).loggedIn,
            compact: _landscape,
            onLogin: _loginForEmoji,
            onRetry: _loadEmoticons,
            onPick: _pickEmoticon,
            onClose: _closeEmojiPanel,
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _hintTimer?.cancel();
    _danmakuFlush?.cancel();
    _danmakuFocus.removeListener(_onComposerFocus);
    _danmakuFocus.dispose();
    _danmakuText.dispose();
    unawaited(_danmakuFeed.close());
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
    final DanmakuClient? danmaku = _danmaku;
    _danmaku = null;
    if (danmaku != null) unawaited(danmaku.close());
    super.dispose();
  }

  @override
  // ===== 页面骨架 =====
  Widget build(BuildContext context) {
    return PopScope(
      canPop:
          !_landscape &&
          !_qualityOpen &&
          !_syncOpen &&
          !_danmakuSettingsOpen &&
          !_emojiOpen,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop) return;
        // 面板打开时返回键先收起面板；横屏时先退出全屏，都不是直接离开播放页。
        if (_composerFocused) {
          _danmakuFocus.unfocus();
          return;
        }
        if (_emojiOpen) {
          _closeEmojiPanel();
          return;
        }
        if (_danmakuSettingsOpen) {
          _closeDanmakuSettings();
          return;
        }
        if (_syncOpen) {
          _closeSyncPanel();
          return;
        }
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
            if (_syncOpen && _session != null)
              Positioned.fill(
                child: LiveSyncPanel(
                  session: _session!,
                  onClose: _closeSyncPanel,
                  onRestart: () {
                    _closeSyncPanel();
                    _start();
                  },
                ),
              ),
            if (_qualityOpen)
              Positioned.fill(
                child: LiveQualityPanelOverlay(
                  options: _session?.qualities.value ?? const <LiveQuality>[],
                  currentQn: _session?.currentQn.value ?? _qn,
                  loggedIn: ref.watch(biliAccountProvider).loggedIn,
                  onSelect: (int qn) {
                    _closeQualityPanel();
                    _switchQuality(qn);
                  },
                  onClose: _closeQualityPanel,
                ),
              ),
            if (_emojiOpen) Positioned.fill(child: _buildEmojiOverlay(context)),
            if (_danmakuSettingsOpen)
              Positioned.fill(
                // 只让面板订阅设置，拖动滑块时不会重建视频层。
                child: Consumer(
                  builder:
                      (BuildContext context, WidgetRef ref, Widget? child) {
                        final AppSettings settings = ref.watch(
                          settingsControllerProvider,
                        );
                        final SettingsController controller = ref.read(
                          settingsControllerProvider.notifier,
                        );
                        return LiveDanmakuSettingsPanel(
                          area: settings.danmakuArea,
                          opacity: settings.danmakuOpacity,
                          fontScale: settings.danmakuFontScale,
                          speed: settings.danmakuSpeed,
                          onAreaChanged: controller.setDanmakuArea,
                          onOpacityChanged: controller.setDanmakuOpacity,
                          onFontScaleChanged: controller.setDanmakuFontScale,
                          onSpeedChanged: controller.setDanmakuSpeed,
                          onReset: controller.resetDanmakuStyle,
                          onClose: _closeDanmakuSettings,
                        );
                      },
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ===== 竖屏：信息条 / 画面（底部控制条）/ 弹幕 / 输入栏 =====
  Widget _buildPortrait(BuildContext context) {
    final DualLiveSession? session = _session;
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
          child: LiveConsoleHeader(
            picture: widget.args.picture,
            voice: widget.args.voice,
            hint: _error ?? _voiceWarning ?? (_starting ? _status : ''),
            starting: _starting,
            usingVoice: _usingVoice,
            hasVoice: session?.hasVoice ?? false,
            onBack: () => context.canPop() ? context.pop() : context.go('/'),
            onOfficialSound: () => _switchSound(official: true),
            onCommentatorSound: () => _switchSound(official: false),
          ),
        ),
        _buildVideoStage(context),
        Expanded(
          child: LiveDanmakuPanel(
            source: widget.args.danmaku,
            status: _danmakuStatus,
            messages: _danmakuMessages,
            roomName: _danmakuRoomName,
            error: _danmakuError,
          ),
        ),
        Consumer(
          builder: (BuildContext context, WidgetRef ref, Widget? child) {
            final bool enabled = ref.watch(
              settingsControllerProvider.select(
                (AppSettings settings) => settings.danmakuEnabled,
              ),
            );
            if (!enabled) {
              // 关掉弹幕后不给输入框，但留一个入口方便重新打开。
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _toggleDanmaku,
                child: Container(
                  height: 38,
                  margin: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(19),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                  child: Row(
                    children: <Widget>[
                      const Icon(
                        Icons.subtitles_off_rounded,
                        size: 15,
                        color: Colors.white38,
                      ),
                      const SizedBox(width: 7),
                      const Text(
                        '弹幕已关闭',
                        style: TextStyle(color: Colors.white38, fontSize: 12),
                      ),
                      const Spacer(),
                      const Text(
                        '开启',
                        style: TextStyle(
                          color: AppColors.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }
            return LiveDanmakuInputBar(
              enabled: widget.args.danmaku != DanmakuSource.off,
              sending: _sendingDanmaku,
              onSend: _sendDanmaku,
              onBlocked: () => showToast(context, '先在首页选择弹幕来源'),
              onEmoji: _toggleEmojiPanel,
              controller: _danmakuText,
              focusNode: _danmakuFocus,
            );
          },
        ),
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
        // 飘屏在画面之上、控制层之下，不拦截点击。
        Consumer(
          builder: (BuildContext context, WidgetRef ref, Widget? child) {
            final AppSettings settings = ref.watch(settingsControllerProvider);
            return LiveDanmakuOverlay(
              messages: _danmakuFeed.stream,
              paused: _paused,
              enabled: settings.danmakuEnabled,
              area: settings.danmakuArea,
              opacity: settings.danmakuOpacity,
              fontScale: settings.danmakuFontScale,
              speed: settings.danmakuSpeed,
            );
          },
        ),
        if (_controlsVisible)
          Consumer(
            builder: (BuildContext context, WidgetRef ref, Widget? child) {
              final AppSettings settings = ref.watch(
                settingsControllerProvider,
              );
              return _buildOverlay(
                context,
                danmakuEnabled: settings.danmakuEnabled,
              );
            },
          ),
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
  ///
  /// 底部工具条放在亮度/音量手势层之外，避免与纵向手势抢事件。
  Widget _buildVideoStage(BuildContext context) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _toggleControls,
            onVerticalDragStart: _onVerticalStart,
            onVerticalDragUpdate: _onVerticalUpdate,
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                ColoredBox(
                  color: Colors.black,
                  child: _buildVideo(BoxFit.contain),
                ),
                _buildGestureHint(),
              ],
            ),
          ),
          if (_controlsVisible)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _buildPortraitOverlay(),
            ),
        ],
      ),
    );
  }

  /// 竖屏画面底部：暂停与横屏。
  Widget _buildPortraitOverlay() {
    return Align(
      alignment: Alignment.bottomCenter,
      child: LivePortraitControlBar(
        paused: _paused,
        ready: _controller != null,
        onTogglePause: _togglePause,
        onToggleFullscreen: _toggleOrientation,
      ),
    );
  }

  /// 画面控制层：具体摆放交给 [LiveControlOverlay]，这里只接线。
  Widget _buildOverlay(BuildContext context, {required bool danmakuEnabled}) {
    final DualLiveSession? session = _session;
    return LiveControlOverlay(
      picture: widget.args.picture,
      voice: widget.args.voice,
      hint: _error ?? _voiceWarning ?? (_starting ? _status : ''),
      starting: _starting,
      onBack: () {
        if (_landscape) {
          _toggleOrientation();
          return;
        }
        if (context.canPop()) {
          context.pop();
        } else {
          context.go('/');
        }
      },
      landscape: _landscape,
      paused: _paused,
      usingVoice: _usingVoice,
      hasVoice: session?.hasVoice ?? false,
      ready: session != null && _controller != null,
      refreshing: _refreshing,
      hasQuality:
          (session?.qualities.value ?? const <LiveQuality>[]).isNotEmpty,
      qualityLabel: LiveQuality.labelOf(_qn),
      onTogglePause: _togglePause,
      onRefresh: _refreshPicture,
      danmakuEnabled: danmakuEnabled,
      onToggleDanmaku: _toggleDanmaku,
      onDanmakuSettings: _openDanmakuSettings,
      onSync: _openSyncPanel,
      composer: danmakuEnabled
          ? LiveDanmakuInputBar(
              compact: true,
              enabled: widget.args.danmaku != DanmakuSource.off,
              sending: _sendingDanmaku,
              onSend: _sendDanmaku,
              onBlocked: () => showToast(context, '先在首页选择弹幕来源'),
              onEmoji: _toggleEmojiPanel,
              controller: _danmakuText,
              focusNode: _danmakuFocus,
            )
          : null,
      composerExpanded: _landscape && (_composerFocused || _emojiOpen),
      onCollapseComposer: _danmakuFocus.unfocus,
      onQuality: _openQualityPanel,
      onToggleFullscreen: _toggleOrientation,
      onOfficialSound: () => _switchSound(official: true),
      onCommentatorSound: () => _switchSound(official: false),
    );
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
}
