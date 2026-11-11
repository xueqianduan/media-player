// -------------------------------------------------------------------------
// 功能：双路直播播放页
//
// 主要内容：
// - 画面挂载与首帧占位
// - 声音切换、暂停、同步调节
// - 连接状态与错误提示
// -------------------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/ui_kit.dart';
import '../application/network_controller.dart';
import '../data/dual_live_session.dart';
import '../domain/live_models.dart';

/// 播放双路直播所需的选择。
class LivePlayArgs {
  const LivePlayArgs({required this.picture, this.voice});

  final LiveRoom picture;
  final LiveRoom? voice;
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

  @override
  // ===== 生命周期与启动 =====
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    final DualLiveSession? previous = _session;
    if (previous != null) {
      previous.status.removeListener(_onStatus);
      previous.usingVoice.removeListener(_onSoundChanged);
      previous.paused.removeListener(_onPausedChanged);
      await previous.close();
    }

    if (!mounted) return;
    setState(() {
      _session = null;
      _controller = null;
      _starting = true;
      _error = null;
      _voiceWarning = null;
      _status = '正在连接画面源…';
    });

    final DualLiveSession session = DualLiveSession(
      api: ref.read(biliLiveApiProvider),
      onVideo: (VideoController? controller) {
        if (mounted) setState(() => _controller = controller);
      },
    );
    session.status.addListener(_onStatus);
    session.usingVoice.addListener(_onSoundChanged);
    session.paused.addListener(_onPausedChanged);
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
      if (mounted) setState(() => _starting = false);
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

  // ===== 播放控制：暂停 / 声音 / 同步 =====
  Future<void> _togglePause() async {
    final DualLiveSession? session = _session;
    if (session == null) return;
    try {
      await session.setPaused(!_paused);
    } on Object catch (error) {
      if (mounted) showToast(context, '$error');
    }
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
    final DualLiveSession? session = _session;
    if (session != null) {
      session.status.removeListener(_onStatus);
      session.usingVoice.removeListener(_onSoundChanged);
      session.paused.removeListener(_onPausedChanged);
      session.close();
    }
    super.dispose();
  }

  @override
  // ===== 页面骨架 =====
  Widget build(BuildContext context) {
    final bool landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          if (_controller != null)
            Video(
              controller: _controller!,
              controls: NoVideoControls,
              fit: BoxFit.contain,
              wakelock: true,
            )
          else
            _buildPlaceholder(),
          SafeArea(
            child: Column(
              children: <Widget>[
                _buildTopBar(context, landscape),
                const Spacer(),
                if (_controller != null) _buildControls(context, landscape),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Center(
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
    );
  }

  Widget _buildTopBar(BuildContext context, bool landscape) {
    return Padding(
      padding: EdgeInsets.fromLTRB(8, landscape ? 4 : 8, 12, 4),
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
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white54,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildControls(BuildContext context, bool landscape) {
    final bool hasVoice = _session?.hasVoice ?? false;
    return Container(
      margin: EdgeInsets.fromLTRB(12, 0, 12, landscape ? 8 : 14),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: const Color(0xF20B0D14),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              _RoundButton(
                icon: _paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                onTap: _togglePause,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Row(
                  children: <Widget>[
                    _SoundChip(
                      label: '赛事原声',
                      selected: !_usingVoice,
                      onTap: () => _switchSound(official: true),
                    ),
                    const SizedBox(width: 8),
                    _SoundChip(
                      label: '解说声音',
                      selected: _usingVoice,
                      enabled: hasVoice,
                      onTap: () => _switchSound(official: false),
                    ),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: _showSyncSheet,
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white70,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                icon: const Icon(Icons.tune_rounded, size: 17),
                label: const Text('同步', style: TextStyle(fontSize: 12.5)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              _voiceWarning ?? _status,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.45),
                fontSize: 10.5,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ===== 面板与小组件 =====
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

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: Colors.white, size: 22),
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
