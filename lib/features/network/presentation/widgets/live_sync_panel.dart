// -------------------------------------------------------------------------
// 功能：双路同步面板（右侧滑出）
//
// 主要内容：
// - 显示画面 / 声音两路的累计延迟
// - 画面慢 0.5 秒、声音慢 0.5 秒、重新连接并从零校准
// - 没有声音源时给出明确提示，而不是静默不可用
// -------------------------------------------------------------------------

import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/ui_kit.dart';
import '../../data/dual_live_session.dart';
import 'live_side_panel.dart';

/// 同步调节侧栏。
class LiveSyncPanel extends StatefulWidget {
  const LiveSyncPanel({
    super.key,
    required this.session,
    required this.onClose,
    required this.onRestart,
  });

  final DualLiveSession session;
  final VoidCallback onClose;
  final VoidCallback onRestart;

  @override
  State<LiveSyncPanel> createState() => _LiveSyncPanelState();
}

class _LiveSyncPanelState extends State<LiveSyncPanel> {
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
    final bool hasVoice = session.hasVoice;

    return LiveSidePanel(
      onClose: widget.onClose,
      widthFactor: 0.8,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 12, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Expanded(
                  child: Text(
                    '同步调节',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: widget.onClose,
                  icon: const Icon(
                    Icons.close_rounded,
                    color: Colors.white54,
                    size: 20,
                  ),
                ),
              ],
            ),
            Text(
              '画面延迟 ${(session.pictureDelay.inMilliseconds / 1000).toStringAsFixed(1)}s'
              ' · 声音延迟 ${(session.voiceDelay.inMilliseconds / 1000).toStringAsFixed(1)}s',
              style: const TextStyle(color: Colors.white54, fontSize: 11.5),
            ),
            if (!hasVoice) ...<Widget>[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  '还没有声音源。回到网络首页选择「声音来源」后，才能校准两路延迟。',
                  style: TextStyle(
                    color: Colors.white60,
                    fontSize: 11,
                    height: 1.5,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 8),
            _SyncAction(
              icon: Icons.ondemand_video_rounded,
              title: '画面慢 0.5 秒',
              subtitle: '声音比画面晚时使用',
              enabled: !_busy && hasVoice,
              onTap: () => _delay(picture: true),
            ),
            _SyncAction(
              icon: Icons.graphic_eq_rounded,
              title: '声音慢 0.5 秒',
              subtitle: '画面比声音晚时使用',
              enabled: !_busy && hasVoice,
              onTap: () => _delay(picture: false),
            ),
            _SyncAction(
              icon: Icons.restart_alt_rounded,
              title: '重新连接并从零校准',
              subtitle: '延迟重置，两路重新建立连接',
              enabled: !_busy,
              onTap: widget.onRestart,
            ),
            if (_busy) ...<Widget>[
              const SizedBox(height: 10),
              const Row(
                children: <Widget>[
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.6,
                      color: Colors.white54,
                    ),
                  ),
                  SizedBox(width: 8),
                  Text(
                    '正在校准…',
                    style: TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 6),
            const Text(
              '同步只在本次播放内有效，重连或切换直播间后会重置。',
              style: TextStyle(
                color: Colors.white30,
                fontSize: 10.5,
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
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          children: <Widget>[
            Icon(
              icon,
              size: 18,
              color: enabled ? AppColors.primary : Colors.white24,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    title,
                    style: TextStyle(
                      color: enabled ? Colors.white : Colors.white38,
                      fontSize: 12.5,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    subtitle,
                    maxLines: 2,
                    style: const TextStyle(
                      color: Colors.white30,
                      fontSize: 10.5,
                      height: 1.4,
                    ),
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
